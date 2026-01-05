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

  // Double-stop behavior state
  DateTime? _lastStopTime;
  static const _doubleStopThreshold = Duration(milliseconds: 500);

  // Loop playback enabled (from arrangement)
  bool _loopPlaybackEnabled = true;

  /// Set loop playback enabled state (from arrangement)
  void setLoopPlaybackEnabled({required bool enabled}) {
    _loopPlaybackEnabled = enabled;
  }

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

  /// Stop playback with double-stop behavior.
  /// First stop: pause at current position
  /// Second stop (within 500ms): return to loop start (if loop enabled) or bar 1
  void stop() {
    if (_audioEngine == null) {
      return;
    }

    try {
      final now = DateTime.now();
      final isDoubleStop = _lastStopTime != null &&
          now.difference(_lastStopTime!) < _doubleStopThreshold;

      _audioEngine!.transportStop();
      _isPlaying = false;
      _stopPlayheadTimer();

      if (isDoubleStop) {
        // Second stop: return to loop start or bar 1
        if (_loopPlaybackEnabled) {
          // Return to loop start
          _playheadPosition = _loopStartBeats;
          _audioEngine!.transportSeek(_loopStartBeats);
          _statusMessage = 'Stopped (loop start)';
        } else {
          // Return to bar 1 (beat 0)
          _playheadPosition = 0.0;
          _audioEngine!.transportSeek(0.0);
          _statusMessage = 'Stopped (bar 1)';
        }
        _lastStopTime = null; // Reset for next double-stop
      } else {
        // First stop: just pause at current position
        _statusMessage = 'Stopped';
        _lastStopTime = now;
      }

      notifyListeners();
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
