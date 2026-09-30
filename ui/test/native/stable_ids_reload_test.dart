import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:boojy_audio/audio_engine.dart';
import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/services/project_manager.dart';
import 'package:boojy_audio/utils/audio_clips_info.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_engine_harness.dart';

/// Reopening a project must bring back the same tracks and clips under the
/// same ids, so everything the UI files per id (colours, clip extras, audio
/// clips themselves) still lines up. Real engine over `dart:ffi`, no UI.
void main() {
  if (!isNativeEngineAvailable) {
    const reason = 'native engine library not found — run ./build.sh first';
    if (isNativeEngineRequired) {
      test('native engine present (required under BOOJY_CI)', () {
        fail('$reason. Refusing to report a vacuous green suite (C92).');
      });
    } else {
      test('Stable ids across reload (native engine)', () {}, skip: reason);
    }
    return;
  }

  group('Stable ids across reload (native engine)', () {
    late AudioEngine engine;
    late ProjectManager projectManager;
    late Directory projectDir;
    late File wav;

    setUp(() async {
      engine = await createInitializedEngine();
      engine.clearAllTracks();
      projectManager = ProjectManager(engine);
      projectDir = createTempProjectDir(prefix: 'boojy_stable_ids_');
      wav = File('${projectDir.parent.path}/boojy_stable_ids_source.wav')
        ..writeAsBytesSync(_sineWav(seconds: 2.0));
    });

    tearDown(() {
      deleteTempProjectDir(projectDir);
      if (wav.existsSync()) wav.deleteSync();
    });

    UILayoutData layoutWith(List<ClipData> audioClips) =>
        ProjectPersistence.collect(
          libraryWidth: 200,
          mixerWidth: 380,
          bottomHeight: 250,
          libraryCollapsed: false,
          mixerCollapsed: false,
          bottomCollapsed: true,
          loopEnabled: false,
          loopStartBeats: 0,
          loopEndBeats: 4,
          audioClips: audioClips,
        );

    /// What the app does after opening a project: rebuild the audio clips from
    /// the engine, merging the saved extras.
    List<ClipData> rebuild(List<ClipData> saved) => rebuildAudioClips(
      engineClips: parseAudioClipsInfo(engine.getAllAudioClipsInfo()),
      savedClips: saved,
      peaksFor: (id, _) => engine.getWaveformPeaks(id, 1000),
    );

    test(
      'MIDI track + audio track with 2 clips survive two reopens unchanged',
      () async {
        // A deleted track in the middle makes the ids non-contiguous, which is
        // what exposed the bug (a fresh-id load renumbers them).
        final midiTrack = engine.createTrack('midi', 'Keys');
        final doomed = engine.createTrack('audio', 'Doomed');
        final audioTrack = engine.createTrack('audio', 'Drums');
        engine.deleteTrack(doomed);

        final midiClip = engine.createMidiClip();
        engine.addMidiNoteToClip(midiClip, 60, 100, 0.0, 1.0);
        engine.addMidiClipToTrack(midiTrack, midiClip, 2.0);

        final clipA = engine.loadAudioFileToTrack(
          wav.path,
          audioTrack,
          startTime: 0.0,
        );
        final clipB = engine.loadAudioFileToTrack(
          wav.path,
          audioTrack,
          startTime: 3.0,
        );
        expect(clipA, greaterThanOrEqualTo(0));
        expect(clipB, greaterThan(clipA));

        // The UI's own record of those clips, with extras the engine lacks.
        final savedClips = [
          ClipData(
            clipId: clipA,
            trackId: audioTrack,
            filePath: wav.path,
            startTime: 0.0,
            duration: 2.0,
            color: const Color(0xFFFF5500),
            canRepeat: false,
          ),
          ClipData(
            clipId: clipB,
            trackId: audioTrack,
            filePath: wav.path,
            startTime: 3.0,
            duration: 2.0,
          ),
        ];

        final before = rebuild(savedClips);
        final save = await projectManager.saveProjectToPath(
          projectDir.path,
          layoutWith(savedClips),
        );
        expect(save.success, isTrue, reason: save.message);

        for (var reopen = 1; reopen <= 2; reopen++) {
          final load = await projectManager.loadProject(projectDir.path);
          expect(load.result.success, isTrue, reason: load.result.message);

          // Same tracks, same ids (non-contiguous on purpose).
          expect(
            engine.getAllTrackIds().where((id) => id != 0).toList()..sort(),
            [midiTrack, audioTrack],
            reason: 'reopen #$reopen',
          );
          expect(engine.getTrackInfo(audioTrack), contains('Drums'));

          // MIDI clip kept its id and owner.
          final midiClips = parseMidiClipsInfo(engine.getAllMidiClipsInfo());
          expect(midiClips, hasLength(1));
          expect(midiClips.first['clipId'], midiClip);
          expect(midiClips.first['trackId'], midiTrack);

          // Engine agrees about the audio clips (ids, owner, start).
          final info = parseAudioClipsInfo(engine.getAllAudioClipsInfo())
            ..sort((a, b) => a.clipId.compareTo(b.clipId));
          expect(info.map((c) => c.clipId), [clipA, clipB]);
          expect(info.every((c) => c.trackId == audioTrack), isTrue);
          expect(info.map((c) => c.startTime), [0.0, 3.0]);

          // The rebuilt UI list matches what was there before, extras merged.
          final after = rebuild(load.uiLayout!.audioClips!);
          expect(
            after.map((c) => (c.clipId, c.trackId, c.startTime)).toList(),
            before.map((c) => (c.clipId, c.trackId, c.startTime)).toList(),
            reason: 'reopen #$reopen',
          );
          expect(after.first.color, const Color(0xFFFF5500));
          expect(after.first.canRepeat, isFalse);
          expect(after.first.waveformPeaks, isNotEmpty);

          // Saving again must not grow the project's audio folder.
          final resave = await projectManager.saveProjectToPath(
            projectDir.path,
            layoutWith(after),
          );
          expect(resave.success, isTrue, reason: resave.message);
        }

        final audioFiles = Directory(
          '${projectDir.path}/audio',
        ).listSync().map((e) => e.uri.pathSegments.last).toList()..sort();
        expect(audioFiles, [
          '${clipA.toString().padLeft(3, '0')}-boojy_stable_ids_source.wav',
          '${clipB.toString().padLeft(3, '0')}-boojy_stable_ids_source.wav',
        ]);
      },
    );

    test('project whose layout ids are stale still gets its audio back '
        'with clean names', () async {
      final audioTrack = engine.createTrack('audio', 'Audio');
      final clip = engine.loadAudioFileToTrack(
        wav.path,
        audioTrack,
        startTime: 1.0,
      );
      expect(clip, greaterThanOrEqualTo(0));

      final save = await projectManager.saveProjectToPath(
        projectDir.path,
        layoutWith([
          // Filed under ids that match nothing in the engine (what an older
          // build wrote after its ids drifted).
          ClipData(
            clipId: 900,
            trackId: 901,
            filePath: '${projectDir.path}/audio/014-010-007-005-old.wav',
            startTime: 1.0,
            duration: 2.0,
          ),
        ]),
      );
      expect(save.success, isTrue, reason: save.message);

      final load = await projectManager.loadProject(projectDir.path);
      expect(load.result.success, isTrue, reason: load.result.message);

      final rebuilt = rebuild(load.uiLayout!.audioClips!);
      expect(rebuilt, hasLength(1), reason: 'engine clip shown, stale dropped');
      expect(rebuilt.single.clipId, clip);
      expect(rebuilt.single.trackId, audioTrack);
      expect(rebuilt.single.startTime, 1.0);
      expect(rebuilt.single.duration, closeTo(2.0, 0.01));
      expect(rebuilt.single.fileName, 'boojy_stable_ids_source.wav');
    });

    test('a track or clip created after reopening gets a higher id', () async {
      final track = engine.createTrack('audio', 'A');
      final clip = engine.loadAudioFileToTrack(wav.path, track);

      await projectManager.saveProjectToPath(projectDir.path, null);
      final load = await projectManager.loadProject(projectDir.path);
      expect(load.result.success, isTrue, reason: load.result.message);

      final newTrack = engine.createTrack('audio', 'B');
      expect(newTrack, greaterThan(track));
      final newClip = engine.loadAudioFileToTrack(wav.path, newTrack);
      expect(newClip, greaterThan(clip));
    });

    test('New Project numbering restarts at 1', () {
      engine.createTrack('audio', 'x');
      engine.createTrack('audio', 'y');
      engine.clearAllTracks();
      expect(engine.createTrack('audio', 'first'), 1);
    });
  });
}

/// A 16-bit stereo 48 kHz 440 Hz sine WAV.
Uint8List _sineWav({required double seconds}) {
  const sampleRate = 48000;
  final frames = (seconds * sampleRate).round();
  final data = ByteData(frames * 4);
  for (var i = 0; i < frames; i++) {
    final v = (math.sin(2 * math.pi * 440 * i / sampleRate) * 12000).round();
    data.setInt16(i * 4, v, Endian.little);
    data.setInt16(i * 4 + 2, v, Endian.little);
  }
  final header = ByteData(44);
  void tag(int offset, String s) {
    for (var i = 0; i < 4; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  header.setUint32(4, 36 + data.lengthInBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 2, Endian.little); // channels
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 4, Endian.little);
  header.setUint16(32, 4, Endian.little); // block align
  header.setUint16(34, 16, Endian.little); // bits
  tag(36, 'data');
  header.setUint32(40, data.lengthInBytes, Endian.little);
  return Uint8List.fromList([
    ...header.buffer.asUint8List(),
    ...data.buffer.asUint8List(),
  ]);
}
