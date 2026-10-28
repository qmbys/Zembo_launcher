import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart'; // Добавлено для проверки SHA-1

class MinecraftDownloader {
  static const String manifestUrl = 'https://launchermeta.mojang.com/mc/game/version_manifest.json';
  static const String resourcesUrl = 'https://resources.download.minecraft.net';
  
  static bool _isCancelled = false;
  static bool get isCancelled => _isCancelled;

  static void cancelDownload() => _isCancelled = true;
  static void resetCancel() => _isCancelled = false;

  // Базовая проверка для не-ассет файлов (JAR, JSON)
  static bool isFileReadySync(String filePath) {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return false;
      if (file.lengthSync() == 0) return false;
      
      if (filePath.endsWith('.jar')) {
        final raf = file.openSync(mode: FileMode.read);
        final Uint8List header = raf.readSync(4);
        raf.closeSync();
        if (header == null || header.length < 4) return false;
        if (header[0] != 0x50 || header[1] != 0x4B) return false;
        return true;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  // Проверка SHA-1 хэша файла
  static Future<bool> _verifySha1(String filePath, String expectedHash) async {
    final file = File(filePath);
    if (!await file.exists()) return false;
    
    try {
      final digest = await sha1.bind(file.openRead()).first;
      return digest.toString().toLowerCase() == expectedHash.toLowerCase();
    } catch (e) {
      return false;
    }
  }

  // ИСПРАВЛЕНИЕ 1: Правильный пул воркеров, гарантирующий обработку всей очереди
  static Future<void> downloadInParallel<T>(
    List<T> items,
    Future<bool> Function(T item) downloadFn, {
    required int maxConcurrent,
    Function(int completed, int total)? onProgress,
    required String taskName,
  }) async {
    if (items.isEmpty) {
      print('✅ [$taskName] Нечего загружать (0 элементов)');
      return;
    }

    int completed = 0;
    int failed = 0;
    final queue = Queue<T>.from(items);
    final total = items.length;

    Future<void> worker() async {
      while (!_isCancelled && queue.isNotEmpty) {
        final item = queue.removeFirst();
        try {
          final success = await downloadFn(item);
          completed++;
          if (!success) {
            failed++;
            print('⚠️ [$taskName] Не удалось скачать элемент $completed/$total');
          }
        } catch (e) {
          completed++;
          failed++;
          print('❌ [$taskName] Ошибка: $e');
        }
        onProgress?.call(completed, total);
      }
    }

    final workerCount = maxConcurrent < total ? maxConcurrent : total;
    await Future.wait(List.generate(workerCount, (_) => worker()));

    // ИСПРАВЛЕНИЕ 5: Остановка процесса и возврат ошибки, если есть неудачные загрузки
    if (_isCancelled) {
      print('⏹️ [$taskName] Загрузка отменена');
      throw Exception('Загрузка отменена');
    } else if (failed > 0) {
      print('❌ [$taskName] Завершено с ошибками: ${total - failed}/$total успешно, ошибок: $failed');
      throw Exception('Не удалось скачать $failed файлов в задаче: $taskName');
    } else {
      print('✅ [$taskName] Успешно загружено: $completed/$total');
    }
  }

  static Future<List<Map<String, dynamic>>> getVersions() async {
    final client = http.Client();
    try {
      final response = await client.get(Uri.parse(manifestUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(json.decode(response.body)['versions']);
      }
      throw Exception('HTTP ${response.statusCode}');
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>?> getVersionDetails(String versionId) async {
    final client = http.Client();
    try {
      final versions = await getVersions();
      final version = versions.firstWhere((v) => v['id'] == versionId, orElse: () => throw Exception('Не найдена'));
      final response = await client.get(Uri.parse(version['url'])).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return json.decode(response.body);
      return null;
    } finally {
      client.close();
    }
  }

  // ИСПРАВЛЕНИЕ 4: Проверка содержимого через ожидаемый хэш
  static Future<bool> downloadFileWithRetry(
    String url, 
    String savePath, {
    int maxRetries = 3,
    String? expectedHash,
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      if (_isCancelled) return false;

      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(url));
        final streamedResponse = await client.send(request).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException('Превышено время ожидания (возможна блокировка)'),
        );
        
        if (streamedResponse.statusCode != 200) {
          if (attempt == maxRetries) print('  -> HTTP ${streamedResponse.statusCode} для ${path.basename(savePath)}');
          continue;
        }
        
        final file = File(savePath);
        await file.parent.create(recursive: true);
        
        final sink = file.openWrite();
        await streamedResponse.stream.forEach((chunk) {
          if (_isCancelled) throw Exception('Отменено');
          sink.add(chunk);
        });
        
        await sink.flush();
        await sink.close();
        
        // Проверка целостности
        bool isValid = false;
        if (expectedHash != null) {
          isValid = await _verifySha1(savePath, expectedHash);
        } else {
          isValid = isFileReadySync(savePath);
        }

        if (isValid) {
          return true;
        } else {
          print('  -> 🚫 Файл поврежден или не прошел проверку, попытка $attempt/$maxRetries: ${path.basename(savePath)}');
        }
      } catch (e) {
        if (attempt == maxRetries) {
          print('  -> ❌ ОШИБКА ЗАГРУЗКИ ${path.basename(savePath)}: $e');
        }
      } finally {
        client.close();
      }
      
      await Future.delayed(Duration(milliseconds: 300 * attempt));
      
      final fileToDelete = File(savePath);
      if (await fileToDelete.exists()) {
        try { await fileToDelete.delete(); } catch (_) {}
      }
    }
    return false;
  }

  static Future<bool> downloadVersion({
    required String versionId,
    required String sharedFolder,
    required Function(String, double) onProgress,
  }) async {
    _isCancelled = false;
    try {
      onProgress('Получение информации...', 0);
      final versionDetails = await getVersionDetails(versionId);
      if (versionDetails == null) { 
        onProgress('Ошибка: версия не найдена', 0); 
        return false; 
      }

      final versionsPath = path.join(sharedFolder, 'versions', versionId);
      final versionJsonPath = path.join(versionsPath, '$versionId.json');
      final versionJarPath = path.join(versionsPath, '$versionId.jar');

      onProgress('Скачивание основных файлов...', 0.05);
      final versions = await getVersions();
      final version = versions.firstWhere((v) => v['id'] == versionId);
      
      await Future.wait([
        downloadFileWithRetry(version['url'], versionJsonPath),
        if (versionDetails['downloads']?['client'] != null)
          downloadFileWithRetry(versionDetails['downloads']['client']['url'], versionJarPath),
      ]);

      if (!isFileReadySync(versionJarPath)) { 
        onProgress('Ошибка: jar не готов', 0); 
        return false; 
      }
      if (_isCancelled) return false;

      onProgress('Скачивание библиотек...', 0.1);
      final libraries = versionDetails['libraries'] as List;
      final librariesPath = path.join(sharedFolder, 'libraries');
      final libTasks = <_LibTask>[];
      
      for (final lib in libraries) {
        final parts = (lib['name'] as String).split(':');
        if (parts.length >= 3) {
          final group = parts[0].replaceAll('.', '/');
          final artifact = parts[1];
          final version = parts[2];
          final classifier = parts.length > 3 ? parts[3] : null;
          final fileName = classifier != null ? '$artifact-$version-$classifier.jar' : '$artifact-$version.jar';
          final libPath = path.join(librariesPath, group, artifact, version, fileName);
          
          final libFile = File(libPath);
          if (!libFile.existsSync() || libFile.lengthSync() == 0) {
            final artifactData = lib['downloads']?['artifact'];
            if (artifactData != null) libTasks.add(_LibTask(artifactData['url'], libPath));
          }
        }
      }
      
      if (libTasks.isNotEmpty) {
        await downloadInParallel(
          libTasks, 
          (task) => downloadFileWithRetry(task.url, task.path), 
          maxConcurrent: 5, 
          taskName: 'Библиотеки', 
          onProgress: (c, t) => onProgress('Библиотеки: $c/$t', 0.1 + (0.4 * (c / t)))
        );
      }

      if (_isCancelled) return false;

      onProgress('Скачивание assets...', 0.5);
      final assetIndex = versionDetails['assetIndex'];
      if (assetIndex != null) {
        final assetIndexId = assetIndex['id'];
        final assetsIndexPath = path.join(sharedFolder, 'assets', 'indexes', '$assetIndexId.json');
        
        // ИСПРАВЛЕНИЕ 3: Проверяем результат загрузки asset index
        final indexDownloaded = await downloadFileWithRetry(assetIndex['url'], assetsIndexPath);
        if (!indexDownloaded) {
          throw Exception('Не удалось скачать asset index: $assetIndexId');
        }

        final assetData = json.decode(await File(assetsIndexPath).readAsString());
        final objects = assetData['objects'] as Map;
        final assetsPath = path.join(sharedFolder, 'assets', 'objects');
        final assetTasks = <_AssetTask>[];
        
        for (final obj in objects.entries) {
          final hash = obj.value['hash'] as String;
          final assetPath = path.join(assetsPath, hash.substring(0, 2), hash);
          final assetFile = File(assetPath);
          
          // ИСПРАВЛЕНИЕ 2: Проверяем SHA-1 перед добавлением в очередь
          bool needsDownload = true;
          if (assetFile.existsSync() && assetFile.lengthSync() > 0) {
            needsDownload = !await _verifySha1(assetPath, hash);
          }
          
          if (needsDownload) {
            assetTasks.add(_AssetTask(
              '$resourcesUrl/${hash.substring(0, 2)}/$hash',
              assetPath,
              hash,
            ));
          }
        }
        
        if (assetTasks.isNotEmpty) {
          print('[Downloader] 📦 Начинаю загрузку ${assetTasks.length} ассетов с проверкой SHA-1...');
          await downloadInParallel(
            assetTasks, 
            (task) => downloadFileWithRetry(task.url, task.path, expectedHash: task.expectedHash),
            maxConcurrent: 10, 
            taskName: 'Ассеты', 
            onProgress: (c, t) => onProgress('Assets: $c/$t', 0.5 + (0.45 * (c / t)))
          );
        } else {
          print('[Downloader] ✅ Все ассеты уже присутствуют и прошли проверку SHA-1.');
        }
      }

      onProgress('Готово!', 1.0);
      return true;
    } catch (e) {
      onProgress('Критическая ошибка: $e', 0);
      print('[Downloader] Критическая ошибка: $e');
      return false;
    }
  }
}

class _LibTask { 
  final String url; 
  final String path; 
  _LibTask(this.url, this.path); 
}

// ИСПРАВЛЕНИЕ 4: Добавлено поле expectedHash
class _AssetTask { 
  final String url; 
  final String path; 
  final String expectedHash; 
  _AssetTask(this.url, this.path, this.expectedHash); 
}