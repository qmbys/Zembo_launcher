import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/profile.dart';
import '../services/java_runtime_service.dart';

class ProfileSettingsScreen extends StatefulWidget {
  final Profile profile;
  final Function(Profile) onSave;

  const ProfileSettingsScreen({
    super.key,
    required this.profile,
    required this.onSave,
  });

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  static const _green = Color(0xFF43E477);
  static const _panel = Color(0xFF0D1713);
  static const _card = Color(0xFF111F17);
  static const _border = Color(0xFF26392D);
  static const _muted = Color(0xFF91A497);

  late final TextEditingController _nameController;
  late final TextEditingController _ramController;
  late final TextEditingController _javaPathController;
  late String _selectedIcon;
  List<JavaRuntimeCandidate> _javaCandidates = [];
  bool _scanningJava = false;
  String? _javaScanMessage;

  static const _icons = ['🌿', '⚔️', '🌲', '🔮', '🐉', '⭐', '🔥', '💎', '🧭', '🌙'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _ramController = TextEditingController(text: widget.profile.ram.toString());
    _javaPathController = TextEditingController(text: widget.profile.javaPath);
    _selectedIcon = widget.profile.icon.isEmpty ? '🌿' : widget.profile.icon;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ramController.dispose();
    _javaPathController.dispose();
    super.dispose();
  }

