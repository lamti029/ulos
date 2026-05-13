import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:ulos/features/splash/wave_clipper.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/dio_client.dart';
import '../../core/utils/jwt_utils.dart';
import '../home/home_page.dart';
import '../login/login_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // Avoid async timers/navigation during widget tests.
    if (const bool.fromEnvironment('FLUTTER_TEST')) {
      return;
    }

    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    final token = await DioClient().getToken();
    if (!mounted) return;

    if (token == null || token.isEmpty) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
      return;
    }

    // Validate JWT expiry
    if (JwtUtils.isTokenExpired(token)) {
      await DioClient().clearToken();
      await DioClient().clearUserName();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session expired, please login again'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
      return;
    }

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;

    // Konfigurasi Responsif
    final gradientHeight = isMobile ? size.height * 0.35 : size.height * 0.4;
    final logoSize = isMobile ? 100.0 : 140.0;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          // 1. Background: Tracking Map (Opacity rendah)
          Positioned.fill(
            child: Opacity(
              opacity: 0.5,
              child: Image.asset(
                'assets/images/map_bg.png', // Pastikan file map ada di assets
                fit: BoxFit.cover,
              ),
            ),
          ),

          // 2. Bottom Wave Gradient
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: WaveClipper(),
              child: Container(
                height: gradientHeight,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.primary, // Orange
                      AppColors.secondary, // Brown
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 3. Main Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo Card
                Container(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Icon Pin/Logo
                      Container(
                        width: logoSize,
                        height: logoSize,

                        decoration: const BoxDecoration(
                          color: Color(0xFFFFF3E0),
                          shape: BoxShape.circle,
                        ),
                        //  borderRadius: BorderRadius.circular(24),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                        // ƒchild: Image.asset('assets/images/logo.png'),
                      ).animate().scale(
                        duration: 800.ms,
                        curve: Curves.easeOutBack,
                      ),

                      const SizedBox(height: 24),

                      // Title
                      Text(
                            'Ulos',
                            style: TextStyle(
                              fontSize: isMobile ? 40 : 52,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              letterSpacing: 2,
                            ),
                          )
                          .animate()
                          .fadeIn(delay: 400.ms)
                          .slideY(begin: 0.2, end: 0),

                      // Subtitle
                      Text(
                        'User Location & Operational System',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isMobile ? 14 : 16,
                          color: Colors.grey[600],
                        ),
                      ).animate().fadeIn(delay: 600.ms),

                      const SizedBox(height: 40),

                      // Loading Spinner
                      const SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 4. Footer Copyright
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Text(
              '© 2026 BPS Sumut. All rights reserved.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
