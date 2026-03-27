import 'package:flutter/material.dart';
import '../../state/ui_layout_state.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
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

  PopupMenuItem<SnapValue> _snapMenuItem(
    SnapValue snapValue,
    Color accentColor,
  ) {
    final isSelected = snapValue == widget.value;
    return PopupMenuItem<SnapValue>(
      value: snapValue,
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: isSelected
                ? Icon(BI.radioChecked, size: BT.iconMd, color: accentColor)
                : Icon(BI.circle, size: BT.iconMd),
          ),
          const SizedBox(width: 8),
          Text(
            snapValue.displayName,
            style: TextStyle(
              color: isSelected ? accentColor : null,
              fontWeight: isSelected ? BT.weightSemiBold : null,
            ),
          ),
        ],
      ),
    );
  }

  void _showSnapMenu(BuildContext context, Color accentColor) {
    final RenderBox button =
        _buttonKey.currentContext!.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(
      Offset(0, button.size.height),
      ancestor: overlay,
    );

    showMenu<SnapValue>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        // Smart snap
        _snapMenuItem(SnapValue.auto, accentColor),
        const PopupMenuDivider(),
        // Standard grid sizes
        _snapMenuItem(SnapValue.bar, accentColor),
        _snapMenuItem(SnapValue.beat, accentColor),
        _snapMenuItem(SnapValue.half, accentColor),
        _snapMenuItem(SnapValue.quarter, accentColor),
        const PopupMenuDivider(),
        // Triplets
        _snapMenuItem(SnapValue.eighthTriplet, accentColor),
        _snapMenuItem(SnapValue.sixteenthTriplet, accentColor),
        const PopupMenuDivider(),
        // Off
        _snapMenuItem(SnapValue.off, accentColor),
      ],
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
    final leftBg = isActive
        ? colors.accent.withValues(alpha: BT.opacityLight)
        : Colors.transparent;
    final iconColor = isActive ? colors.accent : colors.textSecondary;
    final textColor = isActive ? colors.textPrimary : colors.textSecondary;

    final tooltip = isActive
        ? 'Snap: ${widget.value.displayName} (click to toggle)'
        : 'Snap Off (click to enable)';

    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        key: _buttonKey,
        decoration: BoxDecoration(
          borderRadius: BT.borderSm,
          border: Border.all(color: colors.divider, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Left zone: icon + "Snap" label (toggle on/off)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isIconHovered = true),
              onExit: (_) => setState(() => _isIconHovered = false),
              child: GestureDetector(
                onTap: _toggleSnap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: BT.buttonPadding,
                  decoration: BoxDecoration(
                    color: _isIconHovered
                        ? (isActive
                              ? colors.accent.withValues(
                                  alpha: BT.opacityMedium,
                                )
                              : colors.textPrimary.withValues(
                                  alpha: BT.opacitySubtle,
                                ))
                        : leftBg,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(BT.radiusSm),
                      bottomLeft: Radius.circular(BT.radiusSm),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(BI.gridOn, size: BT.iconMd, color: iconColor),
                      if (!widget.isIconOnly) ...[
                        const SizedBox(width: BT.xs),
                        Text(
                          'Snap',
                          style: TextStyle(
                            color: textColor,
                            fontSize: BT.fontLabel,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Divider
            Container(
              width: 1,
              height: 19,
              color: colors.textPrimary.withValues(alpha: BT.opacityMedium),
            ),
            // Right zone: current value text (opens dropdown)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isChevronHovered = true),
              onExit: (_) => setState(() => _isChevronHovered = false),
              child: GestureDetector(
                onTap: () => _showSnapMenu(context, colors.accent),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 37),
                  padding: BT.splitRightPadding,
                  decoration: BoxDecoration(
                    color: _isChevronHovered
                        ? (isActive
                              ? colors.accent.withValues(
                                  alpha: BT.opacityMedium,
                                )
                              : colors.textPrimary.withValues(
                                  alpha: BT.opacitySubtle,
                                ))
                        : leftBg,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(2),
                      bottomRight: Radius.circular(2),
                    ),
                  ),
                  child: Text(
                    widget.value.displayName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isActive ? colors.accent : colors.textMuted,
                      fontSize: BT.fontLabel,
                      fontWeight: BT.weightSemiBold,
                    ),
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
