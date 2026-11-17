import 'dart:convert';
import 'dart:io';

import 'package:boojy_audio/models/midi_note_data.dart';
import 'package:boojy_audio/models/track_data.dart';
import 'package:boojy_audio/services/commands/effect_commands.dart';
import 'package:boojy_audio/services/undo_redo_manager.dart';
import 'package:boojy_audio/state/ui_layout_state.dart';
import 'package:boojy_audio/widgets/device_chain/effect_data.dart';
import 'package:boojy_audio/widgets/library_panel.dart';
import 'package:boojy_audio/widgets/timeline_view.dart';
import 'package:boojy_audio/widgets/track_mixer_panel.dart';
import 'package:boojy_audio/widgets/transport_bar.dart';
import 'package:boojy_audio/widgets/transport_bar/count_in_toggle_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/daw_harness.dart';
import 'support/native_engine_harness.dart';
import 'support/workflow_helpers.dart';

// Workflow tests through the real DAW screen and engine (no window). Each
// does what Tyr does, through the methods the buttons call, and checks after
// every step that the screen shows what the engine plays. These are where
// the loop toggle and tempo-to-warp wiring bugs lived.
//
// This file holds the window, track and project workflows. The others are
// split by topic (daw_*_workflow_test.dart, daw_*_undo_test.dart,
// daw_stress_regressions_test.dart): the tests in one file run one after
// another while files run side by side, so one big file was the whole wait.

