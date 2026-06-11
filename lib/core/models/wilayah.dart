import 'package:flutter_map/flutter_map.dart';
import '../../../core/utils/geojson_utils.dart';
import '../../../core/constants/app_colors.dart';

class WilayahData {
  final List<dynamic> rawData;
  final List<Polygon> polygons;
  final List<String> subSLSIds;

  WilayahData({
    required this.rawData,
    required this.polygons,
    required this.subSLSIds,
  });

  /// Create from API response data
  factory WilayahData.fromApi(List<dynamic> data) {
    final List<Polygon> polygons = [];
    final List<String> subSLSIds = [];

    for (final item in data) {
      final geoJsonStr = item['geojson'] as String?;
      if (geoJsonStr != null && geoJsonStr.isNotEmpty) {
        final rings = GeoJsonUtils.parseGeoJson(geoJsonStr);
        for (final ring in rings) {
          if (ring.length >= 3) {
            polygons.add(
              Polygon(
                points: ring,
                color: AppColors.primary.withAlpha(51),
                borderColor: AppColors.primary,
                borderStrokeWidth: 2,
              ),
            );
          }
        }
      }
      final idSubsls = item['id_subsls']?.toString() ?? '';
      if (idSubsls.isNotEmpty) {
        subSLSIds.add(idSubsls);
      }
    }

    return WilayahData(rawData: data, polygons: polygons, subSLSIds: subSLSIds);
  }

  /// Convert to JSON for SharedPreferences
  Map<String, dynamic> toJson() => {'rawData': rawData};

  /// Create from JSON
  factory WilayahData.fromJson(Map<String, dynamic> json) {
    final rawData = json['rawData'] as List<dynamic>;
    // Re-parse polygons/subSLS on load (since need GeoJsonUtils)
    return WilayahData.fromApi(rawData);
  }
}
