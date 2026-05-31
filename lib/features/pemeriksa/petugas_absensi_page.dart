import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:dio/dio.dart';

import '../../core/services/dio_client.dart';

class PetugasAbsensiPage extends StatefulWidget {
  const PetugasAbsensiPage({super.key});

  @override
  State<PetugasAbsensiPage> createState() => _PetugasAbsensiPageState();
}

class AbsensiItem {
  final int? id;
  final String? petugasName;
  final DateTime? tanggal;
  final String? status;

  const AbsensiItem({this.id, this.petugasName, this.tanggal, this.status});

  factory AbsensiItem.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    String? pickString(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v == null) continue;
        final s = v.toString();
        if (s.trim().isNotEmpty) return s;
      }
      return null;
    }

    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      final s = v.toString();
      if (s.trim().isEmpty) return null;
      try {
        return DateTime.parse(s);
      } catch (_) {
        return null;
      }
    }

    return AbsensiItem(
      id: parseInt(json['id']),
      // Backend contoh: user.name (mis. "Petugas Dummy 1")
      petugasName:
          pickString(['name', 'user_name', 'user_name_petugas']) ??
          json['user']?['name']?.toString(),
      tanggal: parseDate(json['created_at'] ?? json['tanggal']),
      status: pickString(['status', 'keterangan', 'absensi', 'state']),
    );
  }
}

class _PetugasAbsensiPageState extends State<PetugasAbsensiPage> {
  bool _isLoading = true;
  String? _errorMessage;

  DateTime? _selectedTanggal;

  final List<AbsensiItem> _items = [];

