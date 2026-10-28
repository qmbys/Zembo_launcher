import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import '../models/settings.dart';
import '../services/settings_service.dart';
import '../services/java_runtime_service.dart';

class SetupWizard extends StatefulWidget {
  final VoidCallback onSetupComplete;

  const SetupWizard({super.key, required this.onSetupComplete});

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  int _currentStep = 0;
  final _nicknameController = TextEditingController();
  final _javaPathController = TextEditingController();
  // Папка, которую выбрал пользователь. Внутри неё создаётся LauncherFiles.
  final _installRootController = TextEditingController();
  static const String _installFolderName = 'LauncherFiles';
  static const int _lastStep = 2;
  bool _installing = false;
  double _installProgress = 0;
  String _installStatus = '';
  String? _installError;
  bool _launchInstalledCopy = true;
  String? _nicknameError;
  List<JavaRuntimeCandidate> _javaCandidates = [];
  bool _scanningJava = false;
  String? _javaScanMessage;

  @override
  void dispose() {
    _nicknameController.dispose();
    _javaPathController.dispose();
    _installRootController.dispose();
    super.dispose();
  }

  // Валидация никнейма: только английские буквы, цифры и подчёркивание
  bool _isValidNickname(String nickname) {
    if (nickname.isEmpty) return false;
    if (nickname.length < 3 || nickname.length > 16) return false;
    
    // Регулярное выражение: только a-z, A-Z, 0-9 и _
    final regex = RegExp(r'^[a-zA-Z0-9_]+$');
    return regex.hasMatch(nickname);
  }

  // Валидация текущего шага
  bool _isCurrentStepValid() {
    switch (_currentStep) {
      case 0:
        return _isValidNickname(_nicknameController.text.trim());
      case 1:
        // Java can be selected later; the launcher downloads the required runtime when needed.
        return true;
      case 2:
        return !_installing && _installRootController.text.trim().isNotEmpty;
      default:
        return false;
    }
  }

  // Проверка никнейма при вводе
  void _validateNickname(String value) {
    setState(() {
      if (value.isEmpty) {
        _nicknameError = null;
      } else if (value.length < 3) {
        _nicknameError = 'Минимум 3 символа';
      } else if (value.length > 16) {
        _nicknameError = 'Максимум 16 символов';
      } else if (!_isValidNickname(value)) {
        _nicknameError = 'Только английские буквы, цифры и _';
      } else {
        _nicknameError = null;
      }
    });
  }

