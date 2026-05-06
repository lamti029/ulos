import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'app.dart';
import 'core/database/database_helper.dart';
import 'core/services/dio_client.dart';
import 'core/services/env_service.dart';
import 'core/services/background_service_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize environment config
  await EnvService.load();

  // Initialize SQLite database (not supported on web)
  if (!kIsWeb) {
    await DatabaseHelper.instance.database;
  }

  // Initialize background service
  await BackgroundServiceHandler.initializeService();

  // Initialize Dio HTTP client
  await DioClient().init();

  // ignore: avoid_print
  print('[ENV] Running in ${EnvService.environment} mode');
  // ignore: avoid_print
  print('[ENV] Base URL: ${EnvService.baseUrl}');

  runApp(const UlosApp());
}
