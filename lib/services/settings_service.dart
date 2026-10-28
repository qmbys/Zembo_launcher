import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/settings.dart';

class SettingsService {
  static const String _settingsKey = 'launcher_settings_v2'; // <-- изменили
  static const String _isSetupKey = 'is_setup_completed_v2'; // <-- изменили
  static const String _discordActivityKey = 'discord_activity_enabled_v2';
  static const String _launchBehaviorKey = 'minecraft_launch_behavior_v1';

  static Future<String> loadLaunchBehavior() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_launchBehaviorKey) ?? 'nothing';
    return const {'nothing', 'tray', 'minimize'}.contains(value) ? value : 'nothing';
  }

  static Future<void> saveLaunchBehavior(String behavior) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_launchBehaviorKey, behavior);
  }


  static Future<bool> loadDiscordActivityEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_discordActivityKey) ?? true;
  }

  static Future<void> saveDiscordActivityEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_discordActivityKey, enabled);
  }

  static Future<bool> isSetupCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isSetupKey) ?? false;
  }

  static Future<void> saveSettings(LauncherSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
    await prefs.setBool(_isSetupKey, true);
  }

  static Future<LauncherSettings?> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_settingsKey);
    if (jsonStr == null) return null;
    
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    return LauncherSettings.fromJson(
      json.map((key, value) => MapEntry(key, value.toString())),
    );
  }

  static Future<void> resetSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_isSetupKey);
    await prefs.remove(_settingsKey);
  }
}