import '../models/navigation_route_model.dart';

abstract class NavigationRepository {
  Future<List<NavigationRouteModel>> getRoutes({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  });

  Future<List<String>> searchPlaces(String query);
  Future<Coordinate?> resolvePlaceCoordinate(String placeName);
}
