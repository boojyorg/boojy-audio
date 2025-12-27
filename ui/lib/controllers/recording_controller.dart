import 'dart:async';
import 'package:flutter/foundation.dart';
import '../audio_engine.dart';

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

  // Virtual piano state
  bool _isVirtualPianoEnabled = false;

  // MIDI device state
  List<Map<String, dynamic>> _midiDevices = [];
  int _selectedMidiDeviceIndex = -1;

  // Callback for when recording stops
  void Function(RecordingResult result)? onRecordingComplete;

  RecordingController();

  // Getters
  bool get isRecording => _isRecording;
  bool get isCountingIn => _isCountingIn;
  bool get isMidiRecording => _isMidiRecording;
  bool get isMetronomeEnabled => _isMetronomeEnabled;
  double get tempo => _tempo;
  bool get isVirtualPianoEnabled => _isVirtualPianoEnabled;
  List<Map<String, dynamic>> get midiDevices => _midiDevices;
  int get selectedMidiDeviceIndex => _selectedMidiDeviceIndex;

  /// Initialize with audio engine reference
  void initialize(AudioEngine engine) {
    _audioEngine = engine;

    // Initialize recording settings
    try {
      _audioEngine!.setCountInBars(2);
      _audioEngine!.setTempo(120.0);
      _audioEngine!.setMetronomeEnabled(true);
      _tempo = 120.0;
      _isMetronomeEnabled = true;
    } catch (e) {
    }

    // Load MIDI devices
    loadMidiDevices();
  }

  /// Toggle recording on/off
  void toggleRecording() {
    if (_audioEngine == null) return;

    if (_isRecording || _isCountingIn) {
      stopRecording();
    } else {
      startRecording();
    }
  }

  /// Start recording
  void startRecording() {
    if (_audioEngine == null) return;

    try {
      final tempo = _audioEngine!.getTempo();

      _audioEngine!.startRecording();
      _audioEngine!.startMidiRecording();

      _isCountingIn = true;
      _isMidiRecording = true;
      _tempo = tempo;
      notifyListeners();

      _startRecordingStateTimer();
    } catch (e) {
    }
  }

  /// Stop recording and return results
  RecordingResult stopRecording() {
    if (_audioEngine == null) {
      return RecordingResult();
    }

    try {
      final audioClipId = _audioEngine!.stopRecording();
      final midiClipId = _audioEngine!.stopMidiRecording();

      _isRecording = false;
      _isCountingIn = false;
      _isMidiRecording = false;
      notifyListeners();

      _recordingStateTimer?.cancel();
      _recordingStateTimer = null;

      final result = RecordingResult(
        audioClipId: audioClipId >= 0 ? audioClipId : null,
        midiClipId: midiClipId > 0 ? midiClipId : null,
        duration: audioClipId >= 0 ? _audioEngine!.getClipDuration(audioClipId) : null,
        waveformPeaks: audioClipId >= 0 ? _audioEngine!.getWaveformPeaks(audioClipId, 2000) : null,
        midiClipInfo: midiClipId > 0 ? _audioEngine!.getMidiClipInfo(midiClipId) : null,
      );

      onRecordingComplete?.call(result);
      return result;
    } catch (e) {
      _isRecording = false;
      _isCountingIn = false;
      _isMidiRecording = false;
      notifyListeners();
      return RecordingResult();
    }
  }

  void _startRecordingStateTimer() {
    _recordingStateTimer?.cancel();

    _recordingStateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_audioEngine == null || (!_isRecording && !_isCountingIn)) {
        timer.cancel();
        _recordingStateTimer = null;
        return;
      }

      final state = _audioEngine!.getRecordingState();

      if (state == 1 && !_isCountingIn) {
        _isCountingIn = true;
        notifyListeners();
      } else if (state == 2 && !_isRecording) {
        _isCountingIn = false;
        _isRecording = true;
        notifyListeners();
      } else if (state == 0 && (_isRecording || _isCountingIn)) {
        timer.cancel();
        _recordingStateTimer = null;
        _isRecording = false;
        _isCountingIn = false;
        notifyListeners();
      }
    });
  }

  /// Toggle metronome on/off
  void toggleMetronome() {
    if (_audioEngine == null) return;

    try {
      final newState = !_isMetronomeEnabled;
      _audioEngine!.setMetronomeEnabled(newState);
      _isMetronomeEnabled = newState;
      notifyListeners();
    } catch (e) {
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
    }
  }

  /// Toggle virtual piano
  bool toggleVirtualPiano() {
    if (_audioEngine == null) return false;

    _isVirtualPianoEnabled = !_isVirtualPianoEnabled;

    if (_isVirtualPianoEnabled) {
      try {
        _audioEngine!.startMidiInput();
        _audioEngine!.transportPlay();
        notifyListeners();
        return true;
      } catch (e) {
        _isVirtualPianoEnabled = false;
        notifyListeners();
        return false;
      }
    } else {
      notifyListeners();
      return true;
    }
  }

  void setVirtualPianoEnabled(bool enabled) {
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
    }
  }

  /// Refresh MIDI device list
  void refreshMidiDevices() {
    if (_audioEngine == null) return;

    try {
      _audioEngine!.refreshMidiDevices();
      loadMidiDevices();
    } catch (e) {
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
