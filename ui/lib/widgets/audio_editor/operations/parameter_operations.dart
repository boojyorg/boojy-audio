import 'package:flutter/material.dart';
import '../../../models/clip_data.dart';
import '../../../models/audio_clip_edit_data.dart';
import '../../../services/commands/audio_engine_interface.dart';
import '../../../services/commands/command.dart';
import '../audio_editor.dart';
import '../audio_editor_state.dart';

/// Mixin for audio clip parameter operations with undo/redo support.
mixin ParameterOperationsMixin on State<AudioEditor>, AudioEditorStateMixin {
  // ============================================
  // UNDO/REDO SUPPORT
  // ============================================

  /// Save current state before making changes.
  void saveToHistory() {
    snapshotBeforeAction = editData;
  }

  /// Commit changes to history after making changes.
  void commitToHistory(String actionDescription) {
    if (snapshotBeforeAction == null || currentClip == null) return;

    final command = AudioClipEditCommand(
      beforeState: snapshotBeforeAction!,
      afterState: editData,
      clipData: currentClip!,
      actionDescription: actionDescription,
      onApplyState: applyEditState,
    );

    undoRedoManager.execute(command);
    snapshotBeforeAction = null;
  }

  /// Apply edit state (used by undo/redo).
  void applyEditState(AudioClipEditData newEditData, ClipData clipData) {
    setState(() {
      editData = newEditData;
      currentClip = clipData.copyWith(editData: newEditData);

      // Sync local state from edit data
      loopEnabled = newEditData.loopEnabled;
      loopStartBeats = newEditData.loopStartBeats;
      loopEndBeats = newEditData.loopEndBeats;
      beatsPerBar = newEditData.beatsPerBar;
      beatUnit = newEditData.beatUnit;
    });
    notifyClipUpdated();
  }

  // ============================================
  // NOTIFICATION
  // ============================================

  /// Notify parent that clip was updated.
  void notifyClipUpdated() {
    if (currentClip == null) return;
    final updatedClip = currentClip!.copyWith(editData: editData);
    widget.onClipUpdated?.call(updatedClip);
  }

  /// Send parameters to audio engine for real-time processing.
  void sendToAudioEngine() {
    if (currentClip == null || widget.audioEngine == null) return;

    final clip = currentClip!;
    final engine = widget.audioEngine!;

    // Send clip gain to audio engine
    engine.setAudioClipGain(clip.trackId, clip.clipId, editData.gainDb);

    // Send warp settings to audio engine
    engine.setAudioClipWarp(
      clip.trackId,
      clip.clipId,
      editData.syncEnabled,
      editData.stretchFactor,
      editData.warpMode.index,
    );

    // Send transpose/pitch shift to audio engine
    engine.setAudioClipTranspose(
      clip.trackId,
      clip.clipId,
      editData.transposeSemitones,
      editData.fineCents,
    );

    // TODO: Future FFI calls for additional parameters:
    // - setAudioClipReverse(trackId, clipId, reversed)
    // - setAudioClipNormalize(trackId, clipId, targetDb)
  }

  // ============================================
  // TRANSPOSE OPERATIONS
  // ============================================

  /// Set transpose amount in semitones (-48 to +48).
  void setTranspose(int semitones) {
    saveToHistory();
    setState(() {
      editData = editData.copyWith(
        transposeSemitones: semitones.clamp(-48, 48),
      );
    });
    notifyClipUpdated();
    sendToAudioEngine();
    commitToHistory('Set transpose to $semitones semitones');
  }

  /// Set fine pitch adjustment in cents (-50 to +50).
  void setFineCents(int cents) {
    saveToHistory();
    setState(() {
      editData = editData.copyWith(
        fineCents: cents.clamp(-50, 50),
      );
    });
    notifyClipUpdated();
    sendToAudioEngine();
    commitToHistory('Set fine tune to $cents cents');
  }

  // ============================================
  // GAIN OPERATIONS
  // ============================================

  /// Set gain in decibels.
  void setGain(double db) {
    saveToHistory();
    setState(() {
      editData = editData.copyWith(
        gainDb: db.clamp(-70.0, 24.0),
      );
    });
    notifyClipUpdated();
    sendToAudioEngine();
    commitToHistory('Set gain to ${db.toStringAsFixed(1)} dB');
  }

  // ============================================
  // PROCESSING OPERATIONS
  // ============================================

  /// Toggle reverse playback.
  void toggleReverse() {
    saveToHistory();
    final newValue = !editData.reversed;
    setState(() {
      editData = editData.copyWith(reversed: newValue);
    });
    notifyClipUpdated();
    sendToAudioEngine();
    commitToHistory(newValue ? 'Enable reverse' : 'Disable reverse');
  }

  /// Set normalize target level (null to disable).
  void setNormalize(double? targetDb) {
    saveToHistory();
    setState(() {
      if (targetDb == null) {
        editData = editData.copyWith(clearNormalize: true);
      } else {
        editData = editData.copyWith(
          normalizeTargetDb: targetDb.clamp(-12.0, 0.0),
        );
      }
    });
    notifyClipUpdated();
    sendToAudioEngine();
    if (targetDb != null) {
      commitToHistory('Normalize to ${targetDb.toStringAsFixed(0)} dB');
    } else {
      commitToHistory('Disable normalization');
    }
  }

  // ============================================
  // TEMPO OPERATIONS
  // ============================================

  /// Set BPM.
  void setBpm(double bpm) {
    saveToHistory();
    setState(() {
      editData = editData.copyWith(bpm: bpm.clamp(20.0, 999.0));
    });
    notifyClipUpdated();
    sendToAudioEngine();
    commitToHistory('Set BPM to ${bpm.toStringAsFixed(1)}');
  }

  /// Toggle tempo sync.
  void toggleSync() {
    saveToHistory();
    final newValue = !editData.syncEnabled;
    setState(() {
      editData = editData.copyWith(syncEnabled: newValue);
    });
    notifyClipUpdated();
    sendToAudioEngine();
    commitToHistory(newValue ? 'Enable tempo sync' : 'Disable tempo sync');
  }

  /// Set stretch factor.
  void setStretch(double factor) {
    saveToHistory();
    setState(() {
      editData = editData.copyWith(stretchFactor: factor.clamp(0.25, 4.0));
    });
    notifyClipUpdated();
    sendToAudioEngine();
    commitToHistory('Set stretch to ${factor}x');
  }
}

/// Command for undo/redo of audio clip edit operations.
class AudioClipEditCommand extends Command {
  final AudioClipEditData beforeState;
  final AudioClipEditData afterState;
  final ClipData clipData;
  final String _actionDescription;
  final void Function(AudioClipEditData, ClipData) onApplyState;

  AudioClipEditCommand({
    required this.beforeState,
    required this.afterState,
    required this.clipData,
    required String actionDescription,
    required this.onApplyState,
  }) : _actionDescription = actionDescription;

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    onApplyState(afterState, clipData);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    onApplyState(beforeState, clipData);
  }

  @override
  String get description => _actionDescription;
}
