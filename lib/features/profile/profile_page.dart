import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/dio_client.dart';
import '../../core/utils/jwt_utils.dart';
import '../login/login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _userName;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    // Try from shared preferences first
    var name = await DioClient().getUserName();
    // Fallback to JWT if not in prefs
    if (name == null || name.isEmpty) {
      name = await JwtUtils.getUserName();
      if (name != null && name.isNotEmpty) {
        await DioClient().setUserName(name);
      }
    }
    if (mounted) {
      setState(() {
        _userName = name ?? 'Pengguna';
        _isLoading = false;
      });
    }
  }

  Future<void> _logout(BuildContext context) async {
    await DioClient().clearToken();
    await DioClient().clearUserName();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  void _showLogoutConfirm(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: AppColors.error, size: 28),
            SizedBox(width: 10),
            Text('Konfirmasi Logout'),
          ],
        ),
        content: const Text('Apakah Anda yakin ingin keluar dari akun ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _logout(context);
            },
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Logout'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
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
        title: const Text('Profile'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // Avatar
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withAlpha(77),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _userName != null && _userName!.isNotEmpty
                              ? _userName![0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
              const SizedBox(height: 20),
              // Name
              if (_isLoading)
                Container(
                  width: 160,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(8),
                  ),
                )
              else
                Text(
                  _userName ?? 'Pengguna',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.2, end: 0),
              const SizedBox(height: 8),
              Text(
                'Petugas ${AppConstants.appName}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 100.ms),
              const SizedBox(height: 40),
              // Info cards
              _InfoCard(
                    icon: Icons.person_outline_rounded,
                    title: 'Nama Lengkap',
                    value: _userName ?? '-',
                    iconColor: AppColors.primary,
                    iconBgColor: AppColors.primary.withAlpha(26),
                  )
                  .animate()
                  .fadeIn(duration: 600.ms, delay: 200.ms)
                  .slideX(begin: -0.2, end: 0, duration: 600.ms, delay: 200.ms),
              const SizedBox(height: 12),
              _InfoCard(
                    icon: Icons.badge_outlined,
                    title: 'Role',
                    value: 'Petugas Lapangan',
                    iconColor: AppColors.success,
                    iconBgColor: AppColors.success.withAlpha(26),
                  )
                  .animate()
                  .fadeIn(duration: 600.ms, delay: 300.ms)
                  .slideX(begin: -0.2, end: 0, duration: 600.ms, delay: 300.ms),
              const SizedBox(height: 12),
              _InfoCard(
                    icon: Icons.app_shortcut_outlined,
                    title: 'Aplikasi',
                    value: AppConstants.appName,
                    iconColor: AppColors.warning,
                    iconBgColor: AppColors.warning.withAlpha(26),
                  )
                  .animate()
                  .fadeIn(duration: 600.ms, delay: 400.ms)
                  .slideX(begin: -0.2, end: 0, duration: 600.ms, delay: 400.ms),
              const SizedBox(height: 40),
              // Logout button
              SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: () => _showLogoutConfirm(context),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Logout'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  )
                  .animate()
                  .fadeIn(duration: 600.ms, delay: 500.ms)
                  .slideY(begin: 0.2, end: 0, duration: 600.ms, delay: 500.ms),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String value;

  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shadowColor: AppColors.cardShadow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
