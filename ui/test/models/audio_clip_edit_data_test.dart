import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/models/audio_clip_edit_data.dart';

void main() {
  group('AudioClipEditData', () {
    group('default construction', () {
      test('has correct default values', () {
        const data = AudioClipEditData();

        expect(data.loopEnabled, true);
        expect(data.startOffsetBeats, 0.0);
        expect(data.lengthBeats, 4.0);
        expect(data.beatsPerBar, 4);
        expect(data.beatUnit, 4);
        expect(data.bpm, 120.0);
        expect(data.syncEnabled, false);
        expect(data.transposeSemitones, 0);
        expect(data.fineCents, 0);
        expect(data.gainDb, 0.0);
        expect(data.isStereo, true);
        expect(data.reversed, false);
        expect(data.normalizeTargetDb, isNull);
        expect(data.loopStartBeats, 0.0);
        expect(data.loopEndBeats, 4.0);
      });
    });

    group('computed properties', () {
      test('loopLengthBeats returns difference of end - start', () {
        const data = AudioClipEditData(loopStartBeats: 1.0, loopEndBeats: 5.0);
        expect(data.loopLengthBeats, 4.0);
      });

      test('totalPitchCents combines semitones and cents', () {
        const data = AudioClipEditData(transposeSemitones: 3, fineCents: 50);
        expect(data.totalPitchCents, 350);
      });

      test('totalPitchCents with negative values', () {
        const data = AudioClipEditData(transposeSemitones: -2, fineCents: -30);
        expect(data.totalPitchCents, -230);
      });

      test('hasPitchShift is false when no pitch shift', () {
        const data = AudioClipEditData();
        expect(data.hasPitchShift, false);
      });

      test('hasPitchShift is true with semitones', () {
        const data = AudioClipEditData(transposeSemitones: 5);
        expect(data.hasPitchShift, true);
      });

      test('hasPitchShift is true with fine cents only', () {
        const data = AudioClipEditData(fineCents: 10);
        expect(data.hasPitchShift, true);
      });

      test('hasProcessing is false by default', () {
        const data = AudioClipEditData();
        expect(data.hasProcessing, false);
      });

      test('hasProcessing is true when reversed', () {
        const data = AudioClipEditData(reversed: true);
        expect(data.hasProcessing, true);
      });

      test('hasProcessing is true when normalizeTargetDb set', () {
        const data = AudioClipEditData(normalizeTargetDb: -6.0);
        expect(data.hasProcessing, true);
      });

      test('hasTempoModification is false by default', () {
        const data = AudioClipEditData();
        expect(data.hasTempoModification, false);
      });

      test('hasTempoModification is true when syncEnabled', () {
        const data = AudioClipEditData(syncEnabled: true);
        expect(data.hasTempoModification, true);
      });

      test('stretchAt follows the project tempo while warp is on', () {
        const data = AudioClipEditData(bpm: 150.0, syncEnabled: true);
        expect(data.stretchAt(120.0), closeTo(0.8, 1e-9));
        expect(data.stretchAt(170.0), closeTo(170.0 / 150.0, 1e-9));
        expect(data.stretchAt(150.0), 1.0);
      });

      test('stretchAt is 1 with warp off and clamps to the engine range', () {
        expect(const AudioClipEditData(bpm: 150.0).stretchAt(120.0), 1.0);
        const slow = AudioClipEditData(bpm: 20.0, syncEnabled: true);
        expect(slow.stretchAt(300.0), 4.0);
      });

      test('loopLengthSeconds counts a warped clip in its own beats', () {
        // 4 bars at 150 BPM is 6.4 s of audio whatever the project tempo.
        const warped = AudioClipEditData(
          bpm: 150.0,
          syncEnabled: true,
          loopEndBeats: 16.0,
        );
        expect(warped.loopLengthSeconds(120.0), closeTo(6.4, 1e-9));
        const unwarped = AudioClipEditData(loopEndBeats: 16.0);
        expect(unwarped.loopLengthSeconds(120.0), closeTo(8.0, 1e-9));
      });
    });

    group('copyWith', () {
      test('copies all fields when none specified', () {
        const original = AudioClipEditData(
          loopEnabled: false,
          startOffsetBeats: 2.0,
          lengthBeats: 8.0,
          beatsPerBar: 3,
          beatUnit: 8,
          bpm: 140.0,
          syncEnabled: true,
          transposeSemitones: 5,
          fineCents: 25,
          gainDb: -3.0,
          isStereo: false,
          reversed: true,
          normalizeTargetDb: -6.0,
          loopStartBeats: 1.0,
          loopEndBeats: 6.0,
        );

        final copy = original.copyWith();
        expect(copy, original);
      });

      test('updates loopEnabled', () {
        const data = AudioClipEditData();
        final copy = data.copyWith(loopEnabled: false);
        expect(copy.loopEnabled, false);
      });

      test('updates startOffsetBeats', () {
        const data = AudioClipEditData();
        final copy = data.copyWith(startOffsetBeats: 2.5);
        expect(copy.startOffsetBeats, 2.5);
      });

      test('updates lengthBeats', () {
        const data = AudioClipEditData();
        final copy = data.copyWith(lengthBeats: 16.0);
        expect(copy.lengthBeats, 16.0);
      });

      test('updates beatsPerBar', () {
        const data = AudioClipEditData();
        final copy = data.copyWith(beatsPerBar: 3);
        expect(copy.beatsPerBar, 3);
      });

      test('updates beatUnit', () {
        const data = AudioClipEditData();
        final copy = data.copyWith(beatUnit: 8);
        expect(copy.beatUnit, 8);
      });

      test('updates bpm', () {
        const data = AudioClipEditData();
        final copy = data.copyWith(bpm: 90.0);
        expect(copy.bpm, 90.0);
      });

      test('updates syncEnabled', () {
        const data = AudioClipEditData();
        final copy = data.copyWith(syncEnabled: true);
        expect(copy.syncEnabled, true);
      });

      test('updates transposeSemitones', () {
        const data = AudioClipEditData();
        final copy = data.copyWith(transposeSemitones: -7);
        expect(copy.transposeSemitones, -7);
      });

      test('updates fineCents', () {
        const data = AudioClipEditData();
        final copy = data.copyWith(fineCents: 50);
        expect(copy.fineCents, 50);
      });

      test('updates gainDb', () {
        const data = AudioClipEditData();
        final copy = data.copyWith(gainDb: 6.0);
        expect(copy.gainDb, 6.0);
      });

      test('updates isStereo', () {
        const data = AudioClipEditData();
        final copy = data.copyWith(isStereo: false);
        expect(copy.isStereo, false);
      });

      test('updates reversed', () {
        const data = AudioClipEditData();
        final copy = data.copyWith(reversed: true);
        expect(copy.reversed, true);
      });

      test('updates normalizeTargetDb', () {
        const data = AudioClipEditData();
        final copy = data.copyWith(normalizeTargetDb: -6.0);
        expect(copy.normalizeTargetDb, -6.0);
      });

      test('clears normalizeTargetDb with clearNormalize', () {
        const data = AudioClipEditData(normalizeTargetDb: -6.0);
        final copy = data.copyWith(clearNormalize: true);
        expect(copy.normalizeTargetDb, isNull);
      });

      test('clearNormalize overrides normalizeTargetDb value', () {
        const data = AudioClipEditData(normalizeTargetDb: -6.0);
        final copy = data.copyWith(
          normalizeTargetDb: -3.0,
          clearNormalize: true,
        );
        expect(copy.normalizeTargetDb, isNull);
      });

      test('updates loopStartBeats', () {
        const data = AudioClipEditData();
        final copy = data.copyWith(loopStartBeats: 2.0);
        expect(copy.loopStartBeats, 2.0);
      });

      test('updates loopEndBeats', () {
        const data = AudioClipEditData();
        final copy = data.copyWith(loopEndBeats: 8.0);
        expect(copy.loopEndBeats, 8.0);
      });

      test('updates multiple fields simultaneously', () {
        const data = AudioClipEditData();
        final copy = data.copyWith(
          bpm: 140.0,
          transposeSemitones: 3,
          reversed: true,
          gainDb: -6.0,
        );

        expect(copy.bpm, 140.0);
        expect(copy.transposeSemitones, 3);
        expect(copy.reversed, true);
        expect(copy.gainDb, -6.0);
        expect(copy.loopEnabled, true); // unchanged
      });
    });

    group('toJson / fromJson roundtrip', () {
      test('roundtrips default values', () {
        const original = AudioClipEditData();
        final json = original.toJson();
        final restored = AudioClipEditData.fromJson(json);

        expect(restored, original);
      });

      test('roundtrips non-default values', () {
        const original = AudioClipEditData(
          loopEnabled: false,
          startOffsetBeats: 2.5,
          lengthBeats: 16.0,
          beatsPerBar: 3,
          beatUnit: 8,
          bpm: 95.0,
          syncEnabled: true,
          transposeSemitones: -5,
          fineCents: 30,
          gainDb: -12.0,
          isStereo: false,
          reversed: true,
          normalizeTargetDb: -3.0,
          loopStartBeats: 1.0,
          loopEndBeats: 12.0,
        );

        final json = original.toJson();
        final restored = AudioClipEditData.fromJson(json);

        expect(restored, original);
      });

      test('fromJson handles missing fields with defaults', () {
        final data = AudioClipEditData.fromJson(const {});

        expect(data.loopEnabled, true);
        expect(data.startOffsetBeats, 0.0);
        expect(data.lengthBeats, 4.0);
        expect(data.bpm, 120.0);
        expect(data.normalizeTargetDb, isNull);
      });

      test('fromJson ignores legacy warpMode and stretchFactor keys', () {
        final data = AudioClipEditData.fromJson(const {
          'warpMode': 'repitch',
          'stretchFactor': 0.5,
        });
        expect(data, const AudioClipEditData());
      });
    });

    group('legacy warpMode', () {
      test('toJson no longer writes warpMode', () {
        expect(
          const AudioClipEditData().toJson().containsKey('warpMode'),
          false,
        );
      });
    });

    group('equality and hashCode', () {
      test('equal instances are equal', () {
        const a = AudioClipEditData(bpm: 140.0, transposeSemitones: 3);
        const b = AudioClipEditData(bpm: 140.0, transposeSemitones: 3);

        expect(a, b);
        expect(a.hashCode, b.hashCode);
      });

      test('different instances are not equal', () {
        const a = AudioClipEditData(bpm: 140.0);
        const b = AudioClipEditData(bpm: 120.0);

        expect(a, isNot(b));
      });

      test('identical instance is equal to itself', () {
        const data = AudioClipEditData();
        expect(data, data);
      });

      test('differs by loopEnabled', () {
        const a = AudioClipEditData(loopEnabled: true);
        const b = AudioClipEditData(loopEnabled: false);
        expect(a, isNot(b));
      });

      test('differs by normalizeTargetDb (null vs value)', () {
        const a = AudioClipEditData();
        const b = AudioClipEditData(normalizeTargetDb: -6.0);
        expect(a, isNot(b));
      });
    });

    group('edge values', () {
      test('transposeSemitones at -48', () {
        const data = AudioClipEditData(transposeSemitones: -48);
        expect(data.transposeSemitones, -48);
        expect(data.totalPitchCents, -4800);
      });

      test('transposeSemitones at +48', () {
        const data = AudioClipEditData(transposeSemitones: 48);
        expect(data.transposeSemitones, 48);
        expect(data.totalPitchCents, 4800);
      });

      test('gainDb at extreme positive', () {
        const data = AudioClipEditData(gainDb: 12.0);
        expect(data.gainDb, 12.0);
      });

      test('gainDb at extreme negative', () {
        const data = AudioClipEditData(gainDb: -100.0);
        expect(data.gainDb, -100.0);
      });

      test('normalizeTargetDb null', () {
        const data = AudioClipEditData();
        expect(data.normalizeTargetDb, isNull);
        expect(data.hasProcessing, false);
      });

      test('normalizeTargetDb at 0 dB', () {
        const data = AudioClipEditData(normalizeTargetDb: 0.0);
        expect(data.normalizeTargetDb, 0.0);
        expect(data.hasProcessing, true);
      });

      test('normalizeTargetDb at -12 dB', () {
        const data = AudioClipEditData(normalizeTargetDb: -12.0);
        expect(data.normalizeTargetDb, -12.0);
      });

      test('fineCents at limits', () {
        const pos = AudioClipEditData(fineCents: 100);
        expect(pos.fineCents, 100);

        const neg = AudioClipEditData(fineCents: -100);
        expect(neg.fineCents, -100);
      });
    });

    group('loop region', () {
      test('default loop region spans 4 beats', () {
        const data = AudioClipEditData();
        expect(data.loopStartBeats, 0.0);
        expect(data.loopEndBeats, 4.0);
        expect(data.loopLengthBeats, 4.0);
      });

      test('custom loop region', () {
        const data = AudioClipEditData(loopStartBeats: 2.0, loopEndBeats: 10.0);
        expect(data.loopLengthBeats, 8.0);
      });

      test('loop region roundtrips through JSON', () {
        const original = AudioClipEditData(
          loopStartBeats: 3.5,
          loopEndBeats: 7.25,
        );
        final restored = AudioClipEditData.fromJson(original.toJson());

        expect(restored.loopStartBeats, 3.5);
        expect(restored.loopEndBeats, 7.25);
        expect(restored.loopLengthBeats, 3.75);
      });

      test('loop region with zero length', () {
        const data = AudioClipEditData(loopStartBeats: 4.0, loopEndBeats: 4.0);
        expect(data.loopLengthBeats, 0.0);
      });
    });

    group('toString', () {
      test('returns formatted string', () {
        const data = AudioClipEditData(
          bpm: 140.0,
          syncEnabled: true,
          transposeSemitones: 5,
          gainDb: -6.0,
          reversed: true,
        );

        final str = data.toString();
        expect(str, contains('bpm: 140.0'));
        expect(str, contains('warp: true'));
        expect(str, contains('transpose: 5st'));
        expect(str, contains('gain: -6.0dB'));
        expect(str, contains('reversed: true'));
      });
    });
    group('loop region stays on the same audio', () {
      // 4 beats at a 120 BPM project = 2 s of the clip's audio.
      const unwarped = AudioClipEditData(bpm: 150, loopEndBeats: 4);

      test('turning warp on recounts the beats at the clip BPM', () {
        final warped = unwarped.withWarp(on: true, projectBpm: 120);
        expect(warped.syncEnabled, isTrue);
        expect(warped.loopEndBeats, 5);
        expect(warped.loopLengthSeconds(90), 2.0);
        final back = warped.withWarp(on: false, projectBpm: 120);
        expect(back.loopEndBeats, 4);
        expect(
          identical(back.withWarp(on: false, projectBpm: 120), back),
          isTrue,
        );
      });

      test('the region is re-counted from the clip loop in seconds', () {
        // Beats saved at 120 BPM, project now at 90: 2 s is 3 beats.
        final fresh = unwarped.withLoopSeconds(2.0, 90);
        expect(fresh.loopEndBeats, 3);
        expect(fresh.loopLengthSeconds(90), 2.0);
      });
    });
  });
}
