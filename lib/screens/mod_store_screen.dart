import 'dart:async';
import 'package:flutter/material.dart';
import '../services/modrinth_service.dart';

class ModStoreScreen extends StatefulWidget {
  final String gameVersion;
  final String loader;

  const ModStoreScreen({
    super.key,
    required this.gameVersion,
    required this.loader,
  });

  @override
  State<ModStoreScreen> createState() => _ModStoreScreenState();
}

class _ModStoreScreenState extends State<ModStoreScreen> with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF43E477);
  static const _panel = Color(0xFF0D1713);
  static const _card = Color(0xFF111F17);
  static const _border = Color(0xFF26392D);
  static const _muted = Color(0xFF91A497);

  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<ModrinthMod> _mods = [];
  List<ModrinthMod> _resourcePacks = [];
  bool _isLoading = true;
  String? _loadError;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadInitialContent();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialContent() async {
    await _search('', showLoading: true);
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () => _search(query));
    setState(() {});
  }

  Future<void> _search(String query, {bool showLoading = true}) async {
    final requestId = ++_requestId;
    if (showLoading && mounted) setState(() { _isLoading = true; _loadError = null; });

    final results = await Future.wait([
      ModrinthService.searchMods(query, gameVersion: widget.gameVersion, loader: widget.loader),
      ModrinthService.searchResourcePacks(query, gameVersion: widget.gameVersion),
    ]);
    if (!mounted || requestId != _requestId) return;

    setState(() {
      _mods = results[0];
      _resourcePacks = results[1];
      _isLoading = false;
      _loadError = _mods.isEmpty && _resourcePacks.isEmpty
          ? 'Не удалось загрузить каталог. Проверь подключение к интернету и попробуй ещё раз.'
          : null;
    });
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(color: _green.withValues(alpha: .12), borderRadius: BorderRadius.circular(14), border: Border.all(color: _green.withValues(alpha: .25))),
                          child: const Icon(Icons.widgets_rounded, color: _green, size: 23),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Моды и ресурспаки', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, fontSize: 25)),
                            const SizedBox(height: 4),
                            Text('Популярное для Minecraft ${widget.gameVersion} · ${widget.loader}', style: const TextStyle(color: _muted, fontSize: 12)),
                          ]),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                          decoration: BoxDecoration(color: _green.withValues(alpha: .09), borderRadius: BorderRadius.circular(9), border: Border.all(color: _green.withValues(alpha: .22))),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.public_rounded, color: _green, size: 14), SizedBox(width: 6), Text('MODRINTH', style: TextStyle(color: _green, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .8))]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: _onSearchChanged,
                            onSubmitted: (query) => _search(query),
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Поиск модов и ресурспаков…',
                              prefixIcon: const Icon(Icons.search_rounded, color: _muted, size: 19),
                              suffixIcon: _searchController.text.isEmpty ? null : IconButton(
                                onPressed: () { _searchController.clear(); _onSearchChanged(''); },
                                icon: const Icon(Icons.close_rounded, size: 17, color: _muted),
                                tooltip: 'Очистить поиск',
                              ),
                              filled: true,
                              fillColor: _panel,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _green, width: 1.3)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton.filledTonal(
                          onPressed: () => _search(_searchController.text),
                          tooltip: 'Обновить каталог',
                          style: IconButton.styleFrom(backgroundColor: _card, foregroundColor: _green, side: const BorderSide(color: _border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
                          icon: const Icon(Icons.refresh_rounded, size: 19),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
                      child: TabBar(
                        controller: _tabController,
                        dividerColor: Colors.transparent,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(color: _green.withValues(alpha: .14), borderRadius: BorderRadius.circular(9), border: Border.all(color: _green.withValues(alpha: .22))),
                        labelColor: _green,
                        unselectedLabelColor: _muted,
                        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        tabs: [
                          Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.extension_rounded, size: 16), const SizedBox(width: 8), const Text('Моды'), _countPill(_mods.length)])),
                          Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.wallpaper_rounded, size: 16), const SizedBox(width: 8), const Text('Ресурспаки'), _countPill(_resourcePacks.length)])),
                        ],
                      ),
                    ),
                    const SizedBox(height: 13),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildGrid(_mods, isResourcePack: false),
                          _buildGrid(_resourcePacks, isResourcePack: true),
                        ],
                      ),
                    ),
                  ],
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
      child: Row(children: [
        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, size: 19), color: _muted, tooltip: 'Назад'),
        const SizedBox(width: 5),
        const Icon(Icons.spa_rounded, color: _green, size: 17),
        const SizedBox(width: 9),
        const Text('Zembo Launcher', style: TextStyle(color: Color(0xFFE3F0E9), fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: .4)),
        const Spacer(),
        const Text('БИБЛИОТЕКА', style: TextStyle(color: _muted, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _countPill(int count) => Padding(
    padding: const EdgeInsets.only(left: 7),
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: _green.withValues(alpha: .12), borderRadius: BorderRadius.circular(6)), child: Text('$count', style: const TextStyle(color: _green, fontSize: 10, fontWeight: FontWeight.w700))),
  );

  Widget _buildGrid(List<ModrinthMod> items, {required bool isResourcePack}) {
    if (_isLoading && items.isEmpty) return const Center(child: CircularProgressIndicator(color: _green, strokeWidth: 2));
    if (items.isEmpty) {
      return Center(child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(_loadError == null ? Icons.search_off_rounded : Icons.cloud_off_rounded, size: 38, color: _muted),
          const SizedBox(height: 12),
          Text(_loadError == null ? 'Ничего не найдено' : 'Каталог временно недоступен', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(_loadError ?? 'Попробуй другое название или очисти поиск, чтобы посмотреть популярные проекты.', textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 12, height: 1.5)),
          const SizedBox(height: 15),
          OutlinedButton.icon(onPressed: () { _searchController.clear(); _search(''); }, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Показать популярное'), style: OutlinedButton.styleFrom(foregroundColor: _green, side: const BorderSide(color: _border))),
        ]),
      ));
    }

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final crossAxisCount = width >= 1120 ? 4 : width >= 790 ? 3 : width >= 510 ? 2 : 1;
      return GridView.builder(
        padding: const EdgeInsets.only(bottom: 8, right: 2),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          mainAxisExtent: crossAxisCount == 1 ? 142 : 174,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) => _ModCard(mod: items[index], isResourcePack: isResourcePack),
      );
    });
  }
}

