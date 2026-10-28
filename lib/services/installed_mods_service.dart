import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Ограничения, которые пользователь задаёт для конкретного мода.
class ModPermissions {
  final bool denyCreateFiles;
  final bool denyOpenWindows;
  final bool denyReadFiles;

  const ModPermissions({
    this.denyCreateFiles = false,
    this.denyOpenWindows = false,
    this.denyReadFiles = false,
  });

  bool get hasRestrictions => denyCreateFiles || denyOpenWindows || denyReadFiles;

  ModPermissions copyWith({bool? denyCreateFiles, bool? denyOpenWindows, bool? denyReadFiles}) {
    return ModPermissions(
      denyCreateFiles: denyCreateFiles ?? this.denyCreateFiles,
      denyOpenWindows: denyOpenWindows ?? this.denyOpenWindows,
      denyReadFiles: denyReadFiles ?? this.denyReadFiles,
    );
  }

  Map<String, dynamic> toJson() => {
        'denyCreateFiles': denyCreateFiles,
        'denyOpenWindows': denyOpenWindows,
        'denyReadFiles': denyReadFiles,
      };

  factory ModPermissions.fromJson(Map<String, dynamic> json) => ModPermissions(
        denyCreateFiles: json['denyCreateFiles'] == true,
        denyOpenWindows: json['denyOpenWindows'] == true,
        denyReadFiles: json['denyReadFiles'] == true,
      );
}

enum ModLoad { low, medium, high }

/// Приблизительная оценка нагрузки мода, посчитанная по содержимому jar.
/// Это НЕ замер во время игры, а эвристика.
class ModLoadEstimate {
  final ModLoad level;
  final int ramMb;
  final double startupSeconds;
  final List<String> reasons;

  const ModLoadEstimate({
    required this.level,
    required this.ramMb,
    required this.startupSeconds,
    required this.reasons,
  });
}

class InstalledMod {
  final String path;
  final String fileName; // имя без .disabled
  final bool enabled;
  final int sizeBytes;

  // Метаданные (могут быть пустыми, пока jar ещё не прочитан).
  final bool analyzed;
  final String id;
  final String name;
  final String version;
  final String description;
  final String loader;
  final int classCount;
  final int mixinCount;
  final int nativeLibs;
  final int nestedJars;
  final int uncompressedBytes;
  final bool hasCoreMod;

  const InstalledMod({
    required this.path,
    required this.fileName,
    required this.enabled,
    required this.sizeBytes,
    this.analyzed = false,
    this.id = '',
    this.name = '',
    this.version = '',
    this.description = '',
    this.loader = '',
    this.classCount = 0,
    this.mixinCount = 0,
    this.nativeLibs = 0,
    this.nestedJars = 0,
    this.uncompressedBytes = 0,
    this.hasCoreMod = false,
  });

  String get displayName => name.isNotEmpty ? name : fileName.replaceAll(RegExp(r'\.jar$', caseSensitive: false), '');

  /// Ключ для хранения настроек: стабильный при выключении/включении мода.
  String get key => fileName;

  InstalledMod copyWith({String? path, bool? enabled}) => InstalledMod(
        path: path ?? this.path,
        fileName: fileName,
        enabled: enabled ?? this.enabled,
        sizeBytes: sizeBytes,
        analyzed: analyzed,
        id: id,
        name: name,
        version: version,
        description: description,
        loader: loader,
        classCount: classCount,
        mixinCount: mixinCount,
        nativeLibs: nativeLibs,
        nestedJars: nestedJars,
        uncompressedBytes: uncompressedBytes,
        hasCoreMod: hasCoreMod,
      );

  InstalledMod withAnalysis(Map<String, dynamic> a) => InstalledMod(
        path: path,
        fileName: fileName,
        enabled: enabled,
        sizeBytes: sizeBytes,
        analyzed: true,
        id: a['id'] as String? ?? '',
        name: a['name'] as String? ?? '',
        version: a['version'] as String? ?? '',
        description: a['description'] as String? ?? '',
        loader: a['loader'] as String? ?? '',
        classCount: a['classCount'] as int? ?? 0,
        mixinCount: a['mixinCount'] as int? ?? 0,
        nativeLibs: a['nativeLibs'] as int? ?? 0,
        nestedJars: a['nestedJars'] as int? ?? 0,
        uncompressedBytes: a['uncompressedBytes'] as int? ?? 0,
        hasCoreMod: a['hasCoreMod'] == true,
      );

