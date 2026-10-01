import 'package:boojy_audio/audio_engine.dart';
import 'package:boojy_audio/models/tool_mode.dart';
import 'package:boojy_audio/services/undo_redo_manager.dart';
import 'package:boojy_audio/theme/boojy_icons.dart';
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:boojy_audio/widgets/shared/boojy_notice.dart';
import 'package:boojy_audio/widgets/timeline/timeline_models.dart';
import 'package:boojy_audio/widgets/timeline_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/native_engine_harness.dart';

// Files dragged in from Finder: the drag only reports the cursor until drop,
// so the timeline shows a one-bar placeholder where the clip will start. These
// drive the real timeline through the desktop_drop channel (the same messages
// the macOS plugin sends) with a library-width gap on the left, which is what
// exposed the empty-area drop landing ~10 beats left of the cursor.

const _library = 240.0; // arrangement starts this far from the window edge
const _pxPerBeat = 25.0; // 120 bpm, default zoom
const _trackY = 74.0; // inside the first (MIDI) track row
const _audioTrackY = 174.0; // inside the second (audio) track row
const _emptyY = 700.0; // inside the empty area below the tracks

Future<void> _send(WidgetTester tester, String method, Object? args) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'desktop_drop',
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
    (_) {},
  );
  await tester.pump();
}

void main() {
  if (!isNativeEngineAvailable) {
    const reason = 'native engine library not found — run ./build.sh first';
    if (isNativeEngineRequired) {
      test('native engine present (required under BOOJY_CI)', () {
        fail('$reason. Refusing to report a vacuous green suite (C92).');
      });
    } else {
      test('Finder drops (native engine + timeline)', () {}, skip: reason);
    }
    return;
  }

  group('Finder drops onto the timeline', () {
    late AudioEngine engine;
    late int midiTrack;
    late int audioTrack;
    late List<double> emptyDrops;
    late List<double> trackDrops;
    late List<double> audioTrackDrops;
    late GlobalKey<TimelineViewState> key;

    setUp(() async {
      engine = await createInitializedEngine();
      UndoRedoManager().initialize(engine);
      midiTrack = engine.createTrack('midi', 'Finder test');
      audioTrack = engine.createTrack('audio', 'Finder audio');
      emptyDrops = [];
      trackDrops = [];
      audioTrackDrops = [];
      key = GlobalKey<TimelineViewState>();
    });

    tearDown(() {
      engine.deleteTrack(midiTrack);
      engine.deleteTrack(audioTrack);
    });

    Future<void> pumpTimeline(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<ThemeProvider>(
              create: (_) => ThemeProvider(),
              child: Row(
                children: [
                  const SizedBox(width: _library),
                  Expanded(
                    child: TimelineView(
                      key: key,
                      playheadNotifier: ValueNotifier<double>(0.0),
                      audioEngine: engine,
                      tempo: 120.0,
                      toolMode: ToolMode.select,
                      trackOrder: [midiTrack, audioTrack],
                      dragDropCallbacks: DragDropCallbacks(
                        onMidiFileDroppedOnEmpty: (_, beats) =>
                            emptyDrops.add(beats),
                        onMidiFileDroppedOnTrack: (_, _, beats) =>
                            trackDrops.add(beats),
                        onAudioFileDroppedOnTrack: (_, _, beats) =>
                            audioTrackDrops.add(beats),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(key.currentState!.pixelsPerBeat, _pxPerBeat);
    }

    Future<void> hover(WidgetTester tester, double x, double y) async {
      await _send(tester, 'entered', [x, y]);
      await _send(tester, 'updated', [x, y]);
    }

    final placeholder = find.byKey(const ValueKey('finder_drop_placeholder'));

    for (final scroll in [0.0, 100.0]) {
      testWidgets('empty space, scrolled ${scroll}px: placeholder under the '
          'cursor, clip lands there', (tester) async {
        await pumpTimeline(tester);
        key.currentState!.scrollController.jumpTo(scroll);
        await tester.pump();

        const x = _library + 12 * _pxPerBeat;
        await hover(tester, x, _emptyY);
        expect(placeholder, findsOneWidget);
        expect(tester.getRect(placeholder).left, closeTo(x, 0.5));
        expect(find.text('Drop to create new track'), findsOneWidget);
        expect(find.text('Drop to create new Audio track'), findsNothing);

        await _send(tester, 'performOperation', ['/tmp/song.mid']);
        expect(emptyDrops, [12 + scroll / _pxPerBeat]);
        expect(placeholder, findsNothing);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('MIDI track, scrolled ${scroll}px: placeholder instead of '
          'the red "can\'t drop" overlay', (tester) async {
        await pumpTimeline(tester);
        key.currentState!.scrollController.jumpTo(scroll);
        await tester.pump();

        const x = _library + 8 * _pxPerBeat;
        await hover(tester, x, _trackY);
        expect(placeholder, findsOneWidget);
        expect(tester.getRect(placeholder).left, closeTo(x, 0.5));
        expect(find.byIcon(BI.pluginOff), findsNothing);

        await _send(tester, 'performOperation', ['/tmp/song.mid']);
        expect(trackDrops, [8 + scroll / _pxPerBeat]);
        expect(placeholder, findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('audio on an audio track goes through the undoable drop; '
        'audio on a MIDI track is refused', (tester) async {
      await pumpTimeline(tester);
      key.currentState!.scrollController.jumpTo(100);
      await tester.pump();

      const x = _library + 6 * _pxPerBeat;
      await hover(tester, x, _audioTrackY);
      expect(tester.getRect(placeholder).left, closeTo(x, 0.5));
      await _send(tester, 'performOperation', ['/tmp/loop.wav']);
      expect(audioTrackDrops, [6 + 100 / _pxPerBeat]);

      await hover(tester, x, _trackY);
      await _send(tester, 'performOperation', ['/tmp/loop.wav']);
      expect(audioTrackDrops, hasLength(1));
      expect(key.currentState!.clips, isEmpty);
      expect(
        Notices.instance.currentInfo?.text,
        'Audio files go on an audio track or empty space',
      );
      Notices.instance.reset();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('leaving the timeline removes the placeholder', (tester) async {
      await pumpTimeline(tester);
      await hover(tester, _library + 100, _emptyY);
      expect(placeholder, findsOneWidget);
      await _send(tester, 'exited', null);
      expect(placeholder, findsNothing);
      expect(emptyDrops, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
