import 'package:battery_plus/battery_plus.dart';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../constants/api_constants.dart';
import 'dio_client.dart';
import 'location_repository.dart';

/// Runs a single sync cycle inside background isolate.
Future<void> runLocationSyncCycle({required int batchLimit}) async {
  final logger = Logger();

  final repo = LocationRepository();
  await repo.initialize();

  final dioClient = DioClient();
  await dioClient.init();

  try {
    final unsynced = await repo.getUnsynced(limit: batchLimit);
    if (unsynced.isEmpty) {
      logger.i('Background sync: no unsynced locations');
      return;
    }

    final battery = Battery();
    final batteryLevel = await battery.batteryLevel;

    final payload = unsynced.map((loc) {
      final apiPayload = loc.toApiPayload();
      apiPayload['battery_level'] = batteryLevel;
      return apiPayload;
    }).toList();

    final response = await dioClient.dio.post(
      ApiConstants.locationBatch,
      data: {'locations': payload},
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final ids = unsynced.map((l) => l.id!).toList();
      final marked = await repo.markAsSynced(ids);
      logger.i('Background sync successful: $marked marked as synced');
    } else {
      logger.w('Background sync failed: HTTP ${response.statusCode}');
    }
  } on DioException catch (e) {
    logger.e('Background sync network error: ${e.message}');
  } catch (e) {
    logger.e('Background sync unexpected error: $e');
  }
}
