import 'dart:io';

import 'package:boojy_audio/audio_engine.dart';
import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/services/commands/clip_commands.dart';
import 'package:boojy_audio/services/undo_redo_manager.dart';
import 'package:boojy_audio/utils/clip_overlap_handler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'clip_drag_overlap_test.dart' show engineClipsOnTrack, writeTestWav;
import 'support/native_engine_harness.dart';

// Dropping an audio file onto a track (from the library or Finder) is one
// AddAudioClipCommand. When the new clip lands on a neighbour, the trim it
// causes must be part of that same undo step: Cmd+Z once brings the
// neighbour back whole and removes the new clip; redo trims it again.

void main() {
  if (!isNativeEngineAvailable) {
    const reason = 'native engine library not found — run ./build.sh first';
    if (isNativeEngineRequired) {
      test('native engine present (required under BOOJY_CI)', () {
        fail('$reason. Refusing to report a vacuous green suite (C92).');
      });
    } else {
      test('Add audio clip undo (native engine)', () {}, skip: reason);
    }
    return;
  }

  late AudioEngine engine;
  late Directory dir;
  late int trackId;

  setUp(() async {
    engine = await createInitializedEngine();
    UndoRedoManager().initialize(engine);
    UndoRedoManager().clear();
    dir = createTempProjectDir(prefix: 'boojy_add_clip_');
    trackId = engine.createTrack('audio', 'Drop test');
  });

  tearDown(() {
    engine.deleteTrack(trackId);
    deleteTempProjectDir(dir);
  });

  test('a drop that trims a neighbour undoes and redoes in one step', () async {
    // Neighbour A: 0–2 s. The dropped 2 s clip lands at 1 s, trimming A to
    // 0–1 s.
    final aId = engine.loadAudioFileToTrack(
      writeTestWav(dir, 'a.wav').path,
      trackId,
      startTime: 0.0,
    );
    final ui = <ClipData>[
      ClipData(
        clipId: aId,
        trackId: trackId,
        filePath: '${dir.path}/a.wav',
        startTime: 0.0,
        duration: engine.getClipDuration(aId),
      ),
    ];

    final dropped = writeTestWav(dir, 'b.wav');
    final command = AddAudioClipCommand(
      trackId: trackId,
      filePath: dropped.path,
      startTime: 1.0,
      clipName: 'b.wav',
      resolveOverlaps: (clipId, duration) {
        final result = ClipOverlapHandler.resolveAudioOverlaps(
          tempo: 120,
          newStart: 1.0,
          newEnd: 1.0 + duration,
          existingClips: List<ClipData>.from(ui),
          trackId: trackId,
          excludeClipId: clipId,
        );
        return ResolveAudioOverlapCommand(
          result: result,
          uiRemoveClip: (id) => ui.removeWhere((c) => c.clipId == id),
          uiUpdateClip: (c) {
            final i = ui.indexWhere((x) => x.clipId == c.clipId);
            if (i >= 0) ui[i] = c;
          },
          uiAddClip: ui.add,
        );
      },
      onClipAdded: (id, duration, _) => ui.add(
        ClipData(
          clipId: id,
          trackId: trackId,
          filePath: dropped.path,
          startTime: 1.0,
          duration: duration,
        ),
      ),
      onClipRemoved: (id) => ui.removeWhere((c) => c.clipId == id),
    );

    await UndoRedoManager().execute(command);
    var engineClips = await engineClipsOnTrack(engine, dir, trackId);
    expect(engineClips, hasLength(2));
    expect(engineClips[aId]!.duration, closeTo(1.0, 1e-6));
    expect(ui.singleWhere((c) => c.clipId == aId).duration, closeTo(1.0, 1e-6));

    // One undo: the dropped clip is gone and A is whole again.
    expect(await UndoRedoManager().undo(), isTrue);
    engineClips = await engineClipsOnTrack(engine, dir, trackId);
    expect(engineClips.keys, [aId]);
    expect(engineClips[aId]!.duration, closeTo(2.0, 0.01));
    expect(ui, hasLength(1));
    expect(ui.single.duration, closeTo(2.0, 0.01));

    // Redo: the clip comes back and A is trimmed again.
    expect(await UndoRedoManager().redo(), isTrue);
    engineClips = await engineClipsOnTrack(engine, dir, trackId);
    expect(engineClips, hasLength(2));
    expect(engineClips[aId]!.duration, closeTo(1.0, 1e-6));
    expect(ui, hasLength(2));
  });
}
