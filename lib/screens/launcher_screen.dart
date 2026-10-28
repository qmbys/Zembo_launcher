import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as path;
import 'package:window_manager/window_manager.dart';

import '../widgets/navigation_rail_widget.dart';
import '../widgets/settings_panel_widget.dart';
import '../models/profile.dart';
import '../widgets/create_profile_dialog.dart';
import '../widgets/profile_settings_dialog.dart';
import '../widgets/modpack_store_screen.dart';
import '../services/settings_service.dart';
import '../widgets/setup_wizard.dart';
import '../models/settings.dart';
import '../services/minecraft_downloader.dart';
import '../services/fabric_installer.dart';
import '../services/forge_installer.dart';
import '../services/minecraft_launcher.dart';
import '../services/profile_service.dart';
import '../services/widgets_service.dart';
import 'player_profile_screen.dart';
import 'settings_screen.dart';
import '../services/elyby_auth_service.dart';
import '../services/skin_mod_service.dart';
import '../services/mod_guard_service.dart';
import '../services/discord_activity_service.dart';
import '../services/tray_service.dart';
import '../services/update_service.dart';

const Color _background = Color(0xFF080F0D);
const Color _surface = Color(0xFF0B120E);
const Color _cardColor = Color(0xFF0F1A14);
const Color _green = Color(0xFF43E477);
const Color _mutedGreen = Color(0xFF9DE8AC);
const Color _borderColor = Color(0xFF23382B);

class LauncherScreen extends StatefulWidget {
  const LauncherScreen({super.key});

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen> {
  int _selectedIndex = 0;
  List<Profile> _profiles = [];
  String? _selectedProfileId;
  LauncherSettings? _settings;
  Profile? _editingProfile;

  String _launchPhase = 'idle';
  String _launchLog = 'Готов к запуску';

  bool _isEditMode = false;
  bool _discordActivityEnabled = true;
  String _launchBehavior = 'nothing';
  List<WidgetItem> _widgets = [];

  UpdateInfo? _update;
  bool _updating = false;
  double _updateProgress = 0;
  String _updateStatus = '';
  String? _updateError;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkForLauncherUpdate();
  }

  Future<void> _checkForLauncherUpdate() async {
    final info = await UpdateService.checkForUpdate();
    if (!mounted || info == null) return;
    setState(() => _update = info);
  }

