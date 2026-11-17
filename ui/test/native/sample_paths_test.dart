import 'dart:io';

import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/widgets/shared/boojy_notice.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/daw_harness.dart';
import 'support/native_engine_harness.dart';

void main() {
  // The engine holds every clip's audio and copies it into the project on
  // save. The screen used to keep its own idea of where the file was, which
  // went stale: a sampler made from a clip couldn't find it, and two files
  // with one name dropped on a saved project became the same clip.
  if (!isNativeEngineAvailable) {
    const reason = 'native engine library not found — run ./build.sh first';
    if (isNativeEngineRequired) {
      test('native engine present (required under BOOJY_CI)', () {
        fail('$reason. Refusing to report a vacuous green suite (C92).');
      });
    } else {
      test('Sample paths (native engine)', () {}, skip: reason);
    }
    return;
  }

  /// Drop [path] onto the empty arrangement; returns its clip.
  Future<ClipData> drop(DawHarness h, String path) async {
    await h.daw.onAudioFileDroppedOnEmpty(path);
    await h.settle();
    return h.daw.timelineKey.currentState!.clips.last;
  }

  testWidgets('a sampler made from a clip uses the clip, not its file', (
    tester,
  ) async {
    final h = await DawHarness.start(tester);
    try {
      Notices.instance.reset();
      final first = await drop(h, h.writeClickWav('one.wav'));
      final second = await drop(h, h.writeClickWav('two.wav'));
      // The files go (as a recording's never existed): the clips still play.
      File(first.filePath).deleteSync();
      File(second.filePath).deleteSync();
      final tracksBefore = h.engine.getAllTrackIds().toSet();

      // The Audio Editor's "create sampler from clip".
      h.daw.createSamplerTrackFromClip(first);
      await h.settle();
      // The track menu's "Convert to Sampler".
      h.daw.convertAudioTrackToSampler(second.trackId);
      await h.settle();

      expect(Notices.instance.problems, isEmpty);
      final samplers = h.engine.getAllTrackIds().toSet().difference(
        tracksBefore,
      );
      expect(samplers, hasLength(2));
      for (final id in samplers) {
        expect(h.engine.isSamplerTrack(id), isTrue);
        expect(h.engine.getSamplerSamplePath(id), isNotNull);
      }
    } finally {
      Notices.instance.reset();
      await h.close();
    }
  });

  testWidgets('a sampler that cannot be made leaves no empty track behind', (
    tester,
  ) async {
    final h = await DawHarness.start(tester);
    try {
      Notices.instance.reset();
      final tracksBefore = h.engine.getAllTrackIds();

      h.daw.createSamplerTrackWithSample('${h.tempDir.path}/gone.wav', 'gone');
      await h.settle();

      expect(Notices.instance.problems, hasLength(1));
      expect(h.engine.getAllTrackIds(), tracksBefore);
    } finally {
      Notices.instance.reset();
      await h.close();
    }
  });

  testWidgets('two files with one name dropped on a saved project stay two '
      'clips, and the project holds one copy of each', (tester) async {
    final h = await DawHarness.start(tester);
    try {
      final project = '${h.tempDir.path}/Kicks.audio';
      await h.realTime(() => h.daw.saveProjectToPath(project));

      // Same name, different folders, different audio (2 s and 0.5 s).
      final long = h.writeClickWav('kick.wav');
      final otherDir = Directory('${h.tempDir.path}/other')..createSync();
      final short = '${otherDir.path}/kick.wav';
      File(h.writeClickWav('short.wav', seconds: 0.5)).renameSync(short);

      // With a project folder, a drop used to copy the file: real file work.
      await h.realTime(() => h.daw.onAudioFileDroppedOnEmpty(long));
      final a = h.daw.timelineKey.currentState!.clips.last;
      await h.realTime(() => h.daw.onAudioFileDroppedOnEmpty(short));
      final b = h.daw.timelineKey.currentState!.clips.last;
      expect(a.duration, closeTo(2.0, 0.01));
      expect(b.duration, closeTo(0.5, 0.01), reason: 'its own audio');
      h.expectScreenMatchesEngine(after: 'dropping both files');

      await h.realTime(() => h.daw.saveProjectToPath(project));
      expect(
        Directory('$project/Samples').existsSync(),
        isFalse,
        reason: 'no second copy beside audio/',
      );
      final saved = Directory('$project/audio').listSync();
      expect(saved, hasLength(2));
    } finally {
      await h.close();
    }
  });
}
