import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/location_service.dart';
import '../../core/services/scheduler_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/wilayah_service.dart';
import '../../core/services/dio_client.dart';
import 'package:dio/dio.dart';

// Token bearer dipakai untuk request absensi/start & absensi/stop.
// Diambil dari token login yang tersimpan.

class TrackingPage extends StatefulWidget {
  const TrackingPage({super.key});

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage>
    with WidgetsBindingObserver {
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

  // Target points from initialization (wilayah service)
  List<Map<String, dynamic>> _initialTargetPoints = [];

  // Target points fetched nearby (nearby endpoint after locate / switch)
  List<Map<String, dynamic>> _nearbyTargetPoints = [];
  bool _showNearbyTargetPoints = false;

  // Warna marker nearby: primary(biru) dan initial:error(merah)

  // Target points initial (berasal dari WilayahService)
  List<Map<String, dynamic>> _targetPoints = [];

  // Target points nearby (hasil endpoint /nearby)
  List<Map<String, dynamic>> _targetPointsNearby = [];

  // Nearby caching to avoid hitting API too often
  LatLng? _lastNearbyCenter;
  bool _isNearbyLoading = false;
  final double _nearbyMinDistanceMeters = 100.0;

  Map<String, dynamic>? _selectedTargetPoint;
  bool _isLoading = true;
  bool _isTracking = false;
  bool _isStartLoading = false;
  bool _isStopLoading = false;
  int _locationInterval = AppConstants.defaultLocationInterval;
  int _batchInterval = AppConstants.defaultBatchInterval;
  List<Polygon> _wilayahPolygons = [];
  List<Map<String, dynamic>> _wilayahData = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedulerService = SchedulerService.instance;
    _updateTrackingStatus();
    _initializeData();
    _getCurrentLocation();
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
    final isRunning = await SchedulerService.isRunning;
    if (mounted) {
      setState(() {
        _isTracking = isRunning;
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

    // MapController requires FlutterMap to be rendered at least once.
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
  }) async {
    const int limit = 20;

    final allPoints = <Map<String, dynamic>>[];

    try {
      // Note: DioClient is already configured with baseUrl from EnvService.
      final dioClient = DioClient();

      final firstResponse = await dioClient.dio.get(
        'https://trackingapi.bps.web.id/api/titik-sasaran/nearby',
        queryParameters: {
          'lat': lat,
          'lng': lng,
          'radius': 100,
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
        data: '',
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
    if (_isTracking) {
      // Stop tracking
      setState(() => _isStopLoading = true);

      try {
        final position = await _locationService.getCurrentPosition();
        if (position != null) {
          final lastLocation = {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'accuracy': position.accuracy,
            'altitude': position.altitude,
            'speed': position.speed,
            'is_mocked': position.isMocked,
            'survei_id': _selectedTargetPoint!['survei_id'] as int?,
            'timestamp': position.timestamp.toUtc().toIso8601String(),
          };
          await _schedulerService.sendImmediateBatch(locations: [lastLocation]);
        }
      } catch (e) {
        debugPrint('[_toggleTracking] error sending last location: $e');
      } finally {
        await _schedulerService.stop();
        await _postAbsensi('stop');
        _updateTrackingStatus();
        if (mounted) {
          setState(() => _isStopLoading = false);
        }
      }
      return;
    }

    // Start tracking
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

      await _postAbsensi('start');

      final firstLocation = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'speed': position.speed,
        'is_mocked': position.isMocked,
        'timestamp': position.timestamp.toUtc().toIso8601String(),
      };

      await _schedulerService.sendImmediateBatch(locations: [firstLocation]);

      _schedulerService.start(
        locationIntervalSeconds: _locationInterval,
        batchIntervalSeconds: _batchInterval,
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

  void _showTargetPoitsNearby() async {
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
    WidgetsBinding.instance.removeObserver(this);
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Tracking'),
        actions: [
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
                Builder(
                  builder: (context) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!_mapHasRendered) {
                        setState(() => _mapHasRendered = true);
                      }
                    });
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
                    // FlutterMap versi yang dipakai di project ini belum punya parameter interactiveFlags.
                    // Zoom/drag tetap harus bekerja via default MapOptions.
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
                Positioned(
                  bottom: 400,
                  right: 16,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // locate
                          FloatingActionButton.small(
                            heroTag: 'locate',
                            backgroundColor: AppColors.surface,
                            foregroundColor: AppColors.primary,
                            onPressed: _getCurrentLocation,
                            child: const Icon(Icons.my_location),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'zoom_polygon',
                            backgroundColor: AppColors.surface,
                            foregroundColor: AppColors.primary,
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
                                : _showTargetPoitsNearby,
                            child: const Icon(Icons.place_outlined),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                if (_selectedTargetPoint != null && !_isTracking)
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
                Positioned(
                  bottom: 24,
                  left: 24,
                  right: 24,
                  child: SafeArea(
                    child: ElevatedButton.icon(
                      onPressed: (_isStartLoading || _isStopLoading)
                          ? null
                          : _toggleTracking,
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
                        backgroundColor: _isTracking
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
                if (_isTracking)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
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
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'Tracking active... Locations are being captured and saved locally.',
                                      style: TextStyle(
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
              ],
            ),
    );
  }
}
