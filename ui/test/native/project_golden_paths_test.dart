import 'dart:io';
import 'dart:typed_data';

import 'package:boojy_audio/audio_engine.dart';
import 'package:boojy_audio/models/midi_note_data.dart';
import 'package:boojy_audio/models/track_send_data.dart';
import 'package:boojy_audio/services/commands/clip_commands.dart';
import 'package:boojy_audio/services/commands/send_commands.dart';
import 'package:boojy_audio/services/project_manager.dart';
import 'package:boojy_audio/services/undo_redo_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_engine_harness.dart';

void main() {
  // These exercise the native Rust engine over `dart:ffi` — no UI is pumped, so
  // they run as plain `flutter test` unit tests (under `test/`), NOT as on-device
  // `integration_test -d macos`. That deliberately sidesteps the headless-macOS
  // app-foreground hang the device path suffered: the old `exit(0)`-on-teardown
  // hack, the reporter-grep success check, and the CI retry are all gone. The
  // engine dylib is loaded directly, so `./build.sh` must have produced it first.

  // C92: never report a vacuous green suite. If the native engine is missing,
  // either fail loudly (CI, where the dylib MUST be built) or skip visibly
  // (local/web without a build) — but do not let every test silently
  // early-return while flutter still prints "N tests passed". Because this
  // returns before the group is defined, the tests below run only when the
  // engine is genuinely available, so they need no per-test availability guard.
  if (!isNativeEngineAvailable) {
    const reason = 'native engine library not found — run ./build.sh first';
    if (isNativeEngineRequired) {
      test('native engine present (required under BOOJY_CI)', () {
        fail('$reason. Refusing to report a vacuous green suite (C92).');
      });
    } else {
      test('Project golden paths (native engine)', () {}, skip: reason);
    }
    return;
  }

  group('Project golden paths (native engine)', () {
    late AudioEngine engine;
    late ProjectManager projectManager;
    late Directory projectDir;

    setUp(() async {
      engine = await createInitializedEngine();
      UndoRedoManager().initialize(engine);
      UndoRedoManager().clear();
      projectManager = ProjectManager(engine);
      projectDir = createTempProjectDir();
    });

    tearDown(() {
      deleteTempProjectDir(projectDir);
    });

    test('create MIDI track → save → reload preserves track count', () async {
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

      // Track IDs are remapped on reload — restore assigns fresh IDs and
      // remaps send targets via id_map (same contract as the other reload
      // tests, which re-query rather than reuse pre-save IDs). Verify send
      // persistence from the return side instead of the stale source trackId.
      final returnsAfter = ReturnTrackData.parseAllReturnsCsv(
        engine.getAllReturns(),
      );
      expect(returnsAfter, isNotEmpty);
      expect(returnsAfter.first.effectType, 'reverb');
      expect(
        engine.countSendsToReturn(returnsAfter.first.id),
        greaterThanOrEqualTo(1),
        reason: 'the send must still target the reverb return after reload',
      );
    });

    test(
      'multiple tracks sharing one return → save → reload preserves all sends',
      () async {
        engine.clearAllTracks();

        final trackA = engine.createTrack('audio', 'Multi A');
        final trackB = engine.createTrack('audio', 'Multi B');
        final trackC = engine.createTrack('audio', 'Multi C');
        expect([trackA, trackB, trackC].every((id) => id > 0), isTrue);

        // All three send to the same shared reverb return (dedup → one return).
        for (final id in [trackA, trackB, trackC]) {
          final r = engine.addSharedSend(id, 'reverb');
          expect(r.startsWith('Error'), isFalse, reason: r);
        }

        final returnsBefore = ReturnTrackData.parseAllReturnsCsv(
          engine.getAllReturns(),
        );
        expect(returnsBefore, hasLength(1));
        expect(returnsBefore.first.effectType, 'reverb');
        expect(engine.countSendsToReturn(returnsBefore.first.id), 3);

        await projectManager.saveProjectToPath(projectDir.path, null);

        final reload = await projectManager.loadProject(projectDir.path);
        expect(reload.result.success, isTrue, reason: reload.result.message);

        // IDs are remapped on reload; verify from the return side that all three
        // sends survived and still target the single (de-duplicated) return.
        final returnsAfter = ReturnTrackData.parseAllReturnsCsv(
          engine.getAllReturns(),
        );
        expect(
          returnsAfter,
          hasLength(1),
          reason: 'reload must not duplicate the shared return',
        );
        expect(returnsAfter.first.effectType, 'reverb');
        expect(
          engine.countSendsToReturn(returnsAfter.first.id),
          3,
          reason: 'all three sends must survive the save/reload round-trip',
        );
      },
    );

    test('shared send dedup: second add reuses existing return', () async {
      engine.clearAllTracks();

      final trackA = engine.createTrack('audio', 'Dedup A');
      final trackB = engine.createTrack('audio', 'Dedup B');
      expect(trackA, greaterThan(0));
      expect(trackB, greaterThan(0));

      final addA = engine.addSharedSend(trackA, 'reverb');
      expect(addA.startsWith('Error'), isFalse, reason: addA);

      final returnsAfterA = ReturnTrackData.parseAllReturnsCsv(
        engine.getAllReturns(),
      );
      expect(returnsAfterA, hasLength(1));
      final reverbReturnId = returnsAfterA.first.id;

      final addB = engine.addSharedSend(trackB, 'reverb');
      expect(addB.startsWith('Error'), isFalse, reason: addB);

      final returnsAfterB = ReturnTrackData.parseAllReturnsCsv(
        engine.getAllReturns(),
      );
      expect(
        returnsAfterB,
        hasLength(1),
        reason: 'second shared reverb send must reuse the existing return',
      );
      expect(returnsAfterB.first.id, reverbReturnId);

      final sendsA = TrackSendData.parseTrackSendsCsv(
        engine.getTrackSends(trackA),
      );
      final sendsB = TrackSendData.parseTrackSendsCsv(
        engine.getTrackSends(trackB),
      );
      expect(sendsA, hasLength(1));
      expect(sendsB, hasLength(1));
      expect(sendsA.first.returnId, reverbReturnId);
      expect(sendsB.first.returnId, reverbReturnId);
    });

    test('AddSharedSendCommand undo removes both send and return', () async {
      engine.clearAllTracks();
      UndoRedoManager().clear();

      final trackId = engine.createTrack('audio', 'Undo Send');
      expect(trackId, greaterThan(0));

      final command = AddSharedSendCommand(
        sourceTrackId: trackId,
        sourceTrackName: 'Undo Send',
        effectType: 'reverb',
        effectLabel: 'Reverb',
      );
      await UndoRedoManager().execute(command);

      expect(command.returnTrackId, isNotNull);
      final returnId = command.returnTrackId!;

      var sends = TrackSendData.parseTrackSendsCsv(
        engine.getTrackSends(trackId),
      );
      var returns = ReturnTrackData.parseAllReturnsCsv(engine.getAllReturns());
      expect(sends, hasLength(1));
      expect(sends.first.returnId, returnId);
      expect(returns.where((r) => r.id == returnId), hasLength(1));

      final undone = await UndoRedoManager().undo();
      expect(undone, isTrue);

      sends = TrackSendData.parseTrackSendsCsv(engine.getTrackSends(trackId));
      returns = ReturnTrackData.parseAllReturnsCsv(engine.getAllReturns());
      expect(sends, isEmpty);
      expect(
        returns.where((r) => r.id == returnId),
        isEmpty,
        reason: 'undoing the only sender must also remove the return bus',
      );

      final redone = await UndoRedoManager().redo();
      expect(redone, isTrue);

      sends = TrackSendData.parseTrackSendsCsv(engine.getTrackSends(trackId));
      returns = ReturnTrackData.parseAllReturnsCsv(engine.getAllReturns());
      expect(sends, hasLength(1));
      expect(returns, isNotEmpty);
    });

    test('export with reverb send has more energy than dry baseline', () async {
      Future<File> renderProject({required bool withReverbSend}) async {
        engine.clearAllTracks();

        final trackId = engine.createTrack('midi', 'Reverb Energy');
        expect(trackId, greaterThan(0));

        // MIDI tracks are silent until an instrument is added — attach the
        // built-in synth so the note renders to audio (otherwise both the dry
        // and wet renders are silent and there's nothing for the send to carry).
        engine.setTrackInstrument(trackId, 'synth');

        final clipId = engine.createMidiClip();
        expect(clipId, isNot(-1));
        engine.addMidiNoteToClip(clipId, 60, 110, 0.0, 1.0);
        engine.addMidiClipToTrack(trackId, clipId, 0.0);

        if (withReverbSend) {
          final addResult = engine.addSharedSend(trackId, 'reverb');
          expect(addResult.startsWith('Error'), isFalse, reason: addResult);
          final returns = ReturnTrackData.parseAllReturnsCsv(
            engine.getAllReturns(),
          );
          expect(returns, hasLength(1));
          engine.setSendAmount(trackId, returns.first.id, -6.0);
        }

        final wavPath =
            '${projectDir.path}/energy_${withReverbSend ? "wet" : "dry"}.wav';
        engine.resetExportProgress();
        final result = engine.exportToWav(wavPath, normalize: false);
        expect(result.startsWith('Error'), isFalse, reason: result);
        final file = File(wavPath);
        expect(file.existsSync(), isTrue);
        expect(file.lengthSync(), greaterThan(44));
        return file;
      }

      final dryFile = await renderProject(withReverbSend: false);
      final dryEnergy = _wavEnergy(dryFile);
      final dryTail = _wavEnergyTail(dryFile, 0.4);

      final wetFile = await renderProject(withReverbSend: true);
      final wetTail = _wavEnergyTail(wetFile, 0.4);

      expect(
        dryEnergy,
        greaterThan(0),
        reason: 'dry render must contain signal (synth + MIDI note)',
      );
      // A reverb send rings out after the note ends. Compare the tail region
      // (last 40% of the export), where the dry render has decayed to near
      // silence — this isolates the reverb's added energy rather than the
      // total, which is confounded by early-reflection phase cancellation and
      // the master limiter during the note itself.
      expect(
        wetTail,
        greaterThan(dryTail * 2.0),
        reason:
            'reverb send should ring out in the tail well above the dry decay '
            '(dryTail=$dryTail wetTail=$wetTail)',
      );
    });
  });
}

