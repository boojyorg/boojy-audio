import 'package:flutter/material.dart';
import '../../theme/animation_constants.dart';
import '../../theme/theme_extension.dart';
import 'button_hover_mixin.dart';

/// Display mode for responsive button layouts.
/// Used to show/hide labels based on available space.
enum ButtonDisplayMode {
  /// Show icon + label
  wide,
  /// Show icon only
  narrow,
}

/// A pill-shaped toggle button with icon and optional label.
///
/// Features:
/// - Responsive: shows icon+label in wide mode, icon-only in narrow mode
/// - Hover scale effect (1.02x)
/// - Press scale effect (0.95x)
/// - Active/inactive color states
/// - Customizable active color
///
/// Used for metronome, virtual piano, and similar toggle controls.
class PillToggleButton extends StatefulWidget {
  /// Icon to display
  final IconData icon;

  /// Label text (shown in wide mode)
  final String label;

  /// Whether the button is in active/enabled state
  final bool isActive;

  /// Display mode for responsive layout
  final ButtonDisplayMode mode;

  /// Called when the button is tapped
  final VoidCallback? onTap;

  /// Tooltip message
  final String tooltip;

  /// Color when active (defaults to accent color)
  final Color? activeColor;

  /// Icon size (default 14)
  final double iconSize;

  /// Text color when inactive (defaults to textPrimary)
  final Color? inactiveTextColor;

  const PillToggleButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.mode,
    this.onTap,
    required this.tooltip,
    this.activeColor,
    this.iconSize = 14,
    this.inactiveTextColor,
  });

  @override
  State<PillToggleButton> createState() => _PillToggleButtonState();
}

class _PillToggleButtonState extends State<PillToggleButton>
    with ButtonHoverMixin {
  // Use subtle hover scale for pill buttons
  @override
  double get hoverScale => AnimationConstants.subtleHoverScale;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activeColor = widget.activeColor ?? colors.accent;

    final bgColor = widget.isActive
        ? activeColor
        : (isHovered ? colors.elevated : colors.dark);

    // Active buttons use elevated (dark grey) to match snap/metronome buttons
    final textColor = widget.isActive
        ? colors.elevated
        : (widget.inactiveTextColor ?? colors.textPrimary);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: handleHoverEnter,
        onExit: handleHoverExit,
        child: GestureDetector(
          onTapDown: handleTapDown,
          onTapUp: (details) {
            handleTapUp(details);
            widget.onTap?.call();
          },
          onTapCancel: handleTapCancel,
          child: AnimatedScale(
            scale: scale,
            duration: AnimationConstants.pressDuration,
            curve: AnimationConstants.standardCurve,
            child: AnimatedContainer(
              duration: AnimationConstants.pressDuration,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: widget.iconSize, color: textColor),
                  if (widget.mode == ButtonDisplayMode.wide) ...[
                    const SizedBox(width: 5),
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 11,
                        fontWeight:
                            widget.isActive ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A simple icon-only toggle button (no label).
///
/// Used for undo/redo and similar minimal icon buttons.
class IconToggleButton extends StatefulWidget {
  /// Icon to display
  final IconData icon;

  /// Whether the button is enabled/clickable
  final bool enabled;

  /// Called when the button is tapped (only if enabled)
  final VoidCallback? onTap;

  /// Tooltip message
  final String tooltip;

  /// Icon size (default 18)
  final double iconSize;

  /// Padding around the icon (default 6)
  final double padding;

  const IconToggleButton({
    super.key,
    required this.icon,
    this.enabled = true,
    this.onTap,
    required this.tooltip,
    this.iconSize = 18,
    this.padding = 6,
  });

  @override
  State<IconToggleButton> createState() => _IconToggleButtonState();
}

class _IconToggleButtonState extends State<IconToggleButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final color = widget.enabled
        ? (_isHovered ? colors.textPrimary : colors.textSecondary)
        : colors.textSecondary.withValues(alpha: AnimationConstants.disabledOpacity);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.enabled ? widget.onTap : null,
          child: Padding(
            padding: EdgeInsets.all(widget.padding),
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
