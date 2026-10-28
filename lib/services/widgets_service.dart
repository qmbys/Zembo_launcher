import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

class WidgetsService {
  static Future<List<Map<String, dynamic>>> loadWidgets(String sharedFolder) async {
    final widgetsFile = File(path.join(sharedFolder, 'widgets.json'));
    if (!widgetsFile.existsSync()) {
      return [];
    }
    
    try {
      final content = widgetsFile.readAsStringSync();
      final List<dynamic> data = json.decode(content);
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  static Future<void> saveWidgets(String sharedFolder, List<Map<String, dynamic>> widgets) async {
    final widgetsFile = File(path.join(sharedFolder, 'widgets.json'));
    await widgetsFile.parent.create(recursive: true);
    await widgetsFile.writeAsString(json.encode(widgets));
  }
}