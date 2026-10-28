import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/installed_mods_service.dart';
import '../services/mod_guard_service.dart';

/// Вкладка «Установленные моды»: список модов сборки, включение/выключение,
/// удаление, а также раскрывающиеся настройки каждого мода
/// (ограничения и примерная нагрузка).
class InstalledModsTab extends StatefulWidget {
  /// Папка сборки: <minecraftFolder>/instances/<имя сборки>
  final String instancePath;

  /// Текст из поля поиска сверху — используется как фильтр по названию.
  final String filter;

  const InstalledModsTab({super.key, required this.instancePath, this.filter = ''});

  @override
  State<InstalledModsTab> createState() => _InstalledModsTabState();
}

class _InstalledModsTabState extends State<InstalledModsTab> with AutomaticKeepAliveClientMixin {
  static const green = Color(0xFF43E477);
  static const muted = Color(0xFF91A497);
  static const border = Color(0xFF26392D);

  List<InstalledMod> _mods = [];
  Map<String, ModPermissions> _permissions = {};
  Map<String, Map<String, int>> _report = {};
  final Set<String> _expanded = {};
  bool _loading = true;
  bool _analyzing = false;
  String? _error;
  int _loadId = 0;

  String get _modsDir => p.join(widget.instancePath, 'mods');

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final mods = await InstalledModsService.listMods(_modsDir);
      final permissions = await InstalledModsService.loadPermissions(widget.instancePath);
      final report = await ModGuardService.loadReport(widget.instancePath);
      if (!mounted || id != _loadId) return;
      setState(() {
        _mods = mods;
        _permissions = permissions;
        _report = report;
        _loading = false;
        _analyzing = mods.isNotEmpty;
      });

