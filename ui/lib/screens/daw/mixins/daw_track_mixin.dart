import 'package:flutter/material.dart';
import '../../../models/clip_data.dart';
import '../../../models/instrument_data.dart';
import '../../../models/midi_note_data.dart';
import '../../../services/commands/track_commands.dart';
import '../../../widgets/instrument_browser.dart';
import '../../daw_screen.dart';
import 'daw_screen_state.dart';
import 'daw_recording_mixin.dart';
import 'daw_ui_mixin.dart';

/// Mixin containing track-related methods for DAWScreen.
/// Handles track selection, creation, deletion, duplication, and instrument assignment.
mixin DAWTrackMixin on State<DAWScreen>, DAWScreenStateMixin, DAWRecordingMixin, DAWUIMixin {
  // ============================================
  // TRACK SELECTION
  // ============================================

  /// Unified track selection method - handles both timeline and mixer clicks
  void onTrackSelected(int? trackId, {bool isShiftHeld = false, bool autoSelectClip = false}) {
    if (trackId == null) {
      setState(() {
        selectTrack(null);
        uiLayout.isEditorPanelVisible = false;
      });
      return;
    }

    setState(() {
      selectTrack(trackId, isShiftHeld: isShiftHeld);
      uiLayout.isEditorPanelVisible = true;
    });

    // Try to find an existing clip for this track and select it
    // instead of clearing the clip selection (only for single selection)
    // When autoSelectClip is false (e.g., after instrument drop), don't auto-select clip
    if (!isShiftHeld && autoSelectClip) {
      final clipsForTrack = midiPlaybackManager?.midiClips
          .where((c) => c.trackId == trackId)
          .toList();

      if (clipsForTrack != null && clipsForTrack.isNotEmpty) {
        // Select the first clip for this track
        final clip = clipsForTrack.first;
        midiPlaybackManager?.selectClip(clip.clipId, clip);
      } else {
        // No clips for this track - clear selection
        midiPlaybackManager?.selectClip(null, null);
      }
    } else if (!isShiftHeld && !autoSelectClip) {
      // Clear clip selection when autoSelectClip is false
      midiPlaybackManager?.selectClip(null, null);
    }
  }

  /// Get the type of the currently selected track ("MIDI", "Audio", or "Master")
  String? getSelectedTrackType() {
    if (selectedTrackId == null || audioEngine == null) return null;
    final info = audioEngine!.getTrackInfo(selectedTrackId!);
    if (info.isEmpty) return null;
    final parts = info.split(',');
    if (parts.length >= 3) {
      // Track type is at index 2: "track_id,name,type,..."
      final type = parts[2].toLowerCase();
      if (type == 'midi') return 'MIDI';
      if (type == 'audio') return 'Audio';
      if (type == 'master') return 'Master';
      return type;
    }
    return null;
  }

  /// Get the name of the currently selected track
  String? getSelectedTrackName() {
    if (selectedTrackId == null || audioEngine == null) return null;
    final info = audioEngine!.getTrackInfo(selectedTrackId!);
    if (info.isEmpty) return null;
    final parts = info.split(',');
    if (parts.length >= 2) {
      // Track name is at index 1: "track_id,name,type,..."
      return parts[1];
    }
    return null;
  }

  // ============================================
  // AUDIO CLIP SELECTION
  // ============================================

  /// Handle audio clip selection from timeline
  void onAudioClipSelected(int? clipId, ClipData? clip) {
    setState(() {
      selectedAudioClip = clip;
      if (clip != null) {
        // Also select the track that contains this clip
        selectedTrackId = clip.trackId;
        uiLayout.isEditorPanelVisible = true;
        // Clear MIDI clip selection
        midiPlaybackManager?.selectClip(null, null);
      }
    });
  }

  /// Handle audio clip updates from Audio Editor
  void onAudioClipUpdated(ClipData clip) {
    setState(() {
      selectedAudioClip = clip;
    });

    // Update the clip in the timeline view so waveform reflects gain changes
    timelineKey.currentState?.updateClip(clip);

    // Auto-update arrangement loop region to follow content
    updateArrangementLoopToContent();
  }

  // ============================================
  // INSTRUMENT METHODS
  // ============================================

  /// Handle instrument selection for a track
  void onInstrumentSelected(int trackId, String instrumentId) {
    // Create default instrument data for the track
    final instrumentData = InstrumentData.defaultSynthesizer(trackId);
    trackController.setTrackInstrument(trackId, instrumentData);
    trackController.selectTrack(trackId);
    uiLayout.isEditorPanelVisible = true;

    // Auto-populate track name if not user-edited
    if (!trackController.isTrackNameUserEdited(trackId)) {
      audioEngine?.setTrackName(trackId, 'Synthesizer');
    }

    // Call audio engine to set instrument
    if (audioEngine != null) {
      audioEngine!.setTrackInstrument(trackId, instrumentId);
    }
  }

  /// Handle instrument dropped on existing track
  void onInstrumentDropped(int trackId, Instrument instrument) {
    // Reuse the same logic as onInstrumentSelected
    onInstrumentSelected(trackId, instrument.id);
  }

  // ============================================
  // TRACK LIFECYCLE
  // ============================================

  /// Handle track deletion
  void onTrackDeleted(int trackId) {
    // Remove all MIDI clips for this track via manager
    midiPlaybackManager?.removeClipsForTrack(trackId);

    // Remove track state from controller
    trackController.onTrackDeleted(trackId);

    // Refresh timeline immediately
    refreshTrackWidgets();
  }

  /// Handle track duplication
  void onTrackDuplicated(int sourceTrackId, int newTrackId) {
    // Copy track state via controller
    trackController.onTrackDuplicated(sourceTrackId, newTrackId);
  }

  /// Called when a track is created from the mixer panel - refresh timeline immediately
  void onTrackCreatedFromMixer(int trackId, String trackType) {
    onTrackSelected(trackId);
    refreshTrackWidgets();
  }

  /// Called when tracks are reordered via drag-and-drop in the mixer panel
  void onTrackReordered(int oldIndex, int newIndex) {
    // Update shared track order in TrackController
    trackController.reorderTrack(oldIndex, newIndex);
    // Refresh timeline to match new track order
    refreshTrackWidgets();
  }

  // ============================================
  // CLIP CREATION
  // ============================================

  /// Create a default 1-bar empty MIDI clip for a new track
  void createDefaultMidiClip(int trackId) {
    // 1 bar = 4 beats (MIDI clips store duration in beats, not seconds)
    const durationBeats = 4.0;

    final defaultClip = MidiClipData(
      clipId: DateTime.now().millisecondsSinceEpoch,
      trackId: trackId,
      startTime: 0.0, // Start at beat 0
      duration: durationBeats,
      name: generateClipName(trackId),
      notes: [],
    );

    midiPlaybackManager?.addRecordedClip(defaultClip);
  }

  // ============================================
  // INSTRUMENT DROP ON EMPTY
  // ============================================

  /// Handle instrument dropped on empty area - creates new track
  Future<void> onInstrumentDroppedOnEmpty(Instrument instrument) async {
    if (audioEngine == null) return;

    // Handle Sampler instrument separately
    if (instrument.id == 'sampler') {
      // Create empty sampler track (no sample loaded yet)
      final trackId = audioEngine!.createTrack('sampler', 'Sampler');
      if (trackId < 0) return;

      // Initialize sampler for the track
      audioEngine!.createSamplerForTrack(trackId);

      refreshTrackWidgets();
      selectTrack(trackId);
      return;
    }

    // Create a new MIDI track for Synthesizer (and other instruments)
    final command = CreateTrackCommand(
      trackType: 'midi',
      trackName: 'MIDI',
    );

    await undoRedoManager.execute(command);

    final trackId = command.createdTrackId;
    if (trackId == null || trackId < 0) {
      return;
    }

    // Create default 4-bar empty clip for the new track
    createDefaultMidiClip(trackId);

    // Assign the instrument to the new track
    onInstrumentSelected(trackId, instrument.id);

    // Select the newly created track but NOT the clip (so Instrument tab shows)
    onTrackSelected(trackId, autoSelectClip: false);

    // Immediately refresh track widgets so the new track appears instantly
    refreshTrackWidgets();

    // Disarm other MIDI tracks (exclusive arm for new track)
    disarmOtherMidiTracks(trackId);
  }

  // ============================================
  // HELPER METHODS
  // ============================================

  /// Check if a track is a MIDI track
  bool isMidiTrack(int trackId) {
    final info = audioEngine?.getTrackInfo(trackId) ?? '';
    if (info.isEmpty) return false;
    final parts = info.split(',');
    if (parts.length >= 3) {
      return parts[2].toLowerCase() == 'midi';
    }
    return false;
  }

  /// Check if a track is an empty audio track (no clips)
  bool isEmptyAudioTrack(int trackId) {
    final info = audioEngine?.getTrackInfo(trackId) ?? '';
    if (info.isEmpty) return false;
    final parts = info.split(',');
    if (parts.length >= 3 && parts[2].toLowerCase() == 'audio') {
      // Check if track has any clips
      final clips = timelineKey.currentState?.getAudioClipsOnTrack(trackId);
      return clips == null || clips.isEmpty;
    }
    return false;
  }
}
