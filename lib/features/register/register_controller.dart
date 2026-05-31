import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/constants/api_constants.dart';
import '../../core/services/dio_client.dart';
import '../../core/utils/altcha_utils.dart';
import '../../core/utils/validation_utils.dart';
import '../login/login_page.dart';

class RegisterController {
  final DioClient _dioClient;

  RegisterController({DioClient? dioClient})
    : _dioClient = dioClient ?? DioClient();

  Future<void> fetchKabupaten(
    void Function(bool isLoading) setLoading,
    void Function(List<Map<String, String>> kabupaten) setStateKabupaten,
  ) async {
    setLoading(true);
    try {
      final response = await _dioClient.dio.get(ApiConstants.kabupaten);
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? [];
        final kabupatenList = data
            .map(
              (item) => {
                'kode_kab': item['kode_kab']?.toString() ?? '',
                'nama_kab': item['nama_kab']?.toString() ?? '',
              },
            )
            .where((k) => (k['kode_kab'] ?? '').isNotEmpty)
            .toList();

        setStateKabupaten(kabupatenList);
      }
    } catch (_) {
      // Keep silent; UI decides how to display errors.
      rethrow;
    } finally {
      setLoading(false);
    }
  }

  Future<String> _getAltchaToken() async {
    final challengeResponse = await _dioClient.dio.get(
      ApiConstants.altchaChallenge,
    );

    if (challengeResponse.statusCode != 200) {
      throw Exception('Failed to get ALTCHA challenge');
    }

    final challengeData =
        challengeResponse.data['data'] as Map<String, dynamic>;
    final challenge = AltchaChallenge.fromJson(challengeData);
    return AltchaUtils.solveChallenge(challenge);
  }

  Future<void> submitRegister({
    required BuildContext context,
    required String name,
    required String email,
    required String password,
    required String confirmPassword,
    required String noHp,
    required String kodeKab,
    required String roleName,
  }) async {
    final formValid =
        ValidationUtils.validateEmail(email) == null && password.isNotEmpty;
    if (!formValid) {
      throw Exception('Invalid input');
    }
    if (password != confirmPassword) {
      throw Exception('Passwords do not match');
    }

    // 1) Solve ALTCHA
    final altchaToken = await _getAltchaToken();

    // 2) Submit registration
    final response = await _dioClient.dio.post(
      ApiConstants.register,
      data: {
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        'no_hp': noHp.trim(),
        'kode_kab': kodeKab,
        'altcha': altchaToken,
        'role_name': roleName,
      },
    );

    if (response.statusCode != 201) {
      final data = response.data as Map<String, dynamic>?;
      final message = data?['message'] ?? 'Registration failed';
      throw Exception(message);
    }

    // 3) Navigate after success
    // (UI will show snackbar; controller keeps navigation minimal)
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  String mapErrorToMessage(Object e) {
    if (e is DioException && e.error is Exception) {
      // Preserve network/format exceptions that are already user-facing.
      return e.error.toString();
    }

    if (e is DioException && e.response != null) {
      final data = e.response?.data;
      if (data is Map<String, dynamic> && data['message'] != null) {
        return 'Registration failed: ${data['message']}';
      }
      return 'Registration failed: ${e.response?.statusMessage}';
    }

    return 'Registration failed: $e';
  }
}
