import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../domain/models/navigation_route_model.dart';
import '../../navigation/data/repositories/navigation_repository_impl.dart';
import '../../../core/services/geolocator_service.dart';

class NavigationState {
  final List<NavigationRouteModel> routes;
  final NavigationRouteModel? selectedRoute;
  final bool isLoading;
  final bool isNavigating;
  final int currentStepIndex;
  final Coordinate? currentSimulatedLocation;
  final String? upcomingHazardAlert;
  final String error;

  // Real-world dynamic navigation metrics
  final double remainingDistanceInMeters;
  final int remainingDurationInSeconds;
  final String currentRoadName;
  final String currentInstruction;
  final double nextTurnDistance;

  NavigationState({
    this.routes = const [],
    this.selectedRoute,
    this.isLoading = false,
    this.isNavigating = false,
    this.currentStepIndex = 0,
    this.currentSimulatedLocation,
    this.upcomingHazardAlert,
    this.error = '',
    this.remainingDistanceInMeters = 0.0,
    this.remainingDurationInSeconds = 0,
    this.currentRoadName = 'NH 16',
    this.currentInstruction = 'Proceed to route',
    this.nextTurnDistance = 0.0,
  });

  NavigationState copyWith({
    List<NavigationRouteModel>? routes,
    NavigationRouteModel? selectedRoute,
    bool? isLoading,
    bool? isNavigating,
    int? currentStepIndex,
    Coordinate? currentSimulatedLocation,
    String? upcomingHazardAlert,
    String? error,
    double? remainingDistanceInMeters,
    int? remainingDurationInSeconds,
    String? currentRoadName,
    String? currentInstruction,
    double? nextTurnDistance,
  }) {
    return NavigationState(
      routes: routes ?? this.routes,
      selectedRoute: selectedRoute ?? this.selectedRoute,
      isLoading: isLoading ?? this.isLoading,
      isNavigating: isNavigating ?? this.isNavigating,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      currentSimulatedLocation: currentSimulatedLocation ?? this.currentSimulatedLocation,
      upcomingHazardAlert: upcomingHazardAlert ?? this.upcomingHazardAlert,
      error: error ?? this.error,
      remainingDistanceInMeters: remainingDistanceInMeters ?? this.remainingDistanceInMeters,
      remainingDurationInSeconds: remainingDurationInSeconds ?? this.remainingDurationInSeconds,
      currentRoadName: currentRoadName ?? this.currentRoadName,
      currentInstruction: currentInstruction ?? this.currentInstruction,
      nextTurnDistance: nextTurnDistance ?? this.nextTurnDistance,
    );
  }
}

// GPS Jitter Filter using weighted moving averages (exponential smoothing)
class JitterFilter {
  double? _filteredLat;
  double? _filteredLng;
  double? _filteredHeading;
  final double alphaLocation = 0.75;
  final double alphaHeading = 0.35;

  Coordinate filter(double lat, double lng, double heading) {
    if (_filteredLat == null || _filteredLng == null) {
      _filteredLat = lat;
      _filteredLng = lng;
      _filteredHeading = heading;
      return Coordinate(lat, lng, heading: heading);
    }

    _filteredLat = alphaLocation * lat + (1 - alphaLocation) * _filteredLat!;
    _filteredLng = alphaLocation * lng + (1 - alphaLocation) * _filteredLng!;

    double newHeading = heading;
    if (_filteredHeading != null && (newHeading - _filteredHeading!).abs() > 180) {
      if (newHeading > _filteredHeading!) {
        _filteredHeading = _filteredHeading! + 360;
      } else {
        newHeading = newHeading + 360;
      }
    }
    _filteredHeading = alphaHeading * newHeading + (1 - alphaHeading) * _filteredHeading!;
    _filteredHeading = _filteredHeading! % 360;

    return Coordinate(_filteredLat!, _filteredLng!, heading: _filteredHeading!);
  }

  void reset() {
    _filteredLat = null;
    _filteredLng = null;
    _filteredHeading = null;
  }
}

class NavigationNotifier extends StateNotifier<NavigationState> {
  final Ref _ref;
  StreamSubscription<Position>? _locationSubscription;
  final JitterFilter _jitterFilter = JitterFilter();
  bool _isRerouting = false;

  NavigationNotifier(this._ref) : super(NavigationState());

