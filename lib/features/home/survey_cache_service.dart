import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/survey.dart';
import '../../core/services/survey_service.dart';

class SurveyCacheService {
  static const String _surveysJsonKey = 'surveys_json';
  static const String _lastSurveySyncMsKey = 'last_survey_sync_ms';

  /// Untuk requirement saat ini: refresh survei hanya boleh dilakukan manual.
  /// Jadi auto-refresh interval tidak dipakai.
  static const Duration autoRefreshInterval = Duration(days: 1);

  /// Cooldown agar tombol Refresh tidak memicu request berulang.
  static const Duration manualRefreshCooldown = Duration(hours: 1);

  static Future<List<SurveyModel>> loadCachedSurveys() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_surveysJsonKey);
    if (jsonStr == null || jsonStr.isEmpty) return const [];

    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! List) return const [];

      return decoded
          .whereType<Map<String, dynamic>>()
          .map((e) => SurveyModel.fromJson(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<DateTime?> loadLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_lastSurveySyncMsKey);
    if (ms == null || ms == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> saveSurveysToCache(List<SurveyModel> surveys) async {
    final prefs = await SharedPreferences.getInstance();

    final payload = surveys
        .map(
          (s) => {
            'id': s.id,
            'nama': s.nama,
            'title': s.title,
            'role_in_survei': s.roleInSurvei,
          },
        )
        .toList();

    await prefs.setString(_surveysJsonKey, jsonEncode(payload));
    await prefs.setInt(
      _lastSurveySyncMsKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Requirement: auto refresh tidak dipakai.
  /// Tetap dibiarkan untuk kompatibilitas, tapi selalu false.
  static Future<bool> shouldAutoRefresh() async => false;

  /// Guard untuk refresh manual agar paling cepat sekali dalam 1 jam.
  static Future<bool> canRefreshNow({required bool force}) async {
    if (!force) return false;

    final last = await loadLastSyncTime();
    if (last == null) return true;

    return DateTime.now().difference(last) >= manualRefreshCooldown;
  }

  static Future<void> refreshCacheIfNeeded({
    required SurveyService surveyService,
    bool force = false,
  }) async {
    final cached = await loadCachedSurveys();
    final should = force || cached.isEmpty || await shouldAutoRefresh();
    if (!should) return;

    final surveys = await surveyService.fetchSurveys();
    await saveSurveysToCache(surveys);
  }
}
