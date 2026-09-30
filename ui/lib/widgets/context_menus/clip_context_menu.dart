import 'package:flutter/material.dart' show BuildContext, Offset;

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
  bool canJoin = false,
}) {
  // Only actions that work for this clip type are offered ("inert controls
  // work or are hidden"). Audio clips have no cut/copy/paste, mute, colour or
  // rename yet, so they don't show them.
  final isMidi = clipType == ClipType.midi;
  final items = <BoojyMenuEntry<String>>[
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
      label: 'Split at Playhead',
      shortcut: '⌘E',
    ),
    // Only offered with 2+ clips of this type selected
    if (canJoin)
      ContextMenuItem(
        value: 'join',
        icon: BI.join,
        label: 'Join Clips',
        shortcut: '⌘J',
      ),
    if (isMidi) ...[
      const BoojyMenuDivider<String>(),
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
      const BoojyMenuDivider<String>(),
      ContextMenuItem(value: 'mute', icon: BI.speakerNone, label: 'Mute Clip'),
      ContextMenuItem(value: 'loop', icon: BI.loop, label: 'Loop Clip'),
      ContextMenuItem(
        value: 'export_midi',
        icon: BI.download,
        label: 'Export as MIDI File...',
      ),
      ContextMenuItem(value: 'rename', icon: BI.pencil, label: 'Rename...'),
    ],
  ];

  return ContextMenuHelper.show(
    context: context,
    position: position,
    items: items,
  );
}
