import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
import '../shared/boojy_tooltip.dart';

/// The transport bar's toggle chip: Loop, Metronome and Count-in all share it,
/// and Snap's two zones match it. Toggle role from the button language —
/// outline + faint accent tint while on, a quiet grey outline while off. An
/// icon, a label, or both; pinned to [BT.splitButtonHeight] so the row lines
/// up whatever each chip holds.
class ToolToggleChip extends StatefulWidget {
  /// Builds the glyph in the chip's current icon colour (accent while on,
  /// secondary text while off). Null for a text-only chip.
  final Widget Function(Color iconColor)? iconBuilder;

  /// Text after the glyph (or alone). Null for an icon-only chip.
  final String? label;

  final bool isActive;
  final VoidCallback? onTap;

  final String tooltipTitle;
  final String? tooltipDescription;
  final String? tooltipShortcut;

  const ToolToggleChip({
    super.key,
    this.iconBuilder,
    this.label,
    required this.isActive,
    required this.onTap,
    required this.tooltipTitle,
    this.tooltipDescription,
    this.tooltipShortcut,
  }) : assert(
         iconBuilder != null || label != null,
         'A chip needs an icon, a label, or both',
       );

  @override
  State<ToolToggleChip> createState() => _ToolToggleChipState();
}

class _ToolToggleChipState extends State<ToolToggleChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isActive = widget.isActive;
    final iconColor = isActive ? colors.accent : colors.textSecondary;
    final textColor = isActive ? colors.textPrimary : colors.textSecondary;
    final restingFill = isActive ? colors.selectionFill : colors.surface;
    final hoverFill = isActive
        ? colors.selectionFillHover
        : colors.textPrimary.withValues(alpha: BT.opacitySubtle);
    final hasLabel = widget.label != null;

    return BoojyTooltip(
      title: widget.tooltipTitle,
      description: widget.tooltipDescription,
      shortcut: widget.tooltipShortcut,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (!_isHovered) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isHovered = true);
            });
          }
        },
        onExit: (_) {
          if (_isHovered) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isHovered = false);
            });
          }
        },
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: DecoratedBox(
            // Foreground border, no clip: the fill can't paint over the stroke
            // because the stroke is drawn on top (see flutter-ui rules).
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BT.borderMd,
              border: Border.all(
                color: isActive ? colors.selectionBorder : colors.textMuted,
                width: 1,
              ),
            ),
            child: Container(
              height: BT.splitButtonHeight,
              // Icon-only chips are square-ish; labelled chips breathe a bit.
              padding: EdgeInsets.symmetric(horizontal: hasLabel ? BT.sm : 6),
              decoration: BoxDecoration(
                color: _isHovered ? hoverFill : restingFill,
                // Inner radius nests inside the 1px stroke.
                borderRadius: BorderRadius.circular(BT.radiusMd - 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.iconBuilder != null)
                    widget.iconBuilder!(iconColor),
                  if (widget.iconBuilder != null && hasLabel)
                    const SizedBox(width: BT.xs),
                  if (hasLabel)
                    Text(
                      widget.label!,
                      style: TextStyle(
                        color: textColor,
                        fontSize: BT.fontLabel,
                        fontWeight: BT.weightMedium,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
