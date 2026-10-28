import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../services/elyby_auth_service.dart';

/// Локальный профиль игрока. Сохраняет ник и PNG-скин в папке Minecraft.
/// Для реальной загрузки скина на Ely.by нужна отдельная авторизация/API.
class PlayerProfileScreen extends StatefulWidget {
  final String minecraftFolder;
  final String initialNickname;
  final ValueChanged<String> onNicknameChanged;

  const PlayerProfileScreen({
    super.key,
    required this.minecraftFolder,
    required this.initialNickname,
    required this.onNicknameChanged,
  });

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  static const Color _background = Color(0xFF080F0D);
  static const Color _panel = Color(0xFF111C16);
  static const Color _green = Color(0xFF43E477);

  late final TextEditingController _nicknameController;
  String? _skinPath;
  bool _isDragging = false;
  bool _isSaving = false;
  String? _message;
  bool _messageIsError = false;
  ElyByAccount? _elyByAccount;
  bool _authBusy = false;

  String get _profileDirectory =>
      path.join(widget.minecraftFolder, 'zembo_profile');

  String get _profileFile => path.join(_profileDirectory, 'player.json');

  String get _savedSkinPath => path.join(_profileDirectory, 'skin.png');

  @override
  void initState() {
    super.initState();
    _nicknameController =
        TextEditingController(text: widget.initialNickname);
    _loadLocalProfile();
    _loadElyByAccount();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }


  Future<void> _loadElyByAccount() async {
    final account = await ElyByAuthService.loadAccount();
    if (mounted) setState(() => _elyByAccount = account);
  }

