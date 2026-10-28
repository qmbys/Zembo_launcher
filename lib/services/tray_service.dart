import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Owns the notification-area icon and the application's close/exit lifecycle.
class TrayService with TrayListener, WindowListener {
  TrayService._();
  static final TrayService instance = TrayService._();

  bool _initialized = false;
  bool _quitting = false;
  Future<void>? _initializing;

  Future<void> initialize() async {
    if (!Platform.isWindows || _initialized) return;
    if (_initializing != null) return _initializing;
    _initializing = _initializeInternal();
    try {
      await _initializing;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initializeInternal() async {
    trayManager.addListener(this);
    windowManager.addListener(this);
    // Intercept the window's X button so we can remove the tray icon and exit
    // the process instead of leaving a hidden launcher running in background.
    await windowManager.setPreventClose(true);

    try {
      final iconPath = await _findIconPath();
      if (iconPath == null) {
        debugPrint('[Tray] app_icon.ico не найден — значок трея не установлен.');
      } else {
        await trayManager.setIcon(iconPath);
        await trayManager.setToolTip('Zembo Launcher');
        await trayManager.setContextMenu(Menu(items: [
          MenuItem(key: 'open', label: 'Открыть Zembo Launcher'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Выход'),
        ]));
        _initialized = true;
        debugPrint('[Tray] Значок установлен: $iconPath');
      }
    } catch (e, st) {
      // Keep the launcher usable, but don't hide the reason the tray failed.
      debugPrint('[Tray] Не удалось инициализировать системный трей: $e\n$st');
    }
  }

  Future<String?> _findIconPath() async {
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      '$executableDir${Platform.pathSeparator}app_icon.ico',
      '${Directory.current.path}${Platform.pathSeparator}windows${Platform.pathSeparator}runner${Platform.pathSeparator}resources${Platform.pathSeparator}app_icon.ico',
    ];

    for (final candidate in candidates) {
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }

  Future<void> hideToTray() async {
    await initialize();
    if (!_initialized) {
      // Never pretend the window was sent to the tray if no tray icon exists.
      debugPrint('[Tray] Скрытие отменено: значок системного трея не готов.');
      return;
    }
    try {
      await windowManager.setSkipTaskbar(true);
      await windowManager.hide();
      debugPrint('[Tray] Окно скрыто в системный трей.');
    } catch (e, st) {
      debugPrint('[Tray] Не удалось скрыть окно: $e\n$st');
    }
  }

  /// Restores the launcher window after Minecraft exits or when opened from tray.
  Future<void> showWindow() async {
    if (!Platform.isWindows) return;
    try {
      await windowManager.setSkipTaskbar(false);
      await windowManager.show();
      await windowManager.restore();
      await windowManager.focus();
      debugPrint('[Tray] Окно лаунчера восстановлено.');
    } catch (e, st) {
      debugPrint('[Tray] Не удалось восстановить окно: $e\n$st');
    }
  }

  @override
  void onTrayIconMouseDown() async {
    // Left click opens the launcher.
    await showWindow();
  }

  @override
  void onTrayIconRightMouseDown() async {
    // Windows does not always open custom tray menus automatically.
    try {
      await trayManager.popUpContextMenu();
    } catch (e) {
      debugPrint('[Tray] Не удалось открыть контекстное меню: $e');
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'open') {
      await showWindow();
    } else if (menuItem.key == 'quit') {
      await quit();
    }
  }

  @override
  void onWindowClose() async {
    await quit();
  }

  /// Removes the notification icon and terminates the process completely.
  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
      await trayManager.destroy();
    } catch (e) {
      debugPrint('[Tray] Ошибка при удалении значка: $e');
    }
    exit(0);
  }
}
