import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/controllers/automation_controller.dart';
import 'package:boojy_audio/models/track_automation_data.dart';
import 'package:boojy_audio/services/commands/automation_commands.dart';
import '../../mocks/mock_audio_engine.dart';

void main() {
  late MockAudioEngine mockEngine;
  late AutomationController controller;

  setUp(() {
    mockEngine = MockAudioEngine();
    controller = AutomationController();
  });

  tearDown(() {
    controller.dispose();
  });

  AutomationPoint? findPoint(int trackId, String pointId) {
    final points =
        controller.getLane(trackId, AutomationParameter.volume)?.points ?? [];
    for (final p in points) {
      if (p.id == pointId) return p;
    }
    return null;
  }

  group('AddAutomationPointCommand', () {
    test('execute adds the point, undo removes it', () async {
      final point = AutomationPoint(time: 4.0, value: 0.5);
      final command = AddAutomationPointCommand(
        controller: controller,
        trackId: 1,
        parameter: AutomationParameter.volume,
        point: point,
      );

      await command.execute(mockEngine);
      expect(findPoint(1, point.id), isNotNull);

      await command.undo(mockEngine);
      expect(findPoint(1, point.id), isNull);
    });

    test('notifies onLaneChanged on execute and undo', () async {
      final changedTrackIds = <int>[];
      final command = AddAutomationPointCommand(
        controller: controller,
        trackId: 7,
        parameter: AutomationParameter.volume,
        point: AutomationPoint(time: 0.0, value: 0.8),
        onLaneChanged: changedTrackIds.add,
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(changedTrackIds, [7, 7]);
    });

    test('description names the parameter', () {
      final command = AddAutomationPointCommand(
        controller: controller,
        trackId: 1,
        parameter: AutomationParameter.volume,
        point: AutomationPoint(time: 0.0, value: 0.5),
      );

      expect(command.description, 'Add Volume Automation Point');
    });
  });

  group('MoveAutomationPointCommand', () {
    test('execute applies the new point, undo restores the old one', () async {
      final oldPoint = AutomationPoint(time: 2.0, value: 0.3);
      controller.addPoint(1, AutomationParameter.volume, oldPoint);
      final newPoint = oldPoint.copyWith(time: 6.0, value: 0.9);

      final command = MoveAutomationPointCommand(
        controller: controller,
        trackId: 1,
        parameter: AutomationParameter.volume,
        oldPoint: oldPoint,
        newPoint: newPoint,
      );

      await command.execute(mockEngine);
      var current = findPoint(1, oldPoint.id);
      expect(current?.time, 6.0);
      expect(current?.value, 0.9);

      await command.undo(mockEngine);
      current = findPoint(1, oldPoint.id);
      expect(current?.time, 2.0);
      expect(current?.value, 0.3);
    });
  });

  group('ClearAutomationLaneCommand', () {
    test(
      'execute clears the lane, undo restores all points (same ids)',
      () async {
        final a = AutomationPoint(time: 0.0, value: 0.2);
        final b = AutomationPoint(time: 4.0, value: 0.9);
        controller.addPoint(5, AutomationParameter.volume, a);
        controller.addPoint(5, AutomationParameter.volume, b);

        final changedTrackIds = <int>[];
        final command = ClearAutomationLaneCommand(
          controller: controller,
          trackId: 5,
          parameter: AutomationParameter.volume,
          points: List.of(
            controller.getLane(5, AutomationParameter.volume)!.points,
          ),
          onLaneChanged: changedTrackIds.add,
        );

        await command.execute(mockEngine);
        expect(
          controller.getLane(5, AutomationParameter.volume)?.points,
          isEmpty,
        );

        await command.undo(mockEngine);
        expect(findPoint(5, a.id)?.value, 0.2);
        expect(findPoint(5, b.id)?.value, 0.9);
        expect(changedTrackIds, [5, 5]);
      },
    );
  });

  group('RemoveAutomationPointCommand', () {
    test('execute removes the point, undo restores it (same id)', () async {
      final point = AutomationPoint(time: 1.0, value: 0.6);
      controller.addPoint(3, AutomationParameter.volume, point);

      final command = RemoveAutomationPointCommand(
        controller: controller,
        trackId: 3,
        parameter: AutomationParameter.volume,
        point: point,
      );

      await command.execute(mockEngine);
      expect(findPoint(3, point.id), isNull);

      await command.undo(mockEngine);
      final restored = findPoint(3, point.id);
      expect(restored, isNotNull);
      expect(restored?.time, 1.0);
      expect(restored?.value, 0.6);
    });
  });
}
