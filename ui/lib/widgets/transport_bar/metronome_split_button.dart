import 'package:flutter/material.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';

/// Metronome split button with value-text design:
///   Left zone: metronome icon — toggles metronome on/off
///   Right zone: count-in value text — opens count-in dropdown
class MetronomeSplitButton extends StatefulWidget {
  final bool isActive;
  final int countInBars;
  final VoidCallback? onToggle;
  final Function(int)? onCountInChanged;

  const MetronomeSplitButton({
    super.key,
    required this.isActive,
    required this.countInBars,
    this.onToggle,
    this.onCountInChanged,
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
    final leftBg = widget.isActive
        ? colors.accent.withValues(alpha: BT.opacityLight)
        : Colors.transparent;
    final iconColor = widget.isActive ? colors.accent : colors.textSecondary;

    final tooltip = widget.isActive
        ? 'Metronome On (M) · Count-in: $_countInText'
        : 'Metronome Off (M)';

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
            // Left zone: metronome icon (toggle on/off)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isLeftHovered = true),
              onExit: (_) => setState(() => _isLeftHovered = false),
              child: GestureDetector(
                onTap: widget.onToggle,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: BT.buttonPadding,
                  decoration: BoxDecoration(
                    color: _isLeftHovered
                        ? (widget.isActive
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
                  child: Image.asset(
                    'assets/images/metronome.png',
                    width: BT.iconMd,
                    height: BT.iconMd,
                    color: iconColor,
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
            // Right zone: count-in value text (opens dropdown)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isRightHovered = true),
              onExit: (_) => setState(() => _isRightHovered = false),
              child: GestureDetector(
                onTap: () => _showCountInMenu(context, colors.accent),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 37),
                  padding: BT.splitRightPadding,
                  decoration: BoxDecoration(
                    color: _isRightHovered
                        ? (widget.isActive
                              ? colors.accent.withValues(
                                  alpha: BT.opacityMedium,
                                )
                              : colors.textPrimary.withValues(
                                  alpha: BT.opacitySubtle,
                                ))
                        : leftBg,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(BT.radiusSm),
                      bottomRight: Radius.circular(BT.radiusSm),
                    ),
                  ),
                  child: Text(
                    _countInText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: widget.isActive ? colors.accent : colors.textMuted,
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
