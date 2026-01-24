// Web implementation of AudioEngine using JS interop with WASM
// ignore_for_file: avoid_positional_boolean_parameters, avoid_print

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'services/commands/audio_engine_interface.dart';

/// JS interop for the Boojy WASM engine
@JS('window.boojyEngine')
external JSObject? get _boojyEngine;

@JS('window.boojyEngineReady')
external bool? get _boojyEngineReady;

/// Check if WASM engine is loaded
bool get isEngineReady => _boojyEngineReady == true && _boojyEngine != null;

/// Wait for WASM engine to be ready
Future<void> waitForEngine() async {
  while (!isEngineReady) {
    await Future.delayed(const Duration(milliseconds: 50));
  }
}

/// Call a WASM function by name with no arguments
JSAny? _callEngine(String functionName) {
  if (!isEngineReady) return null;
  return _boojyEngine!.callMethod(functionName.toJS);
}

/// Call a WASM function with arguments
JSAny? _callEngineWith(String functionName, List<JSAny?> args) {
  if (!isEngineReady) return null;
  return _boojyEngine!.callMethodVarArgs(functionName.toJS, args);
}

/// JS String() function for converting BigInt to string
@JS('String')
external JSString _jsString(JSAny value);

/// JS Number() function for converting to number
@JS('Number')
external JSNumber _jsNumber(JSAny value);

/// Safely convert a JS value to Dart int
/// Handles both JSNumber and JavaScriptBigInt from WASM
int _jsToInt(JSAny? value) {
  if (value == null) return -1;
  try {
    if (value.isA<JSNumber>()) {
      return (value as JSNumber).toDartInt;
    }
    // Handle BigInt by converting via JS String() function
    if (value.isA<JSBigInt>()) {
      final bigIntStr = _jsString(value).toDart;
      return int.tryParse(bigIntStr) ?? -1;
    }
    // Try Number() as fallback for any other type
    final num = _jsNumber(value).toDartDouble;
    return num.toInt();
  } catch (e) {
    print('_jsToInt error: $e for ${value.runtimeType}');
    return -1;
  }
}

/// Safely convert a JS value to Dart double
/// Handles both JSNumber and JavaScriptBigInt from WASM
double _jsToDouble(JSAny? value) {
  if (value == null) return 0.0;
  if (value.isA<JSNumber>()) {
    return (value as JSNumber).toDartDouble;
  }
  // Handle BigInt by converting via JS String() function
  if (value.isA<JSBigInt>()) {
    final bigIntStr = _jsString(value).toDart;
    return double.tryParse(bigIntStr) ?? 0.0;
  }
  return 0.0;
}

/// JS BigInt constructor binding
@JS('BigInt')
external JSBigInt _jsBigInt(JSAny value);

/// Convert Dart int to JS BigInt (for WASM i64 parameters)
JSBigInt _intToBigInt(int value) {
  return _jsBigInt(value.toJS);
}

// ============================================================================
// Web Audio API Synth - Direct JavaScript implementation for audio playback
// ============================================================================

/// Access window.boojySynth for our JavaScript synth
@JS('window.boojySynth')
external JSObject? get _boojySynth;

/// Initialize the JavaScript synth (called once)
void _initWebSynth() {
  // Create a simple polyphonic synth using Web Audio API
  // This is injected into the page for immediate audio feedback
  const script = '''
    if (!window.boojySynth) {
      window.boojySynth = {
        audioContext: null,
        masterGain: null,
        activeNotes: new Map(),

        init: function() {
          if (this.audioContext) return;
          this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
          this.masterGain = this.audioContext.createGain();
          this.masterGain.gain.value = 0.5;
          this.masterGain.connect(this.audioContext.destination);
          console.log('Web Synth initialized');
        },

        resume: function() {
          if (this.audioContext && this.audioContext.state === 'suspended') {
            this.audioContext.resume();
          }
        },

        noteOn: function(note, velocity) {
          this.init();
          this.resume();

          // Stop existing note if playing
          this.noteOff(note);

          const freq = 440 * Math.pow(2, (note - 69) / 12);
          const osc = this.audioContext.createOscillator();
          const gain = this.audioContext.createGain();

          osc.type = 'sawtooth';
          osc.frequency.value = freq;

          // ADSR envelope
          const now = this.audioContext.currentTime;
          const vel = velocity / 127;
          gain.gain.setValueAtTime(0, now);
          gain.gain.linearRampToValueAtTime(vel * 0.3, now + 0.01); // Attack
          gain.gain.linearRampToValueAtTime(vel * 0.2, now + 0.1);  // Decay to sustain

          osc.connect(gain);
          gain.connect(this.masterGain);
          osc.start();

          this.activeNotes.set(note, { osc: osc, gain: gain });
        },

        noteOff: function(note) {
          const noteData = this.activeNotes.get(note);
          if (noteData) {
            const now = this.audioContext.currentTime;
            noteData.gain.gain.cancelScheduledValues(now);
            noteData.gain.gain.setValueAtTime(noteData.gain.gain.value, now);
            noteData.gain.gain.linearRampToValueAtTime(0, now + 0.1); // Release
            noteData.osc.stop(now + 0.15);
            this.activeNotes.delete(note);
          }
        },

        setVolume: function(vol) {
          if (this.masterGain) {
            this.masterGain.gain.value = vol;
          }
        }
      };
    }
  ''';

  // Execute the script
  globalContext.callMethod('eval'.toJS, script.toJS);
}

