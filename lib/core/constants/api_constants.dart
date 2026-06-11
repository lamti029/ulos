import '../services/env_service.dart';

class ApiConstants {
  static String get baseUrl => EnvService.baseUrl;

  static const String login = '/api/auth/login';
  static const String register = '/api/auth/register';
  static const String altchaChallenge = '/api/auth/altcha-challenge';

  static const String kabupaten = '/api/master-wilayah/kabupaten';
  static const String kecamatan = '/api/master-wilayah/kecamatan';
  static const String desa = '/api/master-wilayah/desa';

  static const String titikSasaran = '/api/titik-sasaran';
  static const String wilayah = '/api/wilayah';
  static const String locationBatch = '/api/locations/batch';
}
