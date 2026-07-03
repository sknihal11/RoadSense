import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/tflite_service.dart';
import '../core/services/geolocator_service.dart';
import '../core/services/report_upload_service.dart';
import '../core/services/detection_validator.dart';
import '../features/road_monitoring/presentation/road_monitoring_provider.dart';

class MovableCameraPreview extends ConsumerStatefulWidget {
  const MovableCameraPreview({Key? key}) : super(key: key);

  @override
  ConsumerState<MovableCameraPreview> createState() => _MovableCameraPreviewState();
}

class _MovableCameraPreviewState extends ConsumerState<MovableCameraPreview> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  // Active detections & Processing lock
  List<Detection> _detections = [];
  bool _isProcessing = false;
  DateTime? _lastInferenceTime;

  // Camera picture snapshot cooldown settings
  DateTime? _lastCaptureTime;
  final Duration _captureCooldown = const Duration(seconds: 10);

  // GPS Coordinate Streams & Buffering
  StreamSubscription<Position>? _gpsSubscription;
  double _latestLatitude = GeolocatorService.defaultLatitude;
  double _latestLongitude = GeolocatorService.defaultLongitude;
  double _latestAccuracy = 0.0;

  // Sliding window buffer of coordinates for the last 50 processed frames
  final List<FrameMetadata> _gpsFrameBuffer = [];
  final int _maxBufferSize = 50;

  // Window positioning offsets
  double _left = 16.0;
  double _top = 180.0;

  // Fixed PiP size
  final double _width = 130.0;
  final double _height = 180.0;

  @override
  void initState() {
    super.initState();
    _setupLocationListener();
    _initializeCamera();
  }

  void _setupLocationListener() {
    final geolocator = ref.read(geolocatorServiceProvider);
    
    geolocator.getCurrentLocation().then((position) {
      if (mounted) {
        setState(() {
          _latestLatitude = position.latitude;
          _latestLongitude = position.longitude;
          _latestAccuracy = position.accuracy;
        });
      }
    });

    _gpsSubscription = geolocator.getLocationStream().listen((position) {
      if (mounted) {
        setState(() {
          _latestLatitude = position.latitude;
          _latestLongitude = position.longitude;
          _latestAccuracy = position.accuracy;
        });
      }
    });
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _hasError = true);
        return;
      }

      final backCamera = cameras.first;
      
      _controller = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();
      
      if (!mounted) return;

      setState(() {
        _isInitialized = true;
      });

      // Load TFLite Model
      await ref.read(tfliteServiceProvider).loadModel();

      // Start processing live image frames
      _startInferenceStream();
    } catch (_) {
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  void _startInferenceStream() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    _controller!.startImageStream((CameraImage image) async {
      final metadata = FrameMetadata(
        timestamp: DateTime.now(),
        latitude: _latestLatitude,
        longitude: _latestLongitude,
      );

      if (mounted) {
        setState(() {
          _gpsFrameBuffer.add(metadata);
          if (_gpsFrameBuffer.length > _maxBufferSize) {
            _gpsFrameBuffer.removeAt(0);
          }
        });
      }

      final now = DateTime.now();
      if (_lastInferenceTime != null && now.difference(_lastInferenceTime!) < const Duration(milliseconds: 1500)) {
        return;
      }
      _lastInferenceTime = now;

      if (_isProcessing) return;
      _isProcessing = true;

      try {
        final results = await ref.read(tfliteServiceProvider).runInference(image, metadata);
        
        if (mounted) {
          setState(() {
            _detections = results;
          });

          if (results.isNotEmpty) {
            final validator = ref.read(detectionValidatorProvider);
            final List<Detection> validatedResults = [];
            for (final det in results) {
              final validated = validator.validateDetection(
                detection: det,
                frame: image,
                gpsAccuracy: _latestAccuracy,
              );
              if (validated != null) {
                validatedResults.add(validated);
              }
            }

            if (validatedResults.isNotEmpty) {
              final hasPothole = validatedResults.any((d) => d.label == 'Pothole');
              final hasCrack = validatedResults.any((d) => d.label == 'Road Crack');
              
              if (hasPothole || hasCrack) {
                final firstDetection = validatedResults.first;
                final frameLat = firstDetection.latitude;
                final frameLng = firstDetection.longitude;

                // Local statistics update (statistics provider)
                final notifier = ref.read(roadMonitoringProvider.notifier);
                final current = ref.read(roadMonitoringProvider);
                notifier.startMonitoring();
                
                notifier.updateAnomalyData(
                  potholes: current.detectedPotholes + (hasPothole ? 1 : 0),
                  cracks: current.detectedCracks + (hasCrack ? 1 : 0),
                  lat: frameLat,
                  lng: frameLng,
                  message: 'Verified anomaly detected at GPS: (${frameLat.toStringAsFixed(5)}, ${frameLng.toStringAsFixed(5)})',
                );

                // 5. Cooldown Capture trigger:
                // Capturing snapshots on the main UI stream requires high execution costs,
                // so we enforce a cooldown between snaps.
                final now = DateTime.now();
                if (_lastCaptureTime == null || now.difference(_lastCaptureTime!) > _captureCooldown) {
                  _lastCaptureTime = now;
                  _captureEvidenceAndUpload(firstDetection);
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Frame processing failed: $e');
      } finally {
        _isProcessing = false;
      }
    });
  }

  Future<void> _captureEvidenceAndUpload(Detection detection) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      debugPrint('Triggering snapshot capture for ${detection.label} anomaly...');
      // 1. Take a high-resolution snapshot via the camera
      final XFile file = await _controller!.takePicture();
      
      // 2. Create the queued report using frame-specific location coordinates
      final report = QueuedReport(
        latitude: detection.latitude,
        longitude: detection.longitude,
        timestamp: detection.timestamp,
        anomalyType: detection.label,
        confidence: detection.confidence,
        filePath: file.path,
      );

      // 3. Submit to the persistent upload service
      ref.read(reportUploadServiceProvider.notifier).uploadOrQueue(report);
    } catch (e) {
      debugPrint('Snapshot capture error: $e');
    }
  }

  @override
  void dispose() {
    _gpsSubscription?.cancel();
    if (_controller != null && _controller!.value.isStreamingImages) {
      _controller!.stopImageStream();
    }
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    
    // Watch upload queue state to display count
    final uploadQueue = ref.watch(reportUploadServiceProvider);
    
    // Watch TFLite service to see if actual model is active
    final tflite = ref.watch(tfliteServiceProvider);
    final isRealModel = tflite.isModelLoaded;

    return Positioned(
      left: _left,
      top: _top,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _left += details.delta.dx;
            _top += details.delta.dy;

            // Clamp position so the window stays fully on screen
            _left = _left.clamp(8.0, screenSize.width - _width - 8.0);
            _top = _top.clamp(80.0, screenSize.height - _height - 100.0);
          });
        },
        child: Container(
          width: _width,
          height: _height,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.secondary, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 15,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Camera Feed / Loading State
                if (_isInitialized && _controller != null)
                  CameraPreview(_controller!)
                else if (_hasError)
                  _buildErrorPlaceholder()
                else
                  _buildLoadingPlaceholder(),

                // 2. Bounding Box & Confidence Overlay layer
                if (_isInitialized && _detections.isNotEmpty)
                  ..._detections.map((detection) => _buildBoundingBox(context, detection)).toList(),

                // 3. Drag Handle & Grip Indicator (Top)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 24,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 32,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white54,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),

                // 4. REC Recording Alert (Bottom Left)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BlinkingDot(),
                      const SizedBox(width: 4),
                      const Text(
                        'REC',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(color: Colors.black87, blurRadius: 4),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 5. GPS Buffer & Offline Queue Size Counter Overlay (Bottom Right)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Buf: ${_gpsFrameBuffer.length}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: uploadQueue.isEmpty
                              ? Colors.black54
                              : theme.colorScheme.error.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Queue: ${uploadQueue.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 6. AI Model Status Badge (Top Right)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: isRealModel ? Colors.green[800]!.withOpacity(0.85) : Colors.amber[800]!.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isRealModel ? 'YOLOv8 Active' : 'Emulated AI',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBoundingBox(BuildContext context, Detection detection) {
    final rect = detection.rect;
    
    // Scale normalized coordinates to fit the container bounds
    final double leftPos = rect.left * _width;
    final double topPos = rect.top * _height;
    final double widthPos = rect.width * _width;
    final double heightPos = rect.height * _height;

    final color = detection.label == 'Pothole' ? Colors.orange : Colors.yellow[600]!;

    return Positioned(
      left: leftPos,
      top: topPos,
      width: widthPos,
      height: heightPos,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 2),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: -12,
              left: -2,
              child: Container(
                color: color,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Text(
                  '${detection.label} ${(detection.confidence * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 7,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingPlaceholder() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
          SizedBox(height: 8),
          Text(
            'Initializing AI...',
            style: TextStyle(color: Colors.white70, fontSize: 10),
          )
        ],
      ),
    );
  }

  Widget _buildErrorPlaceholder() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off, color: Colors.white54, size: 24),
            SizedBox(height: 8),
            Text(
              'No Camera Feed',
              style: TextStyle(color: Colors.white70, fontSize: 10),
              textAlign: TextAlign.center,
            )
          ],
        ),
      ),
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot> with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    return FadeTransition(
      opacity: _animController,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
