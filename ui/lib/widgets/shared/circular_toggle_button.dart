import 'package:flutter/material.dart';
import '../../theme/animation_constants.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';

/// A circular toggle button with hover/press animations.
///
/// Used for metronome, virtual piano, loop, and similar toggle controls.
/// Features:
/// - Circular shape with border
/// - Hover scale effect (1.05x)
/// - Press scale effect (0.95x)
/// - Glow effect when enabled and hovered
/// - Customizable colors for enabled/disabled states
class CircularToggleButton extends StatefulWidget {
  /// Whether the button is in the enabled/active state
  final bool enabled;

  /// Called when the button is pressed
  final VoidCallback? onPressed;

  /// Icon to display
  final IconData icon;

  /// Tooltip message (can include keyboard shortcut info)
  final String? tooltip;

  /// Size of the button (default 40)
  final double size;

  /// Icon size (default BT.iconLg)
  final double iconSize;

  /// Color when enabled (defaults to accent color)
  final Color? enabledColor;

  /// Whether to show glow effect when enabled and hovered
  final bool showGlow;

  const CircularToggleButton({
    super.key,
    required this.enabled,
    this.onPressed,
    required this.icon,
    this.tooltip,
    this.size = 40,
    this.iconSize = BT.iconLg,
    this.enabledColor,
    this.showGlow = true,
  });

  @override
  State<CircularToggleButton> createState() => _CircularToggleButtonState();
}

class _CircularToggleButtonState extends State<CircularToggleButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabledColor = widget.enabledColor ?? colors.accent;
    final scale = _isPressed
        ? AnimationConstants.pressScale
        : (_isHovered ? AnimationConstants.hoverScale : 1.0);

    Widget button = MouseRegion(
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
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onPressed?.call();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: AnimationConstants.hoverDuration,
          curve: AnimationConstants.standardCurve,
          child: AnimatedContainer(
            duration: AnimationConstants.hoverDuration,
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.enabled
                  ? enabledColor.withValues(alpha: _isHovered ? 0.3 : 0.2)
                  : colors.elevated.withValues(alpha: _isHovered ? 1.0 : 0.8),
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.enabled ? enabledColor : colors.elevated,
                width: 2,
              ),
              boxShadow: widget.showGlow && _isHovered && widget.enabled
                  ? [
                      BoxShadow(
                        color: enabledColor.withValues(alpha: 0.3),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: widget.enabled ? enabledColor : colors.textMuted,
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }

    return button;
  }
}
