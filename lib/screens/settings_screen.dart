import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

const _bg = Color(0xFF080F0D);
const _card = Color(0xFF0F1A14);
const _border = Color(0xFF23382B);
const _green = Color(0xFF43E477);

/// Main launcher settings page. Kept intentionally small so more settings
/// can be added here later without changing the navigation rail.
class SettingsScreen extends StatelessWidget {
  final bool discordActivityEnabled;
  final ValueChanged<bool> onDiscordActivityChanged;
  final String javaPath;
  final ValueChanged<String> onJavaPathChanged;
  final String launchBehavior;
  final ValueChanged<String> onLaunchBehaviorChanged;

  const SettingsScreen({
    super.key,
    required this.discordActivityEnabled,
    required this.onDiscordActivityChanged,
    required this.javaPath,
    required this.onJavaPathChanged,
    required this.launchBehavior,
    required this.onLaunchBehaviorChanged,
  });

  Future<void> _chooseJava(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Выберите java.exe',
      type: FileType.custom,
      allowedExtensions: Platform.isWindows ? ['exe'] : null,
      allowMultiple: false,
    );
    final selected = result?.files.single.path;
    if (selected == null) return;
    final name = selected.split(RegExp(r'[/\\]')).last.toLowerCase();
    if (Platform.isWindows && name != 'java.exe') {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Выбери именно java.exe')),
        );
      }
      return;
    }
    onJavaPathChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(34, 30, 34, 32),
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _green.withOpacity(.12),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: _green.withOpacity(.25)),
                  ),
                  child: const Icon(Icons.settings_rounded, color: _green, size: 25),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Настройки', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.6)),
                      SizedBox(height: 4),
                      Text('Персонализация Zembo Launcher', style: TextStyle(color: Color(0xFF91A497), fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            const Text('JAVA И ЗАПУСК', style: TextStyle(color: Color(0xFF8EA394), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(18), border: Border.all(color: _border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Путь к Java', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 5),
                const Text('Этот путь используется как Java по умолчанию. Для отдельных сборок может быть задан свой путь.', style: TextStyle(color: Color(0xFF91A497), fontSize: 12, height: 1.4)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13), decoration: BoxDecoration(color: const Color(0xFF0B1510), borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)), child: Text(javaPath.isEmpty ? 'Java будет выбрана автоматически' : javaPath, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFFD7E5DA))))),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(onPressed: () => _chooseJava(context), icon: const Icon(Icons.folder_open_rounded, size: 18), label: const Text('Выбрать')),
                ]),
                if (javaPath.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => onJavaPathChanged(''), child: const Text('Автоматический выбор Java'))),
                ],
                const SizedBox(height: 18),
                const Text('После запуска Minecraft', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 5),
                const Text('Что делать с окном лаунчера, когда игра успешно запустится.', style: TextStyle(color: Color(0xFF91A497), fontSize: 12, height: 1.4)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: launchBehavior,
                  decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  items: const [
                    DropdownMenuItem(value: 'nothing', child: Text('Ничего не делать')),
                    DropdownMenuItem(value: 'tray', child: Text('Свернуть в трей')),
                    DropdownMenuItem(value: 'minimize', child: Text('Свернуть в панель задач')),
                  ],
                  onChanged: (value) { if (value != null) onLaunchBehaviorChanged(value); },
                ),
              ]),
            ),
            const SizedBox(height: 30),
            const Text('ИНТЕГРАЦИИ', style: TextStyle(color: Color(0xFF8EA394), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(color: const Color(0xFF5865F2).withOpacity(.16), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.sports_esports_rounded, color: Color(0xFF8D97FF), size: 27),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Активность в Discord', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 5),
                        Text(
                          discordActivityEnabled ? 'Переключатель включён' : 'Показывать Zembo Launcher в профиле Discord',
                          style: const TextStyle(color: Color(0xFF91A497), fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Switch.adaptive(
                    value: discordActivityEnabled,
                    activeColor: _green,
                    onChanged: onDiscordActivityChanged,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
