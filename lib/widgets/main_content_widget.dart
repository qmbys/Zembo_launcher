import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../widgets/profile_card.dart';
import '../screens/profile_settings_screen.dart';
import '../screens/mod_store_screen.dart';

class MainContentWidget extends StatelessWidget {
  final List<Profile> profiles;
  final String? selectedProfileId;
  final VoidCallback onCreateProfile;
  final ValueChanged<String> onSelectProfile;
  final ValueChanged<Profile> onUpdateProfile;

  const MainContentWidget({
    super.key,
    required this.profiles,
    required this.selectedProfileId,
    required this.onCreateProfile,
    required this.onSelectProfile,
    required this.onUpdateProfile,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ZemboLauncher',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 24),
          const _HeroBanner(),
          const SizedBox(height: 32),

          // Секция сборок
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Мои сборки',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onCreateProfile,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Создать сборку',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Список сборок или пустое состояние
          if (profiles.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 64,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Нет сборок',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Создайте первую сборку, чтобы начать игру',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: profiles.map((profile) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ProfileCard(
                    profile: profile,
                    isSelected: selectedProfileId == profile.id,
                    onTap: () => onSelectProfile(profile.id),
                    onSettings: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ProfileSettingsScreen(
                            profile: profile,
                            onSave: (updatedProfile) {
                              onUpdateProfile(updatedProfile);
                            },
                          ),
                        ),
                      );
                    },
                  ),
                );
              }).toList(),
            ),

          // Кнопка магазина модов (показывается только если есть выбранная сборка)
          if (profiles.isNotEmpty && selectedProfileId != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.5)),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    final selectedProfile = profiles.firstWhere(
                      (p) => p.id == selectedProfileId,
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ModStoreScreen(
                          gameVersion: selectedProfile.version,
                          loader: selectedProfile.loader.toLowerCase(),
                        ),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shopping_bag, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Магазин модов и ресурспаков',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Game Versions
          Text(
            'Game Versions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          const _GameVersionsRow(),
          const SizedBox(height: 32),

          // Latest News
          Text(
            'Latest News',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          const _LatestNewsRow(),
        ],
      ),
    );
  }
}

// ==========================================
// Вспомогательные виджеты
// ==========================================

class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 320,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5E20), Color(0xFF004D40), Color(0xFF0D2620)],
        ),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -50,
            top: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    colorScheme.primary.withValues(alpha: 0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 40,
            bottom: 20,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: colorScheme.primary.withValues(alpha: 0.1),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
              ),
              child: const Icon(Icons.landscape, size: 100, color: Colors.white24),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Featured World',
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.secondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Crystal Peaks\nAdventure',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.primary.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    'Explore',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GameVersionsRow extends StatelessWidget {
  const _GameVersionsRow();

  @override
  Widget build(BuildContext context) {
    const versions = [
      _VersionCard(
        icon: Icons.crop_square_rounded,
        iconColor: Color(0xFF43E477),
        title: 'Latest Release',
        subtitle: '1.20.4',
      ),
      _VersionCard(
        icon: Icons.handyman,
        iconColor: Color(0xFF00BCD4),
        title: 'Snapshot',
        subtitle: '24w12a',
      ),
      _VersionCard(
        icon: Icons.build,
        iconColor: Color(0xFFFF9800),
        title: 'Forge',
        subtitle: '1.20.1',
      ),
      _VersionCard(
        icon: Icons.diamond,
        iconColor: Color(0xFF00E676),
        title: 'OptiFine',
        subtitle: '1.20.4',
      ),
    ];
    return Row(
      children: versions.map((v) => Expanded(child: v)).toList(),
    );
  }
}

class _VersionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _VersionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LatestNewsRow extends StatelessWidget {
  const _LatestNewsRow();

  @override
  Widget build(BuildContext context) {
    const news = [
      _NewsCard(
        gradient: LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF1A237E)]),
        icon: Icons.videocam,
        title: 'Minecraft Live 2024 Recap',
        subtitle: 'Watch the full event now',
      ),
      _NewsCard(
        gradient: LinearGradient(colors: [Color(0xFFE65100), Color(0xFFBF360C)]),
        icon: Icons.pets,
        title: 'New Mob Vote Details',
        subtitle: 'Cast your vote today',
      ),
      _NewsCard(
        gradient: LinearGradient(colors: [Color(0xFF1B5E20), Color(0xFF004D40)]),
        icon: Icons.shopping_bag,
        title: 'Marketplace Spring Sale',
        subtitle: 'Up to 50% off skins',
      ),
    ];
    return Row(
      children: news.map((n) => Expanded(child: n)).toList(),
    );
  }
}

class _NewsCard extends StatelessWidget {
  final Gradient gradient;
  final IconData icon;
  final String title;
  final String subtitle;

  const _NewsCard({
    required this.gradient,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: gradient,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}