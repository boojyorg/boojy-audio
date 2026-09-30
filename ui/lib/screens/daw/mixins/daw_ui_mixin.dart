import 'package:flutter/material.dart';
import '../../../widgets/keyboard_shortcuts_overlay.dart';
import '../../../widgets/app_settings_dialog.dart';
import '../../daw_screen.dart';
import 'daw_screen_state.dart';
import 'daw_playback_mixin.dart';
import 'daw_recording_mixin.dart';

/// Mixin containing UI-related methods for DAWScreen.
/// Handles panel toggles, keyboard shortcuts, and general UI operations.
mixin DAWUIMixin
    on
        State<DAWScreen>,
        DAWScreenStateMixin,
        DAWPlaybackMixin,
        DAWRecordingMixin {
  // ============================================
  // PANEL TOGGLE METHODS
  // ============================================

  /// Toggle library panel visibility
  void toggleLibraryPanel() {
    final windowWidth = MediaQuery.of(context).size.width;

    // If trying to expand library, check if there's room
    if (uiLayout.isLibraryPanelCollapsed) {
      if (!uiLayout.canShowLibrary(windowWidth)) {
        return; // Not enough room - do nothing
      }
    }

    setState(() {
      uiLayout.isLibraryPanelCollapsed = !uiLayout.isLibraryPanelCollapsed;
      userSettings.libraryCollapsed = uiLayout.isLibraryPanelCollapsed;
    });
  }

  /// Toggle mixer panel visibility
  void toggleMixer() {
    final windowWidth = MediaQuery.of(context).size.width;

    // If trying to show mixer, check if there's room
    if (!uiLayout.isMixerVisible) {
      if (!uiLayout.canShowMixer(windowWidth)) {
        return; // Not enough room - do nothing
      }
    }

    setState(() {
      uiLayout.isMixerVisible = !uiLayout.isMixerVisible;
      userSettings.mixerVisible = uiLayout.isMixerVisible;
    });
  }

  /// Toggle editor panel visibility
  void toggleEditor() {
    setState(() {
      uiLayout.isEditorPanelVisible = !uiLayout.isEditorPanelVisible;
      userSettings.editorVisible = uiLayout.isEditorPanelVisible;
    });
  }

  /// Reset panel layout to defaults
  void resetPanelLayout() {
    setState(() {
      // Reset to default panel sizes and visibility
      uiLayout.resetLayout();

      // Save reset states
      userSettings.libraryCollapsed = false;
      userSettings.mixerVisible = true;
      userSettings.editorVisible = true;
    });
  }

  // ============================================
  // KEYBOARD SHORTCUT METHODS
  // ============================================

  /// Show keyboard shortcuts overlay
  void showKeyboardShortcuts() {
    KeyboardShortcutsOverlay.show(context);
  }

  // ============================================
  // APP SETTINGS
  // ============================================

  /// Open app-wide settings dialog (accessed via logo click)
  Future<void> appSettings() async {
    // Wait for audio engine if not yet initialized (up to 2 seconds)
    if (audioEngine == null) {
      for (int i = 0; i < 20 && audioEngine == null && mounted; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    if (!mounted) return;

    await AppSettingsDialog.show(
      context,
      userSettings,
      audioEngine: audioEngine,
    );
  }

  // ============================================
  // LOOP REGION METHODS
  // ============================================

  /// Auto-update arrangement loop region to follow the longest clip.
  /// Only active when loopAutoFollow is true (disabled when user manually drags loop).
  void updateArrangementLoopToContent() {
    if (!uiLayout.loopAutoFollow) return;

    double longestEnd = 4.0; // Minimum 1 bar (4 beats)

    // Check all MIDI clips
    final midiClips = midiPlaybackManager?.midiClips ?? [];
    for (final clip in midiClips) {
      final clipEnd = clip.startTime + clip.duration;
      if (clipEnd > longestEnd) longestEnd = clipEnd;
    }

    // Check all audio clips (stored in timeline state)
    final audioClips = timelineKey.currentState?.clips ?? [];
    for (final clip in audioClips) {
      // Audio clips use seconds, convert to beats
      final beatsPerSecond = tempo / 60.0;
      final clipEndBeats = (clip.startTime + clip.duration) * beatsPerSecond;
      if (clipEndBeats > longestEnd) longestEnd = clipEndBeats;
    }

    // Round to next bar (4 beats)
    final newLoopEnd = (longestEnd / 4).ceil() * 4.0;

    // Only update if changed (avoids unnecessary rebuilds)
    if (newLoopEnd != uiLayout.loopEndBeats) {
      uiLayout.setLoopRegion(uiLayout.loopStartBeats, newLoopEnd);
    }
  }
}
