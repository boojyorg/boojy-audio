import 'package:flutter/material.dart';
import '../../../models/clip_data.dart';
import '../../../models/instrument_data.dart';
import '../../../models/midi_note_data.dart';
import '../../../services/bundled_content_service.dart';
import '../../../services/commands/track_commands.dart';
import '../../../services/vst3_editor_service.dart';
import '../../../utils/csv_field.dart';
import '../../../widgets/instrument_browser.dart';
import '../../daw_screen.dart';
import '../../daw_screen_io.dart'
    if (dart.library.js_interop) '../../daw_screen_io_web.dart';
import 'daw_screen_state.dart';
import 'daw_recording_mixin.dart';
import 'daw_ui_mixin.dart';

/// Mixin containing track-related methods for DAWScreen.
/// Handles track selection, creation, deletion, duplication, and instrument assignment.
mixin DAWTrackMixin
    on State<DAWScreen>, DAWScreenStateMixin, DAWRecordingMixin, DAWUIMixin {
  // ============================================
  // TRACK SELECTION
  // ============================================

  /// Unified track selection method - handles both timeline and mixer clicks
  void onTrackSelected(
    int? trackId, {
    bool isShiftHeld = false,
    bool autoSelectClip = false,
  }) {
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

    // Hide floating windows for other tracks, show for selected track
    _updateFloatingWindowVisibility(trackId);

    // Try to find an existing clip for this track and select it
    // instead of clearing the clip selection (only for single selection)
    // When autoSelectClip is false (e.g., after instrument drop), don't auto-select clip
    if (!isShiftHeld && autoSelectClip) {
      final clipsForTrack = midiPlaybackManager?.midiClips
          .where((c) => c.trackId == trackId)
          .toList();

      if (clipsForTrack != null && clipsForTrack.isNotEmpty) {
        // Keep an existing selection on this track (e.g. the clip a create
        // command just selected); otherwise select the first clip.
        final alreadySelected = clipsForTrack.any(
          (c) => c.clipId == midiPlaybackManager?.selectedClipId,
        );
        if (!alreadySelected) {
          final clip = clipsForTrack.first;
          midiPlaybackManager?.selectClip(clip.clipId, clip);
        }
      } else {
        // No clips for this track - clear selection
        midiPlaybackManager?.selectClip(null, null);
      }
    } else if (!isShiftHeld && !autoSelectClip) {
      // Clear clip selection when autoSelectClip is false
      midiPlaybackManager?.selectClip(null, null);
    }
  }

  /// Hide floating windows for all tracks except the selected one,
  /// and show the selected track's floating windows.
  void _updateFloatingWindowVisibility(int selectedTrackId) {
    final selectedEffectIds =
        vst3PluginManager?.getTrackEffectIds(selectedTrackId) ?? [];
    for (final effectId in floatedPluginEffectIds) {
      if (selectedEffectIds.contains(effectId)) {
        VST3EditorService.showFloatingWindow(effectId);
      } else {
        VST3EditorService.hideFloatingWindow(effectId);
      }
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
      // Track name is at index 1: "track_id,name,type,..." —
      // percent-encoded by the engine (C34).
      return decodeCsvField(parts[1]);
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
    // The Sampler is an engine-side instrument (tracked via isSamplerTrack),
    // not an InstrumentData, so it can't go through the synth path below —
    // that would silently leave the track a Synthesizer. Swap the existing
    // track to a sampler instead, mirroring the new-track path.
    if (instrumentId == 'sampler') {
      trackController.removeTrackInstrument(trackId);
      audioEngine?.createSamplerForTrack(trackId);
      trackController.selectTrack(trackId);
      uiLayout.isEditorPanelVisible = true;
      if (!trackController.isTrackNameUserEdited(trackId)) {
        audioEngine?.setTrackName(trackId, 'Sampler');
      }
      return;
    }

    // A Drum Kit is a whole multi-pad track, not an in-place instrument swap —
    // always spin up a fresh drum-kit track rather than overwriting this one.
    if (instrumentId == 'drum_kit') {
      createDrumKitTrack();
      return;
    }

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
    // Close any floating plugin windows for this track
    final effectIds = vst3PluginManager?.getTrackEffectIds(trackId) ?? [];
    for (final id in effectIds) {
      if (floatedPluginEffectIds.contains(id)) {
        VST3EditorService.closeFloatingWindow(effectId: id);
        floatedPluginEffectIds.remove(id);
      }
    }

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

  // Mixer-created-track handling lives in daw_screen.dart's private
  // _onTrackCreatedFromMixer (the live copy the callback actually binds —
  // see the mixin-trap note in .claude/rules/flutter-ui.md); the dead mixin
  // duplicate was deleted when exclusive arm landed there.

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
    // Register the clip with the engine immediately. addRecordedClip is
    // Dart-side only; without this the clip is unknown to the engine until
    // the first piano-roll edit, so a fresh track plays silence (bug-hunt #1).
    midiPlaybackManager?.rescheduleClip(defaultClip, tempo);
  }

  // ============================================
  // INSTRUMENT DROP ON EMPTY
  // ============================================

  /// Handle instrument dropped on empty area - creates new track
  Future<void> onInstrumentDroppedOnEmpty(Instrument instrument) async {
    if (audioEngine == null) return;

    // Handle Sampler instrument — creates MIDI track with sampler instrument
    if (instrument.id == 'sampler') {
      final trackId = audioEngine!.createTrack('midi', 'Sampler');
      if (trackId < 0) return;

      audioEngine!.createSamplerForTrack(trackId);
      createDefaultMidiClip(trackId);

      refreshTrackWidgets();
      // autoSelectClip so the new 1-bar clip shows selected, matching the
      // synth path below (also opens the editor panel).
      onTrackSelected(trackId, autoSelectClip: true);
      return;
    }

    // Handle Drum Kit instrument — multi-pad one-shot sampler on a MIDI track
    if (instrument.id == 'drum_kit') {
      createDrumKitTrack();
      return;
    }

    // Create a new MIDI track for Synthesizer (and other instruments)
    final command = CreateTrackCommand(trackType: 'midi', trackName: 'MIDI 1');

    await undoRedoManager.execute(command);

    final trackId = command.createdTrackId;
    if (trackId == null || trackId < 0) {
      return;
    }

    // Assign the instrument to the new track (before clip so name resolves)
    onInstrumentSelected(trackId, instrument.id);

    // Create default 1-bar empty clip for the new track
    createDefaultMidiClip(trackId);

    // Select track and highlight the clip (editor stays on Instrument tab)
    onTrackSelected(trackId, autoSelectClip: true);

    // Immediately refresh track widgets so the new track appears instantly
    refreshTrackWidgets();

    // Disarm other MIDI tracks (exclusive arm for new track)
    disarmOtherTracks(trackId);
  }

  /// Create a new Drum Kit track seeded with standard empty pads.
  ///
  /// Pads are pinned to General-MIDI percussion notes and pre-filled with the
  /// bundled starter kit (copied out of the asset bundle on first use), so a
  /// fresh Drum Kit makes sound with zero setup — the one-click first beat.
  Future<void> createDrumKitTrack() async {
    if (audioEngine == null) return;

    final trackId = audioEngine!.createTrack('midi', 'Drum Kit');
    if (trackId < 0) {
      showSnackBar('Failed to create drum kit track');
      return;
    }

    final kitId = audioEngine!.createDrumKitForTrack(trackId);
    if (kitId < 0) {
      showSnackBar('Failed to create drum kit');
      return;
    }

    // The engine loads samples by filesystem path, so make sure the bundled
    // kit is installed on disk (no-op after the first call). On failure the
    // kit still appears, just with empty pads.
    final drumsRoot = await BundledContentService.ensureInstalled();
    var loadedAll = drumsRoot != null;
    for (final (note, sample) in BundledContentService.starterKitPads) {
      final padIndex = audioEngine!.addDrumPad(trackId, note);
      if (drumsRoot != null && padIndex >= 0) {
        final samplePath =
            '$drumsRoot$pathSeparator'
            '${sample.split('/').join(pathSeparator)}';
        loadedAll &= audioEngine!.loadDrumPadSample(
          trackId,
          padIndex,
          samplePath,
        );
      }
    }

    createDefaultMidiClip(trackId);
    refreshTrackWidgets();
    // autoSelectClip so the new 1-bar clip shows selected, matching the synth
    // drop path (also opens the editor panel on the new kit).
    onTrackSelected(trackId, autoSelectClip: true);
    showSnackBar(
      loadedAll
          ? 'Created drum kit'
          : 'Created drum kit (starter sounds unavailable)',
    );
  }

  // ============================================
  // HELPER METHODS
  // ============================================

  /// Show snackbar message
  void showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

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
