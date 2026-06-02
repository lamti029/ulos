import 'dart:async';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';

import '../../core/models/petugas_location.dart' as petugas_location;
import '../../core/models/survey.dart';
import '../../core/services/background_service_handler.dart';
import '../../core/services/dio_client.dart';
import '../../core/services/env_service.dart';
import '../../core/services/location_repository.dart';
import '../../core/services/location_service.dart';
import '../../core/services/scheduler_service.dart';
import '../../core/services/wilayah_service.dart';
import '../../core/controllers/tracking_controller.dart';

import '../pemeriksa/petugas_tracking_page.dart';

class TrackingPageController extends ChangeNotifier {
  TrackingPageController({required this.survey});

  // NOTE: controller is instantiated per page instance.

  final SurveyModel survey;

  static const Duration trackingMaxDuration = Duration(hours: 3);

  static const String prefsTrackingStartedAtMs = 'tracking_started_at_ms';
  static const String prefsTracking3hLastReminderAtMs =
      'tracking_3h_last_reminder_at_ms';

  static const Duration reminderCooldown = Duration(minutes: 30);

  final FlutterLocalNotificationsPlugin localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  AndroidNotificationDetails? androidDetails;
  NotificationDetails? notificationDetails;

  late final SchedulerService schedulerService;

  final LocationService locationService = LocationService();

  final MapController mapController = MapController();

  LatLng? currentPosition;

  // Petugas tracking layer
  bool showPetugasLayer = false;
  bool isPetugasLoading = false;

  final List<_PetugasListItem> petugas = [];
  int? selectedPetugasId;

  final List<petugas_location.PetugasLocation> petugasLocations = [];
  List<Marker> petugasMarkers = const [];
  List<Polyline> petugasPolylines = const [];

  // Wilayah data
  List<Polygon> wilayahPolygons = [];
  List<Map<String, dynamic>> wilayahData = [];

  List<Map<String, dynamic>> initialTargetPoints = [];
  List<Map<String, dynamic>> nearbyTargetPoints = [];
  bool showNearbyTargetPoints = false;
  List<Map<String, dynamic>> targetPoints = [];
  List<Map<String, dynamic>> targetPointsNearby = [];

  LatLng? lastNearbyCenter;
  bool isNearbyLoading = false;
  final double nearbyMinDistanceMeters = 100.0;

  // Target selection
  Map<String, dynamic>? selectedTargetPoint;

  bool isLoading = true;
  bool isLocationActive = false;
  bool isSyncActive = false;

  bool isStartLoading = false;
  bool isStopLoading = false;
  int locationInterval = AppConstants.defaultLocationInterval;
  int batchInterval = AppConstants.defaultBatchInterval;

  // Misc UI flags
  bool isDisposed = false;
  bool mapHasRendered = false;
  Timer? trackingStatusTimer;

  List<Map<String, dynamic>> get initialTargetPointsSafe => initialTargetPoints;

  List<Polygon> get safeWilayahPolygons {
    if (wilayahPolygons.isEmpty) return const <Polygon>[];

    final result = <Polygon>[];
    for (final polygon in wilayahPolygons) {
      final safePoints = <LatLng>[];
      for (final p in polygon.points) {
        final lat = p.latitude;
        final lng = p.longitude;
        if (!lat.isFinite || !lng.isFinite) continue;
        safePoints.add(LatLng(lat, lng));
      }
      if (safePoints.length >= 3) {
        result.add(
          Polygon(
            points: safePoints,
            color: polygon.color,
            borderColor: polygon.borderColor,
            borderStrokeWidth: polygon.borderStrokeWidth,
          ),
        );
      }
    }
    return result;
  }

  bool get isTracking => _getIsTrackingForThisSurvey();

  bool _getIsTrackingForThisSurvey() {
    // Pastikan state dari TrackingController tidak stale ketika halaman
    // baru dibuka / app resume.
    final activeId = TrackingController.instance.activeSurveiId;
    if (activeId == null) return false;
    return survey.id == activeId;
  }

  bool _isFiniteLatLng(LatLng l) => l.latitude.isFinite && l.longitude.isFinite;

  bool showTrackingPetugasFab() {
    final rawRole = survey.roleInSurvei?.toString();
    final role = rawRole
        ?.toLowerCase()
        .trim()
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('"', '')
        .replaceAll("'", '');

    return role == 'pemeriksa';
  }

  void init() {
    schedulerService = SchedulerService.instance;

    // Refresh state global tracking terlebih dahulu agar tombol tidak
    // salah (mis. survey A sudah stop tapi halaman survey B tetap tampil Stop).
    _refreshGlobalTrackingStateThenEnsure();
  }

