import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'app.dart';
import 'core/database/database_helper.dart';
import 'core/services/dio_client.dart';
import 'core/services/env_service.dart';
import 'core/services/background_service_handler.dart';
import 'core/services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('[BOOT] ensureInitialized');

  // Initialize environment config
  debugPrint('[BOOT] starting EnvService.load()');
  await EnvService.load();

  debugPrint('[BOOT] EnvService.load() completed');

  // Initialize SQLite database (not supported on web)
  if (!kIsWeb) {
    debugPrint('[BOOT] starting DatabaseHelper.instance.database');
    await DatabaseHelper.instance.database;

    debugPrint('[BOOT] DatabaseHelper.instance.database completed');
  } else {
    debugPrint('[BOOT] running on web: skip SQLite init');
  }

  // cek background service

  final isRunning = await BackgroundServiceHandler.isRunning();
  if (!isRunning) {
    debugPrint('[BOOT] starting BackgroundServiceHandler.initializeService()');
    await BackgroundServiceHandler.initializeService();

    debugPrint('[BOOT] BackgroundServiceHandler.initializeService() completed');
  }
  // Safety net: make sure a stale background instance is not left running
  // after install/update.
  // debugPrint('[BOOT] BackgroundServiceHandler.ensureNotRunning()');
  // await BackgroundServiceHandler.ensureNotRunning();
  // debugPrint('[BOOT] BackgroundServiceHandler.ensureNotRunning() completed');

  // Initialize FCM

  debugPrint('[BOOT] starting FcmService.initialize()');
  await FcmService.initialize();
  // ignore: avoid_print
  debugPrint('[BOOT] FcmService.initialize() completed');

  // Initialize Dio HTTP client
  debugPrint('[BOOT] starting DioClient().init()');
  await DioClient().init();

  debugPrint('[BOOT] DioClient().init() completed');

  debugPrint('[ENV] Running in ${EnvService.environment} mode');
  debugPrint('[ENV] Base URL: ${EnvService.baseUrl}');

  HttpOverrides.global = MyHttpOverrides();
  runApp(const UlosApp());
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}
