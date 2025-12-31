import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/models/midi_cc_data.dart';

void main() {
  group('MidiCCType', () {
    test('modWheel has correct values', () {
      expect(MidiCCType.modWheel.ccNumber, 1);
      expect(MidiCCType.modWheel.displayName, 'Mod Wheel');
      expect(MidiCCType.modWheel.minValue, 0);
      expect(MidiCCType.modWheel.maxValue, 127);
    });

    test('pitchBend has special ccNumber -1', () {
      expect(MidiCCType.pitchBend.ccNumber, -1);
      expect(MidiCCType.pitchBend.minValue, -8192);
      expect(MidiCCType.pitchBend.maxValue, 8191);
    });

    test('centerValue calculates correctly', () {
      expect(MidiCCType.modWheel.centerValue, 63); // (0 + 127) ~/ 2
      expect(MidiCCType.pan.centerValue, 63);
      expect(MidiCCType.pitchBend.centerValue, 0); // (-8192 + 8191) ~/ 2
    });

    test('isPitchBend returns true only for pitchBend', () {
      expect(MidiCCType.pitchBend.isPitchBend, true);
      expect(MidiCCType.modWheel.isPitchBend, false);
      expect(MidiCCType.volume.isPitchBend, false);
    });
  });

  group('MidiCCPoint', () {
    test('creates point with required parameters', () {
      final point = MidiCCPoint(time: 1.0, value: 64);

      expect(point.time, 1.0);
      expect(point.value, 64);
      expect(point.isSelected, false);
      expect(point.id, isNotEmpty);
    });

    test('creates point with custom id', () {
      final point = MidiCCPoint(
        id: 'custom_id',
        time: 1.0,
        value: 64,
      );

      expect(point.id, 'custom_id');
    });

    test('generates unique ids for different points', () {
      final point1 = MidiCCPoint(time: 1.0, value: 64);
      final point2 = MidiCCPoint(time: 1.0, value: 64);

      expect(point1.id, isNot(point2.id));
    });

    group('copyWith', () {
      test('copies with no changes', () {
        final point = MidiCCPoint(
          id: 'test_id',
          time: 1.0,
          value: 64,
          isSelected: true,
        );
        final copy = point.copyWith();

        expect(copy.id, 'test_id');
        expect(copy.time, 1.0);
        expect(copy.value, 64);
        expect(copy.isSelected, true);
      });

      test('copies with specific changes', () {
        final point = MidiCCPoint(time: 1.0, value: 64);
        final copy = point.copyWith(
          time: 2.0,
          value: 100,
          isSelected: true,
        );

        expect(copy.time, 2.0);
        expect(copy.value, 100);
        expect(copy.isSelected, true);
      });
    });

    group('equality', () {
      test('points with same id are equal', () {
        final point1 = MidiCCPoint(id: 'same', time: 1.0, value: 64);
        final point2 = MidiCCPoint(id: 'same', time: 2.0, value: 100);

        expect(point1 == point2, true);
        expect(point1.hashCode, point2.hashCode);
      });

      test('points with different ids are not equal', () {
        final point1 = MidiCCPoint(id: 'id1', time: 1.0, value: 64);
        final point2 = MidiCCPoint(id: 'id2', time: 1.0, value: 64);

        expect(point1 == point2, false);
      });
    });
  });

  group('MidiCCLane', () {
    group('constructor', () {
      test('creates lane with required parameters', () {
        final lane = MidiCCLane(ccType: MidiCCType.modWheel);

        expect(lane.ccType, MidiCCType.modWheel);
        expect(lane.points, isEmpty);
        expect(lane.isExpanded, true);
        expect(lane.id, isNotEmpty);
      });

      test('creates lane with custom id and points', () {
        final points = [
          MidiCCPoint(time: 0.0, value: 0),
          MidiCCPoint(time: 1.0, value: 127),
        ];
        final lane = MidiCCLane(
          id: 'custom_id',
          ccType: MidiCCType.volume,
          points: points,
          isExpanded: false,
        );

        expect(lane.id, 'custom_id');
        expect(lane.points.length, 2);
        expect(lane.isExpanded, false);
      });
    });

    group('sortedPoints', () {
      test('returns points sorted by time', () {
        final lane = MidiCCLane(
          ccType: MidiCCType.modWheel,
          points: [
            MidiCCPoint(time: 2.0, value: 64),
            MidiCCPoint(time: 0.5, value: 32),
            MidiCCPoint(time: 1.0, value: 100),
          ],
        );

        final sorted = lane.sortedPoints;

        expect(sorted[0].time, 0.5);
        expect(sorted[1].time, 1.0);
        expect(sorted[2].time, 2.0);
      });

      test('returns empty list for empty lane', () {
        final lane = MidiCCLane(ccType: MidiCCType.modWheel);

        expect(lane.sortedPoints, isEmpty);
      });
    });

    group('getValueAtTime', () {
      test('returns center value for empty lane', () {
        final lane = MidiCCLane(ccType: MidiCCType.modWheel);

        expect(lane.getValueAtTime(1.0), MidiCCType.modWheel.centerValue);
      });

      test('returns first point value before first point', () {
        final lane = MidiCCLane(
          ccType: MidiCCType.modWheel,
          points: [MidiCCPoint(time: 1.0, value: 100)],
        );

        expect(lane.getValueAtTime(0.0), 100);
      });

      test('returns last point value after last point', () {
        final lane = MidiCCLane(
          ccType: MidiCCType.modWheel,
          points: [MidiCCPoint(time: 1.0, value: 50)],
        );

        expect(lane.getValueAtTime(2.0), 50);
      });

      test('interpolates between two points', () {
        final lane = MidiCCLane(
          ccType: MidiCCType.modWheel,
          points: [
            MidiCCPoint(time: 0.0, value: 0),
            MidiCCPoint(time: 2.0, value: 100),
          ],
        );

        // At time 1.0 (halfway), value should be 50
        expect(lane.getValueAtTime(1.0), 50);

        // At time 0.5 (quarter way), value should be 25
        expect(lane.getValueAtTime(0.5), 25);
      });

      test('returns exact value at point time', () {
        final lane = MidiCCLane(
          ccType: MidiCCType.modWheel,
          points: [
            MidiCCPoint(time: 0.0, value: 0),
            MidiCCPoint(time: 1.0, value: 64),
            MidiCCPoint(time: 2.0, value: 127),
          ],
        );

        expect(lane.getValueAtTime(1.0), 64);
      });
    });

    group('addPoint', () {
      test('adds point to lane', () {
        final lane = MidiCCLane(ccType: MidiCCType.modWheel);
        final point = MidiCCPoint(time: 1.0, value: 64);

        final updated = lane.addPoint(point);

        expect(updated.points.length, 1);
        expect(updated.points.first.value, 64);
        expect(lane.points, isEmpty); // Original unchanged
      });
    });

    group('removePoint', () {
      test('removes point by id', () {
        final point = MidiCCPoint(id: 'to_remove', time: 1.0, value: 64);
        final lane = MidiCCLane(
          ccType: MidiCCType.modWheel,
          points: [point],
        );

        final updated = lane.removePoint('to_remove');

        expect(updated.points, isEmpty);
      });

      test('does nothing if point not found', () {
        final point = MidiCCPoint(id: 'existing', time: 1.0, value: 64);
        final lane = MidiCCLane(
          ccType: MidiCCType.modWheel,
          points: [point],
        );

        final updated = lane.removePoint('non_existent');

        expect(updated.points.length, 1);
      });
    });

    group('updatePoint', () {
      test('updates existing point', () {
        final point = MidiCCPoint(id: 'point_id', time: 1.0, value: 64);
        final lane = MidiCCLane(
          ccType: MidiCCType.modWheel,
          points: [point],
        );
        final newPoint = point.copyWith(value: 100);

        final updated = lane.updatePoint('point_id', newPoint);

        expect(updated.points.first.value, 100);
      });
    });

    group('selectedPoints', () {
      test('returns only selected points', () {
        final lane = MidiCCLane(
          ccType: MidiCCType.modWheel,
          points: [
            MidiCCPoint(time: 0.0, value: 0, isSelected: true),
            MidiCCPoint(time: 1.0, value: 64, isSelected: false),
            MidiCCPoint(time: 2.0, value: 127, isSelected: true),
          ],
        );

        expect(lane.selectedPoints.length, 2);
      });
    });

    group('copyWith', () {
      test('copies with specific changes', () {
        final lane = MidiCCLane(
          ccType: MidiCCType.modWheel,
          isExpanded: true,
        );

        final copy = lane.copyWith(isExpanded: false);

        expect(copy.ccType, MidiCCType.modWheel);
        expect(copy.isExpanded, false);
      });
    });

    group('JSON serialization', () {
      test('toJson converts lane to JSON', () {
        final lane = MidiCCLane(
          id: 'lane_id',
          ccType: MidiCCType.volume,
          points: [
            MidiCCPoint(id: 'point1', time: 0.0, value: 64),
          ],
          isExpanded: false,
        );

        final json = lane.toJson();

        expect(json['id'], 'lane_id');
        expect(json['ccType'], 7); // Volume CC number
        expect(json['isExpanded'], false);
        expect((json['points'] as List).length, 1);
      });

      test('fromJson creates lane from JSON', () {
        final json = {
          'id': 'lane_id',
          'ccType': 7, // Volume
          'points': [
            {'id': 'point1', 'time': 1.5, 'value': 100},
          ],
          'isExpanded': false,
        };

        final lane = MidiCCLane.fromJson(json);

        expect(lane.id, 'lane_id');
        expect(lane.ccType, MidiCCType.volume);
        expect(lane.isExpanded, false);
        expect(lane.points.length, 1);
        expect(lane.points.first.time, 1.5);
        expect(lane.points.first.value, 100);
      });

      test('fromJson uses default for unknown CC type', () {
        final json = {
          'ccType': 999, // Unknown CC
          'points': <Map<String, dynamic>>[],
        };

        final lane = MidiCCLane.fromJson(json);

        expect(lane.ccType, MidiCCType.modWheel); // Falls back to modWheel
      });

      test('fromJson handles null points', () {
        final json = {
          'ccType': 1,
        };

        final lane = MidiCCLane.fromJson(json);

        expect(lane.points, isEmpty); // Defaults to empty list
      });
    });
  });
}
