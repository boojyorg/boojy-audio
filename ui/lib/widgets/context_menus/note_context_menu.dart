import 'package:flutter/material.dart';

import '../shared/context_menu_item.dart';

/// Shows a context menu for piano roll notes.
///
/// [selectedCount] - Number of selected notes (affects label text)
/// [velocity] - Current velocity of the clicked note
/// [canPaste] - Whether paste action is available (clipboard not empty)
///
/// Returns the selected action string, or null if dismissed.
Future<String?> showNoteContextMenu({
  required BuildContext context,
  required Offset position,
  required int selectedCount,
  required int velocity,
  required bool canPaste,
}) {
  final String noteLabel = selectedCount <= 1 ? 'Note' : '$selectedCount Notes';

  final items = <PopupMenuEntry<String>>[
    ContextMenuItem(
      value: 'delete',
      icon: Icons.delete_outline,
      label: 'Delete $noteLabel',
      shortcut: '⌘⌫',
    ),
    ContextMenuItem(
      value: 'duplicate',
      icon: Icons.content_copy,
      label: 'Duplicate $noteLabel',
      shortcut: '⌘D',
    ),
    const PopupMenuDivider(),
    ContextMenuItem(
      value: 'cut',
      icon: Icons.content_cut,
      label: 'Cut $noteLabel',
      shortcut: '⌘X',
    ),
    ContextMenuItem(
      value: 'copy',
      icon: Icons.copy,
      label: 'Copy $noteLabel',
      shortcut: '⌘C',
    ),
    ContextMenuItem(
      value: 'paste',
      icon: Icons.paste,
      label: 'Paste',
      shortcut: '⌘V',
      enabled: canPaste,
    ),
    const PopupMenuDivider(),
    ContextMenuItem(
      value: 'quantize',
      icon: Icons.grid_on,
      label: 'Quantize',
      shortcut: 'Q',
    ),
    ContextMenuItem(
      value: 'velocity',
      icon: Icons.speed,
      label: 'Velocity: $velocity',
    ),
  ];

  return ContextMenuHelper.show(
    context: context,
    position: position,
    items: items,
  );
}
