import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/api_constants.dart';
import '../../core/services/dio_client.dart';
import '../../core/utils/altcha_utils.dart';
import '../../core/utils/validation_utils.dart';
import '../login/login_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _noHpController = TextEditingController();
  final _kabupatenController = TextEditingController();

  bool _isLoading = false;

  bool _isAltchaSolving = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  double _altchaProgress = 0.0;

  List<Map<String, String>> _kabupatenList = [];
  String? _selectedKodeKab;
  bool _isLoadingKabupaten = false;

  @override
  void initState() {
    super.initState();
    _fetchKabupaten();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _noHpController.dispose();
    _kabupatenController.dispose();
    super.dispose();
  }

  Future<void> _fetchKabupaten() async {
    setState(() => _isLoadingKabupaten = true);
    try {
      final response = await DioClient().dio.get(ApiConstants.kabupaten);
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? [];
        setState(() {
          _kabupatenList = data
              .map(
                (item) => {
                  'kode_kab': item['kode_kab']?.toString() ?? '',
                  'nama_kab': item['nama_kab']?.toString() ?? '',
                },
              )
              .where((k) => k['kode_kab']!.isNotEmpty)
              .toList();
        });
      }
    } catch (e) {
      debugPrint('[_fetchKabupaten] error: $e');
    } finally {
      setState(() => _isLoadingKabupaten = false);
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // 1. Fetch ALTCHA challenge
      setState(() => _isAltchaSolving = true);

      final challengeResponse = await DioClient().dio.get(
        ApiConstants.altchaChallenge,
      );

      if (challengeResponse.statusCode != 200) {
        throw Exception('Failed to get ALTCHA challenge');
      }

      final challengeData =
          challengeResponse.data['data'] as Map<String, dynamic>;

      // Debug: see exact challenge payload shape
      debugPrint(
        '[RegisterPage] altcha challengeData keys=${challengeData.keys.toList()}',
      );

      final challenge = AltchaChallenge.fromJson(challengeData);

      // 2. Solve ALTCHA challenge
      final altchaToken = await AltchaUtils.solveChallenge(challenge);
      debugPrint('ok');
      setState(() {
        _isAltchaSolving = false;
        _altchaProgress = 1.0;
      });

      // 3. Submit registration
      debugPrint(
        '[RegisterPage] submitting register payload altcha_key=altcha altcha_token_prefix=${altchaToken.substring(0, altchaToken.length >= 12 ? 12 : altchaToken.length)}...',
      );

      final response = await DioClient().dio.post(
        ApiConstants.register,
        data: {
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
          'no_hp': _noHpController.text.trim(),
          'kode_kab': _selectedKodeKab ?? '',
          'altcha': altchaToken,
          'role_name': 'petugas',
        },
      );

      if (response.statusCode == 201) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration successful! Please sign in.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
      } else {
        final data = response.data as Map<String, dynamic>?;
        final message = data?['message'] ?? 'Registration failed';
        throw Exception(message);
      }
    } catch (e) {
      if (!mounted) return;

      String errorMessage;
      if (e is DioException && e.error is CorsException) {
        errorMessage = e.error.toString();
      } else if (e is DioException && e.response != null) {
        final data = e.response?.data;
        if (data is Map<String, dynamic> && data['message'] != null) {
          errorMessage = 'Registration failed: ${data['message']}';
        } else {
          errorMessage = 'Registration failed: ${e.response?.statusMessage}';
        }
      } else {
        errorMessage = 'Registration failed: ${e.toString()}';
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
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isAltchaSolving = false;
        });
      }
    }
  }

  Widget _buildKabupatenAutocomplete() {
    return Autocomplete<Map<String, String>>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return _kabupatenList;
        }
        final query = textEditingValue.text.toLowerCase();
        return _kabupatenList.where((k) {
          final kode = k['kode_kab']!.toLowerCase();
          final nama = k['nama_kab']!.toLowerCase();
          return kode.contains(query) || nama.contains(query);
        });
      },
      displayStringForOption: (option) {
        return '${option['kode_kab']} - ${option['nama_kab']}';
      },
      onSelected: (option) {
        setState(() {
          _selectedKodeKab = option['kode_kab'];
          _kabupatenController.text =
              '${option['kode_kab']} - ${option['nama_kab']}';
        });
      },
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
            // Sync with our controller
            if (textEditingController.text != _kabupatenController.text) {
              textEditingController.text = _kabupatenController.text;
            }
            return TextFormField(
              controller: textEditingController,
              focusNode: focusNode,
              onFieldSubmitted: (_) => onFieldSubmitted(),
              decoration: InputDecoration(
                labelText: 'Kabupaten',
                prefixIcon: Icon(
                  Icons.location_city_outlined,
                  color: AppColors.primary,
                ),
                suffixIcon: _isLoadingKabupaten
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              validator: (value) {
                if (_selectedKodeKab == null || _selectedKodeKab!.isEmpty) {
                  return 'Silakan pilih kabupaten';
                }
                return null;
              },
            );
          },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    title: Text(
                      '${option['kode_kab']} - ${option['nama_kab']}',
                    ),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                    'Create Account',
                    style: Theme.of(context).textTheme.headlineMedium,
                  )
                  .animate()
                  .fadeIn(duration: 600.ms)
                  .slideX(begin: -0.2, end: 0, duration: 600.ms),
              const SizedBox(height: 8),
              Text(
                'Sign up to start tracking your journey',
                style: Theme.of(context).textTheme.bodyMedium,
              ).animate().fadeIn(duration: 600.ms, delay: 100.ms),
              const SizedBox(height: 32),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildTextField(
                          controller: _nameController,
                          label: 'Full Name',
                          icon: Icons.person_outline,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your full name';
                            }
                            return null;
                          },
                        )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 150.ms)
                        .slideY(begin: 0.2, end: 0),
                    const SizedBox(height: 16),
                    _buildTextField(
                          controller: _emailController,
                          label: 'Email',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: ValidationUtils.validateEmail,
                        )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 200.ms)
                        .slideY(begin: 0.2, end: 0),
                    const SizedBox(height: 16),
                    _buildTextField(
                          controller: _passwordController,
                          label: 'Password',
                          icon: Icons.lock_outline,
                          obscureText: _obscurePassword,
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
                        .fadeIn(duration: 600.ms, delay: 250.ms)
                        .slideY(begin: 0.2, end: 0),
                    const SizedBox(height: 16),
                    _buildTextField(
                          controller: _confirmPasswordController,
                          label: 'Confirm Password',
                          icon: Icons.lock_outline,
                          obscureText: _obscureConfirmPassword,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: AppColors.textSecondary,
                            ),
                            onPressed: () {
                              setState(
                                () => _obscureConfirmPassword =
                                    !_obscureConfirmPassword,
                              );
                            },
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please confirm your password';
                            }
                            if (value != _passwordController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 300.ms)
                        .slideY(begin: 0.2, end: 0),
                    const SizedBox(height: 16),
                    _buildTextField(
                          controller: _noHpController,
                          label: 'Phone Number',
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                        )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 350.ms)
                        .slideY(begin: 0.2, end: 0),
                    const SizedBox(height: 16),
                    _buildKabupatenAutocomplete()
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 400.ms)
                        .slideY(begin: 0.2, end: 0),
                    const SizedBox(height: 32),
                    if (_isAltchaSolving) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(26),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      AppColors.primary,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Verifying captcha...',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            LinearProgressIndicator(
                              value: _altchaProgress,
                              backgroundColor: AppColors.primary.withAlpha(51),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.primary,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _register,
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
                                : const Text('Sign Up'),
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 500.ms)
                        .slideY(begin: 0.2, end: 0),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Already have an account?',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const LoginPage(),
                              ),
                            );
                          },
                          child: const Text('Sign In'),
                        ),
                      ],
                    ).animate().fadeIn(duration: 600.ms, delay: 550.ms),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary),
        suffixIcon: suffixIcon,
      ),
      validator: validator,
    );
  }
}
