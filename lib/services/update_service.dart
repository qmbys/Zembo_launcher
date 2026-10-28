import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

class UpdateInfo {
  final String currentVersion;
  final String version;
  final String tag;
  final String releaseUrl;
  final String? assetName;
  final String? assetUrl;
  final int? assetSize;
  final String? assetSha256;

  const UpdateInfo({
    required this.currentVersion,
    required this.version,
    required this.tag,
    required this.releaseUrl,
    this.assetName,
    this.assetUrl,
    this.assetSize,
    this.assetSha256,
  });

  bool get canInstallInPlace => Platform.isWindows && assetUrl != null;
}

/// Проверка и установка обновлений из GitHub Releases.
class UpdateService {
  static const String owner = 'qmbys';
  static const String repo = 'Zembo_launcher';

  static final http.Client _client = http.Client();

  /// Возвращает информацию о новой версии или null (обновлений нет / нет сети / нет релизов).
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final current = (await PackageInfo.fromPlatform()).version;
      final response = await _client.get(
        Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest'),
        headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'ZemboLauncher'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null; // 404 — релизов ещё нет

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['draft'] == true || json['prerelease'] == true) return null;
      final tag = (json['tag_name'] as String?) ?? '';
      final latest = _cleanVersion(tag);
      if (latest.isEmpty || compareVersions(latest, current) <= 0) return null;

      // Ищем zip для Windows: сначала с "windows" в названии, потом любой zip.
      final assets = (json['assets'] as List? ?? []).cast<Map<String, dynamic>>();
      final zips = assets.where((a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.zip')).toList();
      Map<String, dynamic>? asset;
      for (final a in zips) {
        if ((a['name'] as String).toLowerCase().contains('windows')) {
          asset = a;
          break;
        }
      }
      asset ??= zips.isEmpty ? null : zips.first;

      final digest = asset?['digest'] as String?;
      return UpdateInfo(
        currentVersion: current,
        version: latest,
        tag: tag,
        releaseUrl: (json['html_url'] as String?) ?? 'https://github.com/$owner/$repo/releases/latest',
        assetName: asset?['name'] as String?,
        assetUrl: asset?['browser_download_url'] as String?,
        assetSize: (asset?['size'] as num?)?.toInt(),
        assetSha256: (digest != null && digest.startsWith('sha256:')) ? digest.substring(7).toLowerCase() : null,
      );
    } catch (_) {
      return null;
    }
  }

  static String _cleanVersion(String tag) {
    final m = RegExp(r'(\d+(?:\.\d+)*)').firstMatch(tag);
    return m?.group(1) ?? '';
  }

  /// >0 если a новее b.
  static int compareVersions(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static Future<void> openReleasePage(UpdateInfo info) async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', info.releaseUrl]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [info.releaseUrl]);
      } else {
        await Process.run('xdg-open', [info.releaseUrl]);
      }
    } catch (_) {}
  }

  /// Скачивает архив, проверяет его и запускает скрипт, который после выхода лаунчера
  /// подменяет файлы и запускает новую версию. После успеха приложение завершается.
  static Future<void> downloadAndInstall(
    UpdateInfo info, {
    required void Function(double progress, String status) onProgress,
  }) async {
    if (!info.canInstallInPlace) {
      throw Exception('Автоматическое обновление доступно только в Windows-сборке с zip в релизе.');
    }

    final workDir = Directory(p.join(Directory.systemTemp.path, 'zembo_update'));
    if (await workDir.exists()) await workDir.delete(recursive: true);
    await workDir.create(recursive: true);
    final zip = File(p.join(workDir.path, info.assetName ?? 'update.zip'));

    onProgress(0, 'Скачивание ${info.version}…');
    final request = http.Request('GET', Uri.parse(info.assetUrl!))..headers['User-Agent'] = 'ZemboLauncher';
    final response = await _client.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('GitHub вернул HTTP ${response.statusCode}');
    }
    final total = response.contentLength ?? info.assetSize ?? 0;
    var received = 0;
    final sink = zip.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total, 'Скачивание ${info.version}… ${(received / 1048576).toStringAsFixed(1)} МБ');
      }
    } finally {
      await sink.close();
    }

    onProgress(1, 'Проверка файла…');
    if (info.assetSize != null && await zip.length() != info.assetSize) {
      throw Exception('Размер скачанного файла не совпал — загрузка повреждена.');
    }
    if (info.assetSha256 != null) {
      final hash = (await sha256.bind(zip.openRead()).first).toString();
      if (hash != info.assetSha256) throw Exception('Контрольная сумма не совпала — файл не принят.');
    }

    final exe = Platform.resolvedExecutable;
    final script = File(p.join(workDir.path, 'zembo_update.ps1'));
    await script.writeAsString(_updateScript, encoding: utf8);

    onProgress(1, 'Перезапуск…');
    await Process.start(
      'powershell',
      [
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-File', script.path,
        '-ProcId', '$pid',
        '-Zip', zip.path,
        '-AppDir', p.dirname(exe),
        '-Exe', p.basename(exe),
      ],
      mode: ProcessStartMode.detached,
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    exit(0);
  }

  // PowerShell: ждёт выхода лаунчера, распаковывает архив поверх папки программы
  // (пользовательские данные Minecraft не затрагиваются — перезаписываются только файлы из архива) и запускает новую версию.
  static const String _updateScript = r'''
param([int]$ProcId, [string]$Zip, [string]$AppDir, [string]$Exe)
$log = Join-Path $env:TEMP 'zembo_update.log'
function Log($m) { Add-Content -Path $log -Value ("{0}  {1}" -f (Get-Date -Format s), $m) }
try {
  Log "start update, waiting for pid $ProcId"
  try { Wait-Process -Id $ProcId -Timeout 60 -ErrorAction SilentlyContinue } catch {}
  Start-Sleep -Seconds 1
  $tmp = Join-Path $env:TEMP ('zembo_update_' + [guid]::NewGuid().ToString('N'))
  Expand-Archive -LiteralPath $Zip -DestinationPath $tmp -Force
  $exeFile = Get-ChildItem -Path $tmp -Recurse -Filter $Exe | Select-Object -First 1
  if (-not $exeFile) { throw "В архиве не найден $Exe" }
  $src = $exeFile.Directory.FullName
  $ok = $false
  for ($i = 0; $i -lt 10 -and -not $ok; $i++) {
    try {
      Copy-Item -Path (Join-Path $src '*') -Destination $AppDir -Recurse -Force -ErrorAction Stop
      $ok = $true
    } catch {
      Log "copy attempt $i failed: $_"
      Start-Sleep -Seconds 1
    }
  }
  if (-not $ok) { throw 'Не удалось скопировать файлы обновления' }
  Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -Path $Zip -Force -ErrorAction SilentlyContinue
  Log 'update installed'
} catch {
  Log "update failed: $_"
}
Start-Process -FilePath (Join-Path $AppDir $Exe) -WorkingDirectory $AppDir
''';
}
