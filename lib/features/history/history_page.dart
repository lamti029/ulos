import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/location_entity.dart';
import '../../core/services/location_repository.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final LocationRepository _repository = LocationRepository();

  List<LocationEntity> _locations = [];
  List<LatLng> _routePoints = [];
  bool _isLoading = true;

  // Date filters
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    List<LocationEntity> locations;
    if (_startDate != null && _endDate != null) {
      locations = await _repository.getBetween(
        start: _startDate!,
        end: _endDate!
            .add(const Duration(days: 1))
            .subtract(const Duration(seconds: 1)),
      );
    } else {
      locations = await _repository.getAll(limit: 500);
    }

    final routePoints = locations.map((l) => l.toLatLng()).toList();

    if (mounted) {
      setState(() {
        _locations = locations;
        _routePoints = routePoints;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All History'),
        content: const Text(
          'Are you sure you want to delete all tracking history from local database?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _repository.deleteAll();
      if (mounted) {
        setState(() {
          _locations = [];
          _routePoints = [];
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('All history cleared')));
      }
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 1)),
              end: now,
            ),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      await _loadData();
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'All time';
    return DateFormat('dd MMM yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History Tracking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _pickDateRange,
            tooltip: 'Filter by date',
          ),
          if (_locations.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearAll,
              tooltip: 'Clear All',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  // Date filter chip
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_formatDate(_startDate)} - ${_formatDate(_endDate)}',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_locations.length} points',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Map with route
                  if (_routePoints.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            height: 240,
                            child: FlutterMap(
                              options: MapOptions(
                                initialCenter: _routePoints.first,
                                initialZoom: 14,
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.ulos.app',
                                ),
                                PolylineLayer(
                                  polylines: [
                                    Polyline(
                                      points: _routePoints,
                                      strokeWidth: 4,
                                      color: AppColors.primary,
                                    ),
                                  ],
                                ),
                                MarkerLayer(
                                  markers: [
                                    // Start marker
                                    Marker(
                                      point: _routePoints.first,
                                      width: 36,
                                      height: 36,
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          color: AppColors.success,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                    // End marker
                                    if (_routePoints.length > 1)
                                      Marker(
                                        point: _routePoints.last,
                                        width: 36,
                                        height: 36,
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            color: AppColors.error,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.stop,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ).animate().fadeIn(duration: 400.ms),
                    ),

                  // Location list
                  if (_locations.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 24,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Location Points',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_locations.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final loc = _locations[index];
                          return _LocationCard(
                                latitude: loc.lat.toStringAsFixed(6),
                                longitude: loc.lng.toStringAsFixed(6),
                                timestamp: _formatDateTime(loc.timestamp),
                                isSynced: loc.isSynced,
                                index: index + 1,
                              )
                              .animate()
                              .fadeIn(duration: 400.ms, delay: (index * 50).ms)
                              .slideX(
                                begin: 0.2,
                                end: 0,
                                duration: 400.ms,
                                delay: (index * 50).ms,
                              );
                        }, childCount: _locations.length),
                      ),
                    ),

                  if (_locations.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.history_rounded,
                              size: 80,
                              color: AppColors.textSecondary.withAlpha(77),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No History Yet',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Start tracking to see your history here',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
            ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('dd MMM yyyy, HH:mm:ss').format(dateTime.toLocal());
  }
}

class _LocationCard extends StatelessWidget {
  final String latitude;
  final String longitude;
  final String timestamp;
  final bool isSynced;
  final int index;

  const _LocationCard({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.isSynced,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSynced
                    ? AppColors.success.withAlpha(26)
                    : AppColors.primary.withAlpha(26),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isSynced
                    ? const Icon(
                        Icons.cloud_done,
                        color: AppColors.success,
                        size: 18,
                      )
                    : Text(
                        '$index',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lat: $latitude, Lng: $longitude',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timestamp,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  if (!isSynced)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Pending sync',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.gps_not_fixed, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }
}
