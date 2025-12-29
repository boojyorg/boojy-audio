import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';

/// A split button with two clickable zones:
/// - Left side (icon + label): triggers primary action
/// - Right side (dropdown arrow): opens dropdown menu
///
/// Used for Snap and Quantize buttons in the Piano Roll toolbar.
class SplitButton<T> extends StatefulWidget {
  /// Icon displayed on the left side
  final IconData? icon;

  /// Label text displayed next to the icon
  final String label;

  /// Whether the button is in active/highlighted state
  final bool isActive;

  /// Called when the left side (icon + label) is tapped
  final VoidCallback? onLabelTap;

  /// Called when the left side is long-pressed
  final VoidCallback? onLabelLongPress;

  /// Dropdown menu items
  final List<PopupMenuEntry<T>> dropdownItems;

  /// Called when a dropdown item is selected
  final Function(T)? onItemSelected;

  /// Whether to show the dropdown arrow
  final bool showDropdown;

  const SplitButton({
    super.key,
    this.icon,
    required this.label,
    this.isActive = false,
    this.onLabelTap,
    this.onLabelLongPress,
    this.dropdownItems = const [],
    this.onItemSelected,
    this.showDropdown = true,
  });

  @override
  State<SplitButton<T>> createState() => _SplitButtonState<T>();
}

class _SplitButtonState<T> extends State<SplitButton<T>> {
  bool _isHoveringLabel = false;
  bool _isHoveringDropdown = false;

  void _showDropdown() {
    if (widget.dropdownItems.isEmpty) return;

    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);

    showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(
        buttonPosition.dx,
        buttonPosition.dy + button.size.height,
        overlay.size.width - buttonPosition.dx - button.size.width,
        0,
      ),
      items: widget.dropdownItems,
      elevation: 8,
    ).then((value) {
      if (value != null && widget.onItemSelected != null) {
        widget.onItemSelected!(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bgColor = widget.isActive ? colors.accent : colors.dark;
    final textColor = colors.textPrimary;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Left side: Icon + Label (clickable for primary action)
          MouseRegion(
            onEnter: (_) => setState(() => _isHoveringLabel = true),
            onExit: (_) => setState(() => _isHoveringLabel = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onLabelTap,
              onLongPress: widget.onLabelLongPress,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: _isHoveringLabel
                      ? colors.textPrimary.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(2),
                    bottomLeft: Radius.circular(2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(
                        widget.icon,
                        size: 12,
                        color: textColor,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Divider line (only show if dropdown is enabled)
          if (widget.showDropdown && widget.dropdownItems.isNotEmpty)
            Container(
              width: 1,
              height: 14,
              color: colors.textPrimary.withValues(alpha: 0.2),
            ),

          // Right side: Dropdown arrow
          if (widget.showDropdown && widget.dropdownItems.isNotEmpty)
            MouseRegion(
              onEnter: (_) => setState(() => _isHoveringDropdown = true),
              onExit: (_) => setState(() => _isHoveringDropdown = false),
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _showDropdown,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isHoveringDropdown
                        ? colors.textPrimary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(2),
                      bottomRight: Radius.circular(2),
                    ),
                  ),
                  child: Icon(
                    Icons.arrow_drop_down,
                    size: 14,
                    color: textColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A simple toolbar button without split functionality.
/// Used for buttons like Legato, Slice, Reverse that have a single action.
class ToolbarButton extends StatefulWidget {
  final IconData? icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? tooltip;

  const ToolbarButton({
    super.key,
    this.icon,
    required this.label,
    this.isActive = false,
    this.onTap,
    this.onLongPress,
    this.tooltip,
  });

  @override
  State<ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<ToolbarButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bgColor = widget.isActive ? colors.accent : colors.dark;
    final textColor = colors.textPrimary;

    Widget button = MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _isHovering
                ? bgColor.withValues(alpha: 0.8)
                : bgColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 14,
                  color: textColor,
                ),
                if (widget.label.isNotEmpty) const SizedBox(width: 4),
              ],
              if (widget.label.isNotEmpty)
                Text(
                  widget.label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(
        message: widget.tooltip!,
        child: button,
      );
    }

    return button;
  }
}
