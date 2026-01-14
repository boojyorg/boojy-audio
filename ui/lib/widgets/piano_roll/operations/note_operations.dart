import 'dart:math';
import 'package:flutter/material.dart';
import '../../../models/midi_note_data.dart';
import '../../../services/commands/clip_commands.dart';
import '../../../utils/grid_utils.dart';
import '../../piano_roll.dart';
import '../piano_roll_state.dart';
import '../utilities/piano_roll_coordinates.dart';

/// Mixin containing note manipulation operations for PianoRoll.
/// Includes adding, deleting, moving, resizing, and transforming notes.
mixin NoteOperationsMixin on State<PianoRoll>, PianoRollStateMixin {
  // ============================================
  // UNDO/REDO SUPPORT
  // ============================================

  /// Save current state snapshot before making changes.
  /// Call this BEFORE modifying currentClip.
  void saveToHistory() {
    if (currentClip == null) return;
    snapshotBeforeAction = currentClip!.copyWith(
      notes: List.from(currentClip!.notes),
    );
  }

  /// Commit the change to global undo history with a description.
  /// Call this AFTER modifying currentClip.
  void commitToHistory(String actionDescription) {
    if (snapshotBeforeAction == null || currentClip == null) return;

    final command = MidiClipSnapshotCommand(
      beforeState: snapshotBeforeAction!,
      afterState: currentClip!.copyWith(
        notes: List.from(currentClip!.notes),
      ),
      actionDescription: actionDescription,
      onApplyState: applyClipState,
    );

    undoRedoManager.execute(command);
    snapshotBeforeAction = null;
  }

  /// Callback for undo/redo to apply clip state.
  void applyClipState(MidiClipData clipData) {
    if (!mounted) return;
    setState(() {
      currentClip = clipData;
    });
    notifyClipUpdated();
  }

  /// Notify parent widget that clip has been updated.
  void notifyClipUpdated() {
    if (widget.onClipUpdated != null && currentClip != null) {
      widget.onClipUpdated!(currentClip!);
    }
    setState(() {});
  }

  /// Undo last action.
  Future<void> undo() async {
    await undoRedoManager.undo();
  }

  /// Redo last undone action.
  Future<void> redo() async {
    await undoRedoManager.redo();
  }

  // ============================================
  // BASIC NOTE OPERATIONS
  // ============================================

  /// Delete a specific note.
  void deleteNote(MidiNoteData note) {
    saveToHistory();
    setState(() {
      currentClip = currentClip?.copyWith(
        notes: currentClip!.notes.where((n) => n.id != note.id).toList(),
      );
    });
    notifyClipUpdated();
    commitToHistory('Delete note: ${note.noteName}');
  }

  /// Delete all selected notes.
  void deleteSelectedNotes() {
    final selectedCount = currentClip?.selectedNotes.length ?? 0;
    setState(() {
      final selectedIds = currentClip?.selectedNotes.map((n) => n.id).toSet() ?? {};
      currentClip = currentClip?.copyWith(
        notes: currentClip!.notes.where((n) => !selectedIds.contains(n.id)).toList(),
      );
    });
    notifyClipUpdated();
    commitToHistory(selectedCount == 1 ? 'Delete note' : 'Delete $selectedCount notes');
  }

  /// Duplicate a single note (place copy after original).
  void duplicateNote(MidiNoteData note) {
    saveToHistory();
    final newNote = note.copyWith(
      startTime: note.startTime + note.duration,
      id: '${note.note}_${note.startTime + note.duration}_${DateTime.now().microsecondsSinceEpoch}',
    );
    setState(() {
      currentClip = currentClip?.copyWith(
        notes: [...currentClip!.notes, newNote],
      );
    });
    notifyClipUpdated();
    commitToHistory('Duplicate note: ${note.noteName}');
  }

  /// Duplicate selected notes (place copies after originals).
  void duplicateSelectedNotes() {
    final selectedNotes = currentClip?.selectedNotes ?? [];
    if (selectedNotes.isEmpty) return;

    saveToHistory();

    final minStart = selectedNotes.map((n) => n.startTime).reduce((a, b) => a < b ? a : b);
    final maxEnd = selectedNotes.map((n) => n.endTime).reduce((a, b) => a > b ? a : b);
    final selectionDuration = maxEnd - minStart;

    final duplicates = selectedNotes.map((note) {
      return note.copyWith(
        id: '${note.note}_${note.startTime + selectionDuration}_${DateTime.now().microsecondsSinceEpoch}',
        startTime: note.startTime + selectionDuration,
        isSelected: true,
      );
    }).toList();

    setState(() {
      currentClip = currentClip?.copyWith(
        notes: [
          ...currentClip!.notes.map((n) => n.copyWith(isSelected: false)),
          ...duplicates,
        ],
      );

      for (final note in duplicates) {
        autoExtendLoopIfNeeded(note);
      }
    });

    notifyClipUpdated();
    commitToHistory(duplicates.length == 1 ? 'Duplicate note' : 'Duplicate ${duplicates.length} notes');
  }

  /// Slice a note at the given beat position.
  void sliceNoteAt(MidiNoteData note, double beatPosition) {
    final splitBeat = snapEnabled ? snapToGrid(beatPosition) : beatPosition;

    if (splitBeat <= note.startTime || splitBeat >= note.endTime) return;

    saveToHistory();

    final leftNote = note.copyWith(
      duration: splitBeat - note.startTime,
      id: '${DateTime.now().microsecondsSinceEpoch}_left',
    );
    final rightNote = note.copyWith(
      startTime: splitBeat,
      duration: note.endTime - splitBeat,
      id: '${DateTime.now().microsecondsSinceEpoch}_right',
    );

    setState(() {
      currentClip = currentClip?.copyWith(
        notes: currentClip!.notes
            .where((n) => n.id != note.id)
            .followedBy([leftNote, rightNote])
            .toList(),
      );
    });

    commitToHistory('Slice note');
    notifyClipUpdated();
  }

  // ============================================
  // QUANTIZATION
  // ============================================

  /// Quantize selected notes to grid.
  /// Uses quantizeDivision (0 = current snap grid, else explicit value).
  void quantizeSelectedNotes() {
    final selectedNotes =
        currentClip?.notes.where((n) => n.isSelected).toList() ?? [];
    if (selectedNotes.isEmpty) return;

    saveToHistory();

    // Calculate grid size based on quantize settings
    double gridSize;
    if (quantizeDivision == 0) {
      // Use current snap grid (including snap triplet)
      gridSize = adaptiveGridEnabled
          ? PianoRollCoordinates.getAdaptiveGridDivision(pixelsPerBeat)
          : gridDivision;
      if (snapTripletEnabled) {
        gridSize = gridSize * 2 / 3;
      }
    } else {
      // Use explicit quantize value (4, 8, 16, 32 → beats)
      gridSize = 4.0 / quantizeDivision; // e.g., 16 → 0.25 beats
      if (quantizeTripletEnabled) {
        gridSize = gridSize * 2 / 3;
      }
    }

    setState(() {
      currentClip = currentClip?.copyWith(
        notes: currentClip!.notes.map((n) {
          if (n.isSelected) {
            return n.quantize(gridSize);
          }
          return n;
        }).toList(),
      );
    });
    notifyClipUpdated();
    commitToHistory('Quantize ${selectedNotes.length} notes');
  }

  /// Quantize entire clip via engine.
  void quantizeClip(int gridDivisionValue) {
    if (currentClip == null || widget.audioEngine == null) return;

    final clipId = currentClip!.clipId;
    widget.audioEngine!.quantizeMidiClip(clipId, gridDivisionValue);
    loadClipFromEngine();
  }

  /// Reload clip notes from engine after quantization.
  void loadClipFromEngine() {
    if (currentClip == null) return;
    widget.onClipUpdated?.call(currentClip!);
    setState(() {});
  }

  // ============================================
  // TRANSFORM OPERATIONS
  // ============================================

  /// Transpose selected notes by a given number of semitones.
  /// Positive values transpose up, negative values transpose down.
  /// Notes are clamped to valid MIDI range (0-127).
  void transposeSelectedNotes(int semitones) {
    final selectedNotes = currentClip?.selectedNotes ?? [];
    if (selectedNotes.isEmpty) return;

    // Check if any note would go out of range
    for (final note in selectedNotes) {
      final newNote = note.note + semitones;
      if (newNote < 0 || newNote > 127) {
        // At least one note would be out of range, abort
        return;
      }
    }

    saveToHistory();

    setState(() {
      currentClip = currentClip?.copyWith(
        notes: currentClip!.notes.map((n) {
          if (n.isSelected) {
            return n.copyWith(note: n.note + semitones);
          }
          return n;
        }).toList(),
      );
    });

    notifyClipUpdated();

    final direction = semitones > 0 ? 'up' : 'down';
    final amount = semitones.abs();
    final unit = amount == 12 ? 'octave' : (amount == 1 ? 'semitone' : 'semitones');
    final displayAmount = amount == 12 ? '1' : '$amount';
    commitToHistory('Transpose $direction $displayAmount $unit');
  }

  /// Apply swing to selected notes.
  void applySwing() {
    if (currentClip == null) return;

    final selectedNotes = currentClip!.notes.where((n) => n.isSelected).toList();
    if (selectedNotes.isEmpty) return;

    saveToHistory();

    final swingDelay = swingAmount * 0.33;

    setState(() {
      currentClip = currentClip!.copyWith(
        notes: currentClip!.notes.map((note) {
          if (!note.isSelected) return note;

          final eighthNotePosition = (note.startTime / 0.5).round();
          final isOffBeat = eighthNotePosition.isOdd;

          if (isOffBeat) {
            final newStart = note.startTime + swingDelay;
            return note.copyWith(startTime: newStart);
          }
          return note;
        }).toList(),
      );
    });

    commitToHistory('Apply swing');
    notifyClipUpdated();
  }

  /// Apply stretch to selected notes (time scaling).
  void applyStretch() {
    if (currentClip == null) return;

    final selectedNotes = currentClip!.notes.where((n) => n.isSelected).toList();
    if (selectedNotes.isEmpty) return;

    saveToHistory();

    final selectionStart = selectedNotes.map((n) => n.startTime).reduce((a, b) => a < b ? a : b);

    setState(() {
      currentClip = currentClip!.copyWith(
        notes: currentClip!.notes.map((note) {
          if (!note.isSelected) return note;

          final relativeStart = note.startTime - selectionStart;
          final newStart = selectionStart + (relativeStart * stretchAmount);
          final newDuration = note.duration * stretchAmount;

          return note.copyWith(
            startTime: newStart,
            duration: newDuration,
          );
        }).toList(),
      );
    });

    commitToHistory('Stretch notes');
    notifyClipUpdated();
  }

  /// Apply humanize to selected notes (random timing variation).
  void applyHumanize() {
    if (currentClip == null) return;

    final selectedNotes = currentClip!.notes.where((n) => n.isSelected).toList();
    if (selectedNotes.isEmpty) return;

    saveToHistory();

    final maxVariationBeats = 0.1 * humanizeAmount;
    final random = Random();

    setState(() {
      currentClip = currentClip!.copyWith(
        notes: currentClip!.notes.map((note) {
          if (!note.isSelected) return note;

          final offset = (random.nextDouble() * 2 - 1) * maxVariationBeats;
          final newStart = (note.startTime + offset).clamp(0.0, double.infinity);

          return note.copyWith(startTime: newStart);
        }).toList(),
      );
    });

    commitToHistory('Humanize notes');
    notifyClipUpdated();
  }

  /// Apply legato - extend each note to touch the next note at same pitch.
  void applyLegato() {
    if (currentClip == null) return;

    final selectedNotes = currentClip!.notes.where((n) => n.isSelected).toList();
    if (selectedNotes.isEmpty) return;

    saveToHistory();

    final notesByPitch = <int, List<MidiNoteData>>{};
    for (final note in selectedNotes) {
      notesByPitch.putIfAbsent(note.note, () => []).add(note);
    }

    for (final notes in notesByPitch.values) {
      notes.sort((a, b) => a.startTime.compareTo(b.startTime));
    }

    setState(() {
      currentClip = currentClip!.copyWith(
        notes: currentClip!.notes.map((note) {
          if (!note.isSelected) return note;

          final pitchNotes = notesByPitch[note.note]!;
          final index = pitchNotes.indexWhere((n) => n.id == note.id);

          if (index < pitchNotes.length - 1) {
            final nextNote = pitchNotes[index + 1];
            final newDuration = nextNote.startTime - note.startTime;
            return note.copyWith(duration: newDuration);
          }

          return note;
        }).toList(),
      );
    });

    commitToHistory('Apply legato');
    notifyClipUpdated();
  }

  /// Reverse selected notes in time.
  void reverseNotes() {
    if (currentClip == null) return;

    final selectedNotes = currentClip!.notes.where((n) => n.isSelected).toList();
    if (selectedNotes.isEmpty) return;

    saveToHistory();

    final selectionStart = selectedNotes.map((n) => n.startTime).reduce((a, b) => a < b ? a : b);
    final selectionEnd = selectedNotes.map((n) => n.endTime).reduce((a, b) => a > b ? a : b);
    final selectionCenter = (selectionStart + selectionEnd) / 2;

    setState(() {
      currentClip = currentClip!.copyWith(
        notes: currentClip!.notes.map((note) {
          if (!note.isSelected) return note;

          final noteCenter = note.startTime + note.duration / 2;
          final distanceFromCenter = noteCenter - selectionCenter;
          final newNoteCenter = selectionCenter - distanceFromCenter;
          final newStart = newNoteCenter - note.duration / 2;

          return note.copyWith(startTime: newStart.clamp(0.0, double.infinity));
        }).toList(),
      );
    });

    commitToHistory('Reverse notes');
    notifyClipUpdated();
  }

  /// Randomize velocity of selected notes.
  void applyVelocityRandomize() {
    if (currentClip == null || velocityRandomizeAmount <= 0) return;

    final notes = currentClip!.notes;
    final selectedNotes = notes.where((n) => n.isSelected).toList();
    final targetNotes = selectedNotes.isNotEmpty ? selectedNotes : notes;

    if (targetNotes.isEmpty) return;

    saveToHistory();

    final maxVariation = (velocityRandomizeAmount * 50).round();
    final random = Random();

    setState(() {
      currentClip = currentClip!.copyWith(
        notes: currentClip!.notes.map((note) {
          final isTarget = selectedNotes.isEmpty || note.isSelected;
          if (!isTarget) return note;

          final variation = random.nextInt(maxVariation * 2 + 1) - maxVariation;
          final newVelocity = (note.velocity + variation).clamp(1, 127);

          return note.copyWith(velocity: newVelocity);
        }).toList(),
      );
    });

    commitToHistory('Randomize velocity');
    notifyClipUpdated();
  }

  // ============================================
  // UTILITY METHODS
  // ============================================

  /// Auto-extend loop length if a note extends beyond the current loop boundary.
  /// Also syncs duration (arrangement clip length) to match loopLength (one-way sync).
  void autoExtendLoopIfNeeded(MidiNoteData note) {
    if (currentClip == null) return;

    final noteEndTime = note.startTime + note.duration;
    final currentLoopLength = currentClip!.loopLength;

    if (noteEndTime > currentLoopLength) {
      final newLoopLength = ((noteEndTime / 4).ceil() * 4).toDouble();
      // One-way sync: when loop length expands due to notes, also expand duration
      // This keeps the arrangement clip in sync with the Piano Roll content
      final newDuration = newLoopLength > currentClip!.duration
          ? newLoopLength
          : currentClip!.duration;
      currentClip = currentClip!.copyWith(
        loopLength: newLoopLength,
        duration: newDuration,
      );
    }
  }

  /// Update the loop length in the current clip.
  /// One-way sync: always updates arrangement duration to match loopLength.
  void updateLoopLength(double newLength) {
    if (currentClip == null) return;
    // Minimum is 1/16th note (0.25 beats), maximum is 256 beats (64 bars)
    const minLength = 0.25;
    final clampedLength = newLength.clamp(minLength, 256.0);
    // One-way sync: loopLength change always syncs to duration
    // This keeps the arrangement clip length matching the Piano Roll loop length
    currentClip = currentClip!.copyWith(
      loopLength: clampedLength,
      duration: clampedLength,
    );
  }

  /// Auto-extend the canvas/clip if loop end exceeds current bounds.
  void autoExtendCanvasIfNeeded(double loopEndBeats) {
    if (currentClip == null) return;
    if (loopEndBeats > currentClip!.duration) {
      final newDuration = ((loopEndBeats / beatsPerBar).ceil() * beatsPerBar).toDouble();
      currentClip = currentClip!.copyWith(duration: newDuration);
    }
  }

  /// Snap a beat position to grid.
  /// Uses adaptive grid if enabled, and applies triplet modifier if active.
  double snapToGrid(double beat) {
    if (!snapEnabled) return beat;

    // Get effective grid division (with triplet modifier if enabled)
    final division = getEffectiveGridDivision();

    return GridUtils.snapToGridFloor(beat, division);
  }

  /// Get the current effective grid division (for display and grid rendering).
  double getEffectiveGridDivision() {
    double division = adaptiveGridEnabled
        ? GridUtils.getAdaptiveGridDivision(pixelsPerBeat)
        : gridDivision;

    if (snapTripletEnabled) {
      division = GridUtils.applyTripletModifier(division);
    }

    return division;
  }

  /// Snap a MIDI note to the current scale.
  int snapNoteToScale(int midiNote) {
    if (currentScale.containsNote(midiNote)) return midiNote;

    int below = midiNote;
    int above = midiNote;

    while (!currentScale.containsNote(below) && below >= 0) {
      below--;
    }
    while (!currentScale.containsNote(above) && above <= 127) {
      above++;
    }

    if (below < 0) return above;
    if (above > 127) return below;

    return (midiNote - below <= above - midiNote) ? below : above;
  }
}
