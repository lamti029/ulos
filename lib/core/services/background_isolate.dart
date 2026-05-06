import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';
import '../models/location_entity.dart';
import 'location_repository.dart';
import 'env_service.dart';

StreamSubscription<Position>? _positionSubscription;
Logger? _logger;
List<LocationEntity> _buffer = [];
LocationEntity? _lastSavedPosition;
double _distanceFilterMeters = 5.0;
int? _surveiId;
LocationRepository? _repository;

@pragma('vm:entry-point')
Future<bool> onStart(ServiceInstance service) async {
  try {
    _logger ??= Logger();
    _logger?.i('Background isolate onStart() called');

    _repository = LocationRepository();
    await _repository!.initialize();

    _distanceFilterMeters = 5.0;
    _buffer.clear();
    _lastSavedPosition = null;

    _logger?.i('Background service fully initialized');

    // Load env after repo init (safe in isolate)
    await EnvService.load();
    _distanceFilterMeters = EnvService.distanceFilterMeters;

    _logger?.i('Env loaded: distanceFilter=${_distanceFilterMeters}m');
  } catch (e) {
    _logger?.e('onStart() init error: $e');
    service.invoke('initError', {'error': e.toString()});
    return false;
  }

  if (service is AndroidServiceInstance) {
    // Memastikan service berjalan sebagai Foreground Service segera setelah start
    service.setAsForegroundService();

    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });

    service.setForegroundNotificationInfo(
      title: 'ULOS Tracking',
      content: 'Menyiapkan pemindaian lokasi...',
    );
  }

  service.on('stopService').listen((event) async {
    _logger?.i('Received stopService');
    await _positionSubscription?.cancel();
    await _flushBuffer();
    service.stopSelf();
  });

  service.on('flushNow').listen((event) async {
    _logger?.i('Received flushNow');
    await _flushBuffer();
    service.invoke('flushComplete');
  });

  // Dynamic config updates from main thread
  service.on('setConfig').listen((event) {
    final data = event as Map;
    if (data['surveiId'] != null) {
      _surveiId = data['surveiId'] as int?;
      _logger?.i('Updated surveiId: $_surveiId');
    }
    if (data['distanceFilterMeters'] != null) {
      _distanceFilterMeters = (data['distanceFilterMeters'] as num).toDouble();
      _logger?.i('Updated distanceFilter: $_distanceFilterMeters m');
    }
  });

  _positionSubscription =
      Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0, // Manual filter applied later
          intervalDuration: Duration(
            seconds: EnvService.locationIntervalSeconds,
          ),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationText: "ULOS sedang merekam lokasi Anda secara otomatis",
            notificationTitle: "Tracking Aktif",
            enableWakeLock: true,
          ),
        ),
      ).listen(
        (Position position) {
          try {
            _logger?.i(
              'STREAM GPS: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
            );
            _onPosition(position, service);
          } catch (e) {
            _logger?.e('Position handler error: $e');
          }
        },
        onError: (e) {
          _logger?.e('STREAM GPS ERROR: $e');
        },
      );

  // Periodic flush using env config (safe >1min)
  Timer.periodic(Duration(seconds: EnvService.flushIntervalSeconds), (_) async {
    try {
      await _flushBuffer();
      _logger?.i('Auto-flushed ${_buffer.length} → 0');
    } catch (e) {
      _logger?.e('Auto-flush error: $e');
    }
  });

  _logger?.i('Background service started with Stream active');
  return true;
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  _logger?.i('iOS background mode activated');
  return true;
}

void _onPosition(Position position, ServiceInstance service) {
  final entity = LocationEntity(
    lat: position.latitude,
    lng: position.longitude,
    timestamp: position.timestamp,
    accuracy: position.accuracy,
    altitude: position.altitude,
    speed: position.speed,
    isMocked: position.isMocked,
    surveiId: _surveiId,
  );

  // Filter jarak manual
  if (_lastSavedPosition != null) {
    final distance = _calculateDistance(
      _lastSavedPosition!.lat,
      _lastSavedPosition!.lng,
      entity.lat,
      entity.lng,
    );
    if (distance < _distanceFilterMeters) {
      _logger?.i('Skipped (dist: ${distance.toStringAsFixed(1)}m)');
      return;
    }
  }

  _buffer.add(entity);
  _lastSavedPosition = entity;
  _logger?.i('Buffered (${_buffer.length})');

  // Update notifikasi agar OS melihat aktivitas berkelanjutan
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: 'ULOS Tracking Aktif',
      content: 'Berhasil mencatat ${_buffer.length} titik lokasi.',
    );
  }
}

Future<void> _flushBuffer() async {
  if (_buffer.isEmpty) {
    _logger?.v('Buffer empty, skip flush');
    return;
  }

  final batch = List<LocationEntity>.from(_buffer);
  _buffer.clear();

  try {
    await _repository!.insertBatch(batch);
    _logger?.i('Flushed ${batch.length} → DB (surveiId: $_surveiId)');
  } catch (e) {
    _logger?.e('Flush failed: $e → rollback batch');
    _buffer.insertAll(0, batch);
  }
}

double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const earthRadius = 6371000.0; // Meter
  final dLat = _toRadians(lat2 - lat1);
  final dLon = _toRadians(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(lat1)) *
          math.cos(_toRadians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadius * c;
}

double _toRadians(double degree) => degree * math.pi / 180;
