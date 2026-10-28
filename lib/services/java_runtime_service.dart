import 'dart:io';

class JavaRuntimeCandidate {
  final String path;
  final int? majorVersion;
  const JavaRuntimeCandidate(this.path, this.majorVersion);

  String get label => 'Java ${majorVersion ?? '?'} — $path';
}

class JavaRuntimeService {
  static Future<int?> majorVersion(String executable) async {
    try {
      final result = await Process.run(executable, ['-version'])
          .timeout(const Duration(seconds: 8));
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

  /// Recursively searches a chosen Java directory for runnable Java executables.
  static Future<List<JavaRuntimeCandidate>> scanDirectory(String directory) async {
    final root = Directory(directory);
    if (!await root.exists()) return const [];
    final candidates = <JavaRuntimeCandidate>[];
    final seen = <String>{};
    try {
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isEmpty
            ? ''
            : entity.uri.pathSegments.last.toLowerCase();
        final isJava = Platform.isWindows ? name == 'java.exe' : name == 'java';
        if (!isJava) continue;
        final absolute = entity.absolute.path;
        if (!seen.add(absolute.toLowerCase())) continue;
        final major = await majorVersion(absolute);
        if (major != null) candidates.add(JavaRuntimeCandidate(absolute, major));
      }
    } catch (_) {
      // Ignore unreadable subfolders and keep the Java installations already found.
    }
    candidates.sort((a, b) {
      final versionOrder = (b.majorVersion ?? 0).compareTo(a.majorVersion ?? 0);
      return versionOrder != 0 ? versionOrder : a.path.compareTo(b.path);
    });
    return candidates;
  }
}
