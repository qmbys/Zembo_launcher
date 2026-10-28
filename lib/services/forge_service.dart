import 'dart:convert';
import 'package:http/http.dart' as http;

class ForgeService {
  static const String promotionsUrl = 'https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json';

  // Получить последнюю версию Forge для указанной версии Minecraft
  static Future<String?> getLatestForgeVersion(String minecraftVersion) async {
    try {
      final response = await http.get(Uri.parse(promotionsUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final promos = data['promos'] as Map<String, dynamic>;
        
        // Ищем recommended или latest
        final key = '$minecraftVersion-recommended';
        final keyLatest = '$minecraftVersion-latest';
        
        if (promos.containsKey(key)) {
          return promos[key];
        } else if (promos.containsKey(keyLatest)) {
          return promos[keyLatest];
        }
      }
    } catch (e) {
      print('Ошибка при получении версии Forge: $e');
    }
    return null;
  }

  // Получить URL для скачивания Forge installer
  static String getInstallerUrl(String minecraftVersion, String forgeVersion) {
    return 'https://maven.minecraftforge.net/net/minecraftforge/forge/$minecraftVersion-$forgeVersion/forge-$minecraftVersion-$forgeVersion-installer.jar';
  }
}