/// Play a note using the web synth
void _webSynthNoteOn(int note, int velocity) {
  _initWebSynth();
  if (_boojySynth != null) {
    _boojySynth!.callMethodVarArgs('noteOn'.toJS, [note.toJS, velocity.toJS]);
  }
}

/// Stop a note using the web synth
void _webSynthNoteOff(int note) {
  if (_boojySynth != null) {
    _boojySynth!.callMethodVarArgs('noteOff'.toJS, [note.toJS]);
  }
}

/// Resume audio context (required after user interaction)
void _webSynthResume() {
  _initWebSynth();
  if (_boojySynth != null) {
    _boojySynth!.callMethod('resume'.toJS);
  }
}

/// Buffer size presets (matching native)
const Map<int, String> bufferSizePresets = {
  0: 'Lowest (64 samples)',
  1: 'Low (128 samples)',
  2: 'Balanced (256 samples)',
  3: 'Safe (512 samples)',
  4: 'High Stability (1024 samples)',
};

/// Web implementation of AudioEngine using WASM
/// Named `AudioEngine` to match native implementation for drop-in replacement
class AudioEngine implements AudioEngineInterface {
  AudioEngine();

  /// Buffer size presets (matching native)
  static const Map<int, String> bufferSizePresets = {
    0: 'Lowest (64 samples)',
    1: 'Low (128 samples)',
    2: 'Balanced (256 samples)',
    3: 'Safe (512 samples)',
    4: 'High Stability (1024 samples)',
  };

  // ============================================================================
  // Initialization
  // ============================================================================

  String initAudioEngine() {
    return 'Web Audio Engine initialized';
  }

  Future<String> initAudioGraph() async {
    await waitForEngine();
    try {
      final result = _callEngine('init_audio_graph');
      return (result as JSString?)?.toDart ?? 'Initialized';
    } catch (e) {
      return 'Error: $e';
    }
  }

  Future<void> resumeAudioContext() async {
    // Resume both WASM audio context and web synth
    _webSynthResume();
    if (!isEngineReady) return;
    _callEngine('resume_audio_context');
  }

  // ============================================================================
  // Transport Controls
  // ============================================================================

  String transportPlay() {
    // Resume audio context on play (browser autoplay policy)
    _webSynthResume();
    final result = _callEngine('transport_play');
    return (result as JSString?)?.toDart ?? 'Playing';
  }

  String transportPause() {
    final result = _callEngine('transport_pause');
    return (result as JSString?)?.toDart ?? 'Paused';
  }

  String transportStop() {
    final result = _callEngine('transport_stop');
    return (result as JSString?)?.toDart ?? 'Stopped';
  }

  String transportSeek(double positionSeconds) {
    final result = _callEngineWith('transport_seek', [positionSeconds.toJS]);
    return (result as JSString?)?.toDart ?? 'Seeked';
  }

  double getPlayheadPosition() {
    final result = _callEngine('get_playhead_position');
    return _jsToDouble(result);
  }

  int getTransportState() {
    final result = _callEngine('get_transport_state');
    final state = _jsToInt(result);
    return state >= 0 ? state : 0; // Default to stopped state
  }

  // ============================================================================
  // Latency / Buffer (Web has different latency model)
  // ============================================================================

  String setBufferSize(int preset) {
    // Web Audio API handles buffering automatically
    return 'Buffer size not configurable on web';
  }

  int getBufferSizePreset() => 2; // Return "Balanced" as default

