import 'package:geolocator/geolocator.dart';

class BackgroundTrackingConstants {
  // Moving vehicle hysteresis thresholds (km/h)
  static const double movingVehicleEnterThresholdKmh = 45.0;
  static const double movingVehicleExitThresholdKmh = 35.0;

  // When moving, sample faster
  static const int movingVehicleIntervalSeconds = 15;
  static const LocationAccuracy movingVehicleAccuracy = LocationAccuracy.high;

  // Default (non-moving) accuracy
  static const LocationAccuracy defaultAccuracy = LocationAccuracy.medium;

  // Low-speed battery optimization hysteresis
  static const double lowSpeedEnterThresholdKmh = 5.0;
  static const double lowSpeedExitThresholdKmh = 8.0;

  // Flush policy
  static const int flushMinBufferSize = 15;
  static const int flushMaxAgeSeconds = 60;

  // Accuracy guard: ignore overly inaccurate positions
  static const double maxAccuracyThresholdMeters = 30.0;

  // Distance filter tuning
  static const int distanceFilterMovingMinMeters = 15;
  static const int distanceFilterLowSpeedMinMeters = 60;
  static const int distanceFilterNormalMeters = 30;
}
