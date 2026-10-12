import 'package:flutter/material.dart';
import '../../../models/midi_note_data.dart';
import '../../piano_roll.dart';
import '../piano_roll_state.dart';
import '../audition_mixin.dart';
import '../operations/note_operations.dart';
import '../operations/selection_operations.dart';
import '../operations/clipboard_operations.dart';

/// Mixin for PianoRoll note lookups.
mixin NoteGestureHandlerMixin
    on
        State<PianoRoll>,
        PianoRollStateMixin,
        AuditionMixin,
        NoteOperationsMixin,
        SelectionOperationsMixin,
        ClipboardOperationsMixin {
  /// Find note nearest to velocity lane position (by start time).
  /// Returns the note whose circle is closest to cursor X,
  /// but only if within pixel threshold (FL Studio style).
  MidiNoteData? findNoteAtVelocityPosition(Offset position) {
    final notes = currentClip?.notes ?? <MidiNoteData>[];
    if (notes.isEmpty) return null;

    const leftThreshold = 45.0; // pixels to left of circle
    const rightThreshold = 55.0; // pixels to right of circle

    MidiNoteData? nearest;
    double minDistance = double.infinity;

    for (final note in notes) {
      final circleX = note.startTime * pixelsPerBeat;
      final dx = position.dx - circleX;

      // Check if within threshold (asymmetric: left vs right)
      bool withinThreshold;
      if (dx < 0) {
        // Cursor is to the left of circle
        withinThreshold = dx.abs() <= leftThreshold;
      } else {
        // Cursor is to the right of circle
        withinThreshold = dx <= rightThreshold;
      }

      if (withinThreshold) {
        final distance = dx.abs();
        if (distance < minDistance) {
          minDistance = distance;
          nearest = note;
        }
      }
    }

    return nearest;
  }
}
