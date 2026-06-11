import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/constants/app_colors.dart';
import '../history/history_page.dart';
import '../pemeriksa/petugas_absensi_page.dart';
import '../tracking/tracking_page.dart';
import 'home_page.dart';

import '../../core/models/survey.dart';

class SubMenuSurveyPage extends StatelessWidget {
  final SurveyModel survey;

  const SubMenuSurveyPage({super.key, required this.survey});

  Future<void> _goTo(BuildContext context, Widget page) async {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final widgetTitleText = (survey.title != null && survey.title!.isNotEmpty)
        ? survey.title!
        : (survey.nama != null && survey.nama!.isNotEmpty)
        ? survey.nama!
        : 'Tracking';

    final roleInSurvei = survey.roleInSurvei?.toString().toLowerCase().trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widgetTitleText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Home',
          onPressed: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const HomePage()));
          },
        ),
      ),

      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pilih menu tracking',
                style: Theme.of(context).textTheme.titleLarge,
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.15, end: 0),
              const SizedBox(height: 16),
              _MenuCard(
                icon: Icons.gps_fixed_rounded,
                iconColor: AppColors.success,
                iconBgColor: AppColors.success.withAlpha(26),
                title: 'Live Tracking',
                subtitle:
                    'Track your location in real-time with target destinations',
                onTap: () => _goTo(context, TrackingPage(survey: survey)),
                animateDelayMs: 0,
              ),
              const SizedBox(height: 16),
              _MenuCard(
                icon: Icons.history_rounded,
                iconColor: AppColors.warning,
                iconBgColor: AppColors.warning.withAlpha(26),
                title: 'History Tracking',
                subtitle: 'View your past tracking sessions and routes',
                onTap: () => _goTo(
                  context,
                  HistoryPage(surveiId: survey.id, userId: null),
                ),

                animateDelayMs: 80,
              ),
              const SizedBox(height: 16),
              if (roleInSurvei?.replaceAll('[', '').replaceAll("]", '') ==
                  'pemeriksa') ...[
                const SizedBox(height: 16),
                _MenuCard(
                  icon: Icons.assignment_turned_in_rounded,
                  iconColor: AppColors.warning,
                  iconBgColor: AppColors.warning.withAlpha(26),
                  title: 'Absensi Petugas',
                  subtitle: 'Lihat absensi petugas',
                  onTap: () =>
                      _goTo(context, PetugasAbsensiPage(surveiId: survey.id)),

                  animateDelayMs: 240,
                ),
              ],
            ],
          ),
        ),
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
  final VoidCallback onTap;
  final int animateDelayMs;

  const _MenuCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.animateDelayMs,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
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

    return card
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
