import 'dart:io';

// import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Loads environment configuration.

class EnvService {
  static String? _baseUrl;
  static String get baseUrl {
    final v = _baseUrl;
    if (v == null || v.isEmpty) {
      return 'https://trackingapi.bps.web.id';
    }
    return v;
  }

  static late final String environment;

  static int distanceFilterMeters = 30;
  static int locationIntervalSeconds = 30;
  static int flushIntervalSeconds = 60;
  static int syncIntervalSeconds = 300;
  static int batchLimit = 100;

  static Future<void> load() async {
    // 0. Determine environment from dart-define (compile-time constant)
    const String env = String.fromEnvironment('ENV', defaultValue: 'prod');
    environment = env;

    String? loadedUrl;

    try {
      final envFile = '.env.$env';
      await dotenv.load(fileName: envFile);
      final url = dotenv.env['BASE_URL'];
      if (url != null && url.isNotEmpty) {
        loadedUrl = url;
      }
    } catch (_) {
      // .env.{env} not available, continue to fallback
    }

    if (loadedUrl == null) {
      try {
        await dotenv.load(fileName: '.env');
        final url = dotenv.env['BASE_URL'];
        if (url != null && url.isNotEmpty) {
          loadedUrl = url;
        }
      } catch (_) {}
    }

    _baseUrl = loadedUrl ?? 'https://trackingapi.bps.web.id';

    if (Platform.isAndroid) {
      final current = _baseUrl ?? 'https://trackingapi.bps.web.id';
      _baseUrl = _remapEmulatorHost(current);
    }

    // 6. Load background location service configurations
    int? loadedDistanceFilter;
    int? loadedLocationInterval;
    int? loadedFlushInterval;
    int? loadedSyncInterval;
    int? loadedBatchLimit;

    // Try .env.{env} file
    try {
      final df = dotenv.env['DISTANCE_FILTER_METERS'];
      if (df != null && df.isNotEmpty) {
        loadedDistanceFilter = int.tryParse(df);
      }
      final li = dotenv.env['LOCATION_INTERVAL_SECONDS'];
      if (li != null && li.isNotEmpty) {
        loadedLocationInterval = int.tryParse(li);
      }
      final fi = dotenv.env['FLUSH_INTERVAL_SECONDS'];
      if (fi != null && fi.isNotEmpty) {
        loadedFlushInterval = int.tryParse(fi);
      }
      final si = dotenv.env['SYNC_INTERVAL_SECONDS'];
      if (si != null && si.isNotEmpty) {
        loadedSyncInterval = int.tryParse(si);
      }
      final bl = dotenv.env['BATCH_LIMIT'];
      if (bl != null && bl.isNotEmpty) {
        loadedBatchLimit = int.tryParse(bl);
      }
    } catch (_) {}

    // Fallback values (original hardcoded values)
    distanceFilterMeters = loadedDistanceFilter ?? 30;
    locationIntervalSeconds = loadedLocationInterval ?? 30;
    flushIntervalSeconds = loadedFlushInterval ?? 60;
    syncIntervalSeconds = loadedSyncInterval ?? 300;
    batchLimit = loadedBatchLimit ?? 100;

    // try {
    //   await Firebase.initializeApp();
    //   final remoteConfig = FirebaseRemoteConfig.instance;

    //   // Optional: use defaults in Remote Config dashboard.
    //   await remoteConfig.setConfigSettings(
    //     RemoteConfigSettings(
    //       fetchTimeout: const Duration(minutes: 2),
    //       minimumFetchInterval: const Duration(minutes: 60),
    //     ),
    //   );

    //   bool updated = await remoteConfig.fetchAndActivate();
    //   if (updated) {
    //     final rcSync = remoteConfig.getInt('syncIntervalSeconds');
    //     final rcLoc = remoteConfig.getInt('locationIntervalSeconds');
    //     final rcFlush = remoteConfig.getInt('flushIntervalSeconds');
    //     final rcDist = remoteConfig.getInt('distanceFilterMeters');

    //     if (rcDist > 0) distanceFilterMeters = rcDist;
    //     if (rcLoc > 0) locationIntervalSeconds = rcLoc;
    //     if (rcFlush > 0) flushIntervalSeconds = rcFlush;
    //     if (rcSync > 0) syncIntervalSeconds = rcSync;
    //   }
    // } catch (_) {
    //   // Keep fallback values when remote config isn't available.
    // }
  }

  static Future<void> refresh() async {
    await load();
  }

  static String _remapEmulatorHost(String url) {
    const replacements = {
      'localhost': '10.0.2.2',
      '127.0.0.1': '10.0.2.2',
      '[::1]': '10.0.2.2',
    };

    String remapped = url;
    replacements.forEach((from, to) {
      remapped = remapped.replaceAll(from, to);
    });
    return remapped;
  }
}
