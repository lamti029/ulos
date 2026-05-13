import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';

class LocationService {
  final Logger _logger = Logger();
  StreamSubscription<Position>? _positionStreamSubscription;

  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await requestPermission();
      if (!hasPermission) return null;
      return await Geolocator.getCurrentPosition(
        // locationSettings: const LocationSettings(
        //   accuracy: LocationAccuracy.high,
        // ),
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      _logger.e('Error getting current position: $e');
      return null;
    }
  }

  Stream<Position> startTracking({int intervalSeconds = 10}) {
    final locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 10),
      distanceFilter: 0,
    );

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  void stopTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
  }
}
