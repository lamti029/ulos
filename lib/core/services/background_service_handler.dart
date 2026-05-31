import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'background_isolate.dart';

class BackgroundServiceHandler {
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();
    debugPrint('[BackgroundServiceHandler] initializeService() -> configuring');
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
    debugPrint(
      '[BackgroundServiceHandler] initializeService() -> configure done',
    );
  }

  @pragma('vm:entry-point')
  static Future<bool> isRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }

  /// Safety net: some devices may keep a background instance alive across
  /// app update/reinstall, causing "Stop Tracking" to show even though
  /// tracking should be off.
  static Future<void> ensureNotRunning({
    Duration waitAfterStop = const Duration(milliseconds: 300),
  }) async {
    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (!running) return;

    debugPrint(
      '[BackgroundServiceHandler] ensureNotRunning(): service is running -> forcing stop',
    );

    try {
      service.invoke('setConfig', {'enable': false});
    } catch (_) {
      // ignore
    }

    try {
      service.invoke('stopService');
    } catch (_) {
      // ignore
    }

    await Future.delayed(waitAfterStop);
  }

  static Future<void> startTracking({
    int distanceFilterMeters = 30,
    int? surveiId,
    int? syncIntervalSeconds,
  }) async {
    final service = FlutterBackgroundService();
    debugPrint(
      '[BackgroundServiceHandler] startTracking() called surveiId=$surveiId distanceFilterMeters=$distanceFilterMeters syncIntervalSeconds=$syncIntervalSeconds',
    );

    await service.startService();
    debugPrint('[BackgroundServiceHandler] startService() done');

    // Tiny delay to reduce race between isolate startup and the first setConfig().
    await Future.delayed(const Duration(milliseconds: 200));

    debugPrint(
      '[BackgroundServiceHandler] invoke setConfig(enable=true, surveiId=$surveiId, distanceFilterMeters=$distanceFilterMeters, syncIntervalSeconds=$syncIntervalSeconds)',
    );

    service.invoke('setConfig', {
      'enable': true,
      'surveiId': surveiId,
      // sessionId dibangkitkan per start tracking agar history polyline terpisah.
      'sessionId': DateTime.now().millisecondsSinceEpoch,
      'distanceFilterMeters': distanceFilterMeters,
      'syncIntervalSeconds': syncIntervalSeconds,
    });

    debugPrint(
      'BackgroundServiceHandler: config sent - surveiId=$surveiId, filter=${distanceFilterMeters}m',
    );
  }

  static Future<void> stopTracking() async {
    final service = FlutterBackgroundService();

    // Disable GPS stream in isolate first.
    service.invoke('setConfig', {'enable': false});

    // Stop background isolate will be handled inside isolate (after drain sync on stop).
    service.invoke('stopService');
  }

  /// Force background isolate to sync all pending locations before shutting down.
  /// Should be called right before stopTracking(), so isolate can drain DB->server.
  static Future<void> syncAllUnsyncedAndStop() async {
    final service = FlutterBackgroundService();
    service.invoke('syncAllUnsyncedAndStop');
  }

  static Future<void> flushNow() async {
    final service = FlutterBackgroundService();
    service.invoke('flushNow');
  }
}
