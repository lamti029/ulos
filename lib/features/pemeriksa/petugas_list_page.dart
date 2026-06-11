import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:ulos/core/models/survey.dart';

import '../../core/services/dio_client.dart';

class PetugasListPage extends StatefulWidget {
  final SurveyModel survey;

  const PetugasListPage({super.key, required this.survey});

  @override
  State<PetugasListPage> createState() => _PetugasListPageState();
}

class PetugasListItem {
  final int? id;
  final String name;
  final String? email;
  final String? role;

  const PetugasListItem({required this.name, this.id, this.email, this.role});

  factory PetugasListItem.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    final dynamic petugasJson = json['petugas'];

    Map<String, dynamic>? petugasObj;
    if (petugasJson is Map<String, dynamic>) {
      petugasObj = petugasJson;
    } else if (petugasJson is List && petugasJson.isNotEmpty) {
      final first = petugasJson.first;
      if (first is Map<String, dynamic>) {
        petugasObj = first;
      }
    }

    final rawName =
        (petugasObj != null
                ? (petugasObj!['name'] ??
                      petugasObj!['nama'] ??
                      petugasObj!['nama_petugas'] ??
                      petugasObj!['petugas_nama'] ??
                      '')
                : (json['name'] ?? json['nama'] ?? json['nama_petugas'] ?? ''))
            .toString();

    final rawId = (petugasObj != null)
        ? (petugasObj!['id'] ??
              petugasObj!['petugas_id'] ??
              petugasObj!['user_id'])
        : (json['id'] ?? json['petugas_id'] ?? json['user_id']);

    final rawEmail = (petugasObj != null)
        ? petugasObj!['email']
        : json['email'];

    final rawRole = (petugasObj != null) ? petugasObj!['role'] : json['role'];

    return PetugasListItem(
      id: parseInt(rawId),
      name: rawName.isNotEmpty ? rawName : 'Tanpa Nama',
      email: rawEmail?.toString(),
      role: rawRole?.toString(),
    );
  }
}

class _PetugasListPageState extends State<PetugasListPage> {
  bool _isLoading = true;
  String? _errorMessage;
  int get _surveiId => widget.survey.id;

  final List<PetugasListItem> _items = [];

  @override
  void initState() {
    super.initState();
    _fetchPetugas(); // Sekarang aman dipanggil tanpa parameter
  }

  Future<void> _fetchPetugas() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final Map<String, dynamic> queryParams = {'page': 1, 'limit': 20};

      queryParams['survei_id'] = _surveiId;

      final res = await DioClient().dio.get(
        '/api/pemeriksa/petugas',
        queryParameters: queryParams,
      );

      if (res.statusCode != 200) {
        throw Exception('Request failed: ${res.statusCode}');
      }

      final data = res.data;

      final List<dynamic> rawList =
          (data is Map<String, dynamic> && data['data'] is List)
          ? (data['data'] as List<dynamic>)
          : (data is List)
          ? data
          : [];

      final parsed = rawList
          .whereType<Map<String, dynamic>>()
          .map((e) => PetugasListItem.fromJson(e))
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
        _errorMessage = 'Gagal memuat petugas: ${msg ?? 'unknown error'}';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Gagal memuat petugas: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daftar Petugas')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lihat Daftar Petugas',
                style: Theme.of(context).textTheme.titleLarge,
              ).animate().fadeIn(duration: 400.ms),
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
                        child: Text('Tidak ada data petugas.'),
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: _fetchPetugas,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return _PetugasTile(item: item);
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

class _PetugasTile extends StatelessWidget {
  final PetugasListItem item;

  const _PetugasTile({required this.item});

  @override
  Widget build(BuildContext context) {
    // Memperbaiki logic join text agar null-safe dan rapi
    final subtitleParts = [
      item.email,
      item.role,
    ].where((s) => s != null && s.isNotEmpty).toList();

    final subtitleText = subtitleParts.isNotEmpty
        ? subtitleParts.join(' • ')
        : '—';

    return Card(
      elevation: 1,
      child: ListTile(
        title: Text(item.name),
        subtitle: Text(subtitleText),
        leading: CircleAvatar(
          child: Text(
            item.name.isNotEmpty
                ? item.name.trim().characters.first.toUpperCase()
                : '?',
          ),
        ),
        onTap: () {
          // Placeholder detail petugas
        },
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0);
  }
}
