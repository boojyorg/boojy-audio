// ignore_for_file: avoid_positional_boolean_parameters
part of 'audio_engine_native.dart';

mixin _TransportMixin on _AudioEngineBase {
  // ========================================================================
  // M0 API
  // ========================================================================

  /// Initialize the audio engine
  String initAudioEngine() {
    final resultPtr = _initAudioEngine();
    final result = resultPtr.toDartString();
    _freeRustString(resultPtr);
    return result;
  }

  // ========================================================================
  // M1 API
  // ========================================================================

  /// Initialize the audio graph
  String initAudioGraph() {
    final resultPtr = _initAudioGraph();
    final result = resultPtr.toDartString();
    _freeRustString(resultPtr);
    return result;
  }

  /// Load an audio file to a specific track and return clip ID (-1 on error)
  int loadAudioFileToTrack(String path, int trackId, {double startTime = 0.0}) {
    final pathPtr = path.toNativeUtf8();
    final clipId = _loadAudioFileToTrack(pathPtr.cast(), trackId, startTime);
    malloc.free(pathPtr);

    if (clipId < 0) {
      return -1;
    }

    return clipId;
  }

  /// Start playback
  String transportPlay() {
    final resultPtr = _transportPlay();
    final result = resultPtr.toDartString();
    _freeRustString(resultPtr);
    return result;
  }

  /// Pause playback
  String transportPause() {
    final resultPtr = _transportPause();
    final result = resultPtr.toDartString();
    _freeRustString(resultPtr);
    return result;
  }

  /// Stop playback
  String transportStop() {
    final resultPtr = _transportStop();
    final result = resultPtr.toDartString();
    _freeRustString(resultPtr);
    return result;
  }

  /// Seek to position in seconds
  String transportSeek(double positionSeconds) {
    final resultPtr = _transportSeek(positionSeconds);
    final result = resultPtr.toDartString();
    _freeRustString(resultPtr);
    return result;
  }

  /// Get current playhead position in seconds
  double getPlayheadPosition() {
    try {
      return _getPlayheadPosition();
    } catch (e) {
      return 0.0;
    }
  }

  // ============================================================================
  // Latency Control API
  // ============================================================================

  /// Set buffer size preset
  /// 0=Lowest, 1=Low, 2=Balanced, 3=Safe, 4=HighStability
  String setBufferSize(int preset) {
    try {
      final result = _setBufferSize(preset);
      final str = result.toDartString();
      _freeRustString(result);
      return str;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Get clip duration in seconds
  double getClipDuration(int clipId) {
    try {
      return _getClipDuration(clipId);
    } catch (e) {
      return 0.0;
    }
  }

  /// Every audio clip on every track, as the engine holds them.
  ///
  /// Semicolon-separated rows; each row is
  /// "clip_id,track_id,start_time,offset,duration,file_duration,gain_db,
  /// warp_enabled,stretch_factor,warp_mode,transpose_semitones,
  /// transpose_cents,reversed,file_path". `duration` is -1 when the clip plays
  /// to the end of its file; booleans are 0/1; `file_path` is last and
  /// percent-encoded (decode with `decodeCsvField`). Parse with
  /// `parseAudioClipsInfo` (lib/utils/audio_clips_info.dart).
  String getAllAudioClipsInfo() {
    try {
      final resultPtr = _getAllAudioClipsInfo();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Set clip start time (position) on timeline
  /// Used for dragging clips to reposition them
  String setClipStartTime(int trackId, int clipId, double startTime) {
    try {
      final result = _setClipStartTime(trackId, clipId, startTime);
      final str = result.toDartString();
      _freeRustString(result);
      return str;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Set audio clip offset (trim start position)
  /// Used for recording overlap trimming
  String setClipOffset(int trackId, int clipId, double offset) {
    try {
      final result = _setClipOffset(trackId, clipId, offset);
      final str = result.toDartString();
      _freeRustString(result);
      return str;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Set audio clip duration
  /// Used for recording overlap trimming
  String setClipDuration(int trackId, int clipId, double duration) {
    try {
      final result = _setClipDuration(trackId, clipId, duration);
      final str = result.toDartString();
      _freeRustString(result);
      return str;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Set audio clip gain
  /// Used to adjust per-clip volume in the Audio Editor
  String setAudioClipGain(int trackId, int clipId, double gainDb) {
    try {
      final result = _setAudioClipGain(trackId, clipId, gainDb);
      final str = result.toDartString();
      _freeRustString(result);
      return str;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Set audio clip warp settings for tempo sync
  /// Used to enable/disable time-stretching in the Audio Editor
  /// Always Stretch (pitch preserved): the engine's mode 0.
  String setAudioClipWarp(
    int trackId,
    int clipId,
    bool warpEnabled,
    double stretchFactor,
  ) {
    try {
      final result = _setAudioClipWarp(
        trackId,
        clipId,
        warpEnabled,
        stretchFactor,
        0,
      );
      final str = result.toDartString();
      _freeRustString(result);
      return str;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Set audio clip transpose (pitch shift)
  /// semitones: -48 to +48
  /// cents: -50 to +50
  String setAudioClipTranspose(
    int trackId,
    int clipId,
    int semitones,
    int cents,
  ) {
    try {
      final result = _setAudioClipTranspose(trackId, clipId, semitones, cents);
      final str = result.toDartString();
      _freeRustString(result);
      return str;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Set whether an audio clip plays backwards
  String setAudioClipReverse(
    int trackId,
    int clipId, {
    required bool reversed,
  }) {
    try {
      final result = _setAudioClipReverse(trackId, clipId, reversed);
      final str = result.toDartString();
      _freeRustString(result);
      return str;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Set how an audio clip repeats: [loopLength] seconds of its own audio
  /// from its trim offset (`<= 0` = no repeats), starting [loopStart]
  /// seconds into the loop.
  String setAudioClipLoop(
    int trackId,
    int clipId,
    double loopLength,
    double loopStart,
  ) {
    try {
      final result = _setAudioClipLoop(trackId, clipId, loopLength, loopStart);
      final str = result.toDartString();
      _freeRustString(result);
      return str;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Get waveform peaks for visualization
  List<double> getWaveformPeaks(int clipId, int resolution) {
    try {
      final lengthPtr = malloc<ffi.Size>();
      final peaksPtr = _getWaveformPeaks(clipId, resolution, lengthPtr);
      final length = lengthPtr.value;
      malloc.free(lengthPtr);

      if (peaksPtr == ffi.nullptr || length == 0) {
        return [];
      }

      // Convert to Dart list
      final peaks = <double>[];
      for (int i = 0; i < length; i++) {
        peaks.add(peaksPtr[i]);
      }

      // Free the peaks array
      _freeWaveformPeaks(peaksPtr, length);

      return peaks;
    } catch (e) {
      return [];
    }
  }
}
