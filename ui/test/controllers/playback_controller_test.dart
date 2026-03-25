import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/controllers/playback_controller.dart';

void main() {
  late PlaybackController controller;

  setUp(() {
    controller = PlaybackController();
  });

  tearDown(() {
    controller.dispose();
  });

  // ---------------------------------------------------------------------------
  // Initial state
  // ---------------------------------------------------------------------------
  group('Initial state', () {
    test('isPlaying is false', () {
      expect(controller.isPlaying, isFalse);
    });

    test('playheadPosition is 0', () {
      expect(controller.playheadPosition, 0.0);
    });

    test('statusMessage is empty', () {
      expect(controller.statusMessage, isEmpty);
    });

    test('clipDuration is null', () {
      expect(controller.clipDuration, isNull);
    });

    test('playStartPosition is 0', () {
      expect(controller.playStartPosition, 0.0);
    });

    test('recordStartPosition is 0', () {
      expect(controller.recordStartPosition, 0.0);
    });
  });

  // ---------------------------------------------------------------------------
  // playheadNotifier
  // ---------------------------------------------------------------------------
  group('playheadNotifier', () {
    test('is a ValueNotifier', () {
      expect(controller.playheadNotifier, isA<ValueNotifier<double>>());
    });

    test('starts at 0', () {
      expect(controller.playheadNotifier.value, 0.0);
    });
  });

  // ---------------------------------------------------------------------------
  // setPlayheadPosition
  // ---------------------------------------------------------------------------
  group('setPlayheadPosition', () {
    test('updates playheadPosition', () {
      controller.setPlayheadPosition(5.0);
      expect(controller.playheadPosition, 5.0);
    });

    test('notifies listeners', () {
      var notified = false;
      controller.addListener(() => notified = true);
      controller.setPlayheadPosition(3.0);
      expect(notified, isTrue);
    });

    test('can be set to 0', () {
      controller.setPlayheadPosition(10.0);
      controller.setPlayheadPosition(0.0);
      expect(controller.playheadPosition, 0.0);
    });
  });

  // ---------------------------------------------------------------------------
  // setStatusMessage
  // ---------------------------------------------------------------------------
  group('setStatusMessage', () {
    test('updates statusMessage', () {
      controller.setStatusMessage('Ready');
      expect(controller.statusMessage, 'Ready');
    });

    test('notifies listeners', () {
      var notified = false;
      controller.addListener(() => notified = true);
      controller.setStatusMessage('Recording...');
      expect(notified, isTrue);
    });

    test('can be set to empty string', () {
      controller.setStatusMessage('Something');
      controller.setStatusMessage('');
      expect(controller.statusMessage, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // setClipDuration
  // ---------------------------------------------------------------------------
  group('setClipDuration', () {
    test('updates clipDuration', () {
      controller.setClipDuration(12.5);
      expect(controller.clipDuration, 12.5);
    });

    test('can be set to null', () {
      controller.setClipDuration(10.0);
      controller.setClipDuration(null);
      expect(controller.clipDuration, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // setRecordStartPosition
  // ---------------------------------------------------------------------------
  group('setRecordStartPosition', () {
    test('updates recordStartPosition', () {
      controller.setRecordStartPosition(2.5);
      expect(controller.recordStartPosition, 2.5);
    });
  });

  // ---------------------------------------------------------------------------
  // play() without engine
  // ---------------------------------------------------------------------------
  group('play() without engine', () {
    test('does not crash', () {
      expect(() => controller.play(), returnsNormally);
    });

    test('does not change isPlaying', () {
      controller.play();
      expect(controller.isPlaying, isFalse);
    });

    test('does not change statusMessage', () {
      controller.play();
      expect(controller.statusMessage, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // playLoop() without engine
  // ---------------------------------------------------------------------------
  group('playLoop() without engine', () {
    test('does not crash', () {
      expect(
        () => controller.playLoop(
          loopStartBeats: 0,
          loopEndBeats: 4,
          tempo: 120,
        ),
        returnsNormally,
      );
    });

    test('does not change isPlaying', () {
      controller.playLoop(
        loopStartBeats: 0,
        loopEndBeats: 4,
        tempo: 120,
      );
      expect(controller.isPlaying, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // pause() without engine
  // ---------------------------------------------------------------------------
  group('pause() without engine', () {
    test('does not crash', () {
      expect(() => controller.pause(), returnsNormally);
    });

    test('does not change isPlaying', () {
      controller.pause();
      expect(controller.isPlaying, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // stop() without engine
  // ---------------------------------------------------------------------------
  group('stop() without engine', () {
    test('does not crash', () {
      expect(() => controller.stop(), returnsNormally);
    });

    test('does not change isPlaying', () {
      controller.stop();
      expect(controller.isPlaying, isFalse);
    });

    test('does not change playheadPosition', () {
      controller.setPlayheadPosition(5.0);
      controller.stop();
      expect(controller.playheadPosition, 5.0);
    });
  });

  // ---------------------------------------------------------------------------
  // seek() without engine
  // ---------------------------------------------------------------------------
  group('seek() without engine', () {
    test('does not crash', () {
      expect(() => controller.seek(3.0), returnsNormally);
    });

    test('does not change position (engine is null)', () {
      controller.seek(3.0);
      // seek returns early when engine is null, so position stays at 0
      expect(controller.playheadPosition, 0.0);
    });
  });

  // ---------------------------------------------------------------------------
  // Listener notification
  // ---------------------------------------------------------------------------
  group('Listener notification', () {
    test('setPlayheadPosition triggers notifyListeners', () {
      var count = 0;
      controller.addListener(() => count++);

      controller.setPlayheadPosition(1.0);
      controller.setPlayheadPosition(2.0);
      controller.setPlayheadPosition(3.0);

      expect(count, 3);
    });

    test('setStatusMessage triggers notifyListeners', () {
      var count = 0;
      controller.addListener(() => count++);

      controller.setStatusMessage('A');
      controller.setStatusMessage('B');

      expect(count, 2);
    });

    test('removed listener is not notified', () {
      var count = 0;
      void listener() => count++;

      controller.addListener(listener);
      controller.setPlayheadPosition(1.0);
      expect(count, 1);

      controller.removeListener(listener);
      controller.setPlayheadPosition(2.0);
      expect(count, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // updateLoopBounds (no engine)
  // ---------------------------------------------------------------------------
  group('updateLoopBounds', () {
    test('does not crash without engine', () {
      expect(
        () => controller.updateLoopBounds(
          loopStartBeats: 2,
          loopEndBeats: 8,
        ),
        returnsNormally,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // onAutoStop callback
  // ---------------------------------------------------------------------------
  group('onAutoStop callback', () {
    test('is null initially', () {
      expect(controller.onAutoStop, isNull);
    });

    test('can be set', () {
      var called = false;
      controller.onAutoStop = () => called = true;
      controller.onAutoStop!();
      expect(called, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // startPlayheadPolling / stopPlayheadPolling without engine
  // ---------------------------------------------------------------------------
  group('playhead polling without engine', () {
    test('startPlayheadPolling does not crash', () {
      expect(
        () => controller.startPlayheadPolling(displayOffset: 1.0),
        returnsNormally,
      );
      // Clean up the timer that was started
      controller.stopPlayheadPolling();
    });

    test('stopPlayheadPolling does not crash', () {
      expect(() => controller.stopPlayheadPolling(), returnsNormally);
    });
  });
}
