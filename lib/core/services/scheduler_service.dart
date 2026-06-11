import 'dart:async';
import 'package:logger/logger.dart';
import 'package:ulos/core/services/background_service_handler.dart';
import 'background_location_service.dart';
import 'env_service.dart';
import 'location_sync_service.dart';
import '../models/location_entity.dart';
import 'location_repository.dart';

class SchedulerService {
  final Logger _logger = Logger();

  final BackgroundLocationService _bgService;
  final LocationSyncService _syncService;

  bool _isRunning = false;

  static SchedulerService? _instance;

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
           LocationSyncService(batchLimit: EnvService.batchLimit);

  static SchedulerService get instance => SchedulerService();

  static Future<bool> get isRunning async {
    return await BackgroundServiceHandler.isRunning();
  }

  Future<void> start({
    required int locationIntervalSeconds,
    required int batchIntervalSeconds,
    int? surveiId,
  }) async {
    final bgRunning = await BackgroundServiceHandler.isRunning();
    if (_isRunning && bgRunning) {
      _logger.d('SchedulerService already running, ignoring start');

      return;
    }
    _isRunning = true;

    _logger.i('SchedulerService started');

    _bgService.start(surveiId: surveiId);
  }

  Future<void> stop() async {
    final bgRunning = await BackgroundServiceHandler.isRunning();
    if (!_isRunning && !bgRunning) {
      _logger.i('SchedulerService not running, ignoring stop');
      return;
    }
    _isRunning = false;

    await _bgService.stop();

    const int maxWaitMs = 3000;
    const int stepMs = 100;
    var waited = 0;
    while (waited < maxWaitMs) {
      final running = await BackgroundServiceHandler.isRunning();
      if (!running) break;
      await Future.delayed(Duration(milliseconds: stepMs));
      waited += stepMs;
    }
    await _syncService.syncNow();

    _logger.i('SchedulerService stopped');
  }

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

      final resolvedSurveiId = (m['survei_id'] ?? m['surveiId'] ?? surveiId);

      final resolvedSessionId = (m['session_id'] ?? m['sessionId']);

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
        sessionId: resolvedSessionId is int
            ? resolvedSessionId
            : (resolvedSessionId == null
                  ? null
                  : (resolvedSessionId as num).toInt()),
        isSynced: false,
      );
    }).toList();

    await repo.insertBatch(entities);

    await _syncService.syncNow();
  }

  Future<int> getPendingSyncCount() async {
    return _syncService.getPendingCount();
  }
}
