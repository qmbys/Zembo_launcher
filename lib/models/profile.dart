
class Profile {
  final String id;
  final String name;
  final String version;
  final String loader;
  final int ram;
  final String icon;
  final String javaPath;
  final String forgeVersion;

  /// Путь к папке конкретной сборки Minecraft.
  final String gameDir;

  Profile({
    required this.id,
    required this.name,
    required this.version,
    required this.loader,
    required this.ram,
    required this.icon,
    this.javaPath = '',
    this.forgeVersion = '',
    this.gameDir = '',
  });

  Profile copyWith({
    String? id,
    String? name,
    String? version,
    String? loader,
    int? ram,
    String? icon,
    String? javaPath,
    String? forgeVersion,
    String? gameDir,
  }) {
    return Profile(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      loader: loader ?? this.loader,
      ram: ram ?? this.ram,
      icon: icon ?? this.icon,
      javaPath: javaPath ?? this.javaPath,
      forgeVersion: forgeVersion ?? this.forgeVersion,
      gameDir: gameDir ?? this.gameDir,
    );
  }

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '',
      loader: json['loader'] as String? ?? 'Vanilla',
      ram: json['ram'] as int? ?? 4,
      icon: json['icon'] as String? ?? 'stone',
      javaPath: json['javaPath'] as String? ?? '',
      forgeVersion: json['forgeVersion'] as String? ?? '',
      gameDir: json['gameDir'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'loader': loader,
      'ram': ram,
      'icon': icon,
      'javaPath': javaPath,
      'forgeVersion': forgeVersion,
      'gameDir': gameDir,
    };
  }
}