  /// Эвристическая оценка нагрузки. Считается по числу классов, миксинов,
  /// размеру ресурсов, нативным библиотекам и т.п. Реальную нагрузку
  /// в игре покажет только профайлер (например, Spark).
  ModLoadEstimate get estimate {
    final resourceMb = uncompressedBytes / (1024 * 1024);
    final ram = (3 + classCount * 0.02 + resourceMb * 0.6 + nativeLibs * 15).round();
    final startup = 0.05 + classCount * 0.0006 + mixinCount * 0.03 + nestedJars * 0.05;
    final score = classCount / 150 + mixinCount * 0.8 + resourceMb * 0.3 + nativeLibs * 3 + (hasCoreMod ? 2 : 0) + nestedJars * 0.5;

    final reasons = <String>[];
    if (classCount > 0) reasons.add('классов: $classCount');
    if (mixinCount > 0) reasons.add('миксинов: $mixinCount');
    if (nativeLibs > 0) reasons.add('нативных библиотек: $nativeLibs');
    if (hasCoreMod) reasons.add('вмешивается в загрузку классов');
    if (nestedJars > 0) reasons.add('вложенных jar: $nestedJars');

    return ModLoadEstimate(
      level: score < 3 ? ModLoad.low : (score < 8 ? ModLoad.medium : ModLoad.high),
      ramMb: ram,
      startupSeconds: startup,
      reasons: reasons,
    );
  }
}

class InstalledModsService {
  static const String _disabledSuffix = '.disabled';
  static const String _permissionsFile = 'zembo_mod_permissions.json';

