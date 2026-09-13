import 'package:flutter/material.dart';
import '../../theme/animation_constants.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../shared/boojy_dropdown.dart';
import '../shared/boojy_wordmark.dart';

/// The "▲udio" wordmark at the far left of the bar, now the app-level menu
/// (Settings, Keyboard Shortcuts, Start Screen). Project actions stay under
/// the project name beside it. On macOS these items also live in the system
/// menu bar; on Windows this button is the only route to them.
///
/// The triangle is still the engine-health light: brand accent normally,
/// [BoojyColors.error] red when the engine failed to start (tooltip says
/// where to look).
class AppMenuButton extends StatefulWidget {
  final bool engineFailed;

  /// Slightly smaller wordmark for narrow windows, where the bar's rails
  /// have yielded width to the centre.
  final bool compact;
  final VoidCallback? onSettings;
  final VoidCallback? onKeyboardShortcuts;
  final VoidCallback? onStartScreen;

  const AppMenuButton({
    super.key,
    this.engineFailed = false,
    this.compact = false,
    this.onSettings,
    this.onKeyboardShortcuts,
    this.onStartScreen,
  });

  @override
  State<AppMenuButton> createState() => _AppMenuButtonState();
}

class _AppMenuButtonState extends State<AppMenuButton> {
  bool _isHovered = false;
  final GlobalKey _buttonKey = GlobalKey();

  Future<void> _showMenu(BuildContext context) async {
    final box = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlayBox == null) return;
    // Non-listening read: this runs from a tap handler (flutter-ui rules).
    final colors = context.themeProvider.colors;
    final anchor = Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlayBox),
      box.localToGlobal(
        box.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      ),
    );

    final selected = await showBoojyMenu<String>(
      context: context,
      anchor: anchor,
      items: [
        BoojyMenuItem(value: 'settings', icon: BI.settings, label: 'Settings…'),
        BoojyMenuItem(
          value: 'shortcuts',
          icon: BI.keyboard,
          label: 'Keyboard Shortcuts',
          shortcut: '?',
        ),
        const BoojyMenuDivider(),
        BoojyMenuItem(value: 'start', icon: BI.home, label: 'Start Screen'),
      ],
      selectedValue: null,
      colors: colors,
    );
    switch (selected) {
      case 'settings':
        widget.onSettings?.call();
      case 'shortcuts':
        widget.onKeyboardShortcuts?.call();
      case 'start':
        widget.onStartScreen?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Tooltip(
      message: widget.engineFailed
          ? "Audio engine didn't start — open Settings to check your device"
          : 'Boojy Audio menu',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (!_isHovered) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isHovered = true);
            });
          }
        },
        onExit: (_) {
          if (_isHovered) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isHovered = false);
            });
          }
        },
        child: GestureDetector(
          onTap: () => _showMenu(context),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            key: _buttonKey,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            // Nudge the wordmark up ~2px so its optical centre lines up with
            // the smaller siblings (project name, undo/redo) in the row.
            child: Transform.translate(
              offset: const Offset(0, -2),
              child: AnimatedScale(
                // The hover-scale is the affordance (no fill behind raster
                // art); it also says "this is clickable" like the old logo.
                scale: _isHovered ? AnimationConstants.hoverScale : 1.0,
                duration: AnimationConstants.hoverDuration,
                curve: Curves.easeInOut,
                child: BoojyWordmark(
                  triangleColor: widget.engineFailed
                      ? colors.error
                      : colors.accent,
                  fontSize: widget.compact ? 19 : 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
