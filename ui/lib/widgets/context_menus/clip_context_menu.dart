import 'package:flutter/material.dart';

import '../../theme/boojy_icons.dart';
import '../shared/context_menu_item.dart';

/// Clip type for context menu customization
enum ClipType { audio, midi }

/// Callback definitions for clip context menu actions
typedef ClipContextMenuCallback = void Function(String action);

/// Shows a context menu for audio or MIDI clips.
///
/// Returns the selected action string, or null if dismissed.
Future<String?> showClipContextMenu({
  required BuildContext context,
  required Offset position,
  required ClipType clipType,
}) {
  final items = <PopupMenuEntry<String>>[
    // Common actions
    ContextMenuItem(
      value: 'delete',
      icon: BI.delete,
      label: 'Delete Clip',
      shortcut: '⌘⌫',
    ),
    ContextMenuItem(
      value: 'duplicate',
      icon: BI.copy,
      label: 'Duplicate',
      shortcut: '⌘D',
    ),
    ContextMenuItem(
      value: 'split',
      icon: BI.cut,
      label: 'Split at Marker',
      shortcut: '⌘E',
    ),
    const PopupMenuDivider(),
    ContextMenuItem(value: 'cut', icon: BI.cut, label: 'Cut', shortcut: '⌘X'),
    ContextMenuItem(
      value: 'copy',
      icon: BI.copy,
      label: 'Copy',
      shortcut: '⌘C',
    ),
    ContextMenuItem(
      value: 'paste',
      icon: BI.paste,
      label: 'Paste',
      shortcut: '⌘V',
    ),
    const PopupMenuDivider(),
    ContextMenuItem(value: 'mute', icon: BI.speakerNone, label: 'Mute Clip'),
    // MIDI-specific actions
    if (clipType == ClipType.midi) ...[
      ContextMenuItem(value: 'loop', icon: BI.loop, label: 'Loop Clip'),
      ContextMenuItem(
        value: 'bounce',
        icon: BI.musicNote,
        label: 'Bounce to Audio',
      ),
      ContextMenuItem(
        value: 'export_midi',
        icon: BI.download,
        label: 'Export as MIDI File...',
      ),
    ],
    const PopupMenuDivider(),
    ContextMenuItem(value: 'color', icon: BI.colorLens, label: 'Color...'),
    ContextMenuItem(value: 'rename', icon: BI.pencil, label: 'Rename...'),
  ];

  return ContextMenuHelper.show(
    context: context,
    position: position,
    items: items,
  );
}
