import 'package:flutter/material.dart';
import '../theme/boojy_icons.dart';
import '../theme/theme_extension.dart';
import '../theme/tokens.dart';

/// Compact preset navigation bar: [◀] [- Init - ▾] [▶]
/// Shown in Row 1 of the editor panel for VST3 instruments.
class PresetNav extends StatelessWidget {
  final String currentPresetName;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onDropdownTap;

  const PresetNav({
    super.key,
    required this.currentPresetName,
    this.hasPrevious = false,
    this.hasNext = false,
    this.onPrevious,
    this.onNext,
    this.onDropdownTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Previous preset button
        _NavArrow(
          icon: BI.caretLeft,
          enabled: hasPrevious,
          onTap: onPrevious,
          tooltip: 'Previous Preset',
        ),
        const SizedBox(width: 2),
        // Preset name dropdown trigger
        GestureDetector(
          onTap: onDropdownTap,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 160),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colors.darkest,
                borderRadius: BorderRadius.circular(BT.radiusMd),
                border: Border.all(color: colors.divider, width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      currentPresetName,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: BT.fontBody,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(BI.caretDown, size: 10, color: colors.textMuted),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        // Next preset button
        _NavArrow(
          icon: BI.caretRight,
          enabled: hasNext,
          onTap: onNext,
          tooltip: 'Next Preset',
        ),
      ],
    );
  }
}

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;
  final String tooltip;

  const _NavArrow({
    required this.icon,
    required this.enabled,
    this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(BT.radiusMd),
          child: SizedBox(
            width: 24,
            height: 24,
            child: Icon(
              icon,
              size: 12,
              color: enabled
                  ? colors.textPrimary
                  : colors.textMuted.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
