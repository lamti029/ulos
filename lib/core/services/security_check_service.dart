import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class SecurityCheckResult {
  final bool isRooted;
  final bool isDeveloperMode;
  final bool isAutoTime;
  final List<String> warnings;

  SecurityCheckResult({
    required this.isRooted,
    required this.isDeveloperMode,
    required this.isAutoTime,
    required this.warnings,
  });

  bool get isSecure => !isRooted && !isDeveloperMode && isAutoTime;
}

class SecurityCheckService {
  static const MethodChannel _channel = MethodChannel('com.bps.ulos/security');

  static Future<SecurityCheckResult> performChecks() async {
    // On web or non-Android platforms, bypass checks
    if (kIsWeb || !Platform.isAndroid || kDebugMode) {
      return SecurityCheckResult(
        isRooted: false,
        isDeveloperMode: false,
        isAutoTime: true,
        warnings: [],
      );
    }

    try {
      final Map<dynamic, dynamic> result = await _channel.invokeMethod(
        'performSecurityChecks',
      );
      final isRooted = result['isRooted'] as bool;
      final isDeveloperMode = result['isDeveloperMode'] as bool;
      final isAutoTime = result['isAutoTime'] as bool;

      final List<String> warnings = [];
      if (isRooted) {
        warnings.add(
          'Device terdeteksi dalam mode ROOT. Matikan akses ROOT untuk melanjutkan.',
        );
      }
      if (isDeveloperMode) {
        warnings.add(
          'Mode Developer terdeteksi aktif. Nonaktifkan Mode Developer untuk melanjutkan.',
        );
      }
      if (!isAutoTime) {
        warnings.add(
          'Pengaturan waktu device harus dalam mode Automatic (Otomatis). Ubah ke mode Automatic di pengaturan.',
        );
      }

      return SecurityCheckResult(
        isRooted: isRooted,
        isDeveloperMode: isDeveloperMode,
        isAutoTime: isAutoTime,
        warnings: warnings,
      );
    } catch (e) {
      // If platform channel fails, assume secure to avoid blocking
      return SecurityCheckResult(
        isRooted: false,
        isDeveloperMode: false,
        isAutoTime: true,
        warnings: [],
      );
    }
  }
}
