import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../constants/app_constants.dart';

/// Exception thrown when a CORS error is detected on the web platform.
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
        // Do not throw on 4xx/5xx so we can inspect the real response.
        validateStatus: (status) => true,
      ),
    );

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

            // CORS / general network failures on web
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
            final corsMsg =
                'Invalid credentials. Please check your email and password and try again.\n';
            handler.reject(
              DioException(
                requestOptions: e.requestOptions,
                error: CorsException(corsMsg),
                type: DioExceptionType.connectionError,
              ),
            );
            // Handle unauthorized
          }
          handler.next(e);
        },
      ),
    );

    _dio.interceptors.add(
      LogInterceptor(requestBody: true, responseBody: true),
    );
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

  // /// Build an Accept-Language header matching the device locale,
  // /// e.g. "en-US,en;q=0.9,id-ID;q=0.8,id;q=0.7".
  // String _acceptLanguage() {
  //   String locale;
  //   try {
  //     locale = Platform.localeName;
  //   } catch (_) {
  //     locale = 'en-US';
  //   }
  //   final lang = locale.replaceAll('_', '-');
  //   final short = lang.split('-').first;
  //   return '$lang,$short;q=0.9';
  // }
}
