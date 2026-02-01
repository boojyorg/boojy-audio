import 'package:flutter/material.dart';
import '../../../controllers/controllers.dart';
import '../../../models/midi_note_data.dart';
import '../../../services/commands/project_commands.dart';
import '../../../services/clip_naming_service.dart';
import '../../daw_screen.dart';
import 'daw_screen_state.dart';

/// Mixin containing recording-related methods for DAWScreen.
/// Handles record, metronome, count-in, tempo, virtual piano, and MIDI devices.
mixin DAWRecordingMixin on State<DAWScreen>, DAWScreenStateMixin {
  // ============================================
  // RECORDING METHODS
  // ============================================

  /// Toggle recording on/off
  void toggleRecording() {
    if (isRecording || isCountingIn) {
      stopRecording();
    } else {
      startRecording();
    }
  }

  /// Start recording
  void startRecording() {
    // Block preview playback during recording
    libraryPreviewService?.setRecordingState(true);

    // Set up callback to handle recording completion with MIDI clip processing
    recordingController.onRecordingComplete = handleRecordingComplete;
    recordingController.startRecording();
  }

  /// Stop recording
  void stopRecording() {
    // Re-enable preview playback
    libraryPreviewService?.setRecordingState(false);

    final result = recordingController.stopRecording();
    handleRecordingComplete(result);
  }

  /// Handle recording completion - process audio and MIDI clips
  void handleRecordingComplete(RecordingResult result) {
    final List<String> recordedItems = [];

    // Handle audio clip
    if (result.audioClipId != null) {
      setState(() {
        loadedClipId = result.audioClipId;
        clipDuration = result.duration;
        waveformPeaks = result.waveformPeaks ?? [];
      });
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
            final clipData = MidiClipData(
              clipId: result.midiClipId!,
              trackId: actualTrackId,
              startTime: startTimeBeats,
              duration: durationBeats,
              name: generateClipName(actualTrackId),
              notes: [], // Notes are managed by the engine
            );

            midiPlaybackManager?.addRecordedClip(clipData);
            recordedItems.add('MIDI ($noteCount notes)');
          }
        } catch (e) {
          recordedItems.add('MIDI clip');
        }
      } else {
        recordedItems.add('MIDI clip');
      }
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
