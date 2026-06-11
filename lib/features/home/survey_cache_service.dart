import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/survey.dart';
import '../../core/services/survey_service.dart';

class SurveyCacheService {
  static const String _surveysJsonKeyPrefix = 'surveys_json_';
  static const String _lastSurveySyncMsKeyPrefix = 'last_survey_sync_ms_';

  static String _surveysJsonKeyForUser(int userId) =>
      '$_surveysJsonKeyPrefix$userId';

  static String _lastSurveySyncMsKeyForUser(int userId) =>
      '$_lastSurveySyncMsKeyPrefix$userId';

  /// Untuk requirement saat ini: refresh survei hanya boleh dilakukan manual.
  /// Jadi auto-refresh interval tidak dipakai.
  static const Duration autoRefreshInterval = Duration(days: 1);

  /// Cooldown agar tombol Refresh tidak memicu request berulang.
  static const Duration manualRefreshCooldown = Duration(hours: 1);

  static Future<List<SurveyModel>> loadCachedSurveys({
    required int userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_surveysJsonKeyForUser(userId));

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

  static Future<DateTime?> loadLastSyncTime({required int userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_lastSurveySyncMsKeyForUser(userId));
    if (ms == null || ms == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> saveSurveysToCache({
    required int userId,
    required List<SurveyModel> surveys,
  }) async {
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

    await prefs.setString(_surveysJsonKeyForUser(userId), jsonEncode(payload));
    await prefs.setInt(
      _lastSurveySyncMsKeyForUser(userId),
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Requirement: auto refresh tidak dipakai.
  /// Tetap dibiarkan untuk kompatibilitas, tapi selalu false.
  static Future<bool> shouldAutoRefresh() async => false;

  /// Guard untuk refresh manual agar paling cepat sekali dalam 1 jam.
  static Future<bool> canRefreshNow({
    required bool force,
    required int userId,
  }) async {
    if (!force) return false;

    final last = await loadLastSyncTime(userId: userId);
    if (last == null) return true;

    return DateTime.now().difference(last) >= manualRefreshCooldown;
  }

  static Future<void> refreshCacheIfNeeded({
    required SurveyService surveyService,
    required int userId,
    bool force = false,
  }) async {
    final cached = await loadCachedSurveys(userId: userId);
    final should = force || cached.isEmpty || await shouldAutoRefresh();
    if (!should) return;

    final surveys = await surveyService.fetchSurveys();
    await saveSurveysToCache(userId: userId, surveys: surveys);
  }

  /// Clear cache for a specific user.
  static Future<void> clearForUser(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_surveysJsonKeyForUser(userId));
    await prefs.remove(_lastSurveySyncMsKeyForUser(userId));
  }
}
