import 'dart:async';
import 'package:logger/logger.dart';
import '../models/location_entity.dart';
import 'background_service_handler.dart';

/// Background service that continuously captures GPS positions,
/// applies a distance filter, buffers points in memory, and
/// periodically flushes them to SQLite in batches.
///
/// This dramatically reduces storage I/O compared to writing every
/// single position immediately to the database.
class BackgroundLocationService {
  final Logger _logger = Logger();

  /// Distance filter in meters. Only save if user moved at least this far.
  final double distanceFilterMeters;

  /// How often to capture a GPS reading (seconds).
  final int locationIntervalSeconds;

  /// How often to flush the in-memory buffer to SQLite (seconds).
  final int flushIntervalSeconds;

  BackgroundLocationService({
    this.distanceFilterMeters = 0.0,
    this.locationIntervalSeconds = 10,
    this.flushIntervalSeconds = 60,
  });

  Future<bool> get isRunning async =>
      await BackgroundServiceHandler.isRunning();
  List<LocationEntity> get buffer => []; // Managed by handler

  /// Start capturing locations.
  void start({int? surveiId}) {
    BackgroundServiceHandler.startTracking(
      distanceFilterMeters: distanceFilterMeters,
      surveiId: surveiId ?? 2,
    );

    _logger.i(
      'BackgroundLocationService started '
      '(using background service, distanceFilter: ${distanceFilterMeters}m)',
    );
  }

  /// Stop capturing locations and flush any remaining buffered data.
  Future<void> stop() async {
    await BackgroundServiceHandler.stopTracking();
    await BackgroundServiceHandler.flushNow();

    _logger.i('BackgroundLocationService stopped');
  }

  /// Immediate flush — useful when user stops tracking manually.
  Future<void> flushNow() async {
    await BackgroundServiceHandler.flushNow();
  }

  // _onPosition moved to handler for stream listener

  // Flush delegated to isolate; no local buffer needed
}
