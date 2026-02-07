part of 'audio_engine_native.dart';

mixin _PluginsMixin on _AudioEngineBase {
  // ========================================================================
  // M5 API - Save/Load Project
  // ========================================================================

  /// Save project to .audio folder
  String saveProject(String projectName, String projectPath) {
    try {
      final namePtr = projectName.toNativeUtf8();
      final pathPtr = projectPath.toNativeUtf8();
      final resultPtr = _saveProject(namePtr.cast(), pathPtr.cast());
      malloc.free(namePtr);
      malloc.free(pathPtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Load project from .audio folder
  String loadProject(String projectPath) {
    try {
      final pathPtr = projectPath.toNativeUtf8();
      final resultPtr = _loadProject(pathPtr.cast());
      malloc.free(pathPtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Export project to WAV file (legacy method - uses 32-bit float, 48kHz)
  String exportToWav(String outputPath, {required bool normalize}) {
    try {
      final pathPtr = outputPath.toNativeUtf8();
      final resultPtr = _exportToWav(pathPtr.cast(), normalize);
      malloc.free(pathPtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  // ========================================================================
  // M8 API - Enhanced Export
  // ========================================================================

  /// Check if ffmpeg is available for MP3 encoding
  bool isFfmpegAvailable() {
    return _isFfmpegAvailable() == 1;
  }

  /// Export audio with generic JSON options
  /// Returns JSON string with ExportResult on success
  String exportAudio(String outputPath, String optionsJson) {
    try {
      final pathPtr = outputPath.toNativeUtf8();
      final optionsPtr = optionsJson.toNativeUtf8();
      final resultPtr = _exportAudio(pathPtr.cast(), optionsPtr.cast());
      malloc.free(pathPtr);
      malloc.free(optionsPtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.startsWith('Error:')) {
        throw Exception(result);
      }

      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Export WAV with configurable options
  /// bitDepth: 16, 24, or 32 (float)
  /// sampleRate: 44100 or 48000
  /// Returns JSON string with ExportResult on success
  String exportWavWithOptions({
    required String outputPath,
    int bitDepth = 16,
    int sampleRate = 44100,
    bool normalize = false,
    bool dither = false,
    bool mono = false,
  }) {
    try {
      final pathPtr = outputPath.toNativeUtf8();
      final resultPtr = _exportWavWithOptions(
        pathPtr.cast(),
        bitDepth,
        sampleRate,
        normalize,
        dither,
        mono,
      );
      malloc.free(pathPtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.startsWith('Error:')) {
        throw Exception(result);
      }

      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Export MP3 with configurable options
  /// bitrate: 128, 192, or 320 kbps
  /// sampleRate: 44100 or 48000
  /// Returns JSON string with ExportResult on success
  String exportMp3WithOptions({
    required String outputPath,
    int bitrate = 320,
    int sampleRate = 44100,
    bool normalize = false,
    bool mono = false,
  }) {
    try {
      final pathPtr = outputPath.toNativeUtf8();
      final resultPtr = _exportMp3WithOptions(
        pathPtr.cast(),
        bitrate,
        sampleRate,
        normalize,
        mono,
      );
      malloc.free(pathPtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.startsWith('Error:')) {
        throw Exception(result);
      }

      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Write ID3 metadata to an MP3 file
  /// metadataJson: JSON string with title, artist, album, year, genre, etc.
  String writeMp3Metadata(String filePath, String metadataJson) {
    try {
      final pathPtr = filePath.toNativeUtf8();
      final metadataPtr = metadataJson.toNativeUtf8();
      final resultPtr = _writeMp3Metadata(pathPtr.cast(), metadataPtr.cast());
      malloc.free(pathPtr);
      malloc.free(metadataPtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.startsWith('Error:')) {
        throw Exception(result);
      }

      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Get tracks available for stem export
  /// Returns JSON array of {id, name, type} objects
  String getTracksForStems() {
    try {
      final resultPtr = _getTracksForStems();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.startsWith('Error:')) {
        throw Exception(result);
      }

      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Export stems (individual tracks) to a directory
  /// outputDir: Directory to export stems to
  /// baseName: Base filename for stems (e.g., "My Song")
  /// trackIdsJson: JSON array of track IDs to export, or empty string for all tracks
  /// optionsJson: JSON string of ExportOptions
  /// Returns JSON string with StemExportResult on success
  String exportStems({
    required String outputDir,
    required String baseName,
    String trackIdsJson = '',
    required String optionsJson,
  }) {
    try {
      final dirPtr = outputDir.toNativeUtf8();
      final namePtr = baseName.toNativeUtf8();
      final trackIdsPtr = trackIdsJson.toNativeUtf8();
      final optionsPtr = optionsJson.toNativeUtf8();

      final resultPtr = _exportStems(
        dirPtr.cast(),
        namePtr.cast(),
        trackIdsPtr.cast(),
        optionsPtr.cast(),
      );

      malloc.free(dirPtr);
      malloc.free(namePtr);
      malloc.free(trackIdsPtr);
      malloc.free(optionsPtr);

      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.startsWith('Error:')) {
        throw Exception(result);
      }

      return result;
    } catch (e) {
      rethrow;
    }
  }

  // ========================================================================
  // M8 API - Export Progress
  // ========================================================================

  /// Get current export progress as JSON
  /// Returns: {"progress": 0-100, "is_running": bool, "is_cancelled": bool, "status": string, "error": string|null}
  String getExportProgress() {
    try {
      final resultPtr = _getExportProgress();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return '{"progress": 0, "is_running": false, "is_cancelled": false, "status": "", "error": "Failed to get progress: $e"}';
    }
  }

  /// Cancel the current export operation
  void cancelExport() {
    try {
      _cancelExport();
    } catch (e) {
      // FFI cleanup - ignore errors silently
    }
  }

  /// Reset export progress state (call before starting a new export)
  void resetExportProgress() {
    try {
      _resetExportProgress();
    } catch (e) {
      // FFI cleanup - ignore errors silently
    }
  }

  // ========================================================================
  // M6 API - Per-track Synthesizer
  // ========================================================================

  /// Set the instrument for a track
  /// Returns the instrument ID or -1 on error
  int setTrackInstrument(int trackId, String instrumentType) {
    try {
      final typePtr = instrumentType.toNativeUtf8();
      final instrumentId = _setTrackInstrument(trackId, typePtr.cast());
      malloc.free(typePtr);

      if (instrumentId < 0) {
        return -1;
      }

      return instrumentId;
    } catch (e) {
      rethrow;
    }
  }

  /// Set a synthesizer parameter for a track
  /// paramName: parameter name (e.g., 'osc1_type', 'filter_cutoff')
  /// value: parameter value (will be converted to string)
  String setSynthParameter(int trackId, String paramName, dynamic value) {
    try {
      final namePtr = paramName.toNativeUtf8();
      final valueStr = value.toString();
      final valuePtr = valueStr.toNativeUtf8();
      final resultPtr = _setSynthParameter(trackId, namePtr.cast(), valuePtr.cast());
      malloc.free(namePtr);
      malloc.free(valuePtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Get all synthesizer parameters for a track
  /// Returns a comma-separated string of key:value pairs
  String getSynthParameters(int trackId) {
    try {
      final resultPtr = _getSynthParameters(trackId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Send MIDI note on to a specific track's instrument
  /// trackId: the track to send MIDI to
  /// note: MIDI note number (0-127)
  /// velocity: MIDI velocity (0-127)
  String sendTrackMidiNoteOn(int trackId, int note, int velocity) {
    try {
      final resultPtr = _sendTrackMidiNoteOn(trackId, note, velocity);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Send MIDI note off to a specific track's instrument
  /// trackId: the track to send MIDI to
  /// note: MIDI note number (0-127)
  /// velocity: MIDI velocity (0-127)
  String sendTrackMidiNoteOff(int trackId, int note, int velocity) {
    try {
      final resultPtr = _sendTrackMidiNoteOff(trackId, note, velocity);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  // ========================================================================
  // SAMPLER API
  // ========================================================================

  /// Create a sampler instrument for a track
  /// Returns instrument ID on success, or -1 on error
  int createSamplerForTrack(int trackId) {
    try {
      return _createSamplerForTrack(trackId);
    } catch (e) {
      rethrow;
    }
  }

  /// Load a sample file into a sampler track
  /// trackId: the sampler track to load the sample into
  /// path: path to the audio file
  /// rootNote: MIDI note that plays sample at original pitch (default 60 = C4)
  /// Returns true on success
  bool loadSampleForTrack(int trackId, String path, int rootNote) {
    final pathPtr = path.toNativeUtf8();
    try {
      final result = _loadSampleForTrack(trackId, pathPtr.cast(), rootNote);
      return result == 1;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Set sampler parameter for a track
  /// param: "root_note", "attack", "attack_ms", "release", "release_ms"
  /// value: parameter value as string
  String setSamplerParameter(int trackId, String param, String value) {
    final paramPtr = param.toNativeUtf8();
    final valuePtr = value.toNativeUtf8();
    try {
      final resultPtr = _setSamplerParameter(trackId, paramPtr.cast(), valuePtr.cast());
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } finally {
      calloc.free(paramPtr);
      calloc.free(valuePtr);
    }
  }

  /// Check if a track has a sampler instrument
  /// Returns true if track is a sampler, false otherwise
  bool isSamplerTrack(int trackId) {
    try {
      final result = _isSamplerTrack(trackId);
      return result == 1;
    } catch (e) {
      return false;
    }
  }

  // ========================================================================
  // M7 API - VST3 Plugin Hosting
  // ========================================================================

  /// Scan standard VST3 plugin locations
  /// Returns list of plugin info: name, path, vendor, type
  List<Map<String, String>> scanVst3PluginsStandard() {
    try {
      final resultPtr = _scanVst3PluginsStandard();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.isEmpty) {
        return [];
      }

      // Parse result: "PluginName|/path/to/plugin.vst3|Vendor|is_instrument|is_effect"
      final plugins = <Map<String, String>>[];
      for (final line in result.split('\n')) {
        if (line.isEmpty) continue;
        final parts = line.split('|');
        if (parts.length >= 5) {
          plugins.add({
            'name': parts[0],
            'path': parts[1],
            'vendor': parts[2],
            'is_instrument': parts[3],
            'is_effect': parts[4],
          });
        } else if (parts.length >= 2) {
          // Fallback for old format without type info
          plugins.add({
            'name': parts[0],
            'path': parts[1],
            'vendor': parts.length > 2 ? parts[2] : '',
            'is_instrument': '0',
            'is_effect': '1',
          });
        }
      }

      return plugins;
    } catch (e) {
      return [];
    }
  }

  /// Add a VST3 plugin to a track's FX chain
  /// Returns the effect ID (>= 0) or -1 on error
  int addVst3EffectToTrack(int trackId, String pluginPath) {
    try {
      final pathPtr = pluginPath.toNativeUtf8();
      final effectId = _addVst3EffectToTrack(trackId, pathPtr.cast());
      malloc.free(pathPtr);

      if (effectId < 0) {
        return -1;
      }

      return effectId;
    } catch (e) {
      return -1;
    }
  }

  /// Get the number of parameters in a VST3 plugin
  int getVst3ParameterCount(int effectId) {
    try {
      final count = _getVst3ParameterCount(effectId);
      if (count < 0) {
        return 0;
      }
      return count;
    } catch (e) {
      return 0;
    }
  }

  /// Get info about a VST3 parameter
  /// Returns map with keys: name, min, max, default
  Map<String, dynamic>? getVst3ParameterInfo(int effectId, int paramIndex) {
    try {
      final resultPtr = _getVst3ParameterInfo(effectId, paramIndex);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.isEmpty) {
        return null;
      }

      // Parse result: "name,0.0,1.0,0.5"
      final parts = result.split(',');
      if (parts.length >= 4) {
        return {
          'name': parts[0],
          'min': double.tryParse(parts[1]) ?? 0.0,
          'max': double.tryParse(parts[2]) ?? 1.0,
          'default': double.tryParse(parts[3]) ?? 0.5,
        };
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get a VST3 parameter value (normalized 0.0-1.0)
  double getVst3ParameterValue(int effectId, int paramIndex) {
    try {
      final value = _getVst3ParameterValue(effectId, paramIndex);
      return value;
    } catch (e) {
      return 0.0;
    }
  }

  /// Set a VST3 parameter value (normalized 0.0-1.0)
  bool setVst3ParameterValue(int effectId, int paramIndex, double value) {
    try {
      final resultPtr = _setVst3ParameterValue(effectId, paramIndex, value);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result.contains('Set VST3');
    } catch (e) {
      return false;
    }
  }

  // M7: VST3 Editor methods

  /// Check if a VST3 plugin has an editor GUI
  bool vst3HasEditor(int effectId) {
    try {
      return _vst3HasEditor(effectId);
    } catch (e) {
      return false;
    }
  }

  /// Open VST3 plugin editor (creates IPlugView)
  /// Returns error message or empty string on success
  String vst3OpenEditor(int effectId) {
    try {
      final resultPtr = _vst3OpenEditor(effectId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Failed to open editor: $e';
    }
  }

  /// Close VST3 plugin editor
  void vst3CloseEditor(int effectId) {
    try {
      _vst3CloseEditor(effectId);
    } catch (e) {
      // FFI cleanup - ignore errors silently
    }
  }

  /// Get VST3 editor size in pixels
  /// Returns map with 'width' and 'height' keys, or null on error
  Map<String, int>? vst3GetEditorSize(int effectId) {
    try {
      final resultPtr = _vst3GetEditorSize(effectId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.isEmpty || result.startsWith('Error')) {
        return null;
      }

      // Parse result: "width,height"
      final parts = result.split(',');
      if (parts.length == 2) {
        return {
          'width': int.tryParse(parts[0]) ?? 800,
          'height': int.tryParse(parts[1]) ?? 600,
        };
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Attach VST3 editor to a parent window
  /// parentPtr: Pointer to NSView (on macOS)
  /// Returns error message or empty string on success
  String vst3AttachEditor(int effectId, ffi.Pointer<ffi.Void> parentPtr) {
    try {
      final resultPtr = _vst3AttachEditor(effectId, parentPtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Failed to attach editor: $e';
    }
  }

  /// Send a MIDI note event to a VST3 plugin
  /// eventType: 0 = note on, 1 = note off
  /// channel: MIDI channel (0-15)
  /// note: MIDI note number (0-127)
  /// velocity: MIDI velocity (0-127)
  /// Returns error message or empty string on success
  String vst3SendMidiNote(int effectId, int eventType, int channel, int note, int velocity) {
    try {
      final resultPtr = _vst3SendMidiNote(effectId, eventType, channel, note, velocity);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Failed to send MIDI note: $e';
    }
  }

  // ========================================================================
  // Library Preview API
  // ========================================================================

  /// Load an audio file for library preview
  String previewLoadAudio(String path) {
    try {
      final pathPtr = path.toNativeUtf8().cast<ffi.Char>();
      final resultPtr = _previewLoadAudio(pathPtr);
      final result = resultPtr.toDartString();
      calloc.free(pathPtr);
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Start preview playback
  void previewPlay() {
    try {
      _previewPlay();
    } catch (e) {
      // Ignore errors
    }
  }

  /// Stop preview playback (with fade out)
  void previewStop() {
    try {
      _previewStop();
    } catch (e) {
      // Ignore errors
    }
  }

  /// Seek to position in seconds
  void previewSeek(double positionSeconds) {
    try {
      _previewSeek(positionSeconds);
    } catch (e) {
      // Ignore errors
    }
  }

  /// Get current playback position in seconds
  double previewGetPosition() {
    try {
      return _previewGetPosition();
    } catch (e) {
      return 0.0;
    }
  }

  /// Get total duration in seconds
  double previewGetDuration() {
    try {
      return _previewGetDuration();
    } catch (e) {
      return 0.0;
    }
  }

  /// Check if preview is currently playing
  bool previewIsPlaying() {
    try {
      return _previewIsPlaying();
    } catch (e) {
      return false;
    }
  }

  /// Set looping mode
  void previewSetLooping(bool shouldLoop) {
    try {
      _previewSetLooping(shouldLoop);
    } catch (e) {
      // Ignore errors
    }
  }

  /// Get looping mode
  bool previewIsLooping() {
    try {
      return _previewIsLooping();
    } catch (e) {
      return false;
    }
  }

  /// Get waveform peaks for UI display
  List<double> previewGetWaveform(int resolution) {
    try {
      final resultPtr = _previewGetWaveform(resolution);
      final jsonString = resultPtr.toDartString();
      _freeRustString(resultPtr);

      // Parse JSON array of floats
      if (jsonString.startsWith('[') && jsonString.endsWith(']')) {
        final content = jsonString.substring(1, jsonString.length - 1);
        if (content.isEmpty) return List.filled(resolution, 0.0);
        return content.split(',').map((s) => double.tryParse(s.trim()) ?? 0.0).toList();
      }
      return List.filled(resolution, 0.0);
    } catch (e) {
      return List.filled(resolution, 0.0);
    }
  }
}
