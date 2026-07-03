import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class FrameMetadata {
  final DateTime timestamp;
  final double latitude;
  final double longitude;

  const FrameMetadata({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
  });
}

class Detection {
  final Rect rect; // Normalized coordinates (0.0 to 1.0)
  final String label;
  final double confidence;
  
  // Coordinate metadata associated with the processed frame
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  Detection({
    required this.rect,
    required this.label,
    required this.confidence,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });
}

final tfliteServiceProvider = Provider<TfliteService>((ref) {
  return TfliteService();
});

class TfliteService {
  Interpreter? _interpreter;
  bool _isModelLoaded = false;
  String _modelName = 'Unknown';

  bool get isModelLoaded => _isModelLoaded;
  String get modelName => _modelName;

  /// Loads the YOLOv8 model from assets
  Future<void> loadModel() async {
    if (_isModelLoaded) return;
    try {
      // Configure options (use GPU delegate where available)
      final options = InterpreterOptions();
      if (defaultTargetPlatform == TargetPlatform.android) {
        options.useNnApiForAndroid = true;
      }
      
      const assetPath = 'assets/models/yolov8n.tflite';
      _interpreter = await Interpreter.fromAsset(
        assetPath,
        options: options,
      );
      _isModelLoaded = true;
      _modelName = 'PeterHdd YOLOv8 Pothole Model';
      
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      debugPrint('TFLite Model Loaded Successfully.');
      debugPrint('Model Name: $_modelName');
      debugPrint('Model Input Tensor Shape: $inputShape');
      debugPrint('Model Output Tensor Shape: $outputShape');
    } catch (e) {
      debugPrint('Error loading TFLite model: $e. Model operations will remain inactive.');
    }
  }

  /// Run inference on a camera image frame, passing the frame's GPS metadata
  Future<List<Detection>> runInference(CameraImage image, FrameMetadata metadata) async {
    if (!_isModelLoaded || _interpreter == null) {
      debugPrint('TFLite inference skipped: model is not loaded.');
      return [];
    }

    try {
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;

      // 1. Preprocess CameraImage bytes into YOLOv8 input tensor format
      final stopwatch = Stopwatch()..start();
      final inputBuffer = _preprocessCameraImage(image, inputShape);
      final preprocessTime = stopwatch.elapsedMilliseconds;

      // 2. Prepare output tensor structures
      final outputs = {
        0: List.generate(
          outputShape[0],
          (_) => List.generate(
            outputShape[1],
            (_) => List.filled(outputShape[2], 0.0),
          ),
        ),
      };

      // 3. Execute interpreter
      stopwatch.reset();
      _interpreter!.runForMultipleInputs([inputBuffer], outputs);
      final inferenceTime = stopwatch.elapsedMilliseconds;

      // 4. Determine input width/height to normalize coordinates correctly
      int modelInputHeight = 640;
      int modelInputWidth = 640;
      if (inputShape.length == 4) {
        if (inputShape[1] == 3) {
          modelInputHeight = inputShape[2];
          modelInputWidth = inputShape[3];
        } else {
          modelInputHeight = inputShape[1];
          modelInputWidth = inputShape[2];
        }
      }

      // 5. Decode the outputs with associated metadata
      final List<Detection> detections = _decodeYoloOutput(
        outputs[0]![0],
        image.width,
        image.height,
        metadata,
        modelInputWidth,
        modelInputHeight,
      );

      debugPrint('AI Inference Stats - Model: $_modelName, Preprocess: ${preprocessTime}ms, Inference: ${inferenceTime}ms, Total: ${preprocessTime + inferenceTime}ms');
      return detections;
    } catch (e) {
      debugPrint('Error running TFLite inference: $e');
      return [];
    }
  }

