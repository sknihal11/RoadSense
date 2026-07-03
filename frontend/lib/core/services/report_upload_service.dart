import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import '../constants/app_constants.dart';

class QueuedReport {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String anomalyType;
  final double confidence;
  final String filePath;

  QueuedReport({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.anomalyType,
    required this.confidence,
    required this.filePath,
  });

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'timestamp': timestamp.toIso8601String(),
    'anomaly_type': anomalyType,
    'confidence': confidence,
    'file_path': filePath,
  };

  factory QueuedReport.fromJson(Map<String, dynamic> json) => QueuedReport(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    timestamp: DateTime.parse(json['timestamp'] as String),
    anomalyType: json['anomaly_type'] as String,
    confidence: (json['confidence'] as num).toDouble(),
    filePath: json['file_path'] as String,
  );
}

class ReportUploadNotifier extends StateNotifier<List<QueuedReport>> {
  final ApiService _apiService;
  Timer? _retryTimer;
  static const String _prefsKey = 'roadsense_offline_upload_queue';

  ReportUploadNotifier(this._apiService) : super([]) {
    _loadQueueFromStorage();
    // Start automated background retries every 30 seconds
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) => retryQueue());
  }

  Future<void> _loadQueueFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serializedList = prefs.getStringList(_prefsKey);
      if (serializedList != null) {
        state = serializedList
            .map((item) => QueuedReport.fromJson(jsonDecode(item) as Map<String, dynamic>))
            .toList();
        debugPrint('Loaded ${state.length} pending reports from local storage.');
      }
    } catch (e) {
      debugPrint('Failed to load queue from storage: $e');
    }
  }

  Future<void> _saveQueueToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serializedList = state
          .map((item) => jsonEncode(item.toJson()))
          .toList();
      await prefs.setStringList(_prefsKey, serializedList);
    } catch (e) {
      debugPrint('Failed to save queue to storage: $e');
    }
  }

  /// Attempts to upload a report immediately. If offline or it fails, queues it persistently.
  Future<void> uploadOrQueue(QueuedReport report) async {
    final success = await _uploadToServer(report);
    if (!success) {
      debugPrint('Upload failed. Adding report to offline retry queue.');
      state = [...state, report];
      await _saveQueueToStorage();
    } else {
      debugPrint('Report uploaded successfully.');
    }
  }

  /// Iterates through the queue, attempts uploads, and clears successful ones
  Future<void> retryQueue() async {
    if (state.isEmpty) return;

    debugPrint('Background retry active: Flushing ${state.length} queued reports.');
    final List<QueuedReport> remaining = [];

    for (final report in state) {
      final success = await _uploadToServer(report);
      if (!success) {
        remaining.add(report);
      }
    }

    if (remaining.length != state.length) {
      state = remaining;
      await _saveQueueToStorage();
      debugPrint('Flush cycle completed. Remaining in queue: ${state.length}');
    }
  }

  Future<bool> _uploadToServer(QueuedReport report) async {
    try {
      final multipartFile = await MultipartFile.fromFile(
        report.filePath,
        filename: 'evidence_${report.timestamp.millisecondsSinceEpoch}.jpg',
      );

      final Map<String, dynamic> data = {
        'latitude': report.latitude,
        'longitude': report.longitude,
        'timestamp': report.timestamp.toIso8601String(),
        'anomaly_type': report.anomalyType,
        'confidence': report.confidence,
        'file': multipartFile,
      };

      // Calls FastAPI endpoint: /api/v1/reports/upload
      final response = await _apiService.postMultipartFormData(
        AppConstants.uploadReportPath,
        data: data,
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('API upload error: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }
}

final reportUploadServiceProvider = StateNotifierProvider<ReportUploadNotifier, List<QueuedReport>>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return ReportUploadNotifier(apiService);
});
