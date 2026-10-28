
import 'package:flutter/material.dart';

const Color _railBackground = Color(0xFF0B120E);
const Color _railGreen = Color(0xFF55E878);
const Color _railBorder = Color(0xFF24352A);

class NavigationRailWidget extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onResetSettings;
  final bool isEditMode;
  final VoidCallback onToggleEditMode;

  const NavigationRailWidget({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onResetSettings,
    this.isEditMode = false,
    required this.onToggleEditMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _railBackground,
      child: Column(
        children: [
          const SizedBox(height: 22),

          // Логотип
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF67F589),
                  Color(0xFF239D4B),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: _railGreen.withOpacity(0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.grass_rounded, color: Color(0xFF07120A), size: 27),
          ),

          const SizedBox(height: 34),

          _buildNavItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
            index: 0,
          ),
          _buildNavItem(
            icon: Icons.view_module_outlined,
            selectedIcon: Icons.view_module_rounded,
            index: 1,
          ),
          _buildNavItem(
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
            index: 2,
          ),
          _buildNavItem(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings_rounded,
            index: 3,
          ),

          const Spacer(),

          Container(
            width: 34,
            height: 1,
            color: _railBorder,
            margin: const EdgeInsets.only(bottom: 14),
          ),

          _buildUtilityButton(
            icon: isEditMode
                ? Icons.check_rounded
                : Icons.edit_outlined,
            tooltip: isEditMode ? 'Завершить редактирование' : 'Редактировать',
            color: isEditMode ? _railGreen : const Color(0xFF829187),
            onTap: onToggleEditMode,
          ),

          _buildUtilityButton(
            icon: Icons.restart_alt_rounded,
            tooltip: 'Сбросить настройки',
            color: const Color(0xFF829187),
            onTap: onResetSettings,
          ),

          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData selectedIcon,
    required int index,
  }) {
    final selected = selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Tooltip(
        message: _getLabel(index),
        preferBelow: false,
        child: InkWell(
          onTap: () => onDestinationSelected(index),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF173522)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: selected
                    ? const Color(0xFF2E6540)
                    : Colors.transparent,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: 22,
                  color: selected
                      ? _railGreen
                      : const Color(0xFF829187),
                ),
                if (selected)
                  Positioned(
                    left: 0,
                    child: Container(
                      width: 3,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _railGreen,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUtilityButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 21, color: color),
        style: IconButton.styleFrom(
          fixedSize: const Size(44, 44),
          backgroundColor: const Color(0xFF111C15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _railBorder),
          ),
        ),
      ),
    );
  }

  String _getLabel(int index) {
    switch (index) {
      case 0:
        return 'Главная';
      case 1:
        return 'Сборки';
      case 2:
        return 'Профиль';
      case 3:
        return 'Настройки';
      default:
        return '';
    }
  }
}
