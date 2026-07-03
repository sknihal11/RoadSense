import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/app_constants.dart';
import '../../../widgets/custom_button.dart';
import '../../road_monitoring/presentation/road_monitoring_provider.dart';
import '../../navigation/presentation/navigation_search_provider.dart';
import '../../../widgets/movable_camera_preview.dart';
import '../../../core/services/geolocator_service.dart';


class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _locationSubscription;
  LatLng? _currentPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocationTracking();
    });
  }

  void _initLocationTracking() {
    final geolocator = ref.read(geolocatorServiceProvider);
    geolocator.getCurrentLocation().then((position) {
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
        });
        _mapController.move(_currentPosition!, 14.5);
      }
    });

    _locationSubscription = geolocator.getLocationStream().listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
        });
      }
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final searchState = ref.watch(navigationSearchProvider);
    final monitoringState = ref.watch(roadMonitoringProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route_rounded, color: theme.colorScheme.primary, size: 28),
            const SizedBox(width: 8),
            const Text(AppConstants.appName),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push(AppConstants.routeSettings),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // 1. OpenStreetMap View as Background
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition ?? const LatLng(18.0528, 83.4198), // Starts near MVGR College
              initialZoom: 14.0,
              minZoom: 9.0,
              maxZoom: 18.0,
              cameraConstraint: CameraConstraint.contain(
                bounds: LatLngBounds(
                  const LatLng(17.55, 83.00),
                  const LatLng(18.25, 83.60),
                ),
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.roadsense_ai',
              ),
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition!,
                      width: 44,
                      height: 44,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.25),
                                  blurRadius: 5,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // 2. Floating Top Search Card
          Positioned(
            top: 10,
            left: 12,
            right: 12,
            child: _buildNavigationCard(context, ref, searchState),
          ),

          // 3. Floating Bottom Monitoring Card
          Positioned(
            bottom: 10,
            left: 12,
            right: 12,
            child: _buildRoadMonitoringCard(context, ref, monitoringState),
          ),

          // 4. Centering FAB
          if (_currentPosition != null)
            Positioned(
              right: 16,
              bottom: monitoringState.isMonitoring ? 290 : 190,
              child: FloatingActionButton(
                heroTag: 'home_center_location_fab',
                onPressed: () {
                  _mapController.move(_currentPosition!, 15.5);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Centering on location near MVGR College'),
                      duration: Duration(milliseconds: 1000),
                    ),
                  );
                },
                backgroundColor: theme.colorScheme.surface,
                foregroundColor: theme.colorScheme.primary,
                mini: true,
                child: const Icon(Icons.my_location),
              ),
            ),

          // 5. Movable Camera PiP Overlay
          if (monitoringState.isMonitoring)
            const MovableCameraPreview(),
        ],
      ),
    );
  }

  Widget _buildNavigationCard(
    BuildContext context,
    WidgetRef ref,
    NavigationSearchState searchState,
  ) {
    final theme = Theme.of(context);
    final searchNotifier = ref.read(navigationSearchProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'Enter destination...',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                suffixIcon: searchState.query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => searchNotifier.clearSearch(),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              controller: TextEditingController.fromValue(
                TextEditingValue(
                  text: searchState.query,
                  selection: TextSelection.collapsed(offset: searchState.query.length),
                ),
              ),
              onChanged: (val) => searchNotifier.updateQuery(val),
            ),
            if (searchState.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6.0),
                child: LinearProgressIndicator(),
              ),
            if (searchState.suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: searchState.suggestions.length,
                  itemBuilder: (context, index) {
                    final suggestion = searchState.suggestions[index];
                    return ListTile(
                      dense: true,
                      title: Text(suggestion, style: const TextStyle(fontSize: 14)),
                      onTap: () {
                        searchNotifier.selectDestination(suggestion);
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 10),
            CustomButton(
              text: 'Get Directions',
              icon: Icons.directions,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              onPressed: searchState.selectedDestination != null
                  ? () {
                      context.push(
                        AppConstants.routeNavigation,
                        extra: searchState.selectedDestination,
                      );
                    }
                  : null, // Disabled if no destination selected
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoadMonitoringCard(
    BuildContext context,
    WidgetRef ref,
    RoadMonitoringState monitoringState,
  ) {
    final theme = Theme.of(context);
    final monitoringNotifier = ref.read(roadMonitoringProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.camera_enhance,
                        color: monitoringState.isMonitoring
                            ? theme.colorScheme.secondary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Background Road Monitoring',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: monitoringState.isMonitoring,
                  onChanged: (val) => monitoringNotifier.toggleMonitoring(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Enables dashboard camera and local AI (YOLOv8 Nano) to dynamically scan for road anomalies while driving.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
              ),
            ),
            if (monitoringState.isMonitoring) ...[
              const Divider(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Simulated PiP (Picture in Picture) Camera stream preview
                  Expanded(
                    flex: 4,
                    child: Container(
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.secondary, width: 2),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'REC',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.videocam, color: Colors.white54, size: 28),
                              SizedBox(height: 4),
                              Text(
                                'PiP Cam Mode Active',
                                style: TextStyle(color: Colors.white70, fontSize: 10),
                              ),
                            ],
                          ),
                          Positioned(
                            bottom: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              color: Colors.black54,
                              child: Text(
                                '${monitoringState.currentLatitude.toStringAsFixed(4)}, ${monitoringState.currentLongitude.toStringAsFixed(4)}',
                                style: const TextStyle(color: Colors.white54, fontSize: 8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Real-time AI detection counts
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStatRow(context, Icons.warning_amber_rounded, Colors.orange,
                            'Potholes Detected: ${monitoringState.detectedPotholes}'),
                        const SizedBox(height: 8),
                        _buildStatRow(context, Icons.broken_image_outlined, Colors.yellow[700]!,
                            'Cracks Detected: ${monitoringState.detectedCracks}'),
                        const SizedBox(height: 12),
                        Text(
                          monitoringState.statusMessage,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(BuildContext context, IconData icon, Color color, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildRegionalSafetyCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.shield_outlined, color: theme.colorScheme.primary, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Regional Safety Index',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Safety Status: Excellent\n12 anomalies verified near Visakhapatnam.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
