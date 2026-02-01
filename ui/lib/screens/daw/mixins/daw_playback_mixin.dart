import 'package:flutter/material.dart';
import '../../daw_screen.dart';
import 'daw_screen_state.dart';

/// Mixin containing playback-related methods for DAWScreen.
/// Handles play, pause, stop, loop playback operations.
mixin DAWPlaybackMixin on State<DAWScreen>, DAWScreenStateMixin {
  /// Start playback
  void play() {
    // Clear automation preview values so display shows actual playback values
    if (automationPreviewValues.isNotEmpty) {
      setState(() {
        automationPreviewValues.clear();
      });
    }
    playbackController.play(loadedClipId: loadedClipId);
  }

  /// Play with loop check - used by transport bar play button
  void playWithLoopCheck() {
    // Clear automation preview values so display shows actual playback values
    if (automationPreviewValues.isNotEmpty) {
      setState(() {
        automationPreviewValues.clear();
      });
    }
    if (uiLayout.loopPlaybackEnabled) {
      playLoopRegion();
    } else {
      play();
    }
  }

  /// Pause playback
  void pause() {
    playbackController.pause();
  }

  /// Stop playback completely
  void stopPlayback() {
    playbackController.stop();
    // Reset mixer meters when playback stops
    mixerKey.currentState?.resetMeters();
  }

  /// Context-aware play/pause toggle (Space bar)
  /// - When loop is enabled: plays the loop region (cycling)
  /// - Otherwise: plays full arrangement
  void togglePlayPause() {
    if (isPlaying) {
      pause();
    } else {
      playWithLoopCheck();
    }
  }

  /// Play the loop region, cycling forever until stopped
  void playLoopRegion() {
    // Get loop bounds from UI layout state
    final loopStart = uiLayout.loopStartBeats;
    final loopEnd = uiLayout.loopEndBeats;

    // Play with loop cycling enabled
    playbackController.playLoop(
      loadedClipId: loadedClipId,
      loopStartBeats: loopStart,
      loopEndBeats: loopEnd,
      tempo: tempo,
    );
  }
}
