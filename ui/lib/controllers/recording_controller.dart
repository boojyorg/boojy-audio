import 'dart:async';
import 'package:flutter/foundation.dart';
import '../audio_engine.dart';
import '../services/live_recording_notifier.dart';

/// Result of a recording operation
class RecordingResult {
  final int? audioClipId;
  final int? midiClipId;
  final double? duration;
  final List<double>? waveformPeaks;
  final String? midiClipInfo;

  RecordingResult({
    this.audioClipId,
    this.midiClipId,
    this.duration,
    this.waveformPeaks,
    this.midiClipInfo,
  });
}

/// Manages recording state, metronome, tempo, and MIDI devices.
class RecordingController extends ChangeNotifier {
  AudioEngine? _audioEngine;
  Timer? _recordingStateTimer;

  // Recording state
  bool _isRecording = false;
  bool _isCountingIn = false;
  bool _isMidiRecording = false;
  bool _isMetronomeEnabled = true;
  double _tempo = 120.0;

  // Count-in UI state
  int _countInBeat = 0;
  double _countInProgress = 0.0;

  // Virtual piano state
  bool _isVirtualPianoEnabled = false;

  // MIDI device state
  List<Map<String, dynamic>> _midiDevices = [];
  int _selectedMidiDeviceIndex = -1;

  // Callback for when recording stops
  void Function(RecordingResult result)? onRecordingComplete;

  // Live recording notifier for real-time MIDI note display
  LiveRecordingNotifier? _liveRecordingNotifier;

  // Callback to get the first armed MIDI track ID
  int Function()? getFirstArmedMidiTrackId;

  // Callback to get a clip name for the recording
  String Function(int trackId)? getRecordingClipName;

  // Callback to check if any audio tracks are armed
  bool Function()? hasArmedAudioTracks;

  // Whether audio recording was started (to skip stop if not started)
  bool _audioRecordingStarted = false;

  // Playhead position (seconds) when recording was initiated (before count-in)
  double _recordingStartPosition = 0.0;

  // Actual count-in duration (seconds), measured from engine time at transition
  double _countInDurationSeconds = 0.0;

  RecordingController();

  // Getters
  bool get isRecording => _isRecording;
  bool get isCountingIn => _isCountingIn;
  bool get isMidiRecording => _isMidiRecording;
  bool get isMetronomeEnabled => _isMetronomeEnabled;
  double get tempo => _tempo;
  int get countInBeat => _countInBeat;
  double get countInProgress => _countInProgress;
  bool get isVirtualPianoEnabled => _isVirtualPianoEnabled;
  List<Map<String, dynamic>> get midiDevices => _midiDevices;
  int get selectedMidiDeviceIndex => _selectedMidiDeviceIndex;
  double get recordingStartPosition => _recordingStartPosition;
  double get countInDurationSeconds => _countInDurationSeconds;

  // Callback to set recordStartPosition in PlaybackController
  void Function(double position)? onRecordStartPositionChanged;

  /// Set the live recording notifier for real-time MIDI display
  void setLiveRecordingNotifier(LiveRecordingNotifier notifier) {
    _liveRecordingNotifier = notifier;
  }

  /// Initialize with audio engine reference
  void initialize(AudioEngine engine) {
    _audioEngine = engine;

    // Initialize recording settings
    // Note: count-in bars are set by daw_screen.dart from userSettings BEFORE
    // this method is called. Don't override here.
    try {
      _audioEngine!.setTempo(120.0);
      _audioEngine!.setMetronomeEnabled(enabled: true);
      _tempo = 120.0;
      _isMetronomeEnabled = true;
    } catch (e) {
      debugPrint('RecordingController: Failed to initialize recording settings: $e');
    }

    // Load MIDI devices and start MIDI input
    loadMidiDevices();

    // Start MIDI input immediately - always listening for MIDI controllers
    // MIDI is routed to armed tracks for live playback
    try {
      _audioEngine!.startMidiInput();
      debugPrint('RecordingController: MIDI input started (always-on mode)');
    } catch (e) {
      debugPrint('RecordingController: Failed to start MIDI input: $e');
    }
  }

  /// Toggle recording on/off
  void toggleRecording() {
    if (_audioEngine == null) return;

    if (_isRecording || _isCountingIn) {
      stopRecording();
    } else {
      startRecording(isAlreadyPlaying: false);
    }
  }

