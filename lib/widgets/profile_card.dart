import 'package:flutter/material.dart';

import '../models/profile.dart';

const Color _pixelGreen = Color(0xFF55E878);
const Color _pixelBorder = Color(0xFF294333);
const Color _pixelMuted = Color(0xFF91A497);

/// Compact, pixel-inspired profile tile for the launcher home screen.
class ProfileCard extends StatelessWidget {
  final Profile profile;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onSettings;
  final VoidCallback? onOpenFolder;

  const ProfileCard({
    super.key,
    required this.profile,
    required this.isSelected,
    required this.onTap,
    this.onSettings,
    this.onOpenFolder,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF10271A) : const Color(0xFF0E1913),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: isSelected ? _pixelGreen : _pixelBorder,
          width: isSelected ? 1.6 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: _pixelGreen.withOpacity(0.07),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              // Small block shapes add a restrained Minecraft/pixel-art feel.
              Positioned(
                right: 10,
                bottom: 9,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: isSelected ? 0.17 : 0.10,
                    child: const _PixelDecoration(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 9, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _PixelProfileIcon(icon: profile.icon),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            profile.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFF1F7F2),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Container(
                            width: 19,
                            height: 19,
                            decoration: const BoxDecoration(
                              color: _pixelGreen,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 13,
                              color: Color(0xFF06200E),
                            ),
                          )
                        else if (onSettings != null)
                          SizedBox(
                            width: 25,
                            height: 25,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Настройки сборки',
                              onPressed: onSettings,
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                size: 17,
                                color: _pixelMuted,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        _TinyTag(label: profile.loader, green: true),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            profile.version,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _pixelMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.memory_rounded,
                          size: 13,
                          color: _pixelMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${profile.ram} GB',
                          style: const TextStyle(
                            color: Color(0xFFB9C8BD),
                            fontSize: 10,
                          ),
                        ),
                        if (onOpenFolder != null) ...[
                          const SizedBox(width: 4),
                          SizedBox(
                            width: 23,
                            height: 23,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Открыть папку сборки',
                              onPressed: onOpenFolder,
                              icon: const Icon(
                                Icons.folder_open_rounded,
                                size: 14,
                                color: _pixelMuted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PixelProfileIcon extends StatelessWidget {
  final String icon;

  const _PixelProfileIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 37,
      height: 37,
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A20),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFF3B4B35)),
      ),
      alignment: Alignment.center,
      child: Text(icon, style: const TextStyle(fontSize: 21)),
    );
  }
}

class _TinyTag extends StatelessWidget {
  final String label;
  final bool green;

  const _TinyTag({required this.label, this.green = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: green ? const Color(0xFF172D1E) : const Color(0xFF1A241D),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: green ? const Color(0xFF294B32) : _pixelBorder,
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF9DE8AC),
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PixelDecoration extends StatelessWidget {
  const _PixelDecoration();

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF55E878);
    return SizedBox(
      width: 39,
      height: 29,
      child: Stack(
        children: const [
          Positioned(right: 0, bottom: 0, child: _Pixel(color: color, size: 10)),
          Positioned(right: 11, bottom: 0, child: _Pixel(color: color, size: 10)),
          Positioned(right: 0, bottom: 11, child: _Pixel(color: color, size: 10)),
          Positioned(right: 22, bottom: 11, child: _Pixel(color: color, size: 10)),
          Positioned(right: 11, bottom: 22, child: _Pixel(color: color, size: 7)),
        ],
      ),
    );
  }
}

class _Pixel extends StatelessWidget {
  final Color color;
  final double size;

  const _Pixel({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        color: color,
      );
}
