import 'package:flutter/material.dart';
import '../../constants/ui_constants.dart';
import '../piano_roll.dart';
import 'piano_roll_state.dart';

/// Mixin containing audition (note preview) functionality for PianoRoll.
/// Handles playing notes when clicking/dragging in the piano roll.
mixin AuditionMixin on State<PianoRoll>, PianoRollStateMixin {
  // ============================================
  // AUDITION METHODS
  // ============================================

  /// Chord-preview notes whose delayed NoteOff hasn't fired yet, so dispose()
  /// can flush them if the editor closes within the preview window.
  final Set<({int trackId, int note})> _pendingChordNotes = {};

  /// Start sustained audition - note plays until stopAudition is called (FL Studio style)
  void startAudition(int midiNote, int velocity) {
    if (!auditionEnabled) return;

    // Stop any currently held note first
    stopAudition();

    final trackId = currentClip?.trackId;
    if (trackId != null && widget.audioEngine != null) {
      widget.audioEngine!.sendTrackMidiNoteOn(trackId, midiNote, velocity);
      currentlyHeldNote = midiNote;
    }
  }

  /// Stop the currently held audition note
  void stopAudition() {
    if (currentlyHeldNote != null) {
      final trackId = currentClip?.trackId;
      if (trackId != null && widget.audioEngine != null) {
        widget.audioEngine!.sendTrackMidiNoteOff(
          trackId,
          currentlyHeldNote!,
          UIConstants.midiNoteOffVelocity,
        );
      }
      currentlyHeldNote = null;
    }
  }

  /// Change the audition pitch while holding (for dragging notes up/down)
  void changeAuditionPitch(int newMidiNote, int velocity) {
    if (!auditionEnabled) return;
    if (newMidiNote == currentlyHeldNote) return; // Same note, no change needed

    final trackId = currentClip?.trackId;
    if (trackId != null && widget.audioEngine != null) {
      // Stop old note
      if (currentlyHeldNote != null) {
        widget.audioEngine!.sendTrackMidiNoteOff(
          trackId,
          currentlyHeldNote!,
          UIConstants.midiNoteOffVelocity,
        );
      }
      // Start new note
      widget.audioEngine!.sendTrackMidiNoteOn(trackId, newMidiNote, velocity);
      currentlyHeldNote = newMidiNote;
    }
  }

  /// Toggle note audition on/off
  void toggleAudition() {
    setState(() {
      auditionEnabled = !auditionEnabled;
    });
  }

  /// Preview/audition a chord (play all notes simultaneously)
  void previewChord(List<int> midiNotes) {
    if (!auditionEnabled) return;
    final trackId = currentClip?.trackId;
    // Capture the engine now: `widget` can't be touched after dispose, and
    // the delayed NoteOff below may fire after the editor has closed.
    final engine = widget.audioEngine;
    if (trackId == null || engine == null) return;

    // Play all notes in the chord
    for (final midiNote in midiNotes) {
      engine.sendTrackMidiNoteOn(trackId, midiNote, 100);
      _pendingChordNotes.add((trackId: trackId, note: midiNote));
    }
    // Stop notes after a short delay. Skip any note dispose() already
    // flushed via stopChordPreview() so it isn't double-released.
    Future.delayed(const Duration(milliseconds: 500), () {
      for (final midiNote in midiNotes) {
        if (_pendingChordNotes.remove((trackId: trackId, note: midiNote))) {
          engine.sendTrackMidiNoteOff(
            trackId,
            midiNote,
            UIConstants.midiNoteOffVelocity,
          );
        }
      }
    });
  }

  /// Release any chord-preview notes still sounding (called from dispose).
  void stopChordPreview() {
    final engine = widget.audioEngine;
    if (engine != null) {
      for (final held in _pendingChordNotes) {
        engine.sendTrackMidiNoteOff(
          held.trackId,
          held.note,
          UIConstants.midiNoteOffVelocity,
        );
      }
    }
    _pendingChordNotes.clear();
  }
}
