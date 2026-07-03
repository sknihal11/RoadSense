import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'navigation_provider.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/loading_indicator.dart';
import '../../../widgets/movable_camera_preview.dart';
import '../../road_monitoring/presentation/road_monitoring_provider.dart';

class NavigationScreen extends ConsumerStatefulWidget {
  final String destination;

  const NavigationScreen({
    Key? key,
    required this.destination,
  }) : super(key: key);

  @override
  ConsumerState<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends ConsumerState<NavigationScreen> {
  final MapController _mapController = MapController();

  static const List<LatLng> _potholeLocations = [
    LatLng(17.8170, 83.3480), 
    LatLng(17.9150, 83.3970), 
    LatLng(18.0120, 83.4140), 
    LatLng(17.7550, 83.3275), 
    LatLng(17.9305, 83.4280), 
    LatLng(17.8255, 83.3548), 
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(navigationNotifierProvider.notifier).calculateRoutes(widget.destination);
    });
  }

  void _centerMapOnLocation(double latitude, double longitude, {double zoom = 14.5}) {
    _mapController.move(LatLng(latitude, longitude), zoom);
  }

  @override
  Widget build(final BuildContext context) {
    final state = ref.watch(navigationNotifierProvider);
    final monitoringState = ref.watch(roadMonitoringProvider);
    final theme = Theme.of(context);

    // Listen for coordinate updates in guidance mode and center the map camera automatically
    ref.listen<NavigationState>(navigationNotifierProvider, (previous, next) {
      if (next.isNavigating && next.currentSimulatedLocation != null) {
        final loc = next.currentSimulatedLocation!;
        _mapController.move(LatLng(loc.latitude, loc.longitude), 16.5);
        _mapController.rotate(-loc.heading);
      } else if (previous?.isNavigating == true && !next.isNavigating) {
        _mapController.rotate(0.0);
      }
    });

    if (state.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Calculating Routes...')),
        body: const LoadingIndicator(message: 'Analyzing safest paths and road anomalies...'),
      );
    }

    if (state.error.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Navigation Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(state.error, style: TextStyle(color: theme.colorScheme.error)),
          ),
        ),
      );
    }

    // Coordinates mapping
    final route = state.selectedRoute;
    final currentLoc = state.currentSimulatedLocation;

    // Build markers
    final List<Marker> mapMarkers = [];
    if (route != null && route.coordinates.isNotEmpty) {
      final startCoords = route.coordinates.first;
      final endCoords = route.coordinates.last;
      
      mapMarkers.add(
        Marker(
          point: LatLng(startCoords.latitude, startCoords.longitude),
          width: 40,
          height: 40,
          child: const Icon(
            Icons.location_on,
            color: Colors.green,
            size: 36,
          ),
        ),
      );
      
      mapMarkers.add(
        Marker(
          point: LatLng(endCoords.latitude, endCoords.longitude),
          width: 40,
          height: 40,
          child: const Icon(
            Icons.location_on,
            color: Colors.red,
            size: 36,
          ),
        ),
      );
    }

    // Add known pothole overlay markers
    for (final loc in _potholeLocations) {
      mapMarkers.add(
        Marker(
          point: loc,
          width: 32,
          height: 32,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 1),
                )
              ],
            ),
            child: const Icon(
              Icons.warning_rounded,
              color: Colors.orange,
              size: 22,
            ),
          ),
        ),
      );
    }

    if (currentLoc != null) {
      mapMarkers.add(
        Marker(
          point: LatLng(currentLoc.latitude, currentLoc.longitude),
          width: 44,
          height: 44,
          child: Transform.rotate(
            angle: (currentLoc.heading * pi / 180.0),
            child: Icon(
              Icons.navigation_rounded,
              color: theme.colorScheme.primary,
              size: 32,
            ),
          ),
        ),
      );
    }

    // Build polylines
    final List<Polyline> mapPolylines = [];
    if (route != null) {
      mapPolylines.add(
        Polyline(
          points: route.coordinates.map((c) => LatLng(c.latitude, c.longitude)).toList(),
          color: theme.colorScheme.primary,
          strokeWidth: 6,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(state.isNavigating ? 'Driving to Destination' : 'Select Route'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (state.isNavigating) {
              ref.read(navigationNotifierProvider.notifier).stopGuidance();
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: Stack(
        children: [
          // 1. OpenStreetMap View as Background
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: currentLoc != null 
                  ? LatLng(currentLoc.latitude, currentLoc.longitude)
                  : const LatLng(17.89, 83.25),
              initialZoom: 11.5,
              minZoom: 9.0,
              maxZoom: 18.0,
              cameraConstraint: CameraConstraint.contain(
                bounds: LatLngBounds(
                  const LatLng(17.55, 83.00),
                  const LatLng(18.25, 83.60),
                ),
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.roadsense_ai',
              ),
              PolylineLayer(
                polylines: mapPolylines,
              ),
              MarkerLayer(
                markers: mapMarkers,
              ),
            ],
          ),

          // 2. Map Overlays (HUD / Cards)
          if (state.isNavigating)
            _buildGuidanceOverlay(context, state, monitoringState)
          else
            _buildRouteSelectionOverlay(context, state),

          // 3. Floating Action Button for Centering Map Location
          Positioned(
            right: 16,
            bottom: state.isNavigating ? 180 : 280, // Dynamic positioning to clear sheets
            child: FloatingActionButton(
              heroTag: 'center_location_fab',
              onPressed: () {
                if (currentLoc != null) {
                  _centerMapOnLocation(currentLoc.latitude, currentLoc.longitude, zoom: 15.5);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Centering camera on current position'),
                      duration: Duration(milliseconds: 1000),
                    ),
                  );
                }
              },
              backgroundColor: theme.colorScheme.surface,
              foregroundColor: theme.colorScheme.primary,
              child: const Icon(Icons.my_location),
            ),
          ),

          // 4. Floating Action Button for Toggling Road Monitoring Camera
          Positioned(
            right: 16,
            bottom: state.isNavigating ? 250 : 350, // Stacked above centering FAB
            child: FloatingActionButton(
              heroTag: 'toggle_monitoring_fab',
              onPressed: () {
                ref.read(roadMonitoringProvider.notifier).toggleMonitoring();
                final isMonitoring = ref.read(roadMonitoringProvider).isMonitoring;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isMonitoring 
                        ? 'Road monitoring active. Drag camera overlay to reposition.' 
                        : 'Road monitoring stopped. Camera disposed.'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              backgroundColor: monitoringState.isMonitoring
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.surface,
              foregroundColor: monitoringState.isMonitoring
                  ? Colors.black87
                  : theme.colorScheme.onSurfaceVariant,
              child: Icon(
                monitoringState.isMonitoring
                    ? Icons.videocam
                    : Icons.videocam_off,
              ),
            ),
          ),

          // 5. Movable Camera PiP Overlay
          if (monitoringState.isMonitoring)
            const MovableCameraPreview(),
        ],
      ),
    );
  }

  Widget _buildRouteSelectionOverlay(BuildContext context, NavigationState state) {
    final theme = Theme.of(context);
    final notifier = ref.read(navigationNotifierProvider.notifier);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardTheme.color ?? theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 15,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Destination details
            Row(
              children: [
                Icon(Icons.location_on, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Destination Address',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      Text(
                        widget.destination,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              'Select Safe Route',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // Routes list
            ...state.routes.map((route) {
              final isSelected = state.selectedRoute?.routeId == route.routeId;
              return GestureDetector(
                onTap: () {
                  notifier.selectRoute(route);
                  if (route.coordinates.isNotEmpty) {
                    _centerMapOnLocation(route.coordinates.first.latitude, route.coordinates.first.longitude);
                  }
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? theme.colorScheme.primary.withOpacity(0.08) 
                        : theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected 
                          ? theme.colorScheme.primary 
                          : theme.colorScheme.outlineVariant,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              route.routeName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isSelected ? theme.colorScheme.primary : null,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  '${route.distanceInKm.toStringAsFixed(1)} km  •  ${route.durationInMinutes} mins',
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: route.hazardCount == 0 
                                        ? Colors.green.withOpacity(0.15) 
                                        : Colors.orange.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    route.hazardCount == 0 
                                        ? 'Safe (0 Hazards)' 
                                        : '${route.hazardCount} Potholes',
                                    style: TextStyle(
                                      color: route.hazardCount == 0 ? Colors.green : Colors.orange,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    text: 'Simulate Trip',
                    icon: Icons.alt_route_rounded,
                    onPressed: () => notifier.startGuidance(simulate: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CustomButton(
                    text: 'Real GPS Drive',
                    icon: Icons.navigation_rounded,
                    onPressed: () => notifier.startGuidance(simulate: false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuidanceOverlay(
    BuildContext context,
    NavigationState state,
    RoadMonitoringState monitoringState,
  ) {
    final theme = Theme.of(context);
    final notifier = ref.read(navigationNotifierProvider.notifier);
    final currentStep = state.currentInstruction;

    final IconData turnIcon;
    if (currentStep.toLowerCase().contains('left')) {
      turnIcon = Icons.turn_left_rounded;
    } else if (currentStep.toLowerCase().contains('right')) {
      turnIcon = Icons.turn_right_rounded;
    } else {
      turnIcon = Icons.navigation_rounded;
    }

    return Stack(
      children: [
        // Top Floating Directions card
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[800],
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    Icon(turnIcon, color: Colors.white, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        currentStep,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (state.upcomingHazardAlert != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[800],
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_rounded, color: Colors.white, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.upcomingHazardAlert!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ]
            ],
          ),
        ),

        // Bottom Navigation metrics controls card
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardTheme.color ?? theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 15,
                  offset: const Offset(0, -2),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.currentRoadName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              '${(state.remainingDurationInSeconds / 60.0).round()} mins',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '•',
                              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              state.remainingDistanceInMeters >= 1000.0
                                  ? '${(state.remainingDistanceInMeters / 1000.0).toStringAsFixed(1)} km'
                                  : '${state.remainingDistanceInMeters.round()} m',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Potholes Logged',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        Text(
                          '${monitoringState.detectedPotholes}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                CustomButton(
                  text: 'End Trip',
                  backgroundColor: theme.colorScheme.error,
                  textColor: Colors.white,
                  onPressed: () => notifier.stopGuidance(),
                ),
              ],
            ),
          ),
        )
      ],
    );
  }
}
