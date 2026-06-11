import 'dart:async';
import 'package:logger/logger.dart';
import '../models/location_entity.dart';
import 'background_service_handler.dart';

/// Background service that continuously captures GPS positions,
class BackgroundLocationService {
  final Logger _logger = Logger();

  /// Distance filter in meters. Only save if user moved at least this far.
  final int distanceFilterMeters;

  /// How often to capture a GPS reading (seconds).
  final int locationIntervalSeconds;

  /// How often to flush the in-memory buffer to SQLite (seconds).
  final int flushIntervalSeconds;

  final int syncIntervalSeconds;

  BackgroundLocationService({
    this.distanceFilterMeters = 30,
    this.locationIntervalSeconds = 30,
    this.flushIntervalSeconds = 60,
    this.syncIntervalSeconds = 300,
  });

  Future<bool> get isRunning async =>
      await BackgroundServiceHandler.isRunning();
  List<LocationEntity> get buffer => []; // Managed by handler

  /// Start capturing locations.
  void start({int? surveiId}) {
    BackgroundServiceHandler.startTracking(
      distanceFilterMeters: distanceFilterMeters,
      surveiId: surveiId,
      syncIntervalSeconds: syncIntervalSeconds,
    );

    _logger.i(
      'BackgroundLocationService started '
      '(using background service, distanceFilter: ${distanceFilterMeters}m)',
    );
  }

  /// Stop capturing locations and flush any remaining buffered data.
  Future<void> stop() async {
    // Drain unsynced locations to server before stopping background isolate.
    await BackgroundServiceHandler.syncAllUnsyncedAndStop();
    await BackgroundServiceHandler.stopTracking();

    _logger.i('BackgroundLocationService stopped');
  }

  Future<void> flushNow() async {
    await BackgroundServiceHandler.flushNow();
  }
}
