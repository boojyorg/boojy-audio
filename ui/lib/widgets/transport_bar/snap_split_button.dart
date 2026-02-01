import 'package:flutter/material.dart';
import '../../state/ui_layout_state.dart';
import '../../theme/theme_extension.dart';
import '../shared/pill_toggle_button.dart' show ButtonDisplayMode;

/// Snap split button: icon toggles on/off, chevron opens grid size menu
class SnapSplitButton extends StatefulWidget {
  final SnapValue value;
  final Function(SnapValue)? onChanged;
  final ButtonDisplayMode mode;
  final bool isIconOnly;

  const SnapSplitButton({
    super.key,
    required this.value,
    this.onChanged,
    required this.mode,
    this.isIconOnly = false,
  });

  @override
  State<SnapSplitButton> createState() => _SnapSplitButtonState();
}

class _SnapSplitButtonState extends State<SnapSplitButton> {
  bool _isIconHovered = false;
  bool _isChevronHovered = false;
  SnapValue? _lastNonOffValue; // Remember last grid size for toggle
  final GlobalKey _buttonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Remember initial value if not off
    if (widget.value != SnapValue.off) {
      _lastNonOffValue = widget.value;
    } else {
      _lastNonOffValue = SnapValue.beat; // Default to beat if starting off
    }
  }

  @override
  void didUpdateWidget(SnapSplitButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Remember when user selects a non-off value
    if (widget.value != SnapValue.off) {
      _lastNonOffValue = widget.value;
    }
  }

  void _toggleSnap() {
    if (widget.value == SnapValue.off) {
      // Turn on: restore last value
      widget.onChanged?.call(_lastNonOffValue ?? SnapValue.beat);
    } else {
      // Turn off
      widget.onChanged?.call(SnapValue.off);
    }
  }

  void _showSnapMenu(BuildContext context, Color accentColor) {
    final RenderBox button = _buttonKey.currentContext!.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(Offset(0, button.size.height), ancestor: overlay);

    showMenu<SnapValue>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: SnapValue.values.map((snapValue) {
        final isSelected = snapValue == widget.value;
        return PopupMenuItem<SnapValue>(
          value: snapValue,
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check : Icons.grid_on,
                size: 18,
                color: isSelected ? accentColor : null,
              ),
              const SizedBox(width: 8),
              Text(
                snapValue.displayName,
                style: TextStyle(
                  color: isSelected ? accentColor : null,
                  fontWeight: isSelected ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ).then((value) {
      if (value != null) {
        widget.onChanged?.call(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isActive = widget.value != SnapValue.off;
    final bgColor = isActive ? colors.accent : colors.dark;
    final textColor = isActive ? colors.elevated : colors.textPrimary;

    final tooltip = isActive
        ? 'Snap: ${widget.value.displayName} (click to toggle)'
        : 'Snap Off (click to enable)';

    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        key: _buttonKey,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Left side: Label (clickable for toggle)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isIconHovered = true),
              onExit: (_) => setState(() => _isIconHovered = false),
              child: GestureDetector(
                onTap: _toggleSnap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isIconHovered
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
                      Icon(Icons.grid_on, size: 14, color: textColor),
                      if (!widget.isIconOnly) ...[
                        const SizedBox(width: 5),
                        Text(
                          isActive ? 'Snap ${widget.value.displayName}' : 'Snap',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Divider line
            Container(
              width: 1,
              height: 17,
              color: colors.textPrimary.withValues(alpha: 0.2),
            ),
            // Right side: Dropdown arrow
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isChevronHovered = true),
              onExit: (_) => setState(() => _isChevronHovered = false),
              child: GestureDetector(
                onTap: () => _showSnapMenu(context, colors.accent),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isChevronHovered
                        ? colors.textPrimary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(2),
                      bottomRight: Radius.circular(2),
                    ),
                  ),
                  child: Icon(
                    Icons.arrow_drop_down,
                    size: 17,
                    color: textColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
