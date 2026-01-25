import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/library_item.dart';
import 'commands/audio_engine_interface.dart';

/// Service for managing library audio preview playback.
/// Handles loading, playing, and stopping audio file previews,
/// as well as synth preset previews.
class LibraryPreviewService extends ChangeNotifier {
  final AudioEngineInterface _audioEngine;

  // Audition state
  bool _auditionEnabled = true;
  static const String _auditionEnabledKey = 'libraryAuditionEnabled';

  // Current preview state
  String? _currentFilePath;
  String? _currentFileName;
  bool _isPlaying = false;
  double _position = 0.0;
  double _duration = 0.0;
  List<double> _waveformPeaks = [];

  // For synth preset preview
  int? _previewTrackId;
  Timer? _noteOffTimer;
  Timer? _positionTimer;

  // Recording state (to disable preview during recording)
  bool _isRecording = false;

  LibraryPreviewService(this._audioEngine) {
    _loadAuditionPreference();
  }

  // Getters
  bool get auditionEnabled => _auditionEnabled;
  String? get currentFilePath => _currentFilePath;
  String? get currentFileName => _currentFileName;
  bool get isPlaying => _isPlaying;
  double get position => _position;
  double get duration => _duration;
  List<double> get waveformPeaks => _waveformPeaks;
  bool get hasLoadedFile => _currentFilePath != null;

  /// Load audition preference from shared preferences
  Future<void> _loadAuditionPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _auditionEnabled = prefs.getBool(_auditionEnabledKey) ?? true;
      notifyListeners();
    } catch (e) {
      // Default to true if loading fails
      _auditionEnabled = true;
    }
  }

  /// Save audition preference to shared preferences
  Future<void> _saveAuditionPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_auditionEnabledKey, _auditionEnabled);
    } catch (e) {
      // Ignore save errors
    }
  }

  /// Toggle audition on/off
  void toggleAudition() {
    _auditionEnabled = !_auditionEnabled;
    _saveAuditionPreference();

    // Stop current preview if audition is disabled
    if (!_auditionEnabled) {
      stop();
    }
    notifyListeners();
  }

  /// Set recording state (preview disabled during recording)
  void setRecordingState(bool isRecording) {
    _isRecording = isRecording;
    if (isRecording) {
      stop();
    }
  }

  /// Load and preview an audio file
  void loadAndPreviewAudio(String path, String name) {
    if (_isRecording) return;
    if (!_auditionEnabled) return;

    // Stop any current preview
    _stopPositionTimer();
    _stopNoteOffTimer();

    // Load the file
    final result = _audioEngine.previewLoadAudio(path);
    if (result.startsWith('Error')) {
      return;
    }

    _currentFilePath = path;
    _currentFileName = name;
    _duration = _audioEngine.previewGetDuration();
    _position = 0.0;

    // Set looping based on duration (< 3 seconds = loop)
    final shouldLoop = _duration < 3.0;
    _audioEngine.previewSetLooping(shouldLoop);

    // Get waveform (resolution based on typical preview bar width)
    _waveformPeaks = _audioEngine.previewGetWaveform(200);

    // Start playback
    _audioEngine.previewPlay();
    _isPlaying = true;

    // Start position timer
    _startPositionTimer();

    notifyListeners();
  }

  /// Preview a synth preset by playing Middle C for 2 seconds
  void previewSynthPreset(PresetItem preset) {
    if (_isRecording) return;
    if (!_auditionEnabled) return;

    // Stop any current audio preview
    stop();

    // For synth preset preview, we need a hidden preview track
    // This will be implemented when we integrate with the track system
    // For now, we'll use the track synth manager directly

    // TODO: Create hidden preview track and play MIDI note
    // _ensurePreviewTrack();
    // _audioEngine.setTrackInstrument(_previewTrackId!, preset.instrumentId);
    // _audioEngine.sendTrackMidiNoteOn(_previewTrackId!, 60, 100); // C4
    //
    // _noteOffTimer = Timer(const Duration(seconds: 2), () {
    //   _audioEngine.sendTrackMidiNoteOff(_previewTrackId!, 60, 64);
    //   notifyListeners();
    // });

    notifyListeners();
  }

  /// Start/resume playback
  void play() {
    if (_currentFilePath == null) return;
    if (_isRecording) return;

    _audioEngine.previewPlay();
    _isPlaying = true;
    _startPositionTimer();
    notifyListeners();
  }

  /// Stop playback with fade out
  void stop() {
    _audioEngine.previewStop();
    _isPlaying = false;
    _stopPositionTimer();
    _stopNoteOffTimer();
    notifyListeners();
  }

  /// Seek to a position in seconds
  void seek(double positionSeconds) {
    _audioEngine.previewSeek(positionSeconds);
    _position = positionSeconds;
    notifyListeners();
  }

  /// Called when selection changes in library panel
  void onSelectionChanged(String? newPath) {
    if (newPath != _currentFilePath) {
      stop();
    }
  }

  /// Called when drag starts in library panel
  void onDragStarted() {
    stop();
  }

  /// Start position update timer
  void _startPositionTimer() {
    _stopPositionTimer();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_isPlaying) {
        _stopPositionTimer();
        return;
      }

      _position = _audioEngine.previewGetPosition();
      final isStillPlaying = _audioEngine.previewIsPlaying();

      if (!isStillPlaying) {
        // Playback ended
        _isPlaying = false;
        _stopPositionTimer();
      }

      notifyListeners();
    });
  }

  /// Stop position update timer
  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  /// Stop note-off timer (for synth preset preview)
  void _stopNoteOffTimer() {
    _noteOffTimer?.cancel();
    _noteOffTimer = null;
  }

  /// Clear the current preview
  void clear() {
    stop();
    _currentFilePath = null;
    _currentFileName = null;
    _duration = 0.0;
    _position = 0.0;
    _waveformPeaks = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _stopPositionTimer();
    _stopNoteOffTimer();
    stop();
    super.dispose();
  }
}