  int getActualBufferSize() => 256; // Default web buffer

  /// Returns latency info as a map matching native API
  Map<String, double> getLatencyInfo() {
    // Web Audio typically has ~100-200ms latency
    return {
      'bufferSize': 256,
      'inputLatencyMs': 50.0,
      'outputLatencyMs': 100.0,
      'roundtripMs': 150.0,
    };
  }

  String startLatencyTest() => 'Latency test not available on web';
  String stopLatencyTest() => 'Latency test not available on web';

  // ============================================================================
  // Audio File Loading
  // ============================================================================

  int loadAudioFile(String path) {
    // Web can't load from file paths - use loadAudioData instead
    return -1;
  }

  @override
  int loadAudioFileToTrack(String filePath, int trackId, {double startTime = 0.0}) {
    // Web can't load from file paths - use loadAudioData instead
    return -1;
  }

  int loadAudioData(List<int> data, String name, int trackId, double startTime) {
    // TODO: Implement proper byte array passing to WASM
    return -1;
  }

  @override
  double getClipDuration(int clipId) => 0.0;

  @override
  List<double> getWaveformPeaks(int clipId, int resolution) => [];

  @override
  void setClipStartTime(int trackId, int clipId, double startTime) {}

  @override
  String setAudioClipGain(int trackId, int clipId, double gainDb) => 'OK';

  @override
  String setAudioClipWarp(int trackId, int clipId, bool warpEnabled, double stretchFactor, int warpMode) => 'OK';

  @override
  String setAudioClipTranspose(int trackId, int clipId, int semitones, int cents) => 'OK';

  @override
  void removeAudioClip(int trackId, int clipId) {}

  @override
  int duplicateAudioClip(int trackId, int clipId, double startTime) => -1;

  // ============================================================================
  // Recording (Limited on web due to getUserMedia requirements)
  // ============================================================================

  String startRecording() => 'Recording not yet implemented on web';
  int stopRecording() => -1;
  int getRecordingState() => 0; // Not recording
  double getRecordedDuration() => 0.0;
  List<double> getRecordingWaveform(int resolution) => [];

  @override
  void setCountInBars(int bars) {}
  int getCountInBars() => 0;

  @override
  void setTempo(double bpm) {
    _callEngineWith('set_tempo', [bpm.toJS]);
  }

  double getTempo() {
    final result = _callEngine('get_tempo');
    final tempo = _jsToDouble(result);
    return tempo > 0 ? tempo : 120.0;
  }

  String setMetronomeEnabled({required bool enabled}) {
    return enabled ? 'Metronome enabled' : 'Metronome disabled';
  }

  bool isMetronomeEnabled() => false;

  // ============================================================================
  // MIDI
  // ============================================================================

  String startMidiInput() => 'MIDI input started';
  String stopMidiInput() => 'MIDI input stopped';

  String setSynthOscillatorType(int oscType) => 'OK';
  String setSynthVolume(double volume) => 'OK';

  String sendMidiNoteOn(int note, int velocity) {
    // Use web synth for immediate audio feedback
    _webSynthNoteOn(note, velocity);
    _callEngineWith('send_midi_note_on', [_intToBigInt(0), note.toJS, velocity.toJS]);
    return 'OK';
  }

  String sendMidiNoteOff(int note, int velocity) {
    // Use web synth for immediate audio feedback
    _webSynthNoteOff(note);
    _callEngineWith('send_midi_note_off', [_intToBigInt(0), note.toJS]);
    return 'OK';
  }

  String sendTrackMidiNoteOn(int trackId, int note, int velocity) {
    // Use web synth for immediate audio feedback
    _webSynthNoteOn(note, velocity);
    _callEngineWith('send_midi_note_on', [_intToBigInt(trackId), note.toJS, velocity.toJS]);
    return 'OK';
  }

  String sendTrackMidiNoteOff(int trackId, int note, int velocity) {
    // Use web synth for immediate audio feedback
    _webSynthNoteOff(note);
    _callEngineWith('send_midi_note_off', [_intToBigInt(trackId), note.toJS]);
    return 'OK';
  }

  @override
  int createMidiClip() => -1;

  @override
  String addMidiNoteToClip(int clipId, int note, int velocity, double startTime, double duration) {
    return 'OK';
  }

  @override
  int addMidiClipToTrack(int trackId, int clipId, double startTimeSeconds) => -1;
  int removeMidiClip(int trackId, int clipId) => 0;
  String clearMidiClip(int clipId) => 'OK';

