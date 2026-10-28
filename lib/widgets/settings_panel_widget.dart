
import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../models/settings.dart';

const Color _panelBackground = Color(0xFF0B120E);
const Color _panelCard = Color(0xFF0F1A14);
const Color _panelGreen = Color(0xFF43E477);
const Color _panelBorder = Color(0xFF23382B);
const Color _panelMuted = Color(0xFF91A497);

class SettingsPanelWidget extends StatelessWidget {
  final Future<void> Function() onLaunch;
  final String launchPhase;
  final Profile? selectedProfile;
  final LauncherSettings? settings;
  final bool isEditMode;
  final VoidCallback? onAddWidget;
  final VoidCallback? onAddProfile;

  const SettingsPanelWidget({
    super.key,
    required this.onLaunch,
    required this.launchPhase,
    this.selectedProfile,
    this.settings,
    this.isEditMode = false,
    this.onAddWidget,
    this.onAddProfile,
  });

  @override
  Widget build(BuildContext context) {
    final profile = selectedProfile;

    return Container(
      color: _panelBackground,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFF173522),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF2C5A39),
                        ),
                      ),
                      child: const Icon(
                        Icons.tune_rounded,
                        color: _panelGreen,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Text(
                        'Панель запуска',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Карточка выбранной сборки
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _panelCard,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: _panelBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            color: _panelGreen,
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'ВЫБРАННАЯ СБОРКА',
                            style: TextStyle(
                              color: _panelMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        profile?.name ?? 'Сборка не выбрана',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildInfoRow(
                        Icons.tag_rounded,
                        'Версия',
                        profile?.version ?? '—',
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        Icons.extension_outlined,
                        'Загрузчик',
                        profile?.loader ?? '—',
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        Icons.memory_rounded,
                        'Оперативная память',
                        profile == null ? '—' : '${profile.ram} GB',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Информация об окружении
                const Text(
                  'ОКРУЖЕНИЕ',
                  style: TextStyle(
                    color: _panelMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),

                _buildEnvironmentRow(
                  Icons.person_outline_rounded,
                  'Игрок',
                  settings?.nickname ?? '—',
                ),

                const SizedBox(height: 10),

                _buildEnvironmentRow(
                  Icons.terminal_rounded,
                  'Java',
                  _javaName(settings?.javaPath),
                ),

                const SizedBox(height: 20),

                const Spacer(),

                if (onAddProfile != null) ...[
                  OutlinedButton.icon(
                    onPressed: onAddProfile,
                    icon: const Icon(Icons.add_rounded, size: 19),
                    label: const Text('Добавить сборку'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFCFD9D0),
                      minimumSize: const Size(double.infinity, 46),
                      side: const BorderSide(color: _panelBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                _buildLaunchButton(profile != null),
              ],
            ),
          ),

          if (isEditMode && onAddWidget != null)
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                tooltip: 'Добавить виджет',
                onPressed: onAddWidget,
                icon: const Icon(
                  Icons.add_circle_outline,
                  color: _panelGreen,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Icon(icon, color: _panelMuted, size: 16),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: _panelMuted,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEnvironmentRow(
    IconData icon,
    String label,
    String value,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: _panelCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _panelBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: _panelGreen, size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _panelMuted,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _javaName(String? javaPath) {
    if (javaPath == null || javaPath.trim().isEmpty) {
      return 'Не указана';
    }

    final normalized = javaPath.replaceAll('/', '\\');
    final parts = normalized.split('\\');
    return parts.isEmpty ? normalized : parts.last;
  }

  String _statusText() {
    switch (launchPhase) {
      case 'loading':
        return 'Подготовка Minecraft...';
      case 'running':
        return 'Minecraft запускается';
      default:
        return 'Готов к запуску';
    }
  }

  Widget _buildLaunchButton(bool hasProfile) {
    final isLoading = launchPhase == 'loading';
    final isRunning = launchPhase == 'running';

    final buttonColor = isRunning
        ? const Color(0xFFB74343)
        : _panelGreen;

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: isLoading || !hasProfile ? null : onLaunch,
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          disabledBackgroundColor: const Color(0xFF27352B),
          foregroundColor: isRunning
              ? Colors.white
              : const Color(0xFF07120A),
          disabledForegroundColor: _panelMuted,
          elevation: isLoading ? 0 : 5,
          shadowColor: buttonColor.withOpacity(0.22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              Icon(
                isRunning
                    ? Icons.stop_rounded
                    : Icons.play_arrow_rounded,
                size: 25,
              ),
            const SizedBox(width: 9),
            Text(
              isLoading
                  ? 'Подготовка...'
                  : isRunning
                      ? 'Остановить'
                      : 'Играть',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
