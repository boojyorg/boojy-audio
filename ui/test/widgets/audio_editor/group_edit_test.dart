import 'package:boojy_audio/models/audio_clip_edit_data.dart';
import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/models/clip_group_edit.dart';
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:boojy_audio/widgets/audio_editor/audio_editor.dart';
import 'package:boojy_audio/widgets/shared/editors/capsule_slider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../mocks/mock_audio_engine.dart';

/// With several clips selected, the Audio Editor's Pitch, Volume and Reverse
/// change the open clip and hand the same change on for the others: a drag
/// as a shift, a typed value or reset as a set.
void main() {
  const open = AudioClipEditData(transposeSemitones: -1, loopEndBeats: 16);

  /// The editor over [others] plus its open clip, rebuilt after every change
  /// with the group as it is now, as the DAW does. Returns the group edits,
  /// the finished edits, and the clips' edits (the open clip's first).
  Future<(List<ClipGroupEdit>, List<String>, List<AudioClipEditData>)>
  pumpEditor(
    WidgetTester tester, {
    List<AudioClipEditData> others = const [
      AudioClipEditData(transposeSemitones: -2),
      AudioClipEditData(),
    ],
  }) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final clip = ClipData(
      clipId: 4,
      trackId: 1,
      filePath: '/loops/vocal.wav',
      startTime: 0,
      duration: 8,
      editData: open,
    );
    final engine = MockAudioEngine()..tempo = 120;
    final edits = <ClipGroupEdit>[];
    final finished = <String>[];
    final clips = [open, ...others];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider(),
            child: StatefulBuilder(
              builder: (context, setState) => AudioEditor(
                audioEngine: engine,
                clipData: clip,
                projectTempo: 120,
                group: ClipGroup.of(clips),
                onGroupEdit: (edit) => setState(() {
                  edits.add(edit);
                  for (var i = 1; i < clips.length; i++) {
                    clips[i] = edit.applyTo(clips[i]);
                  }
                }),
                onClipUpdated: (c) => setState(() => clips[0] = c.editData!),
                onEditFinished: finished.add,
              ),
            ),
          ),
        ),
      ),
    );
    return (edits, finished, clips);
  }

  Future<void> dragPitch(WidgetTester tester, double dy, int steps) async {
    final drag = await tester.startGesture(
      tester.getCenter(find.text(' st')),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < steps; i++) {
      await drag.moveBy(Offset(0, dy));
      await tester.pump();
    }
    await drag.up();
    await tester.pump();
  }

  testWidgets('shows how many clips and the spread of their pitch', (
    tester,
  ) async {
    await pumpEditor(tester);
    expect(find.text('3 clips'), findsOneWidget);
    expect(find.text('-2…0'), findsOneWidget);
  });

  testWidgets('a pitch drag shifts every clip, one edit on release', (
    tester,
  ) async {
    final (_, finished, clips) = await pumpEditor(tester);
    await dragPitch(tester, 6, 6); // down
    final moved = clips[0].transposeSemitones - open.transposeSemitones;
    expect(moved, lessThan(0));
    // Each keeps its distance from the others: -1, -2, 0 all moved alike.
    expect(clips.map((e) => e.transposeSemitones), [
      -1 + moved,
      -2 + moved,
      moved,
    ]);
    expect(finished, ['Change pitch of 3 clips']);
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('a pitch drag stops for the whole group at the limit', (
    tester,
  ) async {
    final (_, _, clips) = await pumpEditor(
      tester,
      others: const [AudioClipEditData(transposeSemitones: 47)],
    );
    await dragPitch(tester, -6, 10); // up, far
    // 47 can go up one semitone; the open clip stops with it.
    expect(clips.map((e) => e.transposeSemitones), [0, 48]);
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('typed semitones set every clip', (tester) async {
    final (edits, finished, _) = await pumpEditor(tester);
    final st = find.text(' st');
    await tester.tap(st);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(st);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '-2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(edits.single, isA<SetSemitones>());
    expect((edits.single as SetSemitones).semitones, -2);
    expect(finished, ['Set pitch of 3 clips to -2 semitones']);
  });

  testWidgets('a volume double-click resets every clip to 0 dB', (
    tester,
  ) async {
    final (edits, _, clips) = await pumpEditor(tester);
    final at =
        tester.getCenter(find.byType(CapsuleSlider)) + const Offset(30, 0);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at);
    await tester.pump(kDoubleTapTimeout);

    expect(edits.last, isA<SetGain>());
    expect((edits.last as SetGain).db, 0);
    expect(clips.map((e) => e.gainDb), [0, 0, 0]);
  });

  testWidgets('Reverse reverses every clip', (tester) async {
    final (edits, finished, _) = await pumpEditor(tester);
    await tester.tap(find.text('Reverse'));
    await tester.pump(kDoubleTapTimeout);

    expect(edits.single, isA<SetReversed>());
    expect((edits.single as SetReversed).reversed, isTrue);
    expect(finished, ['Reverse 3 clips']);
  });
}
