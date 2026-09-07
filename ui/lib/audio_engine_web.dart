// Web implementation of AudioEngine using JS interop with WASM
// ignore_for_file: avoid_positional_boolean_parameters, avoid_print

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart' show rootBundle;

import 'models/drum_kit_info.dart';
import 'models/sampler_info.dart';
import 'services/commands/audio_engine_interface.dart';
import 'utils/logger.dart';

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
        },

        // Dedicated metronome click: short oscillator burst, no MIDI note.
        // accent=true → higher pitch + louder (beat 1 of bar).
        click: function(accent) {
          this.init();
          this.resume();
          const ctx = this.audioContext;
          const osc = ctx.createOscillator();
          const gain = ctx.createGain();
          osc.type = 'triangle';
          osc.frequency.value = accent ? 1700 : 1200;
          const now = ctx.currentTime;
          const vol = accent ? 0.8 : 0.5;
          gain.gain.setValueAtTime(vol, now);
          gain.gain.exponentialRampToValueAtTime(0.001, now + 0.05);
          osc.connect(gain);
          gain.connect(this.masterGain);
          osc.start(now);
          osc.stop(now + 0.06);
        },

        // ── Library preview ──────────────────────────────────────────────
        previewBuffer: null,
        previewLoaded: false,
        previewLoading: false,
        previewSource: null,
        previewStartTime: null,
        previewSeekOffset: 0,
        previewLooping: false,

        // Load an audio asset for preview. bytes is a Uint8Array from Dart.
        previewLoad: function(bytes) {
          this.init();
          this.resume();
          this.previewLoaded = false;
          this.previewLoading = true;
          if (this.previewSource) {
            try { this.previewSource.stop(); } catch(e) {}
            this.previewSource = null;
            this.previewStartTime = null;
          }
          this.previewBuffer = null;
          this.previewSeekOffset = 0;
          const self = this;
          // Dart Uint8List.toJS may be a view; slice to get a standalone ArrayBuffer.
          const ab = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
          this.audioContext.decodeAudioData(ab).then(function(decoded) {
            self.previewBuffer = decoded;
            self.previewLoaded = true;
            self.previewLoading = false;
          }).catch(function(err) {
            console.error('Boojy preview decode error:', err);
            self.previewLoading = false;
          });
        },

        previewPlay: function() {
          if (!this.previewBuffer) return;
          if (this.previewSource) {
            try { this.previewSource.stop(); } catch(e) {}
            this.previewSource = null;
          }
          const src = this.audioContext.createBufferSource();
          src.buffer = this.previewBuffer;
          src.loop = this.previewLooping;
          src.connect(this.masterGain);
          src.start(0, this.previewSeekOffset);
          const self = this;
          this.previewSource = src;
          this.previewStartTime = this.audioContext.currentTime;
          src.onended = function() {
            if (self.previewSource === src) {
              self.previewSource = null;
              self.previewStartTime = null;
            }
          };
        },

        previewStop: function() {
          if (this.previewSource) {
            try { this.previewSource.stop(); } catch(e) {}
            this.previewSource = null;
            this.previewStartTime = null;
          }
        },

        // Seek to offset (seconds). If already playing, restarts from the new position.
        previewSeek: function(offset) {
          const wasPlaying = this.previewSource !== null;
          if (this.previewSource) {
            try { this.previewSource.stop(); } catch(e) {}
            this.previewSource = null;
            this.previewStartTime = null;
          }
          this.previewSeekOffset = offset;
          if (wasPlaying) { this.previewPlay(); }
        },

        previewGetPosition: function() {
          if (!this.previewSource || this.previewStartTime === null) return this.previewSeekOffset;
          const elapsed = this.audioContext.currentTime - this.previewStartTime;
          const dur = this.previewBuffer ? this.previewBuffer.duration : 0;
          return Math.min(this.previewSeekOffset + elapsed, dur);
        },

        previewIsPlaying: function() {
          return this.previewSource !== null;
        },

        previewGetDuration: function() {
          return this.previewBuffer ? this.previewBuffer.duration : 0;
        },

        // Returns a Float32Array of [resolution] peak values (0–1) from the waveform.
        previewGetWaveform: function(resolution) {
          if (!this.previewBuffer) return new Float32Array(resolution);
          const data = this.previewBuffer.getChannelData(0);
          const step = Math.max(1, Math.floor(data.length / resolution));
          const peaks = new Float32Array(resolution);
          for (let i = 0; i < resolution; i++) {
            let max = 0;
            const start = i * step;
            for (let j = 0; j < step && (start + j) < data.length; j++) {
              const v = Math.abs(data[start + j]);
              if (v > max) max = v;
            }
            peaks[i] = max;
          }
          return peaks;
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

/// Fire a metronome click via the dedicated Web Audio burst (not a MIDI note).
void _webSynthClick(bool accent) {
  _initWebSynth();
  if (_boojySynth != null) {
    _boojySynth!.callMethodVarArgs('click'.toJS, [accent.toJS]);
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

  String initAudioGraph() {
    // Clear static state so a fresh AudioEngine always starts with no stale tracks.
    _trackRegistry.clear();
    _nextTrackId = 1;
    // WASM loads asynchronously; engine calls fall back gracefully when not ready
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
  //
  // The WASM transport is a stub: get_playhead_position() returns raw
  // AudioContext.currentTime (absolute, monotonically increasing, never resets),
  // and transport_seek() is a no-op TODO. We track playback position entirely
  // in Dart using DateTime.now() as the wall clock.

  bool _isPlaying = false;
  double _seekPosition = 0.0;   // position requested by the last seek / start-of-play
  double _pausedPosition = 0.0; // position frozen when paused or stopped
  DateTime? _playStartTime;     // wall-clock instant play began at _seekPosition

  // MIDI playback scheduling (Dart-side, because WASM clip API is all stubs)
  static int _nextClipId = 100;
  final Map<int, List<_WebMidiNote>> _midiClipNotes = {};
  final Map<int, double> _midiClipStartTimes = {};
  final Map<int, int> _clipTrackIds = {}; // clipId → trackId for track-level cleanup
  final List<Timer> _scheduledNoteTimers = [];
  final Set<int> _activeNoteOns = {};
  int _playGeneration = 0; // bumped on every cancel to invalidate in-flight timers

  // Metronome (Dart-side)
  bool _metronomeEnabled = false;
  double _metronomeTempo = 120.0;
  int _metronomeBeatsPerBar = 4;
  int _metronomeBeat = 0; // running beat index, wraps at _metronomeBeatsPerBar
  Timer? _metronomeTimer;

  String transportPlay() {
    _webSynthResume();
    _callEngine('resume_audio_context');
    _playStartTime = DateTime.now();
    _isPlaying = true;
    _scheduleMidiPlayback(_seekPosition);
    if (_metronomeEnabled) _startMetronome(_seekPosition);
    final result = _callEngine('transport_play');
    return (result as JSString?)?.toDart ?? 'Playing';
  }

  String transportPause() {
    if (_isPlaying && _playStartTime != null) {
      _pausedPosition = _seekPosition +
          DateTime.now().difference(_playStartTime!).inMicroseconds / 1000000.0;
    }
    _isPlaying = false;
    _playStartTime = null;
    _cancelScheduledNotes();
    _stopMetronome();
    final result = _callEngine('transport_pause');
    return (result as JSString?)?.toDart ?? 'Paused';
  }

  String transportStop() {
    if (_isPlaying && _playStartTime != null) {
      _pausedPosition = _seekPosition +
          DateTime.now().difference(_playStartTime!).inMicroseconds / 1000000.0;
    }
    _isPlaying = false;
    _playStartTime = null;
    _cancelScheduledNotes();
    _stopMetronome();
    final result = _callEngine('transport_stop');
    return (result as JSString?)?.toDart ?? 'Stopped';
  }

  String transportSeek(double positionSeconds) {
    _seekPosition = positionSeconds;
    _pausedPosition = positionSeconds;
    if (_isPlaying) {
      _playStartTime = DateTime.now();
      _scheduleMidiPlayback(positionSeconds);
      if (_metronomeEnabled) _startMetronome(positionSeconds);
    }
    _callEngineWith('transport_seek', [positionSeconds.toJS]);
    return 'Seeked';
  }

  double getPlayheadPosition() {
    if (_isPlaying && _playStartTime != null) {
      return _seekPosition +
          DateTime.now().difference(_playStartTime!).inMicroseconds / 1000000.0;
    }
    return _pausedPosition;
  }

  int getTransportState() {
    return _isPlaying ? 1 : 0;
  }

  // ============================================================================
  // MIDI scheduling helpers
  // ============================================================================

  void _scheduleMidiPlayback(double fromPosition) {
    _cancelScheduledNotes();
    _initWebSynth();
    final generation = ++_playGeneration;

    for (final entry in _midiClipStartTimes.entries) {
      final clipId = entry.key;
      final clipStart = entry.value;
      final notes = _midiClipNotes[clipId] ?? [];

      for (final note in notes) {
        final noteAbsStart = clipStart + note.startTime;
        final noteAbsEnd = noteAbsStart + note.duration;

        if (noteAbsEnd <= fromPosition) continue; // already ended

        if (noteAbsStart <= fromPosition) {
          // Note onset has passed but it's still sounding — start immediately
          _activeNoteOns.add(note.note);
          _webSynthNoteOn(note.note, note.velocity);
          final remainingMs =
              ((noteAbsEnd - fromPosition) * 1000).round().clamp(10, 60000);
          _scheduledNoteTimers.add(
            Timer(Duration(milliseconds: remainingMs), () {
              if (generation != _playGeneration) return;
              _activeNoteOns.remove(note.note);
              _webSynthNoteOff(note.note);
            }),
          );
        } else {
          final delayMs =
              ((noteAbsStart - fromPosition) * 1000).round().clamp(0, 600000);
          final durationMs =
              (note.duration * 1000).round().clamp(10, 60000);
          final capturedNote = note;
          _scheduledNoteTimers.add(
            Timer(Duration(milliseconds: delayMs), () {
              if (generation != _playGeneration) return;
              _activeNoteOns.add(capturedNote.note);
              _webSynthNoteOn(capturedNote.note, capturedNote.velocity);
              _scheduledNoteTimers.add(
                Timer(Duration(milliseconds: durationMs), () {
                  if (generation != _playGeneration) return;
                  _activeNoteOns.remove(capturedNote.note);
                  _webSynthNoteOff(capturedNote.note);
                }),
              );
            }),
          );
        }
      }
    }
  }

  void _cancelScheduledNotes() {
    _playGeneration++;
    for (final t in _scheduledNoteTimers) {
      t.cancel();
    }
    _scheduledNoteTimers.clear();
    for (final note in _activeNoteOns) {
      _webSynthNoteOff(note);
    }
    _activeNoteOns.clear();
  }

  void _startMetronome(double fromPosition) {
    _stopMetronome();
    final tempo = _metronomeTempo;
    final beatDurationMs = (60000.0 / tempo).round();
    // Align the first tick to the next beat boundary from fromPosition
    final beatPosition = fromPosition * tempo / 60.0;
    final beatFraction = beatPosition % 1.0;
    final msToNextBeat =
        ((1.0 - beatFraction) * beatDurationMs).round().clamp(0, beatDurationMs);
    // Set beat index so the upcoming tick lands on the right bar position
    _metronomeBeat = beatPosition.floor() % _metronomeBeatsPerBar;

    void clickTick() {
      if (!_isPlaying || !_metronomeEnabled) return;
      final isAccent = _metronomeBeat % _metronomeBeatsPerBar == 0;
      _webSynthClick(isAccent);
      _metronomeBeat = (_metronomeBeat + 1) % _metronomeBeatsPerBar;
      Log.d('[Metro] beat $_metronomeBeat accent=$isAccent');
    }

    Timer(Duration(milliseconds: msToNextBeat), () {
      if (!_isPlaying || !_metronomeEnabled) return;
      clickTick();
      _metronomeTimer = Timer.periodic(Duration(milliseconds: beatDurationMs), (_) {
        if (!_isPlaying || !_metronomeEnabled) {
          _stopMetronome();
          return;
        }
        clickTick();
      });
    });
  }

  void _stopMetronome() {
    _metronomeTimer?.cancel();
    _metronomeTimer = null;
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
  int loadAudioFileToTrack(
    String filePath,
    int trackId, {
    double startTime = 0.0,
  }) {
    // Web can't load from file paths - use loadAudioData instead
    return -1;
  }

  int loadAudioData(
    List<int> data,
    String name,
    int trackId,
    double startTime,
  ) {
    // TODO: Implement proper byte array passing to WASM
    return -1;
  }

  @override
  double getClipDuration(int clipId) => 0.0;

  @override
  List<double> getWaveformPeaks(int clipId, int resolution) => [];

  @override
  String setClipStartTime(int trackId, int clipId, double startTime) {
    _midiClipStartTimes[clipId] = startTime;
    _clipTrackIds[clipId] = trackId;
    return 'OK';
  }

  @override
  String setClipOffset(int trackId, int clipId, double offset) => 'OK';

  @override
  String setClipDuration(int trackId, int clipId, double duration) => 'OK';

  @override
  String setAudioClipGain(int trackId, int clipId, double gainDb) => 'OK';

  @override
  String setAudioClipWarp(
    int trackId,
    int clipId,
    bool warpEnabled,
    double stretchFactor,
    int warpMode,
  ) => 'OK';

  @override
  String setAudioClipTranspose(
    int trackId,
    int clipId,
    int semitones,
    int cents,
  ) => 'OK';

  @override
  String setAudioClipReverse(
    int trackId,
    int clipId, {
    required bool reversed,
  }) => 'OK';

  @override
  bool removeAudioClip(int trackId, int clipId) => true;

  @override
  int addExistingClipToTrack(
    int clipId,
    int trackId,
    double startTime, {
    double offset = 0.0,
    double? duration,
  }) => -1;

  @override
  String? joinAudioClips(int trackId, List<int> clipIds) => null;

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
  int getCountInBeat() => 0;
  double getCountInProgress() => 0.0;

  @override
  void setTempo(double bpm) {
    _metronomeTempo = bpm;
    _callEngineWith('set_tempo', [bpm.toJS]);
  }

  double getTempo() => _metronomeTempo;

  String setMetronomeEnabled({required bool enabled}) {
    _metronomeEnabled = enabled;
    if (enabled && _isPlaying) {
      _startMetronome(getPlayheadPosition());
    } else if (!enabled) {
      _stopMetronome();
    }
    return enabled ? 'Metronome enabled' : 'Metronome disabled';
  }

  bool isMetronomeEnabled() => _metronomeEnabled;

  String setTimeSignature(int beatsPerBar) {
    _metronomeBeatsPerBar = beatsPerBar > 0 ? beatsPerBar : 4;
    return 'OK';
  }

  int getTimeSignature() => _metronomeBeatsPerBar;

  // ============================================================================
  // MIDI
  // ============================================================================

  String startMidiInput() => 'MIDI input started';
  String stopMidiInput() => 'MIDI input stopped';

  String setSynthOscillatorType(int oscType) => 'OK';
  String setSynthVolume(double volume) => 'OK';

  @override
  String sendMidiNoteOn(int note, int velocity) {
    // Use web synth for immediate audio feedback
    _webSynthNoteOn(note, velocity);
    _callEngineWith('send_midi_note_on', [
      _intToBigInt(0),
      note.toJS,
      velocity.toJS,
    ]);
    return 'OK';
  }

  @override
  String sendMidiNoteOff(int note, int velocity) {
    // Use web synth for immediate audio feedback
    _webSynthNoteOff(note);
    _callEngineWith('send_midi_note_off', [_intToBigInt(0), note.toJS]);
    return 'OK';
  }

  String sendTrackMidiNoteOn(int trackId, int note, int velocity) {
    // Use web synth for immediate audio feedback
    _webSynthNoteOn(note, velocity);
    _callEngineWith('send_midi_note_on', [
      _intToBigInt(trackId),
      note.toJS,
      velocity.toJS,
    ]);
    return 'OK';
  }

  String sendTrackMidiNoteOff(int trackId, int note, int velocity) {
    // Use web synth for immediate audio feedback
    _webSynthNoteOff(note);
    _callEngineWith('send_midi_note_off', [_intToBigInt(trackId), note.toJS]);
    return 'OK';
  }

  @override
  int createMidiClip() {
    final id = _nextClipId++;
    _midiClipNotes[id] = [];
    return id;
  }

  @override
  String addMidiNoteToClip(
    int clipId,
    int note,
    int velocity,
    double startTime,
    double duration,
  ) {
    _midiClipNotes[clipId]?.add(
      _WebMidiNote(
        note: note,
        velocity: velocity,
        startTime: startTime,
        duration: duration,
      ),
    );
    return 'OK';
  }

  @override
  int addMidiClipToTrack(int trackId, int clipId, double startTimeSeconds) {
    _midiClipStartTimes[clipId] = startTimeSeconds;
    _clipTrackIds[clipId] = trackId;
    return 0;
  }

  @override
  int removeMidiClip(int trackId, int clipId) {
    _midiClipNotes.remove(clipId);
    _midiClipStartTimes.remove(clipId);
    _clipTrackIds.remove(clipId);
    return 0;
  }

  @override
  String clearMidiClip(int clipId) {
    _midiClipNotes[clipId]?.clear();
    return 'OK';
  }

  /// Get available MIDI input devices (empty on web)
  List<Map<String, dynamic>> getMidiInputDevices() =>
      []; // Web MIDI API would be needed
  String selectMidiInputDevice(int deviceIndex) => 'OK';
  String refreshMidiDevices() => 'OK';

  String startMidiRecording() => 'Not implemented';
  int stopMidiRecording() => -1;
  int getMidiRecordingState() => 0;
  String getMidiRecorderLiveEvents() => '';
  String quantizeMidiClip(int clipId, int gridDivision) => 'OK';
  String getMidiClipInfo(int clipId) => '{}';
  @override
  String getAllMidiClipsInfo() => '[]';
  @override
  String getMidiClipNotes(int clipId) => '[]';

  // ============================================================================
  // Audio Device Selection (Web uses system default)
  // ============================================================================

  /// Get available audio input devices (empty on web)
  List<Map<String, dynamic>> getAudioInputDevices() => [];
  String setAudioInputDevice(int deviceIndex) => 'OK';

  /// Web audio routes to the system default via the Web Audio API.
  List<Map<String, dynamic>> getAudioOutputDevices() => [
    {'name': 'System Default', 'isDefault': true},
  ];
  String setAudioOutputDevice(String deviceName) => 'OK';
  String getSelectedAudioOutputDevice() => 'System Default';
  // Web audio runs in-page — there is no device stream that can die (C99).
  String getAudioStreamError() => '';
  int getSampleRate() => 48000;

  // ============================================================================
  // Track Management
  // ============================================================================

  // Track ID counter for web (since WASM may not provide real IDs yet)
  static int _nextTrackId = 1;

  // In-memory registry — WASM doesn't export get_all_track_ids / get_track_info
  static final Map<int, _WebTrackState> _trackRegistry = {};

  @override
  int createTrack(String trackType, String name) {
    // Notify the WASM engine (preserves the console log), but do NOT trust its
    // return value — the WASM stub always returns 1, which causes every track
    // to collide on the same key in _trackRegistry. The Dart side is already
    // the authoritative source of truth for transport, MIDI, and metronome on
    // web, so it owns track IDs here too.
    try {
      _callEngineWith('create_track', [name.toJS]);
    } catch (_) {
      // Ignore WASM errors — we don't depend on its return value.
    }

    final id = _nextTrackId++;
    _trackRegistry[id] = _WebTrackState(id: id, name: name, type: trackType);
    Log.d('createTrack($trackType, $name) => $id (Dart-allocated)');
    return id;
  }

  @override
  List<int> getAllTrackIds() => _trackRegistry.keys.toList();

  @override
  String getTrackInfo(int trackId) {
    final t = _trackRegistry[trackId];
    if (t == null) return '';
    // CSV: id,name,type,volume_db,pan,mute,solo,armed,input_device,input_channel,input_monitoring
    final encodedName = t.name
        .replaceAll('%', '%25')
        .replaceAll(',', '%2C')
        .replaceAll(';', '%3B');
    return '$trackId,$encodedName,${t.type},${t.volumeDb},${t.pan},${t.mute},${t.solo},false,-1,0,false';
  }

  @override
  void setTrackVolume(int trackId, double volumeDb) {
    _trackRegistry[trackId]?.volumeDb = volumeDb;
    final linear = volumeDb <= -60
        ? 0.0
        : (volumeDb / 60.0 + 1.0).clamp(0.0, 1.0);
    _callEngineWith('set_track_volume', [_intToBigInt(trackId), linear.toJS]);
  }

  @override
  void setTrackVolumeAutomation(int trackId, String csvData) {
    // Web implementation stub - automation not yet supported on web
  }

  @override
  void setTrackPan(int trackId, double pan) {
    _trackRegistry[trackId]?.pan = pan;
    _callEngineWith('set_track_pan', [_intToBigInt(trackId), pan.toJS]);
  }

  @override
  void setTrackMute(int trackId, {required bool mute}) {
    _trackRegistry[trackId]?.mute = mute;
    _callEngineWith('set_track_mute', [_intToBigInt(trackId), mute.toJS]);
  }

  @override
  void setTrackSolo(int trackId, {required bool solo}) {
    _trackRegistry[trackId]?.solo = solo;
    _callEngineWith('set_track_solo', [_intToBigInt(trackId), solo.toJS]);
  }

  @override
  void setTrackArmed(int trackId, {required bool armed}) {}

  @override
  void setTrackName(int trackId, String name) {
    _trackRegistry[trackId]?.name = name;
  }

  String setTrackInput(int trackId, int deviceIndex, int channel) => 'OK';
  Map<String, int> getTrackInput(int trackId) =>
      {'device_index': -1, 'channel': 0};
  String setTrackInputMonitoring(int trackId, {required bool enabled}) => 'OK';
  double getInputChannelLevel(int channel) => 0.0;
  int getInputChannelCount() => 0;

  int getTrackCount() => _trackRegistry.length;

  String getTrackPeakLevels(int trackId) => '{"left": 0.0, "right": 0.0}';

  String getEffectPeakLevels(int effectId) => '-96.0,-96.0';

  @override
  String deleteTrack(int trackId) {
    _trackRegistry.remove(trackId);
    // Remove every MIDI clip that belonged to this track
    final clipIds = _clipTrackIds.entries
        .where((e) => e.value == trackId)
        .map((e) => e.key)
        .toList();
    for (final clipId in clipIds) {
      _midiClipNotes.remove(clipId);
      _midiClipStartTimes.remove(clipId);
      _clipTrackIds.remove(clipId);
    }
    _callEngineWith('delete_track', [_intToBigInt(trackId)]);
    return 'OK';
  }

  @override
  int duplicateTrack(int trackId) => -1;

  String clearAllTracks() {
    _cancelScheduledNotes();
    _stopMetronome();
    _midiClipNotes.clear();
    _midiClipStartTimes.clear();
    _clipTrackIds.clear();
    _trackRegistry.clear();
    _isPlaying = false;
    _playStartTime = null;
    _seekPosition = 0.0;
    _pausedPosition = 0.0;
    return 'OK';
  }

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
  String removeEffectFromTrack(int trackId, int effectId) => 'OK';

  @override
  int addEqBand(int effectId) => -1;

  @override
  String removeEqBand(int effectId, int index) => 'OK';

  @override
  String insertEqBand(int effectId, int index) => 'OK';

  @override
  String getTrackEffects(int trackId) => '[]';
  @override
  String getEffectInfo(int effectId) => '{}';
  @override
  String setEffectParameter(int effectId, String paramName, double value) =>
      'OK';

  @override
  void setEffectBypass(int effectId, {required bool bypassed}) {}

  @override
  void setSynthBypass(int trackId, {required bool bypassed}) {}

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
  Map<String, dynamic>? getVst3ParameterInfo(int effectId, int paramIndex) =>
      null;
  double getVst3ParameterValue(int effectId, int paramIndex) => 0.0;

  @override
  bool setVst3ParameterValue(int effectId, int paramIndex, double value) =>
      true;

  // ============================================================================
  // Sampler API (stubs for web - not yet implemented)
  // ============================================================================

  @override
  int createSamplerForTrack(int trackId) => -1;

  @override
  bool loadSampleForTrack(int trackId, String path, int rootNote) => false;

  @override
  bool unloadSampleForTrack(int trackId) => false;

  @override
  String? getSamplerSamplePath(int trackId) => null;

  @override
  String setSamplerParameter(int trackId, String param, String value) =>
      'Not supported on web';

  @override
  bool isSamplerTrack(int trackId) => false;

  @override
  SamplerInfo? getSamplerInfo(int trackId) => null;

  @override
  List<double> getSamplerWaveformPeaks(int trackId, int resolution) => [];

  // Drum Kit API (stubs for web - not yet implemented)
  @override
  int createDrumKitForTrack(int trackId) => -1;

  @override
  int addDrumPad(int trackId, int pinnedNote) => -1;

  @override
  String removeDrumPad(int trackId, int padIndex) => 'Not supported on web';

  @override
  bool loadDrumPadSample(int trackId, int padIndex, String path) => false;

  @override
  String setDrumPadParameter(
    int trackId,
    int padIndex,
    String param,
    String value,
  ) => 'Not supported on web';

  @override
  bool isDrumKitTrack(int trackId) => false;

  @override
  int drumNextFreeNote(int trackId, int start) => -1;

  @override
  DrumKitInfo? getDrumKitInfo(int trackId) => null;

  @override
  List<double> getDrumPadWaveformPeaks(
    int trackId,
    int padIndex,
    int resolution,
  ) => [];

  bool vst3HasEditor(int effectId) => false;
  String vst3OpenEditor(int effectId) => 'Not supported';
  String vst3CloseEditor(int effectId) => 'OK';
  Map<String, int>? vst3GetEditorSize(int effectId) => {
    'width': 0,
    'height': 0,
  };
  // vst3AttachEditor takes a pointer on native - stub for web
  String vst3AttachEditor(int effectId, dynamic viewPtr) => 'Not supported';

  /// Send a MIDI note event to a VST3 plugin
  /// eventType: 0 = note on, 1 = note off
  String vst3SendMidiNote(
    int effectId,
    int eventType,
    int channel,
    int note,
    int velocity,
  ) => 'OK';

  @override
  String getVst3State(int effectId) => '';
  @override
  String setVst3State(int effectId, String stateBase64) => '';
  String getVst3Presets(int effectId) => '[]';
  String setVst3Program(int effectId, int listId, int programIndex) => '';
  String setVst3EditorMaxSize(int effectId, int maxW, int maxH) => '';

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
    // Clear Dart-side MIDI state before loading so stale clips don't linger
    _cancelScheduledNotes();
    _midiClipNotes.clear();
    _midiClipStartTimes.clear();
    _clipTrackIds.clear();
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
  String getExportProgress() =>
      '{"progress": 0, "is_running": false, "is_cancelled": false, "status": "", "error": null}';
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

  // ============================================================================
  // Library Preview — Web Audio implementation
  // ============================================================================

  @override
  String previewLoadAudio(String path) => 'Not available on web';

  /// Kick off an async asset load + decode. The preview service polls
  /// [previewIsLoaded] and calls [previewPlay] once it becomes true.
  @override
  void previewLoadAudioAsync(String path) {
    _initWebSynth();
    unawaited(_loadPreviewAsset(path));
  }

  Future<void> _loadPreviewAsset(String path) async {
    try {
      final data = await rootBundle.load(path);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (_boojySynth != null) {
        _boojySynth!.callMethodVarArgs('previewLoad'.toJS, [bytes.toJS]);
      }
    } catch (e) {
      Log.e('[Web Preview] Failed to load asset "$path": $e');
    }
  }

  @override
  bool previewIsLoaded() {
    if (_boojySynth == null) return false;
    final v = _boojySynth!['previewLoaded'];
    return v != null && v.isA<JSBoolean>() && (v as JSBoolean).toDart;
  }

  @override
  bool previewCheckFullClip() => false;

  @override
  bool previewIsFullyDecoded() => false;

  @override
  void previewPlay() {
    _initWebSynth();
    _boojySynth?.callMethod('previewPlay'.toJS);
  }

  @override
  void previewStop() {
    _boojySynth?.callMethod('previewStop'.toJS);
  }

  @override
  void previewSeek(double positionSeconds) {
    _initWebSynth();
    _boojySynth?.callMethodVarArgs('previewSeek'.toJS, [positionSeconds.toJS]);
  }

  @override
  double previewGetPosition() {
    if (_boojySynth == null) return 0.0;
    final v = _boojySynth!.callMethod('previewGetPosition'.toJS);
    if (v != null && v.isA<JSNumber>()) return (v as JSNumber).toDartDouble;
    return 0.0;
  }

  @override
  double previewGetDuration() {
    if (_boojySynth == null) return 0.0;
    final v = _boojySynth!.callMethod('previewGetDuration'.toJS);
    if (v != null && v.isA<JSNumber>()) return (v as JSNumber).toDartDouble;
    return 0.0;
  }

  @override
  bool previewIsPlaying() {
    if (_boojySynth == null) return false;
    final v = _boojySynth!.callMethod('previewIsPlaying'.toJS);
    return v != null && v.isA<JSBoolean>() && (v as JSBoolean).toDart;
  }

  @override
  void previewSetLooping(bool shouldLoop) {
    if (_boojySynth == null) return;
    _boojySynth!['previewLooping'] = shouldLoop.toJS;
  }

  @override
  bool previewIsLooping() {
    if (_boojySynth == null) return false;
    final v = _boojySynth!['previewLooping'];
    return v != null && v.isA<JSBoolean>() && (v as JSBoolean).toDart;
  }

  @override
  List<double> previewGetWaveform(int resolution) {
    if (_boojySynth == null) return List.filled(resolution, 0.0);
    try {
      final v = _boojySynth!.callMethodVarArgs('previewGetWaveform'.toJS, [resolution.toJS]);
      if (v != null && v.isA<JSFloat32Array>()) {
        final arr = (v as JSFloat32Array).toDart;
        return arr.map((x) => x.toDouble()).toList();
      }
    } catch (e) {
      Log.e('[Web Preview] previewGetWaveform error: $e');
    }
    return List.filled(resolution, 0.0);
  }

  // ============================================================================
  // Punch Recording (stubs - not yet implemented on web)
  // ============================================================================

  @override
  String setPunchInEnabled({required bool enabled}) =>
      throw UnsupportedError('Web');

  @override
  bool isPunchInEnabled() => throw UnsupportedError('Web');

  @override
  String setPunchOutEnabled({required bool enabled}) =>
      throw UnsupportedError('Web');

  @override
  bool isPunchOutEnabled() => throw UnsupportedError('Web');

  @override
  String setPunchRegion(double inSeconds, double outSeconds) =>
      throw UnsupportedError('Web');

  @override
  double getPunchInSeconds() => throw UnsupportedError('Web');

  @override
  double getPunchOutSeconds() => throw UnsupportedError('Web');

  @override
  bool isPunchComplete() => throw UnsupportedError('Web');

  // ============================================================================
  // Send/Return (stubs - not yet implemented on web)
  // ============================================================================

  @override
  int findReturnByEffectType(String effectType) => 0;

  @override
  int createReturnWithEffect(String effectType, {String? name}) => -1;

  @override
  String addSharedSend(int sourceTrackId, String effectType) =>
      'Not supported on web';

  @override
  String addSend(int sourceTrackId, int returnTrackId, double amountDb) =>
      'Not supported on web';

  @override
  String setSendAmount(int sourceTrackId, int returnTrackId, double amountDb) =>
      'Not supported on web';

  @override
  String removeSend(int sourceTrackId, int returnTrackId) =>
      'Not supported on web';

  @override
  String removeReturn(int returnTrackId) => 'Not supported on web';

  @override
  String getTrackSends(int trackId) => '';

  @override
  String getAllReturns() => '';

  @override
  int countSendsToReturn(int returnTrackId) => 0;

  @override
  bool getMasterTimelineVisible() => false;

  @override
  String setMasterTimelineVisible({required bool visible}) =>
      'Not supported on web';

  @override
  bool syncMasterTimelineVisibility() => false;
}

/// A single MIDI note kept in the Dart-side clip store.
/// startTime and duration are in seconds relative to the clip's start.
class _WebMidiNote {
  final int note;
  final int velocity;
  final double startTime;
  final double duration;

  const _WebMidiNote({
    required this.note,
    required this.velocity,
    required this.startTime,
    required this.duration,
  });
}

/// Mutable track state kept in Dart memory on web.
/// WASM doesn't expose get_all_track_ids / get_track_info.
class _WebTrackState {
  final int id;
  String name;
  final String type;
  double volumeDb = 0.0;
  double pan = 0.0;
  bool mute = false;
  bool solo = false;

  _WebTrackState({required this.id, required this.name, required this.type});
}