  /// Preprocesses CameraImage into a normalized list matching the input tensor shape [1, H, W, 3] or [1, 3, H, W]
  dynamic _preprocessCameraImage(CameraImage image, List<int> inputShape) {
    int inputHeight = 640;
    int inputWidth = 640;
    bool isChannelsFirst = false;
    
    if (inputShape.length == 4) {
      if (inputShape[1] == 3) {
        isChannelsFirst = true;
        inputHeight = inputShape[2];
        inputWidth = inputShape[3];
      } else {
        inputHeight = inputShape[1];
        inputWidth = inputShape[2];
      }
    }
    
    final width = image.width;
    final height = image.height;
    
    final double scaleX = width / inputWidth;
    final double scaleY = height / inputHeight;
    
    final int size = inputHeight * inputWidth * 3;
    final Float32List float32list = Float32List(size);
    int idx = 0;
    
    if (image.planes.length >= 3) {
      // YUV420 format (Android)
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
      
      for (int y = 0; y < inputHeight; y++) {
        final int srcY = (y * scaleY).toInt().clamp(0, height - 1);
        final int yRowOffset = srcY * yRowStride;
        final int uvY = srcY >> 1;
        final int uRowOffset = uvY * uRowStride;
        final int vRowOffset = uvY * vRowStride;
        
        for (int x = 0; x < inputWidth; x++) {
          final int srcX = (x * scaleX).toInt().clamp(0, width - 1);
          final int yIndexInPlane = yRowOffset + srcX * yPixelStride;
          final int yValue = yIndexInPlane < yBuffer.length ? yBuffer[yIndexInPlane] : 128;
          
          final int uvX = srcX >> 1;
          final int uIndexInPlane = uRowOffset + uvX * uPixelStride;
          final int vIndexInPlane = vRowOffset + uvX * vPixelStride;
          
          final int uValue = uIndexInPlane < uBuffer.length ? uBuffer[uIndexInPlane] : 128;
          final int vValue = vIndexInPlane < vBuffer.length ? vBuffer[vIndexInPlane] : 128;
          
          final double r = ((yValue + 1.402 * (vValue - 128)).clamp(0, 255)) / 255.0;
          final double g = ((yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).clamp(0, 255)) / 255.0;
          final double b = ((yValue + 1.772 * (uValue - 128)).clamp(0, 255)) / 255.0;
          
          if (isChannelsFirst) {
            float32list[y * inputWidth + x] = r;
            float32list[inputHeight * inputWidth + y * inputWidth + x] = g;
            float32list[2 * inputHeight * inputWidth + y * inputWidth + x] = b;
          } else {
            float32list[idx++] = r;
            float32list[idx++] = g;
            float32list[idx++] = b;
          }
        }
      }
    } else if (image.planes.length == 1) {
      // BGRA8888 or RGBA8888 (iOS / Simulator)
      final plane = image.planes[0];
      final buffer = plane.bytes;
      final rowStride = plane.bytesPerRow;
      final pixelStride = plane.bytesPerPixel ?? 4;
      
      for (int y = 0; y < inputHeight; y++) {
        final int srcY = (y * scaleY).toInt().clamp(0, height - 1);
        final int rowOffset = srcY * rowStride;
        for (int x = 0; x < inputWidth; x++) {
          final int srcX = (x * scaleX).toInt().clamp(0, width - 1);
          final int index = rowOffset + srcX * pixelStride;
          
          double r = 0.5;
          double g = 0.5;
          double b = 0.5;
          
          if (index < buffer.length - 2) {
            b = buffer[index] / 255.0;
            g = buffer[index + 1] / 255.0;
            r = buffer[index + 2] / 255.0;
          }
          
          if (isChannelsFirst) {
            float32list[y * inputWidth + x] = r;
            float32list[inputHeight * inputWidth + y * inputWidth + x] = g;
            float32list[2 * inputHeight * inputWidth + y * inputWidth + x] = b;
          } else {
            float32list[idx++] = r;
            float32list[idx++] = g;
            float32list[idx++] = b;
          }
        }
      }
    }
    
    if (isChannelsFirst) {
      return float32list.reshape([1, 3, inputHeight, inputWidth]);
    } else {
      return float32list.reshape([1, inputHeight, inputWidth, 3]);
    }
  }

