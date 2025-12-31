import 'package:flutter/material.dart';
import '../piano_roll.dart';
import 'piano_roll_state.dart';
import 'operations/note_operations.dart';
import 'gestures/note_gesture_handler.dart';

/// Mixin containing velocity lane operations for PianoRoll.
/// Handles velocity editing interactions in the velocity lane.
mixin VelocityLaneMixin on State<PianoRoll>, PianoRollStateMixin, NoteOperationsMixin, NoteGestureHandlerMixin {
  // ============================================
  // VELOCITY LANE OPERATIONS
  // ============================================

  /// Toggle velocity lane visibility on/off
  void toggleVelocityLane() {
    setState(() {
      velocityLaneExpanded = !velocityLaneExpanded;
    });
  }

  /// Handle velocity lane pan start
  void onVelocityPanStart(DragStartDetails details) {
    final note = findNoteAtVelocityPosition(details.localPosition);
    if (note != null) {
      saveToHistory();
      velocityDragNoteId = note.id;
    }
  }

  /// Handle velocity lane pan update
  void onVelocityPanUpdate(DragUpdateDetails details) {
    if (velocityDragNoteId == null) return;

    // Calculate new velocity based on Y position (inverted - top = high velocity)
    final newVelocity = ((1 - (details.localPosition.dy / PianoRollStateMixin.velocityLaneHeight)) * 127)
        .round()
        .clamp(1, 127);

    setState(() {
      currentClip = currentClip?.copyWith(
        notes: currentClip!.notes.map((n) {
          if (n.id == velocityDragNoteId) {
            return n.copyWith(velocity: newVelocity);
          }
          return n;
        }).toList(),
      );
    });
    notifyClipUpdated();
  }

  /// Handle velocity lane pan end
  void onVelocityPanEnd(DragEndDetails details) {
    if (velocityDragNoteId != null) {
      commitToHistory('Change velocity');
      velocityDragNoteId = null;
    }
  }
}
