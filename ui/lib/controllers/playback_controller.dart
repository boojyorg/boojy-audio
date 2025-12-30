import 'dart:async';
import 'package:flutter/foundation.dart';
import '../audio_engine.dart';

/// Manages playback state and transport controls.
/// Handles play/pause/stop operations and playhead position updates.
class PlaybackController extends ChangeNotifier {
  AudioEngine? _audioEngine;
  Timer? _playheadTimer;

  // Playback state
  double _playheadPosition = 0.0;
  bool _isPlaying = false;
  String _statusMessage = '';

  // Clip info for auto-stop
  double? _clipDuration;

  // Loop cycling state
  bool _isLoopCycling = false;
  double _loopStartBeats = 0.0;
  double _loopEndBeats = 4.0;

  // Callback for auto-stop at end of clip
  VoidCallback? onAutoStop;

  PlaybackController();

  // Getters
  double get playheadPosition => _playheadPosition;
  bool get isPlaying => _isPlaying;
  String get statusMessage => _statusMessage;
  double? get clipDuration => _clipDuration;

  /// Initialize with audio engine reference
  void initialize(AudioEngine engine) {
    _audioEngine = engine;
  }

  /// Set clip duration for auto-stop functionality
  void setClipDuration(double? duration) {
    _clipDuration = duration;
  }

  /// Start playback
  void play({int? loadedClipId}) {
    if (_audioEngine == null) return;

    try {
      _isLoopCycling = false; // Disable loop cycling for normal play
      _audioEngine!.transportPlay();
      _isPlaying = true;
      _statusMessage = loadedClipId != null ? 'Playing...' : 'Playing (empty)';
      notifyListeners();
      _startPlayheadTimer();
    } catch (e) {
      _statusMessage = 'Play error: $e';
      notifyListeners();
    }
  }

  /// Start playback with loop cycling (Piano Roll context)
  /// Plays from loopStart to loopEnd, then jumps back to loopStart forever
  void playLoop({
    int? loadedClipId,
    required double loopStartBeats,
    required double loopEndBeats,
  }) {
    if (_audioEngine == null) return;

    try {
      // Store loop bounds
      _isLoopCycling = true;
      _loopStartBeats = loopStartBeats;
      _loopEndBeats = loopEndBeats;

      // Seek to loop start and play
      _audioEngine!.transportSeek(loopStartBeats);
      _audioEngine!.transportPlay();
      _isPlaying = true;
      _playheadPosition = loopStartBeats;
      _statusMessage = 'Playing loop...';
      notifyListeners();
      _startPlayheadTimer();
    } catch (e) {
      _statusMessage = 'Play loop error: $e';
      notifyListeners();
    }
  }

  /// Pause playback
  void pause() {
    if (_audioEngine == null) return;

    try {
      _audioEngine!.transportPause();
      _isPlaying = false;
      _statusMessage = 'Paused';
      notifyListeners();
      _stopPlayheadTimer();
    } catch (e) {
      _statusMessage = 'Pause error: $e';
      notifyListeners();
    }
  }

  /// Stop playback and reset position
  void stop() {
    if (_audioEngine == null) {
      return;
    }

    try {
      _audioEngine!.transportStop();

      _isPlaying = false;
      _playheadPosition = 0.0;
      _statusMessage = 'Stopped';
      notifyListeners();
      _stopPlayheadTimer();
    } catch (e) {
      _statusMessage = 'Stop error: $e';
      notifyListeners();
    }
  }

  /// Seek to a specific position
  void seek(double position) {
    if (_audioEngine == null) return;
    _audioEngine!.transportSeek(position);
    _playheadPosition = position;
    notifyListeners();
  }

  /// Update playhead position (called externally if needed)
  void setPlayheadPosition(double position) {
    _playheadPosition = position;
    notifyListeners();
  }

  /// Update status message
  void setStatusMessage(String message) {
    _statusMessage = message;
    notifyListeners();
  }

  void _startPlayheadTimer() {
    _playheadTimer?.cancel();
    // 16ms = ~60fps for smooth visual playhead updates
    _playheadTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (_audioEngine != null) {
        final pos = _audioEngine!.getPlayheadPosition();
        _playheadPosition = pos;

        // Loop cycling: jump back to start when reaching end
        if (_isLoopCycling && pos >= _loopEndBeats) {
          _audioEngine!.transportSeek(_loopStartBeats);
          _playheadPosition = _loopStartBeats;
        }

        notifyListeners();

        // Auto-stop at end of clip (only when not loop cycling)
        if (!_isLoopCycling && _clipDuration != null && pos >= _clipDuration!) {
          stop();
          onAutoStop?.call();
        }
      }
    });
  }

  void _stopPlayheadTimer() {
    _playheadTimer?.cancel();
    _playheadTimer = null;
  }

  @override
  void dispose() {
    _stopPlayheadTimer();
    super.dispose();
  }
}
