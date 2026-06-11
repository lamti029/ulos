import 'dart:convert';
import 'package:latlong2/latlong.dart';

class GeoJsonUtils {
  static List<List<LatLng>> parseGeoJson(String geoJsonString) {
    final List<List<LatLng>> result = [];
    try {
      final Map<String, dynamic> geoJson =
          jsonDecode(geoJsonString) as Map<String, dynamic>;
      final String? type = geoJson['type'] as String?;

      if (type == 'Polygon') {
        final List<dynamic> coordinates =
            geoJson['coordinates'] as List<dynamic>;
        if (coordinates.isNotEmpty) {
          final ring = coordinates.first as List<dynamic>;
          result.add(_parseRing(ring));
        }
      } else if (type == 'MultiPolygon') {
        final List<dynamic> coordinates =
            geoJson['coordinates'] as List<dynamic>;
        for (final polygon in coordinates) {
          final List<dynamic> rings = polygon as List<dynamic>;
          if (rings.isNotEmpty) {
            final ring = rings.first as List<dynamic>;
            result.add(_parseRing(ring));
          }
        }
      }
    } catch (e) {}
    return result;
  }

  static List<LatLng> _parseRing(List<dynamic> ring) {
    return ring.map((coord) {
      final List<dynamic> c = coord as List<dynamic>;
      final double lng = (c[0] as num).toDouble();
      final double lat = (c[1] as num).toDouble();
      return LatLng(lat, lng);
    }).toList();
  }
}
