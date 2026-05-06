import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'background_isolate.dart';

class BackgroundServiceHandler {
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();
    await service.configure(
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        foregroundServiceNotificationId: 888,
        initialNotificationTitle: 'ULOS Background Tracking',
        initialNotificationContent: 'Capturing your location for tracking...',
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<bool> isRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }

  static Future<void> startTracking({
    double distanceFilterMeters = 0.0,
    int? surveiId,
  }) async {
    final service = FlutterBackgroundService();
    await service.startService();

    // Pass config to isolate
    service.invoke('setConfig', {
      'surveiId': surveiId,
      'distanceFilterMeters': distanceFilterMeters,
    });

    print(
      'BackgroundServiceHandler: config sent - surveiId=$surveiId, filter=${distanceFilterMeters}m',
    );
  }

  static Future<void> stopTracking() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
  }

  static Future<void> flushNow() async {
    final service = FlutterBackgroundService();
    service.invoke('flushNow');
  }
}
