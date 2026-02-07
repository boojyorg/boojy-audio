part of 'audio_engine_native.dart';

/// Latency test state constants
const int latencyTestStateIdle = 0;
const int latencyTestStateWaitingForSilence = 1;
const int latencyTestStatePlaying = 2;
const int latencyTestStateListening = 3;
const int latencyTestStateAnalyzing = 4;
const int latencyTestStateDone = 5;
const int latencyTestStateError = 6;

mixin _TransportMixin on _AudioEngineBase {
  // ========================================================================
  // M0 API
  // ========================================================================

  /// Initialize the audio engine
  String initAudioEngine() {
    try {
      final resultPtr = _initAudioEngine();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Play a sine wave at the specified frequency
  String playSineWave(double frequency, int durationMs) {
    try {
      final resultPtr = _playSineWave(frequency, durationMs);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  // ========================================================================
  // M1 API
  // ========================================================================

  /// Initialize the audio graph
  String initAudioGraph() {
    try {
      final resultPtr = _initAudioGraph();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Load an audio file and return clip ID (-1 on error)
  /// Legacy method - adds clip to first available audio track
  int loadAudioFile(String path) {
    try {
      final pathPtr = path.toNativeUtf8();
      final clipId = _loadAudioFile(pathPtr.cast());
      malloc.free(pathPtr);

      if (clipId < 0) {
        return -1;
      }

      return clipId;
    } catch (e) {
      rethrow;
    }
  }

  /// Load an audio file to a specific track and return clip ID (-1 on error)
  int loadAudioFileToTrack(String path, int trackId, {double startTime = 0.0}) {
    try {
      final pathPtr = path.toNativeUtf8();
      final clipId = _loadAudioFileToTrack(pathPtr.cast(), trackId, startTime);
      malloc.free(pathPtr);

      if (clipId < 0) {
        return -1;
      }

      return clipId;
    } catch (e) {
      rethrow;
    }
  }

  /// Start playback
  String transportPlay() {
    try {
      final resultPtr = _transportPlay();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Pause playback
  String transportPause() {
    try {
      final resultPtr = _transportPause();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Stop playback
  String transportStop() {
    try {
      final resultPtr = _transportStop();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Seek to position in seconds
  String transportSeek(double positionSeconds) {
    try {
      final resultPtr = _transportSeek(positionSeconds);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Get current playhead position in seconds
  double getPlayheadPosition() {
    try {
      return _getPlayheadPosition();
    } catch (e) {
      return 0.0;
    }
  }

  /// Get transport state (0=Stopped, 1=Playing, 2=Paused)
  int getTransportState() {
    try {
      return _getTransportState();
    } catch (e) {
      return 0;
    }
  }

  /// Get position when Play was pressed (in seconds)
  double getPlayStartPosition() {
    try {
      return _getPlayStartPosition();
    } catch (e) {
      return 0.0;
    }
  }

  /// Set position when Play was pressed (in seconds)
  String setPlayStartPosition(double positionSeconds) {
    try {
      final resultPtr = _setPlayStartPosition(positionSeconds);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Get position when recording started (after count-in, in seconds)
  double getRecordStartPosition() {
    try {
      return _getRecordStartPosition();
    } catch (e) {
      return 0.0;
    }
  }

  /// Set position when recording started (after count-in, in seconds)
  String setRecordStartPosition(double positionSeconds) {
    try {
      final resultPtr = _setRecordStartPosition(positionSeconds);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
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

  /// Get current buffer size preset (0-4)
  int getBufferSizePreset() {
    try {
      return _getBufferSizePreset();
    } catch (e) {
      return 2; // Default to Balanced
    }
  }

  /// Get actual buffer size in samples
  int getActualBufferSize() {
    try {
      return _getActualBufferSize();
    } catch (e) {
      return 256;
    }
  }

  /// Get audio latency info
  /// Returns: {bufferSize, inputLatencyMs, outputLatencyMs, roundtripMs}
  Map<String, double> getLatencyInfo() {
    final bufferSizePtr = calloc<ffi.Uint32>();
    final inputLatencyPtr = calloc<ffi.Float>();
    final outputLatencyPtr = calloc<ffi.Float>();
    final roundtripPtr = calloc<ffi.Float>();

    try {
      _getLatencyInfo(bufferSizePtr, inputLatencyPtr, outputLatencyPtr, roundtripPtr);

      return {
        'bufferSize': bufferSizePtr.value.toDouble(),
        'inputLatencyMs': inputLatencyPtr.value,
        'outputLatencyMs': outputLatencyPtr.value,
        'roundtripMs': roundtripPtr.value,
      };
    } catch (e) {
      return {
        'bufferSize': 256,
        'inputLatencyMs': 5.3,
        'outputLatencyMs': 5.3,
        'roundtripMs': 10.7,
      };
    } finally {
      calloc.free(bufferSizePtr);
      calloc.free(inputLatencyPtr);
      calloc.free(outputLatencyPtr);
      calloc.free(roundtripPtr);
    }
  }

  // ============================================================================
  // LATENCY TEST
  // ============================================================================

  /// Start latency test to measure real round-trip audio latency
  /// Requires audio input connected to output (loopback)
  String startLatencyTest() {
    final resultPtr = _startLatencyTest();
    try {
      return resultPtr.toDartString();
    } finally {
      _freeRustString(resultPtr);
    }
  }

  /// Stop/cancel the latency test
  String stopLatencyTest() {
    final resultPtr = _stopLatencyTest();
    try {
      return resultPtr.toDartString();
    } finally {
      _freeRustString(resultPtr);
    }
  }

  /// Get latency test status
  /// Returns: (state, resultMs)
  /// State: 0=Idle, 1=WaitingForSilence, 2=Playing, 3=Listening, 4=Analyzing, 5=Done, 6=Error
  /// Result: latency in ms (or -1.0 if not available)
  (int, double) getLatencyTestStatus() {
    final statePtr = calloc<ffi.Int32>();
    final resultPtr = calloc<ffi.Float>();

    try {
      _getLatencyTestStatus(statePtr, resultPtr);
      return (statePtr.value, resultPtr.value);
    } catch (e) {
      return (0, -1.0);
    } finally {
      calloc.free(statePtr);
      calloc.free(resultPtr);
    }
  }

  /// Get latency test error message (if state is Error)
  String? getLatencyTestError() {
    final resultPtr = _getLatencyTestError();
    if (resultPtr == ffi.nullptr) {
      return null;
    }
    try {
      return resultPtr.toDartString();
    } finally {
      _freeRustString(resultPtr);
    }
  }

  /// Run a latency test asynchronously
  /// Returns the measured latency in ms, or null if the test failed
  Future<double?> runLatencyTest({
    Duration timeout = const Duration(seconds: 5),
    Duration pollInterval = const Duration(milliseconds: 100),
  }) async {
    // Start the test
    startLatencyTest();

    final endTime = DateTime.now().add(timeout);

    // Poll for completion
    while (DateTime.now().isBefore(endTime)) {
      await Future.delayed(pollInterval);

      final (state, result) = getLatencyTestStatus();

      if (state == latencyTestStateDone) {
        return result;
      }

      if (state == latencyTestStateError) {
        return null;
      }

      if (state == latencyTestStateIdle) {
        // Test was stopped
        return null;
      }
    }

    // Timeout - stop the test
    stopLatencyTest();
    return null;
  }

  /// Get clip duration in seconds
  double getClipDuration(int clipId) {
    try {
      return _getClipDuration(clipId);
    } catch (e) {
      return 0.0;
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
  /// warpMode: 0 = warp (pitch preserved), 1 = repitch (pitch follows speed)
  String setAudioClipWarp(int trackId, int clipId, bool warpEnabled, double stretchFactor, int warpMode) {
    try {
      final result = _setAudioClipWarp(trackId, clipId, warpEnabled, stretchFactor, warpMode);
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
  String setAudioClipTranspose(int trackId, int clipId, int semitones, int cents) {
    try {
      final result = _setAudioClipTranspose(trackId, clipId, semitones, cents);
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
