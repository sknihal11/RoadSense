class Coordinate {
  final double latitude;
  final double longitude;
  final double heading;

  const Coordinate(this.latitude, this.longitude, {this.heading = 0.0});

  factory Coordinate.fromJson(Map<String, dynamic> json) {
    return Coordinate(
      (json['lat'] as num).toDouble(),
      (json['lng'] as num).toDouble(),
      heading: (json['heading'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': latitude,
      'lng': longitude,
      'heading': heading,
    };
  }
}

class NavigationStepModel {
  final String instruction;
  final String roadName;
  final double distanceInMeters;
  final double durationInSeconds;
  final Coordinate location;

  NavigationStepModel({
    required this.instruction,
    required this.roadName,
    required this.distanceInMeters,
    required this.durationInSeconds,
    required this.location,
  });

  factory NavigationStepModel.fromJson(Map<String, dynamic> json) {
    final maneuver = json['maneuver'] as Map<String, dynamic>? ?? {};
    final type = maneuver['type'] as String? ?? 'proceed';
    final modifier = maneuver['modifier'] as String? ?? '';
    final name = json['name'] as String? ?? '';

    // Generate readable instruction
    String instructionText = '';
    if (type == 'depart') {
      instructionText = 'Depart towards your destination';
    } else if (type == 'arrive') {
      instructionText = 'You have arrived';
    } else if (type == 'turn') {
      instructionText = 'Turn ${modifier.replaceAll('_', ' ')}';
      if (name.isNotEmpty) instructionText += ' onto $name';
    } else if (type == 'new name') {
      instructionText = 'Continue onto $name';
    } else {
      instructionText = '${type.substring(0, 1).toUpperCase()}${type.substring(1)}';
      if (modifier.isNotEmpty) instructionText += ' ${modifier.replaceAll('_', ' ')}';
      if (name.isNotEmpty) instructionText += ' onto $name';
    }

    final locList = maneuver['location'] as List<dynamic>? ?? [0.0, 0.0];
    final double lng = (locList[0] as num).toDouble();
    final double lat = (locList[1] as num).toDouble();

    return NavigationStepModel(
      instruction: instructionText,
      roadName: name.isNotEmpty ? name : 'Local Road',
      distanceInMeters: (json['distance'] as num).toDouble(),
      durationInSeconds: (json['duration'] as num).toDouble(),
      location: Coordinate(lat, lng),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'instruction': instruction,
      'road_name': roadName,
      'distance_in_meters': distanceInMeters,
      'duration_in_seconds': durationInSeconds,
      'location': location.toJson(),
    };
  }
}

class NavigationRouteModel {
  final String routeId;
  final String routeName;
  final double distanceInMeters;
  final int durationInSeconds;
  final String encodedPolyline;
  final int hazardCount;
  final List<Coordinate> coordinates;
  final List<NavigationStepModel> steps;

  NavigationRouteModel({
    required this.routeId,
    required this.routeName,
    required this.distanceInMeters,
    required this.durationInSeconds,
    required this.encodedPolyline,
    required this.hazardCount,
    required this.coordinates,
    required this.steps,
  });

  double get distanceInKm => distanceInMeters / 1000.0;
  int get durationInMinutes => (durationInSeconds / 60.0).round();

  factory NavigationRouteModel.fromJson(Map<String, dynamic> json) {
    return NavigationRouteModel(
      routeId: json['route_id'] as String,
      routeName: json['route_name'] as String,
      distanceInMeters: (json['distance_in_meters'] as num).toDouble(),
      durationInSeconds: json['duration_in_seconds'] as int,
      encodedPolyline: json['encoded_polyline'] as String,
      hazardCount: json['hazard_count'] as int? ?? 0,
      coordinates: (json['coordinates'] as List<dynamic>?)
              ?.map((e) => Coordinate.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      steps: (json['steps'] as List<dynamic>?)
              ?.map((e) => NavigationStepModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'route_id': routeId,
      'route_name': routeName,
      'distance_in_meters': distanceInMeters,
      'duration_in_seconds': durationInSeconds,
      'encoded_polyline': encodedPolyline,
      'hazard_count': hazardCount,
      'coordinates': coordinates.map((e) => e.toJson()).toList(),
      'steps': steps.map((e) => e.toJson()).toList(),
    };
  }
}