  /// Get available MIDI input devices (empty on web)
  List<Map<String, dynamic>> getMidiInputDevices() => []; // Web MIDI API would be needed
  String selectMidiInputDevice(int deviceIndex) => 'OK';
  String refreshMidiDevices() => 'OK';

  String startMidiRecording() => 'Not implemented';
  int stopMidiRecording() => -1;
  int getMidiRecordingState() => 0;
  String quantizeMidiClip(int clipId, int gridDivision) => 'OK';
  String getMidiClipInfo(int clipId) => '{}';
  String getAllMidiClipsInfo() => '[]';
  String getMidiClipNotes(int clipId) => '[]';

  // ============================================================================
  // Audio Device Selection (Web uses system default)
  // ============================================================================

  /// Get available audio input devices (empty on web)
  List<Map<String, dynamic>> getAudioInputDevices() => [];
  String setAudioInputDevice(int deviceIndex) => 'OK';

  /// Get available audio output devices (empty on web)
  List<Map<String, dynamic>> getAudioOutputDevices() => [];
  String setAudioOutputDevice(String deviceName) => 'OK';
  String getSelectedAudioOutputDevice() => 'Default';
  int getSampleRate() => 48000;

  // ============================================================================
  // Track Management
  // ============================================================================

  // Track ID counter for web (since WASM may not provide real IDs yet)
  static int _nextTrackId = 1;

  @override
  int createTrack(String trackType, String name) {
    try {
      final result = _callEngineWith('create_track', [name.toJS]);
      final trackId = _jsToInt(result);
      print('createTrack($trackType, $name) => $trackId (raw: ${result?.runtimeType})');

      // If WASM returned a valid ID, use it
      if (trackId > 0) {
        // Keep our counter in sync
        if (trackId >= _nextTrackId) {
          _nextTrackId = trackId + 1;
        }
        return trackId;
      }

      // Fallback: generate our own ID if WASM fails or returns invalid
      final fallbackId = _nextTrackId++;
      print('createTrack fallback: using generated ID $fallbackId');
      return fallbackId;
    } catch (e) {
      print('createTrack error: $e');
      // Fallback on error
      return _nextTrackId++;
    }
  }

  @override
  void setTrackVolume(int trackId, double volumeDb) {
    final linear = volumeDb <= -60 ? 0.0 : (volumeDb / 60.0 + 1.0).clamp(0.0, 1.0);
    _callEngineWith('set_track_volume', [_intToBigInt(trackId), linear.toJS]);
  }

  @override
  void setTrackVolumeAutomation(int trackId, String csvData) {
    // Web implementation stub - automation not yet supported on web
  }

  @override
  void setTrackPan(int trackId, double pan) {
    _callEngineWith('set_track_pan', [_intToBigInt(trackId), pan.toJS]);
  }

  @override
  void setTrackMute(int trackId, {required bool mute}) {
    _callEngineWith('set_track_mute', [_intToBigInt(trackId), mute.toJS]);
  }

  @override
  void setTrackSolo(int trackId, {required bool solo}) {
    _callEngineWith('set_track_solo', [_intToBigInt(trackId), solo.toJS]);
  }

  @override
  void setTrackArmed(int trackId, {required bool armed}) {}

  @override
  void setTrackName(int trackId, String name) {}

  int getTrackCount() => 0;
  List<int> getAllTrackIds() => [];

  @override
  String getTrackInfo(int trackId) => '{}';

  String getTrackPeakLevels(int trackId) => '{"left": 0.0, "right": 0.0}';

  @override
  void deleteTrack(int trackId) {
    _callEngineWith('delete_track', [_intToBigInt(trackId)]);
  }

  @override
  int duplicateTrack(int trackId) => -1;

  String clearAllTracks() => 'OK';

  // ============================================================================
  // Per-Track Synth
  // ============================================================================

  String setTrackInstrument(int trackId, String instrumentType) => 'OK';
  String setSynthParameter(int trackId, String paramName, double value) => 'OK';
  String getSynthParameters(int trackId) => '{}';

  // ============================================================================
  // Effects
  // ============================================================================

  @override
  int addEffectToTrack(int trackId, String effectType) => -1;

  @override
  void removeEffectFromTrack(int trackId, int effectId) {}

  String getTrackEffects(int trackId) => '[]';
  String getEffectInfo(int effectId) => '{}';
  String setEffectParameter(int effectId, String paramName, double value) => 'OK';

