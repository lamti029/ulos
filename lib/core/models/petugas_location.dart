class PetugasLocation {
  final int? id;
  final int? userId;
  final int? surveiId;
  final String? namaPetugas;
  final double? latitude;
  final double? longitude;
  final num? accuracy;
  final num? speed;
  final num? altitude;
  final num? batteryLevel;
  final bool? isMocked;
  final DateTime? timestamp;

  PetugasLocation({
    this.id,
    this.userId,
    this.surveiId,
    this.namaPetugas,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.speed,
    this.altitude,
    this.batteryLevel,
    this.isMocked,
    this.timestamp,
  });

  static DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  static num? _parseNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  static bool? _parseBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    final s = v.toString().toLowerCase().trim();
    if (s == 'true') return true;
    if (s == 'false') return false;
    return null;
  }

  factory PetugasLocation.fromJson(Map<String, dynamic> json) {
    return PetugasLocation(
      id: _parseInt(json['id']),
      userId: _parseInt(json['user_id']),
      surveiId: _parseInt(json['survei_id']),
      namaPetugas:
          json['nama_petugas']?.toString() ?? json['user']?['name']?.toString(),
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      accuracy: _parseNum(json['accuracy']),
      speed: _parseNum(json['speed']),
      altitude: _parseNum(json['altitude']),
      batteryLevel: _parseNum(json['battery_level']),
      isMocked: _parseBool(json['is_mocked']),
      timestamp: _parseDateTime(json['timestamp'] ?? json['created_at']),
    );
  }
}
