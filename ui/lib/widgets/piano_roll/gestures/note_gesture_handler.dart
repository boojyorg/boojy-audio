import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/midi_note_data.dart';
import '../../../models/tool_mode.dart';
import '../../piano_roll.dart';
import '../piano_roll_state.dart';
import '../operations/note_operations.dart';
import '../operations/selection_operations.dart';
import '../operations/clipboard_operations.dart';

/// Mixin containing note gesture handling for PianoRoll.
/// Handles tap, drag, and context menu interactions with notes.
mixin NoteGestureHandlerMixin on State<PianoRoll>, PianoRollStateMixin,
    NoteOperationsMixin, SelectionOperationsMixin, ClipboardOperationsMixin {

  // ============================================
  // NOTE FINDING
  // ============================================

  /// Find note at position.
  MidiNoteData? findNoteAtPosition(Offset position) {
    final beat = getBeatAtX(position.dx);
    final note = getNoteAtY(position.dy);

    for (final midiNote in currentClip?.notes ?? <MidiNoteData>[]) {
      if (midiNote.contains(beat, note)) {
        return midiNote;
      }
    }
    return null;
  }

  /// Check if position is near left or right edge of note.
  /// Returns 'left', 'right', or null.
  String? getEdgeAtPosition(Offset position, MidiNoteData note) {
    const edgeThreshold = 9.0;

    final noteStartX = calculateBeatX(note.startTime);
    final noteEndX = calculateBeatX(note.endTime);
    final noteY = calculateNoteY(note.note);

    final isInVerticalRange = (position.dy >= noteY) &&
                               (position.dy <= noteY + pixelsPerNote);

    if (!isInVerticalRange) return null;

    if ((position.dx - noteStartX).abs() < edgeThreshold) {
      return 'left';
    }

    if ((position.dx - noteEndX).abs() < edgeThreshold) {
      return 'right';
    }

    return null;
  }

  /// Find note at velocity lane position.
  MidiNoteData? findNoteAtVelocityPosition(Offset position) {
    final beat = getBeatAtX(position.dx);

    for (final note in currentClip?.notes ?? <MidiNoteData>[]) {
      if (beat >= note.startTime && beat < note.endTime) {
        return note;
      }
    }
    return null;
  }

  // ============================================
  // TAP HANDLING
  // ============================================

  /// Handle tap down on piano roll grid.
  void handleTapDown(TapDownDetails details) {
    focusNode.requestFocus();

    final clickedNote = findNoteAtPosition(details.localPosition);
    final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final toolMode = effectiveToolMode;

    // Alt+click OR Erase tool = delete note
    if (isAltPressed || toolMode == ToolMode.eraser) {
      if (clickedNote != null) {
        saveToHistory();
        setState(() {
          currentClip = currentClip?.copyWith(
            notes: currentClip!.notes.where((n) => n.id != clickedNote.id).toList(),
          );
        });
        commitToHistory('Delete note');
        notifyClipUpdated();
      }
      return;
    }

    // Slice tool = slice note
    if (toolMode == ToolMode.slice) {
      if (clickedNote != null) {
        final beatPosition = getBeatAtX(details.localPosition.dx);
        sliceNoteAt(clickedNote, beatPosition);
      }
      return;
    }

    // Duplicate tool OR Cmd+click on note = duplicate in place
    if (toolMode == ToolMode.duplicate || (isCtrlOrCmd && clickedNote != null)) {
      if (clickedNote != null) {
        saveToHistory();
        final duplicate = clickedNote.copyWith(
          id: '${clickedNote.note}_${DateTime.now().microsecondsSinceEpoch}',
          isSelected: false,
        );
        setState(() {
          currentClip = currentClip?.addNote(duplicate);
        });
        commitToHistory('Duplicate note');
        notifyClipUpdated();
        startAudition(clickedNote.note, clickedNote.velocity);
      }
      return;
    }

    // Select tool = only select notes, don't create new ones
    if (toolMode == ToolMode.select) {
      if (clickedNote != null) {
        if (isShiftPressed) {
          toggleNoteSelection(clickedNote.id);
        } else {
          selectSingleNote(clickedNote.id);
        }
        startAudition(clickedNote.note, clickedNote.velocity);
      } else {
        deselectAllNotes();
        notifyClipUpdated();
      }
      return;
    }

    // Draw tool (default behavior)
    if (isCtrlOrCmd && clickedNote == null) {
      final beat = getBeatAtX(details.localPosition.dx);
      final noteToSlice = currentClip?.notes.firstWhere(
        (n) => n.startTime < beat && (n.startTime + n.duration) > beat,
        orElse: () => MidiNoteData(note: -1, velocity: 0, startTime: 0, duration: 0),
      );
      if (noteToSlice != null && noteToSlice.note >= 0) {
        sliceNoteAt(noteToSlice, beat);
      }
      return;
    }

    if (clickedNote != null) {
      if (isShiftPressed) {
        toggleNoteSelection(clickedNote.id);
        return;
      }

      setState(() {
        currentClip = currentClip?.copyWith(
          notes: currentClip!.notes.map((n) {
            if (n.id == clickedNote.id) {
              return n.copyWith(isSelected: !n.isSelected);
            } else {
              return n.copyWith(isSelected: false);
            }
          }).toList(),
        );
      });
      notifyClipUpdated();
      startAudition(clickedNote.note, clickedNote.velocity);
      justCreatedNoteId = null;
    } else {
      // Single-click on empty space = create note
      final beat = getBeatAtX(details.localPosition.dx);
      final noteRow = getNoteAtY(details.localPosition.dy);

      saveToHistory();
      final snappedBeat = snapToGrid(beat);

      // Stamp chord if chord palette visible
      if (chordPaletteVisible) {
        stampChordAt(snappedBeat, noteRow);
        return;
      }

      // Create single note
      final newNote = MidiNoteData(
        note: noteRow,
        velocity: 100,
        startTime: snappedBeat,
        duration: lastNoteDuration,
        isSelected: true,
      );

      setState(() {
        currentClip = currentClip?.copyWith(
          notes: currentClip!.notes.map((n) => n.copyWith(isSelected: false)).toList(),
        );
        currentClip = currentClip?.addNote(newNote);
        autoExtendLoopIfNeeded(newNote);
      });

      justCreatedNoteId = newNote.id;
      commitToHistory('Add note');
      notifyClipUpdated();
      startAudition(noteRow, 100);
    }
  }

  // ============================================
  // AUDITION SUPPORT
  // ============================================

  /// Start sustained audition.
  void startAudition(int midiNote, int velocity) {
    if (!auditionEnabled) return;
    stopAudition();

    final trackId = currentClip?.trackId;
    if (trackId != null && widget.audioEngine != null) {
      widget.audioEngine!.sendTrackMidiNoteOn(trackId, midiNote, velocity);
      currentlyHeldNote = midiNote;
    }
  }

  /// Stop the currently held audition note.
  void stopAudition() {
    if (currentlyHeldNote != null) {
      final trackId = currentClip?.trackId;
      if (trackId != null && widget.audioEngine != null) {
        widget.audioEngine!.sendTrackMidiNoteOff(trackId, currentlyHeldNote!, 64);
      }
      currentlyHeldNote = null;
    }
  }

  /// Change audition pitch while holding.
  void changeAuditionPitch(int newMidiNote, int velocity) {
    if (!auditionEnabled) return;
    if (newMidiNote == currentlyHeldNote) return;

    final trackId = currentClip?.trackId;
    if (trackId != null && widget.audioEngine != null) {
      if (currentlyHeldNote != null) {
        widget.audioEngine!.sendTrackMidiNoteOff(trackId, currentlyHeldNote!, 64);
      }
      widget.audioEngine!.sendTrackMidiNoteOn(trackId, newMidiNote, velocity);
      currentlyHeldNote = newMidiNote;
    }
  }

  /// Preview a chord.
  void previewChord(List<int> midiNotes) {
    if (!auditionEnabled) return;
    final trackId = currentClip?.trackId;
    if (trackId == null || widget.audioEngine == null) return;

    for (final midiNote in midiNotes) {
      widget.audioEngine!.sendTrackMidiNoteOn(trackId, midiNote, 100);
    }
    Future.delayed(const Duration(milliseconds: 500), () {
      for (final midiNote in midiNotes) {
        widget.audioEngine?.sendTrackMidiNoteOff(trackId, midiNote, 64);
      }
    });
  }

  /// Stamp a chord at the given position.
  void stampChordAt(double beat, int baseNote) {
    if (currentClip == null) return;

    final chordNotes = chordConfig.midiNotes;
    if (chordNotes.isEmpty) return;

    final lowestChordNote = chordNotes.reduce((a, b) => a < b ? a : b);
    final offset = baseNote - lowestChordNote;

    final newNotes = <MidiNoteData>[];
    for (final midiNote in chordNotes) {
      final transposedNote = midiNote + offset;
      if (transposedNote >= 0 && transposedNote <= 127) {
        newNotes.add(MidiNoteData(
          note: transposedNote,
          velocity: 100,
          startTime: beat,
          duration: lastNoteDuration,
          isSelected: true,
        ));
      }
    }

    if (newNotes.isEmpty) return;

    setState(() {
      currentClip = currentClip?.copyWith(
        notes: currentClip!.notes.map((n) => n.copyWith(isSelected: false)).toList(),
      );
      for (final note in newNotes) {
        currentClip = currentClip?.addNote(note);
        autoExtendLoopIfNeeded(note);
      }
    });

    commitToHistory('Add chord');
    notifyClipUpdated();
    previewChord(newNotes.map((n) => n.note).toList());
  }

  // ============================================
  // ERASER MODE
  // ============================================

  /// Start eraser mode.
  void startErasing(Offset position) {
    saveToHistory();
    isErasing = true;
    erasedNoteIds = {};
    setState(() => currentCursor = SystemMouseCursors.forbidden);
    eraseNotesAt(position);
  }

  /// Erase notes at the given position.
  void eraseNotesAt(Offset position) {
    final note = findNoteAtPosition(position);
    if (note != null && !erasedNoteIds.contains(note.id)) {
      erasedNoteIds.add(note.id);
      setState(() {
        currentClip = currentClip?.copyWith(
          notes: currentClip!.notes.where((n) => n.id != note.id).toList(),
        );
      });
      notifyClipUpdated();
    }
  }

  /// Stop eraser mode.
  void stopErasing() {
    if (erasedNoteIds.isNotEmpty) {
      commitToHistory('Delete ${erasedNoteIds.length} notes');
    }
    isErasing = false;
    erasedNoteIds = {};
    setState(() => currentCursor = SystemMouseCursors.basic);
  }
}
