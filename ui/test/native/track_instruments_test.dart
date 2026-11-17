import 'dart:io';

import 'package:boojy_audio/models/instrument_data.dart';
import 'package:boojy_audio/models/track_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/daw_harness.dart';
import 'support/native_engine_harness.dart';

void main() {
  // A track's sampler, drum kit or synth goes with it: Duplicate Track gives
  // the copy its own, and undoing Delete Track brings it back. Both used to
  // leave a silent track.
  if (!isNativeEngineAvailable) {
    const reason = 'native engine library not found — run ./build.sh first';
    if (isNativeEngineRequired) {
      test('native engine present (required under BOOJY_CI)', () {
        fail('$reason. Refusing to report a vacuous green suite (C92).');
      });
    } else {
      test('Track instruments (native engine)', () {}, skip: reason);
    }
    return;
  }

  testWidgets('Duplicate Track copies the instrument, and undoing Delete Track '
      'brings it back', (tester) async {
    final h = await DawHarness.start(tester);
    TrackData track(int id) => TrackData.fromCSV(h.engine.getTrackInfo(id))!;
    bool padsLoaded(int id) {
      final pads = h.engine.getDrumKitInfo(id)?.pads ?? const [];
      return pads.length == 2 && pads.every((p) => p.hasSample);
    }

    try {
      final lead = h.writeClickWav('lead.wav');
      final kick = h.writeClickWav('kick.wav', seconds: 0.5);

      final sampler = h.engine.createTrack('midi', 'Sampler');
      h.engine.createSamplerForTrack(sampler);
      expect(h.engine.loadSampleForTrack(sampler, lead, 60), isTrue);
      final drums = h.engine.createTrack('midi', 'Drums');
      h.engine.createDrumKitForTrack(drums);
      for (final note in [36, 38]) {
        final pad = h.engine.addDrumPad(drums, note);
        expect(h.engine.loadDrumPadSample(drums, pad, kick), isTrue);
      }
      final synth = h.engine.createTrack('midi', 'Synth');
      h.daw.trackController.setTrackInstrument(
        synth,
        InstrumentData.defaultSynthesizer(
          synth,
        ).copyWith(parameters: {'filter_cutoff': 0.25}),
      );
      await h.settle();

      // Duplicate Track: each copy has its own instrument.
      final before = h.engine.getAllTrackIds().toSet();
      await h.daw.onDuplicateTrackRequested(track(sampler));
      final samplerCopy = h.engine.getAllTrackIds().toSet().difference(before);
      await h.daw.onDuplicateTrackRequested(track(drums));
      await h.settle();
      final drumsCopy = h.engine
          .getAllTrackIds()
          .toSet()
          .difference(before)
          .difference(samplerCopy);
      expect(h.engine.isSamplerTrack(samplerCopy.single), isTrue);
      expect(h.engine.getSamplerSamplePath(samplerCopy.single), lead);
      expect(h.engine.isDrumKitTrack(drumsCopy.single), isTrue);
      expect(padsLoaded(drumsCopy.single), isTrue);

      // The sample files go: undo must not need to read them again.
      File(lead).deleteSync();
      File(kick).deleteSync();

      // Delete Track, then undo: the instrument is back as it was.
      for (final id in [sampler, drums, synth]) {
        await h.daw.onDeleteTrackRequested(track(id));
        await h.settle();
      }
      expect(h.daw.trackController.getTrackInstrument(synth), isNull);
      for (var i = 0; i < 3; i++) {
        await h.daw.performUndo();
        await h.settle();
      }
      expect(h.engine.isSamplerTrack(sampler), isTrue);
      expect(h.engine.getSamplerSamplePath(sampler), lead);
      expect(padsLoaded(drums), isTrue);
      final restored = h.daw.trackController.getTrackInstrument(synth);
      expect(restored?.type, 'synthesizer');
      expect(restored?.parameters['filter_cutoff'], 0.25);

      // Redo the deletes and undo them again: still there.
      for (var i = 0; i < 3; i++) {
        await h.daw.performRedo();
        await h.settle();
      }
      expect(h.engine.isSamplerTrack(sampler), isFalse);
      for (var i = 0; i < 3; i++) {
        await h.daw.performUndo();
        await h.settle();
      }
      expect(h.engine.getSamplerSamplePath(sampler), lead);
      expect(padsLoaded(drums), isTrue);
      expect(h.daw.trackController.getTrackInstrument(synth), isNotNull);
      h.expectScreenMatchesEngine(after: 'undoing the deletes twice');
    } finally {
      await h.close();
    }
  });
}
