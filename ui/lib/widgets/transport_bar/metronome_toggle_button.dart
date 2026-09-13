import 'package:flutter/material.dart';
import '../../theme/tokens.dart';
import 'tool_toggle_chip.dart';

/// Icon-only Metronome toggle. Governs the click during playback and
/// recording only — the count-in bar always clicks (see the Count-in chip).
class MetronomeToggleButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback? onToggle;

  const MetronomeToggleButton({
    super.key,
    required this.isActive,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ToolToggleChip(
      iconBuilder: (color) => Image.asset(
        'assets/images/metronome.png',
        width: BT.iconMd,
        height: BT.iconMd,
        color: color,
      ),
      isActive: isActive,
      onTap: onToggle,
      tooltipTitle: isActive ? 'Metronome On' : 'Metronome Off',
      tooltipDescription: 'Click while playing and recording',
      tooltipShortcut: 'M',
    );
  }
}
