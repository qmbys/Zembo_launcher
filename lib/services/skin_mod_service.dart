import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

/// Installs the client-side skin loader needed for offline-mode multiplayer.
/// authlib-injector alone cannot resolve offline UUIDs to Ely.by profiles.
class SkinModService {
  static const _userAgent = 'ZemboLauncher/1.0.0 (Ely.by skin support)';

  /// Добавляет Ely.by в список источников скинов CustomSkinLoader
  /// (<gameDir>/CustomSkinLoader/CustomSkinLoader.json), не трогая остальные настройки.
  static Future<void> ensureElyByInConfig(String gameDirectory, {void Function(String message)? onLog}) async {
    try {
      final file = File(path.join(gameDirectory, 'CustomSkinLoader', 'CustomSkinLoader.json'));
      const elyEntry = {'name': 'ElyBy', 'type': 'ElyByAPI', 'root': 'http://skinsystem.ely.by/'};

      Map<String, dynamic> config;
      if (await file.exists()) {
        config = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      } else {
        config = {
          'enable': true,
          'loadlist': [
            {'name': 'Mojang', 'type': 'MojangAPI'},
          ],
        };
      }

      final list = (config['loadlist'] as List<dynamic>? ?? <dynamic>[]).toList();
      final hasEly = list.any((e) => e is Map && (e['type']?.toString().toLowerCase() == 'elybyapi'));
      if (hasEly) return;

      list.add(elyEntry);
      config['loadlist'] = list;
      await file.parent.create(recursive: true);
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(config));
      onLog?.call('[Скины] Ely.by добавлен в список источников CustomSkinLoader.');
    } catch (error) {
      onLog?.call('[Скины] Не удалось настроить CustomSkinLoader: $error');
    }
  }

  static Future<String?> ensureCustomSkinLoader({
    required String gameDirectory,
    required String minecraftVersion,
    required String loader,
    void Function(String message)? onLog,
  }) async {
    void log(String message) => onLog?.call('[Скины] $message');

    final normalizedLoader = loader.trim().toLowerCase();
    if (!const {'forge', 'fabric', 'neoforge', 'quilt'}.contains(normalizedLoader)) {
      log('CustomSkinLoader можно установить только в сборку с Forge/Fabric/NeoForge/Quilt.');
      return null;
    }

    final modsDirectory = Directory(path.join(gameDirectory, 'mods'));
    await modsDirectory.create(recursive: true);

    // Do not download a second copy if the user already installed the mod.
    if (modsDirectory.existsSync()) {
      for (final entity in modsDirectory.listSync()) {
        if (entity is File &&
            path.basename(entity.path).toLowerCase().contains('customskinloader') &&
            entity.path.toLowerCase().endsWith('.jar')) {
          log('CustomSkinLoader уже установлен: ${path.basename(entity.path)}');
          return entity.path;
        }
      }
    }

    final uri = Uri.https(
      'api.modrinth.com',
      '/v2/project/customskinloader/version',
      {
        'game_versions': jsonEncode([minecraftVersion]),
        'loaders': jsonEncode([normalizedLoader]),
      },
    );

    try {
      log('Ищу CustomSkinLoader для Minecraft $minecraftVersion ($normalizedLoader)...');
      final response = await http.get(uri, headers: const {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        log('Modrinth вернул HTTP ${response.statusCode}; мод автоматически не установлен.');
        return null;
      }

      final versions = jsonDecode(response.body) as List<dynamic>;
      for (final item in versions) {
        if (item is! Map<String, dynamic>) continue;
        final files = item['files'] as List<dynamic>? ?? const [];
        final file = files.whereType<Map<String, dynamic>>().firstWhere(
          (candidate) =>
              (candidate['primary'] == true || files.length == 1) &&
              (candidate['filename']?.toString().toLowerCase().endsWith('.jar') ?? false) &&
              (candidate['url']?.toString().startsWith('https://') ?? false),
          orElse: () => <String, dynamic>{},
        );
        if (file.isEmpty) continue;

        final filename = path.basename(file['filename'].toString());
        final target = File(path.join(modsDirectory.path, filename));
        final download = await http.get(Uri.parse(file['url'].toString()), headers: const {
          'User-Agent': _userAgent,
        }).timeout(const Duration(seconds: 60));
        if (download.statusCode != 200 || download.bodyBytes.isEmpty) {
          log('Не удалось скачать $filename (HTTP ${download.statusCode}).');
          return null;
        }
        await target.writeAsBytes(download.bodyBytes, flush: true);
        log('Установлен $filename. Мод загружает скины Ely.by по никам игроков на офлайн-серверах.');
        return target.path;
      }

      log('Для Minecraft $minecraftVersion и загрузчика $normalizedLoader не найден совместимый релиз.');
      return null;
    } catch (error) {
      log('Не удалось установить CustomSkinLoader: $error');
      return null;
    }
  }
}
