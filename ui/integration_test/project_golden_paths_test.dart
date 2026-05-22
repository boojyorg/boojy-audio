import 'dart:io';

import 'package:boojy_audio/audio_engine.dart';
import 'package:boojy_audio/models/midi_note_data.dart';
import 'package:boojy_audio/models/track_send_data.dart';
import 'package:boojy_audio/services/commands/clip_commands.dart';
import 'package:boojy_audio/services/project_manager.dart';
import 'package:boojy_audio/services/undo_redo_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_engine_harness.dart';

void main() {
  group('Project golden paths (native engine)', () {
    late AudioEngine engine;
    late ProjectManager projectManager;
    late Directory projectDir;

    setUp(() async {
      if (!isNativeEngineAvailable) return;

      engine = await createInitializedEngine();
      UndoRedoManager().initialize(engine);
      UndoRedoManager().clear();
      projectManager = ProjectManager(engine);
      projectDir = createTempProjectDir();
    });

    tearDown(() {
      if (!isNativeEngineAvailable) return;
      deleteTempProjectDir(projectDir);
    });

    test('create MIDI track → save → reload preserves track count', () async {
      if (!isNativeEngineAvailable) {
        // Stub/web CI jobs without a built engine — skip gracefully.
        return;
      }

      final baselineCount = engine.getTrackCount();
      final trackId = engine.createTrack('midi', 'Integration MIDI');
      expect(trackId, greaterThan(0));
      expect(engine.getTrackCount(), baselineCount + 1);

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

      final saveResult = await projectManager.saveProjectToPath(
        projectDir.path,
        uiLayout,
      );
      expect(saveResult.success, isTrue, reason: saveResult.message);
      expect(File('${projectDir.path}/project.json').existsSync(), isTrue);
      expect(File('${projectDir.path}/ui_layout.json').existsSync(), isTrue);

      final loadResult = await projectManager.loadProject(projectDir.path);
      expect(
        loadResult.result.success,
        isTrue,
        reason: loadResult.result.message,
      );
      expect(engine.getTrackCount(), baselineCount + 1);
    });

    test('MIDI note in clip → save → reload preserves note data', () async {
      if (!isNativeEngineAvailable) return;

      final trackId = engine.createTrack('midi', 'Note Test');
      expect(trackId, greaterThan(0));

      final clipId = engine.createMidiClip();
      expect(clipId, isNot(-1));

      const note = 60;
      const velocity = 100;
      const noteStart = 0.0;
      const noteDuration = 2.0;

      final addNoteResult = engine.addMidiNoteToClip(
        clipId,
        note,
        velocity,
        noteStart,
        noteDuration,
      );
      expect(addNoteResult.startsWith('Error'), isFalse, reason: addNoteResult);

      final placed = engine.addMidiClipToTrack(trackId, clipId, 0.0);
      expect(placed, 0);

      await projectManager.saveProjectToPath(projectDir.path, null);

      final reload = await projectManager.loadProject(projectDir.path);
      expect(reload.result.success, isTrue, reason: reload.result.message);

      final clips = parseMidiClipsInfo(engine.getAllMidiClipsInfo());
      expect(clips, isNotEmpty);
      expect(clips.first['noteCount'], greaterThanOrEqualTo(1));

      final reloadedClipId = clips.first['clipId'] as int;
      final notesRaw = engine.getMidiClipNotes(reloadedClipId);
      expect(notesRaw.startsWith('Error'), isFalse, reason: notesRaw);
      expect(notesRaw, contains('$note,$velocity'));
    });

    test('MIDI clip move → undo restores start time', () async {
      if (!isNativeEngineAvailable) return;

      const tempo = 120.0;
      const beatsPerSecond = tempo / 60.0;

      final trackId = engine.createTrack('midi', 'Move Undo Test');
      expect(trackId, greaterThan(0));

      final clipId = engine.createMidiClip();
      expect(clipId, isNot(-1));
      engine.addMidiNoteToClip(clipId, 60, 100, 0.0, 1.0);
      engine.addMidiClipToTrack(trackId, clipId, 0.0);

      final clip = MidiClipData(
        clipId: clipId,
        trackId: trackId,
        startTime: 0,
        duration: 4,
      );

      final positions = <double>[];

      void applyClipStart(int id, double startBeats) {
        final result = engine.setClipStartTime(
          trackId,
          id,
          startBeats / beatsPerSecond,
        );
        expect(result, contains('MIDI clip'), reason: result);
        positions.add(startBeats);
      }

      await UndoRedoManager().execute(
        MoveMidiClipPositionCommand(
          originalClip: clip,
          oldStartTime: 0,
          newStartTime: 8,
          onClipMoved: applyClipStart,
        ),
      );

      expect(positions, [8.0]);

      final undone = await UndoRedoManager().undo();
      expect(undone, isTrue);
      expect(positions, [8.0, 0.0]);
    });

    test(
      'export WAV smoke test completes for project with MIDI content',
      () async {
        if (!isNativeEngineAvailable) return;

        final trackId = engine.createTrack('midi', 'Export Test');
        expect(trackId, greaterThan(0));

        final clipId = engine.createMidiClip();
        engine.addMidiNoteToClip(clipId, 60, 100, 0.0, 2.0);
        engine.addMidiClipToTrack(trackId, clipId, 0.0);

        final wavPath = '${projectDir.path}/export_smoke.wav';
        engine.resetExportProgress();

        final exportResult = engine.exportToWav(wavPath, normalize: false);
        expect(exportResult.startsWith('Error'), isFalse, reason: exportResult);
        expect(File(wavPath).existsSync(), isTrue);
        expect(
          File(wavPath).lengthSync(),
          greaterThan(44),
        ); // WAV header + samples
      },
    );

    test('shared send → save → reload preserves return and send', () async {
      if (!isNativeEngineAvailable) return;

      final trackId = engine.createTrack('audio', 'Send Test');
      expect(trackId, greaterThan(0));

      final addResult = engine.addSharedSend(trackId, 'reverb');
      expect(addResult.startsWith('Error'), isFalse, reason: addResult);

      final sendsBefore = TrackSendData.parseTrackSendsCsv(
        engine.getTrackSends(trackId),
      );
      expect(sendsBefore, isNotEmpty);

      final returnsBefore = ReturnTrackData.parseAllReturnsCsv(
        engine.getAllReturns(),
      );
      expect(returnsBefore, isNotEmpty);

      await projectManager.saveProjectToPath(projectDir.path, null);

      final reload = await projectManager.loadProject(projectDir.path);
      expect(reload.result.success, isTrue, reason: reload.result.message);

      final sendsAfter = TrackSendData.parseTrackSendsCsv(
        engine.getTrackSends(trackId),
      );
      expect(sendsAfter, hasLength(sendsBefore.length));
      expect(sendsAfter.first.returnId, sendsBefore.first.returnId);

      final returnsAfter = ReturnTrackData.parseAllReturnsCsv(
        engine.getAllReturns(),
      );
      expect(returnsAfter, isNotEmpty);
      expect(returnsAfter.first.effectType, 'reverb');
    });
  });
}
