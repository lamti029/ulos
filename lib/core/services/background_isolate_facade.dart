import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/location_entity.dart';
import 'background_gps_state.dart';
import 'background_location_buffer.dart';
import 'background_tracking_config.dart';
import 'background_sync.dart';
import '../constants/background_tracking_constants.dart' as constants;
import 'env_service.dart';
import 'location_repository.dart';
import 'background_sync_drain.dart';

class BackgroundIsolateFacade {
  final Logger logger;

  StreamSubscription<Position>? positionSubscription;

  final BackgroundGpsState gpsState;
  final BackgroundLocationBuffer buffer;

  LocationRepository? repository;

  int? surveiId;
  int? sessionId;

  Timer? flushTimer;
  Timer? syncTimer;
  bool shouldStart = false;

  bool trackingEnabled = false;

  BackgroundIsolateFacade({required this.logger})
    : gpsState = BackgroundGpsState(distanceFilterMeters: 30.0),
      buffer = BackgroundLocationBuffer(
        logger: Logger(),
        flushMinBufferSize:
            constants.BackgroundTrackingConstants.flushMinBufferSize,
        flushMaxAgeSeconds:
            constants.BackgroundTrackingConstants.flushMaxAgeSeconds,
      );

  Future<bool> start(ServiceInstance service) async {
    repository = LocationRepository();
    await repository!.initialize();

    await EnvService.load();

    gpsState.distanceFilterMeters = EnvService.distanceFilterMeters.toDouble();

    // Setup mode
    if (service is AndroidServiceInstance) {
      final prefs = await SharedPreferences.getInstance();
      final shouldBeForeground = prefs.getBool('is_tracking') ?? false;

      if (shouldBeForeground) {
        service.setAsForegroundService();
        service
            .on('setAsForeground')
            .listen((_) => service.setAsForegroundService());
        service
            .on('setAsBackground')
            .listen((_) => service.setAsBackgroundService());

        service.setForegroundNotificationInfo(
          title: 'ULOS Tracking',
          content: 'The background tracking is active',
        );
      } else {
        service
            .on('setAsBackground')
            .listen((_) => service.setAsBackgroundService());
      }
    }

    // Event listeners
    service.on('setConfig').listen((event) async {
      final config = BackgroundTrackingConfig.fromEventPayload(event);
      await applyConfig(service, config);
    });

    service.on('stopService').listen((_) async {
      await positionSubscription?.cancel();
      await flushBufferToDb();
      service.stopSelf();
    });

    service.on('flushNow').listen((_) async {
      await flushBufferToDb();
      service.invoke('flushComplete');
    });

    service.on('syncAllUnsyncedAndStop').listen((_) async {
      logger.i('Received syncAllUnsyncedAndStop');
      await positionSubscription?.cancel();
      await flushBufferToDb();

      final drain = BackgroundSyncDrain(logger: logger);
      await drain.drainUnsyncedUntilEmpty(
        repository: repository!,
        runSyncCycle: ({required int batchLimit}) =>
            runLocationSyncCycle(batchLimit: batchLimit),
        drainBatchLimit: 100,
        maxRounds: 50,
      );

      service.stopSelf();
    });

    logger.d('Background service started (waiting for enable=true)');
    return true;
  }

