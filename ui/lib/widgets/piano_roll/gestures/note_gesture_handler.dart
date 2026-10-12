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

    double stalkX(MidiNoteData note) => note.startTime * pixelsPerBeat;

    // The stalk nearest the pointer, among notes within reach.
    final inReach = <MidiNoteData>[];
    var nearestDx = double.infinity;
    var nearestStalkX = 0.0;
    for (final note in notes) {
      final dx = position.dx - stalkX(note);
      // Asymmetric reach: less to the left of a circle than to its right.
      if (dx < 0 ? -dx <= leftThreshold : dx <= rightThreshold) {
        inReach.add(note);
        if (dx.abs() < nearestDx) {
          nearestDx = dx.abs();
          nearestStalkX = stalkX(note);
        }
      }
    }

    // Its column: notes whose own stalk is within [sameColumn] of it. (Not
    // "about as far from the pointer": midway between two stalks a beat
    // apart, both are, and the far note could win on height.)
    bool inNearestColumn(MidiNoteData note) =>
        (stalkX(note) - nearestStalkX).abs() <= sameColumn;

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
