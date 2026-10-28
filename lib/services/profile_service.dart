import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/profile.dart';

class ProfileService {
  static const String profilesFileName = 'profiles.json';
  
  // Сохранить все профили в файл
  static Future<void> saveProfiles(List<Profile> profiles, String minecraftFolder) async {
    try {
      final profilesPath = path.join(minecraftFolder, profilesFileName);
      final file = File(profilesPath);
      await file.parent.create(recursive: true);
      
      final profilesJson = profiles.map((p) => {
        'id': p.id,
        'name': p.name,
        'loader': p.loader,
        'version': p.version,
        'ram': p.ram,
        'icon': p.icon,
        'javaPath': p.javaPath,
      }).toList();
      
      await file.writeAsString(json.encode(profilesJson));
      print('[ProfileService] Сохранено ${profiles.length} профилей');
    } catch (e) {
      print('[ProfileService] Ошибка сохранения: $e');
    }
  }
  
  // Загрузить профили из файла
  static Future<List<Profile>> loadProfiles(String minecraftFolder) async {
    try {
      final profilesPath = path.join(minecraftFolder, profilesFileName);
      final file = File(profilesPath);
      
      if (!await file.exists()) {
        print('[ProfileService] Файл профилей не найден');
        return [];
      }
      
      final jsonString = await file.readAsString();
      final profilesJson = json.decode(jsonString) as List;
      
      final profiles = profilesJson.map((p) => Profile(
        id: p['id'],
        name: p['name'],
        loader: p['loader'],
        version: p['version'],
        ram: p['ram'],
        icon: p['icon'],
        javaPath: p['javaPath'] ?? '',
      )).toList();
      
      print('[ProfileService] Загружено ${profiles.length} профилей');
      return profiles;
    } catch (e) {
      print('[ProfileService] Ошибка загрузки: $e');
      return [];
    }
  }
}