  Future<bool> applyConfig(
    ServiceInstance service,
    BackgroundTrackingConfig config,
  ) async {
    if (config.surveiId != null) surveiId = config.surveiId;
    if (config.sessionId != null) sessionId = config.sessionId;
    if (config.distanceFilterMeters != null) {
      gpsState.distanceFilterMeters = config.distanceFilterMeters!.toDouble();
    }
    if (config.syncIntervalSeconds != null) {
      EnvService.syncIntervalSeconds = config.syncIntervalSeconds!;
    }

    trackingEnabled = config.enable;

    if (!config.enable) {
      shouldStart = false;
      flushTimer?.cancel();
      syncTimer?.cancel();
      flushTimer = null;
      syncTimer = null;
      await positionSubscription?.cancel();

      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'ULOS Tracking',
          content: 'Tracking berhenti',
        );
      }
      return false;
    }

    if (!shouldStart) {
      shouldStart = true;

      final flushSeconds = EnvService.flushIntervalSeconds;
      flushTimer?.cancel();
      if (flushSeconds > 0) {
        flushTimer = Timer.periodic(Duration(seconds: flushSeconds), (_) {
          flushBufferToDb().catchError((e) => logger.e('Auto-flush error: $e'));
        });
      }

      await startPositionStream(service);

      // Sync timer (battery saver)
      if (service is AndroidServiceInstance) {
        final prefs = await SharedPreferences.getInstance();
        final syncActive = prefs.getBool('is_tracking') ?? false;

        syncTimer?.cancel();
        if (syncActive) {
          final syncSeconds = EnvService.syncIntervalSeconds;
          syncTimer = Timer.periodic(Duration(seconds: syncSeconds), (_) async {
            try {
              final pending = await repository!.countUnsynced();
              if (pending > 0) {
                await runLocationSyncCycle(batchLimit: EnvService.batchLimit);
                // kept for compatibility; original isolate had this
              }
            } catch (e) {
              logger.e('Auto-sync check error: $e');
            }
          });
        }

        service.setForegroundNotificationInfo(
          title: 'ULOS Tracking',
          content: syncActive
              ? 'Tracking aktif dan sync background aktif.'
              : 'Tracking dan sync background nonaktif.',
        );
      }
    }

    return true;
  }

  Future<void> startPositionStream(ServiceInstance service) async {
    await positionSubscription?.cancel();

    final speedIntervalSeconds = gpsState.isMovingOptimized
        ? constants.BackgroundTrackingConstants.movingVehicleIntervalSeconds
        : (gpsState.isLowSpeedMode ? 60 : EnvService.locationIntervalSeconds);

    final accuracy = gpsState.accuracy;

    positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: AndroidSettings(
            accuracy: accuracy,
            distanceFilter: gpsState.distanceFilterMeters.toInt(),
            intervalDuration: Duration(seconds: speedIntervalSeconds),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationText:
                  'ULOS sedang merekam lokasi Anda secara otomatis',
              notificationTitle: 'Tracking Aktif',
              enableWakeLock: false,
            ),
          ),
        ).listen((Position position) async {
          await onPosition(position, service);
        }, onError: (e) => logger.e('STREAM GPS ERROR: $e'));
  }

  Future<void> restartPositionStream(ServiceInstance service) async {
    logger.d(
      'Restarting GPS stream. movingOptimized=${gpsState.isMovingOptimized}',
    );
    await startPositionStream(service);
  }

  Future<void> onPosition(Position position, ServiceInstance service) async {
    if (!trackingEnabled) return;

    final prefs = await SharedPreferences.getInstance();
    final isTrackingPref = prefs.getBool('is_tracking') ?? false;

    if (!isTrackingPref) {
      logger.d(
        'GPS received but prefs is_tracking=false while trackingEnabled=$trackingEnabled. lat=${position.latitude} lng=${position.longitude}',
      );
    }

    if (position.accuracy >
        constants.BackgroundTrackingConstants.maxAccuracyThresholdMeters) {
      return;
    }

    final speedKmh = position.speed * 3.6;

    // state transitions
    gpsState.onSpeedKmh(
      speedKmh,
      restartRequested: () {
        restartPositionStream(service);
      },
    );

    // Create entity
    final entity = LocationEntity(
      lat: position.latitude,
      lng: position.longitude,
      timestamp: position.timestamp,
      accuracy: position.accuracy,
      altitude: position.altitude,
      speed: position.speed,
      isMocked: position.isMocked,
      surveiId: surveiId,
      sessionId: sessionId,
      batteryLevel: null,
    );

    buffer.add(entity);

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'ULOS Tracking Aktif',
        content: 'Berhasil mencatat ${buffer.length} titik lokasi.',
      );
    }
  }

  Future<void> flushBufferToDb() async {
    if (buffer.isEmpty) return;

    if (!buffer.shouldFlush()) return;

    final batch = buffer.drain();

    try {
      await repository!.insertBatch(batch);
      logger.i('Flushed ${batch.length} → DB');
    } catch (e) {
      logger.e('Flush failed: $e → rollback batch');
      buffer.rollback(batch);
    }
  }
}
