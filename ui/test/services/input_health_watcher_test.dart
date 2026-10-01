import 'package:boojy_audio/models/audio_input_status.dart';
import 'package:boojy_audio/services/input_health_watcher.dart';
import 'package:boojy_audio/widgets/shared/boojy_notice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final notices = Notices.instance;

  setUp(notices.reset);
  tearDown(notices.reset);

  group('AudioInputHealth.fromCode', () {
    test('decodes each engine state', () {
      expect(AudioInputHealth.fromCode(0).state, InputHealthState.closed);
      expect(AudioInputHealth.fromCode(1).state, InputHealthState.off);
      expect(AudioInputHealth.fromCode(2).state, InputHealthState.waiting);
      expect(AudioInputHealth.fromCode(3).state, InputHealthState.heard);
      expect(AudioInputHealth.fromCode(4).state, InputHealthState.silent);
      expect(AudioInputHealth.fromCode(5).state, InputHealthState.failed);
    });

    test('reads the feedback flag from bit 8', () {
      final health = AudioInputHealth.fromCode(3 | 256);
      expect(health.state, InputHealthState.heard);
      expect(health.feedbackGuarded, isTrue);
      expect(AudioInputHealth.fromCode(3).feedbackGuarded, isFalse);
    });

    test('an engine error or unknown code is unknown', () {
      expect(AudioInputHealth.fromCode(-1).state, InputHealthState.unknown);
      expect(AudioInputHealth.fromCode(99).state, InputHealthState.unknown);
    });

    test('only off, silent and failed are problems', () {
      expect(AudioInputHealth.fromCode(1).problem, contains('off'));
      expect(AudioInputHealth.fromCode(4).problem, contains("can't hear"));
      expect(AudioInputHealth.fromCode(5).problem, contains("can't hear"));
      for (final ok in [0, 2, 3]) {
        expect(AudioInputHealth.fromCode(ok).problem, isNull);
      }
    });
  });

  group('InputHealthWatcher', () {
    late AudioInputHealth current;
    late bool armed;
    late InputHealthWatcher watcher;

    setUp(() {
      current = const AudioInputHealth(InputHealthState.waiting);
      armed = true;
      watcher = InputHealthWatcher(
        readHealth: () => current,
        hasArmedAudioTrack: () => armed,
      );
    });

    List<String> problems() => notices.problems.map((n) => n.text).toList();

    test('says nothing while waiting for the first sound', () {
      watcher.tick();
      expect(problems(), isEmpty);
    });

    test('silence raises one notice and sound clears it', () {
      current = const AudioInputHealth(InputHealthState.silent);
      watcher.tick();
      watcher.tick();
      expect(problems(), ["Boojy can't hear your input"]);

      current = const AudioInputHealth(InputHealthState.heard);
      watcher.tick();
      expect(problems(), isEmpty);
    });

    test('a closed notice is not re-raised for the same problem', () {
      current = const AudioInputHealth(InputHealthState.silent);
      watcher.tick();
      Notices.clear(InputHealthWatcher.noticeId); // user closed it
      watcher.tick();
      expect(problems(), isEmpty);
    });

    test('input off is raised as soon as a track is armed', () {
      current = const AudioInputHealth(InputHealthState.off);
      watcher.tick();
      expect(problems().single, contains('off'));
    });

    test('disarming clears the notice', () {
      current = const AudioInputHealth(InputHealthState.failed);
      watcher.tick();
      expect(problems(), isNotEmpty);

      armed = false;
      watcher.tick();
      expect(problems(), isEmpty);
    });

    test('nothing is checked while no audio track is armed', () {
      armed = false;
      current = const AudioInputHealth(InputHealthState.silent);
      watcher.tick();
      expect(problems(), isEmpty);
    });

    test(
      'suggests headphones once per arming when monitoring is held back',
      () {
        current = const AudioInputHealth(
          InputHealthState.heard,
          feedbackGuarded: true,
        );
        watcher.tick();
        expect(notices.currentInfo?.text, 'Use headphones to hear yourself');

        notices.reset();
        watcher.tick();
        expect(notices.currentInfo, isNull);

        armed = false;
        watcher.tick();
        armed = true;
        watcher.tick();
        expect(notices.currentInfo?.text, 'Use headphones to hear yourself');
      },
    );
  });
}
