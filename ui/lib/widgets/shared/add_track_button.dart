import 'package:flutter/material.dart';

import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';

/// A compact "add track" button: a [+] glyph + a track-type glyph + an optional
/// label, on a thin outline that lifts to the track-type colour on hover (synth
/// purple for MIDI, blue for audio) — teaching the colour language at the point
/// of creation.
///
/// Defaults to [BT.controlHeight] and transparent background so it lines up
/// with other compact chrome in the transport bar. Pass [height] and
/// [backgroundColor] to render a larger, filled variant (e.g. the empty-state
/// arrangement prompt). Icon size, horizontal padding, and font scale
/// proportionally with [height] unless [iconSize] or [labelSize] are given
/// explicitly (use those to avoid oversized content at high scale factors).
///
/// When [backgroundColor] is supplied (filled mode), hover shows a neutral
/// surface lift ([colors.surface] fill, [colors.textPrimary] text) instead of
/// the type-colour tint used in the compact transport-bar variant.
class AddTrackButton extends StatefulWidget {
  final String label;
  final IconData typeIcon;
  final Color typeColor;
  final VoidCallback? onTap;
  final String? tooltip;

  /// Override height. Defaults to [BT.controlHeight] (24 px). Icons, padding,
  /// and font scale proportionally unless [iconSize] or [labelSize] override.
  final double? height;

  /// Resting background. Defaults to transparent; pass [colors.dark] etc. for
  /// a filled variant. Also switches hover to a neutral surface lift.
  final Color? backgroundColor;

  /// Explicit icon size. Overrides the proportional scale from [height] so
  /// content doesn't become oversized when [height] is much larger than
  /// [BT.controlHeight].
  final double? iconSize;

  /// Explicit label font size. Overrides the proportional scale from [height].
  final double? labelSize;

  const AddTrackButton({
    super.key,
    required this.label,
    required this.typeIcon,
    required this.typeColor,
    this.onTap,
    this.tooltip,
    this.height,
    this.backgroundColor,
    this.iconSize,
    this.labelSize,
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
    final isFilled = widget.backgroundColor != null;

    final Color fg;
    final Color bgColor;
    final Color borderColor;
    if (!enabled) {
      fg = colors.textMuted;
      bgColor = widget.backgroundColor ?? Colors.transparent;
      borderColor = colors.divider;
    } else if (active) {
      if (isFilled) {
        // Filled variant: opaque surface lift on hover.
        fg = colors.textPrimary;
        bgColor = colors.surface;
        borderColor = colors.divider;
      } else {
        // Transport-bar variant: type-colour tint teaches the track colour.
        fg = widget.typeColor;
        bgColor = widget.typeColor.withValues(alpha: BT.opacityLight);
        borderColor = widget.typeColor.withValues(alpha: 0.5);
      }
    } else {
      fg = colors.textSecondary;
      bgColor = widget.backgroundColor ?? Colors.transparent;
      borderColor = colors.divider;
    }

    final hasLabel = widget.label.isNotEmpty;
    final effectiveHeight = widget.height ?? BT.controlHeight;
    final scale = effectiveHeight / BT.controlHeight;
    final iconSize = widget.iconSize ?? (12.0 * scale).roundToDouble();
    final hPad = (7.0 * scale).roundToDouble();
    final fontSize = widget.labelSize ?? BT.fontLabel * scale;

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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: effectiveHeight,
          padding: EdgeInsets.symmetric(horizontal: hPad),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(BI.add, size: iconSize, color: fg),
                SizedBox(width: (2.0 * scale).roundToDouble()),
                Icon(widget.typeIcon, size: iconSize, color: fg),
                if (hasLabel) ...[
                  SizedBox(width: (3.0 * scale).roundToDouble()),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: fg,
                      fontSize: fontSize,
                      fontWeight: BT.weightMedium,
                    ),
                  ),
                ],
              ],
            ),
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
