import 'package:flutter/gestures.dart';
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
    // Check if starting on a note - if so, begin drag
    final note = findNoteAtVelocityPosition(details.localPosition);
    if (note != null) {
      saveToHistory();
      velocityDragActive = true;
      velocityDraggedNoteId = note.id;
      // Update the note at start position immediately
      _updateVelocityAtPosition(details.localPosition);
    }
  }

  /// Handle velocity lane pan update
  void onVelocityPanUpdate(DragUpdateDetails details) {
    if (!velocityDragActive) return;
    _updateVelocityAtPosition(details.localPosition);
  }

  /// Update velocity for note at given position (position-aware)
  void _updateVelocityAtPosition(Offset position) {
    final note = findNoteAtVelocityPosition(position);
    if (note == null) return; // No note at this X position

    // Update tracked note ID for highlight
    velocityDraggedNoteId = note.id;

    // Calculate new velocity based on Y position (inverted - top = high velocity)
    final newVelocity = ((1 - (position.dy / velocityLaneHeight)) * 127)
        .round()
        .clamp(1, 127);

    setState(() {
      currentClip = currentClip?.copyWith(
        notes: currentClip!.notes.map((n) {
          if (n.id == note.id) {
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
    if (velocityDragActive) {
      commitToHistory('Change velocity');
      velocityDragActive = false;
      velocityDraggedNoteId = null;
    }
  }

  /// Handle velocity lane hover
  void onVelocityHover(PointerHoverEvent event) {
    final note = findNoteAtVelocityPosition(event.localPosition);
    final newHoveredId = note?.id;
    if (newHoveredId != velocityHoveredNoteId) {
      setState(() {
        velocityHoveredNoteId = newHoveredId;
      });
    }
  }

  /// Handle velocity lane hover exit
  void onVelocityHoverExit(PointerExitEvent event) {
    if (velocityHoveredNoteId != null) {
      setState(() {
        velocityHoveredNoteId = null;
      });
    }
  }

  // ============================================
  // VELOCITY LANE RESIZE
  // ============================================

  /// Handle velocity lane resize drag
  void onVelocityLaneResizeUpdate(DragUpdateDetails details) {
    setState(() {
      // Dragging up (negative dy) = increase height
      // Allow any height - display will clamp to available space
      velocityLaneHeight = (velocityLaneHeight - details.delta.dy)
          .clamp(PianoRollStateMixin.velocityLaneMinHeight, 10000.0);
    });
  }
}
