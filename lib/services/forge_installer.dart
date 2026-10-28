import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

class ForgeInstaller {
  static const String _mavenBase =
      'https://maven.minecraftforge.net/net/minecraftforge/forge';

  /// Приводит версии к Maven-формату: 1.20.1-47.4.9.
  /// Принимает также forge-1.20.1-47.4.9 и 1.20.1-forge-47.4.9.
  static String _getMavenVersion(String value) {
    var version = value.trim();
    if (version.startsWith('forge-')) {
      version = version.substring('forge-'.length);
    }

    final canonical = RegExp(
      r'^(\d+\.\d+(?:\.\d+)?)-forge-(.+)$',
    ).firstMatch(version);
    if (canonical != null) {
      return '${canonical.group(1)}-${canonical.group(2)}';
    }

    return version;
  }

  /// ID папки и JSON, создаваемые официальным установщиком Forge.
  static String _getForgeVersionId(String value) {
    final mavenVersion = _getMavenVersion(value);
    final match = RegExp(
      r'^(\d+\.\d+(?:\.\d+)?)-(.+)$',
    ).firstMatch(mavenVersion);

    if (match == null) {
      throw FormatException('Неверная версия Forge: $value');
    }
    return '${match.group(1)}-forge-${match.group(2)}';
  }

