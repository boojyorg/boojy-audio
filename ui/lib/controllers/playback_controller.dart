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

  // Position tracking for Stop button behavior
  double _playStartPosition = 0.0;  // Position when Play pressed
  double _recordStartPosition = 0.0; // Position when recording starts (after count-in)

  // Display offset for recording (subtracted from engine position so count-in
  // doesn't visually advance the playhead)
  double _playheadDisplayOffset = 0.0;

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
  double get playStartPosition => _playStartPosition;
  double get recordStartPosition => _recordStartPosition;

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
      // Save current playhead position as play start position
      _playStartPosition = _audioEngine!.getPlayheadPosition();
      debugPrint('▶️ [PLAYBACK] play() - saving playStartPosition: ${_playStartPosition.toStringAsFixed(3)}s');

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
      final loopEndSeconds = loopEndBeats * 60.0 / tempo;

      // Only seek to loop start if playhead is outside loop bounds
      // This allows resuming from current position within the loop
      if (_playheadPosition < loopStartSeconds || _playheadPosition >= loopEndSeconds) {
        _audioEngine!.transportSeek(loopStartSeconds);
        _playheadPosition = loopStartSeconds;
      }

      _audioEngine!.transportPlay();
      _isPlaying = true;
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

  /// Stop playback and return to start position.
  /// If [isRecording] is true, returns to recordStartPosition.
  /// If currently playing, returns to playStartPosition.
  /// If idle (not playing), returns to bar 1 (position 0.0).
  void stop({bool isRecording = false}) {
    if (_audioEngine == null) {
      return;
    }

    try {
      final wasPlaying = _isPlaying;
      debugPrint('▶️ [PLAYBACK] stop(isRecording=$isRecording, wasPlaying=$wasPlaying): '
          'playheadPos=${_playheadPosition.toStringAsFixed(3)}s, '
          'displayOffset=${_playheadDisplayOffset.toStringAsFixed(3)}s');

      _audioEngine!.transportStop();
      _isPlaying = false;
      _playheadDisplayOffset = 0.0;
      _stopPlayheadTimer();

      // Return to appropriate start position
      if (isRecording) {
        _playheadPosition = _recordStartPosition;
        _audioEngine!.transportSeek(_recordStartPosition);
        playheadNotifier.value = _recordStartPosition;
        _statusMessage = 'Stopped (recording start)';
        debugPrint('▶️ [PLAYBACK] Returning to recordStartPosition: ${_recordStartPosition.toStringAsFixed(3)}s');
      } else if (wasPlaying) {
        _playheadPosition = _playStartPosition;
        _audioEngine!.transportSeek(_playStartPosition);
        playheadNotifier.value = _playStartPosition;
        _statusMessage = 'Stopped (playback start)';
        debugPrint('▶️ [PLAYBACK] Returning to playStartPosition: ${_playStartPosition.toStringAsFixed(3)}s');
      } else {
        // Idle (not playing) - return to bar 1
        _playheadPosition = 0.0;
        _audioEngine!.transportSeek(0.0);
        playheadNotifier.value = 0.0;
        _statusMessage = 'Stopped (bar 1)';
        debugPrint('▶️ [PLAYBACK] Returning to bar 1 (idle state)');
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
    playheadNotifier.value = position;
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

  /// Set record start position (called when recording actually begins after count-in)
  void setRecordStartPosition(double position) {
    _recordStartPosition = position;
    debugPrint('▶️ [PLAYBACK] setRecordStartPosition: ${position.toStringAsFixed(3)}s');
  }

  /// Start polling the engine for playhead position updates (60fps).
  /// Used during recording when the engine transport is running but
  /// PlaybackController.play() was not called.
  /// [displayOffset] is subtracted from the engine position so that count-in
  /// time doesn't visually advance the playhead.
  void startPlayheadPolling({double displayOffset = 0.0}) {
    debugPrint('▶️ [PLAYBACK] startPlayheadPolling(displayOffset=${displayOffset.toStringAsFixed(3)}s)');
    _playheadDisplayOffset = displayOffset;
    _startPlayheadTimer();
  }

  /// Stop polling the engine for playhead position updates.
  /// Used when recording stops.
  void stopPlayheadPolling() => _stopPlayheadTimer();

  int _playheadLogCounter = 0; // For throttled debug logging

  void _startPlayheadTimer() {
    _playheadTimer?.cancel();
    _playheadLogCounter = 0;
    // 16ms = ~60fps for smooth visual playhead updates
    _playheadTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (_audioEngine != null) {
        // pos is in SECONDS from the engine
        final pos = _audioEngine!.getPlayheadPosition();
        _playheadPosition = pos - _playheadDisplayOffset;

        // Log once per second (~60 frames) to avoid spam
        _playheadLogCounter++;
        if (_playheadLogCounter % 60 == 1) {
          debugPrint('▶️ [PLAYBACK] timer: enginePos=${pos.toStringAsFixed(3)}s, '
              'offset=${_playheadDisplayOffset.toStringAsFixed(3)}s, '
              'displayPos=${_playheadPosition.toStringAsFixed(3)}s');
        }

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
