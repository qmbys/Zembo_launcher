import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/profile.dart';

const _bg = Color(0xFF080F0D);
const _card = Color(0xFF0F1A14);
const _green = Color(0xFF43E477);
const _muted = Color(0xFF91A79A);
const _border = Color(0xFF23382B);

class ModpackStoreScreen extends StatefulWidget {
  const ModpackStoreScreen({super.key, required this.minecraftFolder, required this.onInstalled});
  final String minecraftFolder;
  final ValueChanged<Profile> onInstalled;

  @override
  State<ModpackStoreScreen> createState() => _ModpackStoreScreenState();
}

class _ModpackStoreScreenState extends State<ModpackStoreScreen> {
  final _query = TextEditingController();
  final ScrollController _projectsScroll = ScrollController();
  int _offset = 0;
  int _searchRequestId = 0;
  bool _hasMore = true;
  bool _loadingMore = false;
  List<Map<String, dynamic>> _projects = [];
  List<String> _gameVersions = [];
  String _version = '';
  String _loader = 'Любой загрузчик';
  bool _loading = false;
  String? _error;
  String? _installingId;
  double _progress = 0;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _projectsScroll.addListener(_onProjectsScroll);
    _loadGameVersions();
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    _projectsScroll.dispose();
    super.dispose();
  }

  Future<void> _loadGameVersions() async {
    try {
      final response = await http.get(Uri.https('api.modrinth.com', '/v2/tag/game_version')).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as List;
      final versions = data.whereType<Map>().where((v) => v['version_type'] == 'release').map((v) => '${v['version']}').toList();
      if (!mounted) return;
      setState(() => _gameVersions = versions.take(100).toList());
    } catch (_) {}
  }

  void _onProjectsScroll() {
    if (!_projectsScroll.hasClients || _loading || _loadingMore || !_hasMore) return;
    if (_projectsScroll.position.extentAfter < 600) _search(loadMore: true);
  }

  Future<void> _search({bool loadMore = false}) async {
    if (loadMore) {
      if (_loading || _loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
      await _fetchPage(_offset, _searchRequestId, append: true);
      return;
    }
    final requestId = ++_searchRequestId;
    setState(() { _loading = true; _loadingMore = false; _error = null; _offset = 0; _hasMore = true; });
    await _fetchPage(0, requestId);
  }

  Future<void> _fetchPage(int offset, int requestId, {bool append = false}) async {
    try {
      final facets = <List<String>>[[ 'project_type:modpack' ]];
      if (_version.isNotEmpty) facets.add(['versions:$_version']);
      if (_loader == 'Fabric') facets.add(['categories:fabric']);
      if (_loader == 'Forge') facets.add(['categories:forge']);
      final uri = Uri.https('api.modrinth.com', '/v2/search', {
        'query': _query.text.trim(), 'facets': jsonEncode(facets), 'limit': '30', 'offset': '$offset', 'index': 'downloads',
      });
      final response = await http.get(uri, headers: const {'User-Agent':'ZemboLauncher/1.0.0 (modpack browser)', 'Accept':'application/json'}).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('Modrinth вернул код ${response.statusCode}');
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted || requestId != _searchRequestId) return;
      final hits = (body['hits'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      setState(() {
        if (append) {
          final known = _projects.map((e) => '${e['project_id'] ?? e['id'] ?? ''}').toSet();
          _projects.addAll(hits.where((e) => !known.contains('${e['project_id'] ?? e['id'] ?? ''}')));
        } else {
          _projects = hits;
        }
        _offset = offset + hits.length;
        _hasMore = hits.length == 30;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (mounted && requestId == _searchRequestId) setState(() {
        _error = 'Не удалось загрузить каталог. Проверь интернет и попробуй ещё раз.';
        if (append) _hasMore = false;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _install(Map<String, dynamic> project) async {
    final id = '${project['project_id'] ?? project['id'] ?? ''}';
    if (id.isEmpty || _installingId != null) return;
    String? tempPath;
    String? createdInstancePath;
    try {
      setState(() { _installingId = id; _progress = 0.02; _status = 'Получение версии сборки…'; });
      final versionsUri = Uri.https('api.modrinth.com', '/v2/project/$id/version', {
        if (_version.isNotEmpty) 'game_versions': jsonEncode([_version]),
        if (_loader != 'Любой загрузчик') 'loaders': jsonEncode([_loader.toLowerCase()]),
      });
      final versionsResponse = await http.get(versionsUri, headers: const {'User-Agent':'ZemboLauncher/1.0.0'}).timeout(const Duration(seconds: 20));
      if (versionsResponse.statusCode != 200) throw Exception('Не удалось получить версии модпака');
      final versions = (jsonDecode(versionsResponse.body) as List).whereType<Map<String,dynamic>>().toList();
      if (versions.isEmpty) throw Exception('Для выбранной версии Minecraft нет релиза этой сборки');
      final chosen = versions.first;
      final files = (chosen['files'] as List? ?? []).whereType<Map<String,dynamic>>().toList();
      final packFile = files.cast<Map<String,dynamic>?>().firstWhere((f) => f?['primary'] == true, orElse: () => files.isNotEmpty ? files.first : null);
      final downloadUrl = packFile?['url']?.toString();
      if (downloadUrl == null || downloadUrl.isEmpty) throw Exception('У релиза нет файла для скачивания');

      final safeName = _safeName('${project['title'] ?? 'Modpack'}');
      final instancePath = p.join(widget.minecraftFolder, 'instances', safeName);
      createdInstancePath = instancePath;
      if (await Directory(instancePath).exists()) throw Exception('Сборка "$safeName" уже существует. Удали или переименуй её и попробуй снова.');
      final tempDir = Directory(p.join(widget.minecraftFolder, 'temp', 'modpacks'));
      await tempDir.create(recursive: true);
      tempPath = p.join(tempDir.path, '$id.mrpack');
      setState(() { _status = 'Скачивание архива сборки…'; _progress = .08; });
      final req = await http.get(Uri.parse(downloadUrl), headers: const {'User-Agent':'ZemboLauncher/1.0.0'}).timeout(const Duration(minutes: 3));
      if (req.statusCode != 200) throw Exception('Ошибка скачивания архива (${req.statusCode})');
      await File(tempPath).writeAsBytes(req.bodyBytes, flush: true);
      final archive = ZipDecoder().decodeBytes(req.bodyBytes, verify: true);
      ArchiveFile? indexFile;
      for (final candidate in archive.files) { if (candidate.name == 'modrinth.index.json') { indexFile = candidate; break; } }
      if (indexFile == null) throw Exception('Архив не содержит modrinth.index.json — формат сборки не поддерживается');
      final index = jsonDecode(utf8.decode(indexFile.content as List<int>)) as Map<String,dynamic>;
      final dependencies = (index['dependencies'] as Map?)?.cast<String,dynamic>() ?? {};
      final mcVersion = '${dependencies['minecraft'] ?? _version}';
      final loader = dependencies.containsKey('fabric-loader') ? 'Fabric' : dependencies.containsKey('forge') ? 'Forge' : dependencies.containsKey('neoforge') ? 'NeoForge' : 'Vanilla';
      if (loader == 'NeoForge') throw Exception('Сборки NeoForge пока нельзя запускать в этой версии Zembo Launcher. Выбери Fabric или Forge.');
      final instance = Directory(instancePath);
      await instance.create(recursive: true);
      final overridesName = '${index['overrides'] ?? 'overrides'}';
      final overrideFiles = archive.files.where((f) => f.isFile && f.name.startsWith('$overridesName/')).toList();
      for (var i = 0; i < overrideFiles.length; i++) {
        final file = overrideFiles[i];
        final relative = file.name.substring(overridesName.length + 1);
        if (!_safeRelative(relative)) continue;
        final output = File(p.join(instancePath, p.fromUri(Uri(path: relative))));
        await output.parent.create(recursive: true);
        await output.writeAsBytes(file.content as List<int>, flush: false);
        if (i % 12 == 0 && mounted) setState(() { _progress = .15 + .25 * (i / math.max(1, overrideFiles.length)); _status = 'Распаковка файлов сборки…'; });
      }
      final packFiles = (index['files'] as List? ?? []).whereType<Map<String,dynamic>>().toList();
      for (var i = 0; i < packFiles.length; i++) {
        final item = packFiles[i];
        final env = item['env'] as Map?;
        if (env?['client'] == 'unsupported') continue;
        final relative = '${item['path'] ?? ''}';
        if (!_safeRelative(relative)) continue;
        final hashes = (item['hashes'] as Map?)?.cast<String,dynamic>() ?? {};
        final hash = '${hashes['sha1'] ?? ''}';
        final urls = (item['downloads'] as List? ?? []).map((u) => '$u').toList();
        if (hash.isEmpty || urls.isEmpty) continue;
        final target = File(p.join(instancePath, p.fromUri(Uri(path: relative))));
        if (await target.exists() && await _sha1(await target.readAsBytes()) == hash) continue;
        await target.parent.create(recursive: true);
        bool downloaded = false;
        for (final url in urls) {
          try {
            final response = await http.get(Uri.parse(url), headers: const {'User-Agent':'ZemboLauncher/1.0.0'}).timeout(const Duration(minutes: 2));
            if (response.statusCode == 200 && await _sha1(response.bodyBytes) == hash) {
              await target.writeAsBytes(response.bodyBytes, flush: false); downloaded = true; break;
            }
          } catch (_) {}
        }
        if (!downloaded) throw Exception('Не удалось скачать файл сборки: ${p.basename(relative)}');
        if (mounted && i % 3 == 0) setState(() { _progress = .4 + .55 * ((i + 1) / math.max(1, packFiles.length)); _status = 'Скачивание модов: ${i + 1} из ${packFiles.length}'; });
      }
      final profile = Profile(
        id: '${DateTime.now().millisecondsSinceEpoch}', name: safeName,
        version: mcVersion, loader: loader, ram: 4,
        icon: 'grass', gameDir: instancePath,
      );
      if (!mounted) return;
      setState(() { _progress = 1; _status = 'Сборка установлена'; });
      widget.onInstalled(profile);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Сборка «$safeName» установлена')));
    } catch (e) {
      if (createdInstancePath != null) { try { final d = Directory(createdInstancePath); if (await d.exists()) await d.delete(recursive: true); } catch (_) {} }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось установить сборку: ${e.toString().replaceFirst('Exception: ', '')}'), duration: const Duration(seconds: 7)));
    } finally {
      if (tempPath != null) { try { final f = File(tempPath); if (await f.exists()) await f.delete(); } catch (_) {} }
      if (mounted) setState(() { _installingId = null; _status = ''; _progress = 0; });
    }
  }

  String _safeName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isEmpty ? 'Modpack ${DateTime.now().millisecondsSinceEpoch}' : cleaned.substring(0, math.min(60, cleaned.length));
  }
  bool _safeRelative(String value) => value.isNotEmpty && !p.isAbsolute(value) && !value.split(RegExp(r'[/\\]')).contains('..');
  Future<String> _sha1(List<int> bytes) async {
    // Modrinth's sha1 verification is implemented with a compact pure-Dart SHA-1 below.
    return _sha1Hex(bytes);
  }
  String _sha1Hex(List<int> input) {
    final bytes = [...input, 0x80]; while (bytes.length % 64 != 56) { bytes.add(0); }
    final bitLength = input.length * 8;
    for (var i = 7; i >= 0; i--) { bytes.add((bitLength >> (i * 8)) & 0xff); }
    var h0=0x67452301, h1=0xEFCDAB89, h2=0x98BADCFE, h3=0x10325476, h4=0xC3D2E1F0;
    int rol(int x, int n) => ((x << n) | (x >> (32-n))) & 0xffffffff;
    for (var offset=0; offset<bytes.length; offset+=64) {
      final w=List<int>.filled(80,0);
      for(var i=0;i<16;i++){ final j=offset+i*4; w[i]=((bytes[j]<<24)|(bytes[j+1]<<16)|(bytes[j+2]<<8)|bytes[j+3])&0xffffffff; }
      for(var i=16;i<80;i++){w[i]=rol(w[i-3]^w[i-8]^w[i-14]^w[i-16],1);}
      var a=h0,b=h1,c=h2,d=h3,e=h4;
      for(var i=0;i<80;i++){int f,k;if(i<20){f=(b&c)|((~b)&d);k=0x5A827999;}else if(i<40){f=b^c^d;k=0x6ED9EBA1;}else if(i<60){f=(b&c)|(b&d)|(c&d);k=0x8F1BBCDC;}else{f=b^c^d;k=0xCA62C1D6;} final temp=(rol(a,5)+f+e+k+w[i])&0xffffffff;e=d;d=c;c=rol(b,30);b=a;a=temp;}
      h0=(h0+a)&0xffffffff;h1=(h1+b)&0xffffffff;h2=(h2+c)&0xffffffff;h3=(h3+d)&0xffffffff;h4=(h4+e)&0xffffffff;
    }
    return [h0,h1,h2,h3,h4].map((v)=>v.toRadixString(16).padLeft(8,'0')).join();
  }

  @override
  Widget build(BuildContext context) {
    return Container(color: _bg, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(28, 26, 28, 16), child: Row(children: [
        Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFF173522), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.view_module_rounded, color: _green, size: 25)),
        const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [Text('Готовые сборки', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)), SizedBox(height: 4), Text('Находи модпаки и устанавливай их в один клик', style: TextStyle(color: _muted, fontSize: 13))])),
      ])),
      Padding(padding: const EdgeInsets.fromLTRB(28, 0, 28, 18), child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(width: 290, child: TextField(controller: _query, onSubmitted: (_) => _search(), style: const TextStyle(color: Colors.white, fontSize: 13), decoration: InputDecoration(hintText: 'Поиск модпаков…', hintStyle: const TextStyle(color: _muted), prefixIcon: const Icon(Icons.search, color: _muted, size: 19), filled: true, fillColor: _card, contentPadding: const EdgeInsets.symmetric(vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _border)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _border))))),
        SizedBox(width: 165, child: DropdownButtonFormField<String>(value: _version.isEmpty ? '' : _version, isExpanded: true, dropdownColor: _card, style: const TextStyle(color: Colors.white, fontSize: 12), decoration: _filterDecoration('Minecraft'), items: [const DropdownMenuItem(value: '', child: Text('Все версии')), ..._gameVersions.map((v) => DropdownMenuItem(value: v, child: Text(v)))], onChanged: (v) { setState(() => _version = v ?? ''); _search(); })),
        SizedBox(width: 165, child: DropdownButtonFormField<String>(value: _loader, isExpanded: true, dropdownColor: _card, style: const TextStyle(color: Colors.white, fontSize: 12), decoration: _filterDecoration('Загрузчик'), items: const ['Любой загрузчик','Fabric','Forge'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) { setState(() => _loader = v ?? 'Любой загрузчик'); _search(); })),
        SizedBox(height: 46, child: ElevatedButton.icon(onPressed: _loading ? null : _search, icon: const Icon(Icons.tune_rounded, size: 17), label: const Text('Найти'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B4729), foregroundColor: _green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
      ])),
      if (_installingId != null) Padding(padding: const EdgeInsets.fromLTRB(28, 0, 28, 14), child: Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const SizedBox(width: 16,height:16,child:CircularProgressIndicator(strokeWidth:2,color:_green)),const SizedBox(width:10),Expanded(child:Text(_status,style:const TextStyle(color:Colors.white,fontSize:12))),Text('${(_progress*100).round()}%',style:const TextStyle(color:_green,fontSize:12,fontWeight:FontWeight.bold))]),const SizedBox(height:10),ClipRRect(borderRadius:BorderRadius.circular(5),child:LinearProgressIndicator(value:_progress, minHeight:5,backgroundColor:const Color(0xFF1A2A20),color:_green))]))),
      Expanded(child: _loading && _projects.isEmpty ? const Center(child:CircularProgressIndicator(color:_green)) : _error != null && _projects.isEmpty ? Center(child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.cloud_off_rounded,color:_muted,size:38),const SizedBox(height:12),Text(_error!,style:const TextStyle(color:_muted),textAlign:TextAlign.center),const SizedBox(height:12),TextButton(onPressed:_search,child:const Text('Повторить'))])) : _projects.isEmpty ? const Center(child:Text('Ничего не найдено. Попробуй изменить фильтры.',style:TextStyle(color:_muted))) : GridView.builder(controller:_projectsScroll,padding:const EdgeInsets.fromLTRB(28,0,28,26),itemCount:_projects.length+(_hasMore?1:0),gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:MediaQuery.sizeOf(context).width>1350?3:MediaQuery.sizeOf(context).width>850?2:1,crossAxisSpacing:14,mainAxisSpacing:14,mainAxisExtent:186),itemBuilder:(context,i){if(i>=_projects.length){if(!_loadingMore){WidgetsBinding.instance.addPostFrameCallback((_)=>_onProjectsScroll());}return const Center(child:Padding(padding:EdgeInsets.all(18),child:SizedBox(width:22,height:22,child:CircularProgressIndicator(color:_green,strokeWidth:2))));}return _projectCard(_projects[i]);})),
    ]));
  }

  InputDecoration _filterDecoration(String label) => InputDecoration(labelText:label,labelStyle:const TextStyle(color:_muted,fontSize:11),filled:true,fillColor:_card,contentPadding:const EdgeInsets.symmetric(horizontal:12,vertical:10),border:OutlineInputBorder(borderRadius:BorderRadius.circular(11),borderSide:const BorderSide(color:_border)),enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(11),borderSide:const BorderSide(color:_border)));

  Widget _projectCard(Map<String,dynamic> project) {
    final id='${project['project_id']??project['id']??''}';
    final icon='${project['icon_url']??''}';
    final loading=_installingId==id;
    final downloads=(project['downloads'] as num?)?.toInt()??0;
    final categories=(project['categories'] as List? ?? []).map((e)=>'$e').toList();
    return Container(decoration:BoxDecoration(color:_card,borderRadius:BorderRadius.circular(14),border:Border.all(color:_border)),child:Padding(padding:const EdgeInsets.all(14),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      ClipRRect(borderRadius:BorderRadius.circular(11),child:Container(width:58,height:58,color:const Color(0xFF17251D),child:icon.isEmpty?const Icon(Icons.inventory_2_rounded,color:_green,size:28):Image.network(icon,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const Icon(Icons.inventory_2_rounded,color:_green,size:28)))),
      const SizedBox(width:13),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${project['title']??'Без названия'}',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontSize:14,fontWeight:FontWeight.w700)),const SizedBox(height:5),Text('${project['description']??''}',maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:_muted,fontSize:11,height:1.25)),const Spacer(),Wrap(spacing:8,runSpacing:4,children:[_chip('${_formatDownloads(downloads)} загрузок'),...categories.where((c)=>['fabric','forge','neoforge','quilt'].contains(c)).take(2).map(_chip)]),const SizedBox(height:9),Align(alignment:Alignment.centerRight,child:SizedBox(height:32,child:ElevatedButton.icon(onPressed:_installingId!=null?null:()=>_install(project),icon:loading?const SizedBox(width:13,height:13,child:CircularProgressIndicator(strokeWidth:2,color:_green)):const Icon(Icons.download_rounded,size:16),label:Text(loading?'Установка…':'Установить'),style:ElevatedButton.styleFrom(backgroundColor:const Color(0xFF1B4729),foregroundColor:_green,disabledForegroundColor:_muted,padding:const EdgeInsets.symmetric(horizontal:11),textStyle:const TextStyle(fontSize:11,fontWeight:FontWeight.w600),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(8))))))]))])));
  }
  Widget _chip(String text)=>Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:4),decoration:BoxDecoration(color:const Color(0xFF18271D),borderRadius:BorderRadius.circular(6)),child:Text(text,style:const TextStyle(color:_muted,fontSize:9)));
  String _formatDownloads(int value) => value>=1000000?'${(value/1000000).toStringAsFixed(1)}M':value>=1000?'${(value/1000).toStringAsFixed(1)}K':'$value';
}
