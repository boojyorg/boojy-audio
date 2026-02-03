import 'package:flutter/material.dart';
import '../../../controllers/controllers.dart';
import '../../../models/midi_note_data.dart';
import '../../../services/commands/project_commands.dart';
import '../../../services/clip_naming_service.dart';
import '../../../services/live_recording_notifier.dart';
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
    } else if (isCountingIn) {
      // During count-in: Cancel and return to start
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
    debugPrint('🔴 [REC_MIXIN] startRecording(isAlreadyPlaying=$isAlreadyPlaying) called');
    debugPrint('🔴 [REC_MIXIN]   countInBars=${userSettings.countInBars}, tempo=$tempo');
    debugPrint('🔴 [REC_MIXIN]   selectedTrackId=$selectedTrackId');

    // Block preview playback during recording
    libraryPreviewService?.setRecordingState(true);

    // Listen for live recording updates (real-time MIDI note display)
    liveRecordingNotifier.addListener(_onLiveRecordingUpdate);
    debugPrint('🔴 [REC_MIXIN]   Added _onLiveRecordingUpdate listener');

    // Set up callbacks
    recordingController.onRecordingComplete = handleRecordingComplete;
    recordingController.onRecordStartPositionChanged = playbackController.setRecordStartPosition;

    recordingController.startRecording(isAlreadyPlaying: isAlreadyPlaying);

    // Don't start playhead polling during count-in — the playhead should stay
    // frozen at the recording start position. Listen for the count-in → recording
    // transition and start polling then (with a display offset so the engine's
    // elapsed count-in time doesn't shift the visual playhead).
    recordingController.addListener(_onRecordingStateChanged);
    debugPrint('🔴 [REC_MIXIN]   Added _onRecordingStateChanged listener');
  }

  /// Detect count-in → recording transition and start playhead polling
  void _onRecordingStateChanged() {
    debugPrint('🔴 [REC_MIXIN] _onRecordingStateChanged() fired: '
        'isRecording=${recordingController.isRecording}, '
        'isCountingIn=${recordingController.isCountingIn}');

    if (recordingController.isRecording && !recordingController.isCountingIn) {
      recordingController.removeListener(_onRecordingStateChanged);

      // Calculate count-in duration to use as display offset
      final countInBars = userSettings.countInBars;
      final beatsPerBar = projectMetadata.timeSignatureNumerator;
      final countInDuration = countInBars * beatsPerBar * 60.0 / tempo;

      debugPrint('🔴 [REC_MIXIN]   Count-in→Recording transition detected!');
      debugPrint('🔴 [REC_MIXIN]   countInBars=$countInBars, beatsPerBar=$beatsPerBar, tempo=$tempo');
      debugPrint('🔴 [REC_MIXIN]   countInDuration=${countInDuration.toStringAsFixed(3)}s');
      debugPrint('🔴 [REC_MIXIN]   Starting playhead polling with displayOffset=$countInDuration');

      playbackController.startPlayheadPolling(displayOffset: countInDuration);
    }
  }

  /// Pause recording: Stop recording, stay at current position
  void pauseRecording() {
    if (!isRecording && !isCountingIn) return;

    debugPrint('🔴 [REC_MIXIN] pauseRecording() called - stopping and staying at current position');

    // Stop recording and save clip
    final result = _completeRecording();

    // Pause (stay at current position)
    playbackController.pause();

    handleRecordingComplete(result);
  }

  /// Stop recording: Stop recording, return to recordStartPosition
  void stopRecordingAndReturn() {
    if (!isRecording && !isCountingIn) return;

    debugPrint('🔴 [REC_MIXIN] stopRecordingAndReturn() called - stopping and returning to record start');

    // Stop recording and save clip
    final result = _completeRecording();

    // Stop and return to recording start position
    playbackController.stop(isRecording: true);

    handleRecordingComplete(result);
  }

  /// Stop playback (not recording): Return to playStartPosition or bar 1 if idle
  void stopPlayback() {
    debugPrint('🔴 [REC_MIXIN] stopPlayback() called');
    debugPrint('🔴 [REC_MIXIN]   isPlaying=${playbackController.isPlaying}');
    debugPrint('🔴 [REC_MIXIN]   playStartPosition=${playbackController.playStartPosition.toStringAsFixed(3)}s');
    debugPrint('🔴 [REC_MIXIN]   playheadPosition=${playbackController.playheadPosition.toStringAsFixed(3)}s');
    playbackController.stop(isRecording: false);
    debugPrint('🔴 [REC_MIXIN] stopPlayback() completed');
  }

  /// Internal: Complete recording and return results
  RecordingResult _completeRecording() {
    debugPrint('🔴 [REC_MIXIN] _completeRecording() called');

    // Re-enable preview playback
    libraryPreviewService?.setRecordingState(false);

    // Capture live recording notes BEFORE stopping — stopRecording() clears
    // the live recording notifier, so we must snapshot the notes now.
    final liveClip = liveRecordingNotifier.buildLiveClipData();
    final capturedNotes = liveClip?.notes ?? [];
    debugPrint('🔴 [REC_MIXIN]   Captured ${capturedNotes.length} live notes before stop');

    // Stop listening for live recording updates and state changes
    liveRecordingNotifier.removeListener(_onLiveRecordingUpdate);
    recordingController.removeListener(_onRecordingStateChanged);
    midiPlaybackManager?.setLiveRecordingClip(null);

    // Clear the callback BEFORE calling stopRecording() to prevent double-call.
    // recordingController.stopRecording() fires onRecordingComplete internally,
    // and we call handleRecordingComplete explicitly below — only one should run.
    recordingController.onRecordingComplete = null;

    final result = recordingController.stopRecording();
    debugPrint('🔴 [REC_MIXIN]   Recording result: '
        'audioClipId=${result.audioClipId}, midiClipId=${result.midiClipId}, '
        'duration=${result.duration}, midiClipInfo=${result.midiClipInfo}');

    // Stop playhead polling (transport will be stopped by caller)
    playbackController.stopPlayheadPolling();

    return result;
  }

  /// Called at ~30fps during recording to update live clip display
  void _onLiveRecordingUpdate() {
    final liveClip = liveRecordingNotifier.buildLiveClipData();
    midiPlaybackManager?.setLiveRecordingClip(liveClip);

    // Set as current editing clip so piano roll shows live notes
    if (liveClip != null && liveClip.notes.isNotEmpty) {
      midiPlaybackManager?.selectClip(LiveRecordingNotifier.liveClipId, liveClip);
      // Log every ~30 frames (once per second at 30fps) to avoid spam
      if (liveClip.notes.length % 5 == 1) {
        debugPrint('🔴 [REC_MIXIN] _onLiveRecordingUpdate: '
            '${liveClip.notes.length} notes, '
            'startTime=${liveClip.startTime.toStringAsFixed(2)}, '
            'duration=${liveClip.duration.toStringAsFixed(2)}');
      }
    }
  }

  /// Remove any clips on the track that are completely covered by the new clip.
  /// A clip is "completely covered" if: new_start <= old_start AND new_end >= old_end
  void _removeCompletelyCoveredClips({
    required int trackId,
    required double startTime,
    required double duration,
    required bool isMidiClip,
  }) {
    final newEndTime = startTime + duration;

    if (isMidiClip) {
      // Check MIDI clips on the same track
      final clipsToRemove = <int>[];
      for (final clip in midiPlaybackManager?.midiClips ?? []) {
        if (clip.trackId == trackId) {
          final clipEndTime = clip.startTime + clip.duration;
          // Check if new clip completely covers this existing clip
          if (startTime <= clip.startTime && newEndTime >= clipEndTime) {
            clipsToRemove.add(clip.clipId);
            debugPrint('🔴 [REC_MIXIN] Removing completely covered MIDI clip: '
                'id=${clip.clipId}, start=${clip.startTime.toStringAsFixed(2)}, '
                'end=${clipEndTime.toStringAsFixed(2)}');
          }
        }
      }
      // Remove the covered clips
      for (final clipId in clipsToRemove) {
        midiClipController.deleteClip(clipId, trackId);
      }
    } else {
      // Check audio clips on the same track
      final timelineState = timelineKey.currentState;
      if (timelineState != null) {
        final clipsToRemove = <int>[];
        for (final clip in timelineState.clips) {
          if (clip.trackId == trackId) {
            final clipEndTime = clip.startTime + clip.duration;
            // Check if new clip completely covers this existing clip
            if (startTime <= clip.startTime && newEndTime >= clipEndTime) {
              clipsToRemove.add(clip.clipId);
              debugPrint('🔴 [REC_MIXIN] Removing completely covered audio clip: '
                  'id=${clip.clipId}, start=${clip.startTime.toStringAsFixed(2)}, '
                  'end=${clipEndTime.toStringAsFixed(2)}');
            }
          }
        }
        // Remove the covered clips
        for (final clipId in clipsToRemove) {
          timelineState.removeClip(clipId);
        }
      }
    }
  }

  /// Handle recording completion - process audio and MIDI clips
  void handleRecordingComplete(RecordingResult result, {List<MidiNoteData> capturedNotes = const []}) {
    debugPrint('🔴 [REC_MIXIN] handleRecordingComplete() called');
    debugPrint('🔴 [REC_MIXIN]   audioClipId=${result.audioClipId}, midiClipId=${result.midiClipId}');
    debugPrint('🔴 [REC_MIXIN]   duration=${result.duration}, midiClipInfo="${result.midiClipInfo}"');

    // Ensure live recording display is cleared
    liveRecordingNotifier.removeListener(_onLiveRecordingUpdate);
    midiPlaybackManager?.setLiveRecordingClip(null);

    final List<String> recordedItems = [];

    // Handle audio clip
    if (result.audioClipId != null) {
      debugPrint('🔴 [REC_MIXIN]   Processing audio clip: id=${result.audioClipId}');
      setState(() {
        loadedClipId = result.audioClipId;
        clipDuration = result.duration;
        waveformPeaks = result.waveformPeaks ?? [];
      });
      recordedItems.add('Audio ${result.duration?.toStringAsFixed(2) ?? ""}s');
    }

    // Handle MIDI clip
    if (result.midiClipId != null && result.midiClipInfo != null) {
      debugPrint('🔴 [REC_MIXIN]   Processing MIDI clip: id=${result.midiClipId}');
      final clipInfo = result.midiClipInfo!;
      if (!clipInfo.startsWith('Error')) {
        try {
          final parts = clipInfo.split(',');
          debugPrint('🔴 [REC_MIXIN]   clipInfo parts (${parts.length}): $parts');
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
            debugPrint('🔴 [REC_MIXIN]   MIDI clip placement: trackId=$actualTrackId, '
                'startTimeBeats=${startTimeBeats.toStringAsFixed(3)}, '
                'durationBeats=${durationBeats.toStringAsFixed(3)}, '
                'noteCount=$noteCount, capturedNotes=${capturedNotes.length}');
            final clipData = MidiClipData(
              clipId: result.midiClipId!,
              trackId: actualTrackId,
              startTime: startTimeBeats,
              duration: durationBeats,
              name: generateClipName(actualTrackId),
              notes: capturedNotes.isNotEmpty ? capturedNotes : [],
            );

            // Remove any completely covered clips before adding the new one
            _removeCompletelyCoveredClips(
              trackId: actualTrackId,
              startTime: startTimeBeats,
              duration: durationBeats,
              isMidiClip: true,
            );

            debugPrint('🔴 [REC_MIXIN]   Calling midiPlaybackManager.addRecordedClip()');
            midiPlaybackManager?.addRecordedClip(clipData);
            recordedItems.add('MIDI ($noteCount notes)');
          } else {
            debugPrint('🔴 [REC_MIXIN]   ⚠️ clipInfo has <5 parts, skipping MIDI clip');
          }
        } catch (e) {
          debugPrint('🔴 [REC_MIXIN]   ⚠️ Error parsing MIDI clipInfo: $e');
          recordedItems.add('MIDI clip');
        }
      } else {
        debugPrint('🔴 [REC_MIXIN]   ⚠️ clipInfo starts with Error: $clipInfo');
        recordedItems.add('MIDI clip');
      }
    } else {
      debugPrint('🔴 [REC_MIXIN]   ⚠️ No MIDI clip: midiClipId=${result.midiClipId}, '
          'midiClipInfo=${result.midiClipInfo}');
    }

    // Update status message
    if (recordedItems.isNotEmpty) {
      debugPrint('🔴 [REC_MIXIN]   Final recorded items: $recordedItems');
      playbackController.setStatusMessage('Recorded: ${recordedItems.join(', ')}');
    } else if (result.audioClipId == null && result.midiClipId == null) {
      debugPrint('🔴 [REC_MIXIN]   ⚠️ No recording captured at all');
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
