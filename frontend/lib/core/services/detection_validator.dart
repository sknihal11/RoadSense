import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'tflite_service.dart';

final detectionValidatorProvider = Provider<DetectionValidator>((ref) {
  return DetectionValidator();
});

class RecentDetection {
  final Detection detection;
  final DateTime timestamp;
  bool isValidated;

  RecentDetection({
    required this.detection,
    required this.timestamp,
    this.isValidated = false,
  });
}

class DetectionValidator {
  final List<RecentDetection> _recentDetections = [];
  final List<Detection> _verifiedAnomalies = [];
  
  // Configuration thresholds
  final double minConfidence = 0.65;
  final double minBBoxSize = 0.05; // 5% of screen size minimum
  final double duplicateDistanceThreshold = 15.0; // meters
  final int minFramesForConsistency = 3;
  final Duration temporalWindow = const Duration(seconds: 3);

  /// Clears validation cache (e.g. when monitoring is restarted)
  void reset() {
    _recentDetections.clear();
    _verifiedAnomalies.clear();
  }

  /// Calculates distance in meters between two GPS points using Haversine formula
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295; // pi / 180
    final a = 0.5 - cos((lat2 - lat1) * p)/2 + 
          cos(lat1 * p) * cos(lat2 * p) * 
          (1 - cos((lon2 - lon1) * p))/2;
    return 12742 * asin(sqrt(a)) * 1000; // Returns meters (R = 6371 km)
  }

  /// Evaluates whether a raw AI prediction is a valid road anomaly.
  /// Returns a validated [Detection] if it passes all validation stages, else null.
  Detection? validateDetection({
    required Detection detection,
    required CameraImage frame,
    required double gpsAccuracy,
  }) {
    // 1. Confidence threshold check
    if (detection.confidence < minConfidence) {
      debugPrint('Validation Failed: Confidence (${detection.confidence.toStringAsFixed(2)}) below threshold ($minConfidence)');
      return null;
    }

    // 2. Minimum BBox size check
    if (detection.rect.width < minBBoxSize || detection.rect.height < minBBoxSize) {
      debugPrint('Validation Failed: BBox dimensions too small (${detection.rect.width.toStringAsFixed(3)}x${detection.rect.height.toStringAsFixed(3)})');
      return null;
    }

    // 3. Road Region Validation: Potholes must be on the road surface.
    // They cannot appear in the sky, horizon, or trees (upper half of the frame).
    // Normalized coordinates (0.0 to 1.0), where 0.0 is top/left, 1.0 is bottom/right.
    if (detection.rect.bottom < 0.4 || detection.rect.top < 0.15) {
      debugPrint('Validation Failed: Anomaly location outside road region (rect: ${detection.rect})');
      return null;
    }

    // 4. GPS Accuracy Check
    // Reject detections if GPS accuracy is poor (e.g. > 15m), which is common indoors
    if (gpsAccuracy > 15.0) {
      debugPrint('Validation Failed: Poor GPS Accuracy (${gpsAccuracy.toStringAsFixed(1)}m > 15m). Likely indoors.');
      return null;
    }

    // 5. Road Context Validation via Grayness Analysis of the Bottom Half of the Frame
    if (!_validateRoadContext(frame)) {
      debugPrint('Validation Failed: Image frame does not resemble a road scene (failed grayness analysis). Likely indoors.');
      return null;
    }

    final now = DateTime.now();
    
    // Clean up old detections from the buffer
    _recentDetections.removeWhere((item) => now.difference(item.timestamp) > temporalWindow);

    // 6. Duplicate Check: Ignore if we have already verified a pothole at this exact GPS point recently
    for (final verified in _verifiedAnomalies) {
      final distance = _calculateDistance(
        detection.latitude, 
        detection.longitude, 
        verified.latitude, 
        verified.longitude
      );
      if (distance < duplicateDistanceThreshold) {
        debugPrint('Validation Ignored: Duplicate anomaly already verified within ${distance.toStringAsFixed(1)} meters.');
        return null;
      }
    }

    // Add current prediction to temporal consistency buffer
    final currentRecent = RecentDetection(detection: detection, timestamp: now);
    _recentDetections.add(currentRecent);

    // 7. Temporal Consistency Check: Match detections across frames
    int matchCount = 0;
    final List<RecentDetection> matchingGroup = [];

    for (final item in _recentDetections) {
      if (item.isValidated) continue;
      
      // Calculate distance between the coordinates of these detections
      final dist = _calculateDistance(
        detection.latitude, 
        detection.longitude, 
        item.detection.latitude, 
        item.detection.longitude
      );
      
      // Since vehicle moves, consecutive detections of the same pothole will have very close GPS coordinates
      if (dist < 10.0) {
        matchCount++;
        matchingGroup.add(item);
      }
    }

    debugPrint('Temporal Consistency: Found $matchCount matching predictions in the last ${temporalWindow.inSeconds}s window.');

    if (matchCount >= minFramesForConsistency) {
      // Mark all matched items as validated to prevent re-triggering for the same cluster
      for (final item in matchingGroup) {
        item.isValidated = true;
      }
      
      // Save to verified list to prevent duplicate uploads
      _verifiedAnomalies.add(detection);
      
      // Keep verified anomalies list capped to prevent memory growth
      if (_verifiedAnomalies.length > 100) {
        _verifiedAnomalies.removeAt(0);
      }

      debugPrint('>>> VALIDATION PASSED: Anomaly verified via Temporal Consistency! <<<');
      return detection;
    }

    return null;
  }

  /// Analyzes the color distribution in the lower part of the camera frame.
  /// Road surface (asphalt/concrete) is typically gray/dark with low saturation.
  /// Indoor objects (furniture, beds, walls, carpets) have higher color variance/saturation.
  bool _validateRoadContext(CameraImage image) {
    try {
      int grayPixelCount = 0;
      int sampledPixelCount = 0;

      // Sample pixels on a grid in the bottom half of the image
      final int startY = (image.height * 0.55).toInt();
      final int endY = (image.height * 0.90).toInt();
      final int startX = (image.width * 0.15).toInt();
      final int endX = (image.width * 0.85).toInt();

      final int stepY = max(1, (endY - startY) ~/ 8);
      final int stepX = max(1, (endX - startX) ~/ 8);

      if (image.planes.length == 1) {
        // Single plane (e.g. BGRA/RGBA on iOS or Simulator)
        final plane = image.planes[0];
        final bytes = plane.bytes;
        final rowStride = plane.bytesPerRow;
        final pixelStride = plane.bytesPerPixel ?? 4;

        for (int y = startY; y < endY; y += stepY) {
          for (int x = startX; x < endX; x += stepX) {
            final int index = y * rowStride + x * pixelStride;
            if (index < bytes.length - 2) {
              final int b = bytes[index];
              final int g = bytes[index + 1];
              final int r = bytes[index + 2];

              // Grayness check: difference between channel intensities should be small
              final double diff = ((r - g).abs() + (g - b).abs() + (b - r).abs()).toDouble();
              
              // Dark or light gray (road asphalt/concrete range)
              if (diff < 35.0) {
                grayPixelCount++;
              }
              sampledPixelCount++;
            }
          }
        }
      } else if (image.planes.length >= 3) {
        // YUV420 plane formats (typical on Android)
        final yPlane = image.planes[0];
        final uPlane = image.planes[1];
        final vPlane = image.planes[2];

        final yBuffer = yPlane.bytes;
        final uBuffer = uPlane.bytes;
        final vBuffer = vPlane.bytes;

        final yRowStride = yPlane.bytesPerRow;
        final uRowStride = uPlane.bytesPerRow;
        final vRowStride = vPlane.bytesPerRow;

        final yPixelStride = yPlane.bytesPerPixel ?? 1;
        final uPixelStride = uPlane.bytesPerPixel ?? 2;
        final vPixelStride = vPlane.bytesPerPixel ?? 2;

        for (int y = startY; y < endY; y += stepY) {
          for (int x = startX; x < endX; x += stepX) {
            final int yIdx = y * yRowStride + x * yPixelStride;
            if (yIdx >= yBuffer.length) continue;

            final int uvX = x >> 1;
            final int uvY = y >> 1;

            final uIdx = uvY * uRowStride + uvX * uPixelStride;
            final vIdx = uvY * vRowStride + uvX * vPixelStride;

            if (uIdx >= uBuffer.length || vIdx >= vBuffer.length) continue;

            final int yVal = yBuffer[yIdx];
            final int uVal = uBuffer[uIdx];
            final int vVal = vBuffer[vIdx];

            // Convert to RGB to analyze grayness
            final double r = (yVal + 1.402 * (vVal - 128)).clamp(0.0, 255.0);
            final double g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128)).clamp(0.0, 255.0);
            final double b = (yVal + 1.772 * (uVal - 128)).clamp(0.0, 255.0);

            final double diff = (r - g).abs() + (g - b).abs() + (b - r).abs();
            if (diff < 35.0) {
              grayPixelCount++;
            }
            sampledPixelCount++;
          }
        }
      }

      if (sampledPixelCount == 0) return true; // Fallback if no pixels sampled

      final double grayRatio = grayPixelCount / sampledPixelCount;
      debugPrint('Road Context: Sampled $sampledPixelCount pixels. Gray ratio: ${(grayRatio * 100).toStringAsFixed(1)}%');
      
      // Road surface should be at least 55% gray-ish colors
      return grayRatio >= 0.55;
    } catch (e) {
      debugPrint('Error in Road Context Analysis: $e');
      return true; // Fallback to avoid breaking on platform errors
    }
  }
}
