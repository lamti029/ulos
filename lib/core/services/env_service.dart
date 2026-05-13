import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Loads environment configuration.
///
/// Priority:
/// 1. Dart-define `ENV` (dev/prod) — determines which file set to load.
/// 2. `.env.{ENV}` file (via flutter_dotenv) — standard for dev/prod builds.
/// 3. `env.{ENV}.json` from server root (web) or assets (mobile) — allows
///    post-build configuration swaps without recompiling.
/// 4. Legacy `.env` / `assets/env.json` — backward compatibility.
/// 5. Hard-coded fallback.
class EnvService {
  static late final String baseUrl;
  // static late final double locationThreshold;
  static late final String environment;

  // Background location service configurations
  static late final double distanceFilterMeters;
  static late final int locationIntervalSeconds;
  static late final int flushIntervalSeconds;
  static late final int syncIntervalSeconds;
  static late final int batchLimit;

  static Future<void> load() async {
    // 0. Determine environment from dart-define (compile-time constant)
    const String env = String.fromEnvironment('ENV', defaultValue: 'prod');
    environment = env;

    String? loadedUrl;

    // 1. Try environment-specific .env file (e.g., .env.dev, .env.prod)
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

    // 2. Try environment-specific env.json (e.g., assets/env.dev.json)
    if (loadedUrl == null) {
      try {
        final jsonFile = 'assets/env.$env.json';
        final jsonString = await rootBundle.loadString(jsonFile);
        final config = jsonDecode(jsonString) as Map<String, dynamic>;
        loadedUrl ??= config['baseUrl'] as String?;
      } catch (_) {
        // env.{env}.json not available, continue to fallback
      }
    }

    // 3. Legacy fallback: .env (backward compatibility)
    if (loadedUrl == null) {
      try {
        await dotenv.load(fileName: '.env');
        final url = dotenv.env['BASE_URL'];
        if (url != null && url.isNotEmpty) {
          loadedUrl = url;
        }
      } catch (_) {}
    }

    // 4. Legacy fallback: env.json (backward compatibility)
    if (loadedUrl == null) {
      if (kIsWeb) {
        loadedUrl = await _loadFromWeb();
      } else {
        loadedUrl = await _loadFromAsset();
      }
    }

    // 5. Final fallback
    baseUrl = loadedUrl ?? 'https://trackingapi.bps.web.id';

    // Android emulator can’t reach services on the dev machine via localhost.
    // If baseUrl is configured as localhost/127.0.0.1, remap it to the
    // Android emulator alias for the host machine.
    //
    // https://developer.android.com/studio/run/emulator-networking
    if (Platform.isAndroid) {
      baseUrl = _remapEmulatorHost(baseUrl);
    }

    // 6. Load background location service configurations
    double? loadedDistanceFilter;
    int? loadedLocationInterval;
    int? loadedFlushInterval;
    int? loadedSyncInterval;
    int? loadedBatchLimit;

    // Try .env.{env} file
    try {
      final df = dotenv.env['DISTANCE_FILTER_METERS'];
      if (df != null && df.isNotEmpty) {
        loadedDistanceFilter = double.tryParse(df);
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

    // Try env.{env}.json if not loaded from .env
    if (loadedDistanceFilter == null ||
        loadedLocationInterval == null ||
        loadedFlushInterval == null ||
        loadedSyncInterval == null ||
        loadedBatchLimit == null) {
      try {
        final jsonString = await rootBundle.loadString(
          'assets/env.$environment.json',
        );
        final config = jsonDecode(jsonString) as Map<String, dynamic>;

        if (loadedDistanceFilter == null) {
          final df = config['distanceFilterMeters'];
          if (df != null) {
            loadedDistanceFilter = (df is num)
                ? df.toDouble()
                : double.tryParse(df.toString());
          }
        }
        if (loadedLocationInterval == null) {
          final li = config['locationIntervalSeconds'];
          if (li != null) {
            loadedLocationInterval = (li is num)
                ? li.toInt()
                : int.tryParse(li.toString());
          }
        }
        if (loadedFlushInterval == null) {
          final fi = config['flushIntervalSeconds'];
          if (fi != null) {
            loadedFlushInterval = (fi is num)
                ? fi.toInt()
                : int.tryParse(fi.toString());
          }
        }
        if (loadedSyncInterval == null) {
          final si = config['syncIntervalSeconds'];
          if (si != null) {
            loadedSyncInterval = (si is num)
                ? si.toInt()
                : int.tryParse(si.toString());
          }
        }
        if (loadedBatchLimit == null) {
          final bl = config['batchLimit'];
          if (bl != null) {
            loadedBatchLimit = (bl is num)
                ? bl.toInt()
                : int.tryParse(bl.toString());
          }
        }
      } catch (_) {}
    }

    // Fallback values (original hardcoded values)
    distanceFilterMeters = loadedDistanceFilter ?? 5.0;
    locationIntervalSeconds = loadedLocationInterval ?? 10;
    flushIntervalSeconds = loadedFlushInterval ?? 60;
    syncIntervalSeconds = loadedSyncInterval ?? 60;
    batchLimit = loadedBatchLimit ?? 100;
  }

  static Future<String?> _loadFromWeb() async {
    // Try env-specific first, then legacy env.json
    try {
      final jsonString = await rootBundle.loadString(
        'assets/env.$environment.json',
      );
      final config = jsonDecode(jsonString) as Map<String, dynamic>;
      return config['baseUrl'] as String?;
    } catch (_) {}

    try {
      final jsonString = await rootBundle.loadString('assets/env.json');
      final config = jsonDecode(jsonString) as Map<String, dynamic>;
      return config['baseUrl'] as String?;
    } catch (_) {}

    try {
      final dio = Dio();
      final response = await dio.get(
        'env.json',
        options: Options(
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      if (response.data is Map<String, dynamic>) {
        return response.data['baseUrl'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _remapEmulatorHost(String url) {
    // Only rewrite hosts that commonly point to the emulator itself.
    // - localhost
    // - 127.0.0.1
    // - [::1]
    const replacements = {
      'localhost': '10.0.2.2',
      '127.0.0.1': '10.0.2.2',
      '[::1]': '10.0.2.2',
    };

    String remapped = url;
    replacements.forEach((from, to) {
      // Replace both with/without scheme. Use simple string replace
      // because baseUrl is expected to be a full URL.
      remapped = remapped.replaceAll(from, to);
    });
    return remapped;
  }

  static Future<String?> _loadFromAsset() async {
    try {
      final jsonString = await rootBundle.loadString(
        'assets/env.$environment.json',
      );
      final config = jsonDecode(jsonString) as Map<String, dynamic>;
      return config['baseUrl'] as String?;
    } catch (_) {}

    try {
      final jsonString = await rootBundle.loadString('assets/env.json');
      final config = jsonDecode(jsonString) as Map<String, dynamic>;
      return config['baseUrl'] as String?;
    } catch (_) {
      return null;
    }
  }
}