/// Sum of squared float32 samples after the WAV `data` chunk.
///
/// Engine exports as 32-bit float WAV at 48 kHz; this skips through the
/// header chunks to find `data` and returns the energy of the audio payload.
double _wavEnergy(File wavFile) {
  final bytes = wavFile.readAsBytesSync();
  // Walk RIFF chunks looking for `data`.
  // Header: 'RIFF' (4) + size (4) + 'WAVE' (4) = 12 bytes, then chunks.
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = ByteData.sublistView(
      bytes,
      offset + 4,
      offset + 8,
    ).getUint32(0, Endian.little);
    if (id == 'data') {
      final dataStart = offset + 8;
      final dataEnd = (dataStart + size).clamp(0, bytes.length);
      final sampleBytes = dataEnd - dataStart;
      final sampleCount = sampleBytes ~/ 4;
      final samples = Float32List.view(
        bytes.buffer,
        bytes.offsetInBytes + dataStart,
        sampleCount,
      );
      var energy = 0.0;
      for (final s in samples) {
        energy += s * s;
      }
      return energy;
    }
    offset += 8 + size;
    if (size.isOdd) offset += 1; // chunk size word-align
  }
  return 0.0;
}

/// Energy of the final [fraction] of the WAV payload — the reverb-tail region,
/// where the dry render has decayed toward silence. Isolating the tail avoids
/// the phase-cancellation/limiter confounds of comparing total energy.
double _wavEnergyTail(File wavFile, double fraction) {
  final bytes = wavFile.readAsBytesSync();
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = ByteData.sublistView(
      bytes,
      offset + 4,
      offset + 8,
    ).getUint32(0, Endian.little);
    if (id == 'data') {
      final dataStart = offset + 8;
      final dataEnd = (dataStart + size).clamp(0, bytes.length);
      final sampleCount = (dataEnd - dataStart) ~/ 4;
      final samples = Float32List.view(
        bytes.buffer,
        bytes.offsetInBytes + dataStart,
        sampleCount,
      );
      final tailStart = (sampleCount * (1.0 - fraction)).floor();
      var energy = 0.0;
      for (var i = tailStart; i < sampleCount; i++) {
        energy += samples[i] * samples[i];
      }
      return energy;
    }
    offset += 8 + size;
    if (size.isOdd) offset += 1;
  }
  return 0.0;
}