  static Future<List<String>> getAvailableForgeVersions(
    String minecraftVersion,
  ) async {
    final client = http.Client();
    try {
      final url = Uri.parse('$_mavenBase/maven-metadata.xml');
      final response = await client
          .get(url)
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        print('[Forge] Metadata HTTP ${response.statusCode}');
        return [];
      }

      // Regex не зависит от того, размещены ли XML-теги на отдельных строках.
      final versions = <String>[];
      final regex = RegExp(r'<version>\s*([^<]+?)\s*</version>');
      for (final match in regex.allMatches(response.body)) {
        final version = match.group(1)?.trim();
        if (version != null &&
            version.startsWith('$minecraftVersion-')) {
          versions.add(version);
        }
      }

      // Maven-версии нельзя надёжно сортировать обычным сравнением строк.
      versions.sort((a, b) => _compareVersions(b, a));
      return versions;
    } catch (e) {
      print('[Forge] Ошибка получения списка версий: $e');
      return [];
    } finally {
      client.close();
    }
  }

  static int _compareVersions(String a, String b) {
    final aa = a.split(RegExp(r'[.-]'));
    final bb = b.split(RegExp(r'[.-]'));
    final length = aa.length > bb.length ? aa.length : bb.length;
    for (var i = 0; i < length; i++) {
      final av = i < aa.length ? aa[i] : '0';
      final bv = i < bb.length ? bb[i] : '0';
      final an = int.tryParse(av);
      final bn = int.tryParse(bv);
      final comparison = an != null && bn != null
          ? an.compareTo(bn)
          : av.compareTo(bv);
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  static Future<String?> getLatestForgeVersion(
    String minecraftVersion,
  ) async {
    final versions = await getAvailableForgeVersions(minecraftVersion);
    return versions.isNotEmpty ? versions.first : null;
  }

  static Future<bool> downloadInstaller({
    required String forgeVersion,
    required String sharedFolder,
    required void Function(String status, double progress) onProgress,
  }) async {
    final client = http.Client();
    try {
      final mavenVersion = _getMavenVersion(forgeVersion);
      final installerDir = path.join(
        sharedFolder,
        'versions',
        'forge-$mavenVersion',
      );
      final installerPath = path.join(
        installerDir,
        'forge-$mavenVersion-installer.jar',
      );
      final installerFile = File(installerPath);

      if (await installerFile.exists() &&
          await installerFile.length() > 100000) {
        onProgress('Forge installer уже скачан', 1.0);
        return true;
      }

      onProgress('Скачивание Forge installer...', 0.0);
      final url = Uri.parse(
        '$_mavenBase/$mavenVersion/forge-$mavenVersion-installer.jar',
      );
      final response = await client
          .get(url)
          .timeout(const Duration(minutes: 3));

      if (response.statusCode != 200) {
        onProgress('Ошибка скачивания Forge: HTTP ${response.statusCode}', 0.0);
        print('[Forge] URL: $url');
        return false;
      }

      // HTML-страница ошибки иногда приходит с HTTP 200, поэтому проверяем размер.
      if (response.bodyBytes.length < 100000 ||
          response.bodyBytes[0] != 0x50 ||
          response.bodyBytes[1] != 0x4B) {
        onProgress('Сервер вернул повреждённый installer', 0.0);
        return false;
      }

      await installerFile.parent.create(recursive: true);
      await installerFile.writeAsBytes(response.bodyBytes, flush: true);
      onProgress('Forge installer скачан', 1.0);
      return true;
    } catch (e) {
      onProgress('Ошибка скачивания Forge: $e', 0.0);
      print('[Forge] Ошибка скачивания: $e');
      return false;
    } finally {
      client.close();
    }
  }

  static Future<bool> installForge({
    required String forgeVersion,
    required String sharedFolder,
    required String javaPath,
    required void Function(String status, double progress) onProgress,
  }) async {
    Process? process;
    try {
      final mavenVersion = _getMavenVersion(forgeVersion);
      final versionId = _getForgeVersionId(forgeVersion);
      final installerPath = path.join(
        sharedFolder,
        'versions',
        'forge-$mavenVersion',
        'forge-$mavenVersion-installer.jar',
      );
      final installerFile = File(installerPath);

      if (!await installerFile.exists() ||
          await installerFile.length() < 100000) {
        onProgress('Forge installer не найден или повреждён', 0.0);
        return false;
      }

      onProgress('Подготовка к установке Forge...', 0.1);
      await Directory(sharedFolder).create(recursive: true);

      final profilesFile = File(
        path.join(sharedFolder, 'launcher_profiles.json'),
      );
      if (!await profilesFile.exists()) {
        await profilesFile.writeAsString('{"profiles":{}}');
      }

      onProgress('Установка Forge $versionId...', 0.2);
      process = await Process.start(
        javaPath,
        [
          '-jar',
          installerFile.absolute.path,
          '--installClient',
          path.absolute(sharedFolder),
        ],
        workingDirectory: sharedFolder,
        runInShell: false,
      );

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      final stdoutFuture = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .forEach((data) {
        stdoutBuffer.write(data);
        print('[Forge] $data');
      });
      final stderrFuture = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .forEach((data) {
        stderrBuffer.write(data);
        print('[Forge STDERR] $data');
      });

      final exitCode = await process.exitCode.timeout(
        const Duration(minutes: 10),
        onTimeout: () {
          process?.kill();
          throw TimeoutException('Установка Forge превысила 10 минут');
        },
      );
      await Future.wait([stdoutFuture, stderrFuture]);

      if (exitCode != 0) {
        onProgress('Ошибка установки Forge: код $exitCode', 0.0);
        print('[Forge] STDOUT: $stdoutBuffer');
        print('[Forge] STDERR: $stderrBuffer');
        return false;
      }

      onProgress('Проверка файлов Forge...', 0.9);
      final versionJson = File(path.join(
        sharedFolder,
        'versions',
        versionId,
        '$versionId.json',
      ));

      if (!await versionJson.exists() || await versionJson.length() == 0) {
        onProgress('JSON версии Forge не найден: ${versionJson.path}', 0.0);
        print('[Forge] STDOUT: $stdoutBuffer');
        print('[Forge] STDERR: $stderrBuffer');
        return false;
      }

      try {
        final data = jsonDecode(await versionJson.readAsString())
            as Map<String, dynamic>;
        if (data['id'] == null || data['mainClass'] == null) {
          throw const FormatException('В JSON отсутствуют id или mainClass');
        }
      } catch (e) {
        onProgress('Некорректный JSON Forge: $e', 0.0);
        return false;
      }

      onProgress('Forge успешно установлен: $versionId', 1.0);
      return true;
    } catch (e) {
      onProgress('Ошибка установки Forge: $e', 0.0);
      print('[Forge] Критическая ошибка: $e');
      return false;
    }
  }

  static bool isForgeInstalled(String forgeVersion, String sharedFolder) {
    try {
      final versionId = _getForgeVersionId(forgeVersion);
      final versionJson = File(path.join(
        sharedFolder,
        'versions',
        versionId,
        '$versionId.json',
      ));
      if (!versionJson.existsSync() || versionJson.lengthSync() == 0) {
        return false;
      }
      final data = jsonDecode(versionJson.readAsStringSync())
          as Map<String, dynamic>;
      return data['id'] != null && data['mainClass'] != null;
    } catch (e) {
      print('[Forge] Ошибка проверки установки: $e');
      return false;
    }
  }
}