  LatLngBounds? _buildPetugasLocationsBounds() {
    LatLngBounds? bounds;

    // flutter_map sometimes produces NaN/Infinity zoom when bounds are
    // extremely small (e.g., only 1 point). We handle that by returning a
    // “slightly expanded” bounds when needed.
    const double minDelta = 0.0005; // ~55m at equator

    for (final loc in petugasLocations) {
      final lat = loc.latitude;
      final lng = loc.longitude;
      if (lat == null || lng == null) continue;
      if (!_isFiniteLatLng(LatLng(lat, lng))) continue;
      final p = LatLng(lat, lng);
      if (bounds == null) {
        bounds = LatLngBounds(p, p);
      } else {
        bounds.extend(p);
      }
    }

    if (bounds == null) return null;

    final latSpan = (bounds.north - bounds.south).abs();
    final lngSpan = (bounds.east - bounds.west).abs();

    if (latSpan < minDelta || lngSpan < minDelta) {
      final center = LatLng(
        (bounds.north + bounds.south) / 2,
        (bounds.east + bounds.west) / 2,
      );
      final ne = LatLng(
        center.latitude + minDelta,
        center.longitude + minDelta,
      );
      final sw = LatLng(
        center.latitude - minDelta,
        center.longitude - minDelta,
      );
      return LatLngBounds(sw, ne);
    }

    return bounds;
  }