  Future<void> _selectJavaFolder() async {
    final selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Выберите папку Java (можно общую папку со всеми версиями)',
    );
    if (selectedDirectory == null) return;
    setState(() {
      _scanningJava = true;
      _javaCandidates = [];
      _javaScanMessage = 'Ищу установленные версии Java…';
    });
    final found = await JavaRuntimeService.scanDirectory(selectedDirectory);
    if (!mounted) return;
    setState(() {
      _scanningJava = false;
      _javaCandidates = found;
      _javaScanMessage = found.isEmpty
          ? 'В этой папке не найдено работающих установок Java. Выбери папку, внутри которой есть bin\\java.exe.'
          : 'Найдено установок Java: ${found.length}. Выбери нужную версию ниже.';
      if (found.isNotEmpty) _javaPathController.text = found.first.path;
    });
  }

  Future<void> _selectFolder(TextEditingController controller) async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Выберите папку, в которой будет создана LauncherFiles',
    );

    if (selectedDirectory != null) {
      setState(() {
        controller.text = selectedDirectory;
        _installError = null;
      });
    }
  }

  /// Итоговая папка: <выбранная папка>\LauncherFiles
  /// (если пользователь сам выбрал папку с именем LauncherFiles — вложенную не создаём).
  String _resolveInstallDir() {
    final root = _installRootController.text.trim();
    if (p.basename(p.normalize(root)).toLowerCase() == _installFolderName.toLowerCase()) {
      return p.normalize(root);
    }
    return p.join(root, _installFolderName);
  }

  /// Реально копирует файлы лаунчера (exe, dll, папку data) в [targetDir].
  Future<void> _copyLauncherFiles(Directory sourceDir, Directory targetDir) async {
    final sourcePath = p.normalize(sourceDir.absolute.path);
    final targetPath = p.normalize(targetDir.absolute.path);

    // Установка в ту же папку, откуда запущен лаунчер — копировать нечего.
    if (p.equals(sourcePath, targetPath)) return;

    // Собираем список файлов. Если целевая папка лежит внутри исходной — пропускаем её,
    // иначе получится бесконечное копирование самого в себя.
    final files = <File>[];
    await for (final entity in sourceDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final path = p.normalize(entity.absolute.path);
      if (p.isWithin(targetPath, path)) continue;
      files.add(entity);
    }

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final relative = p.relative(p.normalize(file.absolute.path), from: sourcePath);
      final destination = File(p.join(targetPath, relative));
      await destination.parent.create(recursive: true);
      await file.copy(destination.path);

      if (!mounted) return;
      setState(() {
        _installProgress = (i + 1) / files.length;
        _installStatus = 'Копирование: $relative';
      });
      // Отдаём управление UI, чтобы прогресс-бар успевал перерисовываться.
      if (i % 20 == 0) await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> _completeSetup() async {
    if (_installing) return;

    final installDir = Directory(_resolveInstallDir());

    setState(() {
      _installing = true;
      _installError = null;
      _installProgress = 0;
      _installStatus = 'Создаю папку ${installDir.path}…';
    });

    String? installedExe;
    try {
      await installDir.create(recursive: true);

      final currentExe = File(Platform.resolvedExecutable);
      await _copyLauncherFiles(currentExe.parent, installDir);

      final candidate = File(p.join(installDir.path, p.basename(currentExe.path)));
      if (await candidate.exists()) installedExe = candidate.path;

      if (!mounted) return;
      setState(() {
        _installProgress = 1;
        _installStatus = 'Сохраняю настройки…';
      });

      // Папка лаунчера и папка файлов Minecraft — одна и та же LauncherFiles.
      final settings = LauncherSettings(
        nickname: _nicknameController.text.trim(),
        javaPath: _javaPathController.text.trim(),
        launcherFolder: installDir.path,
        minecraftFolder: installDir.path,
      );
      await SettingsService.saveSettings(settings);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _installError = 'Не удалось установить: $e';
      });
      return;
    }

    if (!mounted) return;

    // Запускаем установленную копию (если она лежит не там, откуда запущен установщик).
    if (_launchInstalledCopy &&
        installedExe != null &&
        !p.equals(p.normalize(installedExe), p.normalize(Platform.resolvedExecutable))) {
      try {
        await Process.start(
          installedExe,
          const [],
          workingDirectory: installDir.path,
          mode: ProcessStartMode.detached,
        );
        exit(0);
      } catch (_) {
        // Не получилось запустить копию — просто продолжаем в текущем окне.
      }
    }

    setState(() => _installing = false);
    widget.onSetupComplete();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isValid = _isCurrentStepValid();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF080F0D),
              Color(0xFF111C16),
            ],
          ),
        ),
        child: Center(
          child: Container(
            width: 700,
            height: 600,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF111C16),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Установка ZemboLauncher',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Шаг ${_currentStep + 1} из ${_lastStep + 1}',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (_currentStep + 1) / (_lastStep + 1),
                  backgroundColor: colorScheme.outline.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 32),
                Expanded(
                  child: _buildStepContent(colorScheme),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_currentStep > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.outline),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _installing ? null : () => setState(() => _currentStep--),
                            child: Text(
                              'Назад',
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 100),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: isValid ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isValid ? colorScheme.primary : colorScheme.outline,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: isValid
                              ? () {
                                  if (_currentStep < _lastStep) {
                                    setState(() => _currentStep++);
                                  } else {
                                    _completeSetup();
                                  }
                                }
                              : null,
                          child: Text(
                            _currentStep < _lastStep ? 'Далее' : (_installing ? 'Установка…' : 'Установить'),
                            style: TextStyle(
                              color: isValid ? Colors.white : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent(ColorScheme colorScheme) {
    switch (_currentStep) {
      case 0:
        return _buildNicknameStep(colorScheme);
      case 1:
        return _buildJavaPathStep(colorScheme);
      case 2:
        return _buildInstallFolderStep(colorScheme);
      default:
        return const SizedBox();
    }
  }

  Widget _buildNicknameStep(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.person_outline,
          size: 64,
          color: colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Как вас зовут?',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Введите ваш никнейм для игры в Minecraft (только английские буквы)',
          style: TextStyle(
            fontSize: 16,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _nicknameController,
          onChanged: _validateNickname,
          style: TextStyle(color: colorScheme.onSurface, fontSize: 18),
          decoration: InputDecoration(
            hintText: 'Steve_123',
            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            errorText: _nicknameError,
            errorStyle: const TextStyle(color: Colors.redAccent),
            filled: true,
            fillColor: colorScheme.surface.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: _nicknameError != null ? Colors.red : colorScheme.outline,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: _nicknameError != null ? Colors.red : colorScheme.primary,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
            prefixIcon: Icon(Icons.person, color: colorScheme.primary),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            counterText: '${_nicknameController.text.length}/16',
          ),
        ),
        if (_scanningJava) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_javaScanMessage != null) ...[
          const SizedBox(height: 10),
          Text(_javaScanMessage!, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
        ],
        if (_javaCandidates.isNotEmpty) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _javaCandidates.any((candidate) => candidate.path == _javaPathController.text)
                ? _javaPathController.text : _javaCandidates.first.path,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Найденные установки Java'),
            items: _javaCandidates.map((candidate) => DropdownMenuItem<String>(
              value: candidate.path,
              child: Text('Java ${candidate.majorVersion} — ${candidate.path}', overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _javaPathController.text = value);
            },
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: colorScheme.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Никнейм может содержать только английские буквы (a-z, A-Z), цифры (0-9) и подчёркивание (_). Длина: 3-16 символов.',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildJavaPathStep(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.code,
          size: 64,
          color: colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Путь к Java',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Укажите путь к установленной Java для запуска Minecraft',
          style: TextStyle(
            fontSize: 16,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _javaPathController,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Выбери папку с установленными версиями Java',
            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 12),
            filled: true,
            fillColor: colorScheme.surface.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
            ),
            suffixIcon: IconButton(
              icon: Icon(Icons.folder_open, color: colorScheme.primary),
              onPressed: _selectJavaFolder,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: colorScheme.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Можно выбрать общую папку Java: лаунчер найдёт все java.exe внутри неё. Если для сборки нужна более новая Java, Zembo скачает её автоматически.',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInstallFolderStep(ColorScheme colorScheme) {
    final hasPath = _installRootController.text.trim().isNotEmpty;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.folder,
            size: 64,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Папка установки',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Выберите папку — в ней будет создана папка $_installFolderName для лаунчера и файлов Minecraft',
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _installRootController,
            enabled: !_installing,
            onChanged: (_) => setState(() => _installError = null),
            style: TextStyle(color: colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: 'C:\\Users\\User\\Games',
              hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 12),
              filled: true,
              fillColor: colorScheme.surface.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.primary, width: 2),
              ),
              suffixIcon: IconButton(
                icon: Icon(Icons.folder_open, color: colorScheme.primary),
                onPressed: _installing ? null : () => _selectFolder(_installRootController),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.create_new_folder_outlined, color: colorScheme.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasPath
                        ? 'Будет создана папка:\n${_resolveInstallDir()}'
                        : 'После выбора здесь появится итоговый путь установки.',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _launchInstalledCopy,
            onChanged: _installing ? null : (v) => setState(() => _launchInstalledCopy = v ?? true),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              'Запустить лаунчер из установленной папки после установки',
              style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
            ),
          ),
          if (_installing) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _installProgress == 0 ? null : _installProgress),
            const SizedBox(height: 8),
            Text(
              _installStatus,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
          if (_installError != null) ...[
            const SizedBox(height: 12),
            Text(_installError!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}
