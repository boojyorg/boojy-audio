import 'package:flutter/material.dart';
import '../../state/ui_layout_state.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
import '../shared/boojy_dropdown.dart';
import '../shared/boojy_tooltip.dart';

/// Snap split button: the grid glyph toggles snapping on and off; the value
/// zone ("Bar ▾") opens the grid-resolution menu. On/off and the resolution
/// are separate state, so the value stays visible (dimmed) while snap is off —
/// the layout never shifts and the remembered grid is always readable.
class SnapSplitButton extends StatefulWidget {
  final bool isEnabled;

  /// The grid the arrangement snaps to when enabled — never [SnapValue.off].
  final SnapValue resolution;
  final VoidCallback? onToggle;
  final ValueChanged<SnapValue>? onResolutionChanged;

  /// At the bar's narrowest density the value zone hugs its text instead of
  /// reserving the widest entry's slot.
  final bool compactValue;

  const SnapSplitButton({
    super.key,
    required this.isEnabled,
    required this.resolution,
    this.onToggle,
    this.onResolutionChanged,
    this.compactValue = false,
  });

  @override
  State<SnapSplitButton> createState() => _SnapSplitButtonState();
}

class _SnapSplitButtonState extends State<SnapSplitButton> {
  bool _isIconHovered = false;
  bool _isValueHovered = false;
  final GlobalKey _buttonKey = GlobalKey();

  /// Value-zone width pinned to the widest entry ("1/16T" + chevron) so the
  /// button keeps one width whatever grid is chosen.
  static const double _valueZoneMinWidth = 58;

  Future<void> _showResolutionMenu(BuildContext context) async {
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

    final selected = await showBoojyMenu<SnapValue>(
      context: context,
      anchor: anchor,
      items: [
        const BoojyMenuItem(
          value: SnapValue.auto,
          label: 'Auto (follows zoom)',
        ),
        const BoojyMenuDivider(),
        const BoojyMenuItem(value: SnapValue.bar, label: 'Bar'),
        const BoojyMenuItem(value: SnapValue.beat, label: 'Beat'),
        const BoojyMenuItem(value: SnapValue.half, label: '1/2 beat'),
        const BoojyMenuItem(value: SnapValue.quarter, label: '1/4 beat'),
        const BoojyMenuDivider(),
        const BoojyMenuItem(
          value: SnapValue.eighthTriplet,
          label: '1/8 triplet',
        ),
        const BoojyMenuItem(
          value: SnapValue.sixteenthTriplet,
          label: '1/16 triplet',
        ),
      ],
      selectedValue: widget.resolution,
      colors: colors,
    );
    if (selected != null) widget.onResolutionChanged?.call(selected);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isActive = widget.isEnabled;
    final restingFill = isActive ? colors.selectionFill : colors.surface;
    final hoverFill = isActive
        ? colors.selectionFillHover
        : colors.textPrimary.withValues(alpha: BT.opacitySubtle);
    final iconColor = isActive ? colors.accent : colors.textSecondary;
    final valueColor = isActive ? colors.accent : colors.textMuted;
    final valueName = widget.resolution.displayName;

    return BoojyTooltip(
      title: isActive ? 'Snap to $valueName' : 'Snap Off',
      description: isActive
          ? 'Click the grid to turn snap off · $valueName ▾ changes the grid'
          : 'Click the grid to snap edits to $valueName again',
      child: DecoratedBox(
        key: _buttonKey,
        // Foreground border, no clip — the zone fills can't paint over the
        // stroke because it is drawn on top (flutter-ui rules).
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BT.borderMd,
          border: Border.all(
            color: isActive ? colors.selectionBorder : colors.textMuted,
            width: 1,
          ),
        ),
        child: SizedBox(
          height: BT.splitButtonHeight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left zone: grid glyph — toggles snap on/off
              MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => _setHover(icon: true),
                onExit: (_) => _setHover(icon: false),
                child: GestureDetector(
                  onTap: widget.onToggle,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: _isIconHovered ? hoverFill : restingFill,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(BT.radiusMd - 1),
                        bottomLeft: Radius.circular(BT.radiusMd - 1),
                      ),
                    ),
                    child: Icon(BI.gridOn, size: BT.iconMd, color: iconColor),
                  ),
                ),
              ),
              // Divider between the zones
              Container(
                width: 1,
                color: isActive
                    ? colors.selectionBorder
                    : colors.textPrimary.withValues(alpha: BT.opacityMedium),
              ),
              // Right zone: current grid + chevron — opens the resolution menu
              MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => _setHover(value: true),
                onExit: (_) => _setHover(value: false),
                child: GestureDetector(
                  onTap: () => _showResolutionMenu(context),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    alignment: Alignment.center,
                    constraints: BoxConstraints(
                      minWidth: widget.compactValue ? 0 : _valueZoneMinWidth,
                    ),
                    padding: const EdgeInsets.only(left: 7, right: 4),
                    decoration: BoxDecoration(
                      color: _isValueHovered ? hoverFill : restingFill,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(BT.radiusMd - 1),
                        bottomRight: Radius.circular(BT.radiusMd - 1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          valueName,
                          style: TextStyle(
                            color: valueColor,
                            fontSize: BT.fontLabel,
                            fontWeight: BT.weightSemiBold,
                          ),
                        ),
                        const SizedBox(width: 1),
                        Icon(BI.expandMore, size: BT.iconMd, color: valueColor),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setHover({bool? icon, bool? value}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        if (icon != null) _isIconHovered = icon;
        if (value != null) _isValueHovered = value;
      });
    });
  }
}
