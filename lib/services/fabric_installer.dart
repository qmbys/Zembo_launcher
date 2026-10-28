import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

class FabricInstaller {
  static const String metaUrl = 'https://meta.fabricmc.net/v2';

  static Future<String?> getLatestLoaderVersion() async {
    final client = http.Client();
    try {
      final response = await client.get(
        Uri.parse('$metaUrl/versions/loader'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List && data.isNotEmpty) {
          return data[0]['version'];
        }
      }
    } catch (e) {
      print('[Fabric] Ошибка: $e');
    } finally {
      client.close();
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getFabricProfile(String minecraftVersion, String loaderVersion) async {
    final client = http.Client();
    try {
      final response = await client.get(
        Uri.parse('$metaUrl/versions/loader/$minecraftVersion/$loaderVersion/profile/json'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('[Fabric] Ошибка профиля: $e');
    } finally {
      client.close();
    }
    return null;
  }

  static Future<bool> installFabric({
    required String minecraftVersion,
    required String sharedFolder,
    required Function(String, double) onProgress,
  }) async {
    try {
      onProgress('Получение версии Fabric...', 0);
      final loaderVersion = await getLatestLoaderVersion();
      
      if (loaderVersion == null) {
        onProgress('Ошибка: не удалось получить версию Fabric', 0);
        return false;
      }

      onProgress('Скачивание профиля Fabric...', 0.1);
      final profile = await getFabricProfile(minecraftVersion, loaderVersion);
      
      if (profile == null) {
        onProgress('Ошибка: профиль Fabric не найден', 0);
        return false;
      }

      final versionsPath = path.join(sharedFolder, 'versions');
      final fabricVersionId = 'fabric-loader-$loaderVersion-$minecraftVersion';
      final fabricProfilePath = path.join(versionsPath, fabricVersionId, '$fabricVersionId.json');
      
      File(fabricProfilePath).parent.createSync(recursive: true);
      File(fabricProfilePath).writeAsStringSync(json.encode(profile));

      onProgress('Скачивание библиотек Fabric...', 0.2);
      final libraries = profile['libraries'] as List;
      final librariesPath = path.join(sharedFolder, 'libraries');
      
      final libTasks = <_FabricLibTask>[];
      for (final lib in libraries) {
        final libName = lib['name'] as String;
        final parts = libName.split(':');
        
        if (parts.length >= 3) {
          final group = parts[0].replaceAll('.', '/');
          final artifact = parts[1];
          final version = parts[2];
          final fileName = '$artifact-$version.jar';
          final libPath = path.join(librariesPath, group, artifact, version, fileName);
          
          if (!File(libPath).existsSync()) {
            final url = lib['url'] ?? 'https://maven.fabricmc.net/';
            final fullUrl = '$url$group/$artifact/$version/$fileName';
            libTasks.add(_FabricLibTask(fullUrl, libPath));
          }
        }
      }
      
      if (libTasks.isNotEmpty) {
        final client = http.Client();
        int completed = 0;
        
        await Future.wait(
          libTasks.map((task) async {
            try {
              final response = await client.get(Uri.parse(task.url)).timeout(
                const Duration(seconds: 30),
              );
              if (response.statusCode == 200) {
                File(task.path).parent.createSync(recursive: true);
                File(task.path).writeAsBytesSync(response.bodyBytes);
              }
            } catch (e) {
              print('[Fabric] Ошибка: $e');
            }
            completed++;
            onProgress(
              'Библиотеки Fabric: $completed/${libTasks.length}',
              0.2 + (0.75 * (completed / libTasks.length)),
            );
          }),
        );
        
        client.close();
      }

      // СИНХРОННАЯ ПРОВЕРКА FABRIC ПРОФИЛЯ
      print('[Fabric] Проверка профиля: $fabricProfilePath');
      final profileFile = File(fabricProfilePath);
      if (!profileFile.existsSync() || profileFile.lengthSync() < 100) {
        onProgress('Ошибка: Fabric профиль не создан', 0);
        return false;
      }

      onProgress('Fabric установлен!', 1.0);
      return true;
    } catch (e) {
      onProgress('Ошибка установки Fabric: $e', 0);
      return false;
    }
  }
}

class _FabricLibTask {
  final String url;
  final String path;
  _FabricLibTask(this.url, this.path);
}