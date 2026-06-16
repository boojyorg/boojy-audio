import 'package:flutter/material.dart';

import '../../theme/theme_extension.dart';
import 'boojy_dropdown.dart';

export 'boojy_dropdown.dart'
    show BoojyMenuEntry, BoojyMenuItem, BoojyMenuDivider, BoojyMenuSection;

/// A [BoojyMenuItem<String>] with a required leading icon — the standard shape
/// for all right-click context menu rows. Callers that already import this file
/// get [BoojyMenuEntry], [BoojyMenuDivider], and [BoojyMenuSection] for free
/// via the re-export above.
class ContextMenuItem extends BoojyMenuItem<String> {
  const ContextMenuItem({
    required super.value,
    required super.icon,
    required super.label,
    super.shortcut,
    super.enabled,
    super.destructive,
  });
}

/// Shows a right-click context menu at [position] on the shared Boojy rounded
/// surface. Pass [BoojyMenuDivider] and [BoojyMenuSection] entries alongside
/// [ContextMenuItem]s to add separators and group headers.
///
/// Returns the selected action string, or null if dismissed.
class ContextMenuHelper {
  static Future<String?> show({
    required BuildContext context,
    required Offset position,
    required List<BoojyMenuEntry<String>> items,
  }) {
    // listen:false — a listening read inside a tap handler asserts in debug
    // and the action silently does nothing (recurring v0.5.1 footgun).
    final colors = context.themeProvider.colors;

    return showBoojyMenu<String>(
      context: context,
      anchor: Rect.fromLTWH(position.dx, position.dy, 0, 0),
      items: items,
      selectedValue: null,
      colors: colors,
    );
  }
}
