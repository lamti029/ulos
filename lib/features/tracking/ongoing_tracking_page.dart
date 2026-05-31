import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/scheduler_service.dart';

class OngoingTrackingPage extends StatefulWidget {
  final int surveiId;
  final String? surveyName;
  final String? roleInSurvei;

  const OngoingTrackingPage({
    super.key,
    required this.surveiId,
    this.surveyName,
    this.roleInSurvei,
  });

  @override
  State<OngoingTrackingPage> createState() => _OngoingTrackingPageState();
}

class _OngoingTrackingPageState extends State<OngoingTrackingPage> {
  bool _isRunning = false;
  int _pendingSyncCount = 0;

  bool _isLoading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();

    // Keep UI consistent even if background service changes after user
    // navigates to this page.
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;

    final isRunning = await SchedulerService.isRunning;
    final pending = isRunning
        ? await SchedulerService().getPendingSyncCount()
        : 0;

    if (!mounted) return;

    setState(() {
      _isRunning = isRunning;
      _pendingSyncCount = pending;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ongoing Tracking'),
        actions: [
          if (widget.surveyName != null || widget.roleInSurvei != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.surveyName != null)
                    Text(
                      widget.surveyName!.toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  if (widget.roleInSurvei != null)
                    Text(
                      widget.roleInSurvei!.toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                ],
              ),
            ),
        ],
      ),

      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: _isRunning
                          ? _buildRunningCard()
                          : _buildIdleCard(),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
    );
  }

  Widget _buildRunningCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.success.withAlpha(26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withAlpha(140)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.success.withAlpha(26),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.my_location,
                  color: AppColors.success,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Tracking sedang berjalan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.2, end: 0),
          const SizedBox(height: 12),
          Text(
            'Background process aktif: lokasi sedang direkam dan disimpan secara lokal.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          if (_pendingSyncCount > 0)
            Text(
              'Pending sync: $_pendingSyncCount lokasi.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Text(
              'Sync berjalan otomatis saat tersedia.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _buildIdleCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.textSecondary.withAlpha(80)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withAlpha(20),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.pause_circle_outline,
              color: AppColors.textSecondary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tidak ada tracking aktif',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Jika Anda memulai tracking dari Live Tracking, status akan muncul di sini.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
