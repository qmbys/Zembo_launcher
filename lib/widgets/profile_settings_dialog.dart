import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../services/forge_installer.dart';
import '../services/mojang_api_service.dart';
import 'installed_mods_tab.dart';

/// Settings for an existing profile + Modrinth project browser.
class ProfileSettingsScreen extends StatefulWidget {
  final Profile initialProfile;
  final String minecraftFolder;

  final ValueChanged<Profile> onSave;
  final VoidCallback onCancel;

  const ProfileSettingsScreen({
    super.key,
    required this.initialProfile,
    required this.minecraftFolder,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen>
    with SingleTickerProviderStateMixin {
  static const green = Color(0xFF43E477);
  static const panel = Color(0xFF111C16);

  late TabController _tabs;
  bool _shaderSupport = false;
  late final TextEditingController _name;
  late final TextEditingController _ram;
  late final TextEditingController _search;
  late String _version;
  late String _loader;
  late String _icon;
  late String _forgeVersion;

  List<String> _versions = [];
  List<String> _forgeVersions = [];
  bool _loadingVersions = true;
  bool _loadingForge = false;
  bool _searching = false;
  bool _installing = false;
  String _projectType = 'mod';
  String _message = '';
  List<Map<String, dynamic>> _results = [];
  final Set<String> _selected = {};
  final ScrollController _resultsScroll = ScrollController();
  int _searchOffset = 0;
  bool _hasMoreResults = true;
  bool _loadingMoreResults = false;
  int _searchRequestId = 0;
  Timer? _searchDebounce;
  // Меняется при открытии вкладки «Установленные моды» и после установки модов — список перечитывается.
  int _installedModsRefresh = 0;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    _tabs = TabController(length: 3, vsync: this)..addListener(_onTabChanged);
    _resultsScroll.addListener(_onResultsScroll);
    _name = TextEditingController(text: p.name);
    _ram = TextEditingController(text: p.ram.toString());
    _search = TextEditingController();
    _version = p.version;
    _loader = p.loader;
    _icon = p.icon.isEmpty ? 'stone' : p.icon;
    _forgeVersion = p.forgeVersion;
    _loadVersions();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabs.dispose();
    _resultsScroll.dispose();
    _name.dispose();
    _ram.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    if (_tabs.index == 2) {
      // Вкладка «Установленные моды»: перечитываем папку mods.
      setState(() => _installedModsRefresh++);
    } else if (_shaderSupport && _tabs.index == 3 && _projectType != 'shader') {
      setState(() { _projectType = 'shader'; _results = []; _selected.clear(); });
      _searchProjects();
    } else if (_tabs.index == 1 && _projectType == 'shader') {
      setState(() { _projectType = 'mod'; _results = []; _selected.clear(); });
      _searchProjects();
    } else if (mounted) {
      setState(() {}); // Update compact header controls when the active tab changes.
    }
  }

  Future<dynamic> _getJson(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'ZemboLauncher/1.0');
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _loadVersions() async {
    try {
      final data = await MojangApiService.fetchVersions();
      final versions = data
          .where((v) => v.type == 'release')
          .map<String>((v) => v.id as String)
          .toList();
      if (!mounted) return;
      setState(() {
        _versions = versions;
        if (_version.isNotEmpty && !_versions.contains(_version)) {
          _versions.insert(0, _version);
        }
        _loadingVersions = false;
      });
      if (_loader == 'Forge') await _loadForgeVersions();
      await _detectShaderSupport();
      // Populate the store with popular projects immediately; search is optional.
      await _searchProjects();
    } catch (e) {
      if (mounted) setState(() {
        _loadingVersions = false;
        _message = 'Не удалось загрузить версии Minecraft: $e';
      });
    }
  }

  Future<void> _detectShaderSupport() async {
    // Only expose shader management when the instance already has a known
    // shader-capable mod/loader installed. Iris, Oculus (Forge), and OptiFine
    // are detected by their jar names in the instance mods directory.
    try {
      final instancePath = [widget.minecraftFolder, 'instances', widget.initialProfile.name]
          .join(Platform.pathSeparator);
      final dirs = <Directory>[
        Directory([instancePath, 'mods'].join(Platform.pathSeparator)),
        Directory([widget.minecraftFolder, 'versions'].join(Platform.pathSeparator)),
      ];
      var supported = false;
      for (final dir in dirs) {
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(followLinks: false)) {
          final name = entity.uri.pathSegments.isEmpty ? entity.path : entity.uri.pathSegments.last;
          final lower = name.toLowerCase();
          if (lower.endsWith('.jar') &&
              (lower.contains('iris') || lower.contains('optifine') ||
               lower.contains('oculus') || lower.contains('shader-support'))) {
            supported = true;
            break;
          }
        }
        if (supported) break;
      }
      if (!mounted || supported == _shaderSupport) return;
      final oldIndex = _tabs.index;
      _tabs.dispose();
      setState(() {
        _shaderSupport = supported;
        _tabs = TabController(length: supported ? 4 : 3, vsync: this, initialIndex: oldIndex.clamp(0, supported ? 3 : 2))..addListener(_onTabChanged);
      });
    } catch (_) {
      // Keep shader tab hidden if the instance path cannot be inspected.
    }
  }

  Future<void> _loadForgeVersions() async {
    if (_version.isEmpty) return;
    setState(() => _loadingForge = true);
    try {
      final versions =
          await ForgeInstaller.getAvailableForgeVersions(_version);
      if (!mounted) return;
      setState(() {
        _forgeVersions = versions;
        if (!_forgeVersions.contains(_forgeVersion)) {
          _forgeVersion = _forgeVersions.isEmpty ? '' : _forgeVersions.first;
        }
        _loadingForge = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _loadingForge = false;
        _message = 'Не удалось загрузить версии Forge: $e';
      });
    }
  }

  List<String> get _loadersForApi {
    if (_loader == 'Fabric') return ['fabric'];
    if (_loader == 'Forge') return ['forge'];
    return ['fabric', 'forge', 'quilt', 'neoforge'];
  }

  void _onResultsScroll() {
    if (!_resultsScroll.hasClients || _searching || _loadingMoreResults || !_hasMoreResults) return;
    if (_resultsScroll.position.extentAfter < 500) _searchProjects(loadMore: true);
  }

  Future<void> _searchProjects({bool loadMore = false}) async {
    if (loadMore) {
      if (_searching || _loadingMoreResults || !_hasMoreResults) return;
      setState(() => _loadingMoreResults = true);
    } else {
      final requestId = ++_searchRequestId;
      setState(() {
        _searching = true;
        _loadingMoreResults = false;
        _message = '';
        _selected.clear();
        _searchOffset = 0;
        _hasMoreResults = true;
      });
      await _fetchProjectPage(0, requestId);
      return;
    }
    await _fetchProjectPage(_searchOffset, _searchRequestId, append: true);
  }

  Future<void> _fetchProjectPage(int offset, int requestId, {bool append = false}) async {
    try {
      final facets = <List<String>>[
        ['project_type:${_projectType == 'shader' ? 'shader' : _projectType}'],
        ['versions:$_version'],
      ];
      if (_projectType == 'mod' && _loader != 'Vanilla') {
        facets.add(_loadersForApi.map((v) => 'categories:$v').toList());
      }
      final uri = Uri.https('api.modrinth.com', '/v2/search', {
        'query': _search.text.trim(),
        'facets': jsonEncode(facets),
        'limit': '24',
        'offset': '$offset',
        'index': _search.text.trim().isEmpty ? 'downloads' : 'relevance',
      });
      final data = await _getJson(uri.toString()) as Map<String, dynamic>;
      if (!mounted || requestId != _searchRequestId) return;
      final hits = (data['hits'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        if (append) {
          final known = _results.map((e) => e['project_id']?.toString() ?? e['id']?.toString() ?? '').toSet();
          _results.addAll(hits.where((e) => !known.contains(e['project_id']?.toString() ?? e['id']?.toString() ?? '')));
        } else {
          _results = hits;
        }
        _searchOffset = offset + hits.length;
        _hasMoreResults = hits.length == 24;
        _searching = false;
        _loadingMoreResults = false;
        if (_results.isEmpty) _message = 'Ничего не найдено. Измени запрос или фильтры.';
      });
    } catch (e) {
      if (mounted && requestId == _searchRequestId) setState(() {
        _searching = false;
        _loadingMoreResults = false;
        _hasMoreResults = false;
        _message = 'Ошибка поиска Modrinth: $e';
      });
    }
  }

  Future<Map<String, dynamic>> _projectVersion(String projectId) async {
    final query = <String, String>{
      'game_versions': jsonEncode([_version]),
    };
    // Resource packs are not tied to Fabric/Forge, so do not filter them by loader.
    if (_projectType == 'mod' && _loader != 'Vanilla') {
      query['loaders'] = jsonEncode(_loadersForApi);
    }
    final uri = Uri.https(
      'api.modrinth.com',
      '/v2/project/$projectId/version',
      query,
    );
    final data = await _getJson(uri.toString()) as List;
    if (data.isEmpty) {
      throw Exception('Нет версии для Minecraft $_version и загрузчика $_loader');
    }
    return Map<String, dynamic>.from(data.first as Map);
  }

  Future<void> _downloadVersion(
    String versionId,
    Directory target,
    Set<String> seen,
  ) async {
    if (!seen.add(versionId)) return;
    final version = Map<String, dynamic>.from(
      await _getJson('https://api.modrinth.com/v2/version/$versionId') as Map,
    );

    // Required dependencies with explicit version IDs can be installed recursively.
    // Project-only dependencies are not guessed, to avoid installing an incompatible version.
    final dependencies = (version['dependencies'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['dependency_type'] == 'required')
        .toList();
    for (final dependency in dependencies) {
      final depId = dependency['version_id'] as String?;
      if (depId != null && depId.isNotEmpty) {
        await _downloadVersion(depId, target, seen);
      }
    }

    final files = (version['files'] as List? ?? []).whereType<Map>().toList();
    if (files.isEmpty) throw Exception('У версии нет доступного файла');
    final file = files.cast<Map>().firstWhere(
      (f) => f['primary'] == true,
      orElse: () => files.first,
    );
    final url = file['url'] as String?;
    final filename = file['filename'] as String?;
    if (url == null || filename == null) throw Exception('Нет ссылки на файл');

    await target.create(recursive: true);
    final destination = File('${target.path}${Platform.pathSeparator}$filename');
    if (await destination.exists()) return;
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Ошибка скачивания $filename: ${response.statusCode}');
      }
      await response.pipe(destination.openWrite());
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _installSelected() async {
    final selected = _results.where((p) =>
      _selected.contains(p['project_id']?.toString())).toList();
    if (selected.isEmpty) {
      setState(() => _message = 'Сначала выбери хотя бы один проект.');
      return;
    }
    if (_projectType == 'mod' && _loader == 'Vanilla') {
      setState(() => _message = 'Для модов выбери Fabric или Forge. Ресурс-паки доступны и для Vanilla.');
      return;
    }
    setState(() {
      _installing = true;
      _message = 'Подготовка установки...';
    });
    try {
      final instancePath = [
        widget.minecraftFolder, 'instances', widget.initialProfile.name
      ].join(Platform.pathSeparator);
      final target = Directory([
        instancePath, _projectType == 'mod' ? 'mods' : (_projectType == 'shader' ? 'shaderpacks' : 'resourcepacks')
      ].join(Platform.pathSeparator));
      final installedVersions = <String>{};
      var count = 0;
      for (final project in selected) {
        final id = project['project_id']?.toString();
        if (id == null || id.isEmpty) continue;
        if (mounted) setState(() => _message = 'Установка ${project['title'] ?? id}...');
        final version = await _projectVersion(id);
        await _downloadVersion(version['id'] as String, target, installedVersions);
        count++;
      }
      if (mounted) setState(() =>
        _message = 'Установлено проектов: $count. Перезапусти Minecraft для применения.');
      if (mounted) setState(() => _installedModsRefresh++);
    } catch (e) {
      if (mounted) setState(() => _message = 'Ошибка установки: $e');
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  void _save() {
    final name = _name.text.trim();
    final ram = int.tryParse(_ram.text.trim());
    if (name.isEmpty || ram == null || ram < 1 || ram > 32 || _version.isEmpty) {
      setState(() => _message = 'Укажи название, версию Minecraft и ОЗУ от 1 до 32 GB.');
      _tabs.animateTo(0);
      return;
    }
    widget.onSave(Profile(
      id: widget.initialProfile.id,
      name: name,
      version: _version,
      loader: _loader,
      ram: ram,
      icon: _icon,
      javaPath: widget.initialProfile.javaPath,
      forgeVersion: _loader == 'Forge' ? _forgeVersion : '',
    ));
  }

  Widget _headerTab(int index, IconData icon, String label) {
    final selected = _tabs.index == index;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: selected ? green.withValues(alpha: .13) : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: () => _tabs.animateTo(index),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: selected ? green.withValues(alpha: .22) : Colors.transparent,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 13, color: selected ? green : const Color(0xFF91A497)),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? green : const Color(0xFF91A497),
              )),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1713),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: const BoxDecoration(
            color: Color(0xFF0D1713),
            border: Border(bottom: BorderSide(color: Color(0xFF26392D), width: .8)),
          ),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: green.withValues(alpha: .11), borderRadius: BorderRadius.circular(12), border: Border.all(color: green.withValues(alpha: .22))),
              child: const Icon(Icons.tune_rounded, color: green, size: 21),
            ),
            const SizedBox(width: 6),
            IntrinsicWidth(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Настройки сборки', maxLines: 1, softWrap: false, overflow: TextOverflow.visible, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 1),
              SizedBox(width: 145, child: Text(widget.initialProfile.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF91A497), fontSize: 10))),
            ])),
            const SizedBox(width: 4),
            Container(
              padding: EdgeInsets.zero,
              decoration: BoxDecoration(
                color: const Color(0xFF0A130E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF26392D)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _headerTab(0, Icons.settings_rounded, 'Основное'),
                _headerTab(1, Icons.storefront_rounded, 'Моды и ресурспаки'),
                _headerTab(2, Icons.inventory_2_rounded, 'Установленные моды'),
                if (_shaderSupport) _headerTab(3, Icons.blur_on_rounded, 'Шейдеры'),
              ]),
            ),
            const SizedBox(width: 6),
            Expanded(flex: 5, child: TextField(
              controller: _search,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: _decoration('Поиск — необязательно').copyWith(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF91A497), size: 18),
                suffixIcon: _search.text.isEmpty ? null : IconButton(
                  tooltip: 'Очистить поиск',
                  onPressed: () { _search.clear(); if (_tabs.index == 2) { setState(() {}); } else { _searchProjects(); } },
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF91A497), size: 16),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              ),
              onChanged: (_) {
                _searchDebounce?.cancel();
                if (_tabs.index == 2) { setState(() {}); return; } // на вкладке установленных модов поиск работает как фильтр
                _searchDebounce = Timer(const Duration(milliseconds: 450), _searchProjects);
                setState(() {});
              },
              onSubmitted: (_) { if (_tabs.index != 2) _searchProjects(); },
            )),
            const SizedBox(width: 6),
            if (_tabs.index == 1) Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFF0B1510), borderRadius: BorderRadius.circular(9), border: Border.all(color: const Color(0xFF26392D))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _projectTypeChip('mod', 'Моды', Icons.extension_rounded),
                _projectTypeChip('resourcepack', 'Ресурспаки', Icons.wallpaper_rounded),
              ]),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: green.withValues(alpha: .08), borderRadius: BorderRadius.circular(8), border: Border.all(color: green.withValues(alpha: .2))),
              child: Text(_version, style: const TextStyle(color: green, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 5),
            IconButton(onPressed: widget.onCancel, tooltip: 'Закрыть', icon: const Icon(Icons.close_rounded, color: Color(0xFF91A497), size: 18), visualDensity: VisualDensity.compact),
          ]),
        ),
        if (_message.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: green.withValues(alpha: .07), borderRadius: BorderRadius.circular(9), border: Border.all(color: green.withValues(alpha: .18))),
            child: Row(children: [const Icon(Icons.info_outline_rounded, color: green, size: 16), const SizedBox(width: 8), Expanded(child: Text(_message, style: const TextStyle(color: Color(0xFFB5C7BB), fontSize: 11), maxLines: 3, overflow: TextOverflow.ellipsis))]),
          ),
        Expanded(child: TabBarView(controller: _tabs, children: [
          _settingsTab(),
          _storeTab(),
          InstalledModsTab(
            key: ValueKey(_installedModsRefresh),
            instancePath: [widget.minecraftFolder, 'instances', widget.initialProfile.name].join(Platform.pathSeparator),
            filter: _search.text,
          ),
          if (_shaderSupport) _shaderTab(),
        ])),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          decoration: const BoxDecoration(color: Color(0xFF0D1713), border: Border(top: BorderSide(color: Color(0xFF26392D), width: .8))),
          child: Row(children: [
            Expanded(child: Text('${_selected.length} выбрано', style: const TextStyle(color: Color(0xFF91A497), fontSize: 11))),
            OutlinedButton(onPressed: widget.onCancel, style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF91A497), side: const BorderSide(color: Color(0xFF26392D)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))), child: const Text('Отмена')),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _installing || _selected.isEmpty ? null : _installSelected,
              icon: const Icon(Icons.download_rounded, size: 15),
              label: const Text('Установить выбранное'),
              style: OutlinedButton.styleFrom(foregroundColor: green, side: BorderSide(color: green.withValues(alpha: .45)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13), textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Сохранить'),
              style: ElevatedButton.styleFrom(backgroundColor: green, foregroundColor: const Color(0xFF05200F), elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _settingsTab() => LayoutBuilder(
    builder: (context, constraints) {
      final cardWidth = constraints.maxWidth >= 850
          ? (constraints.maxWidth - 42) / 2
          : constraints.maxWidth;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Параметры сборки', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -.3)),
          const SizedBox(height: 5),
          const Text('Настрой внешний вид, версию игры и производительность.', style: TextStyle(color: Color(0xFF91A497), fontSize: 12)),
          const SizedBox(height: 18),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              SizedBox(width: cardWidth, child: _settingsSection(
                icon: Icons.grid_view_rounded,
                title: 'Основное',
                subtitle: 'Название и иконка сборки',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('Название сборки'),
                  _field(_name, 'Например, Survival+'),
                  const SizedBox(height: 16),
                  _label('Иконка сборки'),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final entry in const <String, IconData>{
                      'stone': Icons.square_rounded,
                      'grass': Icons.grass_rounded,
                      'diamond': Icons.diamond_rounded,
                      'lava': Icons.local_fire_department_rounded,
                      'water': Icons.water_drop_rounded,
                      'ice': Icons.ac_unit_rounded,
                      'wood': Icons.park_rounded,
                      'gold': Icons.bolt_rounded,
                      'obsidian': Icons.hexagon_rounded,
                      'sand': Icons.grain_rounded,
                    }.entries)
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => _icon = entry.key),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: _icon == entry.key ? green.withValues(alpha: .13) : const Color(0xFF0A1510),
                            border: Border.all(color: _icon == entry.key ? green : const Color(0xFF26392D), width: _icon == entry.key ? 1.5 : 1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(entry.value, color: _icon == entry.key ? green : const Color(0xFF91A497), size: 19),
                        ),
                      ),
                  ]),
                ]),
              )),
              SizedBox(width: cardWidth, child: _settingsSection(
                icon: Icons.memory_rounded,
                title: 'Производительность',
                subtitle: 'Ресурсы для запуска Minecraft',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('Оперативная память (ГБ)'),
                  _field(_ram, '4', number: true),
                  const SizedBox(height: 7),
                  const Text('Для большинства сборок подойдёт 4–6 ГБ.', style: TextStyle(color: Color(0xFF91A497), fontSize: 11)),
                  const SizedBox(height: 17),
                  _label('Версия Minecraft'),
                  DropdownButtonFormField<String>(
                    value: _versions.contains(_version) ? _version : null,
                    dropdownColor: panel,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: _decoration(_loadingVersions ? 'Загрузка версий...' : 'Выбери версию'),
                    items: _versions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: _loadingVersions ? null : (v) {
                      if (v == null) return;
                      setState(() => _version = v);
                      if (_loader == 'Forge') _loadForgeVersions();
                      _searchProjects();
                    },
                  ),
                  const SizedBox(height: 14),
                  _label('Загрузчик'),
                  DropdownButtonFormField<String>(
                    value: _loader,
                    dropdownColor: panel,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: _decoration('Выбери загрузчик'),
                    items: const ['Vanilla', 'Fabric', 'Forge'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _loader = v);
                      if (v == 'Forge') _loadForgeVersions();
                      _searchProjects();
                    },
                  ),
                  if (_loader == 'Forge') ...[
                    const SizedBox(height: 14),
                    _label('Версия Forge'),
                    DropdownButtonFormField<String>(
                      value: _forgeVersions.contains(_forgeVersion) ? _forgeVersion : null,
                      dropdownColor: panel,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: _decoration(_loadingForge ? 'Загрузка Forge...' : 'Выбери версию Forge'),
                      items: _forgeVersions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                      onChanged: _loadingForge ? null : (v) => setState(() => _forgeVersion = v ?? ''),
                    ),
                  ],
                ]),
              )),
            ],
          ),
        ]),
      );
    },
  );

  Widget _settingsSection({required IconData icon, required String title, required String subtitle, required Widget child}) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: const Color(0xFF0F1A14),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color(0xFF26392D)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 35, height: 35, decoration: BoxDecoration(color: green.withValues(alpha: .1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: green, size: 18)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: Color(0xFF91A497), fontSize: 10)),
        ])),
      ]),
      const SizedBox(height: 18),
      child,
    ]),
  );

  Widget _storeTab() => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
      child: Row(children: [
        const Icon(Icons.trending_up_rounded, color: green, size: 15),
        const SizedBox(width: 6),
        Expanded(child: Text(
          _search.text.trim().isEmpty ? 'Популярное для Minecraft $_version' : 'Результаты поиска для «${_search.text.trim()}»',
          style: const TextStyle(color: Color(0xFF91A497), fontSize: 11),
          maxLines: 1, overflow: TextOverflow.ellipsis,
        )),
        if (_searching) const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(color: green, strokeWidth: 1.7)),
      ]),
    ),
    Expanded(child: _searching && _results.isEmpty
      ? const Center(child: CircularProgressIndicator(color: green, strokeWidth: 2))
      : _results.isEmpty
        ? Center(child: Container(
            margin: const EdgeInsets.all(18), padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: const Color(0xFF0F1A14), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF26392D))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_rounded, color: Color(0xFF91A497), size: 34),
              const SizedBox(height: 10),
              const Text('Каталог пока пуст', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Проверь подключение или очисти поиск, чтобы загрузить популярные проекты.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF91A497), fontSize: 11, height: 1.45)),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: () { _search.clear(); _searchProjects(); }, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Показать популярное'), style: OutlinedButton.styleFrom(foregroundColor: green, side: const BorderSide(color: Color(0xFF26392D)))),
            ]),
          ))
        : LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 1050 ? 4 : width >= 760 ? 3 : width >= 500 ? 2 : 1;
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 11,
                mainAxisSpacing: 11,
                mainAxisExtent: 154,
              ),
              controller: _resultsScroll,
              itemCount: _results.length + (_hasMoreResults ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= _results.length) {
                  if (!_loadingMoreResults) { WidgetsBinding.instance.addPostFrameCallback((_) => _onResultsScroll()); }
                  return const Center(child: Padding(padding: EdgeInsets.all(18), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: green, strokeWidth: 2))));
                }
                final p = _results[i];
                final id = p['project_id']?.toString() ?? '';
                final iconUrl = p['icon_url']?.toString();
                final selected = _selected.contains(id);
                final title = p['title']?.toString() ?? id;
                final description = p['description']?.toString() ?? '';
                final downloads = p['downloads'];
                return InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: () => setState(() { if (selected) { _selected.remove(id); } else { _selected.add(id); } }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFF14291C) : const Color(0xFF0F1A14),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: selected ? green : const Color(0xFF26392D), width: selected ? 1.5 : 1),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: iconUrl == null || iconUrl.isEmpty
                            ? Container(width: 36, height: 36, color: green.withValues(alpha: .1), child: Icon(_projectType == 'mod' ? Icons.extension_rounded : Icons.wallpaper_rounded, color: green, size: 19))
                            : Image.network(iconUrl, width: 36, height: 36, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 36, height: 36, color: green.withValues(alpha: .1), child: Icon(_projectType == 'mod' ? Icons.extension_rounded : Icons.wallpaper_rounded, color: green, size: 19))),
                        ),
                        const SizedBox(width: 9),
                        Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, height: 1.2))),
                        Icon(selected ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded, color: selected ? green : const Color(0xFF91A497), size: 18),
                      ]),
                      const SizedBox(height: 9),
                      Expanded(child: Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF91A497), fontSize: 10, height: 1.35))),
                      const SizedBox(height: 7),
                      Row(children: [
                        const Icon(Icons.download_rounded, size: 12, color: Color(0xFF91A497)),
                        const SizedBox(width: 4),
                        Expanded(child: Text(downloads is num ? _formatDownloads(downloads) : 'Modrinth', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF91A497), fontSize: 10))),
                        if (selected) const Text('ВЫБРАН', style: TextStyle(color: green, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .5)),
                      ]),
                    ]),
                  ),
                );
              },
            );
          })),
    const SizedBox(height: 8),
  ]);

  Widget _shaderTab() {
    // The tab is only added when Iris/OptiFine/Oculus support is detected.
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 2, 20, 8), child: Row(children: [
        const Icon(Icons.blur_on_rounded, color: green, size: 15), const SizedBox(width: 6),
        Expanded(child: Text(_search.text.trim().isEmpty ? 'Популярные шейдеры для Minecraft $_version' : 'Результаты поиска шейдеров', style: const TextStyle(color: Color(0xFF91A497), fontSize: 11))),
        if (_searching) const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(color: green, strokeWidth: 1.7)),
      ])),
      Expanded(child: _searching && _results.isEmpty
        ? const Center(child: CircularProgressIndicator(color: green, strokeWidth: 2))
        : _results.isEmpty
          ? const Center(child: Text('Не удалось загрузить шейдеры. Попробуй обновить каталог.', style: TextStyle(color: Color(0xFF91A497), fontSize: 12)))
          : LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 1050 ? 4 : width >= 760 ? 3 : width >= 500 ? 2 : 1;
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, crossAxisSpacing: 11, mainAxisSpacing: 11, mainAxisExtent: 154),
                itemCount: _results.length,
                itemBuilder: (context, i) {
                  final p = _results[i]; final id = p['project_id']?.toString() ?? ''; final selected = _selected.contains(id);
                  final title = p['title']?.toString() ?? id; final desc = p['description']?.toString() ?? ''; final iconUrl = p['icon_url']?.toString(); final downloads = p['downloads'];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12), hoverColor: green.withValues(alpha: .10),
                    onTap: () => setState(() { if (selected) { _selected.remove(id); } else { _selected.add(id); } }),
                    child: AnimatedContainer(duration: const Duration(milliseconds: 150), padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: selected ? const Color(0xFF14291C) : const Color(0xFF0F1A14), borderRadius: BorderRadius.circular(12), border: Border.all(color: selected ? green : const Color(0xFF26392D), width: selected ? 1.5 : 1)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [ClipRRect(borderRadius: BorderRadius.circular(8), child: iconUrl == null || iconUrl.isEmpty ? Container(width: 36, height: 36, color: green.withValues(alpha: .1), child: const Icon(Icons.blur_on_rounded, color: green, size: 19)) : Image.network(iconUrl, width: 36, height: 36, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 36, height: 36, color: green.withValues(alpha: .1), child: const Icon(Icons.blur_on_rounded, color: green, size: 19)))), const SizedBox(width: 8), Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))), Icon(selected ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded, color: selected ? green : const Color(0xFF91A497), size: 17)]),
                        const SizedBox(height: 7), Expanded(child: Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF91A497), fontSize: 10, height: 1.3))),
                        Row(children: [const Icon(Icons.download_rounded, size: 12, color: Color(0xFF91A497)), const SizedBox(width: 4), Expanded(child: Text(downloads is num ? _formatDownloads(downloads) : 'Modrinth', style: const TextStyle(color: Color(0xFF91A497), fontSize: 10), overflow: TextOverflow.ellipsis)), if (selected) const Text('ВЫБРАН', style: TextStyle(color: green, fontSize: 9, fontWeight: FontWeight.w700))]),
                      ]),
                    ),
                  );
                },
              );
            })),
      Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 14), child: Align(alignment: Alignment.centerLeft, child: Text('${_selected.length} выбрано · файлы будут установлены в shaderpacks', style: const TextStyle(color: Color(0xFF91A497), fontSize: 11)))),
    ]);
  }

  Widget _projectTypeChip(String value, String label, IconData icon) {
    final active = _projectType == value;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        if (_projectType == value) return;
        setState(() { _projectType = value; _results = []; _selected.clear(); });
        _searchProjects();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: active ? green.withValues(alpha: .13) : Colors.transparent, borderRadius: BorderRadius.circular(8), border: Border.all(color: active ? green.withValues(alpha: .25) : Colors.transparent)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: active ? green : const Color(0xFF91A497)), const SizedBox(width: 5), Text(label, style: TextStyle(color: active ? green : const Color(0xFF91A497), fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w500))]),
      ),
    );
  }

  String _formatDownloads(num value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)} млн загрузок';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)} тыс. загрузок';
    return '$value загрузок';
  }

  Widget _field(TextEditingController c, String label, {bool number = false}) => TextField(
    controller: c,
    keyboardType: number ? TextInputType.number : TextInputType.text,
    style: const TextStyle(color: Colors.white),
    decoration: _decoration(label),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(text, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
  );

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    hintText: label,
    labelStyle: const TextStyle(color: Color(0xFF91A497), fontSize: 12),
    hintStyle: const TextStyle(color: Color(0xFF65786C), fontSize: 12),
    contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
    filled: true,
    fillColor: const Color(0xFF0B1510),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF26392D))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF26392D))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: green, width: 1.3)),
  );
}
