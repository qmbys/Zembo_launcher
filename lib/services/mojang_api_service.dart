import 'dart:convert';
import 'package:http/http.dart' as http;

class MojangVersion {
  final String id;
  final String type; // 'release', 'snapshot', 'old_beta', 'old_alpha'
  final String releaseTime;

  MojangVersion({
    required this.id,
    required this.type,
    required this.releaseTime,
  });

  factory MojangVersion.fromJson(Map<String, dynamic> json) {
    return MojangVersion(
      id: json['id'],
      type: json['type'],
      releaseTime: json['releaseTime'],
    );
  }
}

class MojangApiService {
  // Официальный эндпоинт Mojang для получения списка всех версий
  static const String manifestUrl = 'https://launchermeta.mojang.com/mc/game/version_manifest.json';

  static Future<List<MojangVersion>> fetchVersions() async {
    try {
      final response = await http.get(Uri.parse(manifestUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List versions = data['versions'];
        return versions.map((v) => MojangVersion.fromJson(v)).toList();
      } else {
        throw Exception('Не удалось загрузить список версий: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка при загрузке версий: $e');
      return [];
    }
  }
}