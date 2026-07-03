import 'package:flutter_riverpod/flutter_riverpod.dart';

class RoadMonitoringState {
  final bool isMonitoring;
  final int detectedPotholes;
  final int detectedCracks;
  final double currentLatitude;
  final double currentLongitude;
  final String statusMessage;

  RoadMonitoringState({
    this.isMonitoring = false,
    this.detectedPotholes = 0,
    this.detectedCracks = 0,
    this.currentLatitude = 0.0,
    this.currentLongitude = 0.0,
    this.statusMessage = 'Monitoring Inactive',
  });

  RoadMonitoringState copyWith({
    bool? isMonitoring,
    int? detectedPotholes,
    int? detectedCracks,
    double? currentLatitude,
    double? currentLongitude,
    String? statusMessage,
  }) {
    return RoadMonitoringState(
      isMonitoring: isMonitoring ?? this.isMonitoring,
      detectedPotholes: detectedPotholes ?? this.detectedPotholes,
      detectedCracks: detectedCracks ?? this.detectedCracks,
      currentLatitude: currentLatitude ?? this.currentLatitude,
      currentLongitude: currentLongitude ?? this.currentLongitude,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

class RoadMonitoringNotifier extends StateNotifier<RoadMonitoringState> {
  RoadMonitoringNotifier() : super(RoadMonitoringState());

  void toggleMonitoring() {
    if (state.isMonitoring) {
      stopMonitoring();
    } else {
      startMonitoring();
    }
  }

  void updateAnomalyData({
    required int potholes,
    required int cracks,
    required double lat,
    required double lng,
    required String message,
  }) {
    state = state.copyWith(
      detectedPotholes: potholes,
      detectedCracks: cracks,
      currentLatitude: lat,
      currentLongitude: lng,
      statusMessage: message,
    );
  }

  void startMonitoring() {
    if (state.isMonitoring) return;
    state = state.copyWith(
      isMonitoring: true,
      statusMessage: 'Background monitoring active (Running local AI inference)...',
    );
  }

  void stopMonitoring() {
    state = state.copyWith(
      isMonitoring: false,
      statusMessage: 'Monitoring Inactive',
    );
  }
}

final roadMonitoringProvider = StateNotifierProvider<RoadMonitoringNotifier, RoadMonitoringState>((ref) {
  return RoadMonitoringNotifier();
});
