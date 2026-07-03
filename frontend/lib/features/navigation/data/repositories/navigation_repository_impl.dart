import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/api_service.dart';
import '../../domain/models/navigation_route_model.dart';
import '../../domain/repositories/navigation_repository.dart';

final navigationRepositoryProvider = Provider<NavigationRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return NavigationRepositoryImpl(apiService);
});

class NavigationRepositoryImpl implements NavigationRepository {
  final ApiService _apiService;

  NavigationRepositoryImpl(this._apiService);

  // Predefined list of known pothole hazards along the corridor
  static const List<Coordinate> knownPotholes = [
    Coordinate(17.8170, 83.3480), // Near Madhurawada PM Palem
    Coordinate(17.9150, 83.3970), // Near Anandapuram Bypass
    Coordinate(18.0120, 83.4140), // Near Jonnada
    Coordinate(17.7550, 83.3275), // Near Hanumanthawaka
    Coordinate(17.9305, 83.4280), // Near Tagarapuvalasa
    Coordinate(17.8255, 83.3548), // Near GITAM / Rushikonda
  ];

  static const Map<String, Coordinate> _offlinePlaceCoordinates = {
    'Vizianagaram Fort, Vizianagaram': Coordinate(18.1124, 83.3989),
    'Bhogapuram International Airport, Bhogapuram': Coordinate(17.9540, 83.4930),
    'GITAM University, Rushikonda, Visakhapatnam': Coordinate(17.8250, 83.3550),
    'RTC Complex, Visakhapatnam': Coordinate(17.7290, 83.3087),
    'Madhurawada Junction, Visakhapatnam': Coordinate(17.8176, 83.3488),
    'Anandapuram Bypass, Visakhapatnam': Coordinate(17.9157, 83.3980),
    'Tagarapuvalasa Bridge, Visakhapatnam': Coordinate(17.9310, 83.4289),
  };

  // Offline backup road node lists tracing actual road pathways

  static const List<Coordinate> _roadNodesVisakhapatnamToVizianagaram = [
    Coordinate(17.7290, 83.3087), 
    Coordinate(17.7410, 83.3190), 
    Coordinate(17.7555, 83.3285), 
    Coordinate(17.7680, 83.3320), 
    Coordinate(17.7850, 83.3420), 
    Coordinate(17.8010, 83.3440), 
    Coordinate(17.8176, 83.3488), 
    Coordinate(17.8310, 83.3505), 
    Coordinate(17.8420, 83.3520), 
    Coordinate(17.8730, 83.3760), 
    Coordinate(17.9010, 83.3890), 
    Coordinate(17.9157, 83.3980), 
    Coordinate(17.9550, 83.4070), 
    Coordinate(18.0125, 83.4150), 
    Coordinate(18.0510, 83.4120), 
    Coordinate(18.0850, 83.4110), 
    Coordinate(18.1124, 83.3989), 
  ];

  static const List<Coordinate> _roadNodesAnandapuramToBhogapuram = [
    Coordinate(17.9157, 83.3980), 
    Coordinate(17.9220, 83.4130), 
    Coordinate(17.9310, 83.4289), 
    Coordinate(17.9380, 83.4470), 
    Coordinate(17.9420, 83.4610), 
    Coordinate(17.9500, 83.4800), 
    Coordinate(17.9540, 83.4930), 
  ];

  static const List<Coordinate> _roadNodesVisakhapatnamToRushikonda = [
    Coordinate(17.7290, 83.3087), 
    Coordinate(17.7410, 83.3190), 
    Coordinate(17.7320, 83.3350), 
    Coordinate(17.7510, 83.3490), 
    Coordinate(17.7720, 83.3680), 
    Coordinate(17.7820, 83.3820), 
    Coordinate(17.8250, 83.3550), 
  ];

