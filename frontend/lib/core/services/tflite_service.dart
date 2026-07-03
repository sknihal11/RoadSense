import 'package:flutter/foundation.dart';
import 'dart:isolate';
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
      options.threads = 4;
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

      // Transfer plane bytes zero-copy using TransferableTypedData
      final transferablePlanes = image.planes
          .map((p) => TransferableTypedData.fromList([p.bytes]))
          .toList();

      final args = InferenceIsolateArgs(
        planeBytes: transferablePlanes,
        planeBytesPerRow: image.planes.map((p) => p.bytesPerRow).toList(),
        planeBytesPerPixel: image.planes.map((p) => p.bytesPerPixel).toList(),
        width: image.width,
        height: image.height,
        inputShape: inputShape,
        outputShape: outputShape,
        modelAssetPath: 'assets/models/yolov8n.tflite',
        metadata: metadata,
      );

      final stopwatch = Stopwatch()..start();
      final List<Detection> detections = await compute(runYoloInferenceIsolate, args);
      final totalTime = stopwatch.elapsedMilliseconds;

      debugPrint('AI Background Isolate Inference Stats - Total: ${totalTime}ms, Detections: ${detections.length}');
      return detections;
    } catch (e) {
      debugPrint('Error running background TFLite inference: $e');
      return [];
    }
  }

  // Synchronous preprocessing has been moved to a background Isolate for UI responsiveness.

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

/// Arguments container for running the entire YOLOv8 model inference chain on a background Isolate
class InferenceIsolateArgs {
  final List<TransferableTypedData> planeBytes;
  final List<int> planeBytesPerRow;
  final List<int?> planeBytesPerPixel;
  final int width;
  final int height;
  final List<int> inputShape;
  final List<int> outputShape;
  final String modelAssetPath;
  final FrameMetadata metadata;

  InferenceIsolateArgs({
    required this.planeBytes,
    required this.planeBytesPerRow,
    required this.planeBytesPerPixel,
    required this.width,
    required this.height,
    required this.inputShape,
    required this.outputShape,
    required this.modelAssetPath,
    required this.metadata,
  });
}

