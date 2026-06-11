import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrackingController {
  TrackingController._();
  static final TrackingController instance = TrackingController._();

  static const String _keyActiveSurveiId = 'active_survei_id';
  static const String _keyIsTrackingActive = 'is_tracking';

  int? _activeSurveiId;
  bool _isTrackingActive = false; // Berikan default value false agar tidak null

  // --- GETTER ---

  int? get activeSurveiId => _activeSurveiId;

  // Ini yang membuat Anda bisa memanggil .isTrackingActive tanpa error/null
  bool get isTrackingActive => _isTrackingActive;

  /// Panggil ini di main.dart sebelum runApp()
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _activeSurveiId = prefs.getInt(_keyActiveSurveiId);
    debugPrint('_activeSurveiId $_activeSurveiId');

    // Load status tracking, jika belum pernah diset, default ke false
    _isTrackingActive = prefs.getBool(_keyIsTrackingActive) ?? false;
    debugPrint(
      '_activeSurveiId = $_activeSurveiId , _isTrackingActive = _isTrackingActive',
    );
  }

  bool canOperate(int surveiId) {
    if (_activeSurveiId == null) return true;
    return _activeSurveiId == surveiId;
  }

  Future<void> lockTo(int surveiId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setInt(_keyActiveSurveiId, surveiId);
      await prefs.setBool(_keyIsTrackingActive, true);

      // Update state lokal
      _activeSurveiId = surveiId;
      _isTrackingActive = true;
    } catch (e) {
      debugPrint('Gagal mengunci tracking: $e');
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.remove(_keyActiveSurveiId);
      await prefs.setBool(_keyIsTrackingActive, false);

      // Update state lokal
      _activeSurveiId = null;
      _isTrackingActive = false;
    } catch (e) {
      debugPrint('Gagal menghapus data tracking: $e');
    }
  }

  Future<void> reset() async {
    await clear();
  }
}
