import 'package:boojy_audio/models/audio_input_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioInputStatus.parse', () {
    test('reads a connected device', () {
      final s = AudioInputStatus.parse('0|0|2|Scarlett 2i2 USB');
      expect(s.isOff, isFalse);
      expect(s.fellBack, isFalse);
      expect(s.channelCount, 2);
      expect(s.deviceName, 'Scarlett 2i2 USB');
    });

    test('keeps a | inside the device name', () {
      expect(
        AudioInputStatus.parse('0|1|1|Mic | Left').deviceName,
        'Mic | Left',
      );
    });

    test('an engine error reads as unknown', () {
      expect(
        identical(
          AudioInputStatus.parse('Error: no graph'),
          AudioInputStatus.unknown,
        ),
        isTrue,
      );
    });
  });

  group('AudioInputStatus.notice', () {
    test('nothing to say when the input is as chosen', () {
      expect(AudioInputStatus.parse('0|0|2|Scarlett 2i2 USB').notice(), isNull);
    });

    test('says when input is off', () {
      expect(AudioInputStatus.parse('1|0|0|').notice(), contains('off'));
    });

    test('says when nothing is connected', () {
      expect(
        AudioInputStatus.parse('0|0|0|').notice(),
        contains('No audio input'),
      );
    });

    test('names both devices when a pinned device is missing', () {
      final notice = AudioInputStatus.parse(
        '0|1|1|MacBook Air Microphone',
      ).notice(preferred: 'Scarlett 2i2 USB');
      expect(
        notice,
        "Scarlett 2i2 USB isn't connected, using MacBook Air Microphone.",
      );
    });

    test('stays quiet when the engine did not answer', () {
      expect(AudioInputStatus.unknown.notice(), isNull);
    });
  });
}