  Future<void> _selectJavaFolder() async {
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Выберите папку Java или общую папку со всеми версиями',
    );
    if (folder == null) return;
    setState(() {
      _scanningJava = true;
      _javaCandidates = [];
      _javaScanMessage = 'Сканирую папку и проверяю версии Java…';
    });
    final found = await JavaRuntimeService.scanDirectory(folder);
    if (!mounted) return;
    setState(() {
      _scanningJava = false;
      _javaCandidates = found;
      _javaScanMessage = found.isEmpty
          ? 'Не найден java.exe. Выбери папку, содержащую bin\\java.exe.'
          : 'Найдено версий Java: ${found.length}';
      if (found.isNotEmpty) _javaPathController.text = found.first.path;
    });
  }

  void _saveSettings() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажи название сборки')),
      );
      return;
    }
    final ram = int.tryParse(_ramController.text.trim());
    final updatedProfile = widget.profile.copyWith(
      name: name,
      ram: ram != null && ram >= 1 && ram <= 64 ? ram : widget.profile.ram,
      javaPath: _javaPathController.text.trim(),
      icon: _selectedIcon,
    );
    widget.onSave(updatedProfile);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080F0D),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: _green.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: _green.withValues(alpha: .28)),
                              ),
                              child: const Icon(Icons.tune_rounded, color: _green, size: 25),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Настройки сборки', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, fontSize: 26)),
                                  const SizedBox(height: 4),
                                  Text('Настрой параметры ${widget.profile.name} под себя', style: const TextStyle(color: _muted, fontSize: 13)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: _green.withValues(alpha: .1), borderRadius: BorderRadius.circular(10), border: Border.all(color: _green.withValues(alpha: .25))),
                              child: Text(widget.profile.version, style: const TextStyle(color: _green, fontWeight: FontWeight.w600, fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        LayoutBuilder(builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 680;
                          final general = _settingsCard(
                            title: 'Основное',
                            subtitle: 'Название и внешний вид сборки',
                            icon: Icons.grid_view_rounded,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _fieldLabel('Название сборки'),
                                TextField(
                                  controller: _nameController,
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                  decoration: const InputDecoration(hintText: 'Например, Survival+', prefixIcon: Icon(Icons.edit_rounded, size: 18)),
                                ),
                                const SizedBox(height: 20),
                                _fieldLabel('Иконка сборки'),
                                Wrap(
                                  spacing: 9,
                                  runSpacing: 9,
                                  children: _icons.map((icon) {
                                    final selected = icon == _selectedIcon;
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(11),
                                      onTap: () => setState(() => _selectedIcon = icon),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 140),
                                        width: 43,
                                        height: 43,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: selected ? _green.withValues(alpha: .14) : const Color(0xFF0A1510),
                                          borderRadius: BorderRadius.circular(11),
                                          border: Border.all(color: selected ? _green : _border, width: selected ? 1.5 : 1),
                                        ),
                                        child: Text(icon, style: const TextStyle(fontSize: 21)),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          );
                          final runtime = _settingsCard(
                            title: 'Производительность',
                            subtitle: 'Память и Java для Minecraft',
                            icon: Icons.memory_rounded,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _fieldLabel('Оперативная память (ГБ)'),
                                TextField(
                                  controller: _ramController,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                  decoration: const InputDecoration(prefixIcon: Icon(Icons.memory_rounded, size: 18), suffixText: 'GB'),
                                ),
                                const SizedBox(height: 7),
                                const Text('Обычно достаточно 4–6 ГБ для большинства сборок.', style: TextStyle(color: _muted, fontSize: 11, height: 1.4)),
                                const SizedBox(height: 20),
                                _fieldLabel('Путь к Java'),
                                TextField(
                                  controller: _javaPathController,
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                  decoration: InputDecoration(
                                    hintText: 'Автоматический выбор Java',
                                    prefixIcon: const Icon(Icons.terminal_rounded, size: 18),
                                    suffixIcon: IconButton(tooltip: 'Выбрать папку Java', onPressed: _selectJavaFolder, icon: const Icon(Icons.folder_open_rounded, color: _green, size: 19)),
                                  ),
                                ),
                                if (_scanningJava) ...[
                                  const SizedBox(height: 10),
                                  const LinearProgressIndicator(),
                                ],
                                if (_javaScanMessage != null) ...[
                                  const SizedBox(height: 8),
                                  Text(_javaScanMessage!, style: const TextStyle(color: _muted, fontSize: 11)),
                                ],
                                if (_javaCandidates.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    value: _javaCandidates.any((candidate) => candidate.path == _javaPathController.text)
                                        ? _javaPathController.text : _javaCandidates.first.path,
                                    isExpanded: true,
                                    decoration: const InputDecoration(labelText: 'Найденные версии Java'),
                                    items: _javaCandidates.map((candidate) => DropdownMenuItem<String>(
                                      value: candidate.path,
                                      child: Text('Java ${candidate.majorVersion} — ${candidate.path}', overflow: TextOverflow.ellipsis),
                                    )).toList(),
                                    onChanged: (value) {
                                      if (value != null) setState(() => _javaPathController.text = value);
                                    },
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(11),
                                  decoration: BoxDecoration(color: _green.withValues(alpha: .07), borderRadius: BorderRadius.circular(10), border: Border.all(color: _green.withValues(alpha: .16))),
                                  child: const Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.info_outline_rounded, color: _green, size: 17),
                                      SizedBox(width: 8),
                                      Expanded(child: Text('Выбери папку, чтобы найти все установленные Java. Если сборке нужна более новая версия, лаунчер скачает её автоматически.', style: TextStyle(color: _muted, fontSize: 11, height: 1.45))),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (narrow) return Column(children: [general, const SizedBox(height: 16), runtime]);
                          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: general), const SizedBox(width: 16), Expanded(child: runtime)]);
                        }),
                        const SizedBox(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded, size: 17),
                              label: const Text('Отмена'),
                              style: OutlinedButton.styleFrom(foregroundColor: _muted, side: const BorderSide(color: _border), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              onPressed: _saveSettings,
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text('Сохранить изменения'),
                              style: FilledButton.styleFrom(backgroundColor: _green, foregroundColor: const Color(0xFF05200F), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)), textStyle: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(color: _panel, border: Border(bottom: BorderSide(color: _border, width: .8))),
      child: Row(
        children: [
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, size: 19), color: _muted, tooltip: 'Назад'),
          const SizedBox(width: 5),
          const Icon(Icons.spa_rounded, color: _green, size: 17),
          const SizedBox(width: 9),
          const Text('Zembo Launcher', style: TextStyle(color: Color(0xFFE3F0E9), fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: .4)),
          const Spacer(),
          const Text('НАСТРОЙКИ СБОРКИ', style: TextStyle(color: _muted, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _fieldLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label, style: const TextStyle(color: Color(0xFFB5C7BB), fontSize: 12, fontWeight: FontWeight.w600)),
  );

  Widget _settingsCard({required String title, required String subtitle, required IconData icon, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(color: _green.withValues(alpha: .1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: _green, size: 19)),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: _muted, fontSize: 11))])),
          ]),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}
