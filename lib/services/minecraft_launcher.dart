import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

class MinecraftLauncher {
  // Принимает оба формата: forge-1.20.1-47.4.9 и 1.20.1-forge-47.4.9.
  static Future<int?> _javaMajorVersion(String javaPath) async {
    try {
      final result = await Process.run(javaPath, ['-version']).timeout(const Duration(seconds: 8));
      final output = '${result.stdout}\n${result.stderr}';
      final match = RegExp(r'(?:version\s+"?|openjdk\s+)(\d+)').firstMatch(output);
      if (match == null) return null;
      final parsed = int.tryParse(match.group(1)!);
      if (parsed == 1) {
        final legacy = RegExp(r'version\s+"1\.(\d+)').firstMatch(output);
        return legacy == null ? parsed : int.tryParse(legacy.group(1)!);
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }

  static Future<String> _javaForVersion({
    required String configuredPath,
    required String sharedFolder,
    required int requiredMajor,
    required void Function(String) log,
  }) async {
    final configuredMajor = await _javaMajorVersion(configuredPath);
    if (configuredMajor != null && configuredMajor >= requiredMajor) {
      log('Java $configuredMajor подходит для этой версии Minecraft.');
      return configuredPath;
    }

    final runtimeRoot = Directory(path.join(sharedFolder, 'runtimes', 'java-$requiredMajor'));
    final executableName = Platform.isWindows ? 'java.exe' : 'java';
    final bundledJava = path.join(runtimeRoot.path, 'bin', executableName);
    final bundledMajor = await _javaMajorVersion(bundledJava);
    if (bundledMajor != null && bundledMajor >= requiredMajor) {
      log('Используется встроенная Java $bundledMajor: $bundledJava');
      return bundledJava;
    }

    if (!Platform.isWindows) {
      throw Exception('Для этой сборки нужна Java $requiredMajor+. Установленная Java ${configuredMajor ?? 'не определена'}; автоматическая установка пока поддерживается только на Windows x64. Укажи путь к Java $requiredMajor в настройках.');
    }

    log('Для этой сборки нужна Java $requiredMajor+, установлена Java ${configuredMajor ?? 'не определена'}. Загружаю совместимую Java…');
    final url = Uri.parse('https://api.adoptium.net/v3/binary/latest/$requiredMajor/ga/windows/x64/jre/hotspot/normal/eclipse');
    final tempZip = File(path.join(sharedFolder, 'runtimes', 'java-$requiredMajor.zip'));
    await tempZip.parent.create(recursive: true);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 25);
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.userAgentHeader, 'ZemboLauncher/1.0');
      final response = await request.close().timeout(const Duration(minutes: 3));
      if (response.statusCode != HttpStatus.ok) {
        throw Exception('Не удалось скачать Java $requiredMajor (HTTP ${response.statusCode}).');
      }
      final sink = tempZip.openWrite();
      await response.pipe(sink).timeout(const Duration(minutes: 5));
    } finally {
      client.close(force: true);
    }