  /// Decodes YOLOv8 outputs containing coordinates and classes dynamically
  List<Detection> _decodeYoloOutput(
    List<List<double>> outputTensor,
    int imgWidth,
    int imgHeight,
    FrameMetadata metadata,
    int modelInputWidth,
    int modelInputHeight,
  ) {
    final List<Detection> detections = [];
    final numPredictions = outputTensor[0].length;
    final numClasses = outputTensor.length - 4;

    debugPrint('Model output parsing context: predictionsCount = $numPredictions, classesCount = $numClasses');
    
    // Check if it's the COCO 80-class model
    if (numClasses >= 80) {
      debugPrint('Warning: Loaded model is a standard 80-class COCO model. COCO classes do not map to potholes. Rejecting detections to prevent false classifications.');
      return [];
    }

    for (int i = 0; i < numPredictions; i++) {
      double bestScore = 0.0;
      int bestClassIdx = -1;
      
      for (int c = 0; c < numClasses; c++) {
        final double score = outputTensor[c + 4][i];
        if (score > bestScore) {
          bestScore = score;
          bestClassIdx = c;
        }
      }

      if (bestScore >= 0.45 && bestClassIdx != -1) {
        final double xCenter = outputTensor[0][i];
        final double yCenter = outputTensor[1][i];
        final double w = outputTensor[2][i];
        final double h = outputTensor[3][i];
        
        final double left = (xCenter - w / 2) / modelInputWidth;
        final double top = (yCenter - h / 2) / modelInputHeight;
        final double width = w / modelInputWidth;
        final double height = h / modelInputHeight;

        // Dynamic class mapping based on number of classes
        String label = 'Pothole';
        if (numClasses == 2) {
          label = (bestClassIdx == 0) ? 'Pothole' : 'Road Crack';
        } else if (numClasses == 1) {
          label = 'Pothole';
        } else {
          label = 'Class_$bestClassIdx';
        }

        debugPrint('Raw Prediction Found - Class ID: $bestClassIdx, Label: $label, Confidence: ${(bestScore * 100).toStringAsFixed(1)}%, Bbox: [L: ${left.toStringAsFixed(3)}, T: ${top.toStringAsFixed(3)}, W: ${width.toStringAsFixed(3)}, H: ${height.toStringAsFixed(3)}]');

        detections.add(
          Detection(
            rect: Rect.fromLTWH(
              left.clamp(0.0, 1.0),
              top.clamp(0.0, 1.0),
              width.clamp(0.0, 1.0),
              height.clamp(0.0, 1.0),
            ),
            label: label,
            confidence: bestScore,
            latitude: metadata.latitude,
            longitude: metadata.longitude,
            timestamp: metadata.timestamp,
          ),
        );
      }
    }

    final filteredDetections = _applyNMS(detections);
    debugPrint('Final filtered detections count after NMS: ${filteredDetections.length}');
    for (final det in filteredDetections) {
      debugPrint('Active Detection Log - Label: ${det.label}, Confidence: ${(det.confidence * 100).toStringAsFixed(1)}%, Location: (${det.latitude.toStringAsFixed(5)}, ${det.longitude.toStringAsFixed(5)})');
    }
    return filteredDetections;
  }

  List<Detection> _applyNMS(List<Detection> detections) {
    detections.sort((a, b) => b.confidence.compareTo(a.confidence));
    final List<Detection> activeDetections = [];

    for (final detection in detections) {
      bool keep = true;
      for (final active in activeDetections) {
        if (_calculateIoU(detection.rect, active.rect) > 0.5) {
          keep = false;
          break;
        }
      }
      if (keep) {
        activeDetections.add(detection);
      }
      if (activeDetections.length >= 5) break;
    }

    return activeDetections;
  }

  double _calculateIoU(Rect r1, Rect r2) {
    final intersection = r1.intersect(r2);
    if (intersection.width <= 0 || intersection.height <= 0) return 0.0;
    
    final intersectionArea = intersection.width * intersection.height;
    final unionArea = (r1.width * r1.height) + (r2.width * r2.height) - intersectionArea;
    return intersectionArea / unionArea;
  }

  void dispose() {
    _interpreter?.close();
  }
}
