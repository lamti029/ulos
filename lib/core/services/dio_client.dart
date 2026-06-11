import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../constants/app_constants.dart';

class CorsException implements Exception {
  final String message;
  CorsException(this.message);

  @override
  String toString() => message;
}

class DioClient {
  static final DioClient _instance = DioClient._internal();
  factory DioClient() => _instance;
  DioClient._internal();

  late Dio _dio;

  Dio get dio => _dio;

  Future<void> init() async {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,

        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        validateStatus: (status) => true,
      ),
    );
    final bool allowBadCertificates = const bool.fromEnvironment(
      'ALLOW_BAD_CERTS',
      defaultValue: false,
    );

    assert(() {
      debugPrint('[DioClient] ALLOW_BAD_CERTS=$allowBadCertificates');
      return true;
    }());

    if (allowBadCertificates) {
      debugPrint(
        '[DioClient] ALLOW_BAD_CERTS=true but certificate override is disabled in this build.',
      );
    }

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString(AppConstants.tokenKey);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (DioException e, handler) {
          // Detect network layer failures (CORS on web, broken pipe, refused connection, etc.)
          if ((e.type == DioExceptionType.connectionError ||
                  e.type == DioExceptionType.unknown) &&
              e.response == null) {
            final uri = e.requestOptions.uri.toString();
            final errorStr = e.error?.toString() ?? '';

            // Broken pipe / connection reset → server closed connection unexpectedly
            if (errorStr.contains('Broken pipe') ||
                errorStr.contains('Connection reset') ||
                errorStr.contains('Connection refused')) {
              final msg =
                  'Server at $uri is unreachable or closed the connection unexpectedly. '
                  'Please make sure the backend server is running and accessible.';
              handler.reject(
                DioException(
                  requestOptions: e.requestOptions,
                  error: CorsException(msg),
                  type: DioExceptionType.connectionError,
                ),
              );
              return;
            }

            if (kIsWeb) {
              final corsMsg =
                  'Cannot connect to $uri. Please check your internet connection';
              handler.reject(
                DioException(
                  requestOptions: e.requestOptions,
                  error: CorsException(corsMsg),
                  type: DioExceptionType.connectionError,
                ),
              );
              return;
            }
          }

          if (e.response?.statusCode == 401) {
            clearSessionIfNeeded();
            handler.reject(
              DioException(
                requestOptions: e.requestOptions,
                error: CorsException('Session expired, please login again'),
                type: DioExceptionType.unknown,
              ),
            );
            return;
          }

          handler.next(e);
        },
      ),
    );

    _dio.interceptors.add(
      LogInterceptor(requestBody: true, responseBody: true),
    );
  }

  static bool _isClearingSession = false;
  static void clearSessionIfNeeded() {
    if (_isClearingSession) return;
    _isClearingSession = true;
    DioClient()
        .clearToken()
        .then((_) => DioClient().clearUserName())
        .then((_) => DioClient().clearEmail())
        .whenComplete(() => _isClearingSession = false);
  }

  Future<void> setToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.tokenKey, token);
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.tokenKey);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.tokenKey);
  }

  Future<void> setUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.userNameKey, name);
  }

  Future<void> clearUserName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.userNameKey);
  }

  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.userNameKey);
  }

  Future<void> setEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.email, email);
  }

  Future<String?> getEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.email);
  }

  Future<void> clearEmail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.email);
  }
}
