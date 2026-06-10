import 'dart:io';
import 'package:flutter/material.dart';
import '../../../utils/logger.dart';
import '../../../models/clip_data.dart';
import '../../../models/midi_note_data.dart';
import '../../../services/commands/track_commands.dart';
// ignore: unused_import
import '../../../services/commands/clip_commands.dart';
import '../../../utils/clip_overlap_handler.dart';
import '../../../services/midi_file_service.dart';
import '../../daw_screen.dart';
import 'daw_screen_state.dart';
import 'daw_recording_mixin.dart';
import 'daw_ui_mixin.dart';
import 'daw_track_mixin.dart';
import 'daw_clip_mixin.dart';
import 'daw_vst3_mixin.dart';

/// Mixin containing library-related methods for DAWScreen.
/// Handles library item interactions, audio file drops, and sampler operations.
mixin DAWLibraryMixin
    on
        State<DAWScreen>,
        DAWScreenStateMixin,
        DAWRecordingMixin,
        DAWUIMixin,
        DAWTrackMixin,
        DAWClipMixin,
        DAWVst3Mixin {
  // ============================================
  // SAMPLER OPERATIONS
  // ============================================

  // TOMBSTONE: handleLibraryItemDoubleClick / handleVst3DoubleClick /
  // handleOpenInSampler do NOT live here. The live handlers are the private
  // `_handleLibraryItemDoubleClick` / `_handleVst3DoubleClick` /
  // `_handleOpenInSampler` in `daw_screen.dart` — both LibraryPanel instances
  // wire those. The mixin copies (and their orphaned helpers
  // findInstrumentByName / findInstrumentById / addAudioClipToTrack /
  // addBuiltInEffectToTrack) were dead duplicates that had already diverged
  // from the live versions, so they were deleted — fix bugs in the
  // daw_screen privates, don't re-add copies here (see the mixin-trap rule
  // in .claude/rules/flutter-ui.md).

  /// Create a new Sampler track and load a sample into it
  void createSamplerTrackWithSample(String filePath, String sampleName) {
    if (audioEngine == null) return;

    // Generate track name based on sample name
    final trackName = 'Sampler: ${truncateName(sampleName, 20)}';

    // Create MIDI track with sampler instrument (samplers live on regular
    // MIDI tracks — the instrument is engine-side, see isSamplerTrack)
    final trackId = audioEngine!.createTrack('midi', trackName);
    if (trackId < 0) {
      showSnackBar('Failed to create sampler track');
      return;
    }

    // Create sampler instrument for the track
    final samplerId = audioEngine!.createSamplerForTrack(trackId);
    if (samplerId < 0) {
      showSnackBar('Failed to create sampler instrument');
      return;
    }

    // Load the sample (root note C4 = 60)
    final success = audioEngine!.loadSampleForTrack(trackId, filePath, 60);
    if (!success) {
      showSnackBar('Failed to load sample');
      return;
    }

    // Give the track a default clip like every other instrument path —
    // without one, the piano roll shows "Click to create MIDI clip" and the
    // transport never triggers the sampler (bug-hunt #1 sibling).
    createDefaultMidiClip(trackId);

    // Refresh track list, select the new track and its clip (autoSelectClip
    // so the fresh 1-bar clip shows selected, matching the synth drop path)
    refreshTrackWidgets();
    onTrackSelected(trackId, autoSelectClip: true);

    showSnackBar('Created sampler with "${truncateName(sampleName, 30)}"');
  }

  /// Convert an Audio track to a Sampler track
  /// Takes the first audio clip on the track and uses it as the sample
  /// Creates MIDI notes at the position/duration of each audio clip
  void convertAudioTrackToSampler(int trackId) {
    if (audioEngine == null) return;

    // Get audio clips on this track
    final audioClips = timelineKey.currentState?.getAudioClipsOnTrack(trackId);
    if (audioClips == null || audioClips.isEmpty) {
      showSnackBar('No audio clips on track to convert');
      return;
    }

    // Get the first clip's file path (we'll use this as the sample)
    final firstClip = audioClips.first;
    final samplePath = firstClip.filePath;
    if (samplePath.isEmpty) {
      showSnackBar('Audio clip has no file path');
      return;
    }

    // Get track name for the new sampler track
    final trackName = getTrackName(trackId) ?? 'Sampler';
    final samplerTrackName = trackName.startsWith('Sampler:')
        ? trackName
        : 'Sampler: $trackName';

    // Create MIDI track with sampler instrument
    final samplerTrackId = audioEngine!.createTrack('midi', samplerTrackName);
    if (samplerTrackId < 0) {
      showSnackBar('Failed to create sampler track');
      return;
    }

    // Create sampler instrument for the track
    final samplerId = audioEngine!.createSamplerForTrack(samplerTrackId);
    if (samplerId < 0) {
      showSnackBar('Failed to create sampler instrument');
      return;
    }

    // Load the sample (root note C4 = 60)
    final success = audioEngine!.loadSampleForTrack(
      samplerTrackId,
      samplePath,
      60,
    );
    if (!success) {
      showSnackBar('Failed to load sample');
      return;
    }

    // Create MIDI clips for each audio clip position — each audio clip
    // becomes a MIDI note at the same position. Register the clips through
    // midiPlaybackManager (rescheduleClip creates the engine clip, adds the
    // note, and places it on the track): the previous direct-FFI loop left
    // the clips engine-only, so they were invisible to the timeline and
    // could never be selected or edited (bug-hunt #20).
    final beatsPerSecond = tempo / 60.0;
    var nextClipId = DateTime.now().millisecondsSinceEpoch;
    for (final clip in audioClips) {
      // ClipData times are seconds; MidiClipData stores beats.
      final startBeats = clip.startTime * beatsPerSecond;
      final durationBeats = clip.duration * beatsPerSecond;

      // Calculate MIDI note based on transpose (if any)
      // Default root note is 60 (C4), transpose shifts it
      final transpose = clip.editData?.transposeSemitones ?? 0;
      final midiNote = (60 + transpose).clamp(0, 127);

      final midiClip = MidiClipData(
        clipId: nextClipId++,
        trackId: samplerTrackId,
        startTime: startBeats,
        duration: durationBeats,
        loopLength: durationBeats,
        name: generateClipName(samplerTrackId),
        notes: [
          MidiNoteData(
            note: midiNote,
            velocity: 100,
            startTime: 0.0, // note starts at beginning of clip
            duration: durationBeats, // note duration = clip duration
          ),
        ],
      );
      midiPlaybackManager?.addRecordedClip(midiClip);
      midiPlaybackManager?.rescheduleClip(midiClip, tempo);
    }

    // Refresh tracks and select the new sampler track + its first clip
    refreshTrackWidgets();
    onTrackSelected(samplerTrackId, autoSelectClip: true);

    // Optionally delete the original audio track (ask user?)
    // For now, keep both tracks so user can compare

    showSnackBar('Converted to Sampler track');
  }

  // ============================================
  // AUDIO FILE DROP HANDLERS
  // ============================================

  /// Handle audio file dropped on empty area - creates new audio track
  Future<void> onAudioFileDroppedOnEmpty(String filePath) async {
    if (audioEngine == null) return;

    try {
      // 1. Copy sample to project folder if setting is enabled
      final finalPath = await prepareSamplePath(filePath);

      // 2. Create new audio track
      final command = CreateTrackCommand(
        trackType: 'audio',
        trackName: 'Audio',
      );

      await undoRedoManager.execute(command);

      final trackId = command.createdTrackId;
      if (trackId == null || trackId < 0) {
        return;
      }

      // 3. Load audio file to the newly created track
      final clipId = audioEngine!.loadAudioFileToTrack(finalPath, trackId);
      if (clipId < 0) {
        return;
      }

      // 4. Get clip info + a quick low-res waveform for immediate display; the
      // timeline sharpens it to full resolution a frame later.
      final duration = audioEngine!.getClipDuration(clipId);
      final peaks = audioEngine!.getWaveformPeaks(clipId, 1000);

      // 5. Add to timeline view's clip list
      timelineKey.currentState?.addClip(
        ClipData(
          clipId: clipId,
          trackId: trackId,
          filePath: finalPath, // Use the copied path
          startTime: 0.0,
          duration: duration,
          waveformPeaks: peaks,
        ),
      );

      // 6. Select the newly created clip (opens Audio Editor)
      timelineKey.currentState?.selectAudioClip(clipId);

      // 7. Upgrade to the full-resolution waveform once the clip is on screen
      timelineKey.currentState?.scheduleWaveformUpgrade(clipId);

      // 8. Refresh track widgets
      refreshTrackWidgets();
    } catch (e) {
      Log.e('Failed to add audio file to new track: $e');
    }
  }

  /// Handle audio file dropped on existing track (with undo support)
  Future<void> onAudioFileDroppedOnTrack(
    int trackId,
    String filePath,
    double startTimeBeats,
  ) async {
    Log.d(
      '[OVERLAP] onAudioFileDroppedOnTrack: track $trackId, file=${filePath.split("/").last}, startBeats=${startTimeBeats.toStringAsFixed(3)}',
    );
    if (audioEngine == null) return;

    // Defensive check: only allow audio file drops on audio tracks (not MIDI tracks)
    if (isMidiTrack(trackId)) return;

    try {
      // 1. Copy sample to project folder if setting is enabled
      final finalPath = await prepareSamplePath(filePath);

      // 2. Convert beats to seconds (audio clips use seconds)
      final startTimeSeconds = startTimeBeats * 60.0 / tempo;

      // 3. Extract filename for display
      final fileName = finalPath.split('/').last.split('\\').last;

      // 4. Use AddAudioClipCommand for undo support
      final command = AddAudioClipCommand(
        trackId: trackId,
        filePath: finalPath,
        startTime: startTimeSeconds,
        clipName: fileName,
        onClipAdded: (clipId, duration, peaks) {
          // Resolve overlaps before adding the new clip
          final result = ClipOverlapHandler.resolveAudioOverlaps(
            newStart: startTimeSeconds,
            newEnd: startTimeSeconds + duration,
            existingClips: List<ClipData>.from(
              timelineKey.currentState?.clips ?? [],
            ),
            trackId: trackId,
          );
          ClipOverlapHandler.applyAudioResult(
            result: result,
            engineRemoveClip: (tId, cId) =>
                audioEngine?.removeAudioClip(tId, cId),
            engineSetStartTime: (tId, cId, s) =>
                audioEngine?.setClipStartTime(tId, cId, s),
            engineSetOffset: (tId, cId, o) =>
                audioEngine?.setClipOffset(tId, cId, o),
            engineSetDuration: (tId, cId, d) =>
                audioEngine?.setClipDuration(tId, cId, d),
            engineDuplicateClip: (tId, cId, s) =>
                audioEngine?.duplicateAudioClip(tId, cId, s) ?? -1,
            uiRemoveClip: (cId) => timelineKey.currentState?.removeClip(cId),
            uiUpdateClip: (clip) => timelineKey.currentState?.updateClip(clip),
            uiAddClip: (clip) => timelineKey.currentState?.addClip(clip),
          );
          // Add the new clip to timeline
          timelineKey.currentState?.addClip(
            ClipData(
              clipId: clipId,
              trackId: trackId,
              filePath: finalPath,
              startTime: startTimeSeconds,
              duration: duration,
              waveformPeaks: peaks,
            ),
          );
          // Select the newly created clip (opens Audio Editor)
          timelineKey.currentState?.selectAudioClip(clipId);
          // Upgrade to the full-resolution waveform once the clip is on screen
          timelineKey.currentState?.scheduleWaveformUpgrade(clipId);
        },
        onClipRemoved: (clipId) {
          // Remove from timeline view (undo)
          timelineKey.currentState?.removeClip(clipId);
        },
      );

      await undoRedoManager.execute(command);

      // 5. Refresh track widgets
      refreshTrackWidgets();
    } catch (e) {
      Log.e('Failed to add audio file to track: $e');
    }
  }

  /// Create new track with clip (drag-to-create)
  Future<void> onCreateTrackWithClip(
    String trackType,
    double startBeats,
    double durationBeats,
  ) async {
    if (audioEngine == null) return;

    try {
      // Create new track
      final command = CreateTrackCommand(
        trackType: trackType,
        trackName: trackType == 'midi' ? 'MIDI' : 'Audio',
      );

      await undoRedoManager.execute(command);

      final trackId = command.createdTrackId;
      if (trackId == null || trackId < 0) {
        return;
      }

      // For MIDI tracks, create a clip with the specified position and
      // duration. Await it so the clip exists (and is selected by its command
      // callback) before the track selection below — selecting first cleared
      // the clip selection and raced the create command (flicker, #21).
      if (trackType == 'midi') {
        await createMidiClipWithParams(trackId, startBeats, durationBeats);
      }
      // For audio tracks, they start empty (user will drop audio files)

      // Select the newly created track (keeping its fresh clip selected)
      onTrackSelected(trackId, autoSelectClip: trackType == 'midi');

      // Refresh track widgets
      refreshTrackWidgets();

      // Disarm other MIDI tracks when creating new MIDI track (exclusive arm)
      if (trackType == 'midi') {
        disarmOtherMidiTracks(trackId);
      }
    } catch (e) {
      Log.e('Failed to create track with clip: $e');
    }
  }

  // ============================================
  // MIDI FILE DROP HANDLERS
  // ============================================

  /// Handle MIDI file dropped on empty area - creates new MIDI track
  Future<void> onMidiFileDroppedOnEmpty(String filePath) async {
    if (audioEngine == null) return;

    try {
      final bytes = await File(filePath).readAsBytes();
      final result = MidiFileService.decode(bytes);
      if (result.notes.isEmpty) return;

      // Create new MIDI track
      final command = CreateTrackCommand(trackType: 'midi', trackName: 'MIDI');
      await undoRedoManager.execute(command);

      final trackId = command.createdTrackId;
      if (trackId == null || trackId < 0) return;

      _importMidiNotesToTrack(trackId, filePath, 0.0, result);
    } catch (e) {
      Log.e('Failed to import MIDI file to new track: $e');
    }
  }

  /// Handle MIDI file dropped on existing track
  Future<void> onMidiFileDroppedOnTrack(
    int trackId,
    String filePath,
    double startTimeBeats,
  ) async {
    Log.d(
      '[OVERLAP] onMidiFileDroppedOnTrack: track $trackId, file=${filePath.split("/").last}, startBeats=${startTimeBeats.toStringAsFixed(3)}',
    );
    if (audioEngine == null) return;
    if (!isMidiTrack(trackId)) return;

    try {
      final bytes = await File(filePath).readAsBytes();
      final result = MidiFileService.decode(bytes);
      if (result.notes.isEmpty) return;

      _importMidiNotesToTrack(trackId, filePath, startTimeBeats, result);
    } catch (e) {
      Log.e('Failed to import MIDI file to track: $e');
    }
  }

  /// Import decoded MIDI notes as a clip on a track
  // ignore: unused_element
  void _importMidiNotesToTrack(
    int trackId,
    String filePath,
    double startTimeBeats,
    MidiFileDecodeResult result,
  ) {
    // Find the max note end to determine clip duration
    double maxEnd = 0;
    for (final note in result.notes) {
      final end = note.startTime + note.duration;
      if (end > maxEnd) maxEnd = end;
    }
    final durationBeats = maxEnd > 0 ? maxEnd : 4.0;

    final clipId = DateTime.now().microsecondsSinceEpoch;
    final clipName =
        result.trackName ?? filePath.split('/').last.split('.').first;

    final clipData = MidiClipData(
      clipId: clipId,
      trackId: trackId,
      startTime: startTimeBeats,
      duration: durationBeats,
      notes: result.notes,
      name: clipName,
    );

    // Resolve overlaps before adding the new clip
    final overlapResult = ClipOverlapHandler.resolveMidiOverlaps(
      newStart: startTimeBeats,
      newEnd: startTimeBeats + durationBeats,
      existingClips: List<MidiClipData>.from(
        midiPlaybackManager?.midiClips ?? [],
      ),
      trackId: trackId,
    );
    ClipOverlapHandler.applyMidiResult(
      result: overlapResult,
      deleteClip: (cId, tId) => midiClipController.deleteClip(cId, tId),
      updateClipInPlace: (clip) => midiPlaybackManager?.updateClipInPlace(clip),
      rescheduleClip: (clip, t) => midiPlaybackManager?.rescheduleClip(clip, t),
      addClip: (clip) => midiPlaybackManager?.addRecordedClip(clip),
      tempo: tempo,
    );

    midiPlaybackManager?.addRecordedClip(clipData);
    midiPlaybackManager?.rescheduleClip(clipData, tempo);

    refreshTrackWidgets();
  }

  // ============================================
  // HELPER METHODS
  // ============================================

  /// Copy audio file to project's Samples folder if setting is enabled
  Future<String> prepareSamplePath(String originalPath) async {
    // If setting is disabled or no project is open, use original path
    if (!userSettings.copySamplesToProject ||
        projectManager?.currentPath == null) {
      return originalPath;
    }

    try {
      final projectPath = projectManager!.currentPath!;
      final samplesDir = Directory('$projectPath/Samples');

      // Create Samples folder if it doesn't exist
      if (!await samplesDir.exists()) {
        await samplesDir.create(recursive: true);
      }

      // Get the file name from the original path
      final fileName = originalPath.split(Platform.pathSeparator).last;
      final destinationPath = '$projectPath/Samples/$fileName';

      // Check if file already exists in Samples folder
      final destinationFile = File(destinationPath);
      if (await destinationFile.exists()) {
        // File already exists, use it
        return destinationPath;
      }

      // Copy the file to Samples folder
      final sourceFile = File(originalPath);
      await sourceFile.copy(destinationPath);

      return destinationPath;
    } catch (e) {
      // Fall back to original path if copy fails
      return originalPath;
    }
  }

  // (addAudioClipToTrack / addBuiltInEffectToTrack / findInstrumentByName /
  // findInstrumentById lived here as dead duplicates of the daw_screen
  // privates — see the tombstone above.)

  /// Truncate a name to max length with ellipsis
  // ignore: unused_element
  String truncateName(String name, int maxLength) {
    if (name.length <= maxLength) return name;
    return '${name.substring(0, maxLength - 3)}...';
  }

  // showSnackBar lives in DAWTrackMixin (shared by the track-creation paths
  // there); this mixin is `on DAWTrackMixin`, so it resolves from here too.
}
