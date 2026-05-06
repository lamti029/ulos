import 'dart:convert';
import '../services/dio_client.dart';

class JwtUtils {
  static Map<String, dynamic>? _decodePayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      // Base64Url decode payload
      String payload = parts[1];
      // Pad with '=' to make length multiple of 4
      final padding = 4 - payload.length % 4;
      if (padding != 4) {
        payload += '=' * padding;
      }
      final decoded = utf8.decode(base64Url.decode(payload));
      return jsonDecode(decoded) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  static Future<int?> getUserId() async {
    final token = await DioClient().getToken();
    if (token == null || token.isEmpty) return null;
    final payload = _decodePayload(token);
    if (payload == null) return null;
    final userId = payload['user_id'];
    if (userId is int) return userId;
    if (userId is double) return userId.toInt();
    if (userId is String) return int.tryParse(userId);
    return null;
  }

  static Future<String?> getUserName() async {
    final token = await DioClient().getToken();
    if (token == null || token.isEmpty) return null;
    final payload = _decodePayload(token);
    if (payload == null) return null;
    final name = payload['name'];
    if (name is String && name.isNotEmpty) return name;
    return null;
  }
}
