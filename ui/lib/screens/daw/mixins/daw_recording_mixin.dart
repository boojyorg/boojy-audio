import 'package:flutter/material.dart';
import '../../../controllers/controllers.dart';
import '../../../models/clip_data.dart';
import '../../../models/midi_note_data.dart';
import '../../../models/track_data.dart';
import '../../../services/commands/clip_commands.dart';
import '../../../services/commands/command.dart';
import '../../../services/commands/project_commands.dart';
import '../../../services/clip_naming_service.dart';
import '../../../services/live_recording_notifier.dart';
import '../../../widgets/timeline/gestures/midi_clip_gestures.dart';
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
    // Block preview playback during recording
    libraryPreviewService?.setRecordingState(true);

    // Listen for live recording updates (real-time MIDI note display)
    liveRecordingNotifier.addListener(_onLiveRecordingUpdate);

    // Set up callbacks
    recordingController.onRecordingComplete = handleRecordingComplete;
    recordingController.onRecordStartPositionChanged = playbackController.setRecordStartPosition;

    recordingController.startRecording(isAlreadyPlaying: isAlreadyPlaying);

    // Don't start playhead polling during count-in — the playhead should stay
    // frozen at the recording start position. Listen for the count-in → recording
    // transition and start polling then (with a display offset so the engine's
    // elapsed count-in time doesn't shift the visual playhead).
    recordingController.addListener(_onRecordingStateChanged);
  }

  /// Detect count-in → recording transition and start playhead polling
  void _onRecordingStateChanged() {
    if (recordingController.isRecording && !recordingController.isCountingIn) {
      recordingController.removeListener(_onRecordingStateChanged);

      // Use actual count-in duration from recording controller (measured by engine)
      // This ensures correct offset for both normal recording (with count-in) and
      // Play→Record (no count-in, offset = 0)
      final countInDuration = recordingController.countInDurationSeconds;

      playbackController.startPlayheadPolling(displayOffset: countInDuration);
    }
  }

  /// Pause recording: Stop recording, stay at current position
  void pauseRecording() {
    if (!isRecording && !isCountingIn) return;

    // Stop recording and save clip
    final (result, capturedNotes) = _completeRecording();

    // Pause (stay at current position)
    playbackController.pause();

    handleRecordingComplete(result, capturedNotes: capturedNotes);
  }

  /// Stop recording: Stop recording, return to recordStartPosition
  void stopRecordingAndReturn() {
    if (!isRecording && !isCountingIn) return;

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
  /// overlap with the new recording. "New recording always wins."
  ///
  /// Handles 4 scenarios:
  /// 1. Complete cover: new covers existing entirely → delete existing
  /// 2. Overlaps end: new starts inside existing → trim existing end
  /// 3. Overlaps start: new ends inside existing → trim existing start
  /// 4. Inside existing: new is inside existing → split existing into two
  ///
  /// Clips trimmed smaller than [minClipSize] are deleted instead.
  void _handleRecordingOverlap({
    required int trackId,
    required double startTime,
    required double duration,
    required bool isMidiClip,
  }) {
    final newStart = startTime;
    final newEnd = startTime + duration;
    // Minimum clip size: 0.25 beats (MIDI) or equivalent seconds (audio)
    const minClipSize = 0.25;

    if (isMidiClip) {
      _handleMidiRecordingOverlap(trackId, newStart, newEnd, minClipSize);
    } else {
      _handleAudioRecordingOverlap(trackId, newStart, newEnd, minClipSize);
    }
  }

  void _handleMidiRecordingOverlap(
    int trackId,
    double newStart,
    double newEnd,
    double minClipSize,
  ) {
    final clips = List<MidiClipData>.from(midiPlaybackManager?.midiClips ?? []);
    final clipsToRemove = <int>[];
    final clipsToUpdate = <MidiClipData>[];
    final clipsToAdd = <MidiClipData>[];
    final clipIdsToRemoveForSplit = <int>[];

    for (final clip in clips) {
      if (clip.trackId != trackId) continue;
      final clipEnd = clip.startTime + clip.duration;

      // No overlap — skip
      if (newEnd <= clip.startTime || newStart >= clipEnd) continue;

      // Case 1: Complete cover → delete
      if (newStart <= clip.startTime && newEnd >= clipEnd) {
        clipsToRemove.add(clip.clipId);
        continue;
      }

      // Case 2: New overlaps end of existing → trim existing end
      if (newStart > clip.startTime && newStart < clipEnd && newEnd >= clipEnd) {
        final newDuration = newStart - clip.startTime;
        if (newDuration < minClipSize) {
          clipsToRemove.add(clip.clipId);
        } else {
          clipsToUpdate.add(clip.copyWith(duration: newDuration));
        }
        continue;
      }

      // Case 3: New overlaps start of existing → trim existing start
      if (newEnd > clip.startTime && newEnd < clipEnd && newStart <= clip.startTime) {
        final newDuration = clipEnd - newEnd;
        if (newDuration < minClipSize) {
          clipsToRemove.add(clip.clipId);
        } else {
          // Adjust notes for the trim offset
          final trimOffset = newEnd - clip.startTime;
          final adjustedNotes = MidiClipGestureUtils.adjustNotesForTrim(
            notes: clip.notes,
            trimOffset: trimOffset,
          );
          clipsToUpdate.add(clip.copyWith(
            startTime: newEnd,
            duration: newDuration,
            notes: adjustedNotes,
          ));
        }
        continue;
      }

      // Case 4: New is inside existing → split into Part A + Part B
      if (newStart > clip.startTime && newEnd < clipEnd) {
        final partADuration = newStart - clip.startTime;
        final partBDuration = clipEnd - newEnd;
        final splitOffset = newEnd - clip.startTime;

        // Part A: original start to newStart
        if (partADuration >= minClipSize) {
          final partAId = generateUniqueClipId();
          clipsToAdd.add(clip.copyWith(
            clipId: partAId,
            duration: partADuration,
            name: '${clip.name} (L)',
          ));
        }

        // Part B: newEnd to original end
        if (partBDuration >= minClipSize) {
          final partBId = generateUniqueClipId();
          final adjustedNotes = MidiClipGestureUtils.adjustNotesForTrim(
            notes: clip.notes,
            trimOffset: splitOffset,
          );
          clipsToAdd.add(clip.copyWith(
            clipId: partBId,
            startTime: newEnd,
            duration: partBDuration,
            notes: adjustedNotes,
            name: '${clip.name} (R)',
          ));
        }

        // Mark original for removal
        clipIdsToRemoveForSplit.add(clip.clipId);
        continue;
      }
    }

    // Execute: remove, update, then add (order matters)
    for (final clipId in clipsToRemove) {
      midiClipController.deleteClip(clipId, trackId);
    }
    for (final clipId in clipIdsToRemoveForSplit) {
      midiClipController.deleteClip(clipId, trackId);
    }
    for (final updated in clipsToUpdate) {
      midiPlaybackManager?.updateClipInPlace(updated);
      // Sync to engine: reschedule notes and update start time
      midiPlaybackManager?.rescheduleClip(updated, tempo);
    }
    for (final newClip in clipsToAdd) {
      midiPlaybackManager?.addRecordedClip(newClip);
      // Sync to engine: create Rust clip and schedule notes
      midiPlaybackManager?.rescheduleClip(newClip, tempo);
    }
  }

  void _handleAudioRecordingOverlap(
    int trackId,
    double newStart,
    double newEnd,
    double minClipSize,
  ) {
    final timelineState = timelineKey.currentState;
    if (timelineState == null) return;

    final clips = List<ClipData>.from(timelineState.clips);
    final clipIdsToRemove = <int>[];
    final clipsToUpdate = <ClipData>[];
    final clipsToAdd = <ClipData>[];

    for (final clip in clips) {
      if (clip.trackId != trackId) continue;
      final clipEnd = clip.startTime + clip.duration;

      // No overlap — skip
      if (newEnd <= clip.startTime || newStart >= clipEnd) continue;

      // Case 1: Complete cover → delete
      if (newStart <= clip.startTime && newEnd >= clipEnd) {
        // Sync to engine
        audioEngine?.removeAudioClip(clip.trackId, clip.clipId);
        clipIdsToRemove.add(clip.clipId);
        continue;
      }

      // Case 2: New overlaps end of existing → trim existing end
      if (newStart > clip.startTime && newStart < clipEnd && newEnd >= clipEnd) {
        final newDuration = newStart - clip.startTime;
        if (newDuration < minClipSize) {
          audioEngine?.removeAudioClip(clip.trackId, clip.clipId);
          clipIdsToRemove.add(clip.clipId);
        } else {
          // Sync to engine: update duration in-place
          audioEngine?.setClipDuration(clip.trackId, clip.clipId, newDuration);
          clipsToUpdate.add(clip.copyWith(duration: newDuration));
        }
        continue;
      }

      // Case 3: New overlaps start of existing → trim existing start
      if (newEnd > clip.startTime && newEnd < clipEnd && newStart <= clip.startTime) {
        final newDuration = clipEnd - newEnd;
        if (newDuration < minClipSize) {
          audioEngine?.removeAudioClip(clip.trackId, clip.clipId);
          clipIdsToRemove.add(clip.clipId);
        } else {
          final trimDelta = newEnd - clip.startTime;
          // Sync to engine: update start time, offset, and duration in-place
          audioEngine?.setClipStartTime(clip.trackId, clip.clipId, newEnd);
          audioEngine?.setClipOffset(clip.trackId, clip.clipId, clip.offset + trimDelta);
          audioEngine?.setClipDuration(clip.trackId, clip.clipId, newDuration);
          clipsToUpdate.add(clip.copyWith(
            startTime: newEnd,
            duration: newDuration,
            offset: clip.offset + trimDelta,
          ));
        }
        continue;
      }

      // Case 4: New is inside existing → split into Part A + Part B
      if (newStart > clip.startTime && newEnd < clipEnd) {
        final partADuration = newStart - clip.startTime;
        final partBDuration = clipEnd - newEnd;
        final trimDelta = newEnd - clip.startTime;

        // Part B: duplicate BEFORE modifying original (duplicateAudioClip reads from track)
        if (partBDuration >= minClipSize) {
          final partBEngineId = audioEngine?.duplicateAudioClip(clip.trackId, clip.clipId, newEnd) ?? -1;
          if (partBEngineId > 0) {
            audioEngine?.setClipOffset(clip.trackId, partBEngineId, clip.offset + trimDelta);
            audioEngine?.setClipDuration(clip.trackId, partBEngineId, partBDuration);
            clipsToAdd.add(clip.copyWith(
              clipId: partBEngineId,
              startTime: newEnd,
              duration: partBDuration,
              offset: clip.offset + trimDelta,
            ));
          }
        }

        // Part A: shrink original in-place
        if (partADuration >= minClipSize) {
          audioEngine?.setClipDuration(clip.trackId, clip.clipId, partADuration);
          clipsToUpdate.add(clip.copyWith(duration: partADuration));
        } else {
          audioEngine?.removeAudioClip(clip.trackId, clip.clipId);
          clipIdsToRemove.add(clip.clipId);
        }
        continue;
      }
    }

    // Execute UI updates: remove, update, then add (order matters)
    for (final clipId in clipIdsToRemove) {
      timelineState.removeClip(clipId);
    }
    for (final updated in clipsToUpdate) {
      timelineState.updateClip(updated);
    }
    for (final newClip in clipsToAdd) {
      timelineState.addClip(newClip);
    }
  }

  /// Generate a unique clip ID for split clips
  static int generateUniqueClipId() {
    return DateTime.now().microsecondsSinceEpoch + (++_clipIdCounter);
  }
  static int _clipIdCounter = 0;

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
