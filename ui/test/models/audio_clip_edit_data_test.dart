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
        expect(data.stretchFactor, 1.0);
        expect(data.warpMode, WarpMode.warp);
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

      test('hasTempoModification is true when stretchFactor != 1.0', () {
        const data = AudioClipEditData(stretchFactor: 2.0);
        expect(data.hasTempoModification, true);
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
          stretchFactor: 0.5,
          warpMode: WarpMode.repitch,
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

      test('updates stretchFactor', () {
        const data = AudioClipEditData();
        final copy = data.copyWith(stretchFactor: 2.0);
        expect(copy.stretchFactor, 2.0);
      });

      test('updates warpMode', () {
        const data = AudioClipEditData();
        final copy = data.copyWith(warpMode: WarpMode.repitch);
        expect(copy.warpMode, WarpMode.repitch);
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
        final copy = data.copyWith(normalizeTargetDb: -3.0, clearNormalize: true);
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
        expect(copy.warpMode, WarpMode.warp); // unchanged
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
          stretchFactor: 0.75,
          warpMode: WarpMode.repitch,
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
        final data = AudioClipEditData.fromJson({});

        expect(data.loopEnabled, true);
        expect(data.startOffsetBeats, 0.0);
        expect(data.lengthBeats, 4.0);
        expect(data.bpm, 120.0);
        expect(data.warpMode, WarpMode.warp);
        expect(data.normalizeTargetDb, isNull);
      });

      test('fromJson handles unknown warpMode with default', () {
        final data = AudioClipEditData.fromJson({'warpMode': 'unknown'});
        expect(data.warpMode, WarpMode.warp);
      });
    });

    group('WarpMode serialization', () {
      test('warp mode serializes to "warp"', () {
        const data = AudioClipEditData(warpMode: WarpMode.warp);
        final json = data.toJson();
        expect(json['warpMode'], 'warp');
      });

      test('repitch mode serializes to "repitch"', () {
        const data = AudioClipEditData(warpMode: WarpMode.repitch);
        final json = data.toJson();
        expect(json['warpMode'], 'repitch');
      });

      test('warp mode roundtrips through JSON', () {
        const original = AudioClipEditData(warpMode: WarpMode.warp);
        final restored = AudioClipEditData.fromJson(original.toJson());
        expect(restored.warpMode, WarpMode.warp);
      });

      test('repitch mode roundtrips through JSON', () {
        const original = AudioClipEditData(warpMode: WarpMode.repitch);
        final restored = AudioClipEditData.fromJson(original.toJson());
        expect(restored.warpMode, WarpMode.repitch);
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

      test('differs by warpMode', () {
        const a = AudioClipEditData(warpMode: WarpMode.warp);
        const b = AudioClipEditData(warpMode: WarpMode.repitch);
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

      test('stretchFactor at 0.5 (half speed)', () {
        const data = AudioClipEditData(stretchFactor: 0.5);
        expect(data.stretchFactor, 0.5);
        expect(data.hasTempoModification, true);
      });

      test('stretchFactor at 2.0 (double speed)', () {
        const data = AudioClipEditData(stretchFactor: 2.0);
        expect(data.stretchFactor, 2.0);
        expect(data.hasTempoModification, true);
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
        const data = AudioClipEditData(
          loopStartBeats: 2.0,
          loopEndBeats: 10.0,
        );
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
        const data = AudioClipEditData(
          loopStartBeats: 4.0,
          loopEndBeats: 4.0,
        );
        expect(data.loopLengthBeats, 0.0);
      });
    });

    group('toString', () {
      test('returns formatted string', () {
        const data = AudioClipEditData(
          bpm: 140.0,
          stretchFactor: 2.0,
          transposeSemitones: 5,
          gainDb: -6.0,
          reversed: true,
        );

        final str = data.toString();
        expect(str, contains('bpm: 140.0'));
        expect(str, contains('stretch: 2.0x'));
        expect(str, contains('transpose: 5st'));
        expect(str, contains('gain: -6.0dB'));
        expect(str, contains('reversed: true'));
      });
    });
  });
}