  /// Start recording
  /// [isAlreadyPlaying]: If true, skips count-in and starts recording immediately
  void startRecording({required bool isAlreadyPlaying}) {
    if (_audioEngine == null) {
      debugPrint('🎙️ [REC_CTRL] startRecording() — audioEngine is null, aborting');
      return;
    }

    try {
      final tempo = _audioEngine!.getTempo();

      // Save playhead position before starting — this is where the clip will be placed
      _recordingStartPosition = _audioEngine!.getPlayheadPosition();
      debugPrint('🎙️ [REC_CTRL] startRecording(isAlreadyPlaying=$isAlreadyPlaying) called');
      debugPrint('🎙️ [REC_CTRL]   tempo=$tempo, recordingStartPosition=${_recordingStartPosition.toStringAsFixed(4)}s');
      debugPrint('🎙️ [REC_CTRL]   hasArmedAudioTracks=${hasArmedAudioTracks?.call() ?? "null callback"}');

      // If already playing, disable count-in for immediate recording
      if (isAlreadyPlaying) {
        _audioEngine!.setCountInBars(0);
        debugPrint('🎙️ [REC_CTRL]   Already playing - disabled count-in');
      }

      // Always call startRecording — it starts the transport and count-in state machine.
      // Track whether we should process the audio result on stop.
      _audioRecordingStarted = hasArmedAudioTracks?.call() ?? false;
      debugPrint('🎙️ [REC_CTRL]   _audioRecordingStarted=$_audioRecordingStarted');
      _audioEngine!.startRecording();
      debugPrint('🎙️ [REC_CTRL]   engine.startRecording() done');
      _audioEngine!.startMidiRecording();
      debugPrint('🎙️ [REC_CTRL]   engine.startMidiRecording() done');
      // Note: MIDI input is always running (started in initialize)

      if (isAlreadyPlaying) {
        // Skip count-in state, go directly to recording
        _isRecording = true;
        _isCountingIn = false;
        // Set recordStartPosition immediately since there's no count-in
        onRecordStartPositionChanged?.call(_recordingStartPosition);
      } else {
        // Normal flow with count-in
        _isCountingIn = true;
      }

      _isMidiRecording = true;
      _tempo = tempo;
      notifyListeners();

      _startRecordingStateTimer();
      debugPrint('🎙️ [REC_CTRL]   Recording state timer started');
    } catch (e) {
      debugPrint('🎙️ [REC_CTRL] ⚠️ Failed to start recording: $e');
    }
  }

  /// Restart recording: save current take and start new one with count-in
  RecordingResult restartRecording() {
    debugPrint('🎙️ [REC_CTRL] restartRecording() called - saving current take and starting new one');

    // Stop current recording and get the result
    final result = stopRecording();

    // Call completion callback to save the take
    onRecordingComplete?.call(result);

    // Seek back to recordStartPosition (engine will adjust for count-in)
    _audioEngine?.transportSeek(_recordingStartPosition);

    // Start new recording with count-in
    startRecording(isAlreadyPlaying: false);

    return result;
  }

