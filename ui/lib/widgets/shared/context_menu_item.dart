import 'package:flutter/material.dart';

import '../../theme/theme_extension.dart';

/// A standardized PopupMenuItem with icon, label, and optional keyboard shortcut.
/// Used across all context menus in the app for consistent styling.
class ContextMenuItem extends PopupMenuItem<String> {
  ContextMenuItem({
    super.key,
    required String value,
    required IconData icon,
    required String label,
    String? shortcut,
    super.enabled = true,
  }) : super(
          value: value,
          child: _ContextMenuItemContent(
            icon: icon,
            label: label,
            shortcut: shortcut,
            enabled: enabled,
          ),
        );
}

class _ContextMenuItemContent extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? shortcut;
  final bool enabled;

  const _ContextMenuItemContent({
    required this.icon,
    required this.label,
    this.shortcut,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textColor = enabled ? null : colors.textMuted;

    return Row(
      children: [
        Icon(icon, size: 18, color: textColor),
        const SizedBox(width: 8),
        Text(label, style: textColor != null ? TextStyle(color: textColor) : null),
        if (shortcut != null) ...[
          const Spacer(),
          Text(
            shortcut!,
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ],
      ],
    );
  }
}

/// Helper class to build and show context menus with consistent positioning.
class ContextMenuHelper {
  /// Shows a context menu at the given position.
  /// Returns the selected value or null if dismissed.
  static Future<String?> show({
    required BuildContext context,
    required Offset position,
    required List<PopupMenuEntry<String>> items,
  }) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    return showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: items,
    );
  }
}
