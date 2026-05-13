import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionUtils {
  const AppVersionUtils._();

  static Future<String> getAppVersionText() async {
    try {
      final info = await PackageInfo.fromPlatform();
      // Flutter versionName is typically the semantic version
      // packageInfo.version already excludes build metadata sometimes.
      final version = info.version;
      final buildNumber = info.buildNumber;

      // If buildNumber is empty, just show version.
      if (buildNumber.isEmpty) return 'v$version';
      return 'v$version+$buildNumber';
    } catch (e) {
      // Fallback keeps UI from crashing.
      if (kDebugMode) {
        // ignore: avoid_print
        print('[AppVersionUtils] Failed: $e');
      }
      return 'v-';
    }
  }
}
