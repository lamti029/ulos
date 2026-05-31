import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
    return PetugasLocation(
      id: _parseInt(json['id']),
      userId: _parseInt(json['user_id']),
      surveiId: _parseInt(json['survei_id']),
      namaPetugas:
          json['nama_petugas']?.toString() ?? json['user']?['name']?.toString(),
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

  Timer? _refreshTimer;

  final MapController _mapController = MapController();

  LatLng _defaultCenter = const LatLng(-6.2088, 106.8456);

  // Filters
  int? _selectedPetugasId;
  DateTime? _fromDate;

  final List<PetugasListItem> _petugas = [];

  bool _isLoadingPetugas = false;

  bool get _isFilterActive => _selectedPetugasId != null || _fromDate != null;

  @override
  void initState() {
    super.initState();
    _fetchPetugasIfNeeded();
    _fetchLatestOrFiltered();

    // Auto refresh tidak diperlukan (biar tidak spam request).
    // Refresh cukup melalui tombol refresh / pull-to-refresh.
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
    if (_petugas.isNotEmpty || _isLoadingPetugas) return;

    setState(() => _isLoadingPetugas = true);

    try {
      final res = await DioClient().dio.get(
        '/api/pemeriksa/petugas',
        queryParameters: {'page': 1, 'limit': 20, 'survei_id': widget.surveiId},
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

        // Auto-select pertama agar filter tanggal tidak memerlukan petugas manual.
        if (_selectedPetugasId == null && _petugas.isNotEmpty) {
          _selectedPetugasId = _petugas.first.id;
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
        return;
      }

      // Filter aktif
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

  List<Marker> get _markers {
    return _locations.asMap().entries.map((entry) {
      final idx = entry.key;
      final loc = entry.value;
      final lat = loc.latitude!;
      final lng = loc.longitude!;
      final nama = (loc.namaPetugas ?? 'Petugas').trim();
      final timestampStr = _formatTimestamp(loc.timestamp);

      // Backend filter uses `petugas_id`; payload umumnya tersedia sebagai `user_id`.
      final int? petugasIdForTracking = loc.userId ?? loc.id;

      return Marker(
        key: ValueKey('${loc.id ?? idx}_$lat,$lng'),
        point: LatLng(lat, lng),
        width: 44,
        height: 44,
        child: GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (context) {
                return AlertDialog(
                  title: Text(nama),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (timestampStr != null) Text('Waktu: $timestampStr'),
                      const SizedBox(height: 8),
                      Text('Lat: ${lat.toStringAsFixed(6)}'),
                      Text('Lng: ${lng.toStringAsFixed(6)}'),
                      if (loc.accuracy != null)
                        Text('Akurasi: ${loc.accuracy} m'),
                      if (loc.batteryLevel != null)
                        Text('Baterai: ${loc.batteryLevel}%'),
                      if (loc.isMocked != null)
                        Text('Mock: ${loc.isMocked == true ? 'Ya' : 'Tidak'}'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Tutup'),
                    ),
                    // if (petugasIdForTracking != null)
                    //   ElevatedButton.icon(
                    //     onPressed: () async {
                    //       final picked = await showDatePicker(
                    //         context: context,
                    //         initialDate: _fromDate ?? DateTime.now(),
                    //         firstDate: DateTime(2020),
                    //         lastDate: DateTime.now(),
                    //       );
                    //       if (picked == null) return;

                    //       setState(() {
                    //         _selectedPetugasId = petugasIdForTracking;
                    //         _fromDate = DateTime(
                    //           picked.year,
                    //           picked.month,
                    //           picked.day,
                    //           0,
                    //           0,
                    //           1,
                    //         );
                    //       });

                    //       Navigator.pop(context);
                    //       await _fetchLatestOrFiltered();
                    //     },
                    //     icon: const Icon(Icons.track_changes),
                    //     label: const Text('Track'),
                    //   ),
                  ],
                );
              },
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
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
            child: const Icon(Icons.location_on, color: Colors.white, size: 24),
          ),
        ),
      );
    }).toList();
  }

  List<Polyline> get _polylines {
    // Buat polyline dari urutan lokasi yang diterima
    if (_locations.length < 2) return const [];

    final points = _locations
        .where((p) => p.latitude != null && p.longitude != null)
        .map((p) => LatLng(p.latitude!, p.longitude!))
        .toList();

    if (points.length < 2) return const [];

    // Optimasi polyline: render hanya “dua titik” (awal & akhir) ketika jumlah titik banyak,
    // agar tidak terlihat seperti cluster titik dan lebih enak dilihat.
    if (points.length > 2) {
      return [
        Polyline(
          points: [points.first, points.last],
          strokeWidth: 4,
          color: Colors.blue.withAlpha(220),
          borderColor: Colors.white.withAlpha(200),
          borderStrokeWidth: 1.5,
        ),
      ];
    }

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
                          decoration: const InputDecoration(
                            labelText: 'Pilih Petugas',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: _petugas.isEmpty
                              ? [
                                  const DropdownMenuItem<int>(
                                    value: null,
                                    enabled: false,
                                    child: Text('Loading petugas...'),
                                  ),
                                ]
                              : _petugas
                                    .where((p) => (p.name).trim().isNotEmpty)
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
                                ? 'From'
                                : 'From: ${_fromDate!.day.toString().padLeft(2, '0')}/${_fromDate!.month.toString().padLeft(2, '0')}',
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
                  const SizedBox(height: 6),
                  Text(
                    _locations.isEmpty
                        ? 'Belum ada data lokasi.'
                        : 'Menampilkan ${_locations.length} petugas.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
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
                        PolylineLayer(polylines: _polylines),
                        MarkerLayer(markers: _markers),
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
