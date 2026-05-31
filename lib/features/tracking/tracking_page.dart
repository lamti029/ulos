import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/survey.dart';
import 'tracking_page_controller.dart';

class TrackingPage extends StatefulWidget {
  final SurveyModel survey;

  const TrackingPage({super.key, required this.survey});

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage>
    with WidgetsBindingObserver {
  late final TrackingPageController controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    controller = TrackingPageController(survey: widget.survey);
    controller.init();
    controller.initializeData();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await controller.getCurrentLocation(context);
      await controller.maybeShowTrackingOver3hPopup(context);
      await controller.maybeTriggerBackgroundReminder();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      await controller.updateTrackingStatus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TrackingPageController>.value(
      value: controller,
      child: Consumer<TrackingPageController>(
        builder: (context, c, _) {
          return Scaffold(
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Live Tracking',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  if (widget.survey.nama != null)
                    Text(
                      widget.survey.nama!.toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 8),
                    ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.sync),
                  onPressed: () => c.syncWilayahData(context),
                  tooltip: 'Sync Wilayah',
                ),
              ],
            ),
            body: c.isLoading
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      FlutterMap(
                        mapController: c.mapController,
                        options: MapOptions(
                          initialCenter:
                              (c.currentPosition != null &&
                                  c.currentPosition!.latitude.isFinite &&
                                  c.currentPosition!.longitude.isFinite)
                              ? c.currentPosition!
                              : const LatLng(-6.2088, 106.8456),
                          initialZoom: 14,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.ulos.app',
                          ),
                          if (c.currentPosition != null)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: c.currentPosition!,
                                  width: 48,
                                  height: 48,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.secondary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 3,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary.withAlpha(
                                            77,
                                          ),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.my_location,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (c.safeWilayahPolygons.isNotEmpty)
                            PolygonLayer(polygons: c.safeWilayahPolygons),
                          if (c.wilayahLabelMarkers.isNotEmpty)
                            MarkerLayer(markers: c.wilayahLabelMarkers),

                          if (c.targetPoints.isNotEmpty)
                            MarkerClusterLayerWidget(
                              options: MarkerClusterLayerOptions(
                                maxClusterRadius: 120,
                                disableClusteringAtZoom: 17,
                                size: const Size(40, 40),
                                alignment: Alignment.center,
                                padding: const EdgeInsets.all(50),
                                maxZoom: 15,
                                markers: c.targetPoints
                                    .asMap()
                                    .entries
                                    .map(
                                      (e) => c.buildTargetMarker(
                                        e.value,
                                        isNearby: false,
                                        index: e.key,
                                        context: context,
                                      ),
                                    )
                                    .toList(),
                                builder: (context, markers) {
                                  return Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      color: AppColors.primary,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withAlpha(77),
                                          blurRadius: 6,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        markers.length.toString(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),

                          if (c.showPetugasLayer) ...[
                            if (c.petugasPolylines.isNotEmpty)
                              PolylineLayer(polylines: c.petugasPolylines),
                            if (c.petugasMarkers.isNotEmpty)
                              MarkerLayer(markers: c.petugasMarkers),
                          ],

                          if (c.showNearbyTargetPoints &&
                              c.targetPointsNearby.isNotEmpty)
                            MarkerClusterLayerWidget(
                              options: MarkerClusterLayerOptions(
                                maxClusterRadius: 120,
                                disableClusteringAtZoom: 17,
                                size: const Size(40, 40),
                                alignment: Alignment.center,
                                padding: const EdgeInsets.all(50),
                                maxZoom: 15,
                                markers: c.targetPointsNearby
                                    .asMap()
                                    .entries
                                    .map(
                                      (e) => c.buildTargetMarker(
                                        e.value,
                                        isNearby: true,
                                        index: e.key,
                                        context: context,
                                      ),
                                    )
                                    .toList(),
                                builder: (context, markers) {
                                  return Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      color: AppColors.primary,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withAlpha(77),
                                          blurRadius: 6,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        markers.length.toString(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),

                      Positioned(
                        bottom: 400,
                        right: 16,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FloatingActionButton.small(
                              heroTag: 'locate',
                              backgroundColor: AppColors.surface,
                              foregroundColor: AppColors.error,
                              onPressed: () => c.getCurrentLocation(context),
                              child: const Icon(Icons.my_location),
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton.small(
                              heroTag: 'zoom_polygon',
                              backgroundColor: AppColors.surface,
                              foregroundColor: AppColors.green,
                              onPressed: () => c.showPolygonSelector(
                                context,
                                c.wilayahPolygons,
                                c.wilayahData,
                                (selected) {
                                  LatLngBounds? bounds;
                                  for (final polygon in selected) {
                                    for (final point in polygon.points) {
                                      if (!point.latitude.isFinite ||
                                          !point.longitude.isFinite) {
                                        continue;
                                      }
                                      final p = LatLng(
                                        point.latitude,
                                        point.longitude,
                                      );
                                      if (bounds == null) {
                                        bounds = LatLngBounds(p, p);
                                      } else {
                                        bounds.extend(p);
                                      }
                                    }
                                  }
                                  if (bounds == null) return;

                                  c.mapController.fitCamera(
                                    CameraFit.bounds(
                                      bounds: bounds,
                                      padding: const EdgeInsets.all(50),
                                    ),
                                  );
                                },
                              ),
                              child: const Icon(Icons.crop_free),
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton.small(
                              heroTag: 'show_target_nearby',
                              backgroundColor: AppColors.surface,
                              foregroundColor: AppColors.primary,
                              onPressed: c.isNearbyLoading
                                  ? null
                                  : () => c.showTargetPointsNearby(context),
                              child: const Icon(Icons.place_outlined),
                            ),
                            if (c.showTrackingPetugasFab()) ...[
                              const SizedBox(height: 8),
                              FloatingActionButton.small(
                                heroTag: 'tracking_petugas',
                                backgroundColor: AppColors.surface,
                                foregroundColor: AppColors.blue,
                                onPressed: () async {
                                  c.showPetugasLayer = !c.showPetugasLayer;
                                  c.notifyListeners();
                                  if (c.showPetugasLayer) {
                                    await c.fetchPetugasIfNeeded(context);
                                    await c
                                        .fetchPetugasLocationsLatestOrFiltered(
                                          context,
                                        );
                                  }
                                },
                                child: const Icon(Icons.person_search_outlined),
                              ),
                            ],
                          ],
                        ),
                      ),

                      if (c.selectedTargetPoint != null && !c.isLocationActive)
                        Positioned(
                          bottom: 88,
                          left: 24,
                          right: 24,
                          child: SafeArea(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                                border: Border.all(
                                  color: AppColors.success.withAlpha(128),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: const BoxDecoration(
                                      color: AppColors.success,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          c.selectedTargetPoint!['nama'] ??
                                              'Titik Sasaran',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        if (c.selectedTargetPoint!['alamat'] !=
                                            null)
                                          Text(
                                            c.selectedTargetPoint!['alamat']
                                                .toString(),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    onPressed: () {
                                      c.selectedTargetPoint = null;
                                      c.notifyListeners();
                                    },
                                    color: AppColors.textSecondary,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            ).animate().fadeIn(duration: 300.ms),
                          ),
                        ),

                      Positioned(
                        bottom: 24,
                        left: 24,
                        right: 24,
                        child: SafeArea(
                          child: ElevatedButton.icon(
                            onPressed: (c.isStartLoading || c.isStopLoading)
                                ? null
                                : () async {
                                    await c.toggleTracking(context);
                                  },
                            icon: (c.isStartLoading || c.isStopLoading)
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    c.isTracking
                                        ? Icons.stop
                                        : Icons.play_arrow,
                                  ),
                            label: Text(
                              c.isStartLoading
                                  ? 'Memulai...'
                                  : c.isStopLoading
                                  ? 'Menghentikan...'
                                  : (c.isTracking
                                        ? 'Stop Tracking'
                                        : 'Start Tracking'),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: c.isTracking
                                  ? AppColors.error
                                  : AppColors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ).animate().fadeIn(duration: 400.ms),
                        ),
                      ),

                      if (c.isTracking)
                        Positioned(
                          top: 16,
                          left: 16,
                          right: 16,
                          child: SafeArea(
                            child:
                                Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.success,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withAlpha(25),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Colors.white,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              c.isSyncActive
                                                  ? 'Tracking aktif: lokasi direkam & sync background aktif.'
                                                  : 'Tracking aktif: lokasi direkam (sync background nonaktif).',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                    .animate()
                                    .fadeIn(duration: 300.ms)
                                    .slideY(
                                      begin: -0.5,
                                      end: 0,
                                      duration: 300.ms,
                                    ),
                          ),
                        ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}
