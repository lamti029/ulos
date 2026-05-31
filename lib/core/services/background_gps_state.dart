import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../constants/background_tracking_constants.dart';

class BackgroundGpsState {
  bool isMovingOptimized = false;
  bool isLowSpeedMode = false;

  double distanceFilterMeters;

  BackgroundGpsState({this.distanceFilterMeters = 30.0});

  LocationAccuracy get accuracy {
    if (isMovingOptimized) {
      return BackgroundTrackingConstants.movingVehicleAccuracy;
    }
    if (isLowSpeedMode) {
      return LocationAccuracy.medium;
    }
    return BackgroundTrackingConstants.defaultAccuracy;
  }

  int get intervalSeconds {
    if (isMovingOptimized) {
      return BackgroundTrackingConstants.movingVehicleIntervalSeconds;
    }
    if (isLowSpeedMode) {
      return 60;
    }
    // normal interval will be provided by EnvService in isolate.
    return 0;
  }

  void onSpeedKmh(
    double speedKmh, {
    required void Function() restartRequested,
  }) {
    // Moving-vehicle hysteresis
    if (!isMovingOptimized &&
        speedKmh >=
            BackgroundTrackingConstants.movingVehicleEnterThresholdKmh) {
      isMovingOptimized = true;
      restartRequested();
    } else if (isMovingOptimized &&
        speedKmh <= BackgroundTrackingConstants.movingVehicleExitThresholdKmh) {
      isMovingOptimized = false;
      restartRequested();
    }

    // Low-speed hysteresis
    if (!isLowSpeedMode &&
        speedKmh <= BackgroundTrackingConstants.lowSpeedEnterThresholdKmh) {
      isLowSpeedMode = true;
    } else if (isLowSpeedMode &&
        speedKmh >= BackgroundTrackingConstants.lowSpeedExitThresholdKmh) {
      isLowSpeedMode = false;
    }

    // Distance filter tuning
    if (isMovingOptimized) {
      distanceFilterMeters = math.max(
        distanceFilterMeters,
        BackgroundTrackingConstants.distanceFilterMovingMinMeters.toDouble(),
      );
    } else if (isLowSpeedMode) {
      distanceFilterMeters = math.max(
        distanceFilterMeters,
        BackgroundTrackingConstants.distanceFilterLowSpeedMinMeters.toDouble(),
      );
    } else {
      distanceFilterMeters = BackgroundTrackingConstants
          .distanceFilterNormalMeters
          .toDouble();
    }
  }

  double computeDistanceFilterMetersOrDefault(int fallbackMeters) {
    if (distanceFilterMeters <= 0) return fallbackMeters.toDouble();
    return distanceFilterMeters;
  }
}
