import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ulos/core/models/petugas_location.dart';
import 'package:ulos/core/utils/jwt_utils.dart';

import '../../core/services/dio_client.dart';
import '../../core/services/wilayah_service.dart';
import 'petugas_list_page.dart' show PetugasListItem;

class PetugasTrackingPage extends StatefulWidget {
  final int surveiId;

  const PetugasTrackingPage({super.key, required this.surveiId});

  @override
  State<PetugasTrackingPage> createState() => _PetugasTrackingPageState();
}

class _PetugasTrackingPageState extends State<PetugasTrackingPage> {
  bool _isLoading = true;
  String? _errorMessage;

  Future<void> _showPetugasInfoDialog(PetugasLocation p) async {
    final nama = (p.namaPetugas ?? '').trim();
    final title = nama.isNotEmpty ? nama : 'Petugas';

    String? ts = _formatTimestamp(p.timestamp);

    String? fmtNum(num? v, {String suffix = ''}) {
      if (v == null) return null;
      return '${v.toString()}$suffix';
    }

    await showDialog<void>(
      context: context,
      builder: (_) {
        final items = <Widget>[];

        void addRow(String label, String? value) {
          if (value == null || value.trim().isEmpty) return;
          items.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w400,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        addRow('Waktu', ts);
        addRow('Lat', p.latitude?.toString());
        addRow('Lng', p.longitude?.toString());
        addRow('Akurasi', fmtNum(p.accuracy));
        addRow('Speed', fmtNum(p.speed));
        addRow('Altitude', fmtNum(p.altitude));
        addRow('Battery', fmtNum(p.batteryLevel, suffix: '%'));
        addRow(
          'Mocked',
          p.isMocked == null ? null : (p.isMocked! ? 'Ya' : 'Tidak'),
        );

        if (items.isEmpty) {
          items.add(
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Tidak ada detail tambahan.'),
            ),
          );
        }

        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: items,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }

  final List<PetugasLocation> _locations = [];
  final List<PetugasLocation> _latestLocations = [];

  Timer? _refreshTimer;

  final MapController _mapController = MapController();

  LatLng _defaultCenter = const LatLng(-6.2088, 106.8456);

  // Filters
  int? _selectedPetugasId;
  DateTime? _fromDate;

  // Wilayah
  List<Polygon> _wilayahPolygons = [];
  List<Map<String, dynamic>> _wilayahData = [];

  final List<PetugasListItem> _petugas = [];
  int? pemeriksaId;
  bool _isLoadingPetugas = false;

  bool get _isFilterActive => _selectedPetugasId != null || _fromDate != null;

  @override
  void initState() {
    super.initState();
    _fetchPetugasIfNeeded();
    _fetchLatestOrFiltered();
    _initWilayah();

    _refreshTimer = null;
  }

  Future<void> _initWilayah() async {
    final role = 'pemeriksa';
    await WilayahService.initFor(surveiId: widget.surveiId, role: role);

    if (!mounted) return;
    setState(() {
      _wilayahPolygons = WilayahService.wilayahPolygons;
      _wilayahData = WilayahService.wilayahData;
    });
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

      final parsed = rawList.whereType<Map<String, dynamic>>().expand((item) {
        final petugasRaw = item['petugas'];
        if (petugasRaw is List) {
          return petugasRaw.whereType<Map<String, dynamic>>().map(
            (petugasObj) => PetugasListItem.fromJson(<String, dynamic>{
              ...petugasObj,
              'petugas': petugasObj,
            }),
          );
        }
        return [PetugasListItem.fromJson(item)];
      }).toList();

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

  Future<void> _showPolygonSelector(
    BuildContext context,
    List<Polygon> wilayahPolygons,
    List<Map<String, dynamic>> wilayahData,
    void Function(List<Polygon>) onSelected,
  ) async {
    if (wilayahPolygons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada wilayah polygon tersedia'),
          backgroundColor: Colors.red,
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
                          color: Theme.of(
                            builderContext,
                          ).colorScheme.onSurface.withOpacity(0.25),
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
                        activeColor: Theme.of(
                          builderContext,
                        ).colorScheme.primary,
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
                            activeColor: Theme.of(
                              builderContext,
                            ).colorScheme.primary,
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
                          backgroundColor: Theme.of(
                            builderContext,
                          ).colorScheme.primary,
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

  Future<void> _fetchLatestOrFiltered() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (!_isFilterActive) {
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

        final latestByPetugas = <int?, PetugasLocation>{};
        for (final p in parsed) {
          final key = p.userId;
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

    debugPrint('[PetugasTrackingPage] _locations.length=${_locations.length}');

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

    if (pts.isEmpty) return const [];

    final segs = <Polyline>[];
    for (var i = 0; i < pts.length - 1; i++) {
      segs.add(
        Polyline(
          points: [pts[i], pts[i + 1]],
          strokeWidth: 4,
          color: Colors.blue.withAlpha(220),
          borderColor: Colors.white.withAlpha(200),
          borderStrokeWidth: 2,
        ),
      );
    }

    return segs;
  }

  Widget _buildPetugasItem(
    BuildContext context,
    PetugasListItem p, {
    bool dense = true,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    final verticalPadding = dense ? 6.0 : 8.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: verticalPadding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999), // Bentuk Elips Sempurna
        color: primary.withOpacity(0.08),
        border: Border.all(color: primary.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withOpacity(0.16),
            ),
            child: Icon(Icons.person, size: 14, color: primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final petugasFiltered = _petugas
        .where((p) => (p.id ?? -1) != -1 && (p.name).trim().isNotEmpty)
        .toList();

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
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: DropdownButtonFormField<int>(
                          alignment: Alignment.bottomLeft,
                          value:
                              (_selectedPetugasId == null ||
                                  _selectedPetugasId == -1)
                              ? null
                              : _selectedPetugasId,
                          isExpanded: true,
                          menuMaxHeight: 320,
                          isDense: true,
                          decoration: InputDecoration(
                            labelText: 'Petugas',
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            filled: true,
                            fillColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withOpacity(0.15),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 1.5,
                              ),
                            ),
                          ),
                          icon: Icon(
                            Icons.keyboard_arrow_down,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          dropdownColor: Theme.of(context).cardColor,
                          hint: const Text('Pilih Petugas'),
                          items: _petugas.isEmpty
                              ? [
                                  const DropdownMenuItem<int>(
                                    value: -1,
                                    enabled: false,
                                    child: Text('Loading petugas...'),
                                  ),
                                ]
                              : [
                                  const DropdownMenuItem<int>(
                                    value: null,
                                    child: Text('Pilih Petugas'),
                                  ),
                                  ...petugasFiltered.map(
                                    (p) => DropdownMenuItem<int>(
                                      value: p.id,
                                      child: _buildPetugasItem(
                                        context,
                                        p,
                                        dense: true,
                                      ),
                                    ),
                                  ),
                                ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _selectedPetugasId = v;
                            });
                            _fetchLatestOrFiltered();
                          },
                          selectedItemBuilder: (context) {
                            if (_petugas.isEmpty) {
                              return [const Text('Loading petugas...')];
                            }
                            return [
                              const Text('Pilih Petugas'),
                              ...petugasFiltered.map((p) {
                                return Row(
                                  children: [
                                    Icon(
                                      Icons.person,
                                      size: 18,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        p.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ];
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
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onTap: () {
                                        _showPetugasInfoDialog(p);
                                      },
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
                                  ),
                                )
                                .toList(),
                          ),
                        if (_wilayahPolygons.isNotEmpty)
                          PolygonLayer(polygons: _wilayahPolygons),
                        PolylineLayer(polylines: _polylines),
                      ],
                    ),

                    // FAB zoom_polygon (same placement style as tracking_page)
                    Positioned(
                      bottom: 400,
                      right: 16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FloatingActionButton.small(
                            heroTag: 'zoom_polygon',
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            foregroundColor: Colors.green,
                            onPressed: _wilayahPolygons.isEmpty
                                ? null
                                : () => _showPolygonSelector(
                                    context,
                                    _wilayahPolygons,
                                    _wilayahData,
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

                                      _mapController.fitCamera(
                                        CameraFit.bounds(
                                          bounds: bounds,
                                          padding: const EdgeInsets.all(50),
                                        ),
                                      );
                                    },
                                  ),
                            child: const Icon(Icons.crop_free),
                          ),
                        ],
                      ),
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