  Future<void> calculateRoutes(String destination) async {
    state = state.copyWith(isLoading: true, error: '');
    try {
      final repository = _ref.read(navigationRepositoryProvider);
      
      // 1. Fetch user's live GPS coordinates via GeolocatorService
      double startLat = 18.0528;
      double startLng = 83.4198;
      try {
        final geolocator = _ref.read(geolocatorServiceProvider);
        final position = await geolocator.getCurrentLocation();
        startLat = position.latitude;
        startLng = position.longitude;
      } catch (_) {}

      // 2. Resolve destination coordinates from geocoder cache
      Coordinate? endCoord = await repository.resolvePlaceCoordinate(destination);
      endCoord ??= const Coordinate(18.1124, 83.3989); // Default Vizianagaram Fort

      final routes = await repository.getRoutes(
        startLatitude: startLat,
        startLongitude: startLng,
        endLatitude: endCoord.latitude,
        endLongitude: endCoord.longitude,
      );
      
      final defaultRoute = routes.isNotEmpty ? routes[0] : null;
      state = state.copyWith(
        routes: routes,
        selectedRoute: defaultRoute,
        currentSimulatedLocation: defaultRoute?.coordinates.isNotEmpty == true 
            ? defaultRoute!.coordinates[0] 
            : Coordinate(startLat, startLng),
        isLoading: false,
        remainingDistanceInMeters: defaultRoute?.distanceInMeters ?? 0.0,
        remainingDurationInSeconds: defaultRoute?.durationInSeconds ?? 0,
        currentRoadName: defaultRoute?.steps.isNotEmpty == true ? defaultRoute!.steps[0].roadName : 'NH 16',
        currentInstruction: defaultRoute?.steps.isNotEmpty == true ? defaultRoute!.steps[0].instruction : 'Proceed to route',
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to find route: ${e.toString()}',
      );
    }
  }

  void selectRoute(NavigationRouteModel route) {
    state = state.copyWith(
      selectedRoute: route,
      currentSimulatedLocation: route.coordinates.isNotEmpty 
          ? route.coordinates[0] 
          : const Coordinate(17.7290, 83.3087),
      remainingDistanceInMeters: route.distanceInMeters,
      remainingDurationInSeconds: route.durationInSeconds,
      currentRoadName: route.steps.isNotEmpty ? route.steps[0].roadName : 'NH 16',
      currentInstruction: route.steps.isNotEmpty ? route.steps[0].instruction : 'Proceed to route',
    );
  }