  /// Stop recording and return results
  RecordingResult stopRecording() {
    debugPrint('🎙️ [REC_CTRL] stopRecording() called');
    if (_audioEngine == null) {
      debugPrint('🎙️ [REC_CTRL]   audioEngine is null, returning empty result');
      return RecordingResult();
    }

    try {
      // Clear live recording display before stopping
      _liveRecordingNotifier?.clear();

      // Always stop audio recording (it was always started for transport/count-in).
      // Only process the audio clip result if audio tracks were armed.
      final rawAudioClipId = _audioEngine!.stopRecording();
      final audioClipId = _audioRecordingStarted ? rawAudioClipId : -1;
      final midiClipId = _audioEngine!.stopMidiRecording();
      debugPrint('🎙️ [REC_CTRL]   rawAudioClipId=$rawAudioClipId, audioRecordingStarted=$_audioRecordingStarted → audioClipId=$audioClipId');
      debugPrint('🎙️ [REC_CTRL]   midiClipId=$midiClipId');
      // Note: MIDI input stays running (always-on mode)

      _isRecording = false;
      _isCountingIn = false;
      _isMidiRecording = false;
      _audioRecordingStarted = false;
      _countInBeat = 0;
      _countInProgress = 0.0;
      _countInDurationSeconds = 0.0;
      notifyListeners();

      _recordingStateTimer?.cancel();
      _recordingStateTimer = null;

      // Store high-resolution peaks (8000/sec) - LOD downsampling happens at render time
      final duration = audioClipId >= 0 ? _audioEngine!.getClipDuration(audioClipId) : 0.0;
      final peakResolution = (duration * 8000).clamp(8000, 240000).toInt();

      final midiClipInfo = midiClipId >= 0 ? _audioEngine!.getMidiClipInfo(midiClipId) : null;
      debugPrint('🎙️ [REC_CTRL]   duration=$duration, midiClipInfo="$midiClipInfo"');
      debugPrint('🎙️ [REC_CTRL]   Result: audioClipId=${audioClipId >= 0 ? audioClipId : null}, '
          'midiClipId=${midiClipId >= 0 ? midiClipId : null}');

      final result = RecordingResult(
        audioClipId: audioClipId >= 0 ? audioClipId : null,
        midiClipId: midiClipId >= 0 ? midiClipId : null,
        duration: duration > 0 ? duration : null,
        waveformPeaks: audioClipId >= 0 ? _audioEngine!.getWaveformPeaks(audioClipId, peakResolution) : null,
        midiClipInfo: midiClipInfo,
      );

      debugPrint('🎙️ [REC_CTRL]   Calling onRecordingComplete callback (${onRecordingComplete != null ? "set" : "NULL"})');
      onRecordingComplete?.call(result);
      return result;
    } catch (e) {
      debugPrint('🎙️ [REC_CTRL] ⚠️ stopRecording exception: $e');
      _isRecording = false;
      _isCountingIn = false;
      _isMidiRecording = false;
      _countInBeat = 0;
      _countInProgress = 0.0;
      notifyListeners();
      return RecordingResult();
    }
  }

