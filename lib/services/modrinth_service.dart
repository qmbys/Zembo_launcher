import 'dart:convert';
import 'package:http/http.dart' as http;

class ModrinthMod {
  final String id;
  final String slug;
  final String name;
  final String description;
  final String iconUrl;
  final int downloads;
  final List<String> categories;
  final String dateModified;

  ModrinthMod({
    required this.id,
    required this.slug,
    required this.name,
    required this.description,
    required this.iconUrl,
    required this.downloads,
    required this.categories,
    required this.dateModified,
  });

  factory ModrinthMod.fromJson(Map<String, dynamic> json) {
    return ModrinthMod(
      id: (json['project_id'] ?? json['id'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
      name: (json['title'] ?? 'Без названия').toString(),
      description: (json['description'] ?? '').toString(),
      iconUrl: (json['icon_url'] ?? '').toString(),
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      categories: (json['categories'] as List? ?? const []).map((value) => value.toString()).toList(),
      dateModified: (json['date_modified'] ?? '').toString(),
    );
  }
}

class ModrinthService {
  static const String _host = 'api.modrinth.com';
  static const String _basePath = '/v2/search';

  static Future<List<ModrinthMod>> searchMods(
    String query, {
    String gameVersion = '',
    String loader = '',
  }) => _search(
        query,
        projectType: 'mod',
        gameVersion: gameVersion,
        loader: loader,
      );

  static Future<List<ModrinthMod>> searchResourcePacks(
    String query, {
    String gameVersion = '',
  }) => _search(query, projectType: 'resourcepack', gameVersion: gameVersion);

  static Future<List<ModrinthMod>> _search(
    String query, {
    required String projectType,
    String gameVersion = '',
    String loader = '',
  }) async {
    try {
      final facets = <List<String>>[
        ['project_type:$projectType'],
      ];
      if (gameVersion.trim().isNotEmpty) facets.add(['versions:${gameVersion.trim()}']);
      if (projectType == 'mod' && loader.trim().isNotEmpty) {
        final normalizedLoader = loader.trim().toLowerCase();
        if (normalizedLoader == 'fabric' || normalizedLoader == 'forge' || normalizedLoader == 'neoforge' || normalizedLoader == 'quilt') {
          facets.add(['categories:$normalizedLoader']);
        }
      }

      final uri = Uri.https(_host, _basePath, <String, String>{
        'query': query.trim(),
        'facets': jsonEncode(facets),
        'limit': '24',
        'index': 'downloads',
      });
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'ZemboLauncher/1.0.0 (launcher; modrinth integration)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final hits = data['hits'] as List? ?? const [];
      return hits
          .whereType<Map<String, dynamic>>()
          .map(ModrinthMod.fromJson)
          .toList(growable: false);
    } catch (error) {
      // The UI presents an empty-state message if the API is unavailable.
      print('Modrinth search failed: $error');
      return [];
    }
  }
}
