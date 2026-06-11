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
    return <String, double>{'lat': point.latitude, 'lng': point.longitude};
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

    // Lint fix: polygon.color is not nullable in practice; avoid dead null-aware.

    final borderColor = polygon.borderColor;

    return {
      'points': _pointsToList(polygon.points),
      'color': color.toARGB32(),
      'borderColor': borderColor.toARGB32(),
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

  static Future<List<Map<String, dynamic>>> _fetchAllPagesForSubSLS(
    String idSubSLS,
    int surveiId,
  ) async {
    final List<Map<String, dynamic>> allData = [];
    const int limit = 100;

    final firstResponse = await DioClient().dio.get(
      ApiConstants.titikSasaran,
      queryParameters: {
        'id_subsls': idSubSLS,
        'survei_id': surveiId,
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

  static Future<void> _fetchTargetPoints({required int surveiId}) async {
    final List<Map<String, dynamic>> allTargetPoints = [];
    for (final idSubSLS in _wilayahSubSLSIds) {
      final data = await _fetchAllPagesForSubSLS(idSubSLS, surveiId);
      allTargetPoints.addAll(data);
    }
    _targetPoints = allTargetPoints;
  }

  static String _roleToCachePart(String role) =>
      role.toLowerCase().trim().contains('pemeriksa') ? 'pemeriksa' : 'petugas';

  static String _keySubSls(int userId, int surveiId, String role) =>
      'wilayah_sub_sls_ids_${userId}_${surveiId}_${_roleToCachePart(role)}';

  static String _keyWilayahDataJson(int userId, int surveiId, String role) =>
      'wilayah_data_json_${userId}_${surveiId}_${_roleToCachePart(role)}';

  static String _keyTargetPointsJson(int userId, int surveiId, String role) =>
      'target_points_json_${userId}_${surveiId}_${_roleToCachePart(role)}';

  static String _keyWilayahPolygonsJson(
    int userId,
    int surveiId,
    String role,
  ) => 'wilayah_polygons_json_${userId}_${surveiId}_${_roleToCachePart(role)}';

  static String _keyLastWilayahSync(int userId, int surveiId, String role) =>
      'last_wilayah_sync_${userId}_${surveiId}_${_roleToCachePart(role)}';

  static Future<void> _fetchWilayah({
    required int userId,
    required int surveiId,
    required String role,
  }) async {
    final endpoint = _roleToCachePart(role) == 'pemeriksa'
        ? '/api/pemeriksa/wilayah'
        : ApiConstants.wilayah;

    final response = await DioClient().dio.get(
      endpoint,
      queryParameters: {'survei_id': surveiId},
    );

    if (response.statusCode != 200) return;

    final List<dynamic> data = response.data['data'] ?? [];
    final List<Polygon> polygons = [];

    for (final item in data) {
      final id = item['id'] ?? item['id_subsls'] ?? item['survei_id'];

      // geojson backend key bisa berbeda, jadi kita dukung beberapa kemungkinan.
      final rawGeojson =
          item['geojson'] ??
          item['geo_json'] ??
          item['geoJson'] ??
          item['geometry'];
      final geoJsonStr = rawGeojson is String
          ? rawGeojson
          : rawGeojson?.toString();

      debugPrint('[WilayahService] _fetchWilayah item id=$id');
      debugPrint(
        '[WilayahService] raw geojson type=${rawGeojson.runtimeType} len=${geoJsonStr?.length ?? 0}',
      );

      // Backend kadang tidak mengirim geojson pada endpoint wilayah.
      // Fallback: ambil geojson dari master-wilayah/subsls/{id_subsls}.
      String? geojsonForParsing = geoJsonStr;
      if (geojsonForParsing == null || geojsonForParsing.isEmpty) {
        final idSubSLS =
            item['id_subsls'] ?? item['idSubSLS'] ?? item['subsls_id'];
        if (idSubSLS != null) {
          try {
            final res = await DioClient().dio.get(
              '/api/master-wilayah/subsls/$idSubSLS',
            );

            if (res.statusCode == 200 || res.statusCode == 201) {
              final payload = res.data;
              final nested = payload is Map<String, dynamic> ? payload : null;
              final candidate = (nested?['data'] ?? payload) as dynamic;

              final fallbackRaw = candidate is Map<String, dynamic>
                  ? (candidate['geojson'] ??
                        candidate['geo_json'] ??
                        candidate['geoJson'] ??
                        candidate['geometry'])
                  : null;

              final fallbackStr = fallbackRaw is String
                  ? fallbackRaw
                  : fallbackRaw?.toString();

              debugPrint(
                '[WilayahService] fallback geojson from subsls id_subsls=$idSubSLS len=${fallbackStr?.length ?? 0}',
              );
              geojsonForParsing = fallbackStr;
            }
          } catch (e) {
            debugPrint(
              '[WilayahService] fallback geojson request failed for id_subsls=$idSubSLS err=$e',
            );
          }
        }

        debugPrint(
          '[WilayahService] geojson is empty/null for id=$id. Keys present: ${item.keys}',
        );
        if (geojsonForParsing == null || geojsonForParsing.isEmpty) {
          continue;
        }
      }

      List<List<LatLng>> rings = const <List<LatLng>>[];
      try {
        rings = GeoJsonUtils.parseGeoJson(
          geojsonForParsing ?? geoJsonStr ?? '',
        );
      } catch (e) {
        debugPrint('[WilayahService] parse geojson failed for id=$id err=$e');
      }

      debugPrint('[WilayahService] rings count for id=$id = ${rings.length}');

      var ringIndex = 0;
      for (final ring in rings) {
        ringIndex++;
        debugPrint('[WilayahService] ring #$ringIndex length=${ring.length}');
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
        .map((item) => item['id_subsls']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
  }

  static Future<void> _saveToPrefsFor({
    required int userId,
    required int surveiId,
    required String role,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setStringList(
      _keySubSls(userId, surveiId, role),
      _wilayahSubSLSIds,
    );
    await prefs.setString(
      _keyWilayahDataJson(userId, surveiId, role),
      jsonEncode(_wilayahData),
    );
    await prefs.setString(
      _keyTargetPointsJson(userId, surveiId, role),
      jsonEncode(_targetPoints),
    );
    await prefs.setString(
      _keyWilayahPolygonsJson(userId, surveiId, role),
      jsonEncode(_wilayahPolygons.map(_polygonToMap).toList()),
    );

    await prefs.setInt(
      _keyLastWilayahSync(userId, surveiId, role),
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<void> _loadFromPrefsFor({
    required int userId,
    required int surveiId,
    required String role,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _wilayahSubSLSIds =
        prefs.getStringList(_keySubSls(userId, surveiId, role)) ?? [];

    _wilayahData =
        (jsonDecode(
                  prefs.getString(
                        _keyWilayahDataJson(userId, surveiId, role),
                      ) ??
                      '[]',
                )
                as List)
            .cast<Map<String, dynamic>>();

    _targetPoints =
        (jsonDecode(
                  prefs.getString(
                        _keyTargetPointsJson(userId, surveiId, role),
                      ) ??
                      '[]',
                )
                as List)
            .cast<Map<String, dynamic>>();

    final polygonsJson =
        prefs.getString(_keyWilayahPolygonsJson(userId, surveiId, role)) ??
        '[]';

    final polygonsList = jsonDecode(polygonsJson) as List;
    _wilayahPolygons = polygonsList
        .map((e) {
          try {
            return _mapToPolygon(e as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<Polygon>()
        .toList();
  }

  static Future<bool> _hasValidDataFor({
    required int userId,
    required int surveiId,
    required String role,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final lastSync =
        prefs.getInt(_keyLastWilayahSync(userId, surveiId, role)) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiry = now - (24 * 60 * 60 * 1000); // 24h

    if (lastSync <= expiry) return false;

    final ids = prefs.getStringList(_keySubSls(userId, surveiId, role)) ?? [];
    return ids.isNotEmpty;
  }

  /// Main init method: load cache for (userId,sureveiId,role), else fetch from API.
  static Future<void> initFor({
    required int surveiId,
    required String role,
  }) async {
    final userId = await JwtUtils.getUserId();
    if (userId == null) return;

    try {
      if (await _hasValidDataFor(
        userId: userId,
        surveiId: surveiId,
        role: role,
      )) {
        await _loadFromPrefsFor(userId: userId, surveiId: surveiId, role: role);

        if (_wilayahSubSLSIds.isEmpty || _wilayahPolygons.isEmpty) {
          throw Exception(
            'Invalid cached wilayah data (subSLS or polygons empty)',
          );
        }

        return;
      }
    } catch (_) {
      // fallthrough to refetch
    }

    // Refetch fresh
    await _fetchWilayah(userId: userId, surveiId: surveiId, role: role);
    await _fetchTargetPoints(surveiId: surveiId);
    await _saveToPrefsFor(userId: userId, surveiId: surveiId, role: role);
  }

  static Future<void> ensureInitialized() async {
    if (_wilayahSubSLSIds.isEmpty) {
      await initFor(surveiId: 2, role: 'petugas');
    }
  }

  static Future<void> _clearPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    debugPrint('[WilayahService] Cleared all wilayah prefs (prefs.clear)');
    _wilayahPolygons.clear();
    _wilayahSubSLSIds.clear();
    _wilayahData.clear();
    _targetPoints.clear();
  }

  static Future<void> clear() async {
    await _clearPrefs();
  }
}