  @override
  void setEffectBypass(int effectId, {required bool bypassed}) {}

  bool getEffectBypass(int effectId) => false;

  @override
  void reorderTrackEffects(int trackId, List<int> effectIds) {}

  // ============================================================================
  // VST3 (Not supported on web)
  // ============================================================================

  @override
  int addVst3EffectToTrack(int trackId, String effectPath) => -1;

  List<Map<String, String>> scanVst3PluginsStandard() => [];
  int getVst3ParameterCount(int effectId) => 0;
  /// Get info about a VST3 parameter (returns null on web)
  Map<String, dynamic>? getVst3ParameterInfo(int effectId, int paramIndex) => null;
  double getVst3ParameterValue(int effectId, int paramIndex) => 0.0;

  @override
  void setVst3ParameterValue(int effectId, int paramIndex, double value) {}

  // ============================================================================
  // Sampler API (stubs for web - not yet implemented)
  // ============================================================================

  @override
  int createSamplerForTrack(int trackId) => -1;

  @override
  bool loadSampleForTrack(int trackId, String path, int rootNote) => false;

  @override
  String setSamplerParameter(int trackId, String param, String value) =>
      'Not supported on web';

  @override
  bool isSamplerTrack(int trackId) => false;

  bool vst3HasEditor(int effectId) => false;
  String vst3OpenEditor(int effectId) => 'Not supported';
  String vst3CloseEditor(int effectId) => 'OK';
  Map<String, int>? vst3GetEditorSize(int effectId) => {'width': 0, 'height': 0};
  // vst3AttachEditor takes a pointer on native - stub for web
  String vst3AttachEditor(int effectId, dynamic viewPtr) => 'Not supported';
  /// Send a MIDI note event to a VST3 plugin
  /// eventType: 0 = note on, 1 = note off
  String vst3SendMidiNote(int effectId, int eventType, int channel, int note, int velocity) => 'OK';

  // ============================================================================
  // Project Save/Load
  // ============================================================================

  String saveProject(String projectName, String projectPath) {
    final result = _callEngine('save_project_to_json');
    return (result as JSString?)?.toDart ?? '{}';
  }

  String loadProject(String projectPath) {
    return 'Load not implemented - use loadProjectFromJson';
  }

  String loadProjectFromJson(String json) {
    final result = _callEngineWith('load_project_from_json', [json.toJS]);
    return (result as JSString?)?.toDart ?? 'Loaded';
  }

  // ============================================================================
  // Export (Limited on web)
  // ============================================================================

  String exportToWav(String outputPath, {required bool normalize}) {
    return 'Export not yet implemented on web';
  }

  bool isFfmpegAvailable() => false;

  String exportAudio(String outputPath, String optionsJson) {
    return 'Export not yet implemented on web';
  }

  /// Export WAV with configurable options (named parameters to match native)
  String exportWavWithOptions({
    required String outputPath,
    int bitDepth = 16,
    int sampleRate = 44100,
    bool normalize = false,
    bool dither = false,
    bool mono = false,
  }) {
    return 'Export not yet implemented on web';
  }

  /// Export MP3 with configurable options (named parameters to match native)
  String exportMp3WithOptions({
    required String outputPath,
    int bitrate = 320,
    int sampleRate = 44100,
    bool normalize = false,
    bool mono = false,
  }) {
    return 'MP3 export not available on web';
  }

  String writeMp3Metadata(String mp3Path, String metadataJson) {
    return 'Not available on web';
  }

  String getTracksForStems() => '[]';
  /// Export stems (named parameters to match native)
  String exportStems({
    required String outputDir,
    required String baseName,
    String trackIdsJson = '',
    required String optionsJson,
  }) => 'Not available on web';

  /// Get current export progress as JSON
  String getExportProgress() => '{"progress": 0, "is_running": false, "is_cancelled": false, "status": "", "error": null}';
  void cancelExport() {}
  void resetExportProgress() {}

  // ============================================================================
  // Utility
  // ============================================================================

  String getEngineVersion() {
    final result = _callEngine('get_engine_version');
    return (result as JSString?)?.toDart ?? 'web-0.1.0';
  }

  bool isAudioInitialized() {
    final result = _callEngine('is_audio_initialized');
    return (result as JSBoolean?)?.toDart ?? false;
  }

  void setMasterVolume(double volume) {
    _callEngineWith('set_master_volume', [volume.toJS]);
  }

  static bool get isSupported => true;
  static bool get isWebAudioAvailable => true;
}
