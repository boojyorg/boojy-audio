import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/controllers/automation_controller.dart';
import 'package:boojy_audio/models/track_automation_data.dart';

void main() {
  group('AutomationController', () {
    late AutomationController controller;

    setUp(() {
      controller = AutomationController();
    });

    tearDown(() {
      controller.dispose();
    });

    // ========================================
    // 1. Visibility
    // ========================================
    group('visibility', () {
      test('initially has no visible automation', () {
        expect(controller.visibleTrackId, isNull);
        expect(controller.hasVisibleAutomation, isFalse);
      });

      test('showAutomationForTrack sets visible track', () {
        controller.showAutomationForTrack(1);

        expect(controller.visibleTrackId, 1);
        expect(controller.hasVisibleAutomation, isTrue);
      });

      test('hideAutomation clears visible track', () {
        controller.showAutomationForTrack(1);
        controller.hideAutomation();

        expect(controller.visibleTrackId, isNull);
        expect(controller.hasVisibleAutomation, isFalse);
      });

      test('only one track visible at a time', () {
        controller.showAutomationForTrack(1);
        expect(controller.visibleTrackId, 1);

        controller.showAutomationForTrack(2);
        expect(controller.visibleTrackId, 2);
        expect(controller.isAutomationVisibleForTrack(1), isFalse);
        expect(controller.isAutomationVisibleForTrack(2), isTrue);
      });

      test('isAutomationVisibleForTrack returns false for non-visible tracks', () {
        expect(controller.isAutomationVisibleForTrack(1), isFalse);

        controller.showAutomationForTrack(1);
        expect(controller.isAutomationVisibleForTrack(1), isTrue);
        expect(controller.isAutomationVisibleForTrack(2), isFalse);
      });

      test('toggleAutomationForTrack shows when hidden', () {
        controller.toggleAutomationForTrack(1);

        expect(controller.visibleTrackId, 1);
        expect(controller.hasVisibleAutomation, isTrue);
      });

      test('toggleAutomationForTrack hides when already visible', () {
        controller.showAutomationForTrack(1);
        controller.toggleAutomationForTrack(1);

        expect(controller.visibleTrackId, isNull);
        expect(controller.hasVisibleAutomation, isFalse);
      });

      test('toggleAutomationForTrack switches to new track', () {
        controller.showAutomationForTrack(1);
        controller.toggleAutomationForTrack(2);

        expect(controller.visibleTrackId, 2);
        expect(controller.isAutomationVisibleForTrack(1), isFalse);
        expect(controller.isAutomationVisibleForTrack(2), isTrue);
      });

      test('visibleLane returns null when no track visible', () {
        expect(controller.visibleLane, isNull);
      });

      test('visibleLane returns the lane for visible track and parameter', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );
        controller.showAutomationForTrack(1);

        final lane = controller.visibleLane;
        expect(lane, isNotNull);
        expect(lane!.parameter, AutomationParameter.volume);
        expect(lane.points.length, 1);
      });

      test('showAutomationForTrack creates empty lanes for the track', () {
        controller.showAutomationForTrack(1);

        final volumeLane = controller.getLane(1, AutomationParameter.volume);
        final panLane = controller.getLane(1, AutomationParameter.pan);
        expect(volumeLane, isNotNull);
        expect(panLane, isNotNull);
        expect(volumeLane!.hasAutomation, isFalse);
        expect(panLane!.hasAutomation, isFalse);
      });
    });

    // ========================================
    // 2. Parameter selection
    // ========================================
    group('parameter selection', () {
      test('default visible parameter is volume', () {
        expect(controller.visibleParameter, AutomationParameter.volume);
      });

      test('setVisibleParameter changes the parameter', () {
        controller.setVisibleParameter(AutomationParameter.pan);
        expect(controller.visibleParameter, AutomationParameter.pan);
      });

      test('setVisibleParameter back to volume', () {
        controller.setVisibleParameter(AutomationParameter.pan);
        controller.setVisibleParameter(AutomationParameter.volume);
        expect(controller.visibleParameter, AutomationParameter.volume);
      });

      test('getParameterForTrack returns parameter for visible track', () {
        controller.showAutomationForTrack(1);
        expect(controller.getParameterForTrack(1), AutomationParameter.volume);
      });

      test('getParameterForTrack returns null for non-visible track', () {
        controller.showAutomationForTrack(1);
        expect(controller.getParameterForTrack(2), isNull);
      });

      test('getParameterForTrack returns null when no track visible', () {
        expect(controller.getParameterForTrack(1), isNull);
      });

      test('getParameterForTrack reflects setVisibleParameter', () {
        controller.showAutomationForTrack(1);
        controller.setVisibleParameter(AutomationParameter.pan);
        expect(controller.getParameterForTrack(1), AutomationParameter.pan);
      });

      test('visibleLane updates when parameter changes', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );
        controller.addPoint(
          1,
          AutomationParameter.pan,
          AutomationPoint(time: 1.0, value: -0.5),
        );
        controller.showAutomationForTrack(1);

        expect(controller.visibleLane!.parameter, AutomationParameter.volume);

        controller.setVisibleParameter(AutomationParameter.pan);
        expect(controller.visibleLane!.parameter, AutomationParameter.pan);
        expect(controller.visibleLane!.points.first.value, -0.5);
      });
    });

    // ========================================
    // 3. Points
    // ========================================
    group('points', () {
      test('addPoint creates a point in the lane', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 2.0, value: 0.7),
        );

        final lane = controller.getLane(1, AutomationParameter.volume);
        expect(lane, isNotNull);
        expect(lane!.points.length, 1);
        expect(lane.points.first.time, 2.0);
        expect(lane.points.first.value, 0.7);
      });

      test('addPoint maintains sorted order by time', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 4.0, value: 0.8),
        );
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 1.0, value: 0.3),
        );
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 2.5, value: 0.5),
        );

        final lane = controller.getLane(1, AutomationParameter.volume)!;
        expect(lane.points.length, 3);
        expect(lane.points[0].time, 1.0);
        expect(lane.points[1].time, 2.5);
        expect(lane.points[2].time, 4.0);
      });

      test('addPoint clamps value to parameter range', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 2.0), // above max (1.0)
        );
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 1.0, value: -1.0), // below min (0.0)
        );

        final lane = controller.getLane(1, AutomationParameter.volume)!;
        expect(lane.points[0].value, 1.0);
        expect(lane.points[1].value, 0.0);
      });

      test('addPoint clamps pan value to parameter range', () {
        controller.addPoint(
          1,
          AutomationParameter.pan,
          AutomationPoint(time: 0.0, value: 5.0), // above max (1.0)
        );
        controller.addPoint(
          1,
          AutomationParameter.pan,
          AutomationPoint(time: 1.0, value: -3.0), // below min (-1.0)
        );

        final lane = controller.getLane(1, AutomationParameter.pan)!;
        expect(lane.points[0].value, 1.0);
        expect(lane.points[1].value, -1.0);
      });

      test('removePoint removes the point by id', () {
        final point = AutomationPoint(id: 'p1', time: 1.0, value: 0.5);
        controller.addPoint(1, AutomationParameter.volume, point);
        expect(controller.getLane(1, AutomationParameter.volume)!.points.length, 1);

        controller.removePoint(1, AutomationParameter.volume, 'p1');
        expect(controller.getLane(1, AutomationParameter.volume)!.points.length, 0);
      });

      test('removePoint on non-existent lane does nothing', () {
        // Should not throw
        controller.removePoint(99, AutomationParameter.volume, 'nonexistent');
      });

      test('removePoint with non-existent id does not remove other points', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(id: 'p1', time: 1.0, value: 0.5),
        );
        controller.removePoint(1, AutomationParameter.volume, 'nonexistent');

        expect(controller.getLane(1, AutomationParameter.volume)!.points.length, 1);
      });

      test('updatePoint changes point data', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(id: 'p1', time: 1.0, value: 0.5),
        );

        controller.updatePoint(
          1,
          AutomationParameter.volume,
          'p1',
          AutomationPoint(id: 'p1', time: 2.0, value: 0.8),
        );

        final lane = controller.getLane(1, AutomationParameter.volume)!;
        expect(lane.points.length, 1);
        expect(lane.points.first.time, 2.0);
        expect(lane.points.first.value, 0.8);
      });

      test('updatePoint maintains sorted order when time changes', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(id: 'p1', time: 1.0, value: 0.3),
        );
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(id: 'p2', time: 3.0, value: 0.7),
        );
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(id: 'p3', time: 5.0, value: 0.9),
        );

        // Move p1 to time 4.0 (between p2 and p3)
        controller.updatePoint(
          1,
          AutomationParameter.volume,
          'p1',
          AutomationPoint(id: 'p1', time: 4.0, value: 0.3),
        );

        final lane = controller.getLane(1, AutomationParameter.volume)!;
        expect(lane.points[0].time, 3.0);
        expect(lane.points[1].time, 4.0);
        expect(lane.points[2].time, 5.0);
      });

      test('updatePoint clamps value to parameter range', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(id: 'p1', time: 1.0, value: 0.5),
        );

        controller.updatePoint(
          1,
          AutomationParameter.volume,
          'p1',
          AutomationPoint(id: 'p1', time: 1.0, value: 5.0),
        );

        final lane = controller.getLane(1, AutomationParameter.volume)!;
        expect(lane.points.first.value, 1.0);
      });

      test('updatePoint on non-existent lane does nothing', () {
        // Should not throw
        controller.updatePoint(
          99,
          AutomationParameter.volume,
          'p1',
          AutomationPoint(id: 'p1', time: 1.0, value: 0.5),
        );
      });

      test('clearLane removes all points from a lane', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.3),
        );
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 1.0, value: 0.7),
        );
        expect(controller.getLane(1, AutomationParameter.volume)!.points.length, 2);

        controller.clearLane(1, AutomationParameter.volume);
        expect(controller.getLane(1, AutomationParameter.volume)!.points.length, 0);
      });

      test('clearLane on non-existent lane does nothing', () {
        // Should not throw
        controller.clearLane(99, AutomationParameter.volume);
      });

      test('clearLane only affects the specified parameter', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );
        controller.addPoint(
          1,
          AutomationParameter.pan,
          AutomationPoint(time: 0.0, value: 0.0),
        );

        controller.clearLane(1, AutomationParameter.volume);

        expect(controller.getLane(1, AutomationParameter.volume)!.hasAutomation, isFalse);
        expect(controller.getLane(1, AutomationParameter.pan)!.hasAutomation, isTrue);
      });

      test('addPoint to different parameters on same track', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );
        controller.addPoint(
          1,
          AutomationParameter.pan,
          AutomationPoint(time: 0.0, value: -0.3),
        );

        final volumeLane = controller.getLane(1, AutomationParameter.volume)!;
        final panLane = controller.getLane(1, AutomationParameter.pan)!;
        expect(volumeLane.points.length, 1);
        expect(panLane.points.length, 1);
        expect(volumeLane.points.first.value, 0.5);
        expect(panLane.points.first.value, -0.3);
      });
    });

    // ========================================
    // 4. hasAutomation
    // ========================================
    group('hasAutomation', () {
      test('returns false for track with no automation data', () {
        expect(controller.hasAutomation(1), isFalse);
      });

      test('returns false for track with empty lanes (shown but no points)', () {
        controller.showAutomationForTrack(1);
        expect(controller.hasAutomation(1), isFalse);
      });

      test('returns true after addPoint', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );
        expect(controller.hasAutomation(1), isTrue);
      });

      test('returns false after clearLane removes all points', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );
        controller.clearLane(1, AutomationParameter.volume);
        expect(controller.hasAutomation(1), isFalse);
      });

      test('returns true when only one parameter has points', () {
        controller.addPoint(
          1,
          AutomationParameter.pan,
          AutomationPoint(time: 0.0, value: 0.0),
        );
        expect(controller.hasAutomation(1), isTrue);
      });

      test('returns true when multiple parameters have points', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );
        controller.addPoint(
          1,
          AutomationParameter.pan,
          AutomationPoint(time: 0.0, value: 0.0),
        );
        expect(controller.hasAutomation(1), isTrue);
      });

      test('hasAutomationForParameter returns false when empty', () {
        expect(
          controller.hasAutomationForParameter(1, AutomationParameter.volume),
          isFalse,
        );
      });

      test('hasAutomationForParameter returns true for parameter with points', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );
        expect(
          controller.hasAutomationForParameter(1, AutomationParameter.volume),
          isTrue,
        );
        expect(
          controller.hasAutomationForParameter(1, AutomationParameter.pan),
          isFalse,
        );
      });

      test('hasAutomation returns false after removePoint removes last point', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(id: 'p1', time: 0.0, value: 0.5),
        );
        controller.removePoint(1, AutomationParameter.volume, 'p1');
        expect(controller.hasAutomation(1), isFalse);
      });
    });

    // ========================================
    // 5. getValueAtTime
    // ========================================
    group('getValueAtTime', () {
      test('returns default value when lane has no points', () {
        expect(
          controller.getValueAtTime(1, AutomationParameter.volume, 0.0),
          AutomationParameter.volume.defaultValue,
        );
      });

      test('returns default value for non-existent track', () {
        expect(
          controller.getValueAtTime(99, AutomationParameter.volume, 5.0),
          AutomationParameter.volume.defaultValue,
        );
      });

      test('returns default for pan when no data exists', () {
        expect(
          controller.getValueAtTime(1, AutomationParameter.pan, 0.0),
          AutomationParameter.pan.defaultValue,
        );
      });

      test('returns point value at exact point time', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 2.0, value: 0.6),
        );

        expect(controller.getValueAtTime(1, AutomationParameter.volume, 2.0), 0.6);
      });

      test('returns first point value before first point', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 2.0, value: 0.6),
        );
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 4.0, value: 0.8),
        );

        expect(controller.getValueAtTime(1, AutomationParameter.volume, 0.0), 0.6);
        expect(controller.getValueAtTime(1, AutomationParameter.volume, 1.0), 0.6);
      });

      test('returns last point value after last point', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 2.0, value: 0.6),
        );
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 4.0, value: 0.8),
        );

        expect(controller.getValueAtTime(1, AutomationParameter.volume, 5.0), 0.8);
        expect(controller.getValueAtTime(1, AutomationParameter.volume, 100.0), 0.8);
      });

      test('linear interpolation between two points', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.0),
        );
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 4.0, value: 1.0),
        );

        // Midpoint
        expect(
          controller.getValueAtTime(1, AutomationParameter.volume, 2.0),
          closeTo(0.5, 0.001),
        );
        // Quarter
        expect(
          controller.getValueAtTime(1, AutomationParameter.volume, 1.0),
          closeTo(0.25, 0.001),
        );
        // Three-quarter
        expect(
          controller.getValueAtTime(1, AutomationParameter.volume, 3.0),
          closeTo(0.75, 0.001),
        );
      });

      test('linear interpolation with multiple segments', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.0),
        );
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 2.0, value: 1.0),
        );
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 4.0, value: 0.0),
        );

        // First segment midpoint
        expect(
          controller.getValueAtTime(1, AutomationParameter.volume, 1.0),
          closeTo(0.5, 0.001),
        );
        // Second segment midpoint
        expect(
          controller.getValueAtTime(1, AutomationParameter.volume, 3.0),
          closeTo(0.5, 0.001),
        );
        // At the peak
        expect(
          controller.getValueAtTime(1, AutomationParameter.volume, 2.0),
          closeTo(1.0, 0.001),
        );
      });

      test('interpolation works with pan values (bipolar range)', () {
        controller.addPoint(
          1,
          AutomationParameter.pan,
          AutomationPoint(time: 0.0, value: -1.0),
        );
        controller.addPoint(
          1,
          AutomationParameter.pan,
          AutomationPoint(time: 4.0, value: 1.0),
        );

        // Midpoint should be center (0.0)
        expect(
          controller.getValueAtTime(1, AutomationParameter.pan, 2.0),
          closeTo(0.0, 0.001),
        );
      });

      test('single point returns that value everywhere', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 2.0, value: 0.7),
        );

        expect(controller.getValueAtTime(1, AutomationParameter.volume, 0.0), 0.7);
        expect(controller.getValueAtTime(1, AutomationParameter.volume, 2.0), 0.7);
        expect(controller.getValueAtTime(1, AutomationParameter.volume, 10.0), 0.7);
      });
    });

    // ========================================
    // 6. Serialization
    // ========================================
    group('serialization', () {
      test('toJson returns empty automation when no data', () {
        final json = controller.toJson();
        expect(json['automation'], isA<Map>());
        expect((json['automation'] as Map).isEmpty, isTrue);
      });

      test('toJson does not include empty lanes', () {
        controller.showAutomationForTrack(1);
        final json = controller.toJson();
        expect((json['automation'] as Map).isEmpty, isTrue);
      });

      test('toJson includes lanes with points', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(id: 'p1', time: 2.0, value: 0.5),
        );

        final json = controller.toJson();
        final automation = json['automation'] as Map<String, dynamic>;
        expect(automation.containsKey('1'), isTrue);

        final trackData = automation['1'] as Map<String, dynamic>;
        expect(trackData.containsKey('volume'), isTrue);
      });

      test('toJson/loadFromJson round-trip preserves data', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(id: 'p1', time: 2.0, value: 0.5),
        );
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(id: 'p2', time: 4.0, value: 0.8),
        );
        controller.addPoint(
          1,
          AutomationParameter.pan,
          AutomationPoint(id: 'p3', time: 1.0, value: -0.5),
        );
        controller.addPoint(
          2,
          AutomationParameter.volume,
          AutomationPoint(id: 'p4', time: 0.0, value: 1.0),
        );

        final json = controller.toJson();

        // Create a new controller and load the JSON
        final controller2 = AutomationController();
        controller2.loadFromJson(json);

        // Verify track 1 volume
        final lane1Vol = controller2.getLane(1, AutomationParameter.volume);
        expect(lane1Vol, isNotNull);
        expect(lane1Vol!.points.length, 2);
        expect(lane1Vol.points[0].time, 2.0);
        expect(lane1Vol.points[0].value, 0.5);
        expect(lane1Vol.points[1].time, 4.0);
        expect(lane1Vol.points[1].value, 0.8);

        // Verify track 1 pan
        final lane1Pan = controller2.getLane(1, AutomationParameter.pan);
        expect(lane1Pan, isNotNull);
        expect(lane1Pan!.points.length, 1);
        expect(lane1Pan.points[0].time, 1.0);
        expect(lane1Pan.points[0].value, -0.5);

        // Verify track 2 volume
        final lane2Vol = controller2.getLane(2, AutomationParameter.volume);
        expect(lane2Vol, isNotNull);
        expect(lane2Vol!.points.length, 1);
        expect(lane2Vol.points[0].value, 1.0);

        controller2.dispose();
      });

      test('loadFromJson with null resets state', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );
        controller.showAutomationForTrack(1);
        controller.setVisibleParameter(AutomationParameter.pan);

        controller.loadFromJson(null);

        expect(controller.hasAutomation(1), isFalse);
        expect(controller.visibleTrackId, isNull);
        expect(controller.visibleParameter, AutomationParameter.volume);
      });

      test('loadFromJson clears previous state', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );

        controller.loadFromJson({
          'automation': {
            '2': {
              'volume': {
                'id': 'lane-1',
                'trackId': 2,
                'parameter': 'volume',
                'points': [
                  {'id': 'p1', 'time': 1.0, 'value': 0.7},
                ],
                'isExpanded': true,
              },
            },
          },
        });

        expect(controller.hasAutomation(1), isFalse);
        expect(controller.hasAutomation(2), isTrue);
      });

      test('loadFromJson resets visibility state', () {
        controller.showAutomationForTrack(1);
        controller.setVisibleParameter(AutomationParameter.pan);

        controller.loadFromJson(<String, dynamic>{'automation': <String, dynamic>{}});

        expect(controller.visibleTrackId, isNull);
        expect(controller.visibleParameter, AutomationParameter.volume);
      });

      test('toJson only includes tracks with points', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );
        // Track 2 has empty lanes (shown but no points)
        controller.showAutomationForTrack(2);

        final json = controller.toJson();
        final automation = json['automation'] as Map<String, dynamic>;
        expect(automation.containsKey('1'), isTrue);
        expect(automation.containsKey('2'), isFalse);
      });

      test('toJson round-trip preserves point IDs', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(id: 'my-custom-id', time: 1.0, value: 0.5),
        );

        final json = controller.toJson();
        final controller2 = AutomationController();
        controller2.loadFromJson(json);

        final lane = controller2.getLane(1, AutomationParameter.volume)!;
        expect(lane.points.first.id, 'my-custom-id');

        controller2.dispose();
      });
    });

    // ========================================
    // 7. Track lifecycle
    // ========================================
    group('track lifecycle', () {
      test('onTrackDeleted removes automation data', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );
        expect(controller.hasAutomation(1), isTrue);

        controller.onTrackDeleted(1);
        expect(controller.hasAutomation(1), isFalse);
      });

      test('onTrackDeleted hides automation if deleted track was visible', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );
        controller.showAutomationForTrack(1);
        expect(controller.visibleTrackId, 1);

        controller.onTrackDeleted(1);
        expect(controller.visibleTrackId, isNull);
        expect(controller.hasVisibleAutomation, isFalse);
      });

      test('onTrackDeleted does not affect other tracks', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );
        controller.addPoint(
          2,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.7),
        );

        controller.onTrackDeleted(1);
        expect(controller.hasAutomation(1), isFalse);
        expect(controller.hasAutomation(2), isTrue);
      });

      test('onTrackDeleted does not affect visibility of other track', () {
        controller.showAutomationForTrack(2);
        controller.onTrackDeleted(1);
        expect(controller.visibleTrackId, 2);
      });

      test('onTrackDuplicated copies automation to new track', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.3),
        );
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 2.0, value: 0.8),
        );
        controller.addPoint(
          1,
          AutomationParameter.pan,
          AutomationPoint(time: 1.0, value: -0.5),
        );

        controller.onTrackDuplicated(1, 2);

        // New track has automation
        expect(controller.hasAutomation(2), isTrue);

        // Volume lane copied
        final newVolLane = controller.getLane(2, AutomationParameter.volume)!;
        expect(newVolLane.points.length, 2);
        expect(newVolLane.points[0].time, 0.0);
        expect(newVolLane.points[0].value, 0.3);
        expect(newVolLane.points[1].time, 2.0);
        expect(newVolLane.points[1].value, 0.8);

        // Pan lane copied
        final newPanLane = controller.getLane(2, AutomationParameter.pan)!;
        expect(newPanLane.points.length, 1);
        expect(newPanLane.points[0].value, -0.5);
      });

      test('onTrackDuplicated generates new point IDs', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(id: 'original-id', time: 0.0, value: 0.5),
        );

        controller.onTrackDuplicated(1, 2);

        final originalLane = controller.getLane(1, AutomationParameter.volume)!;
        final newLane = controller.getLane(2, AutomationParameter.volume)!;

        expect(originalLane.points.first.id, 'original-id');
        expect(newLane.points.first.id, isNot('original-id'));
      });

      test('onTrackDuplicated preserves original track data', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );

        controller.onTrackDuplicated(1, 2);

        expect(controller.hasAutomation(1), isTrue);
        expect(controller.getLane(1, AutomationParameter.volume)!.points.length, 1);
      });

      test('onTrackDuplicated with non-existent source does nothing', () {
        controller.onTrackDuplicated(99, 100);
        expect(controller.hasAutomation(100), isFalse);
      });

      test('onTrackDuplicated sets correct trackId on new lane', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );

        controller.onTrackDuplicated(1, 5);

        final newLane = controller.getLane(5, AutomationParameter.volume)!;
        expect(newLane.trackId, 5);
      });
    });

    // ========================================
    // 8. clear
    // ========================================
    group('clear', () {
      test('clears all automation data', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );
        controller.addPoint(
          2,
          AutomationParameter.pan,
          AutomationPoint(time: 0.0, value: -0.3),
        );

        controller.clear();

        expect(controller.hasAutomation(1), isFalse);
        expect(controller.hasAutomation(2), isFalse);
        expect(controller.allTrackIds, isEmpty);
      });

      test('resets visibility', () {
        controller.showAutomationForTrack(1);
        controller.clear();

        expect(controller.visibleTrackId, isNull);
        expect(controller.hasVisibleAutomation, isFalse);
      });

      test('resets visible parameter to volume', () {
        controller.setVisibleParameter(AutomationParameter.pan);
        controller.clear();

        expect(controller.visibleParameter, AutomationParameter.volume);
      });

      test('getLane returns null after clear', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );
        controller.clear();

        expect(controller.getLane(1, AutomationParameter.volume), isNull);
      });

      test('getValueAtTime returns default after clear', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );
        controller.clear();

        expect(
          controller.getValueAtTime(1, AutomationParameter.volume, 0.0),
          AutomationParameter.volume.defaultValue,
        );
      });
    });

    // ========================================
    // 9. Notifications
    // ========================================
    group('notifications', () {
      test('showAutomationForTrack notifies listeners', () {
        var notified = false;
        controller.addListener(() => notified = true);

        controller.showAutomationForTrack(1);
        expect(notified, isTrue);
      });

      test('hideAutomation notifies listeners', () {
        controller.showAutomationForTrack(1);

        var notified = false;
        controller.addListener(() => notified = true);

        controller.hideAutomation();
        expect(notified, isTrue);
      });

      test('toggleAutomationForTrack notifies listeners', () {
        var notified = false;
        controller.addListener(() => notified = true);

        controller.toggleAutomationForTrack(1);
        expect(notified, isTrue);
      });

      test('setVisibleParameter notifies listeners', () {
        var notified = false;
        controller.addListener(() => notified = true);

        controller.setVisibleParameter(AutomationParameter.pan);
        expect(notified, isTrue);
      });

      test('addPoint notifies listeners', () {
        var notified = false;
        controller.addListener(() => notified = true);

        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );
        expect(notified, isTrue);
      });

      test('removePoint notifies listeners', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(id: 'p1', time: 0.0, value: 0.5),
        );

        var notified = false;
        controller.addListener(() => notified = true);

        controller.removePoint(1, AutomationParameter.volume, 'p1');
        expect(notified, isTrue);
      });

      test('updatePoint notifies listeners', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(id: 'p1', time: 0.0, value: 0.5),
        );

        var notified = false;
        controller.addListener(() => notified = true);

        controller.updatePoint(
          1,
          AutomationParameter.volume,
          'p1',
          AutomationPoint(id: 'p1', time: 1.0, value: 0.8),
        );
        expect(notified, isTrue);
      });

      test('clearLane notifies listeners', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );

        var notified = false;
        controller.addListener(() => notified = true);

        controller.clearLane(1, AutomationParameter.volume);
        expect(notified, isTrue);
      });

      test('clearTrackAutomation notifies listeners', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );

        var notified = false;
        controller.addListener(() => notified = true);

        controller.clearTrackAutomation(1);
        expect(notified, isTrue);
      });

      test('onTrackDeleted notifies listeners', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );

        var notified = false;
        controller.addListener(() => notified = true);

        controller.onTrackDeleted(1);
        expect(notified, isTrue);
      });

      test('onTrackDuplicated notifies listeners', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );

        var notified = false;
        controller.addListener(() => notified = true);

        controller.onTrackDuplicated(1, 2);
        expect(notified, isTrue);
      });

      test('loadFromJson notifies listeners', () {
        var notified = false;
        controller.addListener(() => notified = true);

        // Pass a non-null JSON map so the method reaches notifyListeners()
        // (loadFromJson(null) returns early before notifying)
        controller.loadFromJson(<String, dynamic>{'automation': <String, dynamic>{}});
        expect(notified, isTrue);
      });

      test('clear notifies listeners', () {
        var notified = false;
        controller.addListener(() => notified = true);

        controller.clear();
        expect(notified, isTrue);
      });

      test('multiple mutations fire correct number of notifications', () {
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(id: 'p1', time: 0.0, value: 0.5),
        );
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(id: 'p2', time: 1.0, value: 0.7),
        );
        controller.removePoint(1, AutomationParameter.volume, 'p1');

        expect(notifyCount, 3);
      });
    });

    // ========================================
    // Edge cases and allTrackIds
    // ========================================
    group('allTrackIds', () {
      test('returns empty when no automation data', () {
        expect(controller.allTrackIds, isEmpty);
      });

      test('returns track IDs that have automation data', () {
        controller.addPoint(
          1,
          AutomationParameter.volume,
          AutomationPoint(time: 0.0, value: 0.5),
        );
        controller.addPoint(
          3,
          AutomationParameter.pan,
          AutomationPoint(time: 0.0, value: 0.0),
        );

        final ids = controller.allTrackIds.toSet();
        expect(ids, containsAll([1, 3]));
      });

      test('includes tracks with empty lanes created by showAutomationForTrack', () {
        controller.showAutomationForTrack(5);
        expect(controller.allTrackIds.contains(5), isTrue);
      });
    });
  });

  // ========================================
  // AutomationParameter enum
  // ========================================
  group('AutomationParameter', () {
    test('volume has correct properties', () {
      expect(AutomationParameter.volume.displayName, 'Volume');
      expect(AutomationParameter.volume.minValue, 0.0);
      expect(AutomationParameter.volume.maxValue, 1.0);
      expect(AutomationParameter.volume.defaultValue, 0.833);
    });

    test('pan has correct properties', () {
      expect(AutomationParameter.pan.displayName, 'Pan');
      expect(AutomationParameter.pan.minValue, -1.0);
      expect(AutomationParameter.pan.maxValue, 1.0);
      expect(AutomationParameter.pan.defaultValue, 0.0);
    });

    test('pan is bipolar', () {
      expect(AutomationParameter.pan.isBipolar, isTrue);
    });

    test('volume is not bipolar', () {
      expect(AutomationParameter.volume.isBipolar, isFalse);
    });

    test('pan centerValue is 0.0', () {
      expect(AutomationParameter.pan.centerValue, 0.0);
    });

    test('volume centerValue is 0.5', () {
      expect(AutomationParameter.volume.centerValue, 0.5);
    });
  });
}
