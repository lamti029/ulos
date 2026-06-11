import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../constants/api_constants.dart';

import 'dio_client.dart';
import 'location_repository.dart';

class LocationSyncService {
  final Logger _logger = Logger();
  final LocationRepository _repository = LocationRepository();
  final DioClient _dioClient = DioClient();

  final int batchLimit;

  LocationSyncService({this.batchLimit = 100});

  Future<void> syncNow() async {
    await _syncCycle();
  }

  Future<void> _syncCycle() async {
    try {
      final unsynced = await _repository.getUnsynced(limit: batchLimit);
      if (unsynced.isEmpty) {
        _logger.i('No unsynced locations to send');
        return;
      }

      _logger.i('Syncing ${unsynced.length} locations...');

      final battery = Battery();
      final batteryLevel = await battery.batteryLevel;

      final payload = unsynced.map((loc) {
        final apiPayload = loc.toApiPayload();
        apiPayload['battery_level'] = batteryLevel;
        return apiPayload;
      }).toList();

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

  Future<int> getPendingCount() async {
    return _repository.countUnsynced();
  }
}
