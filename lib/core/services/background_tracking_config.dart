import 'package:flutter/foundation.dart';

class BackgroundTrackingConfig {
  final bool enable;
  final int? surveiId;
  final int? sessionId;
  final int? distanceFilterMeters;

  final int? syncIntervalSeconds;

  const BackgroundTrackingConfig({
    required this.enable,
    this.surveiId,
    this.sessionId,
    this.distanceFilterMeters,
    this.syncIntervalSeconds,
  });

  static bool parseEnable(dynamic enableRaw) {
    if (enableRaw == true) return true;
    if (enableRaw == 1) return true;
    if (enableRaw is String) {
      return enableRaw.toLowerCase().trim() == 'true';
    }
    return false;
  }

  static BackgroundTrackingConfig fromEventPayload(dynamic payload) {
    final map = (payload as Map).map((k, v) => MapEntry(k.toString(), v));

    final enable = parseEnable(map['enable']);

    final surveiIdRaw = map['surveiId'];
    final sessionIdRaw = map['sessionId'];
    final distanceFilterRaw = map['distanceFilterMeters'];
    final syncIntervalRaw = map['syncIntervalSeconds'];

    int? toInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    final surveiId = toInt(surveiIdRaw);
    final sessionId = toInt(sessionIdRaw);
    final distanceFilterMeters = toInt(distanceFilterRaw);
    final syncIntervalSeconds = toInt(syncIntervalRaw);

    debugPrint(
      'BackgroundTrackingConfig: enableRaw=${map['enable']} -> enable=$enable, surveiId=$surveiId, sessionId=$sessionId, distanceFilterMeters=$distanceFilterMeters, syncIntervalSeconds=$syncIntervalSeconds',
    );

    return BackgroundTrackingConfig(
      enable: enable,
      surveiId: surveiId,
      sessionId: sessionId,
      distanceFilterMeters: distanceFilterMeters,
      syncIntervalSeconds: syncIntervalSeconds,
    );
  }

  BackgroundTrackingConfig copyWith({
    bool? enable,
    int? surveiId,
    int? sessionId,
    int? distanceFilterMeters,
    int? syncIntervalSeconds,
  }) {
    return BackgroundTrackingConfig(
      enable: enable ?? this.enable,
      surveiId: surveiId ?? this.surveiId,
      sessionId: sessionId ?? this.sessionId,
      distanceFilterMeters: distanceFilterMeters ?? this.distanceFilterMeters,
      syncIntervalSeconds: syncIntervalSeconds ?? this.syncIntervalSeconds,
    );
  }
}
