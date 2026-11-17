import 'package:boojy_audio/utils/audio_file_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('missingSamplesMessage', () {
    test('nothing missing posts nothing', () {
      expect(missingSamplesMessage(const []), isNull);
    });

    test('one missing sample is named', () {
      expect(
        missingSamplesMessage(const ['kick.wav']),
        "Couldn't find the sample kick.wav. "
        'It stays silent until you load it again.',
      );
    });

    test('a sample used by several pads is listed once', () {
      expect(
        missingSamplesMessage(const ['kick.wav', 'kick.wav', 'snare.wav']),
        "Couldn't find 2 samples: kick.wav, snare.wav. "
        'They stay silent until you load them again.',
      );
    });

    test('a long list is cut to three names', () {
      expect(
        missingSamplesMessage(const [
          'a.wav',
          'b.wav',
          'c.wav',
          'd.wav',
          'e.wav',
        ]),
        "Couldn't find 5 samples: a.wav, b.wav, c.wav and 2 more. "
        'They stay silent until you load them again.',
      );
    });
  });
}
