import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../models/midi_note_data.dart';
import '../piano_roll.dart';
import 'piano_roll_state.dart';
import 'operations/note_operations.dart';
import 'gestures/note_gesture_handler.dart';

/// Mixin containing velocity lane operations for PianoRoll.
/// Handles velocity editing interactions in the velocity lane.
mixin VelocityLaneMixin
    on
        State<PianoRoll>,
        PianoRollStateMixin,
        NoteOperationsMixin,
        NoteGestureHandlerMixin {
  // ============================================
  // VELOCITY LANE OPERATIONS
  // ============================================

  /// Toggle velocity lane visibility on/off
  void toggleVelocityLane() {
    setState(() {
      velocityLaneExpanded = !velocityLaneExpanded;
    });
  }

  /// Starting velocities of the selected notes while one of them is dragged;
  /// null when the drag edits single notes.
  Map<String, int>? _selectionStartVelocities;

  /// Handle velocity lane pan start
  void onVelocityPanStart(DragStartDetails details) {
    // Check if starting on a note - if so, begin drag
    final note = findNoteAtVelocityPosition(details.localPosition);
    if (note != null) {
      saveToHistory();
      velocityDragActive = true;
      velocityDraggedNoteId = note.id;
      // Dragging one of several selected notes moves them all by the same
      // amount, so louder and softer notes keep their difference.
      final selected = currentClip?.selectedNotes ?? const <MidiNoteData>[];
      _selectionStartVelocities = note.isSelected && selected.length > 1
          ? {for (final n in selected) n.id: n.velocity}
          : null;
      // Update the note at start position immediately
      _updateVelocityAtPosition(details.localPosition);
    }
  }

  /// Handle velocity lane pan update
  void onVelocityPanUpdate(DragUpdateDetails details) {
    if (!velocityDragActive) return;
    _updateVelocityAtPosition(details.localPosition);
  }

  /// Velocity a Y position stands for (inverted - top = high velocity). Not
  /// clamped: above or below the lane it runs past 127 or below 1.
  int _rawVelocityAtY(double dy) =>
      ((1 - (dy / velocityLaneHeight)) * 127).round();

  int _velocityAtY(double dy) => _rawVelocityAtY(dy).clamp(1, 127);

  /// Update velocity for note at given position (position-aware)
  void _updateVelocityAtPosition(Offset position) {
    final startVelocities = _selectionStartVelocities;
    if (startVelocities != null) {
      _moveSelectedVelocities(position.dy, startVelocities);
      return;
    }

    final note = findNoteAtVelocityPosition(position);
    if (note == null) return; // No note at this X position

    // Update tracked note ID for highlight
    velocityDraggedNoteId = note.id;

    final newVelocity = _velocityAtY(position.dy);

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

  /// Move every selected note by the dragged note's change, each kept
  /// within 1–127. The change isn't capped by the dragged note's own limit,
  /// so pushing on past the top or bottom gathers the rest there too; it's
  /// measured from the drag's start, so coming back restores the gaps.
  void _moveSelectedVelocities(double dy, Map<String, int> startVelocities) {
    final dragged = startVelocities[velocityDraggedNoteId];
    if (dragged == null) return;
    final delta = _rawVelocityAtY(dy) - dragged;

    setState(() {
      currentClip = currentClip?.copyWith(
        notes: currentClip!.notes.map((n) {
          final start = startVelocities[n.id];
          if (start == null) return n;
          return n.copyWith(velocity: (start + delta).clamp(1, 127));
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
      _selectionStartVelocities = null;
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
      velocityLaneHeight = (velocityLaneHeight - details.delta.dy).clamp(
        PianoRollStateMixin.velocityLaneMinHeight,
        10000.0,
      );
    });
  }
}
