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
  /// Find the note whose velocity circle is nearest [position]: the nearest
  /// stalk in X (within a pixel threshold), and among notes that share it (a
  /// chord), the circle nearest in height. While a drag holds a note, that
  /// note stays picked as long as the pointer is on its stalk.
  MidiNoteData? findNoteAtVelocityPosition(Offset position) {
    final notes = currentClip?.notes ?? <MidiNoteData>[];
    if (notes.isEmpty) return null;

    const leftThreshold = 45.0; // pixels to left of circle
    const rightThreshold = 55.0; // pixels to right of circle
    // Notes whose stalks are this close count as one column (a chord, even
    // one played slightly loose); the circle nearest in height wins there.
    const sameColumn = 4.0;

    final inReach = <MidiNoteData>[];
    var nearestX = double.infinity;
    for (final note in notes) {
      final dx = position.dx - note.startTime * pixelsPerBeat;
      // Asymmetric reach: less to the left of a circle than to its right.
      if (dx < 0 ? -dx <= leftThreshold : dx <= rightThreshold) {
        inReach.add(note);
        if (dx.abs() < nearestX) nearestX = dx.abs();
      }
    }

    bool inNearestColumn(MidiNoteData note) =>
        (position.dx - note.startTime * pixelsPerBeat).abs() <=
        nearestX + sameColumn;

    if (velocityDragActive) {
      for (final note in inReach) {
        if (note.id == velocityDraggedNoteId && inNearestColumn(note)) {
          return note;
        }
      }
    }

    MidiNoteData? nearest;
    var nearestY = double.infinity;
    for (final note in inReach) {
      if (!inNearestColumn(note)) continue;
      final circleY = (1 - note.velocity / 127) * velocityLaneHeight;
      final dy = (position.dy - circleY).abs();
      if (dy < nearestY) {
        nearestY = dy;
        nearest = note;
      }
    }

    return nearest;
  }
}
