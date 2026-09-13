import 'package:flutter/material.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/tokens.dart';
import 'tool_toggle_chip.dart';

/// Icon-only Loop toggle. Punch in/out used to hang off this button as a
/// dropdown; punch was removed from the UI in v0.7, so this is a plain chip.
class LoopToggleButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback? onToggle;

  const LoopToggleButton({super.key, required this.isActive, this.onToggle});

  @override
  Widget build(BuildContext context) {
    return ToolToggleChip(
      iconBuilder: (color) => Icon(BI.loop, size: BT.iconMd, color: color),
      isActive: isActive,
      onTap: onToggle,
      tooltipTitle: isActive ? 'Loop On' : 'Loop Off',
      tooltipDescription: 'Playback repeats the loop region on the ruler',
      tooltipShortcut: 'L',
    );
  }
}
