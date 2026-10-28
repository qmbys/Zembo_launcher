import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'dart:io';

class ElyByAccount {
  final String accessToken;
  final String clientToken;
  final String uuid;
  final String username;

  const ElyByAccount({
    required this.accessToken,
    required this.clientToken,
    required this.uuid,
    required this.username,
  });

  factory ElyByAccount.fromJson(Map<String, dynamic> json) => ElyByAccount(
    accessToken: json['accessToken'] as String,
    clientToken: json['clientToken'] as String,
    uuid: (json['uuid'] as String).replaceAll('-', ''),
    username: json['username'] as String,
  );

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'clientToken': clientToken,
    'uuid': uuid,
    'username': username,
  };
}

class ElyByAuthService {
  static const _storage = FlutterSecureStorage();
  static const _accountKey = 'elyby_account_v1';
  static const _clientTokenKey = 'elyby_client_token_v1';
  static final _client = http.Client();

  static Future<String> _clientToken() async {
    final saved = await _storage.read(key: _clientTokenKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final token = sha256.convert(bytes).toString();
    await _storage.write(key: _clientTokenKey, value: token);
    return token;
  }

  static Future<ElyByAccount?> loadAccount() async {
    final raw = await _storage.read(key: _accountKey);
    if (raw == null) return null;
    try {
      return ElyByAccount.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<ElyByAccount> login({
    required String username,
    required String password,
    String? totp,
  }) async {
    final clientToken = await _clientToken();
    final actualPassword = (totp == null || totp.trim().isEmpty)
        ? password
        : '$password:${totp.trim()}';

    final response = await _client.post(
      Uri.parse('https://authserver.ely.by/auth/authenticate'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'agent': {'name': 'Minecraft', 'version': 1},
        'username': username.trim(),
        'password': actualPassword,
        'clientToken': clientToken,
        'requestUser': true,
      }),
    ).timeout(const Duration(seconds: 25));

    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {}

    if (response.statusCode != 200) {
      final error = (body['errorMessage'] ?? body['error'] ?? 'HTTP ${response.statusCode}').toString();
      if (error.toLowerCase().contains('two factor')) {
        throw Exception('Для аккаунта включена 2FA. Введи одноразовый код.');
      }
      if (response.statusCode == 401) {
        throw Exception('Неверный логин, пароль или код 2FA.');
      }
      throw Exception('Ely.by: $error');
    }

    final profile = body['selectedProfile'] as Map<String, dynamic>?;
    final token = body['accessToken'] as String?;
    if (profile == null || token == null) {
      throw Exception('Ely.by вернул неполный ответ авторизации.');
    }

    final account = ElyByAccount(
      accessToken: token,
      clientToken: (body['clientToken'] as String?) ?? clientToken,
      uuid: (profile['id'] as String).replaceAll('-', ''),
      username: profile['name'] as String,
    );
    await _storage.write(key: _accountKey, value: jsonEncode(account.toJson()));
    return account;
  }

  static Future<void> logout() async {
    final account = await loadAccount();
    if (account != null) {
      try {
        await _client.post(
          Uri.parse('https://authserver.ely.by/auth/invalidate'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'accessToken': account.accessToken,
            'clientToken': account.clientToken,
          }),
        ).timeout(const Duration(seconds: 10));
      } catch (_) {}
    }
    await _storage.delete(key: _accountKey);
  }

  /// Проверяет сохранённый токен Ely.by и при необходимости обновляет его.
  /// Возвращает null, если аккаунта нет или токен больше не работает (нужен повторный вход).
  static Future<ElyByAccount?> ensureValidAccount() async {
    final account = await loadAccount();
    if (account == null) return null;

    try {
      final validate = await _client.post(
        Uri.parse('https://authserver.ely.by/auth/validate'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'accessToken': account.accessToken}),
      ).timeout(const Duration(seconds: 12));
      if (validate.statusCode == 200 || validate.statusCode == 204) return account;

      final refresh = await _client.post(
        Uri.parse('https://authserver.ely.by/auth/refresh'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'accessToken': account.accessToken,
          'clientToken': account.clientToken,
          'requestUser': true,
        }),
      ).timeout(const Duration(seconds: 15));

      if (refresh.statusCode == 200) {
        final body = jsonDecode(refresh.body) as Map<String, dynamic>;
        final token = body['accessToken'] as String?;
        final profile = body['selectedProfile'] as Map<String, dynamic>?;
        if (token != null && token.isNotEmpty) {
          final updated = ElyByAccount(
            accessToken: token,
            clientToken: (body['clientToken'] as String?) ?? account.clientToken,
            uuid: profile != null ? (profile['id'] as String).replaceAll('-', '') : account.uuid,
            username: profile != null ? profile['name'] as String : account.username,
          );
          await _storage.write(key: _accountKey, value: jsonEncode(updated.toJson()));
          return updated;
        }
      }
      if (refresh.statusCode == 401 || refresh.statusCode == 403) return null;
      // Любая другая ошибка сервера: не выкидываем аккаунт, пробуем запуститься с тем, что есть.
      return account;
    } catch (_) {
      // Нет сети до Ely.by — запускаем с сохранённым токеном (скины из кэша / одиночная игра).
      return account;
    }
  }

  static bool _looksLikeJar(List<int> bytes) =>
      bytes.length > 100000 && bytes[0] == 0x50 && bytes[1] == 0x4B; // "PK"

  /// Downloads the official authlib-injector release into the shared Minecraft folder.
  static Future<String> ensureAuthlibInjector(String minecraftFolder) async {
    final directory = Directory(path.join(minecraftFolder, 'zembo_profile', 'libraries'));
    await directory.create(recursive: true);
    final jar = File(path.join(directory.path, 'authlib-injector.jar'));
    if (await jar.exists()) {
      final head = await jar.openRead(0, 2).expand((e) => e).toList();
      if (await jar.length() > 100000 && head.length == 2 && head[0] == 0x50 && head[1] == 0x4B) {
        return jar.path;
      }
      await jar.delete(); // повреждённый или недокачанный файл
    }

    final errors = <String>[];

    // 1) Официальные релизы на GitHub.
    try {
      final releaseResponse = await _client.get(
        Uri.parse('https://api.github.com/repos/yushijinhun/authlib-injector/releases/latest'),
        headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'ZemboLauncher'},
      ).timeout(const Duration(seconds: 20));
      if (releaseResponse.statusCode != 200) {
        throw Exception('GitHub HTTP ${releaseResponse.statusCode}');
      }
      final release = jsonDecode(releaseResponse.body) as Map<String, dynamic>;
      final assets = (release['assets'] as List? ?? []);
      final asset = assets.cast<Map<String, dynamic>>().where((a) {
        final name = (a['name'] as String? ?? '').toLowerCase();
        return name.endsWith('.jar') && name.contains('authlib-injector');
      }).firstOrNull;
      final url = asset?['browser_download_url'] as String?;
      if (url == null) throw Exception('в релизе нет JAR-файла');

      final jarResponse = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (jarResponse.statusCode == 200 && _looksLikeJar(jarResponse.bodyBytes)) {
        await jar.writeAsBytes(jarResponse.bodyBytes, flush: true);
        return jar.path;
      }
      throw Exception('не удалось скачать JAR (HTTP ${jarResponse.statusCode})');
    } catch (e) {
      errors.add('GitHub: $e');
    }

    // 2) Запасной источник — сайт самого authlib-injector.
    try {
      final latest = await _client
          .get(Uri.parse('https://authlib-injector.yushi.moe/artifact/latest.json'))
          .timeout(const Duration(seconds: 20));
      if (latest.statusCode != 200) throw Exception('HTTP ${latest.statusCode}');
      final info = jsonDecode(latest.body) as Map<String, dynamic>;
      final url = info['download_url'] as String?;
      if (url == null) throw Exception('нет ссылки на скачивание');
      final jarResponse = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (jarResponse.statusCode == 200 && _looksLikeJar(jarResponse.bodyBytes)) {
        await jar.writeAsBytes(jarResponse.bodyBytes, flush: true);
        return jar.path;
      }
      throw Exception('не удалось скачать JAR (HTTP ${jarResponse.statusCode})');
    } catch (e) {
      errors.add('authlib-injector.yushi.moe: $e');
    }

    throw Exception('Не удалось скачать authlib-injector (${errors.join('; ')}).');
  }
}
