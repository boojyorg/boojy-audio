import 'package:flutter/material.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/tokens.dart';
import 'tool_toggle_chip.dart';

/// Labelled Count-in toggle: Off, or one bar of clicks before a take. On by
/// default. Independent of the metronome — the lead-in clicks even when the
/// metronome is off, so a silent count never looks like a stuck record button.
class CountInToggleButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback? onToggle;

  /// False only at the bar's narrowest density: the word gives way to a "1"
  /// glyph (one bar) so the rails keep their room. The tooltip still says it.
  final bool showLabel;

  const CountInToggleButton({
    super.key,
    required this.isActive,
    this.onToggle,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    return ToolToggleChip(
      label: showLabel ? 'Count-in' : null,
      iconBuilder: showLabel
          ? null
          : (color) => Icon(BI.countOne, size: BT.iconMd, color: color),
      isActive: isActive,
      onTap: onToggle,
      tooltipTitle: isActive ? 'Count-in: 1 bar' : 'Count-in: Off',
      tooltipDescription: isActive
          ? 'One bar of clicks before recording starts'
          : 'Recording starts the moment you press Record',
    );
  }
}
