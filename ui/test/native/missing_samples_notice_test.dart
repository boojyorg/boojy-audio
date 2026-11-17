import 'dart:io';

import 'package:boojy_audio/widgets/shared/boojy_notice.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/daw_harness.dart';
import 'support/native_engine_harness.dart';

void main() {
  // Sampler and drum-pad samples are copied into the project on save. If one
  // still can't be found when the project opens, the project opens anyway and
  // a notice names the file: a pad that loads silent with no message, and is
  // then wiped by the next save, was the bug.
  if (!isNativeEngineAvailable) {
    const reason = 'native engine library not found — run ./build.sh first';
    if (isNativeEngineRequired) {
      test('native engine present (required under BOOJY_CI)', () {
        fail('$reason. Refusing to report a vacuous green suite (C92).');
      });
    } else {
      test('Missing samples notice (native engine)', () {}, skip: reason);
    }
    return;
  }

  testWidgets('samples are saved in the project, and a missing one is named '
      'when the project opens', (tester) async {
    final h = await DawHarness.start(tester);
    try {
      Notices.instance.reset();
      final lead = h.writeClickWav('lead.wav');
      final kick = h.writeClickWav('kick.wav', seconds: 0.5);

      final sampler = h.engine.createTrack('midi', 'Sampler');
      h.engine.createSamplerForTrack(sampler);
      expect(h.engine.loadSampleForTrack(sampler, lead, 60), isTrue);
      final drums = h.engine.createTrack('midi', 'Drums');
      h.engine.createDrumKitForTrack(drums);
      final pad = h.engine.addDrumPad(drums, 36);
      expect(h.engine.loadDrumPadSample(drums, pad, kick), isTrue);

      final path = '${h.tempDir.path}/Samples Test.audio';
      await h.realTime(() => h.daw.saveProjectToPath(path));
      expect(File('$path/audio/lead.wav').existsSync(), isTrue);
      expect(File('$path/audio/kick.wav').existsSync(), isTrue);

      // The originals go: the project no longer needs them.
      File(lead).deleteSync();
      File(kick).deleteSync();
      await h.realTime(() => h.daw.openRecentProject(path));
      await h.settleUntil(() => !h.daw.isLoading, what: 'the reopen');
      expect(h.engine.getMissingSampleNames(), isEmpty);
      expect(Notices.instance.problems, isEmpty);
      expect(h.engine.getDrumKitInfo(drums)!.pads.single.hasSample, isTrue);

      // One sample disappears from the project folder.
      File('$path/audio/kick.wav').deleteSync();
      await h.realTime(() => h.daw.openRecentProject(path));
      await h.settleUntil(() => !h.daw.isLoading, what: 'the second reopen');
      expect(
        Notices.instance.problems.single.text,
        "Couldn't find the sample kick.wav. "
        'It stays silent until you load it again.',
      );
      expect(h.engine.getDrumKitInfo(drums)!.pads.single.hasSample, isFalse);

      // Opening a project with nothing missing takes the notice away.
      await h.realTime(() => h.daw.saveProjectToPath(path));
      File(
        '$path/audio/kick.wav',
      ).writeAsBytesSync(File('$path/audio/lead.wav').readAsBytesSync());
      await h.realTime(() => h.daw.openRecentProject(path));
      await h.settleUntil(() => !h.daw.isLoading, what: 'the third reopen');
      expect(Notices.instance.problems, isEmpty);
      expect(h.engine.getDrumKitInfo(drums)!.pads.single.hasSample, isTrue);
    } finally {
      Notices.instance.reset();
      await h.close();
    }
  });
}
