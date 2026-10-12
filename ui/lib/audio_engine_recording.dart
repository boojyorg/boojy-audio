part of 'audio_engine_native.dart';

mixin _RecordingMixin on _AudioEngineBase {
  // ========================================================================
  // M2 API - Recording & Input
  // ========================================================================

  /// Start recording audio
  String startRecording() {
    final resultPtr = _startRecording();
    final result = resultPtr.toDartString();
    _freeRustString(resultPtr);
    return result;
  }

  /// Stop recording and return clip ID (-1 if no recording)
  int stopRecording() {
    try {
      final clipId = _stopRecording();
      return clipId;
    } catch (e) {
      return -1;
    }
  }

  /// Every audio clip the last [stopRecording] made, one per armed audio
  /// track ([stopRecording] returns only the first).
  List<int> getLastRecordedClipIds() {
    try {
      final resultPtr = _getLastRecordedClipIds();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return [
        for (final id in result.split(','))
          if (int.tryParse(id) case final clipId?) clipId,
      ];
    } catch (e) {
      return const [];
    }
  }

  /// Get recording state (0=Idle, 1=CountingIn, 2=Recording)
  int getRecordingState() {
    try {
      return _getRecordingState();
    } catch (e) {
      return 0;
    }
  }

  /// Get recorded duration in seconds
  double getRecordedDuration() {
    try {
      return _getRecordedDuration();
    } catch (e) {
      return 0.0;
    }
  }

  /// The live waveform of the take in progress, from peak [from] on (one
  /// left/right pair per 10 ms). Cheap; polled while recording.
  LivePeaksChunk getLiveRecordingPeaks(int from) {
    try {
      final resultPtr = _getLiveRecordingPeaks(from);
      final raw = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return LivePeaksChunk.parse(raw);
    } catch (e) {
      return LivePeaksChunk.empty;
    }
  }

  /// Set count-in duration in bars
  String setCountInBars(int bars) {
    final resultPtr = _setCountInBars(bars);
    final result = resultPtr.toDartString();
    _freeRustString(resultPtr);
    return result;
  }

  /// Get current count-in beat number (1-indexed, 0 when not counting in)
  int getCountInBeat() {
    try {
      return _getCountInBeat();
    } catch (e) {
      return 0;
    }
  }

  /// Get count-in progress (0.0-1.0)
  double getCountInProgress() {
    try {
      return _getCountInProgress();
    } catch (e) {
      return 0.0;
    }
  }

  /// Set tempo in BPM
  String setTempo(double bpm) {
    final resultPtr = _setTempo(bpm);
    final result = resultPtr.toDartString();
    _freeRustString(resultPtr);
    return result;
  }

  /// Get tempo in BPM
  double getTempo() {
    try {
      return _getTempo();
    } catch (e) {
      return 120.0;
    }
  }

  /// Enable or disable metronome
  String setMetronomeEnabled({required bool enabled}) {
    final resultPtr = _setMetronomeEnabled(enabled ? 1 : 0);
    final result = resultPtr.toDartString();
    _freeRustString(resultPtr);
    return result;
  }

  /// Set time signature (beats per bar)
  String setTimeSignature(int beatsPerBar) {
    final resultPtr = _setTimeSignature(beatsPerBar);
    final result = resultPtr.toDartString();
    _freeRustString(resultPtr);
    return result;
  }

  // ========================================================================
  // M3 API - MIDI
  // ========================================================================

  /// Start MIDI input (initializes MIDI system and synthesizer)
  String startMidiInput() {
    final resultPtr = _startMidiInput();
    final result = resultPtr.toDartString();
    _freeRustString(resultPtr);
    return result;
  }

  /// Send MIDI note on event to synthesizer (for virtual piano)
  String sendMidiNoteOn(int note, int velocity) {
    final resultPtr = _sendMidiNoteOn(note, velocity);
    final result = resultPtr.toDartString();
    _freeRustString(resultPtr);
    return result;
  }

  /// Send MIDI note off event to synthesizer (for virtual piano)
  String sendMidiNoteOff(int note, int velocity) {
    final resultPtr = _sendMidiNoteOff(note, velocity);
    final result = resultPtr.toDartString();
    _freeRustString(resultPtr);
    return result;
  }

  /// Create a new empty MIDI clip in Rust
  /// Returns clip ID or -1 on error
  int createMidiClip() {
    try {
      return _createMidiClip();
    } catch (e) {
      return -1;
    }
  }

  /// Add a MIDI note to a clip
  /// Returns success message or error
  String addMidiNoteToClip(
    int clipId,
    int note,
    int velocity,
    double startTime,
    double duration,
  ) {
    try {
      final resultPtr = _addMidiNoteToClip(
        clipId,
        note,
        velocity,
        startTime,
        duration,
      );
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Add a MIDI clip to a track's timeline for playback
  /// Returns 0 on success, -1 on error
  int addMidiClipToTrack(int trackId, int clipId, double startTimeSeconds) {
    try {
      return _addMidiClipToTrack(trackId, clipId, startTimeSeconds);
    } catch (e) {
      return -1;
    }
  }

  /// Remove a MIDI clip from a track and global storage
  /// Returns 0 if removed, 1 if not found, -1 on error
  int removeMidiClip(int trackId, int clipId) {
    try {
      return _removeMidiClip(trackId, clipId);
    } catch (e) {
      return -1;
    }
  }

  /// Clear all MIDI notes from a clip
  /// Returns success message or error
  String clearMidiClip(int clipId) {
    try {
      final resultPtr = _clearMidiClip(clipId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  // ========================================================================
  // MIDI Recording API
  // ========================================================================

  /// Get available MIDI input devices
  /// Returns list of devices with id, name, and isDefault
  List<Map<String, dynamic>> getMidiInputDevices() {
    try {
      final resultPtr = _getMidiInputDevices();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.isEmpty || result.startsWith('Error:')) {
        return [];
      }

      // Parse result: "id|name|is_default" per line
      final devices = <Map<String, dynamic>>[];
      for (final line in result.split('\n')) {
        if (line.isEmpty) continue;
        final parts = line.split('|');
        if (parts.length >= 3) {
          devices.add({
            'id': parts[0],
            'name': parts[1],
            'isDefault': parts[2] == '1',
          });
        }
      }

      return devices;
    } catch (e) {
      return [];
    }
  }

  /// Select a MIDI input device by index
  /// Returns success message or error
  String selectMidiInputDevice(int deviceIndex) {
    try {
      final resultPtr = _selectMidiInputDevice(deviceIndex);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Refresh MIDI devices (rescan)
  /// Returns success message or error
  String refreshMidiDevices() {
    try {
      final resultPtr = _refreshMidiDevices();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  // ========================================================================
  // Audio Device API
  // ========================================================================

  /// Get available audio input devices
  /// Returns list of devices with id, name, and isDefault
  List<Map<String, dynamic>> getAudioInputDevices() {
    try {
      final resultPtr = _getAudioInputDevices();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.isEmpty || result.startsWith('Error:')) {
        return [];
      }

      // Parse result: "id|name|is_default" per line
      final devices = <Map<String, dynamic>>[];
      for (final line in result.split('\n')) {
        if (line.isEmpty) continue;
        final parts = line.split('|');
        if (parts.length >= 3) {
          devices.add({
            'id': parts[0],
            'name': parts[1],
            'isDefault': parts[2] == '1',
          });
        }
      }

      return devices;
    } catch (e) {
      return [];
    }
  }

  /// Get available audio output devices
  /// Returns list of devices with id, name, and isDefault
  List<Map<String, dynamic>> getAudioOutputDevices() {
    try {
      final resultPtr = _getAudioOutputDevices();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.isEmpty || result.startsWith('Error:')) {
        return [];
      }

      // Parse result: "id|name|is_default" per line
      final devices = <Map<String, dynamic>>[];
      for (final line in result.split('\n')) {
        if (line.isEmpty) continue;
        final parts = line.split('|');
        if (parts.length >= 3) {
          devices.add({
            'id': parts[0],
            'name': parts[1],
            'isDefault': parts[2] == '1',
          });
        }
      }

      return devices;
    } catch (e) {
      return [];
    }
  }

  /// Choose the audio input: '' follows the system default,
  /// [kAudioInputOff] turns input off, anything else is a device name.
  /// Returns success message or error
  String setAudioInputChoice(String deviceName) {
    try {
      final deviceNamePtr = deviceName.toNativeUtf8();
      final resultPtr = _setAudioInputChoice(deviceNamePtr);
      calloc.free(deviceNamePtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// The input as it resolves right now (device, fallback, channel count),
  /// without opening it.
  AudioInputStatus getAudioInputStatus() {
    try {
      final resultPtr = _getAudioInputStatus();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return AudioInputStatus.parse(result);
    } catch (e) {
      return AudioInputStatus.unknown;
    }
  }

  /// Whether the open input is delivering sound. Cheap; polled while an
  /// audio track is armed.
  AudioInputHealth getAudioInputHealth() {
    try {
      return AudioInputHealth.fromCode(_getAudioInputHealth());
    } catch (e) {
      return AudioInputHealth.unknown;
    }
  }

  /// Set audio output device by name
  /// Pass empty string to use system default
  /// Returns success message or error
  String setAudioOutputDevice(String deviceName) {
    try {
      final deviceNamePtr = deviceName.toNativeUtf8();
      final resultPtr = _setAudioOutputDevice(deviceNamePtr);
      calloc.free(deviceNamePtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Take (read-and-clear) the last audio output stream error (C99).
  /// Returns an empty string when the stream is healthy. Polled during
  /// playback so a disconnected device stops the transport with a message
  /// instead of failing silently.
  String getAudioStreamError() {
    try {
      final resultPtr = _getAudioStreamError();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      if (result.startsWith('Error:')) {
        return '';
      }
      return result;
    } catch (e) {
      return '';
    }
  }

  /// Start MIDI recording
  /// Returns success message or error
  String startMidiRecording() {
    try {
      final resultPtr = _startMidiRecording();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Stop MIDI recording and return clip ID
  /// Returns clip ID or -1 if no recording
  int stopMidiRecording() {
    try {
      final clipId = _stopMidiRecording();
      return clipId;
    } catch (e) {
      return -1;
    }
  }

  /// Get live MIDI recording events for real-time UI preview
  /// Returns CSV: "note,velocity,type,timestamp_samples;..." or empty string
  String getMidiRecorderLiveEvents() {
    try {
      final resultPtr = _getMidiRecorderLiveEvents();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return '';
    }
  }

  /// Quantize a MIDI clip to grid
  /// gridDivision: 4=1/4 note, 8=1/8, 16=1/16, 32=1/32
  String quantizeMidiClip(int clipId, int gridDivision) {
    try {
      final resultPtr = _quantizeMidiClip(clipId, gridDivision);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Get MIDI clip info
  /// Returns: "clip_id,track_id,start_time,duration,note_count"
  /// track_id is -1 if not assigned to a track
  String getMidiClipInfo(int clipId) {
    try {
      final resultPtr = _getMidiClipInfo(clipId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Get all MIDI clips info
  /// Returns semicolon-separated list:
  /// "clip_id,track_id,start_time,duration,note_count,plays" (plays: 1 = on a track)
  /// Each clip info is separated by semicolon
  String getAllMidiClipsInfo() {
    try {
      final resultPtr = _getAllMidiClipsInfo();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Get MIDI notes from a clip
  /// Returns semicolon-separated list: "note,velocity,start_time,duration"
  String getMidiClipNotes(int clipId) {
    try {
      final resultPtr = _getMidiClipNotes(clipId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }
}
