import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/services/clip_naming_service.dart';
import 'package:boojy_audio/models/instrument_data.dart';
import 'package:boojy_audio/models/midi_note_data.dart';

void main() {
  group('ClipNamingService', () {
    group('generateClipName', () {
      test('VST3 instrument returns plugin name', () {
        final instrument = InstrumentData.vst3Instrument(
          trackId: 1,
          pluginPath: '/path/to/plugin.vst3',
          pluginName: 'Serum',
        );

        final result = ClipNamingService.generateClipName(
          instrument: instrument,
          trackName: 'Track 1',
        );

        expect(result, 'Serum');
      });

      test('synthesizer instrument returns Synthesizer', () {
        final instrument = InstrumentData.defaultSynthesizer(1);

        final result = ClipNamingService.generateClipName(
          instrument: instrument,
          trackName: 'Track 1',
        );

        expect(result, 'Synthesizer');
      });

      test('no instrument with track name returns track name', () {
        final result = ClipNamingService.generateClipName(
          instrument: null,
          trackName: 'My Track',
        );

        expect(result, 'My Track');
      });

      test('no instrument with empty track name returns MIDI', () {
        final result = ClipNamingService.generateClipName(
          instrument: null,
          trackName: '',
        );

        expect(result, 'MIDI');
      });

      test('no instrument with null track name returns MIDI', () {
        final result = ClipNamingService.generateClipName(
          instrument: null,
          trackName: null,
        );

        expect(result, 'MIDI');
      });

      test('null instrument returns track name if available', () {
        final result = ClipNamingService.generateClipName(
          instrument: null,
          trackName: 'Bass',
        );

        expect(result, 'Bass');
      });
    });

    group('countPatternInstances', () {
      test('returns count of clips with same patternId on same track', () {
        final clips = [
          MidiClipData(
            clipId: 1,
            trackId: 1,
            startTime: 0.0,
            duration: 4.0,
            name: 'Clip 1',
            patternId: 'pattern-a',
          ),
          MidiClipData(
            clipId: 2,
            trackId: 1,
            startTime: 4.0,
            duration: 4.0,
            name: 'Clip 2',
            patternId: 'pattern-a',
          ),
          MidiClipData(
            clipId: 3,
            trackId: 1,
            startTime: 8.0,
            duration: 4.0,
            name: 'Clip 3',
            patternId: 'pattern-b',
          ),
          MidiClipData(
            clipId: 4,
            trackId: 2,
            startTime: 0.0,
            duration: 4.0,
            name: 'Clip 4',
            patternId: 'pattern-a',
          ),
        ];

        final count = ClipNamingService.countPatternInstances(
          clips,
          1,
          'pattern-a',
        );

        expect(count, 2);
      });

      test('returns 1 when patternId is null', () {
        final clips = [
          MidiClipData(
            clipId: 1,
            trackId: 1,
            startTime: 0.0,
            duration: 4.0,
            name: 'Clip 1',
          ),
        ];

        final count = ClipNamingService.countPatternInstances(
          clips,
          1,
          null,
        );

        expect(count, 1);
      });
    });

    group('countClipsWithName', () {
      test('returns count of clips with same name on same track', () {
        final clips = [
          MidiClipData(
            clipId: 1,
            trackId: 1,
            startTime: 0.0,
            duration: 4.0,
            name: 'Serum',
          ),
          MidiClipData(
            clipId: 2,
            trackId: 1,
            startTime: 4.0,
            duration: 4.0,
            name: 'Serum',
          ),
          MidiClipData(
            clipId: 3,
            trackId: 1,
            startTime: 8.0,
            duration: 4.0,
            name: 'Other',
          ),
          MidiClipData(
            clipId: 4,
            trackId: 2,
            startTime: 0.0,
            duration: 4.0,
            name: 'Serum',
          ),
        ];

        final count = ClipNamingService.countClipsWithName(
          clips,
          1,
          'Serum',
        );

        expect(count, 2);
      });
    });
  });
}
