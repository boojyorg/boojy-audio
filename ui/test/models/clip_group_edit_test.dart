import 'package:boojy_audio/models/audio_clip_edit_data.dart';
import 'package:boojy_audio/models/clip_group_edit.dart';
import 'package:flutter_test/flutter_test.dart';

AudioClipEditData pitched(int semitones, [int cents = 0]) =>
    AudioClipEditData(transposeSemitones: semitones, fineCents: cents);

AudioClipEditData gained(double db) => AudioClipEditData(gainDb: db);

void main() {
  group('pitch', () {
    final clips = [pitched(-1), pitched(-2), pitched(0)];

    test('a shift moves every clip and keeps their differences', () {
      final shifted = clips.map(const ShiftPitch(-200).applyTo);
      expect(shifted.map((e) => e.transposeSemitones), [-3, -4, -2]);
    });

    test('typed semitones set every clip, each keeping its cents', () {
      final set = [
        pitched(-1, 20),
        pitched(3),
      ].map(const SetSemitones(-2).applyTo).toList();
      expect(set.map((e) => e.transposeSemitones), [-2, -2]);
      expect(set.map((e) => e.fineCents), [20, 0]);
    });

    test('typed cents past ±50 carry into the semitones', () {
      final set = const SetCents(70).applyTo(pitched(2));
      expect((set.transposeSemitones, set.fineCents), (3, -30));
    });

    test('a cents shift carries over a semitone', () {
      final shifted = const ShiftPitch(30).applyTo(pitched(0, 40));
      expect((shifted.transposeSemitones, shifted.fineCents), (1, -30));
    });

    test('+50 ct stays +50 ct', () {
      expect(splitPitchCents(50), (0, 50));
      expect(splitPitchCents(-150), (-1, -50));
      expect(splitPitchCents(maxPitchCents), (48, 50));
    });

    test('the group stops together at the limit', () {
      final group = ClipGroup.of([pitched(46), pitched(40)])!;
      // 46 can go up 2 st and 50 ct.
      expect(group.clampPitchShift(500), 250);
      expect(group.clampPitchShift(500, wholeSemitones: true), 200);
      expect(group.clampPitchShift(-500), -500);
    });

    test('the summary shows the spread', () {
      final group = ClipGroup.of(clips)!;
      expect(group.count, 3);
      expect((group.lowSemitones, group.highSemitones), (-2, 0));
      expect((group.lowCents, group.highCents), (0, 0));
    });

    test('one clip is no group', () {
      expect(ClipGroup.of([pitched(0)]), isNull);
    });
  });

  group('volume', () {
    test('a shift moves every clip by the same dB', () {
      final shifted = [
        gained(0),
        gained(-2),
        gained(1),
      ].map(const ShiftGain(-3).applyTo);
      expect(shifted.map((e) => e.gainDb), [-3, -5, -2]);
    });

    test('the group stops together at +24 dB', () {
      final group = ClipGroup.of([gained(23), gained(0)])!;
      expect(group.clampGainShift(5), 1);
    });

    test('going down, the group stops just above silent', () {
      final group = ClipGroup.of([gained(-60), gained(0)])!;
      expect(group.clampGainShift(-20), closeTo(-9.9, 1e-9));
    });

    test('a silent clip stays silent and holds no one back', () {
      expect(const ShiftGain(6).applyTo(gained(-70)).gainDb, -70);
      final group = ClipGroup.of([gained(-70), gained(0)])!;
      expect(group.clampGainShift(-20), -20);
      expect((group.lowGainDb, group.highGainDb), (-70, 0));
    });

    test('a reset sets every clip', () {
      final set = [gained(-6), gained(3)].map(const SetGain(0).applyTo);
      expect(set.map((e) => e.gainDb), [0, 0]);
    });
  });

  group('reverse', () {
    test('counts the reversed clips', () {
      const reversed = AudioClipEditData(reversed: true);
      const plain = AudioClipEditData();
      expect(ClipGroup.of([reversed, plain, plain])!.reversedCount, 1);
    });

    test('sets every clip', () {
      final set = [
        const AudioClipEditData(reversed: true),
        const AudioClipEditData(),
      ].map(const SetReversed(reversed: true).applyTo);
      expect(set.every((e) => e.reversed), isTrue);
    });
  });
}
