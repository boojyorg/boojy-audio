import 'package:flutter/material.dart';

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
      icon: Icons.delete_outline,
      label: 'Delete Clip',
      shortcut: '⌘⌫',
    ),
    ContextMenuItem(
      value: 'duplicate',
      icon: Icons.content_copy,
      label: 'Duplicate',
      shortcut: '⌘D',
    ),
    ContextMenuItem(
      value: 'split',
      icon: Icons.content_cut,
      label: 'Split at Marker',
      shortcut: '⌘E',
    ),
    const PopupMenuDivider(),
    ContextMenuItem(
      value: 'cut',
      icon: Icons.content_cut,
      label: 'Cut',
      shortcut: '⌘X',
    ),
    ContextMenuItem(
      value: 'copy',
      icon: Icons.copy,
      label: 'Copy',
      shortcut: '⌘C',
    ),
    ContextMenuItem(
      value: 'paste',
      icon: Icons.paste,
      label: 'Paste',
      shortcut: '⌘V',
    ),
    const PopupMenuDivider(),
    ContextMenuItem(
      value: 'mute',
      icon: Icons.volume_off,
      label: 'Mute Clip',
    ),
    // MIDI-specific actions
    if (clipType == ClipType.midi) ...[
      ContextMenuItem(
        value: 'loop',
        icon: Icons.loop,
        label: 'Loop Clip',
      ),
      ContextMenuItem(
        value: 'bounce',
        icon: Icons.audiotrack,
        label: 'Bounce to Audio',
      ),
      ContextMenuItem(
        value: 'export_midi',
        icon: Icons.file_download_outlined,
        label: 'Export as MIDI File...',
      ),
    ],
    const PopupMenuDivider(),
    ContextMenuItem(
      value: 'color',
      icon: Icons.color_lens,
      label: 'Color...',
    ),
    ContextMenuItem(
      value: 'rename',
      icon: Icons.edit,
      label: 'Rename...',
    ),
  ];

  return ContextMenuHelper.show(
    context: context,
    position: position,
    items: items,
  );
}