  /// Быстрый список файлов в папке mods (без чтения содержимого jar).
  static Future<List<InstalledMod>> listMods(String modsDir) async {
    final dir = Directory(modsDir);
    if (!await dir.exists()) return [];
    final result = <InstalledMod>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final lower = name.toLowerCase();
      final enabled = lower.endsWith('.jar');
      final disabled = lower.endsWith('.jar$_disabledSuffix');
      if (!enabled && !disabled) continue;
      final baseName = disabled ? name.substring(0, name.length - _disabledSuffix.length) : name;
      result.add(InstalledMod(
        path: entity.path,
        fileName: baseName,
        enabled: enabled,
        sizeBytes: await entity.length(),
      ));
    }
    result.sort((a, b) => a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()));
    return result;
  }

  /// Читает jar в отдельном изоляте и возвращает мод с метаданными и данными для оценки нагрузки.
  static Future<InstalledMod> analyze(InstalledMod mod) async {
    try {
      final data = await compute(_analyzeJar, mod.path);
      return mod.withAnalysis(data);
    } catch (_) {
      return mod.withAnalysis(const {});
    }
  }

  /// Включить/выключить мод: переименование .jar <-> .jar.disabled.
  static Future<InstalledMod> setEnabled(InstalledMod mod, bool enabled) async {
    if (mod.enabled == enabled) return mod;
    final file = File(mod.path);
    final newPath = enabled
        ? mod.path.substring(0, mod.path.length - _disabledSuffix.length)
        : '${mod.path}$_disabledSuffix';
    await file.rename(newPath);
    return mod.copyWith(path: newPath, enabled: enabled);
  }

  static Future<void> delete(InstalledMod mod) async {
    final file = File(mod.path);
    if (await file.exists()) await file.delete();
  }

  // ---------- Ограничения мода ----------

  static File _permissionsPath(String instancePath) => File(p.join(instancePath, _permissionsFile));

  static Future<Map<String, ModPermissions>> loadPermissions(String instancePath) async {
    try {
      final file = _permissionsPath(instancePath);
      if (!await file.exists()) return {};
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return json.map((key, value) => MapEntry(key, ModPermissions.fromJson(value as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  static Future<void> savePermissions(String instancePath, Map<String, ModPermissions> permissions) async {
    final file = _permissionsPath(instancePath);
    await file.parent.create(recursive: true);
    final json = <String, dynamic>{
      for (final entry in permissions.entries)
        if (entry.value.hasRestrictions) entry.key: entry.value.toJson(),
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }
}

/// Выполняется в отдельном изоляте через compute().
Map<String, dynamic> _analyzeJar(String path) {
  final result = <String, dynamic>{};
  final bytes = File(path).readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);

  var classCount = 0;
  var nativeLibs = 0;
  var nestedJars = 0;
  var uncompressed = 0;
  var mixinCount = 0;
  var hasCoreMod = false;
  final mixinConfigs = <ArchiveFile>[];
  ArchiveFile? fabric;
  ArchiveFile? quilt;
  ArchiveFile? modsToml;
  ArchiveFile? mcmodInfo;

  for (final entry in archive.files) {
    if (!entry.isFile) continue;
    final name = entry.name.replaceAll('\\', '/');
    final lower = name.toLowerCase();
    uncompressed += entry.size;

    if (lower.endsWith('.class')) {
      classCount++;
    } else if (lower.endsWith('.dll') || lower.endsWith('.so') || lower.endsWith('.dylib')) {
      nativeLibs++;
    } else if (lower.endsWith('.jar') && lower.startsWith('meta-inf/')) {
      nestedJars++;
    } else if (lower == 'fabric.mod.json') {
      fabric = entry;
    } else if (lower == 'quilt.mod.json') {
      quilt = entry;
    } else if (lower == 'meta-inf/mods.toml' || lower == 'meta-inf/neoforge.mods.toml') {
      modsToml = entry;
    } else if (lower == 'mcmod.info') {
      mcmodInfo = entry;
    } else if (lower.endsWith('.mixins.json') || (lower.contains('mixins.') && lower.endsWith('.json') && !lower.contains('/'))) {
      mixinConfigs.add(entry);
    }
    if (lower.contains('coremod') || lower.contains('ilaunchplugin') || lower.contains('iclasstransformer')) {
      hasCoreMod = true;
    }
  }

  String text(ArchiveFile f) => utf8.decode(f.content as List<int>, allowMalformed: true);

  try {
    if (fabric != null) {
      final json = jsonDecode(text(fabric)) as Map<String, dynamic>;
      result['loader'] = 'Fabric';
      result['id'] = json['id']?.toString() ?? '';
      result['name'] = json['name']?.toString() ?? '';
      result['version'] = json['version']?.toString() ?? '';
      result['description'] = json['description']?.toString() ?? '';
    } else if (quilt != null) {
      final json = jsonDecode(text(quilt)) as Map<String, dynamic>;
      final loader = json['quilt_loader'] as Map<String, dynamic>? ?? {};
      final meta = loader['metadata'] as Map<String, dynamic>? ?? {};
      result['loader'] = 'Quilt';
      result['id'] = loader['id']?.toString() ?? '';
      result['name'] = meta['name']?.toString() ?? '';
      result['version'] = loader['version']?.toString() ?? '';
      result['description'] = meta['description']?.toString() ?? '';
    } else if (modsToml != null) {
      final toml = text(modsToml);
      String? field(String key) {
        final m = RegExp('^\\s*$key\\s*=\\s*(?:"""|\'\'\'|"|\')(.*?)(?:"""|\'\'\'|"|\')\\s*\$', multiLine: true, dotAll: false).firstMatch(toml);
        return m?.group(1)?.trim();
      }
      result['loader'] = 'Forge';
      result['id'] = field('modId') ?? '';
      result['name'] = field('displayName') ?? '';
      result['version'] = field('version') ?? '';
      result['description'] = field('description') ?? '';
    } else if (mcmodInfo != null) {
      var decoded = jsonDecode(text(mcmodInfo));
      if (decoded is Map && decoded['modList'] is List) decoded = decoded['modList'];
      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        final m = decoded.first as Map;
        result['loader'] = 'Forge';
        result['id'] = m['modid']?.toString() ?? '';
        result['name'] = m['name']?.toString() ?? '';
        result['version'] = m['version']?.toString() ?? '';
        result['description'] = m['description']?.toString() ?? '';
      }
    }
  } catch (_) {
    // Метаданные не обязательны — покажем имя файла.
  }

  for (final config in mixinConfigs) {
    try {
      final json = jsonDecode(text(config));
      if (json is Map) {
        for (final key in const ['mixins', 'client', 'server']) {
          final list = json[key];
          if (list is List) mixinCount += list.length;
        }
      }
    } catch (_) {}
  }

  result['classCount'] = classCount;
  result['mixinCount'] = mixinCount;
  result['nativeLibs'] = nativeLibs;
  result['nestedJars'] = nestedJars;
  result['uncompressedBytes'] = uncompressed;
  result['hasCoreMod'] = hasCoreMod;
  return result;
}
