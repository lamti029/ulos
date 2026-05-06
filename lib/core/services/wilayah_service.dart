import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/utils/jwt_utils.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/geojson_utils.dart';

class WilayahService {
  static List<Polygon> _wilayahPolygons = [];
  static List<String> _wilayahSubSLSIds = [];
  static List<Map<String, dynamic>> _wilayahData = [];
  static List<Map<String, dynamic>> _targetPoints = [];

  // Getters
  static List<Polygon> get wilayahPolygons => _wilayahPolygons;
  static List<String> get wilayahSubSLSIds => _wilayahSubSLSIds;
  static List<Map<String, dynamic>> get wilayahData => _wilayahData;
  static List<Map<String, dynamic>> get targetPoints => _targetPoints;

  // Serialization helpers
  static Map<String, double> _latLngToMap(LatLng point) {
    return {'lat': point.latitude, 'lng': point.longitude};
  }

  static LatLng _mapToLatLng(Map<String, dynamic> map) {
    return LatLng(map['lat'] as double, map['lng'] as double);
  }

  static List<Map<String, double>> _pointsToList(List<LatLng> points) {
    return points.map(_latLngToMap).toList();
  }

  static List<LatLng> _listToPoints(List<dynamic> list) {
    return list.map((e) => _mapToLatLng(e as Map<String, dynamic>)).toList();
  }

  static Map<String, dynamic> _polygonToMap(Polygon polygon) {
    final color = polygon.color ?? AppColors.primary.withAlpha(51);
    final borderColor = polygon.borderColor ?? AppColors.primary;
    debugPrint(
      '[WilayahService] Serializing colors: color=${color.value}, borderColor=${borderColor.value}',
    );
    return {
      'points': _pointsToList(polygon.points),
      'color': color.value,
      'borderColor': borderColor.value,
      'borderStrokeWidth': polygon.borderStrokeWidth,
    };
  }

  static Polygon _mapToPolygon(Map<String, dynamic> map) {
    final colorInt = map['color'] as int?;
    final borderColorInt = map['borderColor'] as int?;
    if (colorInt == null || borderColorInt == null) {
      throw FormatException(
        'Missing/invalid color values in map: color=$colorInt, borderColor=$borderColorInt',
      );
    }
    return Polygon(
      points: _listToPoints(map['points']),
      color: Color(colorInt),
      borderColor: Color(borderColorInt),
      borderStrokeWidth: map['borderStrokeWidth'] as double? ?? 2.0,
    );
  }

