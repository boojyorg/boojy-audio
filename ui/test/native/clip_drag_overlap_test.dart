import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:boojy_audio/audio_engine.dart';
import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/models/tool_mode.dart';
import 'package:boojy_audio/services/project_manager.dart';
import 'package:boojy_audio/services/undo_redo_manager.dart';
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:boojy_audio/widgets/timeline_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/native_engine_harness.dart';

// Regression coverage for the v0.7.0 release blocker "dragging an audio clip
// over a neighbour on the same track deletes the neighbour". These drive the
// real timeline widget (tap-down, drag, drag-end, undo/redo) over the native
// engine, so the whole path is exercised: gesture maths → overlap resolver →
// undoable command → engine clip state → on-screen clip list.
//
// Root cause (found with this harness on 2026-09-13): the resolver deleted any
// neighbour whose remainder after a partial overlap was under 0.25 s. Snapping
// at the default zoom moves clips in 0.25 s steps and most bundled drum
// one-shots are under 0.5 s, so nearly every drag onto one deleted it.

/// Write a mono 16-bit PCM WAV of [seconds] at 48 kHz (a quiet sine) so the
/// engine can load a real clip without a checked-in fixture.
File writeTestWav(Directory dir, String name, {double seconds = 2.0}) {
  const sampleRate = 48000;
  final frames = (seconds * sampleRate).round();
  final data = ByteData(44 + frames * 2);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + frames * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, frames * 2, Endian.little);
  for (var i = 0; i < frames; i++) {
    final v = (math.sin(2 * math.pi * 220 * i / sampleRate) * 8000).round();
    data.setInt16(44 + i * 2, v, Endian.little);
  }
  final file = File('${dir.path}/$name');
  file.writeAsBytesSync(data.buffer.asUint8List());
  return file;
}

/// Engine-side truth for one track's audio clips, read back through a real
/// project save (the engine has no clip-listing FFI). Keyed by clip id.
Future<Map<int, ({double start, double offset, double? duration})>>
engineClipsOnTrack(AudioEngine engine, Directory saveDir, int trackId) async {
  final uiLayout = ProjectPersistence.collect(
    libraryWidth: 200,
    mixerWidth: 380,
    bottomHeight: 250,
    libraryCollapsed: false,
    mixerCollapsed: false,
    bottomCollapsed: true,
    loopEnabled: false,
    loopStartBeats: 0,
    loopEndBeats: 4,
  );
  final result = await ProjectManager(
    engine,
  ).saveProjectToPath(saveDir.path, uiLayout);
  expect(result.success, isTrue, reason: result.message);

  final json =
      jsonDecode(File('${saveDir.path}/project.json').readAsStringSync())
          as Map<String, dynamic>;
  final tracks = json['tracks'] as List<dynamic>;
  final track = tracks.cast<Map<String, dynamic>>().firstWhere(
    (t) => t['id'] == trackId,
  );
  final clips = (track['clips'] as List<dynamic>).cast<Map<String, dynamic>>();
  return {
    for (final c in clips)
      (c['id'] as num).toInt(): (
        start: (c['start_time'] as num).toDouble(),
        offset: (c['offset'] as num).toDouble(),
        duration: (c['duration'] as num?)?.toDouble(),
      ),
  };
}

