class AppConstants {
  // App General Info
  static const String appName = 'RoadSense AI';
  static const String appVersion = '1.0.0';

  // Shared Preferences Keys
  static const String keyRoadMonitoringEnabled = 'road_monitoring_enabled';
  static const String keyVoiceAlertsEnabled = 'voice_alerts_enabled';
  static const String keyThemeMode = 'theme_mode';

  // API Endpoints (Staging/Production placeholders)
  static const String baseApiUrl = 'https://secret.webarcade.in/api/v1';
  static const String uploadReportPath = '/reports/upload';
  static const String getHazardsPath = '/hazards/map';

  // Route Paths
  static const String routeSplash = '/';
  static const String routeHome = '/home';
  static const String routeNavigation = '/navigation';
  static const String routeSettings = '/settings';
}
