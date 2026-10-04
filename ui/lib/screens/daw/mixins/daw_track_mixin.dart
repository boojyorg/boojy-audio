import 'package:flutter/material.dart';
import '../../../models/clip_data.dart';
import '../../../models/instrument_data.dart';
import '../../../models/midi_note_data.dart';
import '../../../models/track_data.dart';
import '../../../services/commands/clip_commands.dart';
import '../../../services/audio_clip_engine_sync.dart';
import '../../../services/bundled_content_service.dart';
import '../../../services/commands/track_commands.dart';
import '../../../services/vst3_editor_service.dart';
import '../../../utils/csv_field.dart';
import '../../../widgets/instrument_browser.dart';
import '../../daw_screen.dart';
import '../../daw_screen_io.dart';
import 'daw_screen_state.dart';
import 'daw_recording_mixin.dart';
import 'daw_ui_mixin.dart';
import '../../../widgets/shared/boojy_notice.dart';

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
      // Deselecting clears the selection but leaves the editor panel open at
      // its current height — it shows a "no track selected" empty state rather
      // than slamming shut (collapsing on every empty-space click was jarring).
      // Manual collapse via the panel chevron still works.
      setState(() {
        selectTrack(null);
      });
      midiPlaybackManager?.selectClip(null, null);
      return;
    }

    setState(() {
      selectTrack(trackId, isShiftHeld: isShiftHeld);
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
  // INSTRUMENT METHODS
  // ============================================

  /// Handle instrument selection for a track
  void onInstrumentSelected(int trackId, String instrumentId) {
    // Checked before the instrument changes: "is this the current plugin's
    // name?" must look at the old instrument.
    final rename = hasAutomaticName(trackId);

    // The Sampler is an engine-side instrument (tracked via isSamplerTrack),
    // not an InstrumentData, so it can't go through the synth path below —
    // that would silently leave the track a Synthesizer. Swap the existing
    // track to a sampler instead, mirroring the new-track path.
    if (instrumentId == 'sampler') {
      trackController.removeTrackInstrument(trackId);
      audioEngine?.createSamplerForTrack(trackId);
      trackController.selectTrack(trackId);
      uiLayout.isEditorPanelVisible = true;
      if (rename) audioEngine?.setTrackName(trackId, 'Sampler');
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
    if (rename) audioEngine?.setTrackName(trackId, 'Synthesizer');

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

  /// Undoable track deletion that snapshots and restores the track's content.
  ///
  /// Lives here (not in the mixer panel) because restoring clips needs the
  /// playback managers. The command owns the engine-side state (mixer, sends,
  /// built-in effects, redo id); these closures own the UI/manager state
  /// (MIDI + audio clips, timeline, selection). VST3 plugins and tweaked synth
  /// params aren't recovered — surfaced via the command's onNotice.
  Future<void> onDeleteTrackRequested(TrackData track) async {
    // Snapshot the track's content BEFORE the command deletes it.
    final midiSnapshot =
        midiPlaybackManager?.midiClips
            .where((c) => c.trackId == track.id)
            .toList() ??
        const <MidiClipData>[];
    final audioSnapshot =
        timelineKey.currentState?.getAudioClipsOnTrack(track.id) ??
        const <ClipData>[];
    // A VST3 *instrument* (e.g. Serum) lives in the track's InstrumentData
    // (trackController), NOT in vst3PluginManager — that's what the UI's
    // instrument slot reads. Capture its path so undo can route the reloaded
    // plugin back to setTrackInstrument; everything else is a VST3 effect.
    final deletedInstrument = trackController.getTrackInstrument(track.id);
    final instrumentPluginPath = (deletedInstrument?.type == 'vst3')
        ? deletedInstrument?.pluginPath
        : null;
    final command = DeleteTrackCommand(
      trackId: track.id,
      trackName: track.name,
      trackType: track.type,
      volumeDb: track.volumeDb,
      pan: track.pan,
      mute: track.mute,
      solo: track.solo,
      armed: track.armed,
      onVst3Restored: (newTrackId, restored) {
        // The command reloaded these plugins into the engine. A reloaded plugin
        // whose path matches the deleted track's VST3 instrument goes back as
        // the track's instrument (trackController); the rest are VST3 effects
        // and re-register with the plugin manager (editor + count chip).
        for (final r in restored) {
          if (instrumentPluginPath != null && r.path == instrumentPluginPath) {
            trackController.setTrackInstrument(
              newTrackId,
              InstrumentData.vst3Instrument(
                trackId: newTrackId,
                pluginPath: r.path,
                pluginName: r.name,
                effectId: r.effectId,
              ),
            );
          } else {
            vst3PluginManager?.registerRestoredPlugin(
              newTrackId,
              r.effectId,
              path: r.path,
              name: r.name,
            );
          }
        }
      },
      onCleanup: (tid) {
        // The engine drops a track's audio clips with the track, but the
        // timeline UI keeps them — prune them here so redo doesn't leave
        // ghosts. Then run the shared teardown (MIDI clips, plugin windows).
        final timeline = timelineKey.currentState;
        if (timeline != null) {
          for (final clip in timeline.getAudioClipsOnTrack(tid)) {
            timeline.removeClip(clip.clipId);
          }
        }
        onTrackDeleted(tid);
      },
      onRestoreUi: (newTrackId) {
        // MIDI clips: re-stamp onto the recreated track, re-add to the manager
        // and resync to the engine (mirrors DeleteMidiClipFromArrangementCommand).
        for (final clip in midiSnapshot) {
          final restored = clip.copyWith(trackId: newTrackId);
          midiPlaybackManager?.addRecordedClip(restored);
          midiClipController.updateClip(restored, playheadPosition);
        }
        // Audio clips: reload from disk onto the new track with their trim
        // and edits (restoreAudioClip, as DeleteAudioClipCommand.undo does).
        for (final clip in audioSnapshot) {
          final engine = audioEngine;
          if (engine == null) break;
          final restored = clip.copyWith(trackId: newTrackId);
          final newClipId = restoreAudioClip(engine, restored);
          if (newClipId >= 0) {
            timelineKey.currentState?.addClip(
              restored.copyWith(clipId: newClipId),
            );
          }
        }
        refreshTrackWidgets();
        onTrackSelected(newTrackId);
      },
      onNotice: Notices.problem,
    );

    await undoRedoManager.execute(command);
  }

  /// Take a track's audio and MIDI clips off the screen (and the MIDI ones
  /// out of the engine) before undo deletes the track that held them.
  void removeTrackClipsFromScreen(int trackId) {
    final timeline = timelineKey.currentState;
    if (timeline != null) {
      for (final clip in timeline.getAudioClipsOnTrack(trackId)) {
        timeline.removeClip(clip.clipId);
      }
    }
    midiPlaybackManager?.removeClipsForTrack(trackId);
  }

  /// Undoable Duplicate Track: the new track gets its own copy of every
  /// clip (new IDs), shown on the timeline. The engine used to copy the clips
  /// itself, under the originals' IDs, so they played but never appeared.
  Future<void> onDuplicateTrackRequested(TrackData track) async {
    final command = DuplicateTrackCommand(
      sourceTrackId: track.id,
      sourceTrackName: track.name,
      audioClips:
          timelineKey.currentState?.getAudioClipsOnTrack(track.id) ?? const [],
      midiClips:
          midiPlaybackManager?.midiClips
              .where((c) => c.trackId == track.id)
              .toList() ??
          const [],
      onCopied: (newTrackId, audioCopies, midiCopies) {
        trackController.onTrackDuplicated(track.id, newTrackId);
        automationController.onTrackDuplicated(track.id, newTrackId);
        syncVolumeAutomationToEngine(newTrackId);
        for (final clip in audioCopies) {
          timelineKey.currentState?.addClip(clip);
        }
        for (final clip in midiCopies) {
          midiPlaybackManager?.addRecordedClip(clip);
          midiClipController.updateClip(clip, playheadPosition);
        }
        refreshTrackWidgets();
      },
      onCleanup: (trackId) {
        final timeline = timelineKey.currentState;
        if (timeline != null) {
          for (final clip in timeline.getAudioClipsOnTrack(trackId)) {
            timeline.removeClip(clip.clipId);
          }
        }
        automationController.onTrackDeleted(trackId);
        onTrackDeleted(trackId);
      },
    );
    await undoRedoManager.execute(command);
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

  /// Create a default 1-bar empty MIDI clip for a new track, or bring back
  /// [reuse] (a redo: the same clip id, so later steps on it still find it).
  MidiClipData createDefaultMidiClip(int trackId, {MidiClipData? reuse}) {
    // 1 bar = 4 beats (MIDI clips store duration in beats, not seconds)
    const durationBeats = 4.0;

    final defaultClip =
        reuse?.copyWith(trackId: trackId) ??
        MidiClipData(
          clipId: generateUniqueClipId(), // ms timestamps collided
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
    return defaultClip;
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
      // synth path below. Dropping an instrument is deliberate, so open the
      // editor on it (selecting alone never does).
      onTrackSelected(trackId, autoSelectClip: true);
      uiLayout.isEditorPanelVisible = true;
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
      Notices.problem("Couldn't create the drum kit track");
      return;
    }

    final kitId = audioEngine!.createDrumKitForTrack(trackId);
    if (kitId < 0) {
      Notices.problem("Couldn't create the drum kit");
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
    // drop path. Creating a kit is deliberate, so open the editor on it.
    onTrackSelected(trackId, autoSelectClip: true);
    uiLayout.isEditorPanelVisible = true;
    if (!loadedAll) {
      Notices.problem(
        "Couldn't load the starter drum sounds. The kit's pads are empty.",
      );
    }
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
