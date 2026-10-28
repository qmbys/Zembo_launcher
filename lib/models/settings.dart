class LauncherSettings {
  String nickname;
  String javaPath;
  String launcherFolder;
  String minecraftFolder;

  LauncherSettings({
    required this.nickname,
    required this.javaPath,
    required this.launcherFolder,
    required this.minecraftFolder,
  });

  Map<String, String> toJson() => {
    'nickname': nickname,
    'javaPath': javaPath,
    'launcherFolder': launcherFolder,
    'minecraftFolder': minecraftFolder,
  };

  factory LauncherSettings.fromJson(Map<String, String> json) {
    return LauncherSettings(
      nickname: json['nickname'] ?? '',
      javaPath: json['javaPath'] ?? '',
      launcherFolder: json['launcherFolder'] ?? '',
      minecraftFolder: json['minecraftFolder'] ?? '',
    );
  }
}