import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/models/track_data.dart';

void main() {
  group('TrackData', () {
    group('fromCSV', () {
      test('parses 10-field format (full)', () {
        final track = TrackData.fromCSV(
          '1,Piano,midi,-6.0,0.3,false,true,false,2,1',
        );

        expect(track, isNotNull);
        expect(track!.id, 1);
        expect(track.name, 'Piano');
        expect(track.type, 'midi');
        expect(track.volumeDb, -6.0);
        expect(track.pan, 0.3);
        expect(track.mute, false);
        expect(track.solo, true);
        expect(track.armed, false);
        expect(track.inputDeviceIndex, 2);
        expect(track.inputChannel, 1);
      });

      test('parses 8-field format (with armed)', () {
        final track = TrackData.fromCSV(
          '1,Piano,midi,-6.0,0.3,false,true,false',
        );

        expect(track, isNotNull);
        expect(track!.id, 1);
        expect(track.name, 'Piano');
        expect(track.armed, false);
        expect(track.inputDeviceIndex, -1);
        expect(track.inputChannel, 0);
      });

      test('parses 7-field format (legacy)', () {
        final track = TrackData.fromCSV('1,Piano,midi,-6.0,0.3,false,true');

        expect(track, isNotNull);
        expect(track!.id, 1);
        expect(track.name, 'Piano');
        expect(track.armed, false);
        expect(track.inputDeviceIndex, -1);
        expect(track.inputChannel, 0);
      });

      test('parses mute as "true" string', () {
        final track = TrackData.fromCSV(
          '1,Drums,audio,0.0,0.0,true,false,false',
        );

        expect(track, isNotNull);
        expect(track!.mute, true);
      });

      test('parses mute as "1"', () {
        final track = TrackData.fromCSV('1,Drums,audio,0.0,0.0,1,false,false');

        expect(track, isNotNull);
        expect(track!.mute, true);
      });

      test('parses solo as "true" string', () {
        final track = TrackData.fromCSV(
          '1,Drums,audio,0.0,0.0,false,true,false',
        );

        expect(track, isNotNull);
        expect(track!.solo, true);
      });

      test('parses solo as "1"', () {
        final track = TrackData.fromCSV('1,Drums,audio,0.0,0.0,false,1,false');

        expect(track, isNotNull);
        expect(track!.solo, true);
      });

      test('parses armed as "true"', () {
        final track = TrackData.fromCSV(
          '1,Drums,audio,0.0,0.0,false,false,true',
        );

        expect(track, isNotNull);
        expect(track!.armed, true);
      });

      test('parses armed as "1"', () {
        final track = TrackData.fromCSV('1,Drums,audio,0.0,0.0,false,false,1');

        expect(track, isNotNull);
        expect(track!.armed, true);
      });

      test(
        'missing fields default: armed=false, inputDeviceIndex=-1, inputChannel=0',
        () {
          final track = TrackData.fromCSV('5,Bass,audio,-3.0,0.5,true,false');

          expect(track, isNotNull);
          expect(track!.armed, false);
          expect(track.inputDeviceIndex, -1);
          expect(track.inputChannel, 0);
        },
      );

      test('returns null for too few fields (<7)', () {
        expect(TrackData.fromCSV('1,Piano,midi,-6.0,0.3,false'), isNull);
        expect(TrackData.fromCSV('1,Piano,midi'), isNull);
        expect(TrackData.fromCSV('1'), isNull);
      });

      test('returns null for invalid data (non-numeric ID)', () {
        expect(TrackData.fromCSV('abc,Piano,midi,-6.0,0.3,false,true'), isNull);
      });

      test('returns null for empty string', () {
        expect(TrackData.fromCSV(''), isNull);
      });

      test('handles 9-field format (inputDeviceIndex but no inputChannel)', () {
        final track = TrackData.fromCSV(
          '1,Piano,midi,-6.0,0.3,false,true,false,3',
        );

        expect(track, isNotNull);
        expect(track!.inputDeviceIndex, 3);
        expect(track.inputChannel, 0);
      });

      test('handles invalid inputDeviceIndex gracefully', () {
        final track = TrackData.fromCSV(
          '1,Piano,midi,-6.0,0.3,false,true,false,abc,0',
        );

        expect(track, isNotNull);
        expect(track!.inputDeviceIndex, -1);
      });

      test('handles invalid inputChannel gracefully', () {
        final track = TrackData.fromCSV(
          '1,Piano,midi,-6.0,0.3,false,true,false,2,abc',
        );

        expect(track, isNotNull);
        expect(track!.inputChannel, 0);
      });
    });

    group('toCSV', () {
      test('serializes all fields correctly', () {
        final track = TrackData(
          id: 1,
          name: 'Piano',
          type: 'midi',
          volumeDb: -6.0,
          pan: 0.3,
          mute: false,
          solo: true,
          armed: false,
          inputDeviceIndex: 2,
          inputChannel: 1,
        );

        expect(track.toCSV(), '1,Piano,midi,-6.0,0.3,false,true,false,2,1');
      });

      test(
        'roundtrip: fromCSV -> toCSV -> fromCSV produces identical data',
        () {
          const csv = '3,Synth,midi,-12.0,0.7,true,false,true,4,2';
          final track1 = TrackData.fromCSV(csv)!;
          final csv2 = track1.toCSV();
          final track2 = TrackData.fromCSV(csv2)!;

          expect(track2.id, track1.id);
          expect(track2.name, track1.name);
          expect(track2.type, track1.type);
          expect(track2.volumeDb, track1.volumeDb);
          expect(track2.pan, track1.pan);
          expect(track2.mute, track1.mute);
          expect(track2.solo, track1.solo);
          expect(track2.armed, track1.armed);
          expect(track2.inputDeviceIndex, track1.inputDeviceIndex);
          expect(track2.inputChannel, track1.inputChannel);
        },
      );
    });

    group('copyWith', () {
      late TrackData original;

      setUp(() {
        original = TrackData(
          id: 1,
          name: 'Piano',
          type: 'midi',
          volumeDb: -6.0,
          pan: 0.3,
          mute: false,
          solo: true,
          armed: false,
          inputDeviceIndex: 2,
          inputChannel: 1,
        );
      });

      test('copies all fields when none specified', () {
        final copy = original.copyWith();

        expect(copy.id, original.id);
        expect(copy.name, original.name);
        expect(copy.type, original.type);
        expect(copy.volumeDb, original.volumeDb);
        expect(copy.pan, original.pan);
        expect(copy.mute, original.mute);
        expect(copy.solo, original.solo);
        expect(copy.armed, original.armed);
        expect(copy.inputDeviceIndex, original.inputDeviceIndex);
        expect(copy.inputChannel, original.inputChannel);
      });

      test('updates id only', () {
        final copy = original.copyWith(id: 99);
        expect(copy.id, 99);
        expect(copy.name, 'Piano');
      });

      test('updates name only', () {
        final copy = original.copyWith(name: 'Guitar');
        expect(copy.name, 'Guitar');
        expect(copy.id, 1);
      });

      test('updates type only', () {
        final copy = original.copyWith(type: 'audio');
        expect(copy.type, 'audio');
      });

      test('updates volumeDb only', () {
        final copy = original.copyWith(volumeDb: -12.0);
        expect(copy.volumeDb, -12.0);
      });

      test('updates pan only', () {
        final copy = original.copyWith(pan: -0.5);
        expect(copy.pan, -0.5);
      });

      test('updates mute only', () {
        final copy = original.copyWith(mute: true);
        expect(copy.mute, true);
      });

      test('updates solo only', () {
        final copy = original.copyWith(solo: false);
        expect(copy.solo, false);
      });

      test('updates armed only', () {
        final copy = original.copyWith(armed: true);
        expect(copy.armed, true);
      });

      test('updates inputDeviceIndex only', () {
        final copy = original.copyWith(inputDeviceIndex: 5);
        expect(copy.inputDeviceIndex, 5);
      });

      test('updates inputChannel only', () {
        final copy = original.copyWith(inputChannel: 3);
        expect(copy.inputChannel, 3);
      });

      test('updates multiple fields', () {
        final copy = original.copyWith(
          name: 'Bass',
          volumeDb: -3.0,
          mute: true,
          inputDeviceIndex: 0,
        );

        expect(copy.name, 'Bass');
        expect(copy.volumeDb, -3.0);
        expect(copy.mute, true);
        expect(copy.inputDeviceIndex, 0);
        expect(copy.id, 1); // unchanged
        expect(copy.solo, true); // unchanged
      });
    });

    group('default values', () {
      test('inputDeviceIndex defaults to -1', () {
        final track = TrackData(
          id: 1,
          name: 'Test',
          type: 'audio',
          volumeDb: 0.0,
          pan: 0.0,
          mute: false,
          solo: false,
          armed: false,
        );

        expect(track.inputDeviceIndex, -1);
      });

      test('inputChannel defaults to 0', () {
        final track = TrackData(
          id: 1,
          name: 'Test',
          type: 'audio',
          volumeDb: 0.0,
          pan: 0.0,
          mute: false,
          solo: false,
          armed: false,
        );

        expect(track.inputChannel, 0);
      });
    });
  });
}
