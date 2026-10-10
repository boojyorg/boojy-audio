import 'package:flutter/material.dart';
import '../audio_editor.dart';
import '../audio_editor_state.dart';

/// Mixin for audio clip parameter operations; the DAW makes each an undo
/// step.
mixin ParameterOperationsMixin on State<AudioEditor>, AudioEditorStateMixin {
  // ============================================
  // EDITS AND UNDO
  // ============================================

  /// True while a control is being dragged: each step updates the editor and
  /// timeline, and the engine and undo history get the result once, on
  /// release (BPM and pitch changes re-render the clip's audio).
  bool liveDragging = false;

  void beginLiveDrag() => liveDragging = true;

  void endLiveDrag(String actionDescription) {
    if (!liveDragging) return;
    liveDragging = false;
    widget.onEditFinished?.call(actionDescription);
  }

  /// Finish one edit: tell the timeline, then (unless mid-drag) the DAW,
  /// which sends the edit to the engine and records it as an undo step.
  void finishEdit(String actionDescription) {
    notifyClipUpdated();
    if (liveDragging) return;
    widget.onEditFinished?.call(actionDescription);
  }

  // ============================================
  // NOTIFICATION
  // ============================================

  /// Notify parent that clip was updated.
  void notifyClipUpdated() {
    if (currentClip == null) return;

    final updatedClip = currentClip!.copyWith(
      editData: editData,
      canRepeat: editData.loopEnabled,
      loopLength: editData.loopLengthSeconds(widget.projectTempo),
    );
    widget.onClipUpdated?.call(updatedClip);
  }

  // ============================================
  // TRANSPOSE OPERATIONS
  // ============================================

  /// Set transpose amount in semitones (-48 to +48).
  void setTranspose(int semitones) {
    setState(() {
      editData = editData.copyWith(
        transposeSemitones: semitones.clamp(-48, 48),
      );
    });
    finishEdit('Set transpose to $semitones semitones');
  }

  /// Set fine pitch adjustment in cents (-50 to +50).
  void setFineCents(int cents) {
    setState(() {
      editData = editData.copyWith(fineCents: cents.clamp(-50, 50));
    });
    finishEdit('Set fine tune to $cents cents');
  }

  // ============================================
  // GAIN OPERATIONS
  // ============================================

  /// Set gain in decibels.
  void setGain(double db) {
    setState(() {
      editData = editData.copyWith(gainDb: db.clamp(-70.0, 24.0));
    });
    finishEdit('Set gain to ${db.toStringAsFixed(1)} dB');
  }

  // ============================================
  // PROCESSING OPERATIONS
  // ============================================

  /// Toggle reverse playback.
  void toggleReverse() {
    final newValue = !editData.reversed;
    setState(() {
      editData = editData.copyWith(reversed: newValue);
    });
    finishEdit(newValue ? 'Enable reverse' : 'Disable reverse');
  }

  /// Set normalize target level (null to disable).
  void setNormalize(double? targetDb) {
    setState(() {
      if (targetDb == null) {
        editData = editData.copyWith(clearNormalize: true);
      } else {
        editData = editData.copyWith(
          normalizeTargetDb: targetDb.clamp(-12.0, 0.0),
        );
      }
    });
    finishEdit(
      targetDb != null
          ? 'Normalize to ${targetDb.toStringAsFixed(0)} dB'
          : 'Disable normalization',
    );
  }

  // ============================================
  // TEMPO OPERATIONS
  // ============================================

  /// Set BPM.
  void setBpm(double bpm) {
    setState(() {
      editData = editData.copyWith(bpm: bpm.clamp(20.0, 999.0));
    });
    finishEdit('Set BPM to ${bpm.toStringAsFixed(1)}');
  }

  /// Toggle tempo sync.
  void toggleSync() {
    final newValue = !editData.syncEnabled;
    setState(() {
      editData = editData.withWarp(
        on: newValue,
        projectBpm: widget.projectTempo,
      );
      loopStartBeats = editData.loopStartBeats;
      loopEndBeats = editData.loopEndBeats;
    });
    finishEdit(newValue ? 'Enable tempo sync' : 'Disable tempo sync');
  }
}
