import 'package:boojy_audio/models/audio_clip_edit_data.dart';
import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:boojy_audio/widgets/audio_editor/audio_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../mocks/mock_audio_engine.dart';

void main() {
  // Every warp send re-renders the clip's stretched audio, so a BPM drag
  // sends once, on release, not on every step.
  testWidgets('dragging the clip BPM re-stretches once, on release', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final engine = MockAudioEngine()..tempo = 120;
    final clip = ClipData(
      clipId: 4,
      trackId: 1,
      filePath: '/loops/drums.wav',
      startTime: 0,
      duration: 6.4,
      editData: const AudioClipEditData(
        bpm: 150,
        syncEnabled: true,
        loopEndBeats: 16,
      ),
    );
    final updates = <ClipData>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider(),
            child: AudioEditor(
              audioEngine: engine,
              clipData: clip,
              projectTempo: 120,
              onClipUpdated: updates.add,
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('150 BPM')),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(0, -4));
      await tester.pump();
    }
    expect(engine.warpCalls, isEmpty, reason: 'no re-stretch mid-drag');
    expect(updates.last.editData!.bpm, greaterThan(150));

    await gesture.up();
    await tester.pump();
    final bpm = updates.last.editData!.bpm;
    expect(engine.warpCalls, hasLength(1));
    expect(engine.warpCalls.single.stretch, closeTo(120 / bpm, 1e-9));
    await tester.pump(kDoubleTapTimeout); // let the double-click timer lapse
  });
}
