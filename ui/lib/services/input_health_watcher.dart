import 'dart:async';

import '../models/audio_input_status.dart';
import '../widgets/shared/boojy_notice.dart';

/// Watches the audio input while an audio track is armed and says so when
/// Boojy can't hear it: input off, failed to open, or exact digital silence
/// (a closed-lid laptop mic or a denied microphone permission). Clears the
/// notice once sound arrives. Also suggests headphones once when arming held
/// monitoring back to avoid feedback.
class InputHealthWatcher {
  /// Notice id, shared with the record-time input warning so they replace
  /// each other instead of stacking.
  static const noticeId = 'audio-input';

  static const pollInterval = Duration(milliseconds: 500);

  final AudioInputHealth Function() readHealth;
  final bool Function() hasArmedAudioTrack;
  final NoticeAction? settingsAction;

  Timer? _timer;
  String? _shownProblem;
  bool _headphonesHintShown = false;

  InputHealthWatcher({
    required this.readHealth,
    required this.hasArmedAudioTrack,
    this.settingsAction,
  });

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => tick());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  /// One check. Public so tests can drive it without a timer.
  void tick() {
    if (!hasArmedAudioTrack()) {
      _clearProblem();
      _headphonesHintShown = false;
      return;
    }

    final health = readHealth();
    if (health.state == InputHealthState.unknown) return;

    if (health.feedbackGuarded && !_headphonesHintShown) {
      _headphonesHintShown = true;
      Notices.info('Use headphones to hear yourself');
    }

    final problem = health.problem;
    if (problem != null) {
      if (problem != _shownProblem) {
        _shownProblem = problem;
        Notices.problem(problem, id: noticeId, action: settingsAction);
      }
    } else if (health.state == InputHealthState.heard ||
        health.state == InputHealthState.closed) {
      _clearProblem();
    }
  }

  void _clearProblem() {
    if (_shownProblem == null) return;
    _shownProblem = null;
    Notices.clear(noticeId);
  }
}
