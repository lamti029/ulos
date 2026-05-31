import 'dart:async';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:ulos/core/services/background_service_handler.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/location_service.dart';
import '../../core/services/scheduler_service.dart';
import '../../core/services/env_service.dart';

import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/wilayah_service.dart';
import '../../core/services/dio_client.dart';
import '../../core/services/location_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/models/survey_model.dart';
import '../../core/controllers/tracking_controller.dart';
import '../pemeriksa/petugas_tracking_page.dart';
import '../../core/models/petugas_location.dart' as petugas_location;

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

    // Backend beberapa kali bisa mengirim key nama berbeda.
    final rawName = [
      json['name'],
      json['nama'],
      json['nama_petugas'],
      json['namaPetugas'],
      json['petugas_nama'],
      json['full_name'],
      json['fullName'],
      json['petugasName'],
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

class TrackingPage extends StatefulWidget {
  final SurveyModel survey;

  const TrackingPage({super.key, required this.survey});

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage>
    with WidgetsBindingObserver {
  // Role-based access for FAB petugas ditentukan secara live dari SurveyModel.
  bool get _showTrackingPetugasFab {
    final rawRole = widget.survey.roleInSurvei?.toString();
    // Normalisasi lebih ketat: buang bracket/quote yang mungkin ikut terbawa backend.
    final role = rawRole
        ?.toLowerCase()
        .trim()
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('"', '')
        .replaceAll("'", '');

    // Hanya role yang benar-benar 'pemeriksa' yang boleh melihat FAB.
    final show = role == 'pemeriksa';

    // Debug: pastikan nilai role yang diterima benar.
    debugPrint(
      '[TrackingPage] roleInSurvei="${widget.survey.roleInSurvei}" (normalized="$role") => _showTrackingPetugasFab=$show',
    );

    return show;
  }

  static const Duration _trackingMaxDuration = Duration(hours: 3);

  static const String _prefsTrackingStartedAtMs = 'tracking_started_at_ms';
  static const String _prefsTracking3hLastReminderAtMs =
      'tracking_3h_last_reminder_at_ms';

  static const Duration _reminderCooldown = Duration(minutes: 30);

  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  AndroidNotificationDetails? _androidDetails;
  NotificationDetails? _notificationDetails;

  int get _surveiId => widget.survey.id;

  Timer? _trackingStatusTimer;

  // Petugas tracking layer (toggle via FAB)
  bool _showPetugasLayer = false;
  bool _isPetugasLoading = false;

  // Filters (opsional; dari requirement user: cukup layer tampilan posisi)
  final List<_PetugasListItem> _petugas = [];
  int? _selectedPetugasId;

  final List<petugas_location.PetugasLocation> _petugasLocations = [];
  List<Marker> _petugasMarkers = const [];
  List<Polyline> _petugasPolylines = const [];

  List<Polygon> get _safeWilayahPolygons {
    // flutter_map PolygonLayer will throw if any LatLng is NaN/Infinity.
    // Filter polygons/points defensively.
    if (_wilayahPolygons.isEmpty) return const <Polygon>[];

    List<Polygon> result = [];
    for (final polygon in _wilayahPolygons) {
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

  bool _isDisposed = false;
  final LocationService _locationService = LocationService();

  late final SchedulerService _schedulerService;

  final MapController _mapController = MapController();

  LatLng? _currentPosition;

  List<Map<String, dynamic>> _initialTargetPoints = [];

  List<Map<String, dynamic>> _nearbyTargetPoints = [];
  bool _showNearbyTargetPoints = false;

  List<Map<String, dynamic>> _targetPoints = [];

  List<Map<String, dynamic>> _targetPointsNearby = [];

  LatLng? _lastNearbyCenter;
  bool _isNearbyLoading = false;
  final double _nearbyMinDistanceMeters = 100.0;

  Map<String, dynamic>? _selectedTargetPoint;
  bool _isLoading = true;
  bool _isLocationActive = false;
  bool _isSyncActive = false;

  bool get _isTracking => _getIsTrackingForThisSurvey();

  // Ensure Start/Stop button matches runtime tracking state.
  // Source of truth: lock id set saat start tracking.
  bool _getIsTrackingForThisSurvey() =>
      widget.survey.id == TrackingController.instance.activeSurveiId;

  Future<bool> _isOtherSurveiLockedAndRunning() async {
    final running = await SchedulerService.isRunning;
    if (!running) return false;

    // Jika lock belum terpasang, kita tidak kunci aksi.
    final lockId = TrackingController.instance.activeSurveiId;
    if (lockId == null) return false;

    // Survei lain tidak boleh start/stop.
    return lockId != widget.survey.id;
  }

  Future<void> _ensureNoStaleBackgroundThenUpdateStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      bool isFirstLaunch =
          prefs.getBool('is_first_launch_after_install') ?? true;

      if (isFirstLaunch) {
        debugPrint(
          '[Tracking] Fresh install/update terdeteksi. Memaksa reset tracking state.',
        );

        await BackgroundServiceHandler.ensureNotRunning();

        try {
          await _schedulerService.stop();
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

      final recheckCount = 3;
      final recheckDelay = const Duration(milliseconds: 200);
      bool stableBgRunning = false;

      for (int i = 0; i < recheckCount; i++) {
        await Future.delayed(recheckDelay);
        final bg = await BackgroundServiceHandler.isRunning();
        stableBgRunning = i == 0 ? bg : (stableBgRunning && bg);
      }

      final schedulerRunningFinal = await SchedulerService.isRunning;
      if (!schedulerRunningFinal && stableBgRunning) {
        await BackgroundServiceHandler.ensureNotRunning();
      }
    } catch (e) {
      debugPrint(
        '[_ensureNoStaleBackgroundThenUpdateStatus] ensureNotRunning error: $e',
      );
    }

    await _updateTrackingStatus();
  }

  bool _isStartLoading = false;
  bool _isStopLoading = false;
  int _locationInterval = AppConstants.defaultLocationInterval;
  int _batchInterval = AppConstants.defaultBatchInterval;
  List<Polygon> _wilayahPolygons = [];
  List<Map<String, dynamic>> _wilayahData = [];

  Future<void> _maybeShowTrackingOver3hPopup() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();

    final schedulerRunning = await SchedulerService.isRunning;
    if (!schedulerRunning) return;

    final startedAtMs = prefs.getInt(_prefsTrackingStartedAtMs);
    if (startedAtMs == null) return;

    final startedAt = DateTime.fromMillisecondsSinceEpoch(startedAtMs);
    final elapsed = DateTime.now().difference(startedAt);

    if (elapsed < _trackingMaxDuration) return;

    final alreadyShown = prefs.getBool('tracking_3h_popup_shown') ?? false;
    if (alreadyShown) return;

    await prefs.setBool('tracking_3h_popup_shown', true);

    if (!mounted) return;
    await showDialog<void>(
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
                // Stop tracking using the existing flow.
                await _toggleTracking();
              },
              child: const Text('Berhenti Tracking'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _maybeTriggerBackgroundReminder() async {
    final prefs = await SharedPreferences.getInstance();

    final schedulerRunning = await SchedulerService.isRunning;
    if (!schedulerRunning) return;

    final startedAtMs = prefs.getInt(_prefsTrackingStartedAtMs);
    if (startedAtMs == null) return;

    final startedAt = DateTime.fromMillisecondsSinceEpoch(startedAtMs);
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < _trackingMaxDuration) return;

    final lastReminderMs = prefs.getInt(_prefsTracking3hLastReminderAtMs) ?? 0;
    final lastReminder = lastReminderMs == 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lastReminderMs);

    if (lastReminder != null) {
      final since = DateTime.now().difference(lastReminder);
      if (since < _reminderCooldown) return;
    }

    // Initialize notification details lazily.
    _androidDetails ??= const AndroidNotificationDetails(
      'tracking_reminders',
      'Tracking Reminders',
      channelDescription: 'Reminder saat tracking berjalan lama',
      importance: Importance.high,
      priority: Priority.high,
      playSound: false,
    );

    _notificationDetails ??= NotificationDetails(
      android: _androidDetails,
      iOS: const DarwinNotificationDetails(),
    );

    final now = DateTime.now();
    final notifId = now.millisecondsSinceEpoch.remainder(1000000);

    await _localNotificationsPlugin.show(
      notifId,
      'Reminder Tracking',
      'Tracking Anda sudah lebih dari 3 jam. '
          'Pertimbangkan untuk berhenti agar sesuai kebutuhan.',
      _notificationDetails!,
    );

    await prefs.setInt(
      _prefsTracking3hLastReminderAtMs,
      now.millisecondsSinceEpoch,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedulerService = SchedulerService.instance;

    _ensureNoStaleBackgroundThenUpdateStatus();

    // FAB petugas (tracking petugas) ditentukan via getter berbasis role.
    // Tidak perlu menyimpan _isPemeriksa di state.
    TrackingController.instance.init();
    debugPrint('isTracking =  ${_getIsTrackingForThisSurvey()}');
    debugPrint(
      'controller isTracking =  ${TrackingController.instance.isTrackingActive}',
    );
    _initializeData();
    _getCurrentLocation();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _maybeShowTrackingOver3hPopup();
      await _maybeTriggerBackgroundReminder();
    });
  }

  Future<void> _initializeData() async {
    await WilayahService.ensureInitialized();
    debugPrint(
      '[Tracking] Service polygons: ${WilayahService.wilayahPolygons.length}',
    );
    if (mounted) {
      setState(() {
        _wilayahPolygons = WilayahService.wilayahPolygons;
        _wilayahData = WilayahService.wilayahData;

        _initialTargetPoints = WilayahService.targetPoints;
        _targetPoints = _initialTargetPoints;

        _isLoading = false;
      });
      debugPrint('[Tracking] Local state polygons: ${_wilayahPolygons.length}');
    }
  }

  Future<void> _updateTrackingStatus() async {
    final schedulerRunning = await SchedulerService.isRunning;

    final locationActive = schedulerRunning;

    // sync is active only when location is active and sync interval is enabled (>0)
    final syncActive = locationActive && EnvService.syncIntervalSeconds > 0;

    if (mounted) {
      setState(() {
        _isLocationActive = locationActive;
        _isSyncActive = syncActive;
        // Keep SurveyModel in sync with actual tracking runtime state.
        widget.survey.isTrackingActive = locationActive && syncActive;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      await _updateTrackingStatus();
    }
  }

  bool _isFiniteLatLng(LatLng l) {
    return l.latitude.isFinite && l.longitude.isFinite;
  }

  bool _mapHasRendered = false;

  Future<void> _getCurrentLocation() async {
    final position = await _locationService.getCurrentPosition();

    if (position == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal mendapatkan lokasi. Pastikan GPS aktif.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      setState(() => _isStartLoading = false);
      return;
    }
    if (!mounted || _isDisposed) return;

    final currentLatLng = LatLng(position.latitude, position.longitude);
    if (!_isFiniteLatLng(currentLatLng)) {
      debugPrint('[_getCurrentLocation] Invalid lat/lng: $currentLatLng');
      return;
    }

    setState(() {
      _currentPosition = currentLatLng;

      _isLoading = false;
    });

    if (_mapHasRendered) {
      _mapController.move(currentLatLng, 15);
    }
  }

  void _showTargetPointDetail(Map<String, dynamic> point) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
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
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
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
                        onPressed: () => Navigator.pop(context),
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

  Future<List<Map<String, dynamic>>> _fetchNearbyTargetPoints({
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

      if (firstResponse.statusCode != 200) {
        debugPrint(
          '[_fetchNearbyTargetPoints] firstResponse status: '
          '${firstResponse.statusCode}',
        );
        return allPoints;
      }

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
    } catch (e) {
      debugPrint('[_fetchNearbyTargetPoints] error: $e');
      return allPoints;
    }

    // Normalize fields so _targetMarkers works.
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

  double _distanceMeters(LatLng a, LatLng b) {
    // Haversine formula
    const double earthRadius = 6371000.0;
    final dLat = (b.latitude - a.latitude) * (3.141592653589793 / 180.0);
    final dLng = (b.longitude - a.longitude) * (3.141592653589793 / 180.0);
    final lat1 = a.latitude * (3.141592653589793 / 180.0);
    final lat2 = b.latitude * (3.141592653589793 / 180.0);

    final double sinDLat = math.sin(dLat / 2.0);
    final double sinDLng = math.sin(dLng / 2.0);

    final double h =
        sinDLat * sinDLat +
        sinDLng * sinDLng * (math.cos(lat1) * math.cos(lat2));

    return 2.0 * earthRadius * math.sqrt(h);
  }

  Future<void> _postAbsensi(String action) async {
    // action: 'start' | 'stop'
    try {
      final dioClient = DioClient();

      // DioClient interceptor otomatis menempelkan Authorization dari token login.
      final res = await dioClient.dio.post(
        '/api/absensi/$action',
        data: {'survei_id': _surveiId},
        options: Options(headers: const {'accept': 'application/json'}),
      );

      debugPrint('[_postAbsensi/$action] status=${res.statusCode}');

      if (res.statusCode != 200 && res.statusCode != 201) {
        debugPrint('[_postAbsensi/$action] response=${res.data}');
      }
    } catch (e) {
      debugPrint('[_postAbsensi/$action] error: $e');
    }
  }

  Future<void> _toggleTracking() async {
    final shouldLock = await _isOtherSurveiLockedAndRunning();
    if (shouldLock) {
      if (mounted) {
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
    if (_isTracking) {
      // Stop tracking
      setState(() => _isStopLoading = true);

      try {
        // Stop flow jangan tergantung GPS terlalu lama.
        final position = await _locationService.getCurrentPosition().timeout(
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
            'survei_id': _surveiId,

            'battery_level': battery?.batteryLevel,
            'timestamp': position.timestamp.toUtc().toIso8601String(),
          };
          await _schedulerService.sendImmediateBatch(locations: [lastLocation]);
        }
      } on TimeoutException {
        debugPrint('[_toggleTracking] stop timeout: GPS too slow');
      } catch (e) {
        debugPrint('[_toggleTracking] error sending last location: $e');
      } finally {
        // Batasi total waktu tunggu stop di UI.
        // Jika timeout, lanjut proses cleanup agar tombol stop tidak menggantung.
        try {
          await _schedulerService.stop().timeout(const Duration(seconds: 8));
        } on TimeoutException {
          debugPrint('[_toggleTracking] scheduler stop timeout');
        } catch (e) {
          debugPrint('[_toggleTracking] scheduler stop error: $e');
        }

        await _postAbsensi('stop');

        // Update SurveyModel runtime status.
        widget.survey.isTrackingActive = false;

        if (TrackingController.instance.activeSurveiId == widget.survey.id) {
          TrackingController.instance.clear();
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_tracking', false);

        await prefs.remove(_prefsTrackingStartedAtMs);
        await prefs.remove('tracking_3h_popup_shown');
        await prefs.remove(_prefsTracking3hLastReminderAtMs);

        _updateTrackingStatus();
        if (mounted) {
          setState(() => _isStopLoading = false);
        }
      }
      return;
    }

    setState(() => _isStartLoading = true);

    try {
      final position = await _locationService.getCurrentPosition();
      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gagal mendapatkan lokasi. Pastikan GPS aktif.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        setState(() => _isStartLoading = false);
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_tracking', true);

      // Update SurveyModel runtime status.
      widget.survey.isTrackingActive = true;
      TrackingController.instance.lockTo(widget.survey.id);

      // Save tracking start time for >3 hours checks/reminders.
      await prefs.setInt(
        _prefsTrackingStartedAtMs,
        DateTime.now().millisecondsSinceEpoch,
      );
      await prefs.remove('tracking_3h_popup_shown');
      await prefs.remove(_prefsTracking3hLastReminderAtMs);

      // Optimization: clean up synced local data from yesterday to keep SQLite smaller.
      try {
        await LocationRepository().deleteSyncedForDay(
          DateTime.now().subtract(const Duration(days: 1)),
        );
      } catch (e) {
        debugPrint(
          '[_toggleTracking] cleanup yesterday synced rows failed: $e',
        );
      }

      await _postAbsensi('start');

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

      await _schedulerService.sendImmediateBatch(locations: [firstLocation]);

      _schedulerService.start(
        locationIntervalSeconds: _locationInterval,
        batchIntervalSeconds: _batchInterval,
        surveiId: _surveiId,
      );

      _updateTrackingStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memulai tracking: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isStartLoading = false);
      }
    }
  }

  void _zoomToPolygon(List<Polygon>? selectedPolygons) {
    if (selectedPolygons == null || selectedPolygons.isEmpty) {
      if (_wilayahPolygons.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak ada wilayah polygon untuk ditampilkan'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    // Create bounds from first finite point, then extend with all other finite points
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

    if (bounds == null) {
      debugPrint(
        '[_zoomToPolygon] No finite polygon points; skipping fitCamera',
      );
      return;
    }

    // Saat zoom ke polygon, sembunyikan nearby target points.
    setState(() {
      _showNearbyTargetPoints = false;
      _targetPoints = _initialTargetPoints;
    });

    if (!_mapHasRendered) {
      debugPrint('[_zoomToPolygon] Map not rendered yet; skipping fitCamera');
      return;
    }

    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
    );
  }

  void _showPolygonSelector() {
    if (_wilayahPolygons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada wilayah polygon tersedia'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    showDialog(
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
                    if (_wilayahPolygons.length > 1)
                      CheckboxListTile(
                        title: const Text('Pilih Semua'),
                        value:
                            selectedIndices.length == _wilayahPolygons.length,
                        onChanged: (bool? value) {
                          setBuilderState(() {
                            if (value == true) {
                              selectedIndices.clear();
                              for (
                                int i = 0;
                                i < _wilayahPolygons.length;
                                i++
                              ) {
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
                        itemCount: _wilayahPolygons.length,
                        itemBuilder: (listContext, index) {
                          final isSelected = selectedIndices.contains(index);
                          final itemData =
                              _wilayahData.isNotEmpty &&
                                  index < _wilayahData.length
                              ? _wilayahData[index]
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
                            // subtitle: Text(
                            //   '${_wilayahPolygons[index].points.length} titik',
                            // ),
                            value: isSelected,
                            onChanged: (bool? value) {
                              setBuilderState(() {
                                if (value == true) {
                                  selectedIndices.add(index);
                                } else {
                                  selectedIndices.remove(index);
                                }
                              });
                              setState(() {});
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
                                    .map((i) => _wilayahPolygons[i])
                                    .toList();
                                Navigator.pop(dialogContext);
                                _zoomToPolygon(selectedPolygons);
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

  void _showTargetPointsNearby() async {
    // Only now fetch & show nearby target points
    final position = await _locationService.getCurrentPosition();
    if (!mounted) return;
    if (position == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal mendapatkan lokasi. Pastikan GPS aktif.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      setState(() => _isStartLoading = false);
      return;
    }

    final currentLatLng = LatLng(position.latitude, position.longitude);
    if (!_isFiniteLatLng(currentLatLng)) {
      debugPrint('[_showTargetPoitsNearby] Invalid lat/lng: $currentLatLng');
      return;
    }
    _mapController.move(currentLatLng, 15);

    // If user didn't move enough (>=100m), reuse cache.
    final shouldRefetch =
        _lastNearbyCenter == null ||
        _distanceMeters(_lastNearbyCenter!, currentLatLng) >=
            _nearbyMinDistanceMeters;

    try {
      if (shouldRefetch) {
        setState(() {
          _isNearbyLoading = true;
        });

        final nearby = await _fetchNearbyTargetPoints(
          lat: currentLatLng.latitude,
          lng: currentLatLng.longitude,
          surveiId: _surveiId,
        );

        if (!mounted) return;

        setState(() {
          _nearbyTargetPoints = nearby;
          _lastNearbyCenter = currentLatLng;
        });
      }

      setState(() {
        _showNearbyTargetPoints = true;
        _targetPointsNearby = _nearbyTargetPoints;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isNearbyLoading = false;
        });
      }
    }
  }

  bool _isValidLatLng(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (!lat.isFinite || !lng.isFinite) return false;
    return lat.abs() <= 90 && lng.abs() <= 180;
  }

  String? _formatTimestamp(DateTime? dt) {
    if (dt == null) return null;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatApiDateTime(DateTime dt) {
    // Backend parse: DD/MM/YYYY HH:mm:ss
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yyyy = dt.year.toString();
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min:$ss';
  }

  Future<void> _fetchPetugasIfNeeded() async {
    if (_petugas.isNotEmpty) return;
    if (_isPetugasLoading) return;

    setState(() => _isPetugasLoading = true);
    try {
      final res = await DioClient().dio.get(
        '/api/pemeriksa/petugas',
        queryParameters: {'page': 1, 'limit': 20, 'survei_id': _surveiId},
      );

      debugPrint(
        '[Tracking] /api/pemeriksa/petugas status=${res.statusCode} payloadType=${res.data.runtimeType}',
      );

      if (res.statusCode != 200) {
        throw Exception('Request failed: ${res.statusCode}');
      }

      final payload = res.data;
      final List<dynamic> rawList =
          (payload is Map<String, dynamic> && payload['data'] is List)
          ? (payload['data'] as List<dynamic>)
          : payload is List
          ? payload
          : [];

      setState(() {
        if (_selectedPetugasId == null && _petugas.isNotEmpty) {
          _selectedPetugasId = _petugas.first.id;
        }
      });
    } catch (e) {
    } finally {
      if (mounted) setState(() => _isPetugasLoading = false);
    }
  }

  Future<void> _fetchPetugasLocationsLatestOrFiltered() async {
    if (!mounted) return;

    try {
      // Default
      if (_selectedPetugasId == null) {
        final res = await DioClient().dio.get(
          '/api/pemeriksa/lokasi/terbaru',
          queryParameters: {'survei_id': _surveiId},
        );
        if (res.statusCode != 200 && res.statusCode != 201) {
          throw Exception('Request failed: ${res.statusCode}');
        }

        final data = res.data;
        final listRaw = data is Map<String, dynamic>
            ? (data['data'] ?? [])
            : [];
        final rawList = listRaw is List ? listRaw : [];

        final parsed = rawList
            .whereType<Map<String, dynamic>>()
            .map(
              (e) => petugas_location.PetugasLocation.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .where((p) => _isValidLatLng(p.latitude, p.longitude))
            .toList();

        setState(() {
          _petugasLocations
            ..clear()
            ..addAll(parsed);
          _petugasMarkers = _buildPetugasMarkers();
          _petugasPolylines = _buildPetugasPolylines();
        });
        return;
      }

      // Filter aktif (petugas saja)
      final res = await DioClient().dio.get(
        '/api/pemeriksa/lokasi',
        queryParameters: {
          'page': 1,
          'limit': 50,
          'petugas_id': _selectedPetugasId,
          'survei_id': _surveiId,
        },
      );

      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception('Request failed: ${res.statusCode}');
      }

      final data = res.data;
      final listRaw = data is Map<String, dynamic> ? (data['data'] ?? []) : [];
      final rawList = listRaw is List ? listRaw : [];

      final parsed = rawList
          .whereType<Map<String, dynamic>>()
          .map(
            (e) => petugas_location.PetugasLocation.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .where((p) => _isValidLatLng(p.latitude, p.longitude))
          .toList();

      setState(() {
        _petugasLocations
          ..clear()
          ..addAll(parsed);
        _petugasMarkers = _buildPetugasMarkers();
        _petugasPolylines = _buildPetugasPolylines();
      });
    } catch (e) {
      // if (mounted) setState(() => _petugasErrorMessage = e.toString());
    }
  }

  Marker _buildPetugasMarker(petugas_location.PetugasLocation loc, int index) {
    final lat = (loc.latitude ?? 0.0);
    final lng = (loc.longitude ?? 0.0);
    final nama = (loc.namaPetugas ?? 'Petugas').trim();
    final timestampStr = _formatTimestamp(loc.timestamp);

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
                    Padding(
                      padding: const EdgeInsets.only(right: 40.0, top: 4.0),
                      child: Text('Lokasi Petugas'),
                    ),
                    // Posisi tombol Close di pojok kanan atas title
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
                // title: Text(nama),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nama: ${nama}'),
                    if (timestampStr != null) Text('Waktu: $timestampStr'),
                    // const SizedBox(height: 8),
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
                        // Ambil petugasId untuk call API track (backend pakai petugas_id)
                        final petugasId = (loc.userId ?? loc.id);
                        if (petugasId == null) return;

                        Navigator.pop(context);

                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PetugasTrackingPage(surveiId: _surveiId),
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

  List<Marker> _buildPetugasMarkers() {
    return _petugasLocations.asMap().entries.map((entry) {
      return _buildPetugasMarker(entry.value, entry.key);
    }).toList();
  }

  List<Polyline> _buildPetugasPolylines() {
    if (_petugasLocations.length < 2) return const [];

    final Map<int, List<petugas_location.PetugasLocation>> byPetugas = {};
    for (final loc in _petugasLocations) {
      final key = (loc.userId ?? loc.id ?? -1);
      if (key == -1) continue;
      byPetugas
          .putIfAbsent(key, () => <petugas_location.PetugasLocation>[])
          .add(loc);
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

      // Draw full path to avoid losing segments across multiple history parts.
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

  Future<void> _syncWilayahData() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getInt('last_wilayah_sync') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 86400000; // day
    final lastDay = lastSync ~/ 86400000;

    if (now <= lastDay) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync available once per day. Try tomorrow.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    debugPrint('[Tracking] Sync wilayah data - clearing prefs first');
    await WilayahService.clear();
    await WilayahService.init();
    await prefs.setInt(
      'last_wilayah_sync',
      DateTime.now().millisecondsSinceEpoch,
    );

    if (mounted) {
      setState(() {
        _wilayahPolygons = WilayahService.wilayahPolygons;
        _wilayahData = WilayahService.wilayahData;

        _initialTargetPoints = WilayahService.targetPoints;
        _targetPoints = _initialTargetPoints;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wilayah & Target Points refreshed from server!'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  /// Calculate centroid from a list of polygon points
  LatLng _calculateCentroid(List<LatLng> points) {
    if (points.isEmpty) {
      return const LatLng(0, 0);
    }
    if (points.length == 1) {
      return points.first;
    }

    double latSum = 0;
    double lngSum = 0;
    for (final point in points) {
      latSum += point.latitude;
      lngSum += point.longitude;
    }
    return LatLng(latSum / points.length, lngSum / points.length);
  }

  /// Get markers to display id_subsls labels on each polygon
  List<Marker> get _wilayahLabelMarkers {
    if (_wilayahPolygons.isEmpty || _wilayahData.isEmpty) {
      return [];
    }

    final List<Marker> markers = [];
    for (int i = 0; i < _wilayahPolygons.length; i++) {
      final polygon = _wilayahPolygons[i];
      final itemData = i < _wilayahData.length ? _wilayahData[i] : null;
      final idSubSLS = itemData?['id_subsls']?.toString() ?? 'Wilayah ${i + 1}';

      if (idSubSLS.isNotEmpty && idSubSLS != 'Wilayah ${i + 1}') {
        final centroid = _calculateCentroid(polygon.points);

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

  Marker _buildTargetMarker(
    Map<String, dynamic> point, {
    required bool isNearby,
    required int index,
  }) {
    final lat = (point['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (point['longitude'] as num?)?.toDouble() ?? 0.0;

    final bool isSelected =
        _selectedTargetPoint != null &&
        _selectedTargetPoint!['id'] == point['id'];

    // warna dasar: initial=error(merah), nearby=primary(biru)
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
        onTap: () => _showTargetPointDetail(point),
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

  List<Marker> get _initialTargetMarkers {
    return _targetPoints.asMap().entries.map((entry) {
      return _buildTargetMarker(entry.value, isNearby: false, index: entry.key);
    }).toList();
  }

  List<Marker> get _nearbyTargetMarkers {
    return _targetPointsNearby.asMap().entries.map((entry) {
      return _buildTargetMarker(entry.value, isNearby: true, index: entry.key);
    }).toList();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _trackingStatusTimer?.cancel();
    _trackingStatusTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start, // Aligns text to the left
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
          if (widget.survey.nama != null || widget.survey.roleInSurvei != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children:
                    const [], // Diperbaiki: Menggunakan konstanta array kosong yang valid
              ),
            ),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _syncWilayahData,
            tooltip: 'Sync Wilayah',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Safe State Binder: Mencegah infinite loop pemicu re-render
                Builder(
                  builder: (context) {
                    if (!_mapHasRendered) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() => _mapHasRendered = true);
                        }
                      });
                    }
                    return const SizedBox.shrink();
                  },
                ),
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter:
                        (_currentPosition != null &&
                            _isFiniteLatLng(_currentPosition!))
                        ? _currentPosition!
                        : const LatLng(-6.2088, 106.8456),
                    initialZoom: 14,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.ulos.app',
                    ),
                    if (_currentPosition != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _currentPosition!,
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
                                    color: AppColors.primary.withAlpha(77),
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
                    if (_wilayahPolygons.isNotEmpty)
                      PolygonLayer(polygons: _safeWilayahPolygons),
                    if (_wilayahLabelMarkers.isNotEmpty)
                      MarkerLayer(markers: _wilayahLabelMarkers),
                    if (_initialTargetMarkers.isNotEmpty)
                      MarkerClusterLayerWidget(
                        options: MarkerClusterLayerOptions(
                          maxClusterRadius: 120,
                          disableClusteringAtZoom: 17,
                          size: const Size(40, 40),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(50),
                          maxZoom: 15,
                          markers: _initialTargetMarkers,
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
                    if (_showPetugasLayer) ...[
                      if (_petugasPolylines.isNotEmpty)
                        PolylineLayer(polylines: _petugasPolylines),
                      if (_petugasMarkers.isNotEmpty)
                        MarkerLayer(markers: _petugasMarkers),
                    ],
                    if (_showNearbyTargetPoints &&
                        _nearbyTargetMarkers.isNotEmpty)
                      MarkerClusterLayerWidget(
                        options: MarkerClusterLayerOptions(
                          maxClusterRadius: 120,
                          disableClusteringAtZoom: 17,
                          size: const Size(40, 40),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(50),
                          maxZoom: 15,
                          markers: _nearbyTargetMarkers,
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
                // Panel Floating Action Buttons (FAB)
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
                        onPressed: _getCurrentLocation,
                        child: const Icon(Icons.my_location),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'zoom_polygon',
                        backgroundColor: AppColors.surface,
                        foregroundColor: AppColors.green,
                        onPressed: _showPolygonSelector,
                        child: const Icon(Icons.crop_free),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'show_target_nearby',
                        backgroundColor: AppColors.surface,
                        foregroundColor: AppColors.primary,
                        onPressed: _isNearbyLoading
                            ? null
                            : _showTargetPointsNearby, // Typo fixed
                        child: const Icon(Icons.place_outlined),
                      ),
                      // Diperbaiki: Menggunakan spread operator agar penempatan di dalam Column valid
                      if (_showTrackingPetugasFab) ...[
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'tracking_petugas',
                          backgroundColor: AppColors.surface,
                          foregroundColor: AppColors.blue,
                          onPressed: () {
                            setState(() {
                              _showPetugasLayer = !_showPetugasLayer;
                            });
                            if (_showPetugasLayer) {
                              _fetchPetugasIfNeeded();
                              _fetchPetugasLocationsLatestOrFiltered();
                            }
                          },
                          child: const Icon(Icons.person_search_outlined),
                        ),
                      ],
                    ],
                  ),
                ),
                // Detail Target Info Card
                if (_selectedTargetPoint != null && !_isLocationActive)
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _selectedTargetPoint!['nama'] ??
                                        'Titik Sasaran',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (_selectedTargetPoint!['alamat'] != null)
                                    Text(
                                      _selectedTargetPoint!['alamat']
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
                                setState(() => _selectedTargetPoint = null);
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
                // Main Action Button (Start/Stop)
                Positioned(
                  bottom: 24,
                  left: 24,
                  right: 24,
                  child: SafeArea(
                    child: ElevatedButton.icon(
                      onPressed: (_isStartLoading || _isStopLoading)
                          ? null
                          : () async {
                              final locked =
                                  await _isOtherSurveiLockedAndRunning();
                              if (locked) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text(
                                        'Tracking sedang aktif pada survei lain',
                                      ),
                                      backgroundColor: AppColors.warning,
                                    ),
                                  );
                                }
                                return;
                              }
                              await _toggleTracking();
                            },
                      icon: _isStartLoading || _isStopLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(_isTracking ? Icons.stop : Icons.play_arrow),
                      label: Text(
                        _isStartLoading
                            ? 'Memulai...'
                            : _isStopLoading
                            ? 'Menghentikan...'
                            : (_isTracking
                                  ? 'Stop Tracking'
                                  : 'Start Tracking'),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _getIsTrackingForThisSurvey()
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
                // Top Status Indicator Banner
                if (_getIsTrackingForThisSurvey())
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
                                        _getIsTrackingForThisSurvey()
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
                              .slideY(begin: -0.5, end: 0, duration: 300.ms),
                    ),
                  ),
              ],
            ),
    );
  }
}