class _ModCard extends StatelessWidget {
  static const _green = Color(0xFF43E477);
  static const _card = Color(0xFF111F17);
  static const _border = Color(0xFF26392D);
  static const _muted = Color(0xFF91A497);

  final ModrinthMod mod;
  final bool isResourcePack;

  const _ModCard({required this.mod, required this.isResourcePack});

  String _formatDownloads(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showDetails(context),
            hoverColor: _green.withValues(alpha: .035),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: _green.withValues(alpha: .08), borderRadius: BorderRadius.circular(10), border: Border.all(color: _green.withValues(alpha: .13))),
                      clipBehavior: Clip.antiAlias,
                      child: mod.iconUrl.isNotEmpty
                          ? Image.network(mod.iconUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(isResourcePack ? Icons.wallpaper_rounded : Icons.extension_rounded, color: _green, size: 21))
                          : Icon(isResourcePack ? Icons.wallpaper_rounded : Icons.extension_rounded, color: _green, size: 21),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(mod.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(mod.categories.take(2).map((e) => e.replaceAll('-', ' ')).join(' · ').isEmpty ? (isResourcePack ? 'Ресурспак' : 'Мод Minecraft') : mod.categories.take(2).map((e) => e.replaceAll('-', ' ')).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _green, fontSize: 10, fontWeight: FontWeight.w600)),
                    ])),
                    const SizedBox(width: 4),
                    const Icon(Icons.open_in_new_rounded, size: 14, color: _muted),
                  ]),
                  const SizedBox(height: 10),
                  Expanded(child: Text(mod.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 11, height: 1.4))),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.download_rounded, size: 13, color: _muted),
                    const SizedBox(width: 4),
                    Text(_formatDownloads(mod.downloads), style: const TextStyle(color: _muted, fontSize: 10)),
                    const Spacer(),
                    SizedBox(
                      height: 30,
                      child: FilledButton.icon(
                        onPressed: () => _showDetails(context),
                        icon: const Icon(Icons.add_rounded, size: 15),
                        label: const Text('Подробнее', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                        style: FilledButton.styleFrom(backgroundColor: _green.withValues(alpha: .13), foregroundColor: _green, padding: const EdgeInsets.symmetric(horizontal: 9), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 0),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF111F17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: _border)),
        title: Row(children: [
          if (mod.iconUrl.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(mod.iconUrl, width: 36, height: 36, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.extension_rounded, color: _green))) else const Icon(Icons.extension_rounded, color: _green),
          const SizedBox(width: 10),
          Expanded(child: Text(mod.name, style: const TextStyle(color: Colors.white, fontSize: 17))),
        ]),
        content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(mod.description, style: const TextStyle(color: _muted, fontSize: 13, height: 1.5)),
          const SizedBox(height: 14),
          Row(children: [const Icon(Icons.download_rounded, size: 15, color: _green), const SizedBox(width: 6), Text('${_formatDownloads(mod.downloads)} скачиваний', style: const TextStyle(color: _muted, fontSize: 12))]),
          const SizedBox(height: 8),
          const Text('Проект найден в каталоге Modrinth. Установка непосредственно в сборку пока не подключена.', style: TextStyle(color: _muted, fontSize: 11, height: 1.4)),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Закрыть', style: TextStyle(color: _green)))],
      ),
    );
  }
}
