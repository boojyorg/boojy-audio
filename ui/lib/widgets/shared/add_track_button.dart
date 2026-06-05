import 'package:flutter/material.dart';

import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';

/// A compact "add track" button: a [+] glyph + a track-type glyph + an optional
/// label, on a thin outline that lifts to the track-type colour on hover (synth
/// purple for MIDI, blue for audio) — teaching the colour language at the point
/// of creation.
///
/// Sized to [BT.controlHeight] so it lines up with the other compact chrome in
/// the transport bar. When [label] is empty it renders icon-only; pass
/// [tooltip] so it stays discoverable on a narrow rail.
class AddTrackButton extends StatefulWidget {
  final String label;
  final IconData typeIcon;
  final Color typeColor;
  final VoidCallback? onTap;
  final String? tooltip;

  const AddTrackButton({
    super.key,
    required this.label,
    required this.typeIcon,
    required this.typeColor,
    this.onTap,
    this.tooltip,
  });

  @override
  State<AddTrackButton> createState() => _AddTrackButtonState();
}

class _AddTrackButtonState extends State<AddTrackButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = widget.onTap != null;
    final active = _hovered && enabled;
    final fg = !enabled
        ? colors.textMuted
        : (active ? widget.typeColor : colors.textSecondary);
    final hasLabel = widget.label.isNotEmpty;

    Widget button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: BT.controlHeight,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: active
                ? widget.typeColor.withValues(alpha: BT.opacityLight)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active
                  ? widget.typeColor.withValues(alpha: 0.5)
                  : colors.divider,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(BI.add, size: 12, color: fg),
              const SizedBox(width: 2),
              Icon(widget.typeIcon, size: 12, color: fg),
              if (hasLabel) ...[
                const SizedBox(width: 3),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: fg,
                    fontSize: BT.fontLabel,
                    fontWeight: BT.weightMedium,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}