void main() {
  if (!isNativeEngineAvailable) {
    const reason = 'native engine library not found — run ./build.sh first';
    if (isNativeEngineRequired) {
      test('native engine present (required under BOOJY_CI)', () {
        fail('$reason. Refusing to report a vacuous green suite (C92).');
      });
    } else {
      test('Clip drag overlap (native engine + timeline)', () {}, skip: reason);
    }
    return;
  }

  group('Audio clip drag over a neighbour (timeline widget + native engine)', () {
    late AudioEngine engine;
    late Directory dir;
    late int trackId;

    setUp(() async {
      engine = await createInitializedEngine();
      UndoRedoManager().initialize(engine);
      UndoRedoManager().clear();
      dir = createTempProjectDir(prefix: 'boojy_overlap_');
      trackId = engine.createTrack('audio', 'Overlap test');
      expect(trackId, greaterThan(0));
    });

    tearDown(() {
      engine.deleteTrack(trackId);
      deleteTempProjectDir(dir);
    });

    /// Pump the timeline at 120 bpm / 25 px per beat (50 px per second) with
    /// the given clips loaded in the engine and mirrored in the UI list.
    Future<TimelineViewState> pumpTimeline(
      WidgetTester tester,
      List<ClipData> clips,
    ) async {
      final key = GlobalKey<TimelineViewState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<ThemeProvider>(
              create: (_) => ThemeProvider(),
              child: TimelineView(
                key: key,
                playheadNotifier: ValueNotifier<double>(0.0),
                audioEngine: engine,
                tempo: 120.0,
                toolMode: ToolMode.select,
                trackOrder: [trackId],
              ),
            ),
          ),
        ),
      );
      // Let the track list load from the engine and the row appear.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final state = key.currentState!;
      expect(state.pixelsPerSecond, closeTo(50.0, 0.001));
      for (final clip in clips) {
        state.addClip(clip);
      }
      await tester.pump();
      for (final clip in clips) {
        expect(
          find.byKey(ValueKey('audio_clip_${clip.clipId}')),
          findsOneWidget,
        );
      }
      return state;
    }

    /// Load [wav] on the test track at [start] and return its UI ClipData.
    ClipData load(File wav, double start) {
      final id = engine.loadAudioFileToTrack(
        wav.path,
        trackId,
        startTime: start,
      );
      expect(id, greaterThanOrEqualTo(0));
      return ClipData(
        clipId: id,
        trackId: trackId,
        filePath: wav.path,
        startTime: start,
        duration: engine.getClipDuration(id),
      );
    }

    /// `tester.drag` spends its first 20 px step crossing the drag slop and
    /// the recogniser discards that step, so the clip moves by (dx - 20) px.
    Future<void> dragClip(WidgetTester tester, int clipId, double dx) async {
      await tester.drag(
        find.byKey(ValueKey('audio_clip_$clipId')),
        Offset(dx, 0),
      );
      // The drag-end handler awaits the undo manager; give it a few frames.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }

    ClipData uiClip(TimelineViewState state, int id) =>
        state.clips.singleWhere((c) => c.clipId == id);

    Future<void> disposeTimeline(WidgetTester tester) =>
        tester.pumpWidget(const SizedBox());

    testWidgets(
      'dogfooding repro: 0.25 s into a 0.4 s one-shot trims it (was deleted), '
      'and undo/redo round-trip in the UI and the engine',
      (tester) async {
        final a = load(writeTestWav(dir, 'a.wav', seconds: 2.0), 0.0);
        final b = load(writeTestWav(dir, 'b.wav', seconds: 0.4), 2.0);
        expect(b.duration, closeTo(0.4, 0.01));
        final state = await pumpTimeline(tester, [a, b]);

        // 32.5 px → 12.5 px effective → 0.25 s, snapped to 0.25 s (1/8 note
        // at this zoom). A now spans 0.25–2.25 s: 0.25 s into B (2.0–2.4 s).
        await dragClip(tester, a.clipId, 32.5);

        final movedA = uiClip(state, a.clipId);
        expect(movedA.startTime, closeTo(0.25, 1e-6));
        expect(
          state.clips.where((c) => c.clipId == b.clipId),
          hasLength(1),
          reason: 'a partial overlap must trim the neighbour, never delete it',
        );
        final trimmedB = uiClip(state, b.clipId);
        expect(trimmedB.startTime, closeTo(movedA.endTime, 1e-6));
        expect(trimmedB.duration, closeTo(0.15, 1e-6));
        expect(trimmedB.offset, closeTo(0.25, 1e-6));
        expect(trimmedB.duration, lessThan(0.25)); // the old deletion floor
        expect(find.byKey(ValueKey('audio_clip_${b.clipId}')), findsOneWidget);

        var engineClips = await engineClipsOnTrack(engine, dir, trackId);
        expect(engineClips[a.clipId]!.start, closeTo(0.25, 1e-6));
        expect(engineClips[b.clipId]!.start, closeTo(2.25, 1e-6));
        expect(engineClips[b.clipId]!.offset, closeTo(0.25, 1e-6));
        expect(engineClips[b.clipId]!.duration, closeTo(0.15, 1e-6));

        // Undo: one Cmd+Z restores both the move and the trim.
        expect(await UndoRedoManager().undo(), isTrue);
        await tester.pump();
        expect(uiClip(state, a.clipId).startTime, closeTo(0.0, 1e-6));
        final restoredB = uiClip(state, b.clipId);
        expect(restoredB.startTime, closeTo(2.0, 1e-6));
        expect(restoredB.duration, closeTo(0.4, 0.01));
        expect(restoredB.offset, closeTo(0.0, 1e-6));
        engineClips = await engineClipsOnTrack(engine, dir, trackId);
        expect(engineClips[a.clipId]!.start, closeTo(0.0, 1e-6));
        expect(engineClips[b.clipId]!.start, closeTo(2.0, 1e-6));
        expect(engineClips[b.clipId]!.offset, closeTo(0.0, 1e-6));
        expect(engineClips[b.clipId]!.duration, closeTo(0.4, 0.01));

        // Redo: the same trim comes back, id unchanged (trimmed in place).
        expect(await UndoRedoManager().redo(), isTrue);
        await tester.pump();
        expect(uiClip(state, a.clipId).startTime, closeTo(0.25, 1e-6));
        final redoneB = uiClip(state, b.clipId);
        expect(redoneB.startTime, closeTo(2.25, 1e-6));
        expect(redoneB.duration, closeTo(0.15, 1e-6));
        expect(redoneB.offset, closeTo(0.25, 1e-6));
        engineClips = await engineClipsOnTrack(engine, dir, trackId);
        expect(engineClips[b.clipId]!.start, closeTo(2.25, 1e-6));
        expect(engineClips[b.clipId]!.offset, closeTo(0.25, 1e-6));
        expect(engineClips[b.clipId]!.duration, closeTo(0.15, 1e-6));

        await disposeTimeline(tester);
      },
    );

    testWidgets(
      'left clip dragged 1 s into an equal-length right neighbour trims its start',
      (tester) async {
        final wav = writeTestWav(dir, 'two.wav', seconds: 2.0);
        final a = load(wav, 0.0);
        final b = load(wav, 2.0);
        final state = await pumpTimeline(tester, [a, b]);

        // 70 px → 50 px effective → 1.0 s. A spans 1–3 s over B at 2–4 s.
        await dragClip(tester, a.clipId, 70);

        expect(uiClip(state, a.clipId).startTime, closeTo(1.0, 1e-6));
        final trimmedB = uiClip(state, b.clipId);
        expect(trimmedB.startTime, closeTo(3.0, 1e-6));
        expect(trimmedB.duration, closeTo(1.0, 1e-6));
        expect(trimmedB.offset, closeTo(1.0, 1e-6));

        final engineClips = await engineClipsOnTrack(engine, dir, trackId);
        expect(engineClips[b.clipId]!.start, closeTo(3.0, 1e-6));
        expect(engineClips[b.clipId]!.offset, closeTo(1.0, 1e-6));
        expect(engineClips[b.clipId]!.duration, closeTo(1.0, 1e-6));

        await disposeTimeline(tester);
      },
    );

    testWidgets(
      'right clip dragged 0.5 s into an equal-length left neighbour trims its end',
      (tester) async {
        final wav = writeTestWav(dir, 'two.wav', seconds: 2.0);
        final a = load(wav, 0.0);
        final b = load(wav, 2.0);
        final state = await pumpTimeline(tester, [a, b]);

        // -45 px → -25 px effective → -0.5 s. B spans 1.5–3.5 s over A (0–2 s).
        await dragClip(tester, b.clipId, -45);

        expect(uiClip(state, b.clipId).startTime, closeTo(1.5, 1e-6));
        final trimmedA = uiClip(state, a.clipId);
        expect(trimmedA.startTime, closeTo(0.0, 1e-6));
        expect(trimmedA.duration, closeTo(1.5, 1e-6));
        expect(trimmedA.offset, closeTo(0.0, 1e-6));

        final engineClips = await engineClipsOnTrack(engine, dir, trackId);
        expect(engineClips[a.clipId]!.start, closeTo(0.0, 1e-6));
        expect(engineClips[a.clipId]!.duration, closeTo(1.5, 1e-6));

        await disposeTimeline(tester);
      },
    );
  });
}
