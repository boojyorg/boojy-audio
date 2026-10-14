import 'package:boojy_audio/audio_engine.dart';
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:boojy_audio/widgets/device_chain/device_chain_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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

void main() {
  testWidgets('a VST3 effect shows as a card beside the built-in ones', (
    tester,
  ) async {
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
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('ValhallaSupermassive'), findsWidgets);
    expect(find.text('Reverb'), findsWidgets);

    // Unmount so the chain's refresh timers stop.
    await tester.pumpWidget(const SizedBox());
  });
}
