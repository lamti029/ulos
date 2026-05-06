import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../../core/constants/app_colors.dart';
import '../../core/services/dio_client.dart';
import '../../core/services/security_check_service.dart';
import '../../core/utils/jwt_utils.dart';
import '../profile/profile_page.dart';
import '../tracking/tracking_page.dart';
import '../history/history_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  bool _isChecking = false;
  String _userName = 'Pengguna';
  Timer? _trackingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserName();
    _checkTrackingStatus();
    _startTrackingPolling();
  }

  void _startTrackingPolling() {
    _trackingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
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

  Future<void> _navigateToTracking(BuildContext context) async {
    if (_isChecking) return;
    setState(() => _isChecking = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Izin lokasi diperlukan untuk melanjutkan.'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Access to location services is restricted.\\nYou can grant permission manually in the app settings.',
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final securityResult = await SecurityCheckService.performChecks();

      if (!context.mounted) return;

      if (!securityResult.isSecure) {
        _showSecurityWarning(context, securityResult.warnings);
        return;
      }

      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const TrackingPage()));
    } finally {
      if (mounted) setState(() => _isChecking = false);
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ulos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ProfilePage())),
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
                  Text(
                    'Menu',
                    style: Theme.of(context).textTheme.titleLarge,
                  ).animate().fadeIn(duration: 500.ms, delay: 200.ms),
                  const SizedBox(height: 16),
                  _MenuCard(
                        icon: Icons.gps_fixed_rounded,
                        iconColor: AppColors.success,
                        iconBgColor: AppColors.success.withAlpha(26),
                        title: 'Live Tracking',
                        subtitle:
                            'Track your location in real-time with target destinations',
                        onTap: _isChecking
                            ? null
                            : () => _navigateToTracking(context),
                      )
                      .animate()
                      .fadeIn(duration: 600.ms, delay: 300.ms)
                      .slideX(
                        begin: -0.2,
                        end: 0,
                        duration: 600.ms,
                        delay: 300.ms,
                      ),
                  const SizedBox(height: 16),
                  _MenuCard(
                        icon: Icons.history_rounded,
                        iconColor: AppColors.warning,
                        iconBgColor: AppColors.warning.withAlpha(26),
                        title: 'History Tracking',
                        subtitle: 'View your past tracking sessions and routes',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const HistoryPage(),
                          ),
                        ),
                      )
                      .animate()
                      .fadeIn(duration: 600.ms, delay: 400.ms)
                      .slideX(
                        begin: -0.2,
                        end: 0,
                        duration: 600.ms,
                        delay: 400.ms,
                      ),
                  const SizedBox(height: 32),
                ],
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

  const _MenuCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
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
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        height: 1.4,
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
