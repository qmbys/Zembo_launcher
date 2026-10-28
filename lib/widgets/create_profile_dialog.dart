import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../services/forge_installer.dart';
import '../services/mojang_api_service.dart'; // <-- Используем твой сервис

class CreateProfileDialog extends StatefulWidget {
  final Profile? initialProfile;

  const CreateProfileDialog({super.key, this.initialProfile});

  @override
  State<CreateProfileDialog> createState() => _CreateProfileDialogState();
}

class _CreateProfileDialogState extends State<CreateProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _ramController;

  String _selectedVersion = '';
  String _selectedLoader = 'Fabric';
  String _selectedIcon = 'stone';
  String _selectedForgeVersion = '';
  
  List<String> _availableVersions = [];
  List<String> _availableForgeVersions = [];
  bool _isLoadingVersions = true;
  bool _isLoadingForgeVersions = false;

  final List<String> _availableLoaders = ['Vanilla', 'Fabric', 'Forge'];

  final List<Map<String, dynamic>> _availableIcons = [
    {'id': 'stone', 'name': 'Камень', 'icon': Icons.square, 'color': const Color(0xFF808080)},
    {'id': 'grass', 'name': 'Трава', 'icon': Icons.landscape, 'color': const Color(0xFF43E477)},
    {'id': 'diamond', 'name': 'Алмаз', 'icon': Icons.diamond, 'color': const Color(0xFF00BCD4)},
    {'id': 'lava', 'name': 'Лава', 'icon': Icons.local_fire_department, 'color': const Color(0xFFFF5722)},
    {'id': 'water', 'name': 'Вода', 'icon': Icons.water_drop, 'color': const Color(0xFF2196F3)},
    {'id': 'ice', 'name': 'Лёд', 'icon': Icons.ac_unit, 'color': const Color(0xFFB3E5FC)},
    {'id': 'wood', 'name': 'Дерево', 'icon': Icons.park, 'color': const Color(0xFF795548)},
    {'id': 'gold', 'name': 'Золото', 'icon': Icons.bolt, 'color': const Color(0xFFFFC107)},
    {'id': 'obsidian', 'name': 'Обсидиан', 'icon': Icons.hexagon, 'color': const Color(0xFF311B92)},
    {'id': 'sand', 'name': 'Песок', 'icon': Icons.grain, 'color': const Color(0xFFFFE082)},
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialProfile?.name ?? '');
    _ramController = TextEditingController(text: widget.initialProfile?.ram.toString() ?? '4');

    if (widget.initialProfile != null) {
      _selectedVersion = widget.initialProfile!.version;
      _selectedLoader = widget.initialProfile!.loader;
      _selectedIcon = widget.initialProfile!.icon.isNotEmpty 
          ? widget.initialProfile!.icon 
          : 'stone';
      _selectedForgeVersion = widget.initialProfile!.forgeVersion ?? '';
    }

    _loadVersions();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ramController.dispose();
    super.dispose();
  }

  Future<void> _loadVersions() async {
    setState(() {
      _isLoadingVersions = true;
    });

    // Загружаем версии через твой MojangApiService
    final mojangVersions = await MojangApiService.fetchVersions();
    
    // Фильтруем только релизные версии и берем первые 50 (чтобы список не был бесконечным)
    final releaseVersions = mojangVersions
        .where((v) => v.type == 'release')
        .map((v) => v.id)
        .take(50)
        .toList();

    if (mounted) {
      setState(() {
        _availableVersions = releaseVersions;
        _isLoadingVersions = false;
        
        // Если текущая версия не в списке (или список пуст), выбираем первую доступную
        if (!_availableVersions.contains(_selectedVersion) && _availableVersions.isNotEmpty) {
          _selectedVersion = _availableVersions.first;
        }
      });
      
      // Если выбран Forge, сразу загружаем версии для текущей версии Minecraft
      if (_selectedLoader == 'Forge' && _selectedVersion.isNotEmpty) {
        _loadForgeVersions();
      }
    }
  }

  Future<void> _loadForgeVersions() async {
    if (_selectedVersion.isEmpty) return;
    
    setState(() {
      _isLoadingForgeVersions = true;
    });

    final versions = await ForgeInstaller.getAvailableForgeVersions(_selectedVersion);

    if (mounted) {
      setState(() {
        _availableForgeVersions = versions;
        _isLoadingForgeVersions = false;
        if (versions.isNotEmpty) {
          if (!_availableForgeVersions.contains(_selectedForgeVersion)) {
            _selectedForgeVersion = versions.first;
          }
        } else {
          _selectedForgeVersion = '';
        }
      });
    }
  }

  void _saveProfile() {
    if (!_formKey.currentState!.validate()) return;

    final ram = int.tryParse(_ramController.text) ?? 4;
    final profile = Profile(
      id: widget.initialProfile?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      version: _selectedVersion,
      loader: _selectedLoader,
      ram: ram,
      icon: _selectedIcon,
      javaPath: widget.initialProfile?.javaPath ?? '',
      forgeVersion: _selectedLoader == 'Forge' ? _selectedForgeVersion : '',
    );

    Navigator.pop(context, profile);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialProfile != null;

    return Dialog(
      backgroundColor: const Color(0xFF111C16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 500,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isEditing ? Icons.edit : Icons.add_circle,
                    color: const Color(0xFF43E477),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEditing ? 'Редактировать сборку' : 'Создать сборку',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Название сборки',
                          labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF43E477)),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Введите название';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      _buildDropdown(
                        label: 'Версия Minecraft',
                        value: _selectedVersion,
                        items: _isLoadingVersions
                            ? ['Загрузка версий...']
                            : (_availableVersions.isEmpty ? ['Не найдено'] : _availableVersions),
                        onChanged: _isLoadingVersions || _availableVersions.isEmpty
                            ? null
                            : (value) {
                                if (value != null && value != 'Не найдено' && value != 'Загрузка версий...') {
                                  setState(() {
                                    _selectedVersion = value;
                                    if (_selectedLoader == 'Forge') {
                                      _loadForgeVersions();
                                    }
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 16),

                      _buildDropdown(
                        label: 'Загрузчик',
                        value: _selectedLoader,
                        items: _availableLoaders,
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedLoader = value;
                              if (value == 'Forge') {
                                _loadForgeVersions();
                              } else {
                                _selectedForgeVersion = '';
                              }
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      if (_selectedLoader == 'Forge') ...[
                        _buildDropdown(
                          label: 'Версия Forge',
                          value: _selectedForgeVersion,
                          items: _isLoadingForgeVersions
                              ? ['Загрузка...']
                              : (_availableForgeVersions.isEmpty ? ['Не найдено'] : _availableForgeVersions),
                          onChanged: _isLoadingForgeVersions || _availableForgeVersions.isEmpty
                              ? null
                              : (value) {
                                  if (value != null && value != 'Не найдено' && value != 'Загрузка...') {
                                    setState(() {
                                      _selectedForgeVersion = value;
                                    });
                                  }
                                },
                        ),
                        const SizedBox(height: 16),
                      ],

                      TextFormField(
                        controller: _ramController,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'ОЗУ (GB)',
                          labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                          suffixText: 'GB',
                          suffixStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF43E477)),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Введите количество ОЗУ';
                          }
                          final ram = int.tryParse(value);
                          if (ram == null || ram < 1 || ram > 32) {
                            return 'Введите число от 1 до 32';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      const Text(
                        'Иконка блока',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _availableIcons.map((block) {
                            final isSelected = _selectedIcon == block['id'];
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedIcon = block['id'] as String;
                                });
                              },
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: (block['color'] as Color).withOpacity(isSelected ? 0.3 : 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? block['color'] as Color
                                        : Colors.white.withOpacity(0.2),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      block['icon'] as IconData,
                                      color: block['color'] as Color,
                                      size: 24,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      block['name'] as String,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 9,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Отмена',
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF43E477),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      isEditing ? 'Сохранить' : 'Создать',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : (items.isNotEmpty ? items.first : null),
              isExpanded: true,
              dropdownColor: const Color(0xFF111C16),
              style: const TextStyle(color: Colors.white, fontSize: 16),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
              items: items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(item),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}