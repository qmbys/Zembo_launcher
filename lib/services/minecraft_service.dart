import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

class MinecraftService {
  static const String manifestUrl = 'https://launchermeta.mojang.com/mc/game/version_manifest.json';

  // Диагностика - проверка всех необходимых файлов
  static Future<Map<String, dynamic>> diagnose({
    required String javaPath,
    required String minecraftFolder,
    required String versionId,
  }) async {
    final result = <String, dynamic>{
      'javaExists': false,
      'minecraftFolderExists': false,
      'versionFolderExists': false,
      'versionJarExists': false,
      'librariesExist': false,
      'assetsExist': false,
      'errors': <String>[],
    };

    // Проверка Java
    final javaFile = File(javaPath);
    result['javaExists'] = await javaFile.exists();
    if (!result['javaExists']) {
      result['errors'].add('Java не найдена по пути: $javaPath');
    }

    // Проверка папки Minecraft
    final mcFolder = Directory(minecraftFolder);
    result['minecraftFolderExists'] = await mcFolder.exists();
    if (!result['minecraftFolderExists']) {
      result['errors'].add('Папка Minecraft не существует: $minecraftFolder');
    }

    // Проверка папки версии
    final versionFolder = Directory(path.join(minecraftFolder, 'versions', versionId));
    result['versionFolderExists'] = await versionFolder.exists();
    if (!result['versionFolderExists']) {
      result['errors'].add('Папка версии не найдена: ${versionFolder.path}');
    }

    // Проверка jar файла версии
    final versionJar = File(path.join(minecraftFolder, 'versions', versionId, '$versionId.jar'));
    result['versionJarExists'] = await versionJar.exists();
    if (!result['versionJarExists']) {
      result['errors'].add('Файл версии не найден: ${versionJar.path}\nНеобходимо скачать Minecraft $versionId');
    }

    // Проверка библиотек
    final librariesFolder = Directory(path.join(minecraftFolder, 'libraries'));
    result['librariesExist'] = await librariesFolder.exists();
    if (!result['librariesExist']) {
      result['errors'].add('Папка библиотек не найдена: ${librariesFolder.path}');
    }

    // Проверка assets
    final assetsFolder = Directory(path.join(minecraftFolder, 'assets'));
    result['assetsExist'] = await assetsFolder.exists();
    if (!result['assetsExist']) {
      result['errors'].add('Папка assets не найдена: ${assetsFolder.path}');
    }

    return result;
  }

  // Получить информацию о версии Minecraft
  static Future<Map<String, dynamic>?> getVersionInfo(String versionId) async {
    try {
      final manifestResponse = await http.get(Uri.parse(manifestUrl));
      if (manifestResponse.statusCode != 200) return null;

      final manifest = json.decode(manifestResponse.body);
      final versions = manifest['versions'] as List;
      final versionData = versions.firstWhere(
        (v) => v['id'] == versionId,
        orElse: () => null,
      );

      if (versionData == null) return null;

      final versionResponse = await http.get(Uri.parse(versionData['url']));
      if (versionResponse.statusCode != 200) return null;

      return json.decode(versionResponse.body);
    } catch (e) {
      print('Ошибка при получении информации о версии: $e');
      return null;
    }
  }

  // Скачать файл с прогрессом
  static Future<bool> downloadFile(String url, String savePath) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final file = File(savePath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(response.bodyBytes);
        return true;
      }
      return false;
    } catch (e) {
      print('Ошибка при скачивании: $e');
      return false;
    }
  }

  // Сформировать команду запуска Minecraft
  static List<String> buildLaunchCommand({
    required String javaPath,
    required String minecraftFolder,
    required String versionId,
    required String username,
    required int ramMb,
    required String loader,
  }) {
    final List<String> args = [];

    // JVM аргументы
    args.add(javaPath);
    args.add('-Xmx${ramMb}M');
    args.add('-Xms${ramMb}M');
    
    // Путь к библиотекам и версиям
    final librariesPath = path.join(minecraftFolder, 'libraries');
    final versionsPath = path.join(minecraftFolder, 'versions', versionId);
    final versionJar = path.join(versionsPath, '$versionId.jar');

    // Classpath
    args.add('-cp');
    args.add('$librariesPath/*;$versionJar');

    // Главный класс
    args.add('net.minecraft.client.main.Main');

    // Аргументы игры
    args.add('--username');
    args.add(username);
    args.add('--version');
    args.add(versionId);
    args.add('--gameDir');
    args.add(minecraftFolder);
    args.add('--assetsDir');
    args.add(path.join(minecraftFolder, 'assets'));
    args.add('--assetIndex');
    args.add('1.20');
    args.add('--uuid');
    args.add('00000000-0000-0000-0000-000000000000');
    args.add('--accessToken');
    args.add('0');
    args.add('--userType');
    args.add('msa');
    args.add('--versionType');
    args.add(loader);

    return args;
  }

  // Запустить Minecraft с полной диагностикой
  static Future<Map<String, dynamic>> launchMinecraft({
    required String javaPath,
    required String minecraftFolder,
    required String versionId,
    required String username,
    required int ramMb,
    required String loader,
  }) async {
    final result = <String, dynamic>{
      'success': false,
      'error': '',
      'logs': <String>[],
    };

    try {
      // Сначала запускаем диагностику
      final diagnosis = await diagnose(
        javaPath: javaPath,
        minecraftFolder: minecraftFolder,
        versionId: versionId,
      );

      if (diagnosis['errors'].isNotEmpty) {
        result['error'] = (diagnosis['errors'] as List).join('\n');
        return result;
      }

      // Формируем команду
      final args = buildLaunchCommand(
        javaPath: javaPath,
        minecraftFolder: minecraftFolder,
        versionId: versionId,
        username: username,
        ramMb: ramMb,
        loader: loader,
      );

      result['logs'].add('Запуск команды:');
      result['logs'].add('Java: ${args[0]}');
      result['logs'].add('RAM: ${args[1]} ${args[2]}');
      result['logs'].add('Версия: $versionId');
      result['logs'].add('Загрузчик: $loader');
      result['logs'].add('');

      // Запускаем процесс
      final process = await Process.start(
        args[0],
        args.sublist(1),
        workingDirectory: minecraftFolder,
        mode: ProcessStartMode.inheritStdio, // Наследуем stdout/stderr
      );

      result['success'] = true;
      result['logs'].add('Процесс запущен с PID: ${process.pid}');

      // Слушаем вывод процесса
      process.stdout.transform(utf8.decoder).listen((data) {
        result['logs'].add('[STDOUT] $data');
        print('[Minecraft STDOUT] $data');
      });

      process.stderr.transform(utf8.decoder).listen((data) {
        result['logs'].add('[STDERR] $data');
        print('[Minecraft STDERR] $data');
      });

      process.exitCode.then((code) {
        result['logs'].add('Процесс завершён с кодом: $code');
        print('[Minecraft] Процесс завершён с кодом: $code');
      });

    } catch (e) {
      result['error'] = 'Ошибка при запуске: $e';
      result['logs'].add('ERROR: $e');
    }

    return result;
  }
}