  Future<void> _showElyByLogin() async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final totpController = TextEditingController();
    bool obscure = true;
    final credentials = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _panel,
          title: const Text('Вход в Ely.by', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: usernameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Ник или e-mail Ely.by',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              TextField(
                controller: passwordController,
                obscureText: obscure,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Пароль',
                  labelStyle: const TextStyle(color: Colors.white70),
                  suffixIcon: IconButton(
                    onPressed: () => setDialogState(() => obscure = !obscure),
                    icon: Icon(obscure ? Icons.visibility : Icons.visibility_off, color: Colors.white54),
                  ),
                ),
              ),
              TextField(
                controller: totpController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Код 2FA (если включена)',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Пароль не сохраняется. Токен сессии хранится в защищённом хранилище Windows.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'username': usernameController.text.trim(),
                'password': passwordController.text,
                'totp': totpController.text.trim(),
              }),
              child: const Text('Войти'),
            ),
          ],
        ),
      ),
    );
    usernameController.dispose();
    passwordController.dispose();
    totpController.dispose();
    if (credentials == null || credentials['username']!.isEmpty || credentials['password']!.isEmpty) return;

    setState(() { _authBusy = true; _message = null; });
    try {
      final account = await ElyByAuthService.login(
        username: credentials['username']!,
        password: credentials['password']!,
        totp: credentials['totp'],
      );
      if (!mounted) return;
      setState(() {
        _elyByAccount = account;
        _nicknameController.text = account.username;
        _message = 'Вход выполнен: ${account.username}.';
        _messageIsError = false;
      });
      widget.onNicknameChanged(account.username);
    } catch (e) {
      if (mounted) setState(() { _message = e.toString().replaceFirst('Exception: ', ''); _messageIsError = true; });
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<void> _logoutElyBy() async {
    setState(() => _authBusy = true);
    await ElyByAuthService.logout();
    if (mounted) {
      setState(() {
        _elyByAccount = null;
        _message = 'Вы вышли из Ely.by.';
        _messageIsError = false;
      });
      setState(() => _authBusy = false);
    }
  }

  Future<void> _loadLocalProfile() async {
    try {
      final file = File(_profileFile);
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString())
            as Map<String, dynamic>;
        final nickname = data['nickname'] as String?;
        if (nickname != null && nickname.trim().isNotEmpty) {
          _nicknameController.text = nickname;
          widget.onNicknameChanged(nickname);
        }
      }

      final skin = File(_savedSkinPath);
      if (await skin.exists() && mounted) {
        setState(() => _skinPath = skin.path);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Не удалось прочитать локальный профиль.';
          _messageIsError = true;
        });
      }
    }
  }

  Future<void> _saveNickname() async {
    final nickname = _nicknameController.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_]{3,16}$').hasMatch(nickname)) {
      setState(() {
        _message = 'Ник должен содержать 3–16 символов: A–Z, 0–9 или _.';
        _messageIsError = true;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });

    try {
      await Directory(_profileDirectory).create(recursive: true);
      final oldData = <String, dynamic>{};
      final file = File(_profileFile);
      if (await file.exists()) {
        try {
          oldData.addAll(jsonDecode(await file.readAsString())
              as Map<String, dynamic>);
        } catch (_) {}
      }
      oldData['nickname'] = nickname;
      oldData['skinPath'] = await File(_savedSkinPath).exists()
          ? _savedSkinPath
          : null;
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(oldData),
      );
      widget.onNicknameChanged(nickname);
      if (mounted) {
        setState(() {
          _message = 'Ник сохранён.';
          _messageIsError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = 'Ошибка сохранения: $e';
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _chooseSkin() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png'],
      dialogTitle: 'Выберите PNG-скин Minecraft',
    );
    if (result == null || result.files.single.path == null) return;
    await _installSkin(result.files.single.path!);
  }

  Future<void> _installSkin(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists() ||
        path.extension(sourcePath).toLowerCase() != '.png') {
      setState(() {
        _message = 'Выбери файл с расширением .png.';
        _messageIsError = true;
      });
      return;
    }

    try {
      await Directory(_profileDirectory).create(recursive: true);
      final destination = File(_savedSkinPath);
      if (path.absolute(source.path) != path.absolute(destination.path)) {
        await source.copy(destination.path);
      }
      final profileFile = File(_profileFile);
      final data = <String, dynamic>{};
      if (await profileFile.exists()) {
        try {
          data.addAll(jsonDecode(await profileFile.readAsString())
              as Map<String, dynamic>);
        } catch (_) {}
      }
      data['nickname'] = _nicknameController.text.trim();
      data['skinPath'] = _savedSkinPath;
      await profileFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
      );

      if (mounted) {
        setState(() {
          _skinPath = destination.path;
          _message = 'Скин сохранён локально.';
          _messageIsError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = 'Не удалось сохранить скин: $e';
          _messageIsError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Профиль игрока',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Настрой свой никнейм и локальный скин Minecraft',
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const SizedBox(height: 28),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: _panel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _elyByAccount == null ? Colors.white10 : _green.withOpacity(0.6)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_user_outlined, color: _green, size: 34),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Аккаунт Ely.by', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            _elyByAccount == null ? 'Не выполнен вход — будет доступен локальный профиль' : 'Выполнен вход: ${_elyByAccount!.username}',
                            style: const TextStyle(color: Colors.white60),
                          ),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      if (_authBusy)
                        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: _green))
                      else if (_elyByAccount == null)
                        FilledButton.icon(
                          onPressed: _showElyByLogin,
                          icon: const Icon(Icons.login),
                          label: const Text('Войти'),
                          style: FilledButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: _logoutElyBy,
                          icon: const Icon(Icons.logout),
                          label: const Text('Выйти'),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _panel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSkinPreview(),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Локальный профиль',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Никнейм',
                              style: TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _nicknameController,
                              maxLength: 16,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                counterStyle:
                                    const TextStyle(color: Colors.white38),
                                hintText: 'Например, qmbys',
                                hintStyle:
                                    const TextStyle(color: Colors.white30),
                                filled: true,
                                fillColor: const Color(0xFF080F0D),
                                prefixIcon: const Icon(
                                  Icons.person_outline,
                                  color: _green,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FilledButton.icon(
                                onPressed:
                                    _isSaving ? null : _saveNickname,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 16,
                                  ),
                                ),
                                icon: _isSaving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save_outlined),
                                label: const Text('Сохранить ник'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Скин Minecraft',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                DropTarget(
                  onDragEntered: (_) => setState(() => _isDragging = true),
                  onDragExited: (_) => setState(() => _isDragging = false),
                  onDragDone: (detail) async {
                    setState(() => _isDragging = false);
                    for (final file in detail.files) {
                      if (path.extension(file.path).toLowerCase() == '.png') {
                        await _installSkin(file.path);
                        break;
                      }
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: _isDragging
                          ? _green.withOpacity(0.16)
                          : _panel,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _isDragging ? _green : Colors.white24,
                        width: _isDragging ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          _isDragging
                              ? Icons.file_download_done
                              : Icons.cloud_upload_outlined,
                          color: _green,
                          size: 42,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isDragging
                              ? 'Отпусти PNG-файл здесь'
                              : 'Перетащи PNG-скин сюда',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Или выбери файл на компьютере',
                          style: TextStyle(color: Colors.white60),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _chooseSkin,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Выбрать PNG'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: _green),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _message!,
                    style: TextStyle(
                      color: _messageIsError
                          ? const Color(0xFFFF8A80)
                          : _green,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.white54, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Скин хранится на этом компьютере. Чтобы его видели другие игроки, нужно отдельно подключить аккаунт Ely.by и загрузку скина через их сервис. Локальный PNG сам по себе не загружает скин на сервер.',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkinPreview() {
    return Container(
      width: 150,
      height: 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF080F0D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          const Text(
            'Твой скин',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _skinPath != null && File(_skinPath!).existsSync()
                ? Image.file(
                    File(_skinPath!),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 54,
                    ),
                  )
                : const Icon(
                    Icons.person,
                    color: _green,
                    size: 76,
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            _skinPath == null ? 'Скин не выбран' : 'PNG установлен',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
