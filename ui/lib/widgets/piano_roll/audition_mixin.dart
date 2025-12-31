import 'package:flutter/material.dart';
import '../piano_roll.dart';
import 'piano_roll_state.dart';

/// Mixin containing audition (note preview) functionality for PianoRoll.
/// Handles playing notes when clicking/dragging in the piano roll.
mixin AuditionMixin on State<PianoRoll>, PianoRollStateMixin {
  // ============================================
  // AUDITION METHODS
  // ============================================

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
        widget.audioEngine!.sendTrackMidiNoteOff(trackId, currentlyHeldNote!, 64);
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
        widget.audioEngine!.sendTrackMidiNoteOff(trackId, currentlyHeldNote!, 64);
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
    if (trackId == null || widget.audioEngine == null) return;

    // Play all notes in the chord
    for (final midiNote in midiNotes) {
      widget.audioEngine!.sendTrackMidiNoteOn(trackId, midiNote, 100);
    }
    // Stop notes after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      for (final midiNote in midiNotes) {
        widget.audioEngine?.sendTrackMidiNoteOff(trackId, midiNote, 64);
      }
    });
  }
}