  String _toApiDate(DateTime dt) {
    // YYYY-MM-DD
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  String _tanggalKey(AbsensiItem item) {
    final dt = item.tanggal;
    if (dt == null) return 'Tanggal Tidak Diketahui';
    return _toApiDate(dt);
  }

  Map<String, List<AbsensiItem>> _groupAbsensiByTanggal(
    List<AbsensiItem> items,
  ) {
    final Map<String, List<AbsensiItem>> map = {};
    for (final item in items) {
      final key = _tanggalKey(item);
      map.putIfAbsent(key, () => <AbsensiItem>[]).add(item);
    }

    // Sort tanggal (YYYY-MM-DD) paling baru di atas jika formatnya valid.
    final entries = map.entries.toList();
    entries.sort((a, b) {
      final da = DateTime.tryParse(a.key);
      final db = DateTime.tryParse(b.key);
      if (da == null || db == null) return b.key.compareTo(a.key);
      return db.compareTo(da);
    });

    return Map<String, List<AbsensiItem>>.fromEntries(entries);
  }

  @override
  void initState() {
    super.initState();
    _fetchAbsensi();
  }

  Future<void> _fetchAbsensi() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final params = <String, dynamic>{'page': 1, 'limit': 200};
      if (_selectedTanggal != null) {
        params['tanggal'] = _toApiDate(_selectedTanggal!);
      }

      final res = await DioClient().dio.get(
        '/api/pemeriksa/absensi',
        queryParameters: params,
      );

      if (res.statusCode != 200) {
        throw Exception('Request failed: ${res.statusCode}');
      }

      final data = res.data;

      List<dynamic> rawList = [];
      if (data is List) {
        rawList = data;
      } else if (data is Map<String, dynamic>) {
        final inner = data['data'];
        if (inner is List) {
          rawList = inner;
        } else if (inner is Map<String, dynamic>) {
          final innerData = inner['data'];
          if (innerData is List) rawList = innerData;
        }
      }

      final parsed = rawList
          .whereType<Map<String, dynamic>>()
          .map((e) => AbsensiItem.fromJson(e))
          .toList();

      setState(() {
        _items
          ..clear()
          ..addAll(parsed);
        _isLoading = false;
      });
    } on DioException catch (e) {
      final msg = e.response?.data != null
          ? e.response!.data.toString()
          : e.message;

      setState(() {
        _errorMessage = 'Gagal memuat absensi: ${msg ?? 'unknown error'}';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Gagal memuat absensi: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Absen Petugas')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Absen Petugas',
                style: Theme.of(context).textTheme.titleLarge,
              ).animate().fadeIn(duration: 400.ms),
              const SizedBox(height: 8),

              // Filter tanggal: pilih satu tanggal saja
              _TanggalFilterBar(
                selected: _selectedTanggal,
                onClear: () {
                  setState(() => _selectedTanggal = null);
                  _fetchAbsensi();
                },
                onPick: (dt) {
                  setState(() => _selectedTanggal = dt);
                  _fetchAbsensi();
                },
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Builder(
                  builder: (_) {
                    if (_isLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (_errorMessage != null) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      );
                    }

                    if (_items.isEmpty) {
                      return const Center(
                        child: Text('Tidak ada data absensi.'),
                      );
                    }

                    final groupedByDate = _groupAbsensiByTanggal(_items);

                    return RefreshIndicator(
                      onRefresh: _fetchAbsensi,
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: groupedByDate.length,
                        itemBuilder: (context, dateIndex) {
                          final dateKey = groupedByDate.keys.elementAt(
                            dateIndex,
                          );
                          final itemsOnDate = groupedByDate[dateKey]!;

                          return _AbsensiDateSection(
                            tanggalKey: dateKey,
                            items: itemsOnDate,
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TanggalFilterBar extends StatelessWidget {
  final DateTime? selected;
  final ValueChanged<DateTime> onPick;
  final VoidCallback onClear;

  const _TanggalFilterBar({
    required this.selected,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final text = selected == null ? 'Pilih tanggal' : _formatUiDate(selected!);

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final initial =
                  selected ?? DateTime(now.year, now.month, now.day);

              final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(now.year - 5),
                lastDate: DateTime(now.year + 1),
              );

              if (picked != null) onPick(picked);
            },
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(text),
          ),
        ),
        const SizedBox(width: 12),
        if (selected != null)
          IconButton.filledTonal(
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Hapus filter',
          ),
      ],
    );
  }

  String _formatUiDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }
}

class _AbsensiDateSection extends StatefulWidget {
  final String tanggalKey;
  final List<AbsensiItem> items;

  const _AbsensiDateSection({required this.tanggalKey, required this.items});

  @override
  State<_AbsensiDateSection> createState() => _AbsensiDateSectionState();
}

class _AbsensiDateSectionState extends State<_AbsensiDateSection> {
  @override
  Widget build(BuildContext context) {
    final Map<String, List<AbsensiItem>> groupedByPetugas = {};
    for (final item in widget.items) {
      final k = (item.petugasName ?? 'Tanpa Nama').trim();
      groupedByPetugas.putIfAbsent(k, () => <AbsensiItem>[]).add(item);
    }

    // Stable sort petugas by name
    final petugasKeys = groupedByPetugas.keys.toList()..sort();

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Card(
        elevation: 0.5,
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: ExpansionTile(
          title: Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.tanggalKey,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          initiallyExpanded: false,
          childrenPadding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: petugasKeys.map((petugasName) {
                final itemsOnPetugas = groupedByPetugas[petugasName]!;
                final count = itemsOnPetugas.length;

                return ExpansionTile(
                  key: PageStorageKey('${widget.tanggalKey}_$petugasName'),
                  title: Text(
                    '$petugasName (x$count)',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  initiallyExpanded: false,
                  childrenPadding: const EdgeInsets.only(
                    left: 12,
                    right: 12,
                    bottom: 10,
                  ),
                  children: [
                    _AbsensiPetugasCard(
                      petugasName: petugasName,
                      items: itemsOnPetugas,
                      showCardShell: false,
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _AbsensiPetugasCard extends StatelessWidget {
  final String petugasName;
  final List<AbsensiItem> items;
  final bool showCardShell;

  const _AbsensiPetugasCard({
    required this.petugasName,
    required this.items,
    this.showCardShell = true,
  });

  @override
  Widget build(BuildContext context) {
    // Sort items by tanggal descending if possible
    final sorted = items.toList()
      ..sort((a, b) {
        final da = a.tanggal;
        final db = b.tanggal;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

    final cardBody = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                child: Text(
                  petugasName.isNotEmpty ? petugasName.characters.first : '?',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  petugasName.isNotEmpty ? petugasName : 'Tanpa Nama',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (sorted.isNotEmpty)
                Text(
                  'x${sorted.length}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ...sorted.map((item) => _AbsensiStatusRow(item: item)),
        ],
      ),
    );

    if (!showCardShell) {
      // used as children inside ExpansionTile -> avoid nested card UI
      return cardBody;
    }

    return Card(
      elevation: 0.5,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: cardBody,
    );
  }
}

class _AbsensiStatusRow extends StatelessWidget {
  final AbsensiItem item;

  const _AbsensiStatusRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final status = (item.status ?? '').trim();

    Color statusColor = Theme.of(context).colorScheme.onSurface;
    if (status.isNotEmpty) {
      final s = status.toLowerCase();
      if (s.contains('hadir') || s.contains('masuk')) {
        statusColor = Colors.green;
      } else if (s.contains('izin') || s.contains('i')) {
        statusColor = Colors.orange;
      } else if (s.contains('alpha') ||
          s.contains('tidak') ||
          s.contains('bolos')) {
        statusColor = Colors.red;
      } else {
        statusColor = Theme.of(context).colorScheme.primary;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.circle, size: 10, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status.isNotEmpty ? status : '—',
              style: TextStyle(fontWeight: FontWeight.w600, color: statusColor),
            ),
          ),
        ],
      ),
    );
  }
}