/// Runs YUV scaling, normalization, TFLite execution, and output decoding on a background Isolate (zero-copy)
Future<List<Detection>> runYoloInferenceIsolate(InferenceIsolateArgs args) async {
  // 1. Materialize plane bytes instantly (zero-copy)
  final materializedPlanes = args.planeBytes.map((t) => t.materialize().asUint8List()).toList();
  
  // 2. Perform preprocessing (scaling and color space conversion)
  int inputHeight = 640;
  int inputWidth = 640;
  bool isChannelsFirst = false;
  
  if (args.inputShape.length == 4) {
    if (args.inputShape[1] == 3) {
      isChannelsFirst = true;
      inputHeight = args.inputShape[2];
      inputWidth = args.inputShape[3];
    } else {
      inputHeight = args.inputShape[1];
      inputWidth = args.inputShape[2];
    }
  }
  
  final double scaleX = args.width / inputWidth;
  final double scaleY = args.height / inputHeight;
  
  final int size = inputHeight * inputWidth * 3;
  final Float32List float32list = Float32List(size);
  int idx = 0;
  
  if (materializedPlanes.length >= 3) {
    // YUV420 format (Android)
    final yBuffer = materializedPlanes[0];
    final uBuffer = materializedPlanes[1];
    final vBuffer = materializedPlanes[2];
    
    final yRowStride = args.planeBytesPerRow[0];
    final uRowStride = args.planeBytesPerRow[1];
    final vRowStride = args.planeBytesPerRow[2];
    
    final yPixelStride = args.planeBytesPerPixel[0] ?? 1;
    final uPixelStride = args.planeBytesPerPixel[1] ?? 2;
    final vPixelStride = args.planeBytesPerPixel[2] ?? 2;
    
    for (int y = 0; y < inputHeight; y++) {
      final int srcY = (y * scaleY).toInt().clamp(0, args.height - 1);
      final int yRowOffset = srcY * yRowStride;
      final int uvY = srcY >> 1;
      final int uRowOffset = uvY * uRowStride;
      final int vRowOffset = uvY * vRowStride;
      
      for (int x = 0; x < inputWidth; x++) {
        final int srcX = (x * scaleX).toInt().clamp(0, args.width - 1);
        final int yIndexInPlane = yRowOffset + srcX * yPixelStride;
        final int yValue = yIndexInPlane < yBuffer.length ? yBuffer[yIndexInPlane] : 128;
        
        final int uvX = srcX >> 1;
        final int uIndexInPlane = uRowOffset + uvX * uPixelStride;
        final int vIndexInPlane = vRowOffset + uvX * vPixelStride;
        
        final int uValue = uIndexInPlane < uBuffer.length ? uBuffer[uIndexInPlane] : 128;
        final int vValue = vIndexInPlane < vBuffer.length ? vBuffer[vIndexInPlane] : 128;
        
        // Fast integer math color space conversion:
        final int rVal = (yValue + ((1435 * (vValue - 128)) >> 10)).clamp(0, 255);
        final int gVal = (yValue - ((352 * (uValue - 128) + 731 * (vValue - 128)) >> 10)).clamp(0, 255);
        final int bVal = (yValue + ((1814 * (uValue - 128)) >> 10)).clamp(0, 255);
        
        final double r = rVal / 255.0;
        final double g = gVal / 255.0;
        final double b = bVal / 255.0;
        
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
  } else if (materializedPlanes.length == 1) {
    // BGRA8888 or RGBA8888 (iOS / Simulator)
    final bytes = materializedPlanes[0];
    final rowStride = args.planeBytesPerRow[0];
    final pixelStride = args.planeBytesPerPixel[0] ?? 4;
    
    for (int y = 0; y < inputHeight; y++) {
      final int srcY = (y * scaleY).toInt().clamp(0, args.height - 1);
      final int rowOffset = srcY * rowStride;
      for (int x = 0; x < inputWidth; x++) {
        final int srcX = (x * scaleX).toInt().clamp(0, args.width - 1);
        final int index = rowOffset + srcX * pixelStride;
        
        double r = 0.5;
        double g = 0.5;
        double b = 0.5;
        
        if (index < bytes.length - 2) {
          b = bytes[index] / 255.0;
          g = bytes[index + 1] / 255.0;
          r = bytes[index + 2] / 255.0;
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
  
  dynamic inputBuffer;
  if (isChannelsFirst) {
    inputBuffer = float32list.reshape([1, 3, inputHeight, inputWidth]);
  } else {
    inputBuffer = float32list.reshape([1, inputHeight, inputWidth, 3]);
  }

  // 3. Load interpreter inside the background isolate thread
  final options = InterpreterOptions();
  options.threads = 4;
  if (defaultTargetPlatform == TargetPlatform.android) {
    options.useNnApiForAndroid = true;
  }
  final interpreter = await Interpreter.fromAsset(args.modelAssetPath, options: options);
  
  // 4. Prepare output tensor structures
  final outputs = {
    0: List.generate(
      args.outputShape[0],
      (_) => List.generate(
        args.outputShape[1],
        (_) => List.filled(args.outputShape[2], 0.0),
      ),
    ),
  };
  
  // 5. Execute model
  interpreter.runForMultipleInputs([inputBuffer], outputs);
  interpreter.close();
  
  // 6. Decode output
  final List<Detection> detections = [];
  final List<List<double>> outputTensor = outputs[0]![0];
  final numPredictions = outputTensor[0].length;
  final numClasses = outputTensor.length - 4;
  
  if (numClasses >= 80) {
    return []; // COCO model safety block
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
      
      final double left = (xCenter - w / 2) / inputWidth;
      final double top = (yCenter - h / 2) / inputHeight;
      final double width = w / inputWidth;
      final double height = h / inputHeight;
      
      String label = 'pothole';
      if (numClasses == 1) {
        label = 'pothole';
      } else if (bestClassIdx == 0) {
        label = 'pothole';
      } else if (bestClassIdx == 1) {
        label = 'crack';
      }
      
      final double lat = args.metadata.latitude + (top + height / 2 - 0.5) * 0.0001;
      final double lng = args.metadata.longitude + (left + width / 2 - 0.5) * 0.0001;
      
      detections.add(Detection(
        rect: Rect.fromLTWH(left, top, width, height),
        confidence: bestScore,
        label: label,
        latitude: lat,
        longitude: lng,
        timestamp: args.metadata.timestamp,
      ));
    }
  }

  // 7. Apply Non-Max Suppression (NMS)
  detections.sort((a, b) => b.confidence.compareTo(a.confidence));
  final List<Detection> activeDetections = [];
  for (final detection in detections) {
    bool keep = true;
    for (final active in activeDetections) {
      final r1 = detection.rect;
      final r2 = active.rect;
      final intersection = r1.intersect(r2);
      double iou = 0.0;
      if (intersection.width > 0 && intersection.height > 0) {
        final intersectionArea = intersection.width * intersection.height;
        final unionArea = (r1.width * r1.height) + (r2.width * r2.height) - intersectionArea;
        iou = intersectionArea / unionArea;
      }
      if (iou > 0.5) {
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
