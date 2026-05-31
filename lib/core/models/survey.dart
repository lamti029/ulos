class SurveyModel {
  final int id;
  final String? nama;
  final String? title;
  final String? roleInSurvei;

  bool isTrackingActive;

  SurveyModel({
    required this.id,
    this.nama,
    this.title,
    this.roleInSurvei,
    this.isTrackingActive = false,
  });

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  factory SurveyModel.fromJson(Map<String, dynamic> json) {
    final id = _parseInt(json['id']) ?? _parseInt(json['survei_id']);
    if (id == null) {
      throw FormatException('Missing survey id in response');
    }

    return SurveyModel(
      id: id,
      nama: (json['nama'] ?? json['title'] ?? json['survei'] ?? json['name'])
          ?.toString(),
      title: json['title']?.toString() ?? json['nama']?.toString(),
      roleInSurvei: (json['role_in_survei'] ?? json['roleInSurvei'])
          ?.toString(),
      // Default false; tracking state is runtime-only (not coming from API).
      isTrackingActive: json['is_tracking_active'] == true,
    );
  }

  String get displayName => (title ?? nama ?? 'Survei $id').toString();
}
