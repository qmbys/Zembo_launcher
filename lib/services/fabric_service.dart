import 'dart:convert';
import 'package:http/http.dart' as http;

class FabricService {
  static const String metaUrl = 'https://meta.fabricmc.net/v2/versions';

  // Получить последнюю версию Fabric Loader
  static Future<String?> getLatestLoaderVersion() async {
    try {
      final response = await http.get(Uri.parse('$metaUrl/loader'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List && data.isNotEmpty) {
          return data[0]['version'];
        }
      }
    } catch (e) {
      print('Ошибка при получении версии Fabric: $e');
    }
    return null;
  }

  // Получить URL для скачивания Fabric Installer
  static String getInstallerUrl(String loaderVersion, String minecraftVersion) {
    return 'https://maven.fabricmc.net/net/fabricmc/fabric-installer/0.11.2/fabric-installer-0.11.2.jar';
  }
}