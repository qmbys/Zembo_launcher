import 'dart:async';

import 'package:dart_discord_presence/dart_discord_presence.dart';

/// Discord Rich Presence integration for Zembo Launcher.
class DiscordActivityService {
  DiscordActivityService._();

  static const String applicationId = '1564351624212779038';
  static const String _logoAssetKey = 'zembo_logo';

  static DiscordRPC? _rpc;
  static bool _enabled = false;
  static bool _starting = false;
  static Timer? _retryTimer;

  static Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    if (!enabled) {
      _retryTimer?.cancel();
      _retryTimer = null;
      await stop();
      return;
    }

    // Try immediately, then keep retrying in case Discord starts after Zembo.
    await start();
    _retryTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_enabled || _rpc != null || _starting) return;
      start();
    });
  }

  static Future<void> start() async {
    if (!_enabled || _starting || !DiscordRPC.isAvailable) return;
    _starting = true;
    try {
      final rpc = DiscordRPC();
      await rpc.initialize(applicationId);
      _rpc = rpc;
      await updateMainMenu();
    } catch (_) {
      // Discord may not be running. The launcher should keep working normally.
      _rpc = null;
    } finally {
      _starting = false;
    }
  }

  static Future<void> updateMainMenu() async {
    if (!_enabled) return;
    if (_rpc == null) {
      await start();
      return;
    }
    try {
      await _rpc!.setPresence(
        DiscordPresence(
          details: 'В лаунчере Minecraft',
          state: 'Выбирает сборку и моды',
          largeAsset: const DiscordAsset(
            key: _logoAssetKey,
            text: 'Zembo Launcher',
          ),
        ),
      );
    } catch (_) {
      // The RPC connection can fail transiently; let the retry loop reconnect.
      final failedRpc = _rpc;
      _rpc = null;
      try {
        await failedRpc?.dispose();
      } catch (_) {}
    }
  }

  static Future<void> stop() async {
    final rpc = _rpc;
    _rpc = null;
    if (rpc == null) return;
    try {
      await rpc.dispose();
    } catch (_) {}
  }
}
