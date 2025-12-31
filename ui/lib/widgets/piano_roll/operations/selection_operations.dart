import 'package:flutter/material.dart';
import '../../piano_roll.dart';
import '../piano_roll_state.dart';
import 'note_operations.dart';

/// Mixin containing selection operations for PianoRoll.
mixin SelectionOperationsMixin on State<PianoRoll>, PianoRollStateMixin, NoteOperationsMixin {
  /// Select all notes in the current clip.
  void selectAllNotes() {
    if (currentClip == null || currentClip!.notes.isEmpty) return;

    setState(() {
      currentClip = currentClip?.copyWith(
        notes: currentClip!.notes.map((n) => n.copyWith(isSelected: true)).toList(),
      );
    });
  }

  /// Deselect all notes.
  void deselectAllNotes() {
    if (currentClip == null) return;

    final hasSelection = currentClip!.notes.any((n) => n.isSelected);
    if (!hasSelection) return;

    setState(() {
      currentClip = currentClip?.copyWith(
        notes: currentClip!.notes.map((n) => n.copyWith(isSelected: false)).toList(),
      );
    });
  }

  /// Toggle selection of a specific note.
  void toggleNoteSelection(String noteId) {
    if (currentClip == null) return;

    setState(() {
      currentClip = currentClip?.copyWith(
        notes: currentClip!.notes.map((n) {
          if (n.id == noteId) {
            return n.copyWith(isSelected: !n.isSelected);
          }
          return n;
        }).toList(),
      );
    });
    notifyClipUpdated();
  }

  /// Select a single note, deselecting others.
  void selectSingleNote(String noteId) {
    if (currentClip == null) return;

    setState(() {
      currentClip = currentClip?.copyWith(
        notes: currentClip!.notes.map((n) {
          return n.copyWith(isSelected: n.id == noteId);
        }).toList(),
      );
    });
    notifyClipUpdated();
  }

  /// Add a note to the current selection (shift+click).
  void addToSelection(String noteId) {
    if (currentClip == null) return;

    setState(() {
      currentClip = currentClip?.copyWith(
        notes: currentClip!.notes.map((n) {
          if (n.id == noteId) {
            return n.copyWith(isSelected: true);
          }
          return n;
        }).toList(),
      );
    });
    notifyClipUpdated();
  }

  /// Update box selection based on current rectangle.
  void updateBoxSelection(Offset start, Offset end) {
    if (currentClip == null) return;

    final startBeat = getBeatAtX(start.dx.clamp(0, double.infinity));
    final endBeat = getBeatAtX(end.dx.clamp(0, double.infinity));
    final startNote = getNoteAtY(start.dy.clamp(0, double.infinity));
    final endNote = getNoteAtY(end.dy.clamp(0, double.infinity));

    final minBeat = startBeat < endBeat ? startBeat : endBeat;
    final maxBeat = startBeat < endBeat ? endBeat : startBeat;
    final minNote = startNote < endNote ? startNote : endNote;
    final maxNote = startNote < endNote ? endNote : startNote;

    setState(() {
      currentClip = currentClip?.copyWith(
        notes: currentClip!.notes.map((note) {
          final isInRange = note.startTime < maxBeat &&
                            note.endTime > minBeat &&
                            note.note >= minNote &&
                            note.note <= maxNote;
          return note.copyWith(isSelected: isInRange);
        }).toList(),
      );
    });
  }

  // ============================================
  // COORDINATE HELPERS
  // ============================================

  /// Get MIDI note at Y coordinate.
  int getNoteAtY(double y) {
    final rawNote = PianoRollStateMixin.maxMidiNote - (y / pixelsPerNote).floor();
    if (scaleLockEnabled) {
      return snapNoteToScale(rawNote);
    }
    return rawNote;
  }

  /// Get beat at X coordinate.
  double getBeatAtX(double x) {
    return x / pixelsPerBeat;
  }

  /// Calculate Y coordinate for a MIDI note.
  double calculateNoteY(int midiNote) {
    return (PianoRollStateMixin.maxMidiNote - midiNote) * pixelsPerNote;
  }

  /// Calculate X coordinate for a beat.
  double calculateBeatX(double beat) {
    return beat * pixelsPerBeat;
  }
}
