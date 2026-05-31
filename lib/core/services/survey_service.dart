import '../services/dio_client.dart';
import '../models/survey.dart';
import '../utils/jwt_utils.dart';

class SurveyService {
  final DioClient _dioClient;

  SurveyService({DioClient? dioClient}) : _dioClient = dioClient ?? DioClient();

  /// Backward compatibility: gunakan endpoint survei berbasis user login.
  Future<List<SurveyModel>> fetchSurveys() async {
    return fetchSurveysForCurrentUser();
  }

  Future<List<SurveyModel>> fetchSurveysForCurrentUser() async {
    final userId = await JwtUtils.getUserId();
    if (userId == null) {
      throw Exception('User ID tidak ditemukan di token');
    }

    final res = await _dioClient.dio.get('/api/survei/user/$userId');

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Failed to fetch surveys: ${res.statusCode}');
    }

    final data = res.data;

    final List<dynamic> rawList;
    if (data is Map<String, dynamic> && data['data'] is List) {
      rawList = data['data'] as List<dynamic>;
    } else if (data is List) {
      rawList = data;
    } else {
      rawList = const [];
    }

    return rawList
        .whereType<Map<String, dynamic>>()
        .map(SurveyModel.fromJson)
        .toList();
  }
}
