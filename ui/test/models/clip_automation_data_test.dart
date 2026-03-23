import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/models/clip_automation_data.dart';
import 'package:boojy_audio/models/track_automation_data.dart';

void main() {
  // =========================================================================
  // ClipAutomationPoint
  // =========================================================================
  group('ClipAutomationPoint', () {
    group('constructor', () {
      test('creates instance with required fields and auto-generated ID', () {
        final point = ClipAutomationPoint(time: 1.0, value: 0.5);

        expect(point.time, 1.0);
        expect(point.value, 0.5);
        expect(point.id, isNotEmpty);
      });

      test('creates instance with explicit ID', () {
        final point =
            ClipAutomationPoint(id: 'my-id', time: 2.0, value: 0.8);

        expect(point.id, 'my-id');
        expect(point.time, 2.0);
        expect(point.value, 0.8);
      });

      test('isSelected defaults to false', () {
        final point = ClipAutomationPoint(time: 0.0, value: 0.0);

        expect(point.isSelected, false);
      });

      test('isSelected can be set to true', () {
        final point =
            ClipAutomationPoint(time: 0.0, value: 0.0, isSelected: true);

        expect(point.isSelected, true);
      });

      test('two points without explicit ID get different IDs', () {
        final p1 = ClipAutomationPoint(time: 1.0, value: 0.5);
        final p2 = ClipAutomationPoint(time: 1.0, value: 0.5);

        expect(p1.id, isNot(equals(p2.id)));
      });
    });

    group('copyWith', () {
      test('copies all fields when none specified', () {
        final original = ClipAutomationPoint(
            id: 'orig', time: 1.0, value: 0.5, isSelected: true);
        final copy = original.copyWith();

        expect(copy.id, 'orig');
        expect(copy.time, 1.0);
        expect(copy.value, 0.5);
        expect(copy.isSelected, true);
      });

      test('updates id only', () {
        final original = ClipAutomationPoint(id: 'a', time: 1.0, value: 0.5);
        final copy = original.copyWith(id: 'b');

        expect(copy.id, 'b');
        expect(copy.time, 1.0);
        expect(copy.value, 0.5);
      });

      test('updates time only', () {
        final original = ClipAutomationPoint(id: 'a', time: 1.0, value: 0.5);
        final copy = original.copyWith(time: 3.0);

        expect(copy.id, 'a');
        expect(copy.time, 3.0);
        expect(copy.value, 0.5);
      });

      test('updates value only', () {
        final original = ClipAutomationPoint(id: 'a', time: 1.0, value: 0.5);
        final copy = original.copyWith(value: 0.9);

        expect(copy.value, 0.9);
        expect(copy.time, 1.0);
      });

      test('updates isSelected only', () {
        final original = ClipAutomationPoint(id: 'a', time: 1.0, value: 0.5);
        final copy = original.copyWith(isSelected: true);

        expect(copy.isSelected, true);
        expect(copy.id, 'a');
      });

      test('updates multiple fields at once', () {
        final original =
            ClipAutomationPoint(id: 'a', time: 1.0, value: 0.5);
        final copy = original.copyWith(time: 2.0, value: 0.8, isSelected: true);

        expect(copy.time, 2.0);
        expect(copy.value, 0.8);
        expect(copy.isSelected, true);
        expect(copy.id, 'a');
      });
    });

    group('equality and hashCode', () {
      test('equal points are equal', () {
        final a = ClipAutomationPoint(id: 'x', time: 1.0, value: 0.5);
        final b = ClipAutomationPoint(id: 'x', time: 1.0, value: 0.5);

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different id means not equal', () {
        final a = ClipAutomationPoint(id: 'x', time: 1.0, value: 0.5);
        final b = ClipAutomationPoint(id: 'y', time: 1.0, value: 0.5);

        expect(a, isNot(equals(b)));
      });

      test('different time means not equal', () {
        final a = ClipAutomationPoint(id: 'x', time: 1.0, value: 0.5);
        final b = ClipAutomationPoint(id: 'x', time: 2.0, value: 0.5);

        expect(a, isNot(equals(b)));
      });

      test('different value means not equal', () {
        final a = ClipAutomationPoint(id: 'x', time: 1.0, value: 0.5);
        final b = ClipAutomationPoint(id: 'x', time: 1.0, value: 0.9);

        expect(a, isNot(equals(b)));
      });

      test('different isSelected means not equal', () {
        final a = ClipAutomationPoint(id: 'x', time: 1.0, value: 0.5);
        final b = ClipAutomationPoint(
            id: 'x', time: 1.0, value: 0.5, isSelected: true);

        expect(a, isNot(equals(b)));
      });

      test('identical reference is equal', () {
        final a = ClipAutomationPoint(id: 'x', time: 1.0, value: 0.5);

        expect(a, equals(a));
      });
    });

    group('toJson / fromJson', () {
      test('roundtrip preserves all serialized fields', () {
        final original =
            ClipAutomationPoint(id: 'pt-1', time: 2.5, value: 0.75);
        final json = original.toJson();
        final restored = ClipAutomationPoint.fromJson(json);

        expect(restored.id, 'pt-1');
        expect(restored.time, 2.5);
        expect(restored.value, 0.75);
      });

      test('toJson does not include isSelected', () {
        final point = ClipAutomationPoint(
            id: 'p', time: 1.0, value: 0.5, isSelected: true);
        final json = point.toJson();

        expect(json.containsKey('isSelected'), false);
      });

      test('fromJson handles integer time and value', () {
        final json = {'id': 'p1', 'time': 3, 'value': 1};
        final point = ClipAutomationPoint.fromJson(json);

        expect(point.time, 3.0);
        expect(point.value, 1.0);
      });

      test('fromJson without id generates a new id', () {
        final json = {'time': 1.0, 'value': 0.5};
        final point = ClipAutomationPoint.fromJson(json);

        expect(point.id, isNotEmpty);
        expect(point.time, 1.0);
        expect(point.value, 0.5);
      });
    });
  });

  // =========================================================================
  // ClipAutomationLane
  // =========================================================================
  group('ClipAutomationLane', () {
    group('constructor and empty factory', () {
      test('empty factory creates lane with no points', () {
        final lane = ClipAutomationLane.empty(AutomationParameter.volume);

        expect(lane.parameter, AutomationParameter.volume);
        expect(lane.points, isEmpty);
        expect(lane.id, isNotEmpty);
      });

      test('constructor with explicit points', () {
        final p1 = ClipAutomationPoint(id: 'a', time: 0.0, value: 0.5);
        final p2 = ClipAutomationPoint(id: 'b', time: 1.0, value: 0.8);
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.pan,
          points: [p1, p2],
        );

        expect(lane.points.length, 2);
        expect(lane.parameter, AutomationParameter.pan);
      });

      test('hasAutomation is false for empty lane', () {
        final lane = ClipAutomationLane.empty(AutomationParameter.volume);

        expect(lane.hasAutomation, false);
      });

      test('hasAutomation is true when points exist', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [ClipAutomationPoint(time: 0.0, value: 0.5)],
        );

        expect(lane.hasAutomation, true);
      });
    });

    group('sortedPoints', () {
      test('returns points sorted by time', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'c', time: 4.0, value: 0.3),
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.5),
            ClipAutomationPoint(id: 'b', time: 2.0, value: 0.8),
          ],
        );

        final sorted = lane.sortedPoints;

        expect(sorted[0].id, 'a');
        expect(sorted[1].id, 'b');
        expect(sorted[2].id, 'c');
      });

      test('returns empty list for empty lane', () {
        final lane = ClipAutomationLane.empty(AutomationParameter.volume);

        expect(lane.sortedPoints, isEmpty);
      });
    });

    group('getValueAtTime', () {
      test('empty lane returns default value', () {
        final lane = ClipAutomationLane.empty(AutomationParameter.volume);

        expect(lane.getValueAtTime(0.0), AutomationParameter.volume.defaultValue);
        expect(lane.getValueAtTime(5.0), AutomationParameter.volume.defaultValue);
      });

      test('empty pan lane returns pan default value (0.0)', () {
        final lane = ClipAutomationLane.empty(AutomationParameter.pan);

        expect(lane.getValueAtTime(1.0), AutomationParameter.pan.defaultValue);
      });

      test('before first point holds first value', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 2.0, value: 0.7),
            ClipAutomationPoint(id: 'b', time: 4.0, value: 0.3),
          ],
        );

        expect(lane.getValueAtTime(0.0), 0.7);
        expect(lane.getValueAtTime(1.0), 0.7);
        expect(lane.getValueAtTime(1.999), 0.7);
      });

      test('after last point holds last value', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.2),
            ClipAutomationPoint(id: 'b', time: 4.0, value: 0.9),
          ],
        );

        expect(lane.getValueAtTime(4.0), 0.9);
        expect(lane.getValueAtTime(5.0), 0.9);
        expect(lane.getValueAtTime(100.0), 0.9);
      });

      test('exact point time returns exact value', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.2),
            ClipAutomationPoint(id: 'b', time: 2.0, value: 0.6),
            ClipAutomationPoint(id: 'c', time: 4.0, value: 1.0),
          ],
        );

        expect(lane.getValueAtTime(0.0), 0.2);
        expect(lane.getValueAtTime(2.0), 0.6);
        expect(lane.getValueAtTime(4.0), 1.0);
      });

      test('linear interpolation at midpoint', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.0),
            ClipAutomationPoint(id: 'b', time: 4.0, value: 1.0),
          ],
        );

        // Midpoint: t=2.0 -> value = 0.5
        expect(lane.getValueAtTime(2.0), closeTo(0.5, 0.0001));
      });

      test('linear interpolation at quarter point', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.0),
            ClipAutomationPoint(id: 'b', time: 4.0, value: 1.0),
          ],
        );

        expect(lane.getValueAtTime(1.0), closeTo(0.25, 0.0001));
        expect(lane.getValueAtTime(3.0), closeTo(0.75, 0.0001));
      });

      test('linear interpolation with descending values', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 1.0),
            ClipAutomationPoint(id: 'b', time: 4.0, value: 0.0),
          ],
        );

        expect(lane.getValueAtTime(2.0), closeTo(0.5, 0.0001));
        expect(lane.getValueAtTime(1.0), closeTo(0.75, 0.0001));
      });

      test('interpolation across multiple segments', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.0),
            ClipAutomationPoint(id: 'b', time: 2.0, value: 1.0),
            ClipAutomationPoint(id: 'c', time: 4.0, value: 0.0),
          ],
        );

        // First segment: 0->2, value 0->1
        expect(lane.getValueAtTime(1.0), closeTo(0.5, 0.0001));
        // Second segment: 2->4, value 1->0
        expect(lane.getValueAtTime(3.0), closeTo(0.5, 0.0001));
      });

      test('single point returns that value everywhere', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 2.0, value: 0.6),
          ],
        );

        expect(lane.getValueAtTime(0.0), 0.6);
        expect(lane.getValueAtTime(2.0), 0.6);
        expect(lane.getValueAtTime(10.0), 0.6);
      });

      test('works with unsorted points in constructor', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'b', time: 4.0, value: 1.0),
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.0),
          ],
        );

        // Should still interpolate correctly after internal sorting
        expect(lane.getValueAtTime(2.0), closeTo(0.5, 0.0001));
      });

      test('pan lane interpolation with negative values', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.pan,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: -1.0),
            ClipAutomationPoint(id: 'b', time: 4.0, value: 1.0),
          ],
        );

        expect(lane.getValueAtTime(2.0), closeTo(0.0, 0.0001));
        expect(lane.getValueAtTime(1.0), closeTo(-0.5, 0.0001));
      });
    });

    group('addPoint', () {
      test('adds point to empty lane', () {
        final lane = ClipAutomationLane.empty(AutomationParameter.volume);
        final updated = lane.addPoint(
            ClipAutomationPoint(id: 'p1', time: 1.0, value: 0.5));

        expect(updated.points.length, 1);
        expect(updated.points[0].value, 0.5);
      });

      test('inserts in sorted order by time', () {
        var lane = ClipAutomationLane.empty(AutomationParameter.volume);
        lane = lane.addPoint(
            ClipAutomationPoint(id: 'a', time: 4.0, value: 0.8));
        lane = lane.addPoint(
            ClipAutomationPoint(id: 'b', time: 1.0, value: 0.2));
        lane = lane.addPoint(
            ClipAutomationPoint(id: 'c', time: 2.0, value: 0.5));

        expect(lane.points[0].id, 'b');
        expect(lane.points[1].id, 'c');
        expect(lane.points[2].id, 'a');
      });

      test('clamps value to parameter max', () {
        final lane = ClipAutomationLane.empty(AutomationParameter.volume);
        final updated = lane.addPoint(
            ClipAutomationPoint(id: 'p', time: 1.0, value: 2.0));

        expect(updated.points[0].value, 1.0);
      });

      test('clamps value to parameter min', () {
        final lane = ClipAutomationLane.empty(AutomationParameter.volume);
        final updated = lane.addPoint(
            ClipAutomationPoint(id: 'p', time: 1.0, value: -0.5));

        expect(updated.points[0].value, 0.0);
      });

      test('clamps pan value to range', () {
        final lane = ClipAutomationLane.empty(AutomationParameter.pan);
        final updated = lane.addPoint(
            ClipAutomationPoint(id: 'p', time: 1.0, value: 5.0));

        expect(updated.points[0].value, 1.0);
      });

      test('does not mutate original lane', () {
        final lane = ClipAutomationLane.empty(AutomationParameter.volume);
        lane.addPoint(ClipAutomationPoint(id: 'p', time: 1.0, value: 0.5));

        expect(lane.points, isEmpty);
      });
    });

    group('removePoint', () {
      test('removes point by id', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.5),
            ClipAutomationPoint(id: 'b', time: 1.0, value: 0.8),
          ],
        );

        final updated = lane.removePoint('a');

        expect(updated.points.length, 1);
        expect(updated.points[0].id, 'b');
      });

      test('no-op if id not found', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.5),
          ],
        );

        final updated = lane.removePoint('nonexistent');

        expect(updated.points.length, 1);
      });
    });

    group('updatePoint', () {
      test('updates value of existing point', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.5),
            ClipAutomationPoint(id: 'b', time: 2.0, value: 0.8),
          ],
        );

        final updated = lane.updatePoint(
            'a', ClipAutomationPoint(id: 'a', time: 0.0, value: 0.9));

        expect(updated.points.firstWhere((p) => p.id == 'a').value, 0.9);
      });

      test('re-sorts when time changes', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.5),
            ClipAutomationPoint(id: 'b', time: 2.0, value: 0.8),
            ClipAutomationPoint(id: 'c', time: 4.0, value: 0.3),
          ],
        );

        // Move 'a' from time 0.0 to time 3.0 (between b and c)
        final updated = lane.updatePoint(
            'a', ClipAutomationPoint(id: 'a', time: 3.0, value: 0.5));

        expect(updated.points[0].id, 'b');
        expect(updated.points[1].id, 'a');
        expect(updated.points[2].id, 'c');
      });

      test('clamps updated value to parameter range', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.5),
          ],
        );

        final updated = lane.updatePoint(
            'a', ClipAutomationPoint(id: 'a', time: 0.0, value: 5.0));

        expect(updated.points[0].value, 1.0);
      });
    });

    group('selectAll / deselectAll / deleteSelected', () {
      test('selectAll selects all points', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.5),
            ClipAutomationPoint(id: 'b', time: 1.0, value: 0.8),
          ],
        );

        final selected = lane.selectAll();

        expect(selected.points.every((p) => p.isSelected), true);
      });

      test('deselectAll deselects all points', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(
                id: 'a', time: 0.0, value: 0.5, isSelected: true),
            ClipAutomationPoint(
                id: 'b', time: 1.0, value: 0.8, isSelected: true),
          ],
        );

        final deselected = lane.deselectAll();

        expect(deselected.points.every((p) => !p.isSelected), true);
      });

      test('deleteSelected removes only selected points', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(
                id: 'a', time: 0.0, value: 0.5, isSelected: true),
            ClipAutomationPoint(id: 'b', time: 1.0, value: 0.8),
            ClipAutomationPoint(
                id: 'c', time: 2.0, value: 0.3, isSelected: true),
          ],
        );

        final result = lane.deleteSelected();

        expect(result.points.length, 1);
        expect(result.points[0].id, 'b');
      });

      test('deleteSelected on no selection returns all points', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.5),
            ClipAutomationPoint(id: 'b', time: 1.0, value: 0.8),
          ],
        );

        final result = lane.deleteSelected();

        expect(result.points.length, 2);
      });

      test('selectedPoints returns only selected', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(
                id: 'a', time: 0.0, value: 0.5, isSelected: true),
            ClipAutomationPoint(id: 'b', time: 1.0, value: 0.8),
          ],
        );

        expect(lane.selectedPoints.length, 1);
        expect(lane.selectedPoints[0].id, 'a');
      });
    });

    group('sliceLeft', () {
      test('empty lane returns same lane', () {
        final lane = ClipAutomationLane.empty(AutomationParameter.volume);
        final result = lane.sliceLeft(2.0);

        expect(result.points, isEmpty);
      });

      test('keeps points before split and adds edge node', () {
        final lane = ClipAutomationLane(
          id: 'lane1',
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.0),
            ClipAutomationPoint(id: 'b', time: 2.0, value: 0.5),
            ClipAutomationPoint(id: 'c', time: 4.0, value: 1.0),
          ],
        );

        final result = lane.sliceLeft(3.0);

        // Points before split: a (0.0) and b (2.0), plus edge at 3.0
        expect(result.points.length, 3);
        expect(result.points[0].id, 'a');
        expect(result.points[1].id, 'b');
        // Edge node at split
        expect(result.points[2].time, 3.0);
        // Interpolated value at t=3: between b(2.0, 0.5) and c(4.0, 1.0) -> 0.75
        expect(result.points[2].value, closeTo(0.75, 0.0001));
      });

      test('split before all points still adds edge node', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 2.0, value: 0.5),
            ClipAutomationPoint(id: 'b', time: 4.0, value: 0.8),
          ],
        );

        final result = lane.sliceLeft(1.0);

        // No points before 1.0, but edge node at 1.0 with held value of first point
        expect(result.points.length, 1);
        expect(result.points[0].time, 1.0);
        expect(result.points[0].value, 0.5); // held from first point
      });

      test('split after all points includes all points plus edge', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.3),
            ClipAutomationPoint(id: 'b', time: 2.0, value: 0.7),
          ],
        );

        final result = lane.sliceLeft(5.0);

        // Both points + edge at 5.0 with held last value
        expect(result.points.length, 3);
        expect(result.points[2].time, 5.0);
        expect(result.points[2].value, 0.7);
      });
    });

    group('sliceRight', () {
      test('empty lane returns same lane', () {
        final lane = ClipAutomationLane.empty(AutomationParameter.volume);
        final result = lane.sliceRight(2.0);

        expect(result.points, isEmpty);
      });

      test('shifts points after split to start at 0 and adds edge at 0', () {
        final lane = ClipAutomationLane(
          id: 'lane1',
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.0),
            ClipAutomationPoint(id: 'b', time: 2.0, value: 0.5),
            ClipAutomationPoint(id: 'c', time: 4.0, value: 1.0),
          ],
        );

        final result = lane.sliceRight(1.0);

        // Edge at 0.0 (interpolated at t=1.0: 0.25), then b shifted to 1.0, c shifted to 3.0
        expect(result.points.length, 3);
        // Edge node at 0
        expect(result.points[0].time, 0.0);
        expect(result.points[0].value, closeTo(0.25, 0.0001));
        // b shifted: 2.0 - 1.0 = 1.0
        expect(result.points[1].time, closeTo(1.0, 0.0001));
        expect(result.points[1].value, 0.5);
        // c shifted: 4.0 - 1.0 = 3.0
        expect(result.points[2].time, closeTo(3.0, 0.0001));
        expect(result.points[2].value, 1.0);
      });

      test('split after all points returns only edge at 0', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.3),
            ClipAutomationPoint(id: 'b', time: 2.0, value: 0.7),
          ],
        );

        final result = lane.sliceRight(5.0);

        // No points after 5.0, just edge at 0 with held last value
        expect(result.points.length, 1);
        expect(result.points[0].time, 0.0);
        expect(result.points[0].value, 0.7);
      });

      test('sliceRight generates new IDs for shifted points', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.0),
            ClipAutomationPoint(id: 'b', time: 4.0, value: 1.0),
          ],
        );

        final result = lane.sliceRight(2.0);

        // The shifted point (originally 'b') should have a new ID
        expect(result.points[1].id, isNot(equals('b')));
      });
    });

    group('shiftTime', () {
      test('shifts all points by positive offset', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.5),
            ClipAutomationPoint(id: 'b', time: 2.0, value: 0.8),
          ],
        );

        final shifted = lane.shiftTime(1.0);

        expect(shifted.points[0].time, 1.0);
        expect(shifted.points[1].time, 3.0);
      });

      test('shifts all points by negative offset', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 2.0, value: 0.5),
            ClipAutomationPoint(id: 'b', time: 4.0, value: 0.8),
          ],
        );

        final shifted = lane.shiftTime(-1.0);

        expect(shifted.points[0].time, 1.0);
        expect(shifted.points[1].time, 3.0);
      });

      test('preserves values when shifting', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.5),
          ],
        );

        final shifted = lane.shiftTime(5.0);

        expect(shifted.points[0].value, 0.5);
      });
    });

    group('deepCopy', () {
      test('creates new IDs for lane and all points', () {
        final lane = ClipAutomationLane(
          id: 'orig-lane',
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'p1', time: 0.0, value: 0.5),
            ClipAutomationPoint(id: 'p2', time: 2.0, value: 0.8),
          ],
        );

        final copy = lane.deepCopy();

        expect(copy.id, isNot(equals('orig-lane')));
        expect(copy.points[0].id, isNot(equals('p1')));
        expect(copy.points[1].id, isNot(equals('p2')));
      });

      test('preserves time and value', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'p1', time: 1.0, value: 0.3),
            ClipAutomationPoint(id: 'p2', time: 3.0, value: 0.9),
          ],
        );

        final copy = lane.deepCopy();

        expect(copy.points[0].time, 1.0);
        expect(copy.points[0].value, 0.3);
        expect(copy.points[1].time, 3.0);
        expect(copy.points[1].value, 0.9);
      });

      test('preserves parameter', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.pan,
          points: [
            ClipAutomationPoint(time: 0.0, value: -0.5),
          ],
        );

        final copy = lane.deepCopy();

        expect(copy.parameter, AutomationParameter.pan);
      });

      test('deep copy resets isSelected to false', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(
                id: 'p1', time: 0.0, value: 0.5, isSelected: true),
          ],
        );

        final copy = lane.deepCopy();

        expect(copy.points[0].isSelected, false);
      });
    });

    group('toJson / fromJson', () {
      test('roundtrip preserves all fields', () {
        final lane = ClipAutomationLane(
          id: 'lane-1',
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'p1', time: 0.0, value: 0.5),
            ClipAutomationPoint(id: 'p2', time: 2.0, value: 0.8),
          ],
        );

        final json = lane.toJson();
        final restored = ClipAutomationLane.fromJson(json);

        expect(restored.id, 'lane-1');
        expect(restored.parameter, AutomationParameter.volume);
        expect(restored.points.length, 2);
        expect(restored.points[0].id, 'p1');
        expect(restored.points[0].time, 0.0);
        expect(restored.points[0].value, 0.5);
        expect(restored.points[1].id, 'p2');
      });

      test('roundtrip with pan parameter', () {
        final lane = ClipAutomationLane(
          id: 'pan-lane',
          parameter: AutomationParameter.pan,
          points: [
            ClipAutomationPoint(id: 'p1', time: 1.0, value: -0.5),
          ],
        );

        final json = lane.toJson();
        final restored = ClipAutomationLane.fromJson(json);

        expect(restored.parameter, AutomationParameter.pan);
        expect(restored.points[0].value, -0.5);
      });

      test('fromJson with empty points list', () {
        final json = {
          'id': 'empty-lane',
          'parameter': 'volume',
          'points': [],
        };

        final lane = ClipAutomationLane.fromJson(json);

        expect(lane.points, isEmpty);
      });

      test('fromJson with null points defaults to empty', () {
        final json = {
          'id': 'lane-x',
          'parameter': 'volume',
        };

        final lane = ClipAutomationLane.fromJson(json);

        expect(lane.points, isEmpty);
      });

      test('fromJson with unknown parameter falls back to volume', () {
        final json = {
          'id': 'lane-x',
          'parameter': 'nonexistent_param',
          'points': [],
        };

        final lane = ClipAutomationLane.fromJson(json);

        expect(lane.parameter, AutomationParameter.volume);
      });
    });

    group('toEngineDbCsv', () {
      test('empty lane returns empty string', () {
        final lane = ClipAutomationLane.empty(AutomationParameter.volume);

        expect(lane.toEngineDbCsv(0.0, 120.0), '');
      });

      test('single point with known conversion', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'p', time: 0.0, value: 0.7),
          ],
        );

        final csv = lane.toEngineDbCsv(0.0, 120.0);
        final parts = csv.split(',');

        // time = 0.0 + 0.0 * 60 / 120 = 0.0
        expect(parts[0], '0.000000');
        // 0.7 is at the unity gain point = 0 dB
        expect(double.parse(parts[1]), closeTo(0.0, 0.1));
      });

      test('beat-to-second conversion at 120 BPM', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'p', time: 2.0, value: 0.7),
          ],
        );

        // clipStart = 1.0s, tempo = 120 BPM
        // time = 1.0 + 2.0 * 60 / 120 = 1.0 + 1.0 = 2.0
        final csv = lane.toEngineDbCsv(1.0, 120.0);
        final parts = csv.split(',');

        expect(double.parse(parts[0]), closeTo(2.0, 0.0001));
      });

      test('multiple points separated by semicolons', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.5),
            ClipAutomationPoint(id: 'b', time: 4.0, value: 0.7),
          ],
        );

        final csv = lane.toEngineDbCsv(0.0, 120.0);
        final entries = csv.split(';');

        expect(entries.length, 2);
      });

      test('points output in sorted order', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'b', time: 4.0, value: 0.7),
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.5),
          ],
        );

        final csv = lane.toEngineDbCsv(0.0, 120.0);
        final entries = csv.split(';');
        final firstTime = double.parse(entries[0].split(',')[0]);
        final secondTime = double.parse(entries[1].split(',')[0]);

        expect(firstTime, lessThan(secondTime));
      });
    });

    group('equality', () {
      test('equal lanes are equal', () {
        final p1 = ClipAutomationPoint(id: 'p1', time: 0.0, value: 0.5);
        final a = ClipAutomationLane(
            id: 'lane1', parameter: AutomationParameter.volume, points: [p1]);
        final b = ClipAutomationLane(
            id: 'lane1', parameter: AutomationParameter.volume, points: [p1]);

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different id means not equal', () {
        final a = ClipAutomationLane(
            id: 'lane1', parameter: AutomationParameter.volume);
        final b = ClipAutomationLane(
            id: 'lane2', parameter: AutomationParameter.volume);

        expect(a, isNot(equals(b)));
      });

      test('different parameter means not equal', () {
        final a = ClipAutomationLane(
            id: 'lane1', parameter: AutomationParameter.volume);
        final b = ClipAutomationLane(
            id: 'lane1', parameter: AutomationParameter.pan);

        expect(a, isNot(equals(b)));
      });

      test('different points means not equal', () {
        final a = ClipAutomationLane(
          id: 'lane1',
          parameter: AutomationParameter.volume,
          points: [ClipAutomationPoint(id: 'p1', time: 0.0, value: 0.5)],
        );
        final b = ClipAutomationLane(
          id: 'lane1',
          parameter: AutomationParameter.volume,
          points: [ClipAutomationPoint(id: 'p1', time: 0.0, value: 0.9)],
        );

        expect(a, isNot(equals(b)));
      });
    });

    group('clear', () {
      test('removes all points', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'a', time: 0.0, value: 0.5),
            ClipAutomationPoint(id: 'b', time: 2.0, value: 0.8),
          ],
        );

        final cleared = lane.clear();

        expect(cleared.points, isEmpty);
        expect(cleared.parameter, AutomationParameter.volume);
      });
    });
  });

  // =========================================================================
  // ClipAutomation
  // =========================================================================
  group('ClipAutomation', () {
    group('constructor and empty factory', () {
      test('empty factory creates automation with no lanes', () {
        final automation = ClipAutomation.empty();

        expect(automation.lanes, isEmpty);
        expect(automation.hasAutomation, false);
      });

      test('const constructor with empty map', () {
        const automation = ClipAutomation();

        expect(automation.lanes, isEmpty);
      });
    });

    group('getLane', () {
      test('returns empty lane for missing parameter', () {
        final automation = ClipAutomation.empty();
        final lane = automation.getLane(AutomationParameter.volume);

        expect(lane.parameter, AutomationParameter.volume);
        expect(lane.points, isEmpty);
      });

      test('returns existing lane', () {
        final lane = ClipAutomationLane(
          id: 'vol-lane',
          parameter: AutomationParameter.volume,
          points: [ClipAutomationPoint(id: 'p', time: 0.0, value: 0.5)],
        );
        final automation = ClipAutomation(
            lanes: {AutomationParameter.volume: lane});

        final retrieved = automation.getLane(AutomationParameter.volume);

        expect(retrieved.id, 'vol-lane');
        expect(retrieved.points.length, 1);
      });
    });

    group('updateLane', () {
      test('adds a new lane', () {
        final automation = ClipAutomation.empty();
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [ClipAutomationPoint(id: 'p', time: 1.0, value: 0.5)],
        );

        final updated =
            automation.updateLane(AutomationParameter.volume, lane);

        expect(updated.lanes.length, 1);
        expect(
            updated.getLane(AutomationParameter.volume).points.length, 1);
      });

      test('replaces an existing lane', () {
        final lane1 = ClipAutomationLane(
          id: 'old',
          parameter: AutomationParameter.volume,
          points: [ClipAutomationPoint(id: 'p1', time: 0.0, value: 0.3)],
        );
        final automation = ClipAutomation(
            lanes: {AutomationParameter.volume: lane1});

        final lane2 = ClipAutomationLane(
          id: 'new',
          parameter: AutomationParameter.volume,
          points: [ClipAutomationPoint(id: 'p2', time: 1.0, value: 0.9)],
        );

        final updated =
            automation.updateLane(AutomationParameter.volume, lane2);

        expect(updated.getLane(AutomationParameter.volume).id, 'new');
      });
    });

    group('removeLane', () {
      test('removes an existing lane', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [ClipAutomationPoint(time: 0.0, value: 0.5)],
        );
        final automation = ClipAutomation(
            lanes: {AutomationParameter.volume: lane});

        final updated = automation.removeLane(AutomationParameter.volume);

        expect(updated.lanes, isEmpty);
      });

      test('no-op if lane does not exist', () {
        final automation = ClipAutomation.empty();
        final updated = automation.removeLane(AutomationParameter.pan);

        expect(updated.lanes, isEmpty);
      });
    });

    group('sliceLeft / sliceRight', () {
      ClipAutomation createTestAutomation() {
        final volLane = ClipAutomationLane(
          id: 'vol',
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'v1', time: 0.0, value: 0.0),
            ClipAutomationPoint(id: 'v2', time: 4.0, value: 1.0),
          ],
        );
        final panLane = ClipAutomationLane(
          id: 'pan',
          parameter: AutomationParameter.pan,
          points: [
            ClipAutomationPoint(id: 'p1', time: 0.0, value: -1.0),
            ClipAutomationPoint(id: 'p2', time: 4.0, value: 1.0),
          ],
        );
        return ClipAutomation(lanes: {
          AutomationParameter.volume: volLane,
          AutomationParameter.pan: panLane,
        });
      }

      test('sliceLeft delegates to all lanes', () {
        final automation = createTestAutomation();
        final left = automation.sliceLeft(2.0);

        // Volume lane: point at 0.0 + edge at 2.0 with value 0.5
        final volLane = left.getLane(AutomationParameter.volume);
        expect(volLane.points.length, 2);
        expect(volLane.points.last.time, 2.0);
        expect(volLane.points.last.value, closeTo(0.5, 0.0001));

        // Pan lane: point at 0.0 + edge at 2.0 with value 0.0
        final panLane = left.getLane(AutomationParameter.pan);
        expect(panLane.points.length, 2);
        expect(panLane.points.last.value, closeTo(0.0, 0.0001));
      });

      test('sliceRight delegates to all lanes', () {
        final automation = createTestAutomation();
        final right = automation.sliceRight(2.0);

        // Volume lane: edge at 0.0 (value 0.5) + shifted v2 at 2.0
        final volLane = right.getLane(AutomationParameter.volume);
        expect(volLane.points.length, 2);
        expect(volLane.points[0].time, 0.0);
        expect(volLane.points[0].value, closeTo(0.5, 0.0001));
        expect(volLane.points[1].time, closeTo(2.0, 0.0001));

        // Pan lane: edge at 0.0 (value 0.0) + shifted p2 at 2.0
        final panLane = right.getLane(AutomationParameter.pan);
        expect(panLane.points.length, 2);
        expect(panLane.points[0].value, closeTo(0.0, 0.0001));
      });
    });

    group('deepCopy', () {
      test('creates independent copy with new lane IDs', () {
        final lane = ClipAutomationLane(
          id: 'orig',
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'p1', time: 0.0, value: 0.5),
          ],
        );
        final automation = ClipAutomation(
            lanes: {AutomationParameter.volume: lane});

        final copy = automation.deepCopy();

        expect(copy.lanes.length, 1);
        final copyLane = copy.getLane(AutomationParameter.volume);
        expect(copyLane.id, isNot(equals('orig')));
        expect(copyLane.points[0].id, isNot(equals('p1')));
        expect(copyLane.points[0].time, 0.0);
        expect(copyLane.points[0].value, 0.5);
      });

      test('empty automation deepCopy is still empty', () {
        final automation = ClipAutomation.empty();
        final copy = automation.deepCopy();

        expect(copy.lanes, isEmpty);
      });
    });

    group('deselectAll', () {
      test('deselects points across all lanes', () {
        final volLane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(
                id: 'v1', time: 0.0, value: 0.5, isSelected: true),
          ],
        );
        final panLane = ClipAutomationLane(
          parameter: AutomationParameter.pan,
          points: [
            ClipAutomationPoint(
                id: 'p1', time: 0.0, value: 0.0, isSelected: true),
          ],
        );
        final automation = ClipAutomation(lanes: {
          AutomationParameter.volume: volLane,
          AutomationParameter.pan: panLane,
        });

        final deselected = automation.deselectAll();

        expect(
          deselected
              .getLane(AutomationParameter.volume)
              .points[0]
              .isSelected,
          false,
        );
        expect(
          deselected
              .getLane(AutomationParameter.pan)
              .points[0]
              .isSelected,
          false,
        );
      });
    });

    group('hasAutomation', () {
      test('false when no lanes', () {
        expect(ClipAutomation.empty().hasAutomation, false);
      });

      test('false when all lanes are empty', () {
        final automation = ClipAutomation(lanes: {
          AutomationParameter.volume:
              ClipAutomationLane.empty(AutomationParameter.volume),
        });

        expect(automation.hasAutomation, false);
      });

      test('true when at least one lane has points', () {
        final lane = ClipAutomationLane(
          parameter: AutomationParameter.volume,
          points: [ClipAutomationPoint(time: 0.0, value: 0.5)],
        );
        final automation = ClipAutomation(
            lanes: {AutomationParameter.volume: lane});

        expect(automation.hasAutomation, true);
      });
    });

    group('toJson / fromJson', () {
      test('roundtrip preserves all lanes and points', () {
        final volLane = ClipAutomationLane(
          id: 'vol-lane',
          parameter: AutomationParameter.volume,
          points: [
            ClipAutomationPoint(id: 'v1', time: 0.0, value: 0.5),
            ClipAutomationPoint(id: 'v2', time: 2.0, value: 0.8),
          ],
        );
        final panLane = ClipAutomationLane(
          id: 'pan-lane',
          parameter: AutomationParameter.pan,
          points: [
            ClipAutomationPoint(id: 'p1', time: 1.0, value: -0.5),
          ],
        );
        final automation = ClipAutomation(lanes: {
          AutomationParameter.volume: volLane,
          AutomationParameter.pan: panLane,
        });

        final json = automation.toJson();
        final restored = ClipAutomation.fromJson(json);

        expect(restored.lanes.length, 2);

        final restoredVol = restored.getLane(AutomationParameter.volume);
        expect(restoredVol.id, 'vol-lane');
        expect(restoredVol.points.length, 2);
        expect(restoredVol.points[0].value, 0.5);

        final restoredPan = restored.getLane(AutomationParameter.pan);
        expect(restoredPan.id, 'pan-lane');
        expect(restoredPan.points.length, 1);
        expect(restoredPan.points[0].value, -0.5);
      });

      test('fromJson with null lanes returns empty', () {
        final json = <String, dynamic>{};
        final automation = ClipAutomation.fromJson(json);

        expect(automation.lanes, isEmpty);
      });

      test('fromJson with empty lanes map', () {
        final json = {'lanes': <String, dynamic>{}};
        final automation = ClipAutomation.fromJson(json);

        expect(automation.lanes, isEmpty);
      });
    });

    group('equality', () {
      test('equal automations are equal', () {
        final lane = ClipAutomationLane(
          id: 'l1',
          parameter: AutomationParameter.volume,
          points: [ClipAutomationPoint(id: 'p1', time: 0.0, value: 0.5)],
        );
        final a = ClipAutomation(
            lanes: {AutomationParameter.volume: lane});
        final b = ClipAutomation(
            lanes: {AutomationParameter.volume: lane});

        expect(a, equals(b));
      });

      test('different lanes means not equal', () {
        final lane1 = ClipAutomationLane(
          id: 'l1',
          parameter: AutomationParameter.volume,
          points: [ClipAutomationPoint(id: 'p1', time: 0.0, value: 0.5)],
        );
        final lane2 = ClipAutomationLane(
          id: 'l2',
          parameter: AutomationParameter.volume,
          points: [ClipAutomationPoint(id: 'p1', time: 0.0, value: 0.9)],
        );

        final a = ClipAutomation(
            lanes: {AutomationParameter.volume: lane1});
        final b = ClipAutomation(
            lanes: {AutomationParameter.volume: lane2});

        expect(a, isNot(equals(b)));
      });

      test('empty automations are equal', () {
        final a = ClipAutomation.empty();
        final b = ClipAutomation.empty();

        expect(a, equals(b));
      });
    });

    group('copyWith', () {
      test('copies with no changes', () {
        final lane = ClipAutomationLane(
          id: 'l1',
          parameter: AutomationParameter.volume,
        );
        final automation = ClipAutomation(
            lanes: {AutomationParameter.volume: lane});

        final copy = automation.copyWith();

        expect(copy, equals(automation));
      });

      test('replaces lanes', () {
        final automation = ClipAutomation.empty();
        final newLane = ClipAutomationLane(
          parameter: AutomationParameter.pan,
          points: [ClipAutomationPoint(time: 0.0, value: 0.0)],
        );

        final updated = automation.copyWith(
            lanes: {AutomationParameter.pan: newLane});

        expect(updated.lanes.length, 1);
        expect(updated.lanes.containsKey(AutomationParameter.pan), true);
      });
    });
  });
}
