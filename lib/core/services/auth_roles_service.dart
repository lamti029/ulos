import 'dio_client.dart';

class AuthRolesService {
  static Future<List<Map<String, dynamic>>> fetchRegisterRoles() async {
    final response = await DioClient().dio.get('/api/auth/register-roles');

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch register roles');
    }

    final List<dynamic> data = response.data['data'] ?? [];
    return data
        .map((e) => {'role_id': e['role_id'], 'name': e['name']})
        .toList();
  }
}
