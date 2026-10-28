import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';

/// Custom title bar for Zembo Launcher. Keep the app mark on the left,
/// the title centered, and native-style window controls on the right.
class ZemboTitleBar extends StatefulWidget {
  const ZemboTitleBar({super.key});

  @override
  State<ZemboTitleBar> createState() => _ZemboTitleBarState();
}

class _ZemboTitleBarState extends State<ZemboTitleBar> with WindowListener {
  static const _background = Color(0xFF07110E);
  static const _border = Color(0xFF18372B);
  static const _green = Color(0xFF43E477);
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _readMaximized();
  }

  Future<void> _readMaximized() async {
    try {
      final value = await windowManager.isMaximized();
      if (mounted) setState(() => _maximized = value);
    } catch (_) {
      // Keep the default restore/maximize icon if the window is not ready yet.
    }
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: _background,
        border: Border(bottom: BorderSide(color: _border, width: 0.8)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The drag region stays behind all controls so buttons remain clickable.
          const Positioned.fill(child: DragToMoveArea(child: SizedBox.expand())),

          // A single centered title. Do not put a second logo here: that caused
          // the icon/title collision visible in the previous build.
          IgnorePointer(
            child: Center(
              child: Text(
                'Zembo Launcher',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFFE3F0E9),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  decoration: TextDecoration.none,
                  decorationColor: Colors.transparent,
                  decorationThickness: 0,
                ),
              ),
            ),
          ),

          // App mark at the left edge, separate from the centered title.
          const Positioned(
            left: 14,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Center(
                child: Icon(Icons.spa_rounded, size: 17, color: _green),
              ),
            ),
          ),

          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TitleBarButton(
                  icon: Icons.remove_rounded,
                  tooltip: 'Свернуть',
                  onPressed: () => windowManager.minimize(),
                ),
                _TitleBarButton(
                  icon: _maximized
                      ? Icons.filter_none_rounded
                      : Icons.crop_square_rounded,
                  tooltip: _maximized ? 'Восстановить' : 'Развернуть',
                  onPressed: () async {
                    if (await windowManager.isMaximized()) {
                      await windowManager.unmaximize();
                    } else {
                      await windowManager.maximize();
                    }
                    await _readMaximized();
                  },
                ),
                _TitleBarButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Закрыть',
                  closeButton: true,
                  onPressed: () => windowManager.close(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBarButton extends StatefulWidget {
  const _TitleBarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.closeButton = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool closeButton;

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.closeButton
        ? const Color(0xFFC94141)
        : const Color(0xFF173328);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered ? hoverColor : Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          hoverColor: Colors.transparent,
          splashColor: Colors.white.withOpacity(0.06),
          child: SizedBox(
            width: 44,
            height: 37,
            child: Icon(
              widget.icon,
              size: 15,
              color: _hovered && widget.closeButton
                  ? Colors.white
                  : _hovered
                      ? const Color(0xFFE2F1E8)
                      : const Color(0xFF8DA69A),
            ),
          ),
        ),
      ),
    );
  }
}