    log('Распаковываю Java $requiredMajor…');
    final bytes = await tempZip.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final staging = Directory('${runtimeRoot.path}.installing');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        final archivePath = path.posix.normalize(entry.name.replaceAll('\\', '/'));
        final segments = archivePath.split('/');
        if (segments.length < 2 || segments.contains('..')) continue;
        final relative = segments.skip(1).join(path.separator);
        if (relative.isEmpty) continue;
        final output = File(path.join(staging.path, relative));
        await output.parent.create(recursive: true);
        await output.writeAsBytes(entry.content as List<int>, flush: false);
      }
      final stagedJava = path.join(staging.path, 'bin', executableName);
      final downloadedMajor = await _javaMajorVersion(stagedJava);
      if (downloadedMajor == null || downloadedMajor < requiredMajor) {
        throw Exception('Скачанная Java не прошла проверку версии.');
      }
      if (await runtimeRoot.exists()) await runtimeRoot.delete(recursive: true);
      await staging.rename(runtimeRoot.path);
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    } finally {
      if (await tempZip.exists()) await tempZip.delete();
    }
    log('Java $requiredMajor установлена и готова к запуску.');
    return bundledJava;
  }

  static String _normalizeVersionId(String value, String loader) {
    if (loader.toLowerCase() != 'forge') return value;
    if (value.startsWith('forge-')) {
      final mavenVersion = value.substring('forge-'.length);
      final match = RegExp(r'^(\d+\.\d+(?:\.\d+)?)-(.+)$').firstMatch(mavenVersion);
      if (match != null) {
        return '${match.group(1)}-forge-${match.group(2)}';
      }
    }
    return value;
  }

  static Process? _currentProcess;
  static bool _isStoppedByUser = false;
  static String _launchAuthUuid = '00000000000000000000000000000000';
  static String _launchAccessToken = '0';
  static String _launchUserType = 'msa';

  static bool evaluateRules(List<dynamic>? rules) {
    if (rules == null || rules.isEmpty) return true;
    
    bool isAllowed = false;
    for (var rule in rules) {
      if (rule is! Map) continue;
      
      String action = rule['action'] ?? 'allow';
      Map? osRule = rule['os'];
      bool osMatches = true;

      if (osRule != null) {
        String? osName = osRule['name'];
        if (osName != null) {
          final osNameLower = osName.toLowerCase();
          if (Platform.isWindows && !osNameLower.contains('windows')) osMatches = false;
          if (Platform.isMacOS && !osNameLower.contains('osx') && !osNameLower.contains('macos')) osMatches = false;
          if (Platform.isLinux && !osNameLower.contains('linux')) osMatches = false;
        }
      }

      if (osMatches) {
        if (action == 'allow') {
          isAllowed = true;
        } else if (action == 'disallow') {
          isAllowed = false; // Не делаем return false, чтобы последующие правила могли это перезаписать
        }
      }
    }
    return isAllowed;
  }

  static String replaceVariables(String arg, {
    required String nativesPath,
    required String librariesPath,
    required String versionId,
    required String instanceFolder,
    required String assetsRoot,
    required String assetIndexName,
    required String username,
    required String loader,
    String classpath = '',
    String? authUuid,
    String? accessToken,
    String? userType,
  }) {
    return arg
        .replaceAll('\${natives_directory}', nativesPath)
        .replaceAll('\${library_directory}', librariesPath)
        .replaceAll('\${version_name}', versionId)
        .replaceAll('\${game_directory}', instanceFolder)
        .replaceAll('\${assets_root}', assetsRoot)
        .replaceAll('\${assets_index_name}', assetIndexName)
        .replaceAll('\${auth_player_name}', username)
        .replaceAll('\${auth_uuid}', authUuid ?? _launchAuthUuid)
        .replaceAll('\${auth_access_token}', accessToken ?? _launchAccessToken)
        .replaceAll('\${user_type}', userType ?? _launchUserType)
        .replaceAll('\${version_type}', loader)
        .replaceAll('\${launcher_name}', 'ZemboLauncher')
        .replaceAll('\${launcher_version}', '1.0')
        .replaceAll('\${classpath_separator}', Platform.isWindows ? ';' : ':')
        .replaceAll('\${classpath}', classpath)
        .replaceAll('\${game_assets}', path.join(assetsRoot, 'virtual', 'legacy'))
        .replaceAll('\${resolution_width}', '1920')
        .replaceAll('\${resolution_height}', '1080');
  }

  static void stop() {
    if (_currentProcess != null) {
      print('[Launcher] Принудительное завершение процесса Minecraft...');
      _isStoppedByUser = true;
      try {
        _currentProcess!.kill();
      } catch (e) {
        print('[Launcher] Ошибка при завершении процесса: $e');
      }
      _currentProcess = null;
    }
  }

  static bool get isStoppedByUser => _isStoppedByUser;

  /// Ищет в latest.log сообщения authlib-injector, чтобы понять, подключился ли агент
  /// и к какому серверу он перенаправил запросы скинов.
  static Future<void> _logAuthlibInjectorStatus(File logFile, void Function(String) log) async {
    try {
      if (!await logFile.exists()) return;
      final lines = await logFile.readAsLines();
      final injectorLines = lines.where((l) => l.toLowerCase().contains('authlib-injector')).toList();
      if (injectorLines.isEmpty) {
        log('⚠️ Ely.by: в логе игры нет сообщений authlib-injector — агент, скорее всего, не загрузился.');
        return;
      }
      log('Ely.by: authlib-injector активен. Сообщения агента (${injectorLines.length}):');
      for (final line in injectorLines.take(6)) {
        log('   $line');
      }
      final problems = lines.where((l) {
        final lower = l.toLowerCase();
        return lower.contains('skin') && (lower.contains('exception') || lower.contains('failed') || lower.contains('unable'));
      }).take(4);
      for (final line in problems) {
        log('⚠️ Ely.by (скины): $line');
      }
    } catch (_) {}
  }

  static Future<void> _logGuardReport(String instanceFolder, void Function(String) log) async {
    try {
      final file = File(path.join(instanceFolder, 'zembo_guard_report.json'));
      if (!await file.exists()) return;
      final mods = (jsonDecode(await file.readAsString()) as Map<String, dynamic>)['mods'] as Map<String, dynamic>? ?? {};
      for (final entry in mods.entries) {
        final m = entry.value as Map<String, dynamic>;
        log('🛡 ${entry.key}: заблокировано — файлы: ${m['create']}, чтение: ${m['read']}, окна/программы: ${m['windows']}');
      }
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> launch({
    required String javaPath,
    required String sharedFolder,
    required String instanceFolder,
    required String versionId,
    required String username,
    required int ramMb,
    required String loader,
    String? accessToken,
    String? authUuid,
    String? authlibInjectorPath,
    String? guardAgentJarPath,
    String? guardConfigPath,
    Future<void> Function()? onProcessStarted,
  }) async {
    final result = <String, dynamic>{
      'success': false,
      'error': '',
      'logs': <String>[],
    };

    void log(String msg) {
      print('[Launcher] $msg');
      result['logs'].add(msg);
    }

    try {
      _isStoppedByUser = false;
      _launchAuthUuid = (authUuid ?? '00000000000000000000000000000000').replaceAll('-', '');
      _launchAccessToken = accessToken ?? '0';
      // Для Yggdrasil-совместимых аккаунтов (Ely.by) используется тип 'mojang'.
      _launchUserType = accessToken == null ? 'msa' : 'mojang';
      versionId = _normalizeVersionId(versionId, loader);
      log('Используется ID версии: $versionId');
      await Directory(instanceFolder).create(recursive: true);

      final versionFolder = Directory(path.join(sharedFolder, 'versions', versionId));
      if (!versionFolder.existsSync()) {
        result['error'] = 'Папка версии не найдена: ${versionFolder.path}';
        return result;
      }

      final versionJson = File(path.join(versionFolder.path, '$versionId.json'));
      if (!versionJson.existsSync()) {
        result['error'] = 'version.json не найден: ${versionJson.path}';
        return result;
      }

      final versionData = json.decode(versionJson.readAsStringSync());
      Map<String, dynamic> finalVersionData;

      if (versionData['inheritsFrom'] != null) {
        final parentVersionId = versionData['inheritsFrom'];
        log('Наследует от: $parentVersionId');
        
        final parentFolder = Directory(path.join(sharedFolder, 'versions', parentVersionId));
        final parentJson = File(path.join(parentFolder.path, '$parentVersionId.json'));
        
        if (parentJson.existsSync()) {
          final parentData = json.decode(parentJson.readAsStringSync());
          finalVersionData = Map<String, dynamic>.from(parentData);
          finalVersionData.addAll(versionData);
          
          final parentLibs = (parentData['libraries'] as List? ?? []).cast<Map>();
          final childLibs = (versionData['libraries'] as List? ?? []).cast<Map>();
          final Map<String, Map> uniqueLibs = {};
          
          for (var lib in parentLibs) {
            if (lib['name'] != null) uniqueLibs[lib['name']] = lib;
          }
          for (var lib in childLibs) {
            if (lib['name'] != null) uniqueLibs[lib['name']] = lib;
          }
          finalVersionData['libraries'] = uniqueLibs.values.toList();

          if (versionData.containsKey('arguments') && parentData.containsKey('arguments')) {
            final childArgs = versionData['arguments'] as Map;
            final parentArgs = parentData['arguments'] as Map;
            final mergedArgs = Map<String, dynamic>.from(parentArgs);
            
            for (var key in childArgs.keys) {
              if (childArgs[key] is List && parentArgs[key] is List) {
                mergedArgs[key] = [...(parentArgs[key] as List), ...(childArgs[key] as List)];
              } else {
                mergedArgs[key] = childArgs[key];
              }
            }
            finalVersionData['arguments'] = mergedArgs;
          }
        } else {
          result['error'] = 'Родительская версия не найдена: $parentVersionId';
          return result;
        }
      } else {
        finalVersionData = versionData;
      }

      final javaVersionData = finalVersionData['javaVersion'];
      var requiredJavaMajor = javaVersionData is Map
          ? (javaVersionData['majorVersion'] as num?)?.toInt()
          : null;
      // Some third-party loader manifests omit javaVersion. Fall back to the
      // Minecraft version convention so a missing/old Java can still be resolved.
      if (requiredJavaMajor == null) {
        final manifestId = '${finalVersionData['inheritsFrom'] ?? versionId}';
        final match = RegExp(r'^(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(manifestId)
            ?? RegExp(r'^(\d+)\.(\d+)(?:\.(\d+))?').firstMatch('${finalVersionData['id'] ?? ''}');
        if (match != null) {
          final major = int.tryParse(match.group(1)!);
          final minor = int.tryParse(match.group(2)!);
          if (major != null && minor != null) {
            if (major >= 26) requiredJavaMajor = 25;
            else if (major == 1 && minor >= 20) {
              final patch = int.tryParse(match.group(3) ?? '0') ?? 0;
              requiredJavaMajor = minor > 20 || patch >= 5 ? 21 : 17;
            } else if (major == 1 && minor >= 18) requiredJavaMajor = 17;
            else if (major == 1 && minor == 17) requiredJavaMajor = 16;
            else if (major == 1 && minor >= 12) requiredJavaMajor = 8;
          }
        }
      }
      if (requiredJavaMajor != null) {
        javaPath = await _javaForVersion(
          configuredPath: javaPath,
          sharedFolder: sharedFolder,
          requiredMajor: requiredJavaMajor,
          log: log,
        );
      }

      final classpath = <String>[];
      final libraries = finalVersionData['libraries'] as List? ?? [];
      final librariesPath = path.join(sharedFolder, 'libraries');
      
      log('📦 Всего библиотек в JSON: ${libraries.length}');
      
      for (final lib in libraries) {
        if (lib is! Map) continue;
        
        final libName = lib['name'] as String? ?? 'unknown';
        if (!evaluateRules(lib['rules'])) {
          log('⏭️ Пропущена библиотека (правила OS): $libName');
          continue;
        }

        String? libPathStr;
        final downloads = lib['downloads'];
        if (downloads != null && downloads['artifact'] != null) {
          final artifact = downloads['artifact'];
          if (artifact is Map && artifact['path'] is String) {
            libPathStr = path.join(librariesPath, artifact['path']);
          }
        }

        if (libPathStr == null) {
          final parts = libName.split(':');
          if (parts.length >= 3) {
            final group = parts[0].replaceAll('.', '/');
            final artifact = parts[1];
            final version = parts[2];
            final classifier = parts.length > 3 ? parts[3] : null;
            final fileName = classifier != null ? '$artifact-$version-$classifier.jar' : '$artifact-$version.jar';
            libPathStr = path.join(librariesPath, group, artifact, version, fileName);
          }
        }

        if (libPathStr != null) {
          if (!File(libPathStr).existsSync()) {
            log('⚠️ Библиотека отсутствует на диске: $libPathStr');
          }
          classpath.add(libPathStr);
        }
      }

      String clientJarPath;
      if (versionData['inheritsFrom'] != null) {
        final parentVersionId = versionData['inheritsFrom'];
        clientJarPath = path.join(sharedFolder, 'versions', parentVersionId, '$parentVersionId.jar');
      } else {
        clientJarPath = path.join(versionFolder.path, '$versionId.jar');
      }
      
      if (!File(clientJarPath).existsSync()) {
        result['error'] = 'Клиентский JAR файл не найден: $clientJarPath';
        return result;
      }
      classpath.add(clientJarPath);

      final mainClass = finalVersionData['mainClass'] as String?;
      if (mainClass == null || mainClass.isEmpty) {
        log('❌ КРИТИЧЕСКАЯ ОШИБКА: mainClass не указан в version.json');
        result['error'] = 'mainClass не указан в version.json';
        return result;
      }

      // 🔥 УЛУЧШЕННАЯ ПРОВЕРКА BOOTSTRAPLAUNCHER С FALLBACK
      final hasBootstrap = classpath.any((p) => p.toLowerCase().contains('bootstraplauncher'));
      log('✅ Всего библиотек в classpath: ${classpath.length}');
      log('✅ BootstrapLauncher найден в classpath через JSON: $hasBootstrap');
      
      if (!hasBootstrap && mainClass.toLowerCase().contains('bootstraplauncher')) {
        log('⚠️ BootstrapLauncher не найден в JSON, попытка найти вручную в папке libraries...');
        final bootstrapDir = Directory(path.join(librariesPath, 'cpw', 'mods', 'bootstraplauncher'));
        if (bootstrapDir.existsSync()) {
          final files = bootstrapDir.listSync(recursive: true).whereType<File>().toList();
          final bootstrapJar = files.firstWhere((f) => f.path.endsWith('.jar'), orElse: () => File(''));
          if (bootstrapJar.existsSync()) {
            log('✅ BootstrapLauncher найден вручную: ${bootstrapJar.path}');
            classpath.add(bootstrapJar.path);
          } else {
            log('❌ КРИТИЧЕСКАЯ ОШИБКА: Файл bootstraplauncher.jar не найден в папке $bootstrapDir');
            result['error'] = 'Отсутствует критическая библиотека: bootstraplauncher.jar';
            return result;
          }
        } else {
          log('❌ КРИТИЧЕСКАЯ ОШИБКА: bootstraplauncher НЕ НАЙДЕН ни в JSON, ни в папке libraries!');
          log('Проверьте файл: ${versionJson.path}');
          result['error'] = 'Отсутствует критическая библиотека: bootstraplauncher. Возможно, версия Forge скачана некорректно или это NeoForge.';
          return result;
        }
      }

      String assetIndexName = versionId;
      if (finalVersionData['assetIndex'] is Map && finalVersionData['assetIndex']['id'] != null) {
        assetIndexName = finalVersionData['assetIndex']['id'].toString();
      } else if (finalVersionData['assets'] != null) {
        assetIndexName = finalVersionData['assets'].toString();
      }
      
      final assetsRoot = path.join(sharedFolder, 'assets');
      final nativesPath = path.join(sharedFolder, 'natives');

      final jvmArgs = <String>[
        javaPath,
        '-Xmx${ramMb}M',
        '-Xms${ramMb}M',
        '-Djava.library.path=$nativesPath',
      ];

      if (authlibInjectorPath != null && accessToken != null) {
        // Authlib-injector redirects Authlib profile/session requests to Ely.by.
        // Keep this before the Minecraft main class and use a valid Minecraft user type.
        jvmArgs.add('-javaagent:$authlibInjectorPath=ely.by');
        log('Ely.by: authlib-injector подключён: $authlibInjectorPath');
      } else if (accessToken != null) {
        log('⚠️ Ely.by: accessToken есть, но authlib-injector не найден — скины могут не загрузиться.');
      }

      if (guardAgentJarPath != null && guardConfigPath != null) {
        final guardJava = await _javaMajorVersion(javaPath);
        if (guardJava != null && guardJava >= 17) {
          jvmArgs.add('-javaagent:$guardAgentJarPath=$guardConfigPath');
          log('Защита модов: агент подключён.');
        } else {
          log('⚠️ Защита модов требует Java 17+ (сейчас: ${guardJava ?? '?'}) — ограничения не применены.');
        }
      }

      if (finalVersionData['arguments'] is Map && finalVersionData['arguments']['jvm'] is List) {
        for (final arg in finalVersionData['arguments']['jvm']) {
          if (arg is String) {
            if (evaluateRules(null)) {
              jvmArgs.add(replaceVariables(arg, nativesPath: nativesPath, librariesPath: librariesPath, versionId: versionId, instanceFolder: instanceFolder, assetsRoot: assetsRoot, assetIndexName: assetIndexName, username: username, loader: loader, classpath: classpath.join(Platform.isWindows ? ';' : ':')));
            }
          } else if (arg is Map) {
            if (evaluateRules(arg['rules'])) {
              final value = arg['value'];
              if (value is String) {
                jvmArgs.add(replaceVariables(value, nativesPath: nativesPath, librariesPath: librariesPath, versionId: versionId, instanceFolder: instanceFolder, assetsRoot: assetsRoot, assetIndexName: assetIndexName, username: username, loader: loader, classpath: classpath.join(Platform.isWindows ? ';' : ':')));
              } else if (value is List) {
                for (final v in value) {
                  if (v is String) {
                    jvmArgs.add(replaceVariables(v, nativesPath: nativesPath, librariesPath: librariesPath, versionId: versionId, instanceFolder: instanceFolder, assetsRoot: assetsRoot, assetIndexName: assetIndexName, username: username, loader: loader, classpath: classpath.join(Platform.isWindows ? ';' : ':')));
                  }
                }
              }
            }
          }
        }
      }

      final separator = Platform.isWindows ? ';' : ':';
      final classpathString = classpath.join(separator);
      if (loader.toLowerCase() == 'forge') {
        // Forge 1.20.1 uses its module path and legacyClassPath property.
        // Remove any legacyClassPath supplied by the version JSON because it
        // may contain the vanilla client JAR, which can cause duplicate
        // net.minecraft packages during Java module resolution.
        jvmArgs.removeWhere((arg) => arg.startsWith('-DlegacyClassPath='));

        final normalizedClientJar = path.normalize(clientJarPath).toLowerCase();
        final legacyClasspath = classpath
            .where((entry) => path.normalize(entry).toLowerCase() != normalizedClientJar)
            .join(separator);

        jvmArgs.add('-DlegacyClassPath=$legacyClasspath');
        jvmArgs.add(mainClass);
      } else {
        jvmArgs.addAll(['-cp', classpathString, mainClass]);
      }

      final gameArgs = <String>[];
      final rawGameArgs = finalVersionData['arguments']?['game'];

      if (rawGameArgs is List) {
        for (final item in rawGameArgs) {
          if (item is String) {
            if (evaluateRules(null)) {
              String processedArg = replaceVariables(
                item,
                nativesPath: nativesPath,
                librariesPath: librariesPath,
                versionId: versionId,
                instanceFolder: instanceFolder,
                assetsRoot: assetsRoot,
                assetIndexName: assetIndexName,
                username: username,
                loader: loader,
              );
              if (processedArg.isNotEmpty && 
                  !processedArg.contains('\${') && 
                  !processedArg.contains('quickPlay') && 
                  !processedArg.contains('clientId') && 
                  !processedArg.contains('xuid') && 
                  processedArg != '--demo') {
                gameArgs.add(processedArg);
              }
            }
          } else if (item is Map) {
            if (evaluateRules(item['rules'])) {
              final value = item['value'];
              if (value is String) {
                String processedArg = replaceVariables(value, nativesPath: nativesPath, librariesPath: librariesPath, versionId: versionId, instanceFolder: instanceFolder, assetsRoot: assetsRoot, assetIndexName: assetIndexName, username: username, loader: loader);
                if (processedArg.isNotEmpty && 
                    !processedArg.contains('\${') && 
                    !processedArg.contains('quickPlay') && 
                    !processedArg.contains('clientId') && 
                    !processedArg.contains('xuid') && 
                    processedArg != '--demo') {
                  gameArgs.add(processedArg);
                }
              } else if (value is List) {
                bool hasForbidden = false;
                for (final v in value) {
                  if (v is String && (v.contains('quickPlay') || v == '--clientId' || v == '--xuid' || v == '--demo')) {
                    hasForbidden = true;
                    break;
                  }
                }
                
                if (!hasForbidden) {
                  for (final v in value) {
                    if (v is String) {
                      String processedArg = replaceVariables(v, nativesPath: nativesPath, librariesPath: librariesPath, versionId: versionId, instanceFolder: instanceFolder, assetsRoot: assetsRoot, assetIndexName: assetIndexName, username: username, loader: loader);
                      if (processedArg.isNotEmpty && !processedArg.contains('\${')) {
                        gameArgs.add(processedArg);
                      }
                    }
                  }
                }
              }
            }
          }
        }
      } else if (finalVersionData['minecraftArguments'] is String) {
        final legacyArgs = (finalVersionData['minecraftArguments'] as String).split(' ');
        for (final arg in legacyArgs) {
          String processedArg = replaceVariables(arg, nativesPath: nativesPath, librariesPath: librariesPath, versionId: versionId, instanceFolder: instanceFolder, assetsRoot: assetsRoot, assetIndexName: assetIndexName, username: username, loader: loader, classpath: classpath.join(Platform.isWindows ? ';' : ':'));
          if (processedArg.isNotEmpty && 
              !processedArg.contains('\${') && 
              !processedArg.contains('quickPlay') && 
              !processedArg.contains('clientId') && 
              !processedArg.contains('xuid') && 
              processedArg != '--demo') {
            gameArgs.add(processedArg);
          }
        }
      }

      final allArgs = [...jvmArgs, ...gameArgs];
      final uuidIndex = gameArgs.indexOf('--uuid');
final tokenIndex = gameArgs.indexOf('--accessToken');

log('Ely.by: UUID передан в аргументах: '
    '${uuidIndex >= 0 && uuidIndex + 1 < gameArgs.length}');
log('Ely.by: токен передан в аргументах: '
    '${tokenIndex >= 0 && tokenIndex + 1 < gameArgs.length}');
log('Ely.by: UUID корректной длины: '
    '${_launchAuthUuid.length == 32}');
log('Ely.by: токен получен: '
    '${_launchAccessToken.isNotEmpty && _launchAccessToken != '0'}');
      log('=== ZemboLauncher Diagnostic ===');
      log('Java: $javaPath');
      log('Версия: $versionId');
      log('ОЗУ: ${ramMb}MB');
      log('Ник: $username');
      log('Asset Index: $assetIndexName');
      log('Всего аргументов: ${allArgs.length}');

      final jarFile = File(clientJarPath);
      log('✅ JAR файл: ${jarFile.lengthSync()} байт');

      final assetsIndexFile = File(path.join(assetsRoot, 'indexes', '$assetIndexName.json'));
      if (assetsIndexFile.existsSync()) {
        log('✅ Asset index найден: ${assetsIndexFile.lengthSync()} байт');
      }

      log('🚀 Запуск Minecraft...');
      
      _currentProcess = await Process.start(
        allArgs[0],
        allArgs.sublist(1),
        workingDirectory: instanceFolder,
      );

      log('Процесс запущен с PID: ${_currentProcess!.pid}');
      // Notify the UI immediately after Java/Minecraft process starts. The launch
      // method continues waiting for Minecraft to exit to collect its logs.
      if (onProcessStarted != null) {
        try {
          await onProcessStarted();
        } catch (e) {
          log('Не удалось применить действие после запуска Minecraft: $e');
        }
      }

      final utf8Decoder = Utf8Decoder(allowMalformed: true);
      final mcLogFile = File(path.join(instanceFolder, 'latest.log'));
      final mcLogSink = mcLogFile.openWrite(mode: FileMode.write);

      final process = _currentProcess!;

      await Future.wait([
        process.stdout.transform(utf8Decoder).forEach((data) {
          mcLogSink.write(data);
          if (data.contains('ERROR') || data.contains('Exception') || data.contains('Crash') || data.contains('FATAL')) {
            print('🎮 [MC ERROR] ${data.trim()}');
          }
        }).catchError((e) {
          print('⚠️ Ошибка чтения stdout: $e');
        }),
        process.stderr.transform(utf8Decoder).forEach((data) {
          mcLogSink.write(data);
          print('⚠️ [MC STDERR] ${data.trim()}');
        }).catchError((e) {
          print('⚠️ Ошибка чтения stderr: $e');
        }),
        process.exitCode.catchError((e) {
          print('⚠️ Ошибка получения exitCode: $e');
          return -1;
        }),
      ]);

      await mcLogSink.close();

      if (authlibInjectorPath != null) {
        await _logAuthlibInjectorStatus(mcLogFile, log);
      }

      if (guardConfigPath != null) {
        await _logGuardReport(instanceFolder, log);
      }
      
      if (_isStoppedByUser) {
        log('🛑 Minecraft остановлен пользователем');
        result['success'] = true;
        result['error'] = '';
        _isStoppedByUser = false;
      } else {
        final exitCode = await process.exitCode.catchError((e) => -1);
        _currentProcess = null;
        
        if (exitCode != 0) {
          result['success'] = false;
          result['error'] = 'Minecraft завершился с кодом $exitCode';
          log('❌ Minecraft завершился с кодом: $exitCode');
        } else {
          result['success'] = true;
          log('🏁 Minecraft завершён успешно');
        }
      }

    } catch (e) {
      result['error'] = 'Критическая ошибка запуска: $e';
      log('❌ ERROR: $e');
      _currentProcess = null;
    }

    return result;
  }
}