  Future<void> _startLauncherUpdate() async {
    final info = _update;
    if (info == null || _updating) return;

    if (_launchPhase != 'idle') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Закрой игру перед обновлением лаунчера.')),
      );
      return;
    }
    if (!info.canInstallInPlace) {
      await UpdateService.openReleasePage(info);
      return;
    }

    setState(() {
      _updating = true;
      _updateError = null;
      _updateProgress = 0;
      _updateStatus = 'Подготовка…';
    });
    try {
      await UpdateService.downloadAndInstall(
        info,
        onProgress: (progress, status) {
          if (!mounted) return;
          setState(() {
            _updateProgress = progress;
            _updateStatus = status;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _updating = false;
        _updateError = 'Не удалось обновить: $e';
      });
    }
  }

  Widget _buildUpdateBanner() {
    final info = _update!;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF12261A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withValues(alpha: .45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update_alt_rounded, color: _green, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Доступна новая версия ${info.version}',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _updating
                      ? _updateStatus
                      : (_updateError ?? 'Сейчас установлена версия ${info.currentVersion}'),
                  style: TextStyle(
                    color: _updateError != null && !_updating ? Colors.redAccent : const Color(0xFF91A497),
                    fontSize: 11,
                  ),
                ),
                if (_updating) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _updateProgress <= 0 || _updateProgress >= 1 ? null : _updateProgress,
                    color: _green,
                    backgroundColor: const Color(0xFF1D3A28),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          FilledButton.icon(
            onPressed: _updating ? null : _startLauncherUpdate,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Обновить лаунчер до последней версии?'),
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.loadSettings();
    if (!mounted) return;

    final discordEnabled = await SettingsService.loadDiscordActivityEnabled();
    final launchBehavior = await SettingsService.loadLaunchBehavior();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _discordActivityEnabled = discordEnabled;
      _launchBehavior = launchBehavior;
    });

    if (discordEnabled) {
      await DiscordActivityService.setEnabled(true);
    }

    if (settings != null) {
      await _loadProfiles(settings);
      await _loadWidgets(settings);
    }
  }

  Future<void> _loadProfiles(LauncherSettings settings) async {
    final profiles =
        await ProfileService.loadProfiles(settings.minecraftFolder);

    if (!mounted) return;

    setState(() {
      _profiles = profiles;
      if (profiles.isNotEmpty &&
          !_profiles.any((p) => p.id == _selectedProfileId)) {
        _selectedProfileId = profiles.first.id;
      }
    });
  }

  Future<void> _loadWidgets(LauncherSettings settings) async {
    final widgetsData =
        await WidgetsService.loadWidgets(settings.minecraftFolder);

    if (!mounted) return;

    setState(() {
      _widgets = widgetsData.map((data) {
        return WidgetItem(
          id: data['id'] as String,
          type: WidgetType.values.firstWhere(
            (e) => e.toString() == data['type'],
            orElse: () => WidgetType.featuredWorld,
          ),
          title: data['title'] as String,
          subtitle: data['subtitle'] as String,
          icon: IconData(
            data['icon'] as int,
            fontFamily: 'MaterialIcons',
          ),
        );
      }).toList();
    });
  }

  Future<void> _saveWidgets() async {
    if (_settings == null) return;

    final widgetsData = _widgets.map((w) {
      return {
        'id': w.id,
        'type': w.type.toString(),
        'title': w.title,
        'subtitle': w.subtitle,
        'icon': w.icon.codePoint,
      };
    }).toList();

    await WidgetsService.saveWidgets(
      _settings!.minecraftFolder,
      widgetsData,
    );
  }

  Future<void> _saveProfiles() async {
    if (_settings == null) return;

    await ProfileService.saveProfiles(
      _profiles,
      _settings!.minecraftFolder,
    );
  }

  String _getInstanceFolder(Profile profile) {
    return path.join(
      _settings!.minecraftFolder,
      'instances',
      profile.name,
    );
  }

  void _addProfile(Profile profile) {
    setState(() {
      _profiles.add(profile);
      _selectedProfileId = profile.id;
    });

    _saveProfiles();
  }

  void _selectProfile(String profileId) {
    setState(() {
      _selectedProfileId = profileId;
    });
  }

  Future<bool> _updateProfile(Profile updatedProfile) async {
    final index = _profiles.indexWhere(
      (profile) => profile.id == updatedProfile.id,
    );

    if (index == -1) return false;

    final oldProfile = _profiles[index];

    if (oldProfile.name != updatedProfile.name && _settings != null) {
      final instancesFolder = Directory(
        path.join(_settings!.minecraftFolder, 'instances'),
      );

      final oldFolder = Directory(
        path.join(instancesFolder.path, oldProfile.name),
      );

      final newFolder = Directory(
        path.join(instancesFolder.path, updatedProfile.name),
      );

      if (await newFolder.exists()) {
        if (!mounted) return false;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Папка с таким названием уже существует. Выбери другое имя.',
            ),
          ),
        );

        return false;
      }

      try {
        if (await oldFolder.exists()) {
          await oldFolder.rename(newFolder.path);
        }
      } catch (e) {
        if (!mounted) return false;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось переименовать папку сборки: $e'),
          ),
        );

        return false;
      }
    }

    if (!mounted) return false;

    setState(() {
      _profiles[index] = updatedProfile;
    });

    await _saveProfiles();
    return true;
  }

  void _deleteProfile(String profileId) {
    setState(() {
      _profiles.removeWhere((p) => p.id == profileId);

      if (_selectedProfileId == profileId) {
        _selectedProfileId =
            _profiles.isNotEmpty ? _profiles.first.id : null;
      }
    });

    _saveProfiles();
  }

  void _updateLog(String message) {
    if (!mounted) return;

    setState(() {
      _launchLog = message;
    });
  }

  void _showAddWidgetDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF111C16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text(
          'Добавить виджет',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildWidgetOption(
              'Установленные моды',
              'Список модов',
              Icons.extension,
              () => _addWidget(WidgetType.installedMods),
            ),
            _buildWidgetOption(
              'Последние миры',
              'Сохранённые миры',
              Icons.public,
              () => _addWidget(WidgetType.recentWorlds),
            ),
            _buildWidgetOption(
              'Статистика',
              'Статистика игры',
              Icons.bar_chart,
              () => _addWidget(WidgetType.statistics),
            ),
            _buildWidgetOption(
              'Быстрый запуск',
              'Кнопка быстрого запуска',
              Icons.play_arrow,
              () => _addWidget(WidgetType.quickLaunch),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Отмена',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWidgetOption(
    String title,
    String description,
    IconData icon,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, color: _green),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white),
      ),
      subtitle: Text(
        description,
        style: const TextStyle(color: Colors.white54),
      ),
      onTap: () {
        onTap();
        Navigator.pop(context);
      },
    );
  }

  void _addWidget(WidgetType type) {
    setState(() {
      _widgets.add(
        WidgetItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: type,
          title: _getWidgetTitle(type),
          subtitle: _getWidgetSubtitle(type),
          icon: _getWidgetIcon(type),
        ),
      );
    });

    _saveWidgets();
  }

  String _getWidgetTitle(WidgetType type) {
    switch (type) {
      case WidgetType.installedMods:
        return 'Установленные моды';
      case WidgetType.recentWorlds:
        return 'Последние миры';
      case WidgetType.statistics:
        return 'Статистика';
      case WidgetType.quickLaunch:
        return 'Быстрый запуск';
      case WidgetType.featuredWorld:
        return 'Избранный мир';
    }
  }

  String _getWidgetSubtitle(WidgetType type) {
    switch (type) {
      case WidgetType.installedMods:
        return 'Список модов';
      case WidgetType.recentWorlds:
        return 'Сохранённые миры';
      case WidgetType.statistics:
        return 'Статистика игры';
      case WidgetType.quickLaunch:
        return 'Быстрый запуск';
      case WidgetType.featuredWorld:
        return 'Избранный мир';
    }
  }

  IconData _getWidgetIcon(WidgetType type) {
    switch (type) {
      case WidgetType.installedMods:
        return Icons.extension;
      case WidgetType.recentWorlds:
        return Icons.folder;
      case WidgetType.statistics:
        return Icons.bar_chart;
      case WidgetType.quickLaunch:
        return Icons.play_arrow;
      case WidgetType.featuredWorld:
        return Icons.explore;
    }
  }

  void _removeWidget(String widgetId) {
    setState(() {
      _widgets.removeWhere((w) => w.id == widgetId);
    });

    _saveWidgets();
  }

  Future<void> _openProfileDialog({Profile? initialProfile}) async {
    if (_settings == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала настрой папку Minecraft'),
        ),
      );
      return;
    }

    if (initialProfile != null) {
      setState(() {
        _editingProfile = initialProfile;
      });
      return;
    }

    final result = await showDialog<Profile>(
      context: context,
      builder: (context) => const CreateProfileDialog(),
    );

    if (!mounted || result == null) return;

    _addProfile(result);
  }

  Future<void> _saveEditedProfile(Profile result) async {
    final saved = await _updateProfile(result);

    if (saved && mounted) {
      setState(() {
        _editingProfile = null;
      });
    }
  }

  void _closeProfileEditor() {
    setState(() {
      _editingProfile = null;
    });
  }

  void _openProfileFolder(Profile profile) {
    final folderPath = _getInstanceFolder(profile);
    Process.run('explorer.exe', [folderPath]);
  }

  Future<String> _getPlayerNickname() async {
    final fallback = _settings?.nickname ?? 'Player';

    if (_settings == null) return fallback;

    try {
      final file = File(
        path.join(
          _settings!.minecraftFolder,
          'zembo_profile',
          'player.json',
        ),
      );

      if (await file.exists()) {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;

        final nickname = data['nickname'] as String?;

        if (nickname != null && nickname.trim().isNotEmpty) {
          return nickname.trim();
        }
      }
    } catch (e) {
      _updateLog('Не удалось прочитать локальный профиль: $e');
    }

    return fallback;
  }

  Future<void> _saveDefaultJavaPath(String javaPath) async {
    if (_settings == null) return;
    final updated = LauncherSettings(
      nickname: _settings!.nickname,
      javaPath: javaPath,
      launcherFolder: _settings!.launcherFolder,
      minecraftFolder: _settings!.minecraftFolder,
    );
    await SettingsService.saveSettings(updated);
    if (!mounted) return;
    setState(() => _settings = updated);
    _updateLog(javaPath.isEmpty ? 'Java: включён автоматический выбор' : 'Java по умолчанию: $javaPath');
  }

  Future<void> _changeLaunchBehavior(String behavior) async {
    await SettingsService.saveLaunchBehavior(behavior);
    if (mounted) setState(() => _launchBehavior = behavior);
  }

  Future<void> _applyLaunchBehavior() async {
    switch (_launchBehavior) {
      case 'minimize':
        await windowManager.minimize();
        break;
      case 'tray':
        // Let Windows finish creating/focusing the Minecraft process before
        // hiding the launcher window.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await TrayService.instance.hideToTray();
        break;
      case 'nothing':
      default:
        break;
    }
  }

  Future<void> _launchMinecraft() async {
    if (_launchPhase == 'running') {
      _updateLog('Остановка Minecraft...');
      MinecraftLauncher.stop();
      MinecraftDownloader.cancelDownload();

      if (!mounted) return;

      setState(() {
        _launchPhase = 'idle';
        _launchLog = 'Minecraft остановлен';
      });

      return;
    }

    if (_settings == null || _selectedProfileId == null) {
      _updateLog('Ошибка: выберите сборку');
      return;
    }

    final matchingProfiles = _profiles.where(
      (p) => p.id == _selectedProfileId,
    );

    if (matchingProfiles.isEmpty) {
      _updateLog('Ошибка: выбранная сборка не найдена');
      return;
    }

    final profile = matchingProfiles.first;
    final instanceFolder = _getInstanceFolder(profile);
    final sharedFolder = _settings!.minecraftFolder;

    setState(() {
      _launchPhase = 'loading';
      _launchLog = 'Подготовка...';
    });

    await Future.delayed(const Duration(seconds: 3));

    if (!mounted || _launchPhase != 'loading') {
      if (mounted) {
        setState(() {
          _launchPhase = 'idle';
          _launchLog = 'Запуск отменён';
        });
      }
      return;
    }

    setState(() {
      _launchPhase = 'running';
      _launchLog = 'Запуск Minecraft...';
    });

    try {
      final javaPath = profile.javaPath.isNotEmpty
          ? profile.javaPath
          : _settings!.javaPath;

      // Java is resolved by MinecraftLauncher from the profile path or by
      // downloading the required runtime when the configured Java is missing/too old.
      if (javaPath.isNotEmpty && !File(javaPath).existsSync()) {
        _updateLog('Указанная Java не найдена. Попробую подобрать или скачать совместимую версию…');
      }

      _updateLog(
        'Скачивание базовой версии Minecraft ${profile.version}...',
      );

      final baseDownloaded = await MinecraftDownloader.downloadVersion(
        versionId: profile.version,
        sharedFolder: sharedFolder,
        onProgress: (status, progress) => _updateLog(status),
      );

      if (!baseDownloaded) {
        _updateLog('Ошибка скачивания базовой версии');
        if (mounted) setState(() => _launchPhase = 'idle');
        return;
      }

      String versionIdToLaunch = profile.version;

      if (profile.loader == 'Fabric') {
        _updateLog('Проверка Fabric...');

        final loaderVersion =
            await FabricInstaller.getLatestLoaderVersion();

        versionIdToLaunch =
            'fabric-loader-$loaderVersion-${profile.version}';

        final fabricInstalled = await FabricInstaller.installFabric(
          minecraftVersion: profile.version,
          sharedFolder: sharedFolder,
          onProgress: (status, progress) => _updateLog(status),
        );

        if (!fabricInstalled) {
          _updateLog('Ошибка установки Fabric');
          if (mounted) setState(() => _launchPhase = 'idle');
          return;
        }
      } else if (profile.loader == 'Forge') {
        _updateLog('Проверка Forge...');

        final forgeVersion = profile.forgeVersion.isNotEmpty
            ? profile.forgeVersion
            : await ForgeInstaller.getLatestForgeVersion(profile.version);

        if (forgeVersion == null || forgeVersion.isEmpty) {
          _updateLog(
            'Ошибка: Forge не найден для версии ${profile.version}',
          );
          if (mounted) setState(() => _launchPhase = 'idle');
          return;
        }

        versionIdToLaunch = 'forge-$forgeVersion';
        _updateLog('Версия Forge: $forgeVersion');

        final clientJarPath = path.join(
          sharedFolder,
          'libraries',
          'net',
          'minecraftforge',
          'forge',
          forgeVersion,
          'forge-$forgeVersion-client.jar',
        );

        if (!File(clientJarPath).existsSync()) {
          _updateLog('Скачивание Forge installer...');

          final installerDownloaded =
              await ForgeInstaller.downloadInstaller(
            forgeVersion: forgeVersion,
            sharedFolder: sharedFolder,
            onProgress: (status, progress) => _updateLog(status),
          );

          if (!installerDownloaded) {
            _updateLog('Ошибка скачивания Forge installer');
            if (mounted) setState(() => _launchPhase = 'idle');
            return;
          }

          _updateLog('Установка Forge...');

          final forgeInstalled = await ForgeInstaller.installForge(
            forgeVersion: forgeVersion,
            sharedFolder: sharedFolder,
            javaPath: javaPath,
            onProgress: (status, progress) => _updateLog(status),
          );

          if (!forgeInstalled) {
            _updateLog('Ошибка установки Forge');
            if (mounted) setState(() => _launchPhase = 'idle');
            return;
          }
        } else {
          _updateLog('Forge уже установлен');
        }
      }

      _updateLog('Запуск Minecraft...');

      final savedAccount = await ElyByAuthService.loadAccount();
      final account = await ElyByAuthService.ensureValidAccount();
      if (savedAccount != null && account == null) {
        _updateLog('⚠️ Ely.by: токен недействителен — войди в аккаунт заново (профиль игрока). Запускаю без Ely.by.');
      }

      String? authlibInjectorPath;

      if (account != null) {
        _updateLog('Подготовка авторизации Ely.by...');
        try {
          authlibInjectorPath =
              await ElyByAuthService.ensureAuthlibInjector(sharedFolder);
        } catch (e) {
          _updateLog('⚠️ Ely.by: $e — скины могут не отображаться.');
        }

        // На серверах в офлайн-режиме authlib-injector скины не получает:
        // для сборок с модами ставим CustomSkinLoader и подключаем к нему Ely.by.
        if (profile.loader != 'Vanilla') {
          await SkinModService.ensureCustomSkinLoader(
            gameDirectory: instanceFolder,
            minecraftVersion: profile.version,
            loader: profile.loader,
            onLog: _updateLog,
          );
          await SkinModService.ensureElyByInConfig(instanceFolder, onLog: _updateLog);
        }
      }

      final guard = await ModGuardService.prepare(
        sharedFolder: sharedFolder,
        instanceFolder: instanceFolder,
        log: _updateLog,
      );

      final result = await MinecraftLauncher.launch(
        javaPath: javaPath,
        sharedFolder: sharedFolder,
        instanceFolder: instanceFolder,
        versionId: versionIdToLaunch,
        username: account?.username ?? await _getPlayerNickname(),
        ramMb: profile.ram * 1024,
        loader: profile.loader,
        accessToken: account?.accessToken,
        authUuid: account?.uuid,
        authlibInjectorPath: authlibInjectorPath,
        guardAgentJarPath: guard?.jar,
        guardConfigPath: guard?.config,
        onProcessStarted: _applyLaunchBehavior,
      );

      // When the user chose "Свернуть в трей", keep the launcher hidden while
      // Minecraft is running, then bring it back once the game process exits.
      if (_launchBehavior == 'tray') {
        await TrayService.instance.showWindow();
      }

      if (result['success'] == true) {
        _updateLog('Minecraft завершил работу.');
      } else {
        _updateLog('Ошибка: ${result['error']}');
      }

      if (mounted) setState(() => _launchPhase = 'idle');
    } catch (e) {
      _updateLog('Ошибка: $e');
      if (mounted) setState(() => _launchPhase = 'idle');
    }
  }

  Future<void> _resetSettings() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF111C16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text(
          'Сбросить настройки?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Это вернёт вас к экрану установки.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Отмена',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Сбросить',
              style: TextStyle(color: _green),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await SettingsService.resetSetup();

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => SetupWizard(
            onSetupComplete: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => const LauncherScreen(),
                ),
              );
            },
          ),
        ),
      );
    }
  }

  Profile? _getSelectedProfile() {
    if (_selectedProfileId == null) return null;

    for (final profile in _profiles) {
      if (profile.id == _selectedProfileId) return profile;
    }

    return null;
  }

  @override
  void dispose() {
    DiscordActivityService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedProfile = _getSelectedProfile();

    return Scaffold(
      backgroundColor: _background,
      body: Row(
        children: [
          Container(
            width: 76,
            decoration: const BoxDecoration(
              color: _surface,
              border: Border(
                right: BorderSide(color: _borderColor),
              ),
            ),
            child: NavigationRailWidget(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() => _selectedIndex = index);
              },
              onResetSettings: _resetSettings,
              isEditMode: _isEditMode,
              onToggleEditMode: () {
                setState(() => _isEditMode = !_isEditMode);
              },
            ),
          ),
          Expanded(
            child: _selectedIndex == 1 && _settings != null && _editingProfile == null
                ? ModpackStoreScreen(
                    minecraftFolder: _settings!.minecraftFolder,
                    onInstalled: (profile) {
                      _addProfile(profile);
                      setState(() => _selectedIndex = 0);
                    },
                  )
                : _selectedIndex == 3
                    ? SettingsScreen(
                        discordActivityEnabled: _discordActivityEnabled,
                        javaPath: _settings?.javaPath ?? '',
                        onJavaPathChanged: _saveDefaultJavaPath,
                        launchBehavior: _launchBehavior,
                        onLaunchBehaviorChanged: _changeLaunchBehavior,
                        onDiscordActivityChanged: (enabled) async {
                          await SettingsService.saveDiscordActivityEnabled(enabled);
                          await DiscordActivityService.setEnabled(enabled);
                          if (!mounted) return;
                          setState(() => _discordActivityEnabled = enabled);
                        },
                      )
                : _editingProfile != null && _settings != null
                ? ProfileSettingsScreen(
                    key: ValueKey('edit_${_editingProfile!.id}'),
                    initialProfile: _editingProfile!,
                    minecraftFolder: _settings!.minecraftFolder,
                    onSave: _saveEditedProfile,
                    onCancel: _closeProfileEditor,
                  )
                : _selectedIndex == 2
                    ? _settings == null
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: _green,
                            ),
                          )
                        : PlayerProfileScreen(
                            minecraftFolder: _settings!.minecraftFolder,
                            initialNickname: _settings!.nickname,
                            onNicknameChanged: (_) {},
                          )
                    : _buildMainContent(selectedProfile),
          ),
          if (_selectedIndex != 2 && _selectedIndex != 1 && _selectedIndex != 3 && _editingProfile == null)
            Container(
              width: 292,
              decoration: const BoxDecoration(
                color: _surface,
                border: Border(
                  left: BorderSide(color: _borderColor),
                ),
              ),
              child: SettingsPanelWidget(
                onLaunch: _launchMinecraft,
                launchPhase: _launchPhase,
                selectedProfile: selectedProfile,
                settings: _settings,
                isEditMode: _isEditMode,
                onAddWidget: _showAddWidgetDialog,
                onAddProfile: () => _openProfileDialog(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMainContent(Profile? selectedProfile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 52,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      if (_update != null) _buildUpdateBanner(),
                      _buildHeroBanner(),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Твои сборки',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF17251D),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              '${_profiles.length}',
                              style: const TextStyle(
                                color: _green,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () => _openProfileDialog(),
                            icon: const Icon(Icons.add, size: 17),
                            label: const Text('Новая сборка'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _green,
                              side: const BorderSide(
                                color: Color(0xFF31583D),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 13,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_profiles.isEmpty)
                        _buildEmptyProfiles()
                      else
                        LayoutBuilder(
                          builder: (context, gridConstraints) {
                            final width = gridConstraints.maxWidth;
                            final columns = width >= 760
                                ? 4
                                : width >= 480
                                    ? 2
                                    : 1;

                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _profiles.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                mainAxisExtent: 166,
                              ),
                              itemBuilder: (context, index) {
                                return _buildProfileCard(_profiles[index]);
                              },
                            );
                          },
                        ),
                      if (_widgets.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Быстрый доступ',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _showAddWidgetDialog,
                              icon: const Icon(Icons.add, size: 17),
                              label: const Text('Добавить'),
                              style: TextButton.styleFrom(
                                foregroundColor: _green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, gridConstraints) {
                            final columns =
                                gridConstraints.maxWidth >= 800 ? 3 : 2;

                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _widgets.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 15,
                                mainAxisSpacing: 15,
                                mainAxisExtent: 145,
                              ),
                              itemBuilder: (context, index) {
                                return _buildWidgetCard(_widgets[index]);
                              },
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      height: 196,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF10251C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1D4A36), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D878).withOpacity(0.07),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/zembo_banner.png',
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
            errorBuilder: (context, error, stackTrace) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF123A2A), Color(0xFF071A1A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: [0.0, 0.43, 0.76, 1.0],
                colors: [
                  Color(0xF5091714),
                  Color(0xD9091714),
                  Color(0x65091714),
                  Color(0x12091714),
                ],
              ),
            ),
          ),
          // Visible voxel/pixel accents: block clusters inspired by Minecraft terrain.
          const Positioned(
            right: 18,
            top: 12,
            child: IgnorePointer(
              child: _VoxelCluster(opacity: 0.58, scale: 1.0),
            ),
          ),
          const Positioned(
            right: 78,
            bottom: 12,
            child: IgnorePointer(
              child: _VoxelCluster(opacity: 0.42, scale: 0.72),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 20, 18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4EE879),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            Icons.grass_rounded,
                            color: Color(0xFF092014),
                            size: 23,
                          ),
                        ),
                        const SizedBox(width: 11),
                        const Flexible(
                          child: Text(
                            'Zembo Launcher',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(
                      'Твой мир. Твои правила.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.82),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _getSelectedProfile() == null ||
                                  _launchPhase == 'loading'
                              ? null
                              : _launchMinecraft,
                          icon: Icon(
                            _launchPhase == 'running'
                                ? Icons.stop_rounded
                                : Icons.play_arrow_rounded,
                            size: 22,
                          ),
                          label: Text(
                            _launchPhase == 'running' ? 'Остановить' : 'Играть',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF20B957),
                            foregroundColor: const Color(0xFF04170B),
                            disabledBackgroundColor: const Color(0xFF355442),
                            disabledForegroundColor: Colors.white54,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 21,
                              vertical: 11,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        Container(
                          constraints: const BoxConstraints(maxWidth: 250),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xC90A1912),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF31513B),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: _launchPhase == 'running'
                                      ? const Color(0xFF4EE879)
                                      : _launchPhase == 'loading'
                                          ? const Color(0xFFFFC857)
                                          : const Color(0xFF7C8D82),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _launchLog,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFD0DAD2),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedProfile(Profile? profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1B422C),
            Color(0xFF10291D),
            Color(0xFF101B15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFF356D45)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1D7A3C).withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showIcon = constraints.maxWidth > 520;

          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _green.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'ВЫБРАННАЯ СБОРКА',
                        style: TextStyle(
                          color: Color(0xFF75F292),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 17),
                    Text(
                      profile?.name ?? 'Сборка не выбрана',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      profile == null
                          ? 'Создай сборку, чтобы начать играть.'
                          : '${profile.loader}  •  Minecraft ${profile.version}  •  ${profile.ram} GB RAM',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.65),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 21),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ElevatedButton.icon(
                          onPressed:
                              profile == null ? null : _launchMinecraft,
                          icon: Icon(
                            _launchPhase == 'running'
                                ? Icons.stop_rounded
                                : _launchPhase == 'loading'
                                    ? Icons.hourglass_top
                                    : Icons.play_arrow_rounded,
                          ),
                          label: Text(
                            _launchPhase == 'running'
                                ? 'Остановить'
                                : _launchPhase == 'loading'
                                    ? 'Подготовка...'
                                    : 'Играть',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _green,
                            foregroundColor: const Color(0xFF08140C),
                            disabledBackgroundColor:
                                const Color(0xFF35463A),
                            disabledForegroundColor: Colors.white54,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 15,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _openProfileDialog(),
                          icon: const Icon(Icons.add, size: 17),
                          label: const Text('Создать сборку'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withOpacity(0.2),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 15,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (showIcon) ...[
                const SizedBox(width: 20),
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: _green.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _green.withOpacity(0.18),
                    ),
                  ),
                  child: Icon(
                    profile == null
                        ? Icons.videogame_asset_outlined
                        : _getBlockIcon(profile.icon),
                    color: profile == null
                        ? _green
                        : _getBlockColor(profile.icon),
                    size: 56,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyProfiles() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: _borderColor),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            color: _green,
            size: 42,
          ),
          SizedBox(height: 12),
          Text(
            'Пока нет сборок',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Создай свою первую сборку, чтобы она появилась здесь.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWidgetCard(WidgetItem widget) {
    return ShakeWidget(
      key: ValueKey('widget_${widget.id}'),
      isShaking: _isEditMode,
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderColor),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    widget.icon,
                    color: _green,
                    size: 22,
                  ),
                ),
                const Spacer(),
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8A9B90),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            if (_isEditMode)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  tooltip: 'Удалить виджет',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.close,
                    color: Color(0xFFFF7373),
                    size: 18,
                  ),
                  onPressed: () => _removeWidget(widget.id),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(Profile profile) {
    final isSelected = _selectedProfileId == profile.id;
    final blockIcon = _getBlockIcon(profile.icon);
    final blockColor = _getBlockColor(profile.icon);

    return ShakeWidget(
      key: ValueKey('profile_${profile.id}'),
      isShaking: _isEditMode,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _selectProfile(profile.id),
          borderRadius: BorderRadius.circular(9),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF14291B)
                  : _cardColor,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: isSelected ? _green : _borderColor,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: 8,
                  bottom: 7,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: isSelected ? 0.42 : 0.25,
                      child: const _VoxelCluster(opacity: 1, scale: 0.78),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: blockColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: blockColor.withOpacity(0.35),
                            ),
                          ),
                          child: Icon(
                            blockIcon,
                            color: blockColor,
                            size: 21,
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A2A20),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              profile.loader,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _mutedGreen,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            profile.version,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF8A9B90),
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.memory,
                          color: Color(0xFF8A9B90),
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${profile.ram} GB',
                          style: const TextStyle(
                            color: Color(0xFFB5C2B9),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 0,
                  right: 34,
                  child: _buildCardIconButton(
                    icon: Icons.folder_open_outlined,
                    tooltip: 'Открыть папку сборки',
                    onPressed: () => _openProfileFolder(profile),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: _buildCardIconButton(
                    icon: Icons.edit_outlined,
                    tooltip: 'Изменить сборку',
                    onPressed: () {
                      _openProfileDialog(initialProfile: profile);
                    },
                  ),
                ),
                if (_isEditMode)
                  Positioned(
                    top: 0,
                    left: 48,
                    child: _buildCardIconButton(
                      icon: Icons.delete_outline,
                      tooltip: 'Удалить сборку',
                      color: const Color(0xFFFF7373),
                      onPressed: () => _deleteProfile(profile.id),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color color = const Color(0xFFB5C2B9),
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          width: 29,
          height: 29,
          decoration: BoxDecoration(
            color: const Color(0xFF1A2920),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0xFF2A4031)),
          ),
          child: Icon(
            icon,
            color: color,
            size: 16,
          ),
        ),
      ),
    );
  }

  IconData _getBlockIcon(String iconName) {
    switch (iconName) {
      case 'stone':
        return Icons.square;
      case 'grass':
        return Icons.landscape;
      case 'diamond':
        return Icons.diamond;
      case 'lava':
        return Icons.local_fire_department;
      case 'water':
        return Icons.water_drop;
      case 'ice':
        return Icons.ac_unit;
      case 'wood':
        return Icons.park;
      case 'gold':
        return Icons.bolt;
      case 'obsidian':
        return Icons.hexagon;
      case 'sand':
        return Icons.grain;
      default:
        return Icons.square;
    }
  }

  Color _getBlockColor(String iconName) {
    switch (iconName) {
      case 'stone':
        return const Color(0xFF808080);
      case 'grass':
        return const Color(0xFF43E477);
      case 'diamond':
        return const Color(0xFF00BCD4);
      case 'lava':
        return const Color(0xFFFF5722);
      case 'water':
        return const Color(0xFF2196F3);
      case 'ice':
        return const Color(0xFFB3E5FC);
      case 'wood':
        return const Color(0xFF795548);
      case 'gold':
        return const Color(0xFFFFC107);
      case 'obsidian':
        return const Color(0xFF7C6BC4);
      case 'sand':
        return const Color(0xFFFFE082);
      default:
        return const Color(0xFF808080);
    }
  }
}

