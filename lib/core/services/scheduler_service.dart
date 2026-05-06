import 'dart:async';
import 'package:logger/logger.dart';
import 'package:ulos/core/services/background_service_handler.dart';
import 'background_location_service.dart';
import 'env_service.dart';
import 'location_sync_service.dart';
import '../models/location_entity.dart';
import 'location_repository.dart';

/// Orchestrates background location capture and server synchronization.
///
/// Replaces the old SharedPreferences-based approach with:
/// - BackgroundLocationService: captures GPS, distance filter, batch insert to SQLite
/// - LocationSyncService: periodic sync of unsynced rows to the server
class SchedulerService {
  final Logger _logger = Logger();

  final BackgroundLocationService _bgService;
  final LocationSyncService _syncService;

  bool _isRunning = false;

  static SchedulerService? _instance;

  /// Singleton factory constructor
  factory SchedulerService({
    BackgroundLocationService? bgService,
    LocationSyncService? syncService,
  }) {
    _instance ??= SchedulerService._internal(
      bgService: bgService,
      syncService: syncService,
    );
    return _instance!;
  }

  /// Private constructor for singleton
  SchedulerService._internal({
    BackgroundLocationService? bgService,
    LocationSyncService? syncService,
  }) : _bgService =
           bgService ??
           BackgroundLocationService(
             distanceFilterMeters: EnvService.distanceFilterMeters,
             locationIntervalSeconds: EnvService.locationIntervalSeconds,
             flushIntervalSeconds: EnvService.flushIntervalSeconds,
           ),
       _syncService =
           syncService ??
           LocationSyncService(
             syncIntervalSeconds: EnvService.syncIntervalSeconds,
             batchLimit: EnvService.batchLimit,
           );

  /// Get singleton instance directly
  static SchedulerService get instance => SchedulerService();

  static Future<bool> get isRunning async {
    if (_instance == null) return false;
    final bgRunning = await BackgroundServiceHandler.isRunning();
    return _instance!._isRunning && bgRunning;
  }

  /// Start both background capture and periodic sync.
  Future<void> start({
    required int locationIntervalSeconds,
    required int batchIntervalSeconds,
    int? surveiId,
  }) async {
    if (_isRunning) {
      _logger.i('SchedulerService already running, ignoring start');
      return;
    }
    _isRunning = true;

    _logger.i('SchedulerService started');

    _bgService.start(surveiId: surveiId);
    _syncService.start();
  }

  /// Stop both services and perform a final flush + sync.
  Future<void> stop() async {
    if (!_isRunning) {
      _logger.i('SchedulerService not running, ignoring stop');
      return;
    }
    _isRunning = false;

    // Flush any remaining buffered locations to SQLite.
    await _bgService.stop();

    // One final sync attempt.
    await _syncService.syncNow();
    _syncService.stop();

    _logger.i('SchedulerService stopped');
  }

  /// Send an immediate batch (e.g. first location on tracking start).
  /// This persists the provided locations to SQLite and triggers a sync.
  Future<void> sendImmediateBatch({
    required List<Map<String, dynamic>> locations,
    int? surveiId,
  }) async {
    _logger.i('Immediate batch: ${locations.length} location(s)');

    if (locations.isEmpty) return;

    final repo = LocationRepository();

    final entities = locations.map((m) {
      final tsRaw = m['timestamp'];
      final timestamp = tsRaw is DateTime
          ? tsRaw
          : (tsRaw is String ? DateTime.parse(tsRaw) : DateTime.now());

      // UI may not always provide survei_id (e.g. no selected target yet).
      final resolvedSurveiId = (m['survei_id'] ?? m['surveiId'] ?? surveiId);

      final isMockedRaw = m['is_mocked'] ?? m['isMocked'] ?? false;

      return LocationEntity(
        lat: (m['latitude'] as num).toDouble(),
        lng: (m['longitude'] as num).toDouble(),
        timestamp: timestamp,
        accuracy: m['accuracy'] != null
            ? (m['accuracy'] as num).toDouble()
            : null,
        altitude: m['altitude'] != null
            ? (m['altitude'] as num).toDouble()
            : null,
        speed: m['speed'] != null ? (m['speed'] as num).toDouble() : null,
        isMocked: isMockedRaw == true || isMockedRaw == 1,
        surveiId: resolvedSurveiId is int
            ? resolvedSurveiId
            : (resolvedSurveiId == null
                  ? null
                  : (resolvedSurveiId as num).toInt()),
        isSynced: false,
      );
    }).toList();

    await repo.insertBatch(entities);

    // Force sync immediately (will pick up is_synced=0 rows).
    await _syncService.syncNow();
  }

  /// Get count of locations pending sync (for UI display).
  Future<int> getPendingSyncCount() async {
    return _syncService.getPendingCount();
  }
}