  static Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('wilayah_sub_sls_ids', _wilayahSubSLSIds);
    await prefs.setString('wilayah_data_json', jsonEncode(_wilayahData));
    await prefs.setString('target_points_json', jsonEncode(_targetPoints));
    await prefs.setString(
      'wilayah_polygons_json',
      jsonEncode(_wilayahPolygons.map(_polygonToMap).toList()),
    );
  }

  static Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    debugPrint('[WilayahService] Loading from prefs keys: ${prefs.getKeys()}');
    _wilayahSubSLSIds = prefs.getStringList('wilayah_sub_sls_ids') ?? [];
    _wilayahData =
        (jsonDecode(prefs.getString('wilayah_data_json') ?? '[]') as List)
            .cast<Map<String, dynamic>>();
    _targetPoints =
        (jsonDecode(prefs.getString('target_points_json') ?? '[]') as List)
            .cast<Map<String, dynamic>>();
    final polygonsJson = prefs.getString('wilayah_polygons_json') ?? '[]';
    debugPrint('[WilayahService] polygonsJson length: ${polygonsJson.length}');
    try {
      final polygonsList = jsonDecode(polygonsJson) as List;
      debugPrint(
        '[WilayahService] parsed polygons list length: ${polygonsList.length}',
      );
      _wilayahPolygons = polygonsList
          .map((e) {
            try {
              return _mapToPolygon(e as Map<String, dynamic>);
            } catch (e) {
              debugPrint('[WilayahService] Failed to parse polygon $e: $e');
              return null;
            }
          })
          .where((p) => p != null)
          .cast<Polygon>()
          .toList();
      debugPrint('[WilayahService] loaded ${_wilayahPolygons.length} polygons');
    } catch (e) {
      debugPrint('[WilayahService] Failed to load polygons from prefs: $e');
      _wilayahPolygons = [];
    }
  }

  static Future<bool> _hasValidData() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getInt('last_wilayah_sync') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiry = now - (24 * 60 * 60 * 1000); // 24h
    return lastSync > expiry &&
        prefs.containsKey('wilayah_sub_sls_ids') &&
        (prefs.getStringList('wilayah_sub_sls_ids') ?? []).isNotEmpty;
  }

  static Future<List<Map<String, dynamic>>> _fetchAllPagesForSubSLS(
    String idSubSLS,
  ) async {
    final List<Map<String, dynamic>> allData = [];
    const int limit = 100;

    final firstResponse = await DioClient().dio.get(
      ApiConstants.titikSasaran,
      queryParameters: {
        'id_subsls': idSubSLS,
        'survei_id': 2,
        'page': 1,
        'limit': limit,
      },
    );

    if (firstResponse.statusCode != 200) return allData;

    allData.addAll(
      List<Map<String, dynamic>>.from(firstResponse.data['data'] ?? []),
    );

    final totalPages =
        firstResponse.data['meta']?['pagination']?['total_pages'] ?? 1;

    if (totalPages > 1) {
      final futures = <Future<Response>>[];
      for (int page = 2; page <= totalPages; page++) {
        futures.add(
          DioClient().dio.get(
            ApiConstants.titikSasaran,
            queryParameters: {
              'id_subsls': idSubSLS,
              'survei_id': 2,
              'page': page,
              'limit': limit,
            },
          ),
        );
      }
      final responses = await Future.wait(futures);
      for (final response in responses) {
        if (response.statusCode == 200) {
          allData.addAll(
            List<Map<String, dynamic>>.from(response.data['data'] ?? []),
          );
        }
      }
    }
    return allData;
  }

  static Future<void> _fetchTargetPoints() async {
    final List<Map<String, dynamic>> allTargetPoints = [];
    for (final idSubSLS in _wilayahSubSLSIds) {
      final data = await _fetchAllPagesForSubSLS(idSubSLS);
      allTargetPoints.addAll(data);
    }
    _targetPoints = allTargetPoints;
  }

  static Future<void> _fetchWilayah() async {
    final userId = await JwtUtils.getUserId();
    if (userId == null) return;

    final response = await DioClient().dio.get(
      ApiConstants.wilayah,
      queryParameters: {'petugas_id': userId, 'survei_id': 2},
    );

    if (response.statusCode != 200) return;

    final List<dynamic> data = response.data['data'] ?? [];
    final List<Polygon> polygons = [];

    for (final item in data) {
      final geoJsonStr = item['geojson'] as String?;
      if (geoJsonStr == null || geoJsonStr.isEmpty) continue;

      final rings = GeoJsonUtils.parseGeoJson(geoJsonStr);
      for (final ring in rings) {
        if (ring.length >= 3) {
          polygons.add(
            Polygon(
              points: ring,
              color: AppColors.primary.withAlpha(51),
              borderColor: AppColors.primary,
              borderStrokeWidth: 2.0,
            ),
          );
        }
      }
    }

    _wilayahPolygons = polygons;
    _wilayahData = data.map((e) => Map<String, dynamic>.from(e)).toList();
    _wilayahSubSLSIds = data
        .map((item) => item['id_subsls']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  /// Main init method: Load from prefs if valid, else fetch from API and save.
  static Future<void> init() async {
    debugPrint('[WilayahService] init() called');
    try {
      if (await _hasValidData()) {
        await _loadFromPrefs();
        debugPrint('[WilayahService] Loaded data from SharedPreferences');
        // Validate loaded data
        if (_wilayahPolygons.isEmpty && _wilayahSubSLSIds.isNotEmpty) {
          debugPrint('[WilayahService] Loaded data invalid, refetching');
          throw Exception('Invalid loaded data');
        }
      } else {
        throw Exception('No valid cached data');
      }
    } catch (e) {
      debugPrint(
        '[WilayahService] Cache load failed ($e), clearing and refetching',
      );
      await _clearPrefs();
      await _fetchWilayah();
      await _fetchTargetPoints();
      await _saveToPrefs();
      debugPrint(
        '[WilayahService] Fetched fresh data from API and saved to prefs',
      );
    }
    debugPrint(
      '[WilayahService] Final state: ${_wilayahPolygons.length} polygons, ${_wilayahSubSLSIds.length} subSLS',
    );
  }

  /// Ensure initialized, call if needed (e.g. in tracking init)
  static Future<void> ensureInitialized() async {
    if (_wilayahSubSLSIds.isEmpty) {
      await init();
    }
  }

  /// Clear data (logout?)
  static Future<void> _clearPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('wilayah_sub_sls_ids');
    await prefs.remove('wilayah_data_json');
    await prefs.remove('target_points_json');
    await prefs.remove('wilayah_polygons_json');
    await prefs.remove('last_wilayah_sync');
    debugPrint('[WilayahService] Cleared all wilayah prefs');
    _wilayahPolygons.clear();
    _wilayahSubSLSIds.clear();
    _wilayahData.clear();
    _targetPoints.clear();
  }

  /// Public clear (e.g. for logout)
  static Future<void> clear() async {
    await _clearPrefs();
  }
}
