import 'package:flutter/material.dart';

import '../../theme/boojy_icons.dart';
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
      icon: BI.delete,
      label: 'Delete $noteLabel',
      shortcut: '⌘⌫',
    ),
    ContextMenuItem(
      value: 'duplicate',
      icon: BI.copy,
      label: 'Duplicate $noteLabel',
      shortcut: '⌘D',
    ),
    const PopupMenuDivider(),
    ContextMenuItem(
      value: 'cut',
      icon: BI.cut,
      label: 'Cut $noteLabel',
      shortcut: '⌘X',
    ),
    ContextMenuItem(
      value: 'copy',
      icon: BI.copy,
      label: 'Copy $noteLabel',
      shortcut: '⌘C',
    ),
    ContextMenuItem(
      value: 'paste',
      icon: BI.paste,
      label: 'Paste',
      shortcut: '⌘V',
      enabled: canPaste,
    ),
    const PopupMenuDivider(),
    ContextMenuItem(
      value: 'quantize',
      icon: BI.gridOn,
      label: 'Quantize',
      shortcut: 'Q',
    ),
    ContextMenuItem(
      value: 'velocity',
      icon: BI.speed,
      label: 'Velocity: $velocity',
    ),
  ];

  return ContextMenuHelper.show(
    context: context,
    position: position,
    items: items,
  );
}