  void startGuidance({bool simulate = false}) {
    if (state.selectedRoute == null) return;
    
    state = state.copyWith(
      isNavigating: true,
      currentStepIndex: 0,
      currentSimulatedLocation: state.selectedRoute!.coordinates.isNotEmpty 
          ? state.selectedRoute!.coordinates[0] 
          : const Coordinate(17.7290, 83.3087),
    );

    _jitterFilter.reset();

    if (simulate) {
      _simulateStepTransitions();
    } else {
      // Real-time GPS location streaming with bestForNavigation accuracy
      _locationSubscription?.cancel();
      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 3, 
        ),
      ).listen(
        (position) {
          final filtered = _jitterFilter.filter(position.latitude, position.longitude, position.heading);
          _updateNavigationMetrics(filtered);
        },
        onError: (error) {
          debugPrint("GPS stream connection error: $error");
        },
      );
    }
  }

  void stopGuidance() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
    
    state = state.copyWith(
      isNavigating: false,
      upcomingHazardAlert: null,
      currentStepIndex: 0,
      currentSimulatedLocation: state.selectedRoute?.coordinates.isNotEmpty == true 
          ? state.selectedRoute!.coordinates[0] 
          : const Coordinate(17.7290, 83.3087),
    );
  }

  // Update navigation metrics dynamically along the active route
  void _updateNavigationMetrics(Coordinate currentLoc) {
    final route = state.selectedRoute;
    if (route == null || route.coordinates.isEmpty) return;

    // 1. Find closest coordinate on path
    int closestIndex = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < route.coordinates.length; i++) {
      final dist = _getDistanceInMeters(
        currentLoc.latitude, currentLoc.longitude,
        route.coordinates[i].latitude, route.coordinates[i].longitude
      );
      if (dist < minDistance) {
        minDistance = dist;
        closestIndex = i;
      }
    }

    // 2. Devation detection (re-calculate if > 50 meters off-route)
    if (minDistance > 50.0 && !_isRerouting) {
      _isRerouting = true;
      debugPrint("Deviated by $minDistance meters. Initiating automatic background rerouting...");
      calculateRoutesQuietly(currentLoc.latitude, currentLoc.longitude, route.coordinates.last);
      return;
    }

    // 3. Estimate remaining distance & time
    double remainingDistance = 0.0;
    for (int i = closestIndex; i < route.coordinates.length - 1; i++) {
      remainingDistance += _getDistanceInMeters(
        route.coordinates[i].latitude, route.coordinates[i].longitude,
        route.coordinates[i + 1].latitude, route.coordinates[i + 1].longitude
      );
    }
    remainingDistance += minDistance;

    final double factor = route.distanceInMeters > 0 ? remainingDistance / route.distanceInMeters : 0.0;
    final int remainingDuration = (route.durationInSeconds * factor).round();

    // 4. Map to turn steps
    int currentStepIdx = 0;
    double minStepDist = double.infinity;
    for (int i = 0; i < route.steps.length; i++) {
      final step = route.steps[i];
      final dist = _getDistanceInMeters(
        currentLoc.latitude, currentLoc.longitude,
        step.location.latitude, step.location.longitude
      );
      if (dist < minStepDist) {
        minStepDist = dist;
        currentStepIdx = i;
      }
    }

    final activeStep = route.steps[currentStepIdx];
    final nextStep = currentStepIdx + 1 < route.steps.length ? route.steps[currentStepIdx + 1] : null;

    double nextTurnDist = 0.0;
    if (nextStep != null) {
      nextTurnDist = _getDistanceInMeters(
        currentLoc.latitude, currentLoc.longitude,
        nextStep.location.latitude, nextStep.location.longitude
      );
    }

    double activeHeading = currentLoc.heading;
    if (activeHeading == 0.0 && closestIndex < route.coordinates.length - 1) {
      activeHeading = route.coordinates[closestIndex].heading;
    }

    // Check for pothole hazards within 200 meters of user along the route
    String? hazardAlert;
    for (final pothole in NavigationRepositoryImpl.knownPotholes) {
      final dist = _getDistanceInMeters(
        currentLoc.latitude, 
        currentLoc.longitude, 
        pothole.latitude, 
        pothole.longitude
      );
      if (dist <= 200.0) {
        // Verify if this pothole lies ahead along the route corridor (up to 200m ahead)
        bool alongUpcomingRoute = false;
        double cumDist = 0.0;
        for (int i = closestIndex; i < route.coordinates.length - 1; i++) {
          final stepDist = _getDistanceInMeters(
            route.coordinates[i].latitude, route.coordinates[i].longitude,
            route.coordinates[i + 1].latitude, route.coordinates[i + 1].longitude
          );
          cumDist += stepDist;
          if (cumDist > 200.0) break;
          
          final d = _getDistanceInMeters(
            route.coordinates[i].latitude, route.coordinates[i].longitude,
            pothole.latitude, pothole.longitude
          );
          if (d <= 25.0) {
            alongUpcomingRoute = true;
            break;
          }
        }
        
        if (alongUpcomingRoute) {
          hazardAlert = "Pothole hazard detected ahead (${dist.round()}m)! Drive carefully.";
          break;
        }
      }
    }

    state = state.copyWith(
      currentStepIndex: currentStepIdx,
      currentSimulatedLocation: Coordinate(currentLoc.latitude, currentLoc.longitude, heading: activeHeading),
      remainingDistanceInMeters: remainingDistance,
      remainingDurationInSeconds: remainingDuration,
      currentRoadName: activeStep.roadName,
      currentInstruction: nextStep != null ? nextStep.instruction : activeStep.instruction,
      nextTurnDistance: nextTurnDist,
      upcomingHazardAlert: hazardAlert,
    );
  }

  // Recalculates route quietly in the background without UI blocking indicators
  Future<void> calculateRoutesQuietly(double startLat, double startLng, Coordinate destination) async {
    try {
      final repository = _ref.read(navigationRepositoryProvider);
      final routes = await repository.getRoutes(
        startLatitude: startLat,
        startLongitude: startLng,
        endLatitude: destination.latitude,
        endLongitude: destination.longitude,
      );
      if (routes.isNotEmpty) {
        state = state.copyWith(
          routes: routes,
          selectedRoute: routes[0],
        );
      }
    } catch (e) {
      debugPrint("Auto-rerouting failed: $e");
    } finally {
      _isRerouting = false;
    }
  }

  // Smooth simulation loop along actual high-resolution OSRM road coordinates
  void _simulateStepTransitions() async {
    final route = state.selectedRoute;
    if (route == null || route.coordinates.isEmpty) return;

    int coordIdx = 0;
    while (state.isNavigating) {
      await Future.delayed(const Duration(seconds: 1)); 
      if (!state.isNavigating) break;

      if (coordIdx >= route.coordinates.length) {
        stopGuidance();
        break;
      }

      final rawCoord = route.coordinates[coordIdx];
      final filtered = _jitterFilter.filter(rawCoord.latitude, rawCoord.longitude, rawCoord.heading);

      _updateNavigationMetrics(filtered);
      
      // Advance by 3 points every second to simulate travel
      coordIdx += 3;
    }
  }

  double _getDistanceInMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }
}

final navigationNotifierProvider = StateNotifierProvider<NavigationNotifier, NavigationState>((ref) {
  return NavigationNotifier(ref);
});
