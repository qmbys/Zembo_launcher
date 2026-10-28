import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import 'installed_mods_service.dart';

/// Подготовка защитного Java-агента (zembo-guard.jar): ограничения модов,
/// заданные во вкладке «Установленные моды», превращаются в конфиг агента.
class ModGuardService {
  static const String _assetPath = 'assets/agent/zembo-guard.jar';
  static const String configName = 'zembo_guard.conf';
  static const String reportName = 'zembo_guard_report.json';

  /// Возвращает пути к jar и конфигу агента или null, если ограничений нет.
  static Future<({String jar, String config})?> prepare({
    required String sharedFolder,
    required String instanceFolder,
    required void Function(String) log,
  }) async {
    final configFile = File(p.join(instanceFolder, configName));
    final reportFile = File(p.join(instanceFolder, reportName));
    try {
      if (await reportFile.exists()) await reportFile.delete();

      final permissions = await InstalledModsService.loadPermissions(instanceFolder);
      final modsDir = Directory(p.join(instanceFolder, 'mods'));
      final present = <String>{};
      if (await modsDir.exists()) {
        await for (final e in modsDir.list(followLinks: false)) {
          if (e is File && e.path.toLowerCase().endsWith('.jar')) present.add(p.basename(e.path));
        }
      }

      // Только включённые моды (выключенные не загружаются) с реальными ограничениями.
      final lines = <String>[];
      for (final entry in permissions.entries) {
        final perm = entry.value;
        if (!perm.hasRestrictions || !present.contains(entry.key)) continue;
        final flags = [
          if (perm.denyCreateFiles) 'create',
          if (perm.denyReadFiles) 'read',
          if (perm.denyOpenWindows) 'windows',
        ];
        lines.add('mod=${entry.key}|${flags.join(',')}');
      }

      if (lines.isEmpty) {
        if (await configFile.exists()) await configFile.delete();
        return null;
      }

      final jarFile = File(p.join(sharedFolder, 'zembo_profile', 'libraries', 'zembo-guard.jar'));
      final data = await rootBundle.load(_assetPath);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (!await jarFile.exists() || await jarFile.length() != bytes.length) {
        await jarFile.parent.create(recursive: true);
        await jarFile.writeAsBytes(bytes, flush: true);
      }

      final config = <String>[
        '# Создано лаунчером автоматически',
        'allow=$instanceFolder',
        'allow=$sharedFolder',
        ...lines,
      ];
      await configFile.writeAsString('${config.join('\n')}\n', encoding: utf8);

      log('Защита модов: ограничения для ${lines.length} мод(ов).');
      return (jar: jarFile.path, config: configFile.path);
    } catch (e) {
      log('⚠️ Защита модов: не удалось подготовить агент ($e). Игра запустится без ограничений.');
      return null;
    }
  }

  /// Сколько раз агент заблокировал действия модов (читается из отчёта после выхода из игры).
  static Future<Map<String, Map<String, int>>> loadReport(String instanceFolder) async {
    try {
      final file = File(p.join(instanceFolder, reportName));
      if (!await file.exists()) return {};
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final mods = json['mods'] as Map<String, dynamic>? ?? {};
      return mods.map((k, v) {
        final m = v as Map<String, dynamic>;
        return MapEntry(k, {
          'create': (m['create'] as num?)?.toInt() ?? 0,
          'read': (m['read'] as num?)?.toInt() ?? 0,
          'windows': (m['windows'] as num?)?.toInt() ?? 0,
        });
      });
    } catch (_) {
      return {};
    }
  }
}
