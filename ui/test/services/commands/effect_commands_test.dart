import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/services/commands/effect_commands.dart';
import '../../mocks/mock_audio_engine.dart';

void main() {
  late MockAudioEngine mockEngine;

  setUp(() {
    mockEngine = MockAudioEngine();
  });

  group('AddEffectCommand', () {
    test('has correct description', () {
      final command = AddEffectCommand(
        trackId: 1,
        trackName: 'Track 1',
        effectType: 'reverb',
        effectName: 'Reverb',
        isVst3: false,
      );

      expect(command.description, 'Add Effect: Reverb');
    });

    test('createdEffectId is null before execute', () {
      final command = AddEffectCommand(
        trackId: 1,
        trackName: 'Track 1',
        effectType: 'reverb',
        effectName: 'Reverb',
        isVst3: false,
      );

      expect(command.createdEffectId, isNull);
    });

    test('execute adds built-in effect', () async {
      final command = AddEffectCommand(
        trackId: 1,
        trackName: 'Track 1',
        effectType: 'reverb',
        effectName: 'Reverb',
        isVst3: false,
      );

      await command.execute(mockEngine);

      expect(command.createdEffectId, isNotNull);
      expect(command.createdEffectId, greaterThanOrEqualTo(0));
      expect(mockEngine.calls, contains('addEffectToTrack'));
      expect(mockEngine.calls, isNot(contains('addVst3EffectToTrack')));
    });

    test('execute adds VST3 effect', () async {
      final command = AddEffectCommand(
        trackId: 1,
        trackName: 'Track 1',
        effectType: '/path/to/plugin.vst3',
        effectName: 'Plugin',
        isVst3: true,
      );

      await command.execute(mockEngine);

      expect(command.createdEffectId, isNotNull);
      expect(mockEngine.calls, contains('addVst3EffectToTrack'));
      expect(mockEngine.calls, isNot(contains('addEffectToTrack')));
    });

    test('execute fires onEffectAdded callback', () async {
      int? addedId;

      final command = AddEffectCommand(
        trackId: 1,
        trackName: 'Track 1',
        effectType: 'reverb',
        effectName: 'Reverb',
        isVst3: false,
        onEffectAdded: (id) => addedId = id,
      );

      await command.execute(mockEngine);

      expect(addedId, command.createdEffectId);
    });

    test('undo removes effect', () async {
      final command = AddEffectCommand(
        trackId: 1,
        trackName: 'Track 1',
        effectType: 'reverb',
        effectName: 'Reverb',
        isVst3: false,
      );

      await command.execute(mockEngine);
      mockEngine.calls.clear();

      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('removeEffectFromTrack'));
    });

    test('undo fires onEffectRemoved callback', () async {
      int? removedId;

      final command = AddEffectCommand(
        trackId: 1,
        trackName: 'Track 1',
        effectType: 'reverb',
        effectName: 'Reverb',
        isVst3: false,
        onEffectRemoved: (id) => removedId = id,
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(removedId, command.createdEffectId);
    });
  });

  group('RemoveEffectCommand', () {
    test('has correct description', () {
      final command = RemoveEffectCommand(
        trackId: 1,
        trackName: 'Track 1',
        effectId: 10,
        effectName: 'Delay',
        effectType: 'delay',
        isVst3: false,
        effectIndex: 0,
      );

      expect(command.description, 'Remove Effect: Delay');
    });

    test('execute removes effect from track', () async {
      final command = RemoveEffectCommand(
        trackId: 1,
        trackName: 'Track 1',
        effectId: 10,
        effectName: 'Delay',
        effectType: 'delay',
        isVst3: false,
        effectIndex: 0,
      );

      await command.execute(mockEngine);

      expect(mockEngine.calls, contains('removeEffectFromTrack'));
    });

    test('execute fires onEffectRemoved callback', () async {
      int? removedId;

      final command = RemoveEffectCommand(
        trackId: 1,
        trackName: 'Track 1',
        effectId: 10,
        effectName: 'Delay',
        effectType: 'delay',
        isVst3: false,
        effectIndex: 0,
        onEffectRemoved: (id) => removedId = id,
      );

      await command.execute(mockEngine);

      expect(removedId, 10);
    });

    test('undo re-adds built-in effect', () async {
      final command = RemoveEffectCommand(
        trackId: 1,
        trackName: 'Track 1',
        effectId: 10,
        effectName: 'Delay',
        effectType: 'delay',
        isVst3: false,
        effectIndex: 0,
      );

      await command.execute(mockEngine);
      mockEngine.calls.clear();

      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('addEffectToTrack'));
    });

    test('undo re-adds VST3 effect', () async {
      final command = RemoveEffectCommand(
        trackId: 1,
        trackName: 'Track 1',
        effectId: 10,
        effectName: 'VST Plugin',
        effectType: '/path/to/plugin.vst3',
        isVst3: true,
        effectIndex: 0,
      );

      await command.execute(mockEngine);
      mockEngine.calls.clear();

      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('addVst3EffectToTrack'));
    });

    test('undo fires onEffectAdded callback', () async {
      int? addedId;

      final command = RemoveEffectCommand(
        trackId: 1,
        trackName: 'Track 1',
        effectId: 10,
        effectName: 'Delay',
        effectType: 'delay',
        isVst3: false,
        effectIndex: 0,
        onEffectAdded: (id) => addedId = id,
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(addedId, isNotNull);
    });
  });

  group('BypassEffectCommand', () {
    test('has correct description when bypassing', () {
      final command = BypassEffectCommand(
        effectId: 1,
        effectName: 'Reverb',
        newBypassed: true,
        oldBypassed: false,
      );

      expect(command.description, 'Bypass Effect: Reverb');
    });

    test('has correct description when enabling', () {
      final command = BypassEffectCommand(
        effectId: 1,
        effectName: 'Reverb',
        newBypassed: false,
        oldBypassed: true,
      );

      expect(command.description, 'Enable Effect: Reverb');
    });

    test('execute sets bypass state', () async {
      final command = BypassEffectCommand(
        effectId: 1,
        effectName: 'Reverb',
        newBypassed: true,
        oldBypassed: false,
      );

      await command.execute(mockEngine);

      expect(mockEngine.calls, contains('setEffectBypass'));
    });

    test('undo restores previous bypass state', () async {
      final command = BypassEffectCommand(
        effectId: 1,
        effectName: 'Reverb',
        newBypassed: true,
        oldBypassed: false,
      );

      await command.execute(mockEngine);
      mockEngine.calls.clear();

      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('setEffectBypass'));
    });
  });

  group('ReorderEffectsCommand', () {
    test('has correct description', () {
      final command = ReorderEffectsCommand(
        trackId: 1,
        trackName: 'Track 1',
        newOrder: [3, 1, 2],
        oldOrder: [1, 2, 3],
      );

      expect(command.description, 'Reorder Effects: Track 1');
    });

    test('execute applies new order', () async {
      final command = ReorderEffectsCommand(
        trackId: 1,
        trackName: 'Track 1',
        newOrder: [3, 1, 2],
        oldOrder: [1, 2, 3],
      );

      await command.execute(mockEngine);

      expect(mockEngine.calls, contains('reorderTrackEffects'));
    });

    test('undo restores old order', () async {
      final command = ReorderEffectsCommand(
        trackId: 1,
        trackName: 'Track 1',
        newOrder: [3, 1, 2],
        oldOrder: [1, 2, 3],
      );

      await command.execute(mockEngine);
      mockEngine.calls.clear();

      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('reorderTrackEffects'));
    });
  });

  group('SetEffectParameterCommand', () {
    test('has correct description', () {
      final command = SetEffectParameterCommand(
        effectId: 1,
        effectName: 'Reverb',
        paramIndex: 0,
        paramName: 'Decay',
        newValue: 0.75,
        oldValue: 0.50,
      );

      expect(command.description,
          'Change Reverb: Decay (0.50 → 0.75)');
    });

    test('execute sets new parameter value', () async {
      final command = SetEffectParameterCommand(
        effectId: 1,
        effectName: 'Reverb',
        paramIndex: 0,
        paramName: 'Decay',
        newValue: 0.75,
        oldValue: 0.50,
      );

      await command.execute(mockEngine);

      expect(mockEngine.calls, contains('setVst3ParameterValue'));
    });

    test('undo restores old parameter value', () async {
      final command = SetEffectParameterCommand(
        effectId: 1,
        effectName: 'Reverb',
        paramIndex: 0,
        paramName: 'Decay',
        newValue: 0.75,
        oldValue: 0.50,
      );

      await command.execute(mockEngine);
      mockEngine.calls.clear();

      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('setVst3ParameterValue'));
    });
  });
}
