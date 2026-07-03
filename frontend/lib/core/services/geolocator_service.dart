import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final geolocatorServiceProvider = Provider<GeolocatorService>((ref) {
  return GeolocatorService();
});

class GeolocatorService {
  // Default coordinates (RTC Complex, Visakhapatnam) if GPS permission is denied
  static const double defaultLatitude = 18.0528;
  static const double defaultLongitude = 83.4198;

  /// Check permissions and get current position. Falls back to default coordinates on error/denial.
  Future<Position> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      // Test if location services are enabled.
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return _getDefaultPosition();
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return _getDefaultPosition();
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return _getDefaultPosition();
      }

      // When permissions are granted, return current position
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
    } catch (_) {
      return _getDefaultPosition();
    }
  }

  /// Streams the user's location updates as they drive.
  Stream<Position> getLocationStream() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1, // Receive updates when user moves 1 meter
    );
    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  Position _getDefaultPosition() {
    return Position(
      latitude: defaultLatitude,
      longitude: defaultLongitude,
      timestamp: DateTime.now(),
      accuracy: 0.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );
  }
}
