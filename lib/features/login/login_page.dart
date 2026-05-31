import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/api_constants.dart';
import '../../core/services/dio_client.dart';
import '../home/home_page.dart';
import '../home/survey_cache_service.dart';
import '../../core/services/survey_service.dart';

import '../../core/utils/validation_utils.dart';
import '../../core/services/wilayah_service.dart';
import '../register/register_page.dart';
import '../../core/utils/app_version_utils.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  String? _appVersionText;
  bool _isLoadingAppVersion = true;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final v = await AppVersionUtils.getAppVersionText();
    if (!mounted) return;
    setState(() {
      _appVersionText = v;
      _isLoadingAppVersion = false;
    });
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await DioClient().dio.post(
        ApiConstants.login,
        data: {
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data['data'] as Map<String, dynamic>?;
        final token = data?['token'] as String?;
        if (token != null && token.isNotEmpty) {
          await DioClient().setToken(token);
          // Save user name if available
          final userName = data?['name'] as String?;
          final email = data?['email'] as String?;
          if (userName != null && userName.isNotEmpty) {
            await DioClient().setUserName(userName);
          }
          debugPrint('email = $email');
          if (email != null && email.isNotEmpty) {
            await DioClient().setEmail(email);
          }
          // Fetch surveys once after login + cache them
          try {
            await SurveyCacheService.refreshCacheIfNeeded(
              surveyService: SurveyService(),
              force: true,
            );
          } catch (_) {
            // ignore cache refresh errors; Home will fallback to cache/auto refresh
          }

          // Fetch wilayah and target points once after login
          await WilayahService.init();
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomePage()),
          );
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Login failed: Token not found in response'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // Handle non-200 responses (e.g., 401, 400) from server
        if (!mounted) return;
        final data = response.data;
        String message = 'Login failed';
        if (data is Map<String, dynamic> && data['message'] != null) {
          message = data['message'].toString();
        } else if (response.statusMessage != null &&
            response.statusMessage!.isNotEmpty) {
          message = response.statusMessage!;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      String errorMessage = 'Login failed: ${e.toString()}';

      if (e is DioException) {
        if (e.type == DioExceptionType.connectionError) {
          errorMessage =
              "No internet connection or server unreachable (Failed host lookup).";
        } else if (e.error is CorsException) {
          errorMessage = e.error.toString();
        } else if (e.response != null) {
          final data = e.response!.data;
          if (data is Map<String, dynamic> && data['message'] != null) {
            errorMessage = 'Login failed: ${data['message']}';
          } else {
            errorMessage =
                'Login failed: ${e.response?.statusMessage ?? 'Unknown error'}';
          }
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;

    // Konfigurasi Responsif
    final logoSize = isMobile ? 100.0 : 140.0;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Center(
                child: Container(
                  width: logoSize,
                  height: logoSize,

                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF3E0),
                    shape: BoxShape.circle,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
              ),
              const SizedBox(height: 40),
              Text(
                    'Welcome to ULOS!',
                    style: Theme.of(context).textTheme.headlineMedium,
                  )
                  .animate()
                  .fadeIn(duration: 600.ms)
                  .slideX(begin: -0.2, end: 0, duration: 600.ms),
              const SizedBox(height: 8),
              Text(
                'Sign in to continue tracking your journey',
                style: Theme.of(context).textTheme.bodyMedium,
              ).animate().fadeIn(duration: 600.ms, delay: 100.ms),
              const SizedBox(height: 40),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(
                              Icons.email_outlined,
                              color: AppColors.primary,
                            ),
                          ),
                          validator: ValidationUtils.validateEmail,
                        )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 200.ms)
                        .slideY(
                          begin: 0.2,
                          end: 0,
                          duration: 600.ms,
                          delay: 200.ms,
                        ),
                    const SizedBox(height: 20),
                    TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(
                              Icons.lock_outline,
                              color: AppColors.primary,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: AppColors.textSecondary,
                              ),
                              onPressed: () {
                                setState(
                                  () => _obscurePassword = !_obscurePassword,
                                );
                              },
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your password';
                            }
                            if (value.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 300.ms)
                        .slideY(
                          begin: 0.2,
                          end: 0,
                          duration: 600.ms,
                          delay: 300.ms,
                        ),
                    const SizedBox(height: 32),
                    SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text('Sign In'),
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 400.ms)
                        .slideY(
                          begin: 0.2,
                          end: 0,
                          duration: 600.ms,
                          delay: 400.ms,
                        ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Don\'t have an account?',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RegisterPage(),
                              ),
                            );
                          },
                          child: const Text('Sign Up'),
                        ),
                      ],
                    ).animate().fadeIn(duration: 600.ms, delay: 500.ms),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Footer app version
              Center(
                child: _isLoadingAppVersion
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _appVersionText ?? 'v-',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
