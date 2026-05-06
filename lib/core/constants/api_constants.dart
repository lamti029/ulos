import '../services/env_service.dart';

class ApiConstants {
  /// Runtime-configurable base URL loaded from env.json.
  static String get baseUrl => EnvService.baseUrl;

  static const String login = '/api/auth/login';
  static const String register = '/api/auth/register';
  static const String altchaChallenge = '/api/auth/altcha-challenge';

  // Master Wilayah (public — available without auth for registration)
  static const String kabupaten = '/api/master-wilayah/kabupaten';
  static const String kecamatan = '/api/master-wilayah/kecamatan';
  static const String desa = '/api/master-wilayah/desa';

  static const String titikSasaran = '/api/titik-sasaran';
  static const String wilayah = '/api/wilayah';
  static const String locationBatch = '/api/locations/batch';
}
