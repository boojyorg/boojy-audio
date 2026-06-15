import 'package:flutter/material.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
import '../shared/boojy_tooltip.dart';

/// Metronome split button with value-text design:
///   Left zone: metronome icon — toggles metronome on/off
///   Right zone: count-in value text — opens count-in dropdown
class MetronomeSplitButton extends StatefulWidget {
  final bool isActive;
  final int countInBars;
  final VoidCallback? onToggle;
  final Function(int)? onCountInChanged;

  /// When false, hides the count-in value/dropdown (right zone), collapsing to
  /// an icon-only metronome toggle — used at narrow transport-bar widths.
  final bool showLabel;

  const MetronomeSplitButton({
    super.key,
    required this.isActive,
    required this.countInBars,
    this.onToggle,
    this.onCountInChanged,
    this.showLabel = true,
  });

  @override
  State<MetronomeSplitButton> createState() => _MetronomeSplitButtonState();
}

class _MetronomeSplitButtonState extends State<MetronomeSplitButton> {
  bool _isLeftHovered = false;
  bool _isRightHovered = false;
  final GlobalKey _buttonKey = GlobalKey();

  /// Count-in display text for the right zone
  String get _countInText {
    switch (widget.countInBars) {
      case 0:
        return 'Off';
      case 1:
        return '1 Bar';
      case 2:
        return '2 Bars';
      case 4:
        return '4 Bars';
      default:
        return '${widget.countInBars} Bars';
    }
  }

  PopupMenuItem<int> _countInItem(int bars, String label, Color accentColor) {
    final isSelected = widget.countInBars == bars;
    return PopupMenuItem<int>(
      value: bars,
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
            label,
            style: TextStyle(
              color: isSelected ? accentColor : null,
              fontWeight: isSelected ? BT.weightSemiBold : null,
            ),
          ),
        ],
      ),
    );
  }

  void _showCountInMenu(BuildContext context, Color accentColor) {
    final RenderBox button =
        _buttonKey.currentContext!.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(
      Offset(0, button.size.height),
      ancestor: overlay,
    );

    showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem<int>(
          enabled: false,
          height: 28,
          child: Text(
            'COUNT-IN',
            style: TextStyle(
              fontSize: 12,
              fontWeight: BT.weightSemiBold,
              letterSpacing: 1.0,
            ),
          ),
        ),
        _countInItem(1, '1 Bar', accentColor),
        _countInItem(2, '2 Bars', accentColor),
        _countInItem(4, '4 Bars', accentColor),
        _countInItem(0, 'Off', accentColor),
      ],
    ).then((value) {
      if (value != null) {
        widget.onCountInChanged?.call(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final leftBg = widget.isActive ? colors.selectionFill : colors.surface;
    final iconColor = widget.isActive ? colors.accent : colors.textSecondary;

    return BoojyTooltip(
      title: widget.isActive ? 'Metronome On' : 'Metronome Off',
      description: widget.isActive ? 'Count-in: $_countInText' : null,
      shortcut: 'M',
      child: DecoratedBox(
        key: _buttonKey,
        // Foreground border, no clip: clipping shaves the stroke at the
        // corner arcs, and a background border gets painted over by the
        // opaque zone fills (DecoratedBox doesn't inset its child the way
        // Container does). Painting the stroke ON TOP keeps it visible over
        // the fills without changing the button's height — so Loop · Snap ·
        // Metronome all measure exactly splitButtonHeight.
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BT.borderMd,
          border: Border.all(
            // Off-state outline matches the active accent one in weight
            // (textMuted, not the near-invisible divider) — grey, not blue.
            color: widget.isActive ? colors.selectionBorder : colors.textMuted,
            width: 1,
          ),
        ),
        // Pinned to a shared height (not IntrinsicHeight) so Loop · Snap ·
        // Metronome align despite differing zone content; stretch then makes
        // the inter-zone divider span that full height (not the bar).
        child: SizedBox(
          height: BT.splitButtonHeight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left zone: metronome icon (toggle on/off)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) {
                  if (!_isLeftHovered) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _isLeftHovered = true);
                    });
                  }
                },
                onExit: (_) {
                  if (_isLeftHovered) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _isLeftHovered = false);
                    });
                  }
                },
                child: GestureDetector(
                  onTap: widget.onToggle,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    alignment: Alignment.center,
                    padding: BT.splitLeftPadding,
                    decoration: BoxDecoration(
                      color: _isLeftHovered
                          ? (widget.isActive
                                ? colors.selectionFillHover
                                : colors.textPrimary.withValues(
                                    alpha: BT.opacitySubtle,
                                  ))
                          : leftBg,
                      // Inner radius = outer radius minus the 1px border, so
                      // the fill arc nests inside the border arc. When the
                      // right zone is shed, this zone owns the right corners.
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(BT.radiusMd - 1),
                        bottomLeft: const Radius.circular(BT.radiusMd - 1),
                        topRight: widget.showLabel
                            ? Radius.zero
                            : const Radius.circular(BT.radiusMd - 1),
                        bottomRight: widget.showLabel
                            ? Radius.zero
                            : const Radius.circular(BT.radiusMd - 1),
                      ),
                    ),
                    child: Image.asset(
                      'assets/images/metronome.png',
                      width: BT.iconMd,
                      height: BT.iconMd,
                      color: iconColor,
                    ),
                  ),
                ),
              ),
              // Divider + right zone (count-in value/dropdown) — hidden when
              // showLabel is false so the metronome collapses to an icon-only
              // toggle, matching Loop/Snap shedding.
              if (widget.showLabel) ...[
                // Divider — full-height, selection-border when engaged to match the outline.
                Container(
                  width: 1,
                  color: widget.isActive
                      ? colors.selectionBorder
                      : colors.textPrimary.withValues(alpha: BT.opacityMedium),
                ),
                // Right zone: count-in value text (opens dropdown)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) {
                    if (!_isRightHovered) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _isRightHovered = true);
                      });
                    }
                  },
                  onExit: (_) {
                    if (_isRightHovered) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _isRightHovered = false);
                      });
                    }
                  },
                  child: GestureDetector(
                    onTap: () => _showCountInMenu(context, colors.accent),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      alignment: Alignment.center,
                      constraints: const BoxConstraints(minWidth: 37),
                      padding: BT.splitRightPadding,
                      decoration: BoxDecoration(
                        color: _isRightHovered
                            ? (widget.isActive
                                  ? colors.selectionFillHover
                                  : colors.textPrimary.withValues(
                                      alpha: BT.opacitySubtle,
                                    ))
                            : leftBg,
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(BT.radiusMd - 1),
                          bottomRight: Radius.circular(BT.radiusMd - 1),
                        ),
                      ),
                      child: Text(
                        _countInText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: widget.isActive
                              ? colors.accent
                              : colors.textMuted,
                          fontSize: BT.fontLabel,
                          fontWeight: BT.weightSemiBold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
