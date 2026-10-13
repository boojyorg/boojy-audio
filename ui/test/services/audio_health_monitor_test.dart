import 'package:boojy_audio/services/audio_health_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> health({
  int late = 0,
  int missed = 0,
  int peak = 40,
  int trackWaits = 0,
  int effectWaits = 0,
}) => {
  'lateBuffers': late,
  'missedBuffers': missed,
  'peakLoadPercent': peak,
  'synthLockWaits': 0,
  'effectLockWaits': effectWaits,
  'trackLockWaits': trackWaits,
  'recorderLockWaits': 0,
  'bufferFrames': 128,
  'sampleRate': 48000,
};

void main() {
  late List<Map<String, Object?>?> readings;
  late List<String> lines;
  late AudioHealthMonitor monitor;

  setUp(() {
    AudioHealthMonitor.dropoutsThisSession.value = 0;
    readings = [];
    lines = [];
    monitor = AudioHealthMonitor(
      readHealth: () => readings.removeAt(0),
      describeContext: () => 'playing at 1:23.4 · 12 tracks, 3 plugins',
      writeLine: lines.add,
    );
  });

  void tickThrough(List<Map<String, Object?>?> sequence) {
    readings = [...sequence];
    while (readings.isNotEmpty) {
      monitor.tick();
    }
  }

  test('a healthy session writes nothing and counts nothing', () {
    tickThrough([health(), health(), health()]);
    expect(lines, isEmpty);
    expect(AudioHealthMonitor.dropoutsThisSession.value, 0);
  });

  test('dropouts before Boojy started watching are not counted', () {
    tickThrough([health(late: 5, missed: 7), health(late: 5, missed: 7)]);
    expect(lines, isEmpty);
    expect(AudioHealthMonitor.dropoutsThisSession.value, 0);
  });

  test('a dropout writes one line saying what was going on', () {
    tickThrough([
      health(),
      health(late: 2, missed: 1, peak: 112, trackWaits: 1),
    ]);
    expect(
      lines.single,
      'Dropout ×2 (2 late, 1 skipped) · playing at 1:23.4 · 12 tracks, '
      '3 plugins · buffer 128 @ 48 kHz · busiest buffer 112% · '
      'waited on: tracks ×1',
    );
    expect(AudioHealthMonitor.dropoutsThisSession.value, 2);
  });

  test('a skip with no late buffer came from outside Boojy', () {
    tickThrough([health(), health(missed: 1, peak: 30)]);
    expect(lines.single, startsWith('Dropout ×1 (1 skipped) · '));
    expect(lines.single, isNot(contains('waited on')));
  });

  test('the session count adds up across seconds', () {
    tickThrough([
      health(),
      health(late: 1, missed: 1),
      health(late: 1, missed: 1),
      health(late: 1, missed: 4, effectWaits: 2),
    ]);
    expect(lines, hasLength(2));
    expect(lines.last, contains('waited on: effects ×2'));
    expect(AudioHealthMonitor.dropoutsThisSession.value, 4);
  });

  test('an engine that cannot answer is skipped, not counted', () {
    tickThrough([health(), null, health(late: 1)]);
    expect(lines, hasLength(1));
    expect(AudioHealthMonitor.dropoutsThisSession.value, 1);
  });
}
