import 'package:flutter/material.dart';
import '../../../theme/theme_extension.dart';

/// Stateful zoom button with hover and pressed states.
/// Used in both Piano Roll and Arrangement nav bars.
class ZoomButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const ZoomButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<ZoomButton> createState() => _ZoomButtonState();
}

class _ZoomButtonState extends State<ZoomButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Determine colors based on state
    Color bgColor;
    Color iconColor;
    if (_isPressed) {
      bgColor = colors.elevated;
      iconColor = colors.textPrimary;
    } else if (_isHovered) {
      bgColor = colors.surface;
      iconColor = colors.textPrimary;
    } else {
      bgColor = colors.standard;
      iconColor = colors.textSecondary;
    }

    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() {
            _isHovered = false;
            _isPressed = false;
          }),
          child: Container(
            width: 19,
            height: 19,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: colors.surface,
                width: 1,
              ),
            ),
            child: Icon(
              widget.icon,
              size: 13,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