class WidgetItem {
  final String id;
  final WidgetType type;
  final String title;
  final String subtitle;
  final IconData icon;

  WidgetItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

enum WidgetType {
  featuredWorld,
  installedMods,
  recentWorlds,
  statistics,
  quickLaunch,
}

class ShakeWidget extends StatefulWidget {
  final Widget child;
  final bool isShaking;

  const ShakeWidget({
    super.key,
    required this.child,
    required this.isShaking,
  });

  @override
  State<ShakeWidget> createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<ShakeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );

    _animation = Tween<double>(
      begin: -2.0,
      end: 2.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    if (widget.isShaking) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(ShakeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isShaking && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isShaking && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(
            widget.isShaking ? _animation.value : 0.0,
            0,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Crisp square voxel motif used as a decorative accent on the home screen.
class _VoxelCluster extends StatelessWidget {
  final double opacity;
  final double scale;

  const _VoxelCluster({required this.opacity, required this.scale});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF55E878);
    const deep = Color(0xFF267A42);
    return Opacity(
      opacity: opacity,
      child: SizedBox(
        width: 72 * scale,
        height: 58 * scale,
        child: Stack(
          children: [
            Positioned(
              right: 0, bottom: 0,
              child: _VoxelSquare(size: 22 * scale, color: deep),
            ),
            Positioned(
              right: 23 * scale, bottom: 0,
              child: _VoxelSquare(size: 13 * scale, color: green),
            ),
            Positioned(
              right: 0, bottom: 23 * scale,
              child: _VoxelSquare(size: 13 * scale, color: green),
            ),
            Positioned(
              right: 14 * scale, bottom: 36 * scale,
              child: _VoxelSquare(size: 9 * scale, color: deep),
            ),
            Positioned(
              right: 36 * scale, bottom: 13 * scale,
              child: _VoxelSquare(size: 9 * scale, color: deep),
            ),
            Positioned(
              right: 45 * scale, bottom: 0,
              child: _VoxelSquare(size: 7 * scale, color: deep),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoxelSquare extends StatelessWidget {
  final double size;
  final Color color;

  const _VoxelSquare({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(
            color: const Color(0xFF8BF6A0).withOpacity(0.32),
            width: 0.7,
          ),
        ),
      );
}
