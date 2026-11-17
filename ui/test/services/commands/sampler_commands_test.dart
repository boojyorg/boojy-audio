import 'package:boojy_audio/services/commands/sampler_commands.dart';
import 'package:boojy_audio/services/undo_redo_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../mocks/mock_audio_engine.dart';

void main() {
  group('LoadSampleCommand', () {
    late MockAudioEngine engine;
    late UndoRedoManager manager;
    var applied = 0;
    var failed = 0;

    LoadSampleCommand load() => LoadSampleCommand(
      trackId: 1,
      newPath: '/samples/kick.wav',
      newRootNote: 60,
      oldPath: null,
      oldParams: const {},
      onApplied: () => applied++,
      onFailed: () => failed++,
    );

    setUp(() {
      engine = MockAudioEngine();
      manager = UndoRedoManager()
        ..clear()
        ..initialize(engine);
      applied = 0;
      failed = 0;
    });

    tearDown(() => manager.clear());

    test('a sample that loads is one undo step', () async {
      await manager.execute(load());

      expect((applied, failed), (1, 0));
      expect(manager.canUndo, isTrue);
    });

    test('a file the engine cannot read is reported and is not an undo '
        'step', () async {
      engine.sampleLoadsSucceed = false;

      await manager.execute(load());

      expect((applied, failed), (0, 1));
      expect(manager.canUndo, isFalse, reason: 'nothing changed');
    });

    test('a redo that can no longer load the file is dropped, not kept as '
        'an undo step', () async {
      await manager.execute(load());
      await manager.undo();
      engine.sampleLoadsSucceed = false; // the file has moved

      await manager.redo();

      expect(failed, 1);
      expect(manager.canUndo, isFalse);
      expect(manager.canRedo, isFalse);
    });
  });
}
