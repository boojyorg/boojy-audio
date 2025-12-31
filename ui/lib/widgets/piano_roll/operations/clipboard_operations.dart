import 'package:flutter/material.dart';
import '../../piano_roll.dart';
import '../piano_roll_state.dart';
import 'note_operations.dart';

/// Mixin containing clipboard operations (copy, cut, paste) for PianoRoll.
mixin ClipboardOperationsMixin on State<PianoRoll>, PianoRollStateMixin, NoteOperationsMixin {
  /// Copy selected notes to clipboard.
  void copySelectedNotes() {
    final selectedNotes = currentClip?.selectedNotes ?? [];
    if (selectedNotes.isEmpty) return;

    clipboard = selectedNotes.map((note) => note.copyWith(isSelected: false)).toList();
  }

  /// Cut selected notes (copy to clipboard, then delete).
  void cutSelectedNotes() {
    final selectedNotes = currentClip?.selectedNotes ?? [];
    if (selectedNotes.isEmpty) return;

    clipboard = selectedNotes.map((note) => note.copyWith(isSelected: false)).toList();

    saveToHistory();
    final selectedIds = selectedNotes.map((n) => n.id).toSet();
    setState(() {
      currentClip = currentClip?.copyWith(
        notes: currentClip!.notes.where((n) => !selectedIds.contains(n.id)).toList(),
      );
    });
    notifyClipUpdated();
    commitToHistory(selectedNotes.length == 1 ? 'Cut note' : 'Cut ${selectedNotes.length} notes');
  }

  /// Paste notes from clipboard.
  void pasteNotes() {
    if (clipboard.isEmpty) return;
    if (currentClip == null) return;

    saveToHistory();

    final earliestTime = clipboard.map((n) => n.startTime).reduce((a, b) => a < b ? a : b);
    final pasteTime = insertMarkerBeats ?? 0.0;
    final timeOffset = pasteTime - earliestTime;

    final newNotes = clipboard.map((note) {
      return note.copyWith(
        id: '${DateTime.now().microsecondsSinceEpoch}_${note.note}',
        startTime: note.startTime + timeOffset,
        isSelected: true,
      );
    }).toList();

    setState(() {
      currentClip = currentClip?.copyWith(
        notes: [
          ...currentClip!.notes.map((n) => n.copyWith(isSelected: false)),
          ...newNotes,
        ],
      );
    });

    notifyClipUpdated();
    commitToHistory(newNotes.length == 1 ? 'Paste note' : 'Paste ${newNotes.length} notes');
  }
}