      // Читаем jar по одному, чтобы список появился сразу, а детали подгружались.
      for (var i = 0; i < mods.length; i++) {
        final analyzed = await InstalledModsService.analyze(mods[i]);
        if (!mounted || id != _loadId) return;
        setState(() {
          final index = _mods.indexWhere((m) => m.key == analyzed.key);
          if (index != -1) _mods[index] = analyzed.copyWith(enabled: _mods[index].enabled, path: _mods[index].path);
        });
      }
      if (mounted && id == _loadId) setState(() => _analyzing = false);
    } catch (e) {
      if (!mounted || id != _loadId) return;
      setState(() {
        _loading = false;
        _analyzing = false;
        _error = 'Не удалось прочитать папку модов: $e';
      });
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
  }

  Future<void> _toggle(InstalledMod mod, bool enabled) async {
    try {
      final updated = await InstalledModsService.setEnabled(mod, enabled);
      if (!mounted) return;
      setState(() {
        final index = _mods.indexWhere((m) => m.key == mod.key);
        if (index != -1) _mods[index] = updated;
      });
    } catch (e) {
      _snack('Не удалось ${enabled ? 'включить' : 'выключить'} мод: $e');
    }
  }

  Future<void> _delete(InstalledMod mod) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF111C16),
        title: const Text('Удалить мод?', style: TextStyle(color: Colors.white)),
        content: Text(
          '${mod.displayName} (${mod.fileName}) будет удалён с диска без возможности восстановления.',
          style: const TextStyle(color: muted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await InstalledModsService.delete(mod);
      _permissions.remove(mod.key);
      await InstalledModsService.savePermissions(widget.instancePath, _permissions);
      if (!mounted) return;
      setState(() {
        _mods.removeWhere((m) => m.key == mod.key);
        _expanded.remove(mod.key);
      });
    } catch (e) {
      _snack('Не удалось удалить мод: $e');
    }
  }

  Future<void> _setPermissions(InstalledMod mod, ModPermissions value) async {
    setState(() => _permissions[mod.key] = value);
    try {
      await InstalledModsService.savePermissions(widget.instancePath, _permissions);
    } catch (e) {
      _snack('Не удалось сохранить ограничения: $e');
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: green, strokeWidth: 2));
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)));
    }

    final query = widget.filter.trim().toLowerCase();
    final visible = _mods.where((m) {
      if (query.isEmpty) return true;
      return m.displayName.toLowerCase().contains(query) || m.fileName.toLowerCase().contains(query);
    }).toList();

    final enabledCount = _mods.where((m) => m.enabled).length;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
        child: Row(children: [
          const Icon(Icons.extension_rounded, color: green, size: 15),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _mods.isEmpty ? 'Модов пока нет' : 'Установлено: ${_mods.length}, включено: $enabledCount',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ),
          if (_analyzing) ...[
            const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(color: green, strokeWidth: 1.7)),
            const SizedBox(width: 6),
            const Text('Анализ модов…', style: TextStyle(color: muted, fontSize: 11)),
          ],
          IconButton(
            tooltip: 'Обновить список',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, color: muted, size: 17),
            visualDensity: VisualDensity.compact,
          ),
        ]),
      ),
      Expanded(
        child: visible.isEmpty
            ? Center(
                child: Text(
                  _mods.isEmpty
                      ? 'Скачай моды во вкладке «Моды и ресурспаки» — они появятся здесь.'
                      : 'Ничего не найдено по запросу.',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _modCard(visible[index]),
              ),
      ),
    ]);
  }

  Widget _modCard(InstalledMod mod) {
    final expanded = _expanded.contains(mod.key);
    final permissions = _permissions[mod.key] ?? const ModPermissions();
    final estimate = mod.analyzed ? mod.estimate : null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1A14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: expanded ? green.withValues(alpha: .35) : border),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
          child: Row(children: [
            IconButton(
              tooltip: expanded ? 'Свернуть настройки' : 'Настройки мода',
              onPressed: () => setState(() {
                if (!_expanded.remove(mod.key)) _expanded.add(mod.key);
              }),
              icon: AnimatedRotation(
                turns: expanded ? .5 : 0,
                duration: const Duration(milliseconds: 160),
                child: const Icon(Icons.keyboard_arrow_down_rounded, color: green, size: 22),
              ),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Opacity(
                opacity: mod.enabled ? 1 : .5,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    mod.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (mod.version.isNotEmpty) mod.version,
                      if (mod.loader.isNotEmpty) mod.loader,
                      _formatSize(mod.sizeBytes),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 10),
                  ),
                ]),
              ),
            ),
            if (permissions.hasRestrictions)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Tooltip(message: 'Для мода заданы ограничения', child: Icon(Icons.shield_rounded, color: green, size: 15)),
              ),
            if (estimate != null) _loadBadge(estimate),
            const SizedBox(width: 6),
            Switch(
              value: mod.enabled,
              activeColor: green,
              onChanged: (v) => _toggle(mod, v),
            ),
            IconButton(
              tooltip: 'Удалить мод',
              onPressed: () => _delete(mod),
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 19),
              visualDensity: VisualDensity.compact,
            ),
          ]),
        ),
        if (expanded) _modDetails(mod, permissions, estimate),
      ]),
    );
  }

  Widget _loadBadge(ModLoadEstimate estimate) {
    final (label, color) = switch (estimate.level) {
      ModLoad.low => ('Низкая', green),
      ModLoad.medium => ('Средняя', Colors.amber),
      ModLoad.high => ('Высокая', Colors.redAccent),
    };
    return Tooltip(
      message: 'Примерная нагрузка (оценка по содержимому мода)',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withValues(alpha: .35)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _modDetails(InstalledMod mod, ModPermissions permissions, ModLoadEstimate? estimate) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: border, width: .8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 10),
        if (mod.description.isNotEmpty) ...[
          Text(mod.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFB5C7BB), fontSize: 11)),
          const SizedBox(height: 4),
        ],
        Text('Файл: ${mod.fileName}${mod.id.isNotEmpty ? '   ·   id: ${mod.id}' : ''}', style: const TextStyle(color: muted, fontSize: 10)),
        const SizedBox(height: 14),

        // ----- Нагрузка -----
        const Text('Примерная нагрузка', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (estimate == null)
          const Text('Анализирую мод…', style: TextStyle(color: muted, fontSize: 11))
        else ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            _stat(Icons.memory_rounded, 'ОЗУ', '~${estimate.ramMb} МБ'),
            _stat(Icons.timer_outlined, 'Загрузка', '~${estimate.startupSeconds.toStringAsFixed(1)} с'),
            _stat(Icons.speed_rounded, 'Уровень', switch (estimate.level) {
              ModLoad.low => 'низкая',
              ModLoad.medium => 'средняя',
              ModLoad.high => 'высокая',
            }),
          ]),
          if (estimate.reasons.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(estimate.reasons.join(' · '), style: const TextStyle(color: muted, fontSize: 10)),
          ],
          const SizedBox(height: 6),
          const Text(
            'Это оценка по содержимому jar (классы, миксины, ресурсы), а не замер во время игры. '
            'Точную нагрузку покажет профайлер, например Spark.',
            style: TextStyle(color: muted, fontSize: 10),
          ),
        ],
        const SizedBox(height: 16),

        // ----- Ограничения -----
        const Text('Ограничения мода', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        if (_report[mod.key] != null) ...[
          const SizedBox(height: 4),
          Text(
            'Заблокировано в последнем запуске — файлы: ${_report[mod.key]!['create']}, '
            'чтение: ${_report[mod.key]!['read']}, окна и программы: ${_report[mod.key]!['windows']}',
            style: const TextStyle(color: Colors.amber, fontSize: 10),
          ),
        ],
        const SizedBox(height: 2),
        _permissionSwitch(
          icon: Icons.note_add_outlined,
          title: 'Запретить создавать файлы',
          subtitle: 'Создание, изменение, удаление и переименование',
          value: permissions.denyCreateFiles,
          onChanged: (v) => _setPermissions(mod, permissions.copyWith(denyCreateFiles: v)),
        ),
        _permissionSwitch(
          icon: Icons.web_asset_rounded,
          title: 'Запретить открывать окна и программы',
          subtitle: 'Окна Java, браузер, запуск внешних программ',
          value: permissions.denyOpenWindows,
          onChanged: (v) => _setPermissions(mod, permissions.copyWith(denyOpenWindows: v)),
        ),
        _permissionSwitch(
          icon: Icons.folder_open_rounded,
          title: 'Запретить просматривать файлы',
          subtitle: 'Чтение и просмотр папок вне папок игры и лаунчера',
          value: permissions.denyReadFiles,
          onChanged: (v) => _setPermissions(mod, permissions.copyWith(denyReadFiles: v)),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Colors.amber.withValues(alpha: .25)),
          ),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, color: Colors.amber, size: 15),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Ограничения применяются при следующем запуске игры (нужна Java 17+, то есть Minecraft 1.17 и новее). '
                'Защита перехватывает стандартные функции Java для файлов, окон и процессов и определяет мод по стеку вызовов. '
                'Нативный код и код мода, внедрённый через миксины в классы игры, она не видит, поэтому недоверенные моды лучше не запускать совсем.',
                style: TextStyle(color: Color(0xFFE6D9A8), fontSize: 10),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _stat(IconData icon, String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1510),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: green, size: 14),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(color: muted, fontSize: 11)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _permissionSwitch({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeColor: green,
        dense: true,
        contentPadding: EdgeInsets.zero,
        secondary: Icon(icon, color: muted, size: 18),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 12)),
        subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(color: muted, fontSize: 10)),
      );
}
