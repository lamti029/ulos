import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ulos/core/utils/jwt_utils.dart';

import '../../core/services/dio_client.dart';
import 'petugas_list_page.dart' show PetugasListItem;

class PetugasLocation {
  final int? id;
  final int? userId;
  final int? surveiId;
  final String? namaPetugas;
  final double? latitude;
  final double? longitude;
  final num? accuracy;
  final num? speed;
  final num? altitude;
  final num? batteryLevel;
  final bool? isMocked;
  final DateTime? timestamp;

  const PetugasLocation({
    this.id,
    this.userId,
    this.surveiId,
    this.namaPetugas,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.speed,
    this.altitude,
    this.batteryLevel,
    this.isMocked,
    this.timestamp,
  });

  static DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  static num? _parseNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  static bool? _parseBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    final s = v.toString().toLowerCase().trim();
    if (s == 'true') return true;
    if (s == 'false') return false;
    return null;
  }

  factory PetugasLocation.fromJson(Map<String, dynamic> json) {
    // Beberapa API kadang mengirim payload berbeda (mis. user terkait disimpan di `user`).
    // Requirement untuk filter: petugas_id diambil dari petugas.id, dan payload biasanya tersedia di `user_id`.
    return PetugasLocation(
      id: _parseInt(json['id']),
      userId: _parseInt(json['user_id']),
      surveiId: _parseInt(json['survei_id']),
      namaPetugas:
          json['nama_petugas']?.toString() ??
          json['user']?['name']?.toString() ??
          json['petugas']?['name']?.toString() ??
          json['name']?.toString(),
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      accuracy: _parseNum(json['accuracy']),
      speed: _parseNum(json['speed']),
      altitude: _parseNum(json['altitude']),
      batteryLevel: _parseNum(json['battery_level']),
      isMocked: _parseBool(json['is_mocked']),
      timestamp: _parseDateTime(json['timestamp'] ?? json['created_at']),
    );
  }
}

class PetugasTrackingPage extends StatefulWidget {
  final int surveiId;

  const PetugasTrackingPage({super.key, required this.surveiId});

  @override
  State<PetugasTrackingPage> createState() => _PetugasTrackingPageState();
}

class _PetugasTrackingPageState extends State<PetugasTrackingPage> {
  bool _isLoading = true;
  String? _errorMessage;

  final List<PetugasLocation> _locations = [];
  final List<PetugasLocation> _latestLocations = [];

  Timer? _refreshTimer;

  final MapController _mapController = MapController();

  LatLng _defaultCenter = const LatLng(-6.2088, 106.8456);

  // Filters
  int? _selectedPetugasId;
  DateTime? _fromDate;

  final List<PetugasListItem> _petugas = [];
  int? pemeriksaId;
  bool _isLoadingPetugas = false;

  bool get _isFilterActive => _selectedPetugasId != null || _fromDate != null;

