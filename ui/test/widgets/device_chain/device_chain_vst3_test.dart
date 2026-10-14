import 'package:boojy_audio/audio_engine.dart';
import 'package:boojy_audio/services/undo_redo_manager.dart';
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:boojy_audio/widgets/device_chain/device_chain_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../mocks/mock_audio_engine.dart';

/// Answers only what the device chain asks the engine; everything else is a
/// no-op.
class _ChainEngine implements AudioEngine {
  @override
  String getTrackEffects(int trackId) => '5,6';

  @override
  String getEffectInfo(int effectId) => effectId == 5
      ? 'type:vst3,bypassed:0,name:ValhallaSupermassive,'
            'path:/Library/Audio/Plug-Ins/VST3/ValhallaSupermassive.vst3'
      : 'type:reverb,bypassed:0,room_size:0.5,damping:0.5,wet_dry:0.3';

  @override
  String getEffectPeakLevels(int effectId) => '-60.00,-60.00';

  @override
  String getTrackPeakLevels(int trackId) => '-60.00,-60.00';

  @override
  String getTrackInfo(int trackId) => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _supermassivePath =
    '/Library/Audio/Plug-Ins/VST3/ValhallaSupermassive.vst3';

Future<void> _pumpChain(
  WidgetTester tester, {
  void Function(int effectId)? onVst3EffectRemoved,
  void Function(int trackId, int effectId, String path, String name)?
  onVst3EffectRestored,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: SizedBox(
            height: 260,
            child: DeviceChainView(
              selectedTrackId: 1,
              audioEngine: _ChainEngine(),
              trackName: 'Audio 1',
              onVst3EffectRemoved: onVst3EffectRemoved,
              onVst3EffectRestored: onVst3EffectRestored,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a VST3 effect shows as a card beside the built-in ones', (
    tester,
  ) async {
    await _pumpChain(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('ValhallaSupermassive'), findsWidgets);
    expect(find.text('Reverb'), findsWidgets);

    // Unmount so the chain's refresh timers stop.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'deleting a VST3 card and undoing it keep the plugin list in step',
    (tester) async {
      final engine = MockAudioEngine()..nextEffectId = 9;
      engine.effectInfoResponses[5] =
          'type:vst3,bypassed:0,name:ValhallaSupermassive,path:$_supermassivePath';
      final undo = UndoRedoManager()
        ..clear()
        ..initialize(engine);
      final removed = <int>[];
      final restored = <(int, int, String, String)>[];
      await _pumpChain(
        tester,
        onVst3EffectRemoved: removed.add,
        onVst3EffectRestored: (track, id, path, name) =>
            restored.add((track, id, path, name)),
      );

      // Select the card, then delete it with the keyboard.
      await tester.tap(find.text('ValhallaSupermassive').last);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(engine.removedEffectIds, [5]);
      expect(removed, [5]);

      await undo.undo();
      expect(engine.addedVst3Plugins.single.path, _supermassivePath);
      expect(restored, [(1, 9, _supermassivePath, 'ValhallaSupermassive')]);

      undo.clear();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
