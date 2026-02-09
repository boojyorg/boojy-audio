import 'package:flutter/material.dart';
import '../../../controllers/controllers.dart';
import '../../../models/clip_data.dart';
import '../../../models/midi_note_data.dart';
import '../../../models/track_data.dart';
import '../../../services/commands/clip_commands.dart';
import '../../../services/commands/project_commands.dart';
import '../../../services/clip_naming_service.dart';
import '../../../services/live_recording_notifier.dart';
import '../../../utils/clip_overlap_handler.dart';
import '../../daw_screen.dart';
import 'daw_screen_state.dart';

/// Mixin containing recording-related methods for DAWScreen.
/// Handles record, metronome, count-in, tempo, virtual piano, and MIDI devices.
mixin DAWRecordingMixin on State<DAWScreen>, DAWScreenStateMixin {
  // ============================================
  // RECORDING METHODS
  // ============================================

  /// Toggle recording on/off (R key)
  void toggleRecording() {
    if (isRecording) {
      // During recording: Save and restart
      recordingController.restartRecording();
    } else if (isCountingIn || recordingController.isWaitingForPunchIn) {
      // During count-in or waiting for punch-in: Cancel and return to start
      stopRecordingAndReturn();
    } else {
      // Idle: Start new recording
      final isPlaying = playbackController.isPlaying;
      startRecording(isAlreadyPlaying: isPlaying);
    }
  }

  /// Start recording
  /// [isAlreadyPlaying]: If true, skips count-in and starts recording immediately
  void startRecording({bool isAlreadyPlaying = false}) {
    // Block preview playback during recording
    libraryPreviewService?.setRecordingState(true);

    // Listen for live recording updates (real-time MIDI note display)
    liveRecordingNotifier.addListener(_onLiveRecordingUpdate);

    // Set up callbacks
    recordingController.onRecordingComplete = handleRecordingComplete;
    recordingController.onRecordStartPositionChanged = playbackController.setRecordStartPosition;
    recordingController.onPunchComplete = _handlePunchComplete;

    // Read punch state from UI layout — punch region reuses loop boundaries
    final punchIn = uiLayout.punchInEnabled;
    final punchOut = uiLayout.punchOutEnabled;
    double punchInSeconds = 0.0;
    double punchOutSeconds = 0.0;
    if (punchIn || punchOut) {
      punchInSeconds = uiLayout.loopStartBeats * 60.0 / tempo;
      punchOutSeconds = uiLayout.loopEndBeats * 60.0 / tempo;
    }

    recordingController.startRecording(
      isAlreadyPlaying: isAlreadyPlaying,
      punchInEnabled: punchIn,
      punchOutEnabled: punchOut,
      punchInSeconds: punchInSeconds,
      punchOutSeconds: punchOutSeconds,
    );

    // Don't start playhead polling during count-in — the playhead should stay
    // frozen at the recording start position. Listen for the count-in → recording
    // transition and start polling then (with a display offset so the engine's
    // elapsed count-in time doesn't shift the visual playhead).
    recordingController.addListener(_onRecordingStateChanged);
  }

  /// Detect count-in → recording transition and start playhead polling
  void _onRecordingStateChanged() {
    // Start playhead polling when entering WaitingForPunchIn (transport is playing)
    if (recordingController.isWaitingForPunchIn) {
      recordingController.removeListener(_onRecordingStateChanged);
      playbackController.startPlayheadPolling(displayOffset: 0.0);
      return;
    }

    if (recordingController.isRecording && !recordingController.isCountingIn) {
      recordingController.removeListener(_onRecordingStateChanged);

      // Use actual count-in duration from recording controller (measured by engine)
      // This ensures correct offset for both normal recording (with count-in) and
      // Play→Record (no count-in, offset = 0)
      final countInDuration = recordingController.countInDurationSeconds;

      playbackController.startPlayheadPolling(displayOffset: countInDuration);
    }
  }

  /// Handle auto-punch-out completion — transport keeps playing
  void _handlePunchComplete(RecordingResult result) {
    // Capture live recording notes BEFORE cleanup
    final liveClip = liveRecordingNotifier.buildLiveClipData();
    final capturedNotes = liveClip?.notes ?? [];

    // Clean up listeners
    liveRecordingNotifier.removeListener(_onLiveRecordingUpdate);
    recordingController.removeListener(_onRecordingStateChanged);
    midiPlaybackManager?.setLiveRecordingClip(null);

    // Re-enable preview playback
    libraryPreviewService?.setRecordingState(false);

    // Process the recording (place clip on timeline) — transport keeps running
    handleRecordingComplete(result, capturedNotes: capturedNotes);

    // Playhead polling continues since transport is still running
  }

  /// Pause recording: Stop recording, stay at current position
  void pauseRecording() {
    if (!isRecording && !isCountingIn && !recordingController.isWaitingForPunchIn) return;

    // Stop recording and save clip
    final (result, capturedNotes) = _completeRecording();

    // Pause (stay at current position)
    playbackController.pause();

    handleRecordingComplete(result, capturedNotes: capturedNotes);
  }

  /// Stop recording: Stop recording, return to recordStartPosition
  void stopRecordingAndReturn() {
    if (!isRecording && !isCountingIn && !recordingController.isWaitingForPunchIn) return;

    // Stop recording and save clip
    final (result, capturedNotes) = _completeRecording();

    // Stop and return to recording start position
    playbackController.stop(isRecording: true);

    handleRecordingComplete(result, capturedNotes: capturedNotes);
  }

  /// Stop playback (not recording): Return to playStartPosition or bar 1 if idle
  void stopPlayback() {
    playbackController.stop(isRecording: false);
  }

  /// Internal: Complete recording and return results with captured notes
  (RecordingResult, List<MidiNoteData>) _completeRecording() {
    // Re-enable preview playback
    libraryPreviewService?.setRecordingState(false);

    // Capture live recording notes BEFORE stopping — stopRecording() clears
    // the live recording notifier, so we must snapshot the notes now.
    final liveClip = liveRecordingNotifier.buildLiveClipData();
    final capturedNotes = liveClip?.notes ?? [];

    // Stop listening for live recording updates and state changes
    liveRecordingNotifier.removeListener(_onLiveRecordingUpdate);
    recordingController.removeListener(_onRecordingStateChanged);
    midiPlaybackManager?.setLiveRecordingClip(null);

    // Clear the callback BEFORE calling stopRecording() to prevent double-call.
    // recordingController.stopRecording() fires onRecordingComplete internally,
    // and we call handleRecordingComplete explicitly below — only one should run.
    recordingController.onRecordingComplete = null;

    final result = recordingController.stopRecording();

    // Stop playhead polling (transport will be stopped by caller)
    playbackController.stopPlayheadPolling();

    return (result, capturedNotes);
  }

  /// Called at ~30fps during recording to update live clip display
  void _onLiveRecordingUpdate() {
    final liveClip = liveRecordingNotifier.buildLiveClipData();
    midiPlaybackManager?.setLiveRecordingClip(liveClip);

    // Set as current editing clip so piano roll shows live notes
    if (liveClip != null && liveClip.notes.isNotEmpty) {
      midiPlaybackManager?.selectClip(LiveRecordingNotifier.liveClipId, liveClip);
    }
  }

  /// Handle recording overlap: trim, split, or delete existing clips that
  /// overlap with the new recording. Uses shared [ClipOverlapHandler].
  void _handleRecordingOverlap({
    required int trackId,
    required double startTime,
    required double duration,
    required bool isMidiClip,
  }) {
    final newStart = startTime;
    final newEnd = startTime + duration;

    if (isMidiClip) {
      _applyMidiOverlap(trackId, newStart, newEnd);
    } else {
      _applyAudioOverlap(trackId, newStart, newEnd);
    }
  }

  void _applyMidiOverlap(int trackId, double newStart, double newEnd) {
    final clips = List<MidiClipData>.from(midiPlaybackManager?.midiClips ?? []);
    final result = ClipOverlapHandler.resolveMidiOverlaps(
      newStart: newStart,
      newEnd: newEnd,
      existingClips: clips,
      trackId: trackId,
    );
    ClipOverlapHandler.applyMidiResult(
      result: result,
      deleteClip: (clipId, tId) => midiClipController.deleteClip(clipId, tId),
      updateClipInPlace: (clip) => midiPlaybackManager?.updateClipInPlace(clip),
      rescheduleClip: (clip, t) => midiPlaybackManager?.rescheduleClip(clip, t),
      addClip: (clip) => midiPlaybackManager?.addRecordedClip(clip),
      tempo: tempo,
    );
  }

  void _applyAudioOverlap(int trackId, double newStart, double newEnd) {
    final timelineState = timelineKey.currentState;
    if (timelineState == null) return;

    final clips = List<ClipData>.from(timelineState.clips);
    final result = ClipOverlapHandler.resolveAudioOverlaps(
      newStart: newStart,
      newEnd: newEnd,
      existingClips: clips,
      trackId: trackId,
    );
    ClipOverlapHandler.applyAudioResult(
      result: result,
      engineRemoveClip: (tId, cId) => audioEngine?.removeAudioClip(tId, cId),
      engineSetStartTime: (tId, cId, s) => audioEngine?.setClipStartTime(tId, cId, s),
      engineSetOffset: (tId, cId, o) => audioEngine?.setClipOffset(tId, cId, o),
      engineSetDuration: (tId, cId, d) => audioEngine?.setClipDuration(tId, cId, d),
      engineDuplicateClip: (tId, cId, s) => audioEngine?.duplicateAudioClip(tId, cId, s) ?? -1,
      uiRemoveClip: (cId) => timelineState.removeClip(cId),
      uiUpdateClip: (clip) => timelineState.updateClip(clip),
      uiAddClip: (clip) => timelineState.addClip(clip),
    );
  }

  /// Generate a unique clip ID for split clips
  static int generateUniqueClipId() {
    return ClipOverlapHandler.generateUniqueClipId();
  }

  /// Handle recording completion - process audio and MIDI clips
  void handleRecordingComplete(RecordingResult result, {List<MidiNoteData> capturedNotes = const []}) {
    // Ensure live recording display is cleared
    liveRecordingNotifier.removeListener(_onLiveRecordingUpdate);
    midiPlaybackManager?.setLiveRecordingClip(null);

    final List<String> recordedItems = [];
    final timelineState = timelineKey.currentState;

    // Track IDs affected by this recording (for undo command)
    int? audioTrackIdForUndo;
    int? midiTrackIdForUndo;

    // Before snapshots (captured before overlap handling)
    List<ClipData> audioClipsBefore = [];
    List<MidiClipData> midiClipsBefore = [];

    // Handle audio clip
    if (result.audioClipId != null) {
      setState(() {
        loadedClipId = result.audioClipId;
        clipDuration = result.duration;
        waveformPeaks = result.waveformPeaks ?? [];
      });

      // Find the armed audio track to place the clip on
      final tracks = mixerKey.currentState?.tracks ?? [];
      final armedAudioTrack = tracks.cast<TrackData?>().firstWhere(
        (t) => t!.type == 'audio' && t.armed,
        orElse: () => null,
      );

      if (armedAudioTrack != null && result.duration != null && result.duration! > 0) {
        final audioTrackId = armedAudioTrack.id;
        audioTrackIdForUndo = audioTrackId;
        final startTime = recordingController.recordingStartPosition;
        final duration = result.duration!;
        final peaks = result.waveformPeaks ?? [];

        // Capture before snapshot
        audioClipsBefore = timelineState?.getAudioClipsOnTrack(audioTrackId) ?? [];

        // Handle overlap: trim, split, or delete existing clips
        _handleRecordingOverlap(
          trackId: audioTrackId,
          startTime: startTime,
          duration: duration,
          isMidiClip: false,
        );

        // Create ClipData and add to timeline
        final clipData = ClipData(
          clipId: result.audioClipId!,
          trackId: audioTrackId,
          filePath: 'recorded_t${audioTrackId}_${result.audioClipId}.wav',
          startTime: startTime,
          duration: duration,
          waveformPeaks: peaks,
        );

        if (timelineState != null) {
          timelineState.addClip(clipData);
        }
      }

      recordedItems.add('Audio ${result.duration?.toStringAsFixed(2) ?? ""}s');
    }

    // Handle MIDI clip
    if (result.midiClipId != null && result.midiClipInfo != null) {
      final clipInfo = result.midiClipInfo!;
      if (!clipInfo.startsWith('Error')) {
        try {
          final parts = clipInfo.split(',');
          if (parts.length >= 5) {
            final trackId = int.parse(parts[1]);
            final startTimeSeconds = double.parse(parts[2]);
            final durationSeconds = double.parse(parts[3]);
            final noteCount = int.parse(parts[4]);

            // Convert from seconds to beats for MIDI clip storage
            final beatsPerSecond = tempo / 60.0;
            final startTimeBeats = startTimeSeconds * beatsPerSecond;
            final durationBeats = durationSeconds > 0
                ? durationSeconds * beatsPerSecond
                : 16.0; // Default 4 bars (16 beats) if no duration

            // Create MidiClipData and add to timeline
            final actualTrackId = trackId >= 0 ? trackId : (selectedTrackId ?? 0);
            midiTrackIdForUndo = actualTrackId;
            final clipData = MidiClipData(
              clipId: result.midiClipId!,
              trackId: actualTrackId,
              startTime: startTimeBeats,
              duration: durationBeats,
              name: generateClipName(actualTrackId),
              notes: capturedNotes.isNotEmpty ? capturedNotes : [],
            );

            // Capture before snapshot
            midiClipsBefore = midiPlaybackManager?.midiClips
                    .where((c) => c.trackId == actualTrackId)
                    .toList() ??
                [];

            // Handle overlap: trim, split, or delete existing clips
            _handleRecordingOverlap(
              trackId: actualTrackId,
              startTime: startTimeBeats,
              duration: durationBeats,
              isMidiClip: true,
            );

            midiPlaybackManager?.addRecordedClip(clipData, rustClipId: result.midiClipId!);
            recordedItems.add('MIDI ($noteCount notes)');
          }
        } catch (e) {
          recordedItems.add('MIDI clip');
        }
      } else {
        recordedItems.add('MIDI clip');
      }
    }

    // Push undo command if any clips were recorded
    if (audioTrackIdForUndo != null || midiTrackIdForUndo != null) {
      // Capture after snapshots
      final audioClipsAfter = audioTrackIdForUndo != null
          ? (timelineState?.getAudioClipsOnTrack(audioTrackIdForUndo) ?? [])
          : <ClipData>[];
      final midiClipsAfter = midiTrackIdForUndo != null
          ? (midiPlaybackManager?.midiClips
                  .where((c) => c.trackId == midiTrackIdForUndo)
                  .toList() ??
              [])
          : <MidiClipData>[];

      final command = RecordingCompleteCommand(
        audioTrackId: audioTrackIdForUndo,
        midiTrackId: midiTrackIdForUndo,
        audioClipsBefore: audioClipsBefore,
        audioClipsAfter: audioClipsAfter,
        midiClipsBefore: midiClipsBefore,
        midiClipsAfter: midiClipsAfter,
        onApplyAudioState: (trackId, clips) {
          timelineKey.currentState?.replaceAudioClipsOnTrack(trackId, clips);
        },
        onApplyMidiState: (trackId, clips) {
          midiPlaybackManager?.replaceClipsOnTrack(trackId, clips);
        },
      );

      // Add to undo stack without re-executing (work already done)
      undoRedoManager.execute(command);
    }

    // Update status message
    if (recordedItems.isNotEmpty) {
      playbackController.setStatusMessage('Recorded: ${recordedItems.join(', ')}');
    } else if (result.audioClipId == null && result.midiClipId == null) {
      playbackController.setStatusMessage('No recording captured');
    }
  }

  // ============================================
  // METRONOME METHODS
  // ============================================

  /// Toggle metronome on/off
  void toggleMetronome() {
    recordingController.toggleMetronome();
    final newState = recordingController.isMetronomeEnabled;
    playbackController.setStatusMessage(newState ? 'Metronome enabled' : 'Metronome disabled');
  }

  /// Set count-in bars (0, 1, or 2)
  void setCountInBars(int bars) {
    userSettings.countInBars = bars;
    audioEngine?.setCountInBars(bars);

    final message = bars == 0
        ? 'Count-in disabled'
        : bars == 1
            ? 'Count-in: 1 bar'
            : 'Count-in: 2 bars';
    playbackController.setStatusMessage(message);
  }

  // ============================================
  // TEMPO METHODS
  // ============================================

  /// Handle tempo change with undo support
  Future<void> onTempoChanged(double bpm) async {
    final oldBpm = recordingController.tempo;
    if (oldBpm == bpm) return;

    final command = SetTempoCommand(
      newBpm: bpm,
      oldBpm: oldBpm,
      onTempoChanged: (newBpm) {
        // Get the current (old) tempo before we change it
        final currentTempo = recordingController.tempo;

        recordingController.setTempo(newBpm);
        midiClipController.setTempo(newBpm);
        midiCaptureBuffer.updateBpm(newBpm);
        midiPlaybackManager?.rescheduleAllClips(newBpm);

        // Adjust audio clip positions to maintain their beat position
        // This prevents audio clips from visually shifting when tempo changes
        timelineKey.currentState?.adjustAudioClipPositionsForTempoChange(currentTempo, newBpm);
      },
    );
    await undoRedoManager.execute(command);
  }

  /// Handle time signature change
  void onTimeSignatureChanged(int beatsPerBar, int beatUnit) {
    setState(() {
      projectMetadata = projectMetadata.copyWith(
        timeSignatureNumerator: beatsPerBar,
        timeSignatureDenominator: beatUnit,
      );
    });
    // Update engine time signature
    audioEngine?.setTimeSignature(beatsPerBar);
  }

  // ============================================
  // VIRTUAL PIANO METHODS
  // ============================================

  /// Toggle virtual piano on/off
  void toggleVirtualPiano() {
    final success = recordingController.toggleVirtualPiano();
    if (success) {
      uiLayout.setVirtualPianoEnabled(enabled: recordingController.isVirtualPianoEnabled);
      playbackController.setStatusMessage(
        recordingController.isVirtualPianoEnabled
            ? 'Virtual piano enabled - Press keys to play!'
            : 'Virtual piano disabled',
      );
    } else {
      playbackController.setStatusMessage('Virtual piano error');
    }
  }

  // ============================================
  // MIDI DEVICE METHODS
  // ============================================

  /// Load available MIDI devices
  void loadMidiDevices() {
    recordingController.loadMidiDevices();
  }

  /// Handle MIDI device selection
  void onMidiDeviceSelected(int deviceIndex) {
    recordingController.selectMidiDevice(deviceIndex);

    // Show feedback
    if (midiDevices.isNotEmpty && deviceIndex >= 0 && deviceIndex < midiDevices.length) {
      final deviceName = midiDevices[deviceIndex]['name'] as String? ?? 'Unknown';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selected: $deviceName'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Refresh MIDI devices list
  void refreshMidiDevices() {
    recordingController.refreshMidiDevices();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('MIDI devices refreshed'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ============================================
  // HELPER METHODS
  // ============================================

  /// Convert buffer size in samples to preset index
  /// 64=0 (Lowest), 128=1 (Low), 256=2 (Balanced), 512=3 (Safe), 1024=4 (HighStability)
  int bufferSizeToPreset(int bufferSize) {
    switch (bufferSize) {
      case 64: return 0;
      case 128: return 1;
      case 256: return 2;
      case 512: return 3;
      case 1024: return 4;
      default: return 2; // Default to Balanced (256)
    }
  }

  /// Get track name from engine
  String? getTrackName(int trackId) {
    final info = audioEngine?.getTrackInfo(trackId) ?? '';
    if (info.isEmpty) return null;

    final parts = info.split(',');
    if (parts.length < 2) return null;

    return parts[1];
  }

  /// Generate clip name for a track using instrument or track name
  String generateClipName(int trackId) {
    final instrument = trackInstruments[trackId];
    final trackName = getTrackName(trackId);
    return ClipNamingService.generateClipName(
      instrument: instrument,
      trackName: trackName,
    );
  }
}