  void _startRecordingStateTimer() {
    _recordingStateTimer?.cancel();

    // Poll at 33ms (~30fps) for smooth count-in ring animation
    _recordingStateTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (_audioEngine == null || (!_isRecording && !_isCountingIn)) {
        timer.cancel();
        _recordingStateTimer = null;
        return;
      }

      final state = _audioEngine!.getRecordingState();

      if (state == 1) {
        // CountingIn — poll beat number and progress for ring timer
        _countInBeat = _audioEngine!.getCountInBeat();
        _countInProgress = _audioEngine!.getCountInProgress();
        if (!_isCountingIn) {
          debugPrint('🎙️ [REC_CTRL] State timer: → CountingIn (state=1)');
          _isCountingIn = true;
        }
        notifyListeners();
      } else if (state == 2 && !_isRecording) {
        // Measure actual count-in duration from engine time
        final currentPosition = _audioEngine!.getPlayheadPosition();
        _countInDurationSeconds = currentPosition - _recordingStartPosition;
        debugPrint('🎙️ [REC_CTRL] State timer: CountingIn → Recording (state=2)');
        debugPrint('🎙️ [REC_CTRL]   countInDurationSeconds=${_countInDurationSeconds.toStringAsFixed(3)}s');
        debugPrint('🎙️ [REC_CTRL]   currentPosition=${currentPosition.toStringAsFixed(3)}s');

        _isCountingIn = false;
        _isRecording = true;
        _countInBeat = 0;
        _countInProgress = 0.0;

        // Set record start position in PlaybackController (for Stop button behavior)
        // Use _recordingStartPosition (BEFORE count-in), not currentPosition (AFTER count-in)
        onRecordStartPositionChanged?.call(_recordingStartPosition);
        debugPrint('🎙️ [REC_CTRL]   Called onRecordStartPositionChanged with ${_recordingStartPosition.toStringAsFixed(3)}s');

        // Initialize live recording notifier now that actual recording has started
        // Use saved recording start position (pre-count-in) so the live clip
        // appears at the correct timeline position (e.g. bar 1, not bar 2)
        if (_liveRecordingNotifier != null) {
          final startBeat = _recordingStartPosition * (_tempo / 60.0);
          final trackId = getFirstArmedMidiTrackId?.call() ?? 0;
          final clipName = getRecordingClipName?.call(trackId) ?? 'Recording';
          debugPrint('🎙️ [REC_CTRL]   Live recording: startBeat=${startBeat.toStringAsFixed(3)}, '
              'trackId=$trackId, clipName=$clipName');
          debugPrint('🎙️ [REC_CTRL]   (recordingStartPosition=${_recordingStartPosition.toStringAsFixed(4)}s, tempo=$_tempo)');
          _liveRecordingNotifier!.startRecording(
            startBeat: startBeat,
            trackId: trackId,
            clipName: clipName,
          );
        } else {
          debugPrint('🎙️ [REC_CTRL]   ⚠️ liveRecordingNotifier is null!');
        }

        notifyListeners();
      } else if (state == 0 && (_isRecording || _isCountingIn)) {
        debugPrint('🎙️ [REC_CTRL] State timer: → Idle (state=0), was recording=$_isRecording, countingIn=$_isCountingIn');
        timer.cancel();
        _recordingStateTimer = null;
        _liveRecordingNotifier?.clear();
        _isRecording = false;
        _isCountingIn = false;
        _countInBeat = 0;
        _countInProgress = 0.0;
        notifyListeners();
      }

      // Poll live MIDI events for real-time display during recording
      // Subtract count-in duration so the live clip's currentBeat matches
      // the visual playhead position (which also subtracts count-in offset)
      if (_isRecording && _liveRecordingNotifier != null && _liveRecordingNotifier!.isActive) {
        final eventsCSV = _audioEngine!.getMidiRecorderLiveEvents();
        final adjustedPos = _audioEngine!.getPlayheadPosition() - _countInDurationSeconds;
        final currentBeat = adjustedPos * (_tempo / 60.0);
        _liveRecordingNotifier!.processEngineEvents(eventsCSV, currentBeat, _tempo);
      }
    });
  }

  /// Toggle metronome on/off
  void toggleMetronome() {
    if (_audioEngine == null) return;

    try {
      final newState = !_isMetronomeEnabled;
      _audioEngine!.setMetronomeEnabled(enabled: newState);
      _isMetronomeEnabled = newState;
      notifyListeners();
    } catch (e) {
      debugPrint('RecordingController: Failed to toggle metronome: $e');
    }
  }

  /// Set tempo (BPM)
  void setTempo(double bpm) {
    if (_audioEngine == null) return;

    final clampedBpm = bpm.clamp(20.0, 300.0);

    try {
      _audioEngine!.setTempo(clampedBpm);
      _tempo = clampedBpm;
      notifyListeners();
    } catch (e) {
      debugPrint('RecordingController: Failed to set tempo: $e');
    }
  }

  /// Toggle virtual piano visibility
  /// Note: MIDI input is always running, this just controls UI visibility
  bool toggleVirtualPiano() {
    if (_audioEngine == null) return false;

    _isVirtualPianoEnabled = !_isVirtualPianoEnabled;
    // Note: MIDI input is always running (always-on mode)
    // This flag just controls virtual piano UI visibility
    notifyListeners();
    return true;
  }

  void setVirtualPianoEnabled({required bool enabled}) {
    _isVirtualPianoEnabled = enabled;
    notifyListeners();
  }

  /// Load available MIDI devices
  void loadMidiDevices() {
    if (_audioEngine == null) return;

    try {
      final devices = _audioEngine!.getMidiInputDevices();
      _midiDevices = devices;

      // Auto-select default device if available
      if (_selectedMidiDeviceIndex < 0 && devices.isNotEmpty) {
        final defaultIndex = devices.indexWhere((d) => d['isDefault'] == true);
        if (defaultIndex >= 0) {
          _selectedMidiDeviceIndex = defaultIndex;
          selectMidiDevice(defaultIndex);
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('RecordingController: Failed to load MIDI devices: $e');
    }
  }

  /// Select a MIDI device by index
  void selectMidiDevice(int deviceIndex) {
    if (_audioEngine == null) return;

    try {
      _audioEngine!.selectMidiInputDevice(deviceIndex);
      _selectedMidiDeviceIndex = deviceIndex;
      notifyListeners();
    } catch (e) {
      debugPrint('RecordingController: Failed to select MIDI device: $e');
    }
  }

  /// Refresh MIDI device list
  void refreshMidiDevices() {
    if (_audioEngine == null) return;

    try {
      _audioEngine!.refreshMidiDevices();
      loadMidiDevices();
    } catch (e) {
      debugPrint('RecordingController: Failed to refresh MIDI devices: $e');
    }
  }

  /// Get recording duration (while recording)
  double getRecordedDuration() {
    return _audioEngine?.getRecordedDuration() ?? 0.0;
  }

  @override
  void dispose() {
    _recordingStateTimer?.cancel();
    super.dispose();
  }
}
