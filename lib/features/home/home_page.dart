import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';
import '../../core/constants/app_colors.dart';
import '../../core/services/dio_client.dart';
import '../../core/utils/jwt_utils.dart';
import '../profile/profile_page.dart';

import '../../core/models/survey.dart';
import '../../core/services/survey_service.dart';
import 'survey_cache_service.dart';
import 'sub_menu_survey_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  String _userName = 'Pengguna';
  Timer? _trackingTimer;

  final SurveyService _surveyService = SurveyService();
  List<SurveyModel> _surveys = const [];
  int? _selectedSurveiId;
  bool _isLoadingSurveys = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserName();
    _loadSurveysFromCacheThenMaybeRefresh();
    // _checkTrackingStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkTrackingStatus();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _checkTrackingStatus(),
      );
    }
  }

  Future<void> _checkTrackingStatus() async {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _trackingTimer?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _loadUserName() async {
    var name = await DioClient().getUserName();

    if (name == null || name.isEmpty) {
      name = await JwtUtils.getUserName();
      if (name != null && name.isNotEmpty) {
        await DioClient().setUserName(name);
      }
    }

    if (mounted) {
      setState(() {
        _userName = name ?? 'Pengguna';
      });
    }
  }

  Future<void> _loadSurveysFromCacheThenMaybeRefresh({
    bool force = false,
  }) async {
    setState(() {
      _isLoadingSurveys = true;
    });

    try {
      final cached = await SurveyCacheService.loadCachedSurveys();

      if (!mounted) return;
      setState(() {
        _surveys = cached;
        _selectedSurveiId = cached.isNotEmpty ? cached.first.id : null;
        _isLoadingSurveys = false;
      });

      // Requirement: refresh survei hanya manual (tidak auto-refresh).
      // Tombol manual dibatasi: paling cepat 1x per jam.
      if (!force) return;

      final canRefresh = await SurveyCacheService.canRefreshNow(force: force);
      if (!canRefresh) return;

      final fresh = await _surveyService.fetchSurveys();

      if (!mounted) return;
      setState(() {
        _surveys = fresh;
        _selectedSurveiId = fresh.isNotEmpty ? fresh.first.id : null;
        _isLoadingSurveys = false;
      });

      await SurveyCacheService.saveSurveysToCache(fresh);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        // Keep whatever we already had (possibly cached).
        _isLoadingSurveys = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memuat survei: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showSecurityWarning(BuildContext context, List<String> warnings) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: AppColors.warning,
              size: 28,
            ),
            const SizedBox(width: 8),
            const Text('Security Alert'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: warnings
              .map(
                (w) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontSize: 16)),
                      Expanded(child: Text(w)),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('ULOS'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          tooltip: 'Home',
          onPressed: () {},
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded),
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ProfilePage()));
            },
            tooltip: 'Profile',
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withAlpha(77),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                  'Halo, $_userName',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                )
                                .animate()
                                .fadeIn(duration: 500.ms)
                                .slideY(begin: 0.2, end: 0),
                            const Icon(
                              Icons.navigation_rounded,
                              size: 40,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Welcome to ULOS',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Start tracking your missions and explore new destinations with real-time navigation.',
                              style: TextStyle(
                                color: Colors.white.withAlpha(204),
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      )
                      .animate()
                      .fadeIn(duration: 600.ms)
                      .slideY(begin: 0.2, end: 0, duration: 600.ms),
                  const SizedBox(height: 28),

                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Daftar Survei',
                          style: Theme.of(context).textTheme.titleLarge,
                        ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        icon: const Icon(Icons.sync_rounded),
                        label: const Text('Refresh'),
                        onPressed: () async {
                          await _loadSurveysFromCacheThenMaybeRefresh(
                            force: true,
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  if (_isLoadingSurveys)
                    const Center(child: CircularProgressIndicator())
                  else if (_surveys.isNotEmpty)
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _surveys.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final s = _surveys[index];
                        return _SurveyMenuCard(
                          icon: Icons.map_outlined,
                          iconColor: AppColors.background,
                          iconBgColor: AppColors.background.withAlpha(26),
                          cardBgColor: AppColors.secondary,
                          title: s.displayName,
                          subtitle: 'Tap to open tracking menu',

                          onTap: () {
                            setState(() => _selectedSurveiId = s.id);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SubMenuSurveyPage(survey: s),
                              ),
                            );
                          },
                          animateDelayMs: 100 + (index * 60),
                        );
                      },
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Tidak ada survei tersedia'),
                    ),

                  const SizedBox(height: 32),
                ],

                // ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color? titleColor;
  final Color? subtitleColor;

  /// Background card color.
  /// Set to match Splash theme (primary/secondary) instead of default Card color.
  final Color cardBgColor;

  const _MenuCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.cardBgColor,
    this.titleColor,
    this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: cardBgColor,
      elevation: 2,
      shadowColor: AppColors.cardShadow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        height: 1.4,
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary.withAlpha(153),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SurveyMenuCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final Color cardBgColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final int animateDelayMs;

  const _SurveyMenuCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.cardBgColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.animateDelayMs,
  });

  @override
  Widget build(BuildContext context) {
    final cardBgColor = AppColors.secondary;
    final titleColor = Colors.white;
    final subtitleColor = Colors.white;

    return _MenuCard(
          icon: icon,
          iconColor: iconColor,
          iconBgColor: iconBgColor,
          cardBgColor: cardBgColor,
          title: title,
          subtitle: subtitle,
          titleColor: titleColor,
          subtitleColor: subtitleColor,
          onTap: onTap,
        )
        .animate()
        .fadeIn(duration: 500.ms, delay: animateDelayMs.ms)
        .slideX(
          begin: -0.2,
          end: 0,
          duration: 500.ms,
          delay: animateDelayMs.ms,
        );
  }
}