  @override
  void initState() {
    super.initState();
    _fetchPetugasIfNeeded();
    _fetchLatestOrFiltered();

    _refreshTimer = null;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
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
    final userId = await JwtUtils.getUserId();
    if (userId == null) return;
    print('userid $userId');
    if (_petugas.isNotEmpty || _isLoadingPetugas) return;

    setState(() => _isLoadingPetugas = true);

    try {
      final res = await DioClient().dio.get(
        '/api/pemeriksa/petugas',
        queryParameters: {
          'page': 1,
          'limit': 20,
          'survei_id': widget.surveiId,
          'pemeriksa_id': userId,
        },
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

      final parsed = rawList
          .whereType<Map<String, dynamic>>()
          .map(PetugasListItem.fromJson)
          .toList();

      setState(() {
        _petugas
          ..clear()
          ..addAll(parsed);

        if (_selectedPetugasId == null) {
          final firstValid = _petugas.cast<PetugasListItem?>().firstWhere(
            (e) => e?.id != null && (e?.name ?? '').trim().isNotEmpty,
            orElse: () => null,
          );
          _selectedPetugasId = firstValid?.id;
        }
        _isLoadingPetugas = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingPetugas = false);
    }
  }

  Future<void> _fetchLatestOrFiltered() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Default (tanpa filter)
      if (!_isFilterActive) {
        // GET https://trackingapi.bps.web.id/api/pemeriksa/lokasi/terbaru
        final res = await DioClient().dio.get(
          '/api/pemeriksa/lokasi/terbaru',
          queryParameters: {'survei_id': widget.surveiId},
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
            .map(PetugasLocation.fromJson)
            .where((p) => _isValidLatLng(p.latitude, p.longitude))
            .toList();

        // Untuk mode /lokasi/terbaru: tampilkan marker lokasi terakhir per petugas.
        final latestByPetugas = <int?, PetugasLocation>{};
        for (final p in parsed) {
          final key = p.userId; // dari respons: user_id = id petugas
          if (key == null) continue;
          final prev = latestByPetugas[key];
          if (prev == null) {
            latestByPetugas[key] = p;
            continue;
          }
          final prevT = prev.timestamp;
          final curT = p.timestamp;
          if (prevT == null && curT != null) {
            latestByPetugas[key] = p;
          } else if (prevT != null && curT != null && curT.isAfter(prevT)) {
            latestByPetugas[key] = p;
          }
        }

        final latestLocations = latestByPetugas.values.toList();

        setState(() {
          _locations
            ..clear()
            ..addAll(parsed);
          _latestLocations
            ..clear()
            ..addAll(latestLocations);
          _isLoading = false;

          if (parsed.isNotEmpty) {
            final first = parsed.first;
            _defaultCenter = LatLng(first.latitude!, first.longitude!);
            _mapController.move(_defaultCenter, 13);
          }
        });
        return;
      }

      // Filter aktif
      // Pada mode filter, marker khusus lokasi terakhir tidak ditampilkan.
      setState(() => _latestLocations.clear());

      final query = <String, dynamic>{
        'page': 1,
        'limit': 50,
        'survei_id': widget.surveiId,
      };

      if (_selectedPetugasId != null) {
        query['petugas_id'] = _selectedPetugasId;
      }
      if (_fromDate != null) {
        query['from'] = _formatApiDateTime(_fromDate!);
      }
      // to: 23:59:59 di tanggal yang sama (agar sama seperti curl)
      if (_fromDate != null) {
        final dtTo = DateTime(
          _fromDate!.year,
          _fromDate!.month,
          _fromDate!.day,
          23,
          59,
          59,
        );
        query['to'] = _formatApiDateTime(dtTo);
      }

      // GET https://trackingapi.bps.web.id/api/pemeriksa/lokasi?petugas_id=...&from=...&to=...
      final res = await DioClient().dio.get(
        '/api/pemeriksa/lokasi',
        queryParameters: query,
      );

      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception('Request failed: ${res.statusCode}');
      }

      final data = res.data;
      final listRaw = data is Map<String, dynamic> ? (data['data'] ?? []) : [];
      final rawList = listRaw is List ? listRaw : [];

      final parsed = rawList
          .whereType<Map<String, dynamic>>()
          .map(PetugasLocation.fromJson)
          .where((p) => _isValidLatLng(p.latitude, p.longitude))
          .toList();

      setState(() {
        _locations
          ..clear()
          ..addAll(parsed);
        _isLoading = false;

        if (parsed.isNotEmpty) {
          final first = parsed.first;
          _defaultCenter = LatLng(first.latitude!, first.longitude!);
          _mapController.move(_defaultCenter, 13);
        }
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  List<Polyline> get _polylines {
    if (_locations.isEmpty) return const [];
    if (_locations.length < 2) {
      // ignore: avoid_print
      print(
        '[PetugasTrackingPage] _locations.length=${_locations.length} (<2) => no polyline',
      );
      return const [];
    }

    // ignore: avoid_print
    print('[PetugasTrackingPage] _locations.length=${_locations.length}');

    final sorted = List<PetugasLocation>.from(_locations);
    sorted.sort((a, b) {
      final ta = a.timestamp;
      final tb = b.timestamp;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return ta.compareTo(tb);
    });

    final pts = sorted
        .where((p) => p.latitude != null && p.longitude != null)
        .map((p) => LatLng(p.latitude!, p.longitude!))
        .toList();

    if (pts.length < 2) return const [];

    // Buat polyline per segmen supaya visual benar-benar mengikuti urutan titik.
    // (Kadang garis multi-titik yang jaraknya sangat rapat terlihat seperti hanya 2 titik.)
    if (pts.length < 2) return const [];

    final segs = <Polyline>[];
    for (var i = 0; i < pts.length - 1; i++) {
      segs.add(
        Polyline(
          points: [pts[i], pts[i + 1]],
          strokeWidth: 4,
          color: Colors.blue.withAlpha(220),
          borderColor: Colors.white.withAlpha(200),
          borderStrokeWidth: 1.5,
        ),
      );
    }

    return segs;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tracking Petugas')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'Tracking Petugas',
                style: Theme.of(context).textTheme.titleLarge,
              ).animate().fadeIn(duration: 400.ms),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Filters
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<int>(
                          value: _selectedPetugasId,
                          isExpanded: true,
                          menuMaxHeight: 280,
                          isDense: true,
                          decoration: InputDecoration(
                            labelText: 'Petugas',
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                          ),
                          items: _petugas.isEmpty
                              ? [
                                  const DropdownMenuItem<int>(
                                    value: -1,
                                    enabled: false,
                                    child: Text('Loading petugas...'),
                                  ),
                                ]
                              : _petugas
                                    .where(
                                      (p) =>
                                          (p.id ?? -1) != -1 &&
                                          (p.name).trim().isNotEmpty,
                                    )
                                    .map(
                                      (p) => DropdownMenuItem<int>(
                                        value: p.id,
                                        child: Text(p.name),
                                      ),
                                    )
                                    .toList(),
                          onChanged: (v) {
                            setState(() {
                              _selectedPetugasId = v;
                            });
                            _fetchLatestOrFiltered();
                          },
                        ),
                      ),
                      SizedBox(
                        width: 190,
                        child: TextButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _fromDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (picked == null) return;
                            setState(() {
                              // from: 00:00:01 (agar inklusif seperti di curl)
                              _fromDate = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                                0,
                                0,
                                1,
                              );
                            });
                            _fetchLatestOrFiltered();
                          },
                          icon: const Icon(Icons.calendar_month),
                          label: Text(
                            _fromDate == null
                                ? 'Pilih Tanggal'
                                : 'Tanggal: ${_fromDate!.day.toString().padLeft(2, '0')}/${_fromDate!.month.toString().padLeft(2, '0')}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                      IconButton(
                        tooltip: 'Clear filter',
                        onPressed: _isFilterActive
                            ? () {
                                setState(() {
                                  _selectedPetugasId = null;
                                  _fromDate = null;
                                });
                                _fetchLatestOrFiltered();
                              }
                            : null,
                        icon: const Icon(Icons.filter_alt_off),
                      ),
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: _isLoading ? null : _fetchLatestOrFiltered,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchLatestOrFiltered,

                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _defaultCenter,
                        initialZoom: 13,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.ulos.app',
                        ),
                        if (_latestLocations.isNotEmpty)
                          MarkerLayer(
                            markers: _latestLocations
                                .where(
                                  (p) =>
                                      p.latitude != null && p.longitude != null,
                                )
                                .map(
                                  (p) => Marker(
                                    point: LatLng(p.latitude!, p.longitude!),
                                    width: 48,
                                    height: 48,
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Container(
                                        margin: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade600,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.person,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),

                        PolylineLayer(polylines: _polylines),
                      ],
                    ),
                    if (_isLoading)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: Color(0x33000000),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                    if (!_isLoading && _errorMessage != null)
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 20,
                        child: Card(
                          color: Colors.red.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'Gagal memuat data: $_errorMessage',
                              style: TextStyle(
                                color: Colors.red.shade900,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