  Future<void> moveCameraToPetugasLayer({double paddingMeters = 50}) async {
    if (petugasLocations.isEmpty) return;

    final bounds = _buildPetugasLocationsBounds();
    if (bounds == null) return;

    // Delay 1 frame so flutter_map tile/zoom calculations are ready.
    // Prevents NaN/Infinity zoom causing: “Unsupported operation: Infinity or NaN toInt”.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // IMPORTANT: fitCamera.bounds keeps all petugas markers visible (multiple petugas).
    mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        // flutter_map CameraFit.padding is pixel padding, not meters.
        padding: EdgeInsets.all(paddingMeters),
      ),
    );
  }

  Future<void> _refreshGlobalTrackingStateThenEnsure() async {
    try {
      await TrackingController.instance.init();
    } catch (_) {
      // no-op
    }
    await _ensureNoStaleBackgroundThenUpdateStatus();
  }

  Future<void> ensureNoStaleBackgroundThenUpdateStatus() async {
    await _ensureNoStaleBackgroundThenUpdateStatus();
  }

  Future<void> _ensureNoStaleBackgroundThenUpdateStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final isFirstLaunch =
          prefs.getBool('is_first_launch_after_install') ?? true;

      if (isFirstLaunch) {
        await BackgroundServiceHandler.ensureNotRunning();
        try {
          await schedulerService.stop();
        } catch (_) {}

        await prefs.setBool('is_first_launch_after_install', false);
        await prefs.setBool('isTracking', false);
      } else {
        final schedulerRunningInitial = await SchedulerService.isRunning;
        final bgRunningInitial = await BackgroundServiceHandler.isRunning();
        if (bgRunningInitial && !schedulerRunningInitial) {
          await BackgroundServiceHandler.ensureNotRunning();
        }
      }

      const recheckCount = 3;
      const recheckDelay = Duration(milliseconds: 200);
      var stableBgRunning = false;

      for (var i = 0; i < recheckCount; i++) {
        await Future.delayed(recheckDelay);
        final bg = await BackgroundServiceHandler.isRunning();
        stableBgRunning = i == 0 ? bg : (stableBgRunning && bg);
      }

      final schedulerRunningFinal = await SchedulerService.isRunning;
      if (!schedulerRunningFinal && stableBgRunning) {
        await BackgroundServiceHandler.ensureNotRunning();
      }
    } catch (_) {}

    await updateTrackingStatus();
  }

  Future<void> updateTrackingStatus() async {
    // Sync state global agar activeSurveiId sesuai prefs terbaru.
    // (mis. user close page lalu buka lagi untuk survei lain)
    try {
      await TrackingController.instance.init();
    } catch (_) {
      // no-op
    }

    final schedulerRunning = await SchedulerService.isRunning;
    final locationActive = schedulerRunning;
    final syncActive = locationActive && EnvService.syncIntervalSeconds > 0;

    isLocationActive = locationActive;
    isSyncActive = syncActive;
    survey.isTrackingActive = locationActive && syncActive;

    notifyListeners();
  }

  Future<void> initializeData() async {
    await WilayahService.ensureInitialized();
    wilayahPolygons = WilayahService.wilayahPolygons;
    wilayahData = WilayahService.wilayahData;

    initialTargetPoints = WilayahService.targetPoints;
    targetPoints = initialTargetPoints;
    isLoading = false;

    notifyListeners();
  }

  Future<void> getCurrentLocation(BuildContext context) async {
    final position = await locationService.getCurrentPosition();
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal mendapatkan lokasi. Pastikan GPS aktif.'),
          backgroundColor: AppColors.error,
        ),
      );
      isStartLoading = false;
      notifyListeners();
      return;
    }

    if (isDisposed) return;

    final currentLatLng = LatLng(position.latitude, position.longitude);
    if (!_isFiniteLatLng(currentLatLng)) {
      return;
    }

    currentPosition = currentLatLng;
    isLoading = false;

    notifyListeners();

    // Always move camera when user taps locate / when we have a valid location.
    // (mapHasRendered is not reliably set, so gating camera movement can prevent locate from working.)
    mapController.move(currentLatLng, 15);
  }

  Future<bool> isOtherSurveiLockedAndRunning() async {
    final running = await SchedulerService.isRunning;
    if (!running) return false;

    final lockId = TrackingController.instance.activeSurveiId;
    if (lockId == null) return false;
    return lockId != survey.id;
  }

  Future<void> maybeShowTrackingOver3hPopup(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();

    final schedulerRunning = await SchedulerService.isRunning;
    if (!schedulerRunning) return;

    final startedAtMs = prefs.getInt(prefsTrackingStartedAtMs);
    if (startedAtMs == null) return;

    final startedAt = DateTime.fromMillisecondsSinceEpoch(startedAtMs);
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < trackingMaxDuration) return;

    final alreadyShown = prefs.getBool('tracking_3h_popup_shown') ?? false;
    if (alreadyShown) return;

    await prefs.setBool('tracking_3h_popup_shown', true);

    // keep dialog behavior identical: still call toggleTracking
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Tracking > 3 jam'),
          content: const Text(
            'Tracking Anda sudah berjalan lebih dari 3 jam. '
            'Apakah akan melanjutkan tracking atau berhenti?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Lanjutkan'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await toggleTracking(context);
              },
              child: const Text('Berhenti Tracking'),
            ),
          ],
        );
      },
    );
  }

  Future<void> maybeTriggerBackgroundReminder() async {
    final prefs = await SharedPreferences.getInstance();

    final schedulerRunning = await SchedulerService.isRunning;
    if (!schedulerRunning) return;

    final startedAtMs = prefs.getInt(prefsTrackingStartedAtMs);
    if (startedAtMs == null) return;

    final startedAt = DateTime.fromMillisecondsSinceEpoch(startedAtMs);
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < trackingMaxDuration) return;

    final lastReminderMs = prefs.getInt(prefsTracking3hLastReminderAtMs) ?? 0;
    final lastReminder = lastReminderMs == 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lastReminderMs);

    if (lastReminder != null) {
      final since = DateTime.now().difference(lastReminder);
      if (since < reminderCooldown) return;
    }

    androidDetails ??= const AndroidNotificationDetails(
      'tracking_reminders',
      'Tracking Reminders',
      channelDescription: 'Reminder saat tracking berjalan lama',
      importance: Importance.high,
      priority: Priority.high,
      playSound: false,
    );

    notificationDetails ??= NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
    );

    final now = DateTime.now();
    final notifId = now.millisecondsSinceEpoch.remainder(1000000);

    await localNotificationsPlugin.show(
      notifId,
      'Reminder Tracking',
      'Tracking Anda sudah lebih dari 3 jam. '
          'Pertimbangkan untuk berhenti agar sesuai kebutuhan.',
      notificationDetails!,
    );

    await prefs.setInt(
      prefsTracking3hLastReminderAtMs,
      now.millisecondsSinceEpoch,
    );
  }

  Future<List<Map<String, dynamic>>> fetchNearbyTargetPoints({
    required double lat,
    required double lng,
    required int surveiId,
  }) async {
    const int limit = 20;
    final allPoints = <Map<String, dynamic>>[];

    try {
      final dioClient = DioClient();

      final firstResponse = await dioClient.dio.get(
        'https://trackingapi.bps.web.id/api/titik-sasaran/nearby',
        queryParameters: {
          'lat': lat,
          'lng': lng,
          'radius': 100,
          'survei_id': surveiId,
          'page': 1,
          'limit': limit,
        },
      );

      if (firstResponse.statusCode != 200) return allPoints;

      final firstData = List<Map<String, dynamic>>.from(
        firstResponse.data['data'] ?? [],
      );
      allPoints.addAll(firstData);

      final totalPages =
          firstResponse.data['meta']?['pagination']?['total_pages'] ?? 1;

      if (totalPages > 1) {
        final futures = <Future<dynamic>>[];
        for (int page = 2; page <= totalPages; page++) {
          futures.add(
            dioClient.dio.get(
              'https://trackingapi.bps.web.id/api/titik-sasaran/nearby',
              queryParameters: {
                'lat': lat,
                'lng': lng,
                'radius': 100,
                'survei_id': surveiId,
                'page': page,
                'limit': limit,
              },
            ),
          );
        }

        final responses = await Future.wait(futures);
        for (final r in responses) {
          if (r.statusCode == 200) {
            allPoints.addAll(
              List<Map<String, dynamic>>.from(r.data['data'] ?? []),
            );
          }
        }
      }
    } catch (_) {
      return allPoints;
    }

    return allPoints
        .map((p) {
          final latVal = (p['latitude'] ?? p['lat'] ?? p['point_lat'])
              ?.toString();
          final lngVal = (p['longitude'] ?? p['lng'] ?? p['point_lng'])
              ?.toString();

          return <String, dynamic>{
            ...p,
            'id': p['id'] ?? p['titik_id'] ?? p['titik_sasaran_id'],
            'nama': p['nama'] ?? p['nama_titik'] ?? p['titik_sasaran'],
            'latitude': latVal != null ? double.tryParse(latVal) : null,
            'longitude': lngVal != null ? double.tryParse(lngVal) : null,
          };
        })
        .where((p) {
          final latOk = (p['latitude'] as double?) != null;
          final lngOk = (p['longitude'] as double?) != null;
          return latOk && lngOk;
        })
        .toList();
  }

  double distanceMeters(LatLng a, LatLng b) {
    const double earthRadius = 6371000.0;
    final dLat = (b.latitude - a.latitude) * (math.pi / 180.0);
    final dLng = (b.longitude - a.longitude) * (math.pi / 180.0);
    final lat1 = a.latitude * (math.pi / 180.0);
    final lat2 = b.latitude * (math.pi / 180.0);

    final sinDLat = math.sin(dLat / 2.0);
    final sinDLng = math.sin(dLng / 2.0);

    final h =
        sinDLat * sinDLat +
        sinDLng * sinDLng * (math.cos(lat1) * math.cos(lat2));

    return 2.0 * earthRadius * math.sqrt(h);
  }

  Future<void> showTargetPointsNearby(BuildContext context) async {
    final position = await locationService.getCurrentPosition();
    if (isDisposed || !isLoading) {
      // no-op
    }

    if (position == null) {
      if (!isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal mendapatkan lokasi. Pastikan GPS aktif.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      isStartLoading = false;
      notifyListeners();
      return;
    }

    final currentLatLng = LatLng(position.latitude, position.longitude);
    if (!_isFiniteLatLng(currentLatLng)) return;

    mapController.move(currentLatLng, 15);

    final shouldRefetch =
        lastNearbyCenter == null ||
        distanceMeters(lastNearbyCenter!, currentLatLng) >=
            nearbyMinDistanceMeters;

    try {
      if (shouldRefetch) {
        isNearbyLoading = true;
        notifyListeners();

        final nearby = await fetchNearbyTargetPoints(
          lat: currentLatLng.latitude,
          lng: currentLatLng.longitude,
          surveiId: survey.id,
        );

        if (isDisposed) return;

        nearbyTargetPoints = nearby;
        lastNearbyCenter = currentLatLng;
      }

      showNearbyTargetPoints = true;
      targetPointsNearby = nearbyTargetPoints;
    } finally {
      isNearbyLoading = false;
    }

    notifyListeners();
  }

  bool isValidLatLng(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (!lat.isFinite || !lng.isFinite) return false;
    return lat.abs() <= 90 && lng.abs() <= 180;
  }

  String? formatTimestamp(DateTime? dt) {
    if (dt == null) return null;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> postAbsensi(String action) async {
    try {
      final dioClient = DioClient();
      await dioClient.dio.post(
        '/api/absensi/$action',
        data: {'survei_id': survey.id},
        options: Options(headers: const {'accept': 'application/json'}),
      );
    } catch (_) {}
  }

  Future<void> toggleTracking(BuildContext context) async {
    final shouldLock = await isOtherSurveiLockedAndRunning();
    if (shouldLock) {
      if (!isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Tracking sedang aktif pada survei lain. Start/Stop diblokir.',
            ),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    final battery = Battery();

    if (isTracking) {
      isStopLoading = true;
      notifyListeners();

      try {
        final position = await locationService.getCurrentPosition().timeout(
          const Duration(seconds: 7),
        );

        if (position != null) {
          final lastLocation = {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'accuracy': position.accuracy,
            'altitude': position.altitude,
            'speed': position.speed,
            'is_mocked': position.isMocked,
            'survei_id': survey.id,
            'battery_level': battery.batteryLevel,
            'timestamp': position.timestamp.toUtc().toIso8601String(),
          };
          await schedulerService.sendImmediateBatch(locations: [lastLocation]);
        }
      } on TimeoutException {
        // ignore
      } catch (_) {
      } finally {
        try {
          await schedulerService.stop().timeout(const Duration(seconds: 8));
        } on TimeoutException {
          // ignore
        } catch (_) {}

        await postAbsensi('stop');
        survey.isTrackingActive = false;

        if (TrackingController.instance.activeSurveiId == survey.id) {
          TrackingController.instance.clear();
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_tracking', false);
        await prefs.remove(prefsTrackingStartedAtMs);
        await prefs.remove('tracking_3h_popup_shown');
        await prefs.remove(prefsTracking3hLastReminderAtMs);

        await updateTrackingStatus();
        isStopLoading = false;
        notifyListeners();
      }
      return;
    }

    isStartLoading = true;
    notifyListeners();

    try {
      final position = await locationService.getCurrentPosition();
      if (position == null) {
        if (!isDisposed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gagal mendapatkan lokasi. Pastikan GPS aktif.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        isStartLoading = false;
        notifyListeners();
        return;
      }

      final prefs = await SharedPreferences.getInstance();

      survey.isTrackingActive = true;
      TrackingController.instance.lockTo(survey.id);

      await prefs.setInt(
        prefsTrackingStartedAtMs,
        DateTime.now().millisecondsSinceEpoch,
      );
      await prefs.remove('tracking_3h_popup_shown');
      await prefs.remove(prefsTracking3hLastReminderAtMs);

      try {
        await LocationRepository().deleteSyncedForDay(
          DateTime.now().subtract(const Duration(days: 1)),
        );
      } catch (_) {}

      await postAbsensi('start');

      final firstLocation = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'speed': position.speed,
        'is_mocked': position.isMocked,
        'battery_level': battery.batteryLevel,
        'timestamp': position.timestamp.toUtc().toIso8601String(),
      };

      await schedulerService.sendImmediateBatch(locations: [firstLocation]);

      schedulerService.start(
        locationIntervalSeconds: locationInterval,
        batchIntervalSeconds: batchInterval,
        surveiId: survey.id,
      );

      await updateTrackingStatus();
    } catch (e) {
      if (!isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memulai tracking: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      isStartLoading = false;
      notifyListeners();
    }
  }

  Marker buildPetugasMarker(
    petugas_location.PetugasLocation loc,
    int index,
    BuildContext context,
  ) {
    final lat = (loc.latitude ?? 0.0);
    final lng = (loc.longitude ?? 0.0);
    final nama = (loc.namaPetugas ?? 'Petugas').trim();
    final timestampStr = formatTimestamp(loc.timestamp);
    final bool isMocked = loc.isMocked == true;

    return Marker(
      key: ValueKey('${loc.id ?? index}_$lat,$lng'),
      point: LatLng(lat, lng),
      width: 44,
      height: 44,
      child: GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: Stack(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(right: 40.0, top: 4.0),
                      child: Text('Lokasi Petugas'),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(
                          Icons.close,
                          color: Colors.red,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nama: $nama'),
                    if (timestampStr != null) Text('Waktu: $timestampStr'),
                    Text('Lat: ${lat.toStringAsFixed(6)}'),
                    Text('Lng: ${lng.toStringAsFixed(6)}'),
                    if (loc.accuracy != null)
                      Text('Akurasi: ${loc.accuracy} m'),
                    if (loc.batteryLevel != null)
                      Text('Baterai: ${loc.batteryLevel}%'),
                    Text('Mock: ${isMocked ? 'Ya' : 'Tidak'}'),
                  ],
                ),
                actions: [
                  if (loc.userId != null || loc.id != null)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.track_changes),
                      label: const Text('Track'),
                      onPressed: () async {
                        final petugasId = (loc.userId ?? loc.id);
                        if (petugasId == null) return;

                        Navigator.pop(context);

                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PetugasTrackingPage(surveiId: survey.id),
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: isMocked ? Colors.redAccent : Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(60),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.person, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  List<Marker> buildPetugasMarkers(BuildContext context) {
    return petugasLocations
        .asMap()
        .entries
        .map((entry) => buildPetugasMarker(entry.value, entry.key, context))
        .toList();
  }

  List<Polyline> buildPetugasPolylines() {
    if (petugasLocations.length < 2) return const [];

    // Polyline dibuat berdasarkan petugas, tetapi key harus konsisten dengan
    // payload API. Di response lokasi ada `user_id` untuk user/petugas.
    // Di model: userId diambil dari json['user_id'].
    //
    // Kalau sebelumnya key pakai (userId ?? id) maka bisa terjadi pemecahan
    // segmen karena `id` adalah id record, bukan id petugas.
    final Map<int, List<petugas_location.PetugasLocation>> byPetugas = {};

    for (final loc in petugasLocations) {
      final key = loc.userId;
      if (key == null) continue;
      byPetugas
          .putIfAbsent(key, () => <petugas_location.PetugasLocation>[])
          .add(loc);
    }

    // Kalau ternyata semua loc tidak punya userId (mis. field berbeda),
    // fallback agar tetap bisa menggambar.
    if (byPetugas.isEmpty) {
      final sorted = petugasLocations
        ..sort((a, b) {
          final ta = a.timestamp;
          final tb = b.timestamp;
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return ta.compareTo(tb);
        });

      final points = sorted
          .where((p) => p.latitude != null && p.longitude != null)
          .map((p) => LatLng(p.latitude!, p.longitude!))
          .toList();

      if (points.length < 2) return const [];

      return [
        Polyline(
          points: points,
          strokeWidth: 4,
          color: Colors.blue.withAlpha(220),
          borderColor: Colors.white.withAlpha(200),
          borderStrokeWidth: 1.5,
        ),
      ];
    }

    final polylines = <Polyline>[];
    for (final entry in byPetugas.entries) {
      final list = entry.value
        ..sort((a, b) {
          final ta = a.timestamp;
          final tb = b.timestamp;
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return ta.compareTo(tb);
        });

      final points = list
          .where((p) => p.latitude != null && p.longitude != null)
          .map((p) => LatLng(p.latitude!, p.longitude!))
          .toList();

      if (points.length < 2) continue;

      polylines.add(
        Polyline(
          points: points,
          strokeWidth: 4,
          color: Colors.blue.withAlpha(220),
          borderColor: Colors.white.withAlpha(200),
          borderStrokeWidth: 1.5,
        ),
      );
    }

    return polylines;
  }

  Future<void> fetchPetugasIfNeeded(BuildContext context) async {
    if (petugas.isNotEmpty) return;
    if (isPetugasLoading) return;

    isPetugasLoading = true;
    notifyListeners();

    try {
      final res = await DioClient().dio.get(
        '/api/pemeriksa/petugas',
        queryParameters: {'page': 1, 'limit': 20, 'survei_id': survey.id},
      );

      if (res.statusCode != 200) return;

      final payload = res.data;
      final List<dynamic> rawList =
          (payload is Map<String, dynamic> && payload['data'] is List)
          ? (payload['data'] as List<dynamic>)
          : payload is List
          ? payload
          : [];

      // This page only uses first item to set selection.
      if (rawList.isNotEmpty) {
        petugas.clear();
        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            petugas.add(_PetugasListItem.fromJson(item));
          }
        }

        if (selectedPetugasId == null && petugas.isNotEmpty) {
          selectedPetugasId = petugas.first.id;
        }
      }
    } catch (_) {
    } finally {
      isPetugasLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchPetugasLocationsLatestOrFiltered(
    BuildContext context,
  ) async {
    if (!context.mounted) return;

    try {
      if (selectedPetugasId == null) {
        final res = await DioClient().dio.get(
          '/api/pemeriksa/lokasi/terbaru',
          queryParameters: {'survei_id': survey.id},
        );

        if (res.statusCode != 200 && res.statusCode != 201) return;

        final data = res.data;
        final listRaw = data is Map<String, dynamic>
            ? (data['data'] ?? [])
            : [];
        final rawList = listRaw is List ? listRaw : [];

        final parsed = rawList
            .whereType<Map<String, dynamic>>()
            .map((e) => petugas_location.PetugasLocation.fromJson(e))
            .where((p) => isValidLatLng(p.latitude, p.longitude))
            .toList();

        petugasLocations
          ..clear()
          ..addAll(parsed);
        petugasMarkers = buildPetugasMarkers(context);
        petugasPolylines = buildPetugasPolylines();
        notifyListeners();
        return;
      }

      final res = await DioClient().dio.get(
        '/api/pemeriksa/lokasi',
        queryParameters: {
          'page': 1,
          'limit': 50,
          'petugas_id': selectedPetugasId,
          'survei_id': survey.id,
        },
      );

      if (res.statusCode != 200 && res.statusCode != 201) return;

      final data = res.data;
      final listRaw = data is Map<String, dynamic> ? (data['data'] ?? []) : [];
      final rawList = listRaw is List ? listRaw : [];

      final parsed = rawList
          .whereType<Map<String, dynamic>>()
          .map((e) => petugas_location.PetugasLocation.fromJson(e))
          .where((p) => isValidLatLng(p.latitude, p.longitude))
          .toList();

      petugasLocations
        ..clear()
        ..addAll(parsed);
      petugasMarkers = buildPetugasMarkers(context);
      petugasPolylines = buildPetugasPolylines();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> syncWilayahData(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getInt('last_wilayah_sync') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 86400000;
    final lastDay = lastSync ~/ 86400000;

    if (now <= lastDay) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync available once per day. Try tomorrow.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    await WilayahService.clear();
    await WilayahService.init();
    await prefs.setInt(
      'last_wilayah_sync',
      DateTime.now().millisecondsSinceEpoch,
    );

    wilayahPolygons = WilayahService.wilayahPolygons;
    wilayahData = WilayahService.wilayahData;
    initialTargetPoints = WilayahService.targetPoints;
    targetPoints = initialTargetPoints;

    notifyListeners();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Wilayah & Target Points refreshed from server!'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  LatLng calculateCentroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(0, 0);
    if (points.length == 1) return points.first;

    var latSum = 0.0;
    var lngSum = 0.0;
    for (final point in points) {
      latSum += point.latitude;
      lngSum += point.longitude;
    }
    return LatLng(latSum / points.length, lngSum / points.length);
  }

  List<Marker> get wilayahLabelMarkers {
    if (wilayahPolygons.isEmpty || wilayahData.isEmpty) return [];

    final List<Marker> markers = [];
    for (int i = 0; i < wilayahPolygons.length; i++) {
      final polygon = wilayahPolygons[i];
      final itemData = i < wilayahData.length ? wilayahData[i] : null;
      final idSubSLS = itemData?['id_subsls']?.toString() ?? 'Wilayah ${i + 1}';

      if (idSubSLS.isNotEmpty && idSubSLS != 'Wilayah ${i + 1}') {
        final centroid = calculateCentroid(polygon.points);
        markers.add(
          Marker(
            point: centroid,
            width: 120,
            height: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(230),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(51),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                idSubSLS,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
      }
    }
    return markers;
  }

  void showTargetPointDetail(BuildContext context, Map<String, dynamic> point) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.7,
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.textSecondary.withAlpha(77),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      point['nama'] ?? 'Titik Sasaran',
                      style: Theme.of(dialogContext).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    if (point['alamat'] != null &&
                        point['alamat'].toString().isNotEmpty)
                      _buildDetailRow(
                        Icons.location_on,
                        point['alamat'].toString(),
                      ),
                    if (point['kategori'] != null &&
                        point['kategori'].toString().isNotEmpty)
                      _buildDetailRow(
                        Icons.category,
                        'Kategori: ${point['kategori']}',
                      ),
                    if (point['kbli'] != null &&
                        point['kbli'].toString().isNotEmpty)
                      _buildDetailRow(Icons.business, 'KBLI: ${point['kbli']}'),
                    if (point['hp'] != null &&
                        point['hp'].toString().isNotEmpty)
                      _buildDetailRow(
                        Icons.phone_android,
                        'HP: ${point['hp']}',
                      ),
                    if (point['telp'] != null &&
                        point['telp'].toString().isNotEmpty)
                      _buildDetailRow(Icons.phone, 'Telp: ${point['telp']}'),
                    if (point['email'] != null &&
                        point['email'].toString().isNotEmpty)
                      _buildDetailRow(Icons.email, 'Email: ${point['email']}'),
                    if (point['kode'] != null &&
                        point['kode'].toString().isNotEmpty)
                      _buildDetailRow(Icons.qr_code, 'Kode: ${point['kode']}'),
                    if (point['kecamatan'] != null &&
                        point['kecamatan'].toString().isNotEmpty)
                      _buildDetailRow(
                        Icons.map,
                        'Kecamatan: ${point['kecamatan']}',
                      ),
                    if (point['desa'] != null &&
                        point['desa'].toString().isNotEmpty)
                      _buildDetailRow(Icons.home, 'Desa: ${point['desa']}'),
                    if (point['kabupaten'] != null &&
                        point['kabupaten'].toString().isNotEmpty)
                      _buildDetailRow(
                        Icons.location_city,
                        'Kabupaten: ${point['kabupaten']}',
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(dialogContext),
                        label: const Text('Close'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.secondary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Marker buildTargetMarker(
    Map<String, dynamic> point, {
    required bool isNearby,
    required int index,
    required BuildContext context,
  }) {
    final lat = (point['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (point['longitude'] as num?)?.toDouble() ?? 0.0;

    final bool isSelected =
        selectedTargetPoint != null &&
        selectedTargetPoint!['id'] == point['id'];

    final Color baseColor = isNearby ? AppColors.secondary : AppColors.primary;

    final compositeKey = (point['id'] != null)
        ? '${point['id']}_$lat,$lng'
        : 'fallback_${lat},$lng';

    return Marker(
      key: ValueKey('${compositeKey}_${isNearby ? 'near' : 'init'}_$index'),
      point: LatLng(lat, lng),
      width: 44,
      height: 44,
      child: GestureDetector(
        onTap: () => showTargetPointDetail(context, point),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? AppColors.success : baseColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: isSelected ? 3 : 2),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.success.withAlpha(128),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            isSelected ? Icons.check_circle : Icons.location_on,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }

  // Target marker building uses page context; keep here only as a helper.

  // Map selector + zoom kept in page for simplicity.

  LatLngBounds? _buildPolygonBounds(List<Polygon> selectedPolygons) {
    LatLngBounds? bounds;
    for (final polygon in selectedPolygons) {
      for (final point in polygon.points) {
        if (!_isFiniteLatLng(point)) continue;
        if (bounds == null) {
          bounds = LatLngBounds(point, point);
        } else {
          bounds.extend(point);
        }
      }
    }
    return bounds;
  }

  Future<void> showPolygonSelector(
    BuildContext context,
    List<Polygon> wilayahPolygons,
    List<Map<String, dynamic>> wilayahData,
    void Function(List<Polygon>) onSelected,
  ) async {
    if (wilayahPolygons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada wilayah polygon tersedia'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final selectedIndices = <int>{};
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: StatefulBuilder(
            builder: (builderContext, setBuilderState) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(width: 24),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(dialogContext),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.textSecondary.withAlpha(77),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Zoom to selected polygon',
                      style: Theme.of(builderContext).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    if (wilayahPolygons.length > 1)
                      CheckboxListTile(
                        title: const Text('Pilih Semua'),
                        value: selectedIndices.length == wilayahPolygons.length,
                        onChanged: (bool? value) {
                          setBuilderState(() {
                            if (value == true) {
                              selectedIndices..clear();
                              for (int i = 0; i < wilayahPolygons.length; i++) {
                                selectedIndices.add(i);
                              }
                            } else {
                              selectedIndices.clear();
                            }
                          });
                        },
                        activeColor: AppColors.primary,
                      ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight:
                            MediaQuery.of(builderContext).size.height * 0.3,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: wilayahPolygons.length,
                        itemBuilder: (listContext, index) {
                          final isSelected = selectedIndices.contains(index);
                          final itemData =
                              wilayahData.isNotEmpty &&
                                  index < wilayahData.length
                              ? wilayahData[index]
                              : <String, dynamic>{};
                          final kodeSubSLS =
                              itemData['id_subsls']?.toString() ?? '';
                          final kodeKab =
                              itemData['kode_kab']?.toString() ?? '';
                          final kodeKec =
                              itemData['kode_kec']?.toString() ?? '';
                          final kodeDesa =
                              itemData['kode_desa']?.toString() ?? '';
                          final displayName = kodeSubSLS.isNotEmpty
                              ? kodeSubSLS
                              : [
                                  kodeKab,
                                  kodeKec,
                                  kodeDesa,
                                ].where((s) => s.isNotEmpty).join(' - ');

                          return CheckboxListTile(
                            title: Text(
                              displayName.isNotEmpty
                                  ? displayName
                                  : 'Wilayah ${index + 1}',
                            ),
                            value: isSelected,
                            onChanged: (bool? value) {
                              setBuilderState(() {
                                if (value == true) {
                                  selectedIndices.add(index);
                                } else {
                                  selectedIndices.remove(index);
                                }
                              });
                            },
                            activeColor: AppColors.primary,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: selectedIndices.isEmpty
                            ? null
                            : () {
                                final selectedPolygons = selectedIndices
                                    .map((i) => wilayahPolygons[i])
                                    .toList();
                                Navigator.pop(dialogContext);
                                onSelected(selectedPolygons);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Tampilkan'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _PetugasListItem {
  final int? id;
  final String name;
  final String? email;
  final String? role;

  const _PetugasListItem({required this.name, this.id, this.email, this.role});

  factory _PetugasListItem.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    final rawName = [
      json['name'],
      json['nama'],
      json['nama_petugas'],
      json['namaPetugas'],
      json['petugas_nama'],
      json['full_name'],
      json['fullName'],
      json['petugasName'],
      json['username'],
    ].where((e) => e != null).toList();

    final name = rawName.isEmpty ? '' : rawName.first.toString().trim();

    return _PetugasListItem(
      id: parseInt(json['id'] ?? json['petugas_id']),
      name: name.isNotEmpty ? name : 'Tanpa Nama',
      email: json['email']?.toString(),
      role: json['role']?.toString(),
    );
  }
}