  @override
  Future<List<NavigationRouteModel>> getRoutes({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) async {
    // We fetch two routes from OSRM:
    // Route 1: Direct route
    // Route 2: Detour route via a waypoint (to offer an alternative that might have fewer potholes)
    
    final directUrl = "http://router.project-osrm.org/route/v1/driving/$startLongitude,$startLatitude;$endLongitude,$endLatitude?overview=full&geometries=geojson&steps=true";
    
    // Choose a waypoint detour dynamically based on end latitude to offer alternative
    Coordinate waypoint;
    final isVizianagaram = (endLatitude - 18.1124).abs() < 0.06;
    final isBhogapuram = (endLatitude - 17.9540).abs() < 0.06;
    if (isVizianagaram || isBhogapuram) {
      waypoint = const Coordinate(17.8250, 83.3550); // Route via Rushikonda Beach detour
    } else {
      waypoint = const Coordinate(17.9157, 83.3980); // Route via Anandapuram Bypass detour
    }
    
    final detourUrl = "http://router.project-osrm.org/route/v1/driving/$startLongitude,$startLatitude;${waypoint.longitude},${waypoint.latitude};$endLongitude,$endLatitude?overview=full&geometries=geojson&steps=true";

    try {
      final directData = await _fetchOSRMRoute(directUrl);
      final detourData = await _fetchOSRMRoute(detourUrl);

      final List<NavigationRouteModel> routes = [];

      if (directData != null && directData['routes'] != null && (directData['routes'] as List).isNotEmpty) {
        final routeJson = (directData['routes'] as List)[0] as Map<String, dynamic>;
        final directRoute = _parseOSRMRoute(routeJson, 'route_fastest', 'NH 16 (Fastest Direct)');
        routes.add(directRoute);
      }

      if (detourData != null && detourData['routes'] != null && (detourData['routes'] as List).isNotEmpty) {
        final routeJson = (detourData['routes'] as List)[0] as Map<String, dynamic>;
        final detourRoute = _parseOSRMRoute(routeJson, 'route_safest', 'Alternative Scenic Road (Safest)');
        routes.add(detourRoute);
      }

      if (routes.isEmpty) {
        throw Exception("No valid routes returned from OSRM");
      }

      // Sort routes using a safety-aware shortest path cost algorithm:
      // Weighting: Safety (hazardCount) = 50%, Duration = 30%, Distance = 20%
      routes.sort((a, b) {
        final double scoreA = (a.distanceInMeters * 0.2) + 
                            (a.durationInSeconds * 0.3) + 
                            (a.hazardCount * 250.0);
        final double scoreB = (b.distanceInMeters * 0.2) + 
                            (b.durationInSeconds * 0.3) + 
                            (b.hazardCount * 250.0);
        return scoreA.compareTo(scoreB);
      });

      return routes;

    } catch (e) {
      debugPrint("OSRM query failed. Falling back to offline-cached routing: $e");
      return _getOfflineFallbackRoutes(startLatitude, startLongitude, endLatitude, endLongitude);
    }
  }

  @override
  Future<List<String>> searchPlaces(String query) async {
    if (query.trim().isEmpty) return [];

    // Check SharedPreferences cache first
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('search_cache_$query');
      if (cachedJson != null) {
        final List<dynamic> decoded = jsonDecode(cachedJson);
        return decoded.cast<String>();
      }
    } catch (_) {}

    // Make network request to Nominatim API
    // Lock to Vizag-Vizianagaram corridor viewbox
    final dio = Dio();
    try {
      final response = await dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': query,
          'format': 'json',
          'limit': 5,
          'bounded': 1,
          'viewbox': '83.00,18.25,83.60,17.55', 
        },
        options: Options(
          headers: {'User-Agent': 'RoadSenseAiMobileApp/1.0.0 (contact@roadsense.ai)'},
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );

      if (response.statusCode == 200 && response.data is List) {
        final List<String> results = [];
        for (final item in response.data) {
          final displayName = item['display_name'] as String;
          results.add(displayName);
          
          final double lat = double.parse(item['lat'] as String);
          final double lon = double.parse(item['lon'] as String);
          
          _saveResolvedCoordinate(displayName, lat, lon);
        }

        // Cache the search query results
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('search_cache_$query', jsonEncode(results));
        } catch (_) {}

        return results;
      }
    } catch (e) {
      debugPrint("Nominatim query failed. Falling back to offline search index: $e");
      return _getOfflineSuggestions(query);
    }

    return _getOfflineSuggestions(query);
  }

  @override
  Future<Coordinate?> resolvePlaceCoordinate(String placeName) async {
    // 1. Check SharedPreferences first
    try {
      final prefs = await SharedPreferences.getInstance();
      final coordJson = prefs.getString('coord_$placeName');
      if (coordJson != null) {
        final decoded = jsonDecode(coordJson) as Map<String, dynamic>;
        return Coordinate(
          (decoded['lat'] as num).toDouble(),
          (decoded['lng'] as num).toDouble(),
        );
      }
    } catch (_) {}

    // 2. Fallback to offline place coordinates dictionary matching
    for (final entry in _offlinePlaceCoordinates.entries) {
      if (entry.key.toLowerCase().contains(placeName.toLowerCase()) ||
          placeName.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    
    // If not found in either, attempt a direct geocoding fetch
    try {
      final dio = Dio();
      final response = await dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': placeName,
          'format': 'json',
          'limit': 1,
        },
        options: Options(
          headers: {'User-Agent': 'RoadSenseAiMobileApp/1.0.0 (contact@roadsense.ai)'},
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
      if (response.statusCode == 200 && response.data is List && (response.data as List).isNotEmpty) {
        final item = (response.data as List)[0] as Map<String, dynamic>;
        final double lat = double.parse(item['lat'] as String);
        final double lon = double.parse(item['lon'] as String);
        final coord = Coordinate(lat, lon);
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('coord_$placeName', jsonEncode({'lat': lat, 'lng': lon}));
        return coord;
      }
    } catch (_) {}

    return null;
  }

  // Helper method to fetch route details from OSRM
  Future<Map<String, dynamic>?> _fetchOSRMRoute(String url) async {
    final dio = Dio();
    int retries = 3;
    while (retries > 0) {
      try {
        final response = await dio.get(
          url,
          options: Options(
            headers: {'User-Agent': 'RoadSenseAiMobileApp/1.0.0 (contact@roadsense.ai)'},
            sendTimeout: const Duration(seconds: 4),
            receiveTimeout: const Duration(seconds: 4),
          ),
        );
        if (response.statusCode == 200 && response.data != null) {
          return response.data as Map<String, dynamic>;
        }
      } catch (e) {
        retries--;
        if (retries == 0) {
          rethrow;
        }
        await Future.delayed(Duration(milliseconds: 500 * (3 - retries)));
      }
    }
    return null;
  }

  // Parse OSRM GeoJSON response
  NavigationRouteModel _parseOSRMRoute(Map<String, dynamic> json, String routeId, String defaultName) {
    final double distance = (json['distance'] as num).toDouble();
    final int duration = (json['duration'] as num).round();
    
    final geometry = json['geometry'] as Map<String, dynamic>;
    final coordinatesList = geometry['coordinates'] as List<dynamic>;
    
    final List<Coordinate> coordinates = [];
    for (int i = 0; i < coordinatesList.length; i++) {
      final point = coordinatesList[i] as List<dynamic>;
      final double lng = (point[0] as num).toDouble();
      final double lat = (point[1] as num).toDouble();
      
      double heading = 0.0;
      if (i > 0) {
        heading = _calculateHeading(coordinates[i - 1].latitude, coordinates[i - 1].longitude, lat, lng);
        if (i == 1) {
          coordinates[0] = Coordinate(coordinates[0].latitude, coordinates[0].longitude, heading: heading);
        }
      }
      coordinates.add(Coordinate(lat, lng, heading: heading));
    }

    final List<NavigationStepModel> steps = [];
    if (json['legs'] != null && (json['legs'] as List).isNotEmpty) {
      final leg = (json['legs'] as List)[0] as Map<String, dynamic>;
      if (leg['steps'] != null) {
        for (final stepJson in leg['steps']) {
          steps.add(NavigationStepModel.fromJson(stepJson as Map<String, dynamic>));
        }
      }
    }

    final int hazardCount = _countPotholesOnRoute(coordinates);

    return NavigationRouteModel(
      routeId: routeId,
      routeName: defaultName,
      distanceInMeters: distance,
      durationInSeconds: duration,
      encodedPolyline: 'encoded_osrm_poly',
      hazardCount: hazardCount,
      coordinates: coordinates,
      steps: steps,
    );
  }

  double _calculateHeading(double lat1, double lon1, double lat2, double lon2) {
    final double dLon = (lon2 - lon1) * pi / 180.0;
    final double lat1Rad = lat1 * pi / 180.0;
    final double lat2Rad = lat2 * pi / 180.0;
    
    final double y = sin(dLon) * cos(lat2Rad);
    final double x = cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(dLon);
    
    final double brng = atan2(y, x) * 180.0 / pi;
    return (brng + 360.0) % 360.0;
  }

  int _countPotholesOnRoute(List<Coordinate> routeCoords) {
    int count = 0;
    for (final pothole in knownPotholes) {
      bool onRoute = false;
      for (final coord in routeCoords) {
        if (_getDistance(pothole.latitude, pothole.longitude, coord.latitude, coord.longitude) <= 25.0) {
          onRoute = true;
          break;
        }
      }
      if (onRoute) count++;
    }
    return count;
  }

  double _getDistance(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  void _saveResolvedCoordinate(String name, double lat, double lon) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('coord_$name', jsonEncode({'lat': lat, 'lng': lon}));
    } catch (_) {}
  }

  List<String> _getOfflineSuggestions(String query) {
    final allSuggestions = [
      'Vizianagaram Fort, Vizianagaram',
      'Bhogapuram International Airport, Bhogapuram',
      'GITAM University, Rushikonda, Visakhapatnam',
      'RTC Complex, Visakhapatnam',
      'Madhurawada Junction, Visakhapatnam',
      'Anandapuram Bypass, Visakhapatnam',
      'Tagarapuvalasa Bridge, Visakhapatnam',
    ];
    return allSuggestions
        .where((place) => place.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  List<NavigationRouteModel> _getOfflineFallbackRoutes(double startLat, double startLng, double endLat, double endLng) {
    final start = Coordinate(startLat, startLng);
    final end = Coordinate(endLat, endLng);

    final fastestCoords = _generateCoordinatesOffline(start, end, useAlternative: false);
    final safestCoords = _generateCoordinatesOffline(start, end, useAlternative: true);

    final distanceFastest = fastestCoords.length * 4000.0; 
    final distanceSafest = safestCoords.length * 4000.0;

    return [
      NavigationRouteModel(
        routeId: 'route_fastest',
        routeName: 'NH 16 via Madhurawada (Offline Fallback)',
        distanceInMeters: distanceFastest,
        durationInSeconds: (distanceFastest / 15).round(),
        encodedPolyline: 'encoded_poly_1',
        hazardCount: _countPotholesOnRoute(fastestCoords), 
        coordinates: fastestCoords,
        steps: [
          NavigationStepModel(
            instruction: 'Depart onto highway road corridor',
            roadName: 'NH 16',
            distanceInMeters: distanceFastest,
            durationInSeconds: (distanceFastest / 15),
            location: start,
          ),
          NavigationStepModel(
            instruction: 'Arrived at your destination',
            roadName: 'Local Destination',
            distanceInMeters: 0,
            durationInSeconds: 0,
            location: end,
          )
        ],
      ),
      NavigationRouteModel(
        routeId: 'route_safest',
        routeName: 'Alternative Road (Offline Fallback)',
        distanceInMeters: distanceSafest,
        durationInSeconds: (distanceSafest / 13).round(),
        encodedPolyline: 'encoded_poly_2',
        hazardCount: _countPotholesOnRoute(safestCoords), 
        coordinates: safestCoords,
        steps: [
          NavigationStepModel(
            instruction: 'Depart onto scenic highway detour',
            roadName: 'Alternative Bypass',
            distanceInMeters: distanceSafest,
            durationInSeconds: (distanceSafest / 13),
            location: start,
          ),
          NavigationStepModel(
            instruction: 'Arrived at destination',
            roadName: 'Local Destination',
            distanceInMeters: 0,
            durationInSeconds: 0,
            location: end,
          )
        ],
      ),
    ];
  }

  List<Coordinate> _generateCoordinatesOffline(Coordinate start, Coordinate end, {required bool useAlternative}) {
    final isVizianagaram = (end.latitude - 18.1124).abs() < 0.06;
    final isBhogapuram = (end.latitude - 17.9540).abs() < 0.06;
    final isRushikonda = (end.latitude - 17.8250).abs() < 0.04;

    final List<Coordinate> path = [];
    path.add(start);

    if (isRushikonda) {
      path.addAll(_roadNodesVisakhapatnamToRushikonda);
    } else if (isBhogapuram) {
      if (useAlternative) {
        path.addAll(_roadNodesVisakhapatnamToRushikonda);
        path.addAll(_roadNodesVisakhapatnamToVizianagaram.skip(7).take(5)); 
        path.addAll(_roadNodesAnandapuramToBhogapuram.skip(1));
      } else {
        path.addAll(_roadNodesVisakhapatnamToVizianagaram.take(12)); 
        path.addAll(_roadNodesAnandapuramToBhogapuram.skip(1));
      }
    } else if (isVizianagaram) {
      if (useAlternative) {
        path.addAll(_roadNodesVisakhapatnamToRushikonda);
        path.addAll(_roadNodesVisakhapatnamToVizianagaram.skip(7)); 
      } else {
        path.addAll(_roadNodesVisakhapatnamToVizianagaram);
      }
    } else {
      path.add(end);
      return path;
    }

    path.add(end);

    final List<Coordinate> uniquePath = [];
    for (final coord in path) {
      if (uniquePath.isEmpty ||
          (uniquePath.last.latitude - coord.latitude).abs() > 0.0001 ||
          (uniquePath.last.longitude - coord.longitude).abs() > 0.0001) {
        uniquePath.add(coord);
      }
    }

    return uniquePath;
  }
}
