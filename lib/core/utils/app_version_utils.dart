import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionUtils {
  const AppVersionUtils._();

  static Future<String> getAppVersionText() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version;
      final buildNumber = info.buildNumber;

      if (buildNumber.isEmpty) return 'v$version';
      return 'v$version+$buildNumber';
    } catch (e) {
      if (kDebugMode) {
        print('[AppVersionUtils] Failed: $e');
      }
      return 'v-';
    }
  }
}
