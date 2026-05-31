import 'package:logger/logger.dart';

import 'location_repository.dart';

class BackgroundSyncDrain {
  final Logger logger;

  BackgroundSyncDrain({required this.logger});

  Future<void> drainUnsyncedUntilEmpty({
    required LocationRepository repository,
    required Future<void> Function({required int batchLimit}) runSyncCycle,
    int drainBatchLimit = 100,
    int maxRounds = 50,
  }) async {
    var rounds = 0;

    while (true) {
      if (rounds >= maxRounds) {
        logger.w('sync drain stopped by maxRounds=$maxRounds');
        break;
      }
      rounds++;

      final pending = await repository.countUnsynced();
      logger.i('sync drain round=$rounds pending=$pending');
      if (pending <= 0) break;

      await runSyncCycle(batchLimit: drainBatchLimit);

      await Future.delayed(const Duration(milliseconds: 200));
    }
  }
}
