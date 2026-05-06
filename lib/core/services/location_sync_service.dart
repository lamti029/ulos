import 'dart:async';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../constants/api_constants.dart';

import 'dio_client.dart';
import 'location_repository.dart';

/// Service responsible for synchronizing locally-stored (unsynced)
/// locations to the remote server in batches.
///
/// Workflow:
/// 1. Query SQLite for locations where is_synced = 0 (up to batchLimit).
/// 2. POST to API /locations/batch.
/// 3. On success, mark those rows as is_synced = 1.
/// 4. On failure, leave them unsynced for retry next cycle.
class LocationSyncService {
  final Logger _logger = Logger();
  final LocationRepository _repository = LocationRepository();
  final DioClient _dioClient = DioClient();

  Timer? _syncTimer;
  bool _isRunning = false;

  /// How often to attempt a sync cycle (seconds).
  final int syncIntervalSeconds;

  /// Maximum number of locations to send in a single batch.
  final int batchLimit;

  LocationSyncService({this.syncIntervalSeconds = 60, this.batchLimit = 100});

  bool get isRunning => _isRunning;

  /// Start automatic periodic sync.
  void start() {
    if (_isRunning) return;
    _isRunning = true;

    _logger.i(
      'LocationSyncService started (interval: ${syncIntervalSeconds}s, batchLimit: $batchLimit)',
    );

    // Immediate first attempt.
    _syncCycle();

    _syncTimer = Timer.periodic(
      Duration(seconds: syncIntervalSeconds),
      (_) => _syncCycle(),
    );
  }

  /// Stop automatic sync.
  void stop() {
    _isRunning = false;
    _syncTimer?.cancel();
    _syncTimer = null;
    _logger.i('LocationSyncService stopped');
  }

  /// Force an immediate sync cycle (e.g. when user stops tracking).
  Future<void> syncNow() async {
    await _syncCycle();
  }

  /// Core sync cycle.
  Future<void> _syncCycle() async {
    try {
      final unsynced = await _repository.getUnsynced(limit: batchLimit);
      if (unsynced.isEmpty) {
        _logger.i('No unsynced locations to send');
        return;
      }

      _logger.i('Syncing ${unsynced.length} locations...');

      final payload = unsynced.map((loc) => loc.toApiPayload()).toList();

      final response = await _dioClient.dio.post(
        ApiConstants.locationBatch,
        data: {'locations': payload},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final ids = unsynced.map((l) => l.id!).toList();
        final marked = await _repository.markAsSynced(ids);
        _logger.i('Sync successful: $marked locations marked as synced');
      } else {
        _logger.w(
          'Sync failed: HTTP ${response.statusCode} — will retry later',
        );
      }
    } on DioException catch (e) {
      _logger.e('Sync network error: ${e.message} — will retry later');
    } catch (e) {
      _logger.e('Sync unexpected error: $e — will retry later');
    }
  }

  /// Count how many locations are currently pending sync.
  Future<int> getPendingCount() async {
    return _repository.countUnsynced();
  }
}
