import 'package:latlong2/latlong.dart';

/// Represents a single captured GPS point stored in the local SQLite database.
class LocationEntity {
  final int? id;
  final double lat;
  final double lng;
  final DateTime timestamp;
  final double? accuracy;
  final double? altitude;
  final double? speed;
  final bool isMocked;
  final int? surveiId;
  final bool isSynced;
  final DateTime? createdAt;

  const LocationEntity({
    this.id,
    required this.lat,
    required this.lng,
    required this.timestamp,
    this.accuracy,
    this.altitude,
    this.speed,
    this.isMocked = false,
    this.surveiId,
    this.isSynced = false,
    this.createdAt,
  });

  /// Convert to a Map for sqflite insert.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'lat': lat,
      'lng': lng,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'accuracy': accuracy,
      'altitude': altitude,
      'speed': speed,
      'is_mocked': isMocked ? 1 : 0,
      'survei_id': surveiId,
      'is_synced': isSynced ? 1 : 0,
      'created_at': createdAt?.toUtc().toIso8601String(),
    };
  }

  /// Create from a Map returned by sqflite query.
  factory LocationEntity.fromMap(Map<String, dynamic> map) {
    return LocationEntity(
      id: map['id'] as int?,
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      timestamp: DateTime.parse(map['timestamp'] as String),
      accuracy: (map['accuracy'] as num?)?.toDouble(),
      altitude: (map['altitude'] as num?)?.toDouble(),
      speed: (map['speed'] as num?)?.toDouble(),
      isMocked: map['is_mocked'] == 1,
      surveiId: map['survei_id'] as int?,
      isSynced: map['is_synced'] == 1,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
    );
  }

  /// Convert to API payload format.
  Map<String, dynamic> toApiPayload() {
    return {
      'latitude': lat,
      'longitude': lng,
      'accuracy': accuracy,
      'altitude': altitude,
      'speed': speed,
      'is_mocked': isMocked,
      'survei_id': surveiId,
      'timestamp': timestamp.toUtc().toIso8601String(),
    };
  }

  /// Convert to flutter_map LatLng for display.
  LatLng toLatLng() => LatLng(lat, lng);

  LocationEntity copyWith({
    int? id,
    double? lat,
    double? lng,
    DateTime? timestamp,
    double? accuracy,
    double? altitude,
    double? speed,
    bool? isMocked,
    int? surveiId,
    bool? isSynced,
    DateTime? createdAt,
  }) {
    return LocationEntity(
      id: id ?? this.id,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      timestamp: timestamp ?? this.timestamp,
      accuracy: accuracy ?? this.accuracy,
      altitude: altitude ?? this.altitude,
      speed: speed ?? this.speed,
      isMocked: isMocked ?? this.isMocked,
      surveiId: surveiId ?? this.surveiId,
      isSynced: isSynced ?? this.isSynced,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
