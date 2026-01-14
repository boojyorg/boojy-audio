import 'dart:async';
import 'package:flutter/foundation.dart';
import '../audio_engine.dart';

/// Manages playback state and transport controls.
/// Handles play/pause/stop operations and playhead position updates.
///
/// PERFORMANCE NOTE: Playhead position updates use a separate ValueNotifier
/// to avoid triggering full widget rebuilds on every frame. Widgets that need
/// playhead updates should listen to [playheadNotifier] directly.
class PlaybackController extends ChangeNotifier {
  AudioEngine? _audioEngine;
  Timer? _playheadTimer;

  // Playback state
  double _playheadPosition = 0.0;
  bool _isPlaying = false;
  String _statusMessage = '';

  /// Separate notifier for playhead position to avoid triggering full rebuilds.
  /// Widgets needing real-time playhead updates should use ValueListenableBuilder
  /// with this notifier instead of listening to the main controller.
  final ValueNotifier<double> playheadNotifier = ValueNotifier(0.0);

  // Clip info for auto-stop
  double? _clipDuration;

  // Loop cycling state
  bool _isLoopCycling = false;
  double _loopStartBeats = 0.0;
  double _loopEndBeats = 4.0;
  double _loopTempo = 120.0;

  // Double-stop behavior state
  DateTime? _lastStopTime;
  static const _doubleStopThreshold = Duration(milliseconds: 500);

  // Loop playback enabled (from arrangement)
  bool _loopPlaybackEnabled = true;

  /// Set loop playback enabled state (from arrangement)
  void setLoopPlaybackEnabled({required bool enabled}) {
    _loopPlaybackEnabled = enabled;
  }

  /// Update loop bounds in real-time during playback.
  /// Call this when the user drags loop handles while playing.
  void updateLoopBounds({
    required double loopStartBeats,
    required double loopEndBeats,
  }) {
    _loopStartBeats = loopStartBeats;
    _loopEndBeats = loopEndBeats;

    // If currently playing and playhead is outside new loop bounds, seek to loop start
    if (_isLoopCycling && _isPlaying) {
      final loopStartSeconds = loopStartBeats * 60.0 / _loopTempo;
      final loopEndSeconds = loopEndBeats * 60.0 / _loopTempo;

      // If playhead is now outside the loop, bring it back in
      if (_playheadPosition < loopStartSeconds ||
          _playheadPosition >= loopEndSeconds) {
        _audioEngine?.transportSeek(loopStartSeconds);
        _playheadPosition = loopStartSeconds;
        playheadNotifier.value = _playheadPosition;
      }
    }
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
    required double tempo,
  }) {
    if (_audioEngine == null) return;

    try {
      // Store loop bounds and tempo for conversion
      _isLoopCycling = true;
      _loopStartBeats = loopStartBeats;
      _loopEndBeats = loopEndBeats;
      _loopTempo = tempo;

      // Convert beats to seconds for engine (which works in seconds)
      final loopStartSeconds = loopStartBeats * 60.0 / tempo;

      // Seek to loop start and play
      _audioEngine!.transportSeek(loopStartSeconds);
      _audioEngine!.transportPlay();
      _isPlaying = true;
      _playheadPosition = loopStartSeconds;
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
          // Return to loop start (convert beats to seconds)
          final loopStartSeconds = _loopStartBeats * 60.0 / _loopTempo;
          _playheadPosition = loopStartSeconds;
          _audioEngine!.transportSeek(loopStartSeconds);
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
        // pos is in SECONDS from the engine
        final pos = _audioEngine!.getPlayheadPosition();
        _playheadPosition = pos;

        // Loop cycling: jump back to start when reaching end
        if (_isLoopCycling) {
          // Convert loop bounds from beats to seconds for comparison
          final loopEndSeconds = _loopEndBeats * 60.0 / _loopTempo;
          final loopStartSeconds = _loopStartBeats * 60.0 / _loopTempo;

          if (pos >= loopEndSeconds) {
            _audioEngine!.transportSeek(loopStartSeconds);
            _playheadPosition = loopStartSeconds;
          }
        }

        // PERFORMANCE: Only update playhead notifier, not full controller.
        // This prevents 60fps full widget rebuilds during playback.
        // Widgets needing playhead updates use ValueListenableBuilder with playheadNotifier.
        playheadNotifier.value = _playheadPosition;

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
    playheadNotifier.dispose();
    super.dispose();
  }
}
