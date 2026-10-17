import 'package:boojy_audio/audio_engine.dart';
import 'package:boojy_audio/models/vst3_plugin_data.dart';
import 'package:boojy_audio/services/undo_redo_manager.dart';
import 'package:boojy_audio/services/vst3_plugin_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/mock_audio_engine.dart';

/// The manager only needs an engine for scanning, which these tests don't do.
class _NoEngine implements AudioEngine {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late MockAudioEngine engine;
  late Vst3PluginManager manager;
  final undo = UndoRedoManager();
  final supermassive = Vst3Plugin(
    name: 'ValhallaSupermassive',
    path: '/Library/Audio/Plug-Ins/VST3/ValhallaSupermassive.vst3',
    vendor: 'Valhalla DSP',
  );

  setUp(() {
    engine = MockAudioEngine()..nextEffectId = 20;
    manager = Vst3PluginManager(_NoEngine());
    undo
      ..clear()
      ..initialize(engine);
  });

  test(
    'adding a plugin is one undo step, and the plugin list follows',
    () async {
      await undo.execute(manager.addPluginCommand(1, supermassive));

      expect(engine.addedVst3Plugins.single.path, supermassive.path);
      expect(
        engine.addedVst3Plugins.single.name,
        supermassive.name,
        reason: 'the plugin is picked by name within its file',
      );
      expect(manager.getTrackPluginCounts()[1], 1);
      expect(manager.getPluginInfo(20)?['name'], 'ValhallaSupermassive');

      await undo.undo();
      expect(engine.removedEffectIds, [20]);
      expect(manager.getTrackPluginCounts()[1] ?? 0, 0);
      expect(manager.getPluginInfo(20), isNull);

      await undo.redo();
      expect(engine.addedVst3Plugins, hasLength(2));
      expect(manager.getTrackPluginCounts()[1], 1);
      expect(manager.getPluginInfo(21)?['name'], 'ValhallaSupermassive');
    },
  );

  test('a plugin that fails to load leaves the list alone', () async {
    engine.nextEffectId = -1;
    final command = manager.addPluginCommand(1, supermassive);

    await undo.execute(command);

    expect(command.createdEffectId, -1);
    expect(manager.getTrackPluginCounts()[1] ?? 0, 0);
  });
}
