import 'package:flutter/material.dart';
import '../../theme/animation_constants.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';

/// Unified button for the entire Boojy UI — "Outlined Accent" style.
///
/// 4 visual states driven by [isActive] and hover:
///   Inactive:        transparent bg, divider border, textSecondary icon/text
///   Inactive+Hover:  accent@8% bg, accent@30% border, textPrimary icon/text
///   Active:          accent@15% bg, accent@50% border, accent icon/text
///   Active+Hover:    accent@22% bg, accent@65% border, accentHover icon/text
///
/// 2 sizes controlled by [compact]:
///   Standard: padding h:8 v:5, icon 14px, text 11px (transport bar, toolbars)
///   Compact:  padding h:6 v:3, icon 12px, text 9px  (piano roll sidebar)
///
/// Usage:
///   BoojyButton(icon: BI.loop, label: 'Loop', isActive: true, onTap: ...)
///   BoojyButton(icon: BI.gridOn, label: 'Snap', compact: true, onTap: ...)
///   BoojyButton(icon: BI.delete, label: 'Delete', onTap: ...) // action, never active
class BoojyButton extends StatefulWidget {
  final IconData? icon;
  final String? label;
  final bool isActive;
  final bool compact;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? tooltip;

  /// Optional: use a widget instead of an IconData (e.g., Image.asset)
  final Widget? iconWidget;

  const BoojyButton({
    super.key,
    this.icon,
    this.label,
    this.isActive = false,
    this.compact = false,
    this.onTap,
    this.onLongPress,
    this.tooltip,
    this.iconWidget,
  });

  @override
  State<BoojyButton> createState() => _BoojyButtonState();
}

class _BoojyButtonState extends State<BoojyButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = widget.isActive;
    final hovered = _isHovered;

    // Background color — 4 states
    final Color bg;
    if (active && hovered) {
      bg = colors.accent.withValues(alpha: 0.22);
    } else if (active) {
      bg = colors.accent.withValues(alpha: BT.opacityLight);
    } else if (hovered) {
      bg = colors.accent.withValues(alpha: BT.opacitySubtle);
    } else {
      bg = Colors.transparent;
    }

    // Border color — 4 states
    final Color borderColor;
    if (active && hovered) {
      borderColor = colors.accent.withValues(alpha: BT.opacityFull);
    } else if (active) {
      borderColor = colors.accent.withValues(alpha: BT.opacityStrong);
    } else if (hovered) {
      borderColor = colors.accent.withValues(alpha: BT.opacityMedium);
    } else {
      borderColor = colors.divider;
    }

    // Icon/text color — 4 states
    final Color contentColor;
    if (active && hovered) {
      contentColor = colors.accentHover;
    } else if (active) {
      contentColor = colors.accent;
    } else if (hovered) {
      contentColor = colors.textPrimary;
    } else {
      contentColor = colors.textSecondary;
    }

    // Size tokens
    final padding = widget.compact ? BT.buttonPaddingCompact : BT.buttonPadding;
    final iconSize = widget.compact ? BT.iconSm : BT.iconMd;
    final fontSize = widget.compact ? BT.fontCaption : BT.fontLabel;
    final gap = widget.compact ? BT.xxs : BT.xs;

    Widget button = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap?.call();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        onLongPress: widget.onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Transform.translate(
          offset: Offset(0, _isPressed ? AnimationConstants.pressDepth : 0),
          child: AnimatedContainer(
            duration: AnimationConstants.hoverDuration,
            padding: padding,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BT.borderSm,
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.iconWidget != null)
                  SizedBox(
                    width: iconSize,
                    height: iconSize,
                    child: widget.iconWidget,
                  )
                else if (widget.icon != null)
                  Icon(widget.icon, size: iconSize, color: contentColor),
                if (_hasLabel && _hasIcon) SizedBox(width: gap),
                if (_hasLabel) ...[
                  Text(
                    widget.label!,
                    style: TextStyle(
                      color: contentColor,
                      fontSize: fontSize,
                      fontWeight: active ? BT.weightSemiBold : BT.weightMedium,
                    ),
                  ),
                ],
              ],
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

  bool get _hasIcon => widget.icon != null || widget.iconWidget != null;

  bool get _hasLabel => widget.label != null && widget.label!.isNotEmpty;
}