void main() {
  if (!isNativeEngineAvailable) {
    test('DAW workflows (native engine)', () {}, skip: true);
    return;
  }

  testWidgets('the Count-in button lights up and dims as it is clicked', (
    tester,
  ) async {
    final h = await DawHarness.start(tester);
    try {
      bool shownOn() => tester
          .widget<CountInToggleButton>(find.byType(CountInToggleButton))
          .isActive;

      expect(h.daw.userSettings.countInBars, 1);
      expect(shownOn(), isTrue, reason: 'on by default');

      await tester.tap(find.byType(CountInToggleButton));
      await h.settle();
      expect(h.daw.userSettings.countInBars, 0);
      expect(shownOn(), isFalse, reason: 'first click turns it off');

      await tester.tap(find.byType(CountInToggleButton));
      await h.settle();
      expect(h.daw.userSettings.countInBars, 1);
      expect(shownOn(), isTrue, reason: 'second click turns it back on');
    } finally {
      await h.close();
    }
  });

  testWidgets('a narrow window narrows both side panels and closes neither', (
    tester,
  ) async {
    final h = await DawHarness.start(tester);
    try {
      double drawn(Type panel) => tester.getSize(find.byType(panel)).width;
      h.daw.uiLayout.restoreLibraryWidths(60, 412); // 480
      h.daw.uiLayout.mixerPanelWidth = 480;
      await h.settle();
      expect(drawn(LibraryPanel), 480);
      expect(drawn(TrackMixerPanel), 480);

      // The smallest window: 960 - 340 timeline - 2 x 4 dividers = 306 each
      tester.view.physicalSize = const Size(960, 600);
      await h.settle();
      expect(h.daw.uiLayout.isLibraryPanelCollapsed, isFalse);
      expect(h.daw.uiLayout.isMixerVisible, isTrue);
      expect(drawn(LibraryPanel), 306);
      expect(drawn(TrackMixerPanel), 306);

      tester.view.physicalSize = const Size(1440, 900);
      await h.settle();
      expect(drawn(LibraryPanel), 480, reason: 'chosen width comes back');
      expect(drawn(TrackMixerPanel), 480);
    } finally {
      await h.close();
    }
  });

  testWidgets('hiding one squeezed panel never squeezes the timeline', (
    tester,
  ) async {
    final h = await DawHarness.start(tester);
    try {
      h.daw.uiLayout.restoreLibraryWidths(60, 412); // 480
      h.daw.uiLayout.mixerPanelWidth = 480;
      tester.view.physicalSize = const Size(960, 600); // both drawn at 306
      await h.settle();

      // Frame by frame through the slide: the panel that stays grows back
      // to 480 while the other closes, and they must share the window
      Future<void> slide(String tooltip) async {
        await tester.tap(find.byTooltip(tooltip));
        for (var ms = 0; ms <= 300; ms += 16) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            tester.getSize(find.byType(TimelineView)).width,
            greaterThanOrEqualTo(UILayoutState.minArrangementWidth),
            reason: '$tooltip, ${ms}ms in',
          );
        }
      }

      await slide('Hide Library');
      await slide('Show Library');
      await slide('Hide Mixer');
      await slide('Show Mixer');
    } finally {
      await h.close();
    }
  });

  testWidgets('a plugin window can close before its effect is freed', (
    tester,
  ) async {
    // Freed with its window up, a VST3's UI timers fire into freed memory
    // (deleting Serum 2 FX crashed). The engine wrapper calls
    // beforeEffectRemoved while the effect still exists, on every path that
    // frees one: removing it, and deleting its track.
    final h = await DawHarness.start(tester);
    final engine = h.engine;
    final previous = engine.beforeEffectRemoved;
    try {
      bool exists(int id) => engine.getEffectInfo(id).startsWith('type:');
      final stillThere = <int, bool>{};
      engine.beforeEffectRemoved = (id) => stillThere[id] = exists(id);

      final track = engine.createTrack('audio', 'Audio');
      final reverb = engine.addEffectToTrack(track, 'reverb');
      final delay = engine.addEffectToTrack(track, 'delay');
      expect(reverb, greaterThanOrEqualTo(0));

      engine.removeEffectFromTrack(track, reverb);
      expect(stillThere, {reverb: true}, reason: 'removing an effect');
      expect(exists(reverb), isFalse, reason: 'then it is freed');

      engine.deleteTrack(track);
      expect(stillThere[delay], isTrue, reason: 'deleting its track');
      expect(exists(delay), isFalse);
    } finally {
      engine.beforeEffectRemoved = previous;
      await h.close();
    }
  });

  testWidgets(
    'Duplicate Track copies audio and MIDI clips; undo removes them',
    (tester) async {
      final h = await DawHarness.start(tester);
      try {
        final audio = await dropClip(h, 'drums.wav');

        await tester.tap(find.text('MIDI').first);
        await h.settle();
        final manager = h.daw.midiPlaybackManager!;
        final midi = manager.midiClips.single;
        h.daw.midiClipController.updateClip(
          midi.copyWith(
            notes: [
              MidiNoteData(note: 60, velocity: 100, startTime: 0, duration: 1),
              MidiNoteData(note: 64, velocity: 100, startTime: 2, duration: 1),
            ],
          ),
          h.daw.playheadPosition,
        );
        await h.settle();
        h.expectScreenMatchesEngine(after: 'adding an audio and a MIDI track');

        TrackData track(int id) =>
            TrackData.fromCSV(h.engine.getTrackInfo(id))!;
        await h.daw.onDuplicateTrackRequested(track(audio.trackId));
        await h.daw.onDuplicateTrackRequested(track(midi.trackId));
        await h.settle();

        final clips = h.daw.timelineKey.currentState!.clips;
        expect(clips, hasLength(2), reason: 'the audio copy is on screen');
        expect(clips.map((c) => c.clipId).toSet(), hasLength(2));
        expect(manager.midiClips, hasLength(2), reason: 'the MIDI copy too');
        expect(manager.midiClips.last.notes, hasLength(2));
        h.expectScreenMatchesEngine(after: 'duplicating both tracks');

        await h.daw.undoRedoManager.undo();
        await h.daw.undoRedoManager.undo();
        await h.settle();
        expect(h.daw.timelineKey.currentState!.clips, hasLength(1));
        expect(manager.midiClips, hasLength(1));
        h.expectScreenMatchesEngine(after: 'undoing both duplicates');
      } finally {
        await h.close();
      }
    },
  );

  testWidgets('New Project starts at 120 BPM in 4/4, whatever came before', (
    tester,
  ) async {
    final h = await DawHarness.start(tester);
    TransportBar toolbar() => tester.widget(find.byType(TransportBar));
    try {
      await dropClip(h, 'loop.wav');
      await h.daw.onTempoChanged(174);
      await toolbar().onTimeSignatureChanged!(3, 4);
      await h.settle();
      expect(h.engine.getTempo(), 174);
      expect(toolbar().beatsPerBar, 3);

      h.daw.executeNewProject();
      await h.settle();

      expect(h.daw.tempo, 120, reason: 'the tempo box');
      expect(h.engine.getTempo(), 120, reason: 'what the engine plays at');
      expect(h.daw.projectMetadata.bpm, 120, reason: 'what Save would write');
      expect(toolbar().beatsPerBar, 4);
      expect(h.daw.projectMetadata.timeSignatureDenominator, 4);
      expect(h.daw.timelineKey.currentState!.clips, isEmpty);
      expect(h.daw.undoRedoManager.canUndo, isFalse);
      h.expectScreenMatchesEngine(after: 'New Project');
    } finally {
      await h.close();
    }
  });

  testWidgets('Mute Clip silences a MIDI clip, in export too, and keeps its '
      'notes', (tester) async {
    final h = await DawHarness.start(tester);
    try {
      final timeline = h.daw.timelineKey.currentState!;
      final manager = h.daw.midiPlaybackManager!;
      // Whether an export of the project has any sound in it.
      var exports = 0;
      Future<bool> exportIsAudible() async {
        final out = '${h.tempDir.path}/export${exports++}.wav';
        await h.realTime(() => h.engine.exportWavWithOptions(outputPath: out));
        final bytes = File(out).readAsBytesSync();
        final data = ascii.decode(bytes.sublist(0, 200), allowInvalid: true);
        return bytes.skip(data.indexOf('data') + 8).any((b) => b != 0);
      }

      await tester.tap(find.text('MIDI').first);
      await h.settle();
      h.engine.setTrackInstrument(manager.midiClips.single.trackId, 'synth');
      h.daw.midiClipController.updateClip(
        manager.midiClips.single.copyWith(
          notes: [
            MidiNoteData(note: 60, velocity: 100, startTime: 0, duration: 1),
            MidiNoteData(note: 64, velocity: 100, startTime: 2, duration: 1),
          ],
        ),
        h.daw.playheadPosition,
      );
      await h.settle();
      expect(await exportIsAudible(), isTrue, reason: 'before muting');

      await timeline.toggleMidiClipMute(manager.midiClips.single);
      await h.settle();
      expect(manager.midiClips.single.isMuted, isTrue);
      h.expectScreenMatchesEngine(after: 'Mute Clip');
      expect(await exportIsAudible(), isFalse, reason: 'muted');

      await h.daw.undoRedoManager.undo();
      await h.settle();
      expect(manager.midiClips.single.isMuted, isFalse);
      h.expectScreenMatchesEngine(after: 'undoing Mute Clip');
      expect(await exportIsAudible(), isTrue, reason: 'mute undone');
      await h.daw.undoRedoManager.redo();
      await h.settle();
      h.expectScreenMatchesEngine(after: 'redoing Mute Clip');

      // Saved while muted: the notes are still there when it reopens.
      final path = '${h.tempDir.path}/Muted.audio';
      await h.realTime(() => h.daw.saveProjectToPath(path));
      await h.settleUntil(() => !h.daw.isLoading, what: 'the save');
      h.daw.executeNewProject();
      await h.settle();
      await h.realTime(() => h.daw.openRecentProject(path));
      await h.settleUntil(
        () => h.daw.midiPlaybackManager!.midiClips.length == 1,
        what: 'the reopened project to show its clip',
      );
      await h.settle();
      final reopened = h.daw.midiPlaybackManager!.midiClips.single;
      expect(reopened.isMuted, isTrue);
      expect(reopened.notes.map((n) => n.note), [60, 64]);
      h.expectScreenMatchesEngine(after: 'reopening');
      expect(await exportIsAudible(), isFalse, reason: 'reopened muted');

      await timeline.toggleMidiClipMute(reopened);
      await h.settle();
      h.expectScreenMatchesEngine(after: 'unmuting');
      expect(await exportIsAudible(), isTrue, reason: 'unmuted');
    } finally {
      await h.close();
    }
  });

  testWidgets('a muted clip reopens muted even if the layout file is lost', (
    tester,
  ) async {
    // The engine saves mute beside the notes. The screen's own file (names,
    // colours) can be missing, as in a backup whose layout write failed.
    final h = await DawHarness.start(tester);
    try {
      await tester.tap(find.text('MIDI').first);
      await h.settle();
      final manager = h.daw.midiPlaybackManager!;
      h.daw.midiClipController.updateClip(
        manager.midiClips.single.copyWith(
          notes: [
            MidiNoteData(note: 60, velocity: 100, startTime: 0, duration: 1),
          ],
        ),
        h.daw.playheadPosition,
      );
      await h.daw.timelineKey.currentState!.toggleMidiClipMute(
        manager.midiClips.single,
      );
      await h.settle();

      final path = '${h.tempDir.path}/NoLayout.audio';
      await h.realTime(() => h.daw.saveProjectToPath(path));
      await h.settleUntil(() => !h.daw.isLoading, what: 'the save');
      File('$path/ui_layout.json').deleteSync();
      h.daw.executeNewProject();
      await h.settle();
      await h.realTime(() => h.daw.openRecentProject(path));
      await h.settleUntil(
        () => h.daw.midiPlaybackManager!.midiClips.length == 1,
        what: 'the reopened project to show its clip',
      );
      await h.settle();

      expect(h.daw.midiPlaybackManager!.midiClips.single.isMuted, isTrue);
      h.expectScreenMatchesEngine(after: 'reopening without the layout file');
    } finally {
      await h.close();
    }
  });

  testWidgets('a note inside another of the same pitch matches the engine', (
    tester,
  ) async {
    final h = await DawHarness.start(tester);
    try {
      await tester.tap(find.text('MIDI').first);
      await h.settle();
      h.daw.midiClipController.updateClip(
        h.daw.midiPlaybackManager!.midiClips.single.copyWith(
          notes: [
            MidiNoteData(note: 60, velocity: 100, startTime: 0, duration: 4),
            MidiNoteData(note: 60, velocity: 90, startTime: 1, duration: 1),
          ],
        ),
        h.daw.playheadPosition,
      );
      await h.settle();
      h.expectScreenMatchesEngine(after: 'drawing a note inside another');
    } finally {
      await h.close();
    }
  });

  testWidgets('a deleted EQ comes back with its bands and settings on undo', (
    tester,
  ) async {
    final h = await DawHarness.start(tester);
    try {
      final engine = h.engine;
      final trackId = engine.createTrack('audio', 'FX');
      Map<String, double> settings(int effectId) => EffectData.fromInfo(
        effectId,
        engine.getEffectInfo(effectId),
      )!.parameters;
      int bands(int effectId) => settings(effectId)['band_count']!.round();

      // A new EQ has three bands: check one with more and one with fewer.
      for (final wanted in [4, 2]) {
        final eq = engine.addEffectToTrack(trackId, 'eq');
        while (bands(eq) < wanted) {
          engine.addEqBand(eq);
        }
        while (bands(eq) > wanted) {
          engine.removeEqBand(eq, bands(eq) - 1);
        }
        engine.setEffectParameter(eq, 'band_1_freq', 1234);
        engine.setEffectParameter(eq, 'band_1_gain', -6);
        final before = settings(eq);

        await UndoRedoManager().execute(
          RemoveEffectCommand(
            trackId: trackId,
            trackName: 'FX',
            effectId: eq,
            effectName: 'EQ',
            effectType: 'eq',
            isVst3: false,
            effectIndex: 0,
          ),
        );
        await h.daw.performUndo();
        await h.settle();

        final restored = int.parse(engine.getTrackEffects(trackId));
        expect(settings(restored), before, reason: '$wanted bands');
        engine.removeEffectFromTrack(trackId, restored);
      }
    } finally {
      await h.close();
    }
  });
}
