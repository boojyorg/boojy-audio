import 'dart:async';

import 'package:flutter/foundation.dart';

import 'log_file.dart';

/// Reads the engine's audio health counters once a second and writes a line
/// to the local log for each second with a dropout, saying what was going on.
/// Silent while healthy: nothing shows on screen except the session count in
/// Settings ([dropoutsThisSession]).
///
/// A dropout is counted two ways by the engine: **late** (Boojy took longer
/// to render a buffer than the buffer lasts) and **skipped** (the sound
/// card's timestamps jumped a buffer, whatever the cause). One crackle often
/// shows up as both, so a second counts the larger of the two.
///
/// The microphone's input skipping (it ran ahead of or fell behind the
/// output, e.g. two devices on different clocks) gets a line of its own: it
/// glitches what you hear of yourself and the take, not the playback.
class AudioHealthMonitor {
  static const pollInterval = Duration(seconds: 1);

  /// Dropouts since launch, for Settings.
  static final dropoutsThisSession = ValueNotifier<int>(0);

  /// The engine's counters (`getAudioHealth`), or null if it can't answer.
  final Map<String, Object?>? Function() readHealth;

  /// What the user was doing, e.g. `playing at 1:23.4 · 12 tracks,
  /// 3 plugins · last action: Move Clip`.
  final String Function() describeContext;

  /// Where lines go; the log file unless a test swaps it.
  final void Function(String line) writeLine;

  Timer? _timer;
  Map<String, int>? _last;

  AudioHealthMonitor({
    required this.readHealth,
    required this.describeContext,
    this.writeLine = LogFile.write,
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
    final raw = readHealth();
    if (raw == null) return;
    final now = {
      for (final e in raw.entries)
        if (e.value is num) e.key: (e.value! as num).toInt(),
    };
    final last = _last;
    _last = now;
    if (last == null) return; // First reading is the baseline.

    int delta(String key) => (now[key] ?? 0) - (last[key] ?? 0);
    final inputSkips = delta('inputSkips');
    if (inputSkips > 0) {
      writeLine(
        [
          'Input skipped ×$inputSkips (microphone ran ahead or fell behind)',
          describeContext(),
        ].join(' · '),
      );
    }
    final late = delta('lateBuffers');
    final skipped = delta('missedBuffers');
    final dropouts = late > skipped ? late : skipped;
    if (dropouts <= 0) return;

    dropoutsThisSession.value += dropouts;

    final kinds = [
      if (late > 0) '$late late',
      if (skipped > 0) '$skipped skipped',
    ].join(', ');
    final waits = [
      for (final (key, name) in const [
        ('trackLockWaits', 'tracks'),
        ('effectLockWaits', 'effects'),
        ('synthLockWaits', 'synths'),
        ('recorderLockWaits', 'recorder'),
      ])
        if (delta(key) > 0) '$name ×${delta(key)}',
    ];
    final frames = now['bufferFrames'] ?? 0;
    final rate = now['sampleRate'] ?? 0;
    final khz = (rate / 1000).toStringAsFixed(rate % 1000 == 0 ? 0 : 1);

    writeLine(
      [
        'Dropout ×$dropouts ($kinds)',
        describeContext(),
        'buffer $frames @ $khz kHz',
        'busiest buffer ${now['peakLoadPercent'] ?? 0}%',
        if (waits.isNotEmpty) 'waited on: ${waits.join(', ')}',
      ].join(' · '),
    );
  }
}
