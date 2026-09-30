import 'package:boojy_audio/utils/track_naming.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isAutomaticTrackName', () {
    test('defaults and built-in instrument names are automatic', () {
      for (final name in [
        '',
        'MIDI',
        'MIDI 1',
        'MIDI 12',
        'Audio',
        'Audio 3',
        'Synthesizer',
        'Sampler',
        'Sampler: Kick 01',
        'Drum Kit',
      ]) {
        expect(isAutomaticTrackName(name), isTrue, reason: '"$name"');
      }
    });

    test("the current plugin's name is automatic", () {
      expect(isAutomaticTrackName('Serum', currentPluginName: 'Serum'), isTrue);
    });

    test('names the user typed are kept', () {
      for (final name in ['Lead Vocal', 'Bass', 'MIDI bass', 'Serum 2']) {
        expect(
          isAutomaticTrackName(name, currentPluginName: 'Serum'),
          isFalse,
          reason: '"$name"',
        );
      }
    });

    test('a plugin name counts only while that plugin is on the track', () {
      expect(isAutomaticTrackName('Serum'), isFalse);
      expect(
        isAutomaticTrackName('Serum', currentPluginName: 'Vital'),
        isFalse,
      );
    });
  });
}
