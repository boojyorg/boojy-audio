import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:boojy_audio/widgets/export_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/daw_harness.dart';
import 'support/native_engine_harness.dart';
import 'support/workflow_helpers.dart';

// Export workflows through the real DAW screen and engine (see
// daw_workflow_test.dart).

void main() {
  if (skipWithoutNativeEngine('DAW export workflows')) return;

  testWidgets('export writes a repeating clip and reads back the result', (
    tester,
  ) async {
    // Found by Tyr: every export said "Couldn't export" although the file was
    // written (the screen read 'format', the engine sends
    // 'format_description').
    final h = await DawHarness.start(tester);
    try {
      final clip = await dropClip(h, 'loop.wav');
      h.engine.setClipDuration(clip.trackId, clip.clipId, clip.duration * 2);
      final out = '${Directory.systemTemp.createTempSync('export').path}/a.wav';
      var json = '';
      await h.realTime(() async {
        json = await h.engine.exportWavWithOptions(outputPath: out);
      });
      final result = ExportResult.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      expect(result.format, 'WAV 16-bit');
      expect(File(out).existsSync(), isTrue);
      // Two passes of the loop plus the one-second tail.
      expect(result.duration, closeTo(clip.duration * 2 + 1, 0.01));
    } finally {
      await h.close();
    }
  });

  testWidgets('stems export from the dialog, one file per track, even with '
      'two tracks of the same name', (tester) async {
    // Found by Tyr: every stem export said "Couldn't export". The dialog left
    // a setting out of the options the engine reads, and read the engine's
    // list of stems as if it were a single total.
    final h = await DawHarness.start(tester);
    try {
      final first = await dropClip(h, 'kick.wav');
      final second = await dropClip(h, 'snare.wav');
      expect(second.trackId, isNot(first.trackId));
      h.engine.setTrackName(first.trackId, 'Drums');
      h.engine.setTrackName(second.trackId, 'Drums');

      // Through the export window's own code (`runExport`), with its
      // settings as they are when Stems is switched on.
      final folder = '${h.tempDir.path}/stems';
      var results = <ExportResult>[];
      await h.realTime(() async {
        results = await runExport(
          h.engine,
          ExportOptions(
            exportMp3: false,
            exportWav: true,
            exportStems: true,
            stemTracks: stemTracksFromEngine(h.engine),
          ),
          baseName: 'Song',
          folderPath: folder,
        );
      });
      final result = results.single;

      final files = Directory(folder).listSync().cast<File>();
      expect(files.map((f) => f.uri.pathSegments.last).toList()..sort(), [
        'Song - Drums 2.wav',
        'Song - Drums.wav',
      ]);
      expect(result.format, '2 stems (WAV)');
      expect(result.path, folder);
      expect(result.fileSize, files.fold<int>(0, (n, f) => n + f.lengthSync()));
    } finally {
      await h.close();
    }
  });

  testWidgets('the app keeps running and talking to the engine during export', (
    tester,
  ) async {
    // Found by Tyr: export froze the window and its progress bar never
    // moved, because the export ran on the UI thread and held the engine.
    final h = await DawHarness.start(tester);
    try {
      final clip = await dropClip(h, 'loop.wav');
      h.engine.setClipDuration(clip.trackId, clip.clipId, 120); // 2 minutes
      final out = '${Directory.systemTemp.createTempSync('export').path}/a.wav';
      final progress = <int>{};
      var ticks = 0;
      var slowestCall = Duration.zero;
      await h.realTime(() async {
        h.engine.resetExportProgress();
        final export = h.engine.exportWavWithOptions(outputPath: out);
        final timer = Timer.periodic(const Duration(milliseconds: 2), (_) {
          ticks++;
          final watch = Stopwatch()..start();
          h.engine.getPlayheadPosition(); // any engine call, like a meter
          final info = ExportProgressInfo.fromJson(
            jsonDecode(h.engine.getExportProgress()) as Map<String, dynamic>,
          );
          if (watch.elapsed > slowestCall) slowestCall = watch.elapsed;
          progress.add(info.progress.round());
        });
        await export;
        timer.cancel();
      });
      expect(File(out).existsSync(), isTrue);
      expect(ticks, greaterThan(5), reason: 'the UI thread ran meanwhile');
      // Generous for slow CI machines: the old freeze held each call for
      // the whole render (and the ticks above caught it at 1).
      expect(
        slowestCall,
        lessThan(const Duration(milliseconds: 250)),
        reason: 'engine calls did not wait for the render',
      );
      expect(
        progress.where((p) => p > 20 && p < 70),
        hasLength(greaterThanOrEqualTo(3)),
        reason: 'the bar moves through the render: $progress',
      );
    } finally {
      await h.close();
    }
  });

  testWidgets('Play and Record wait while an export runs', (tester) async {
    final h = await DawHarness.start(tester);
    try {
      await dropClip(h, 'loop.wav');
      final exportDone = Completer<void>();
      showDialog<void>(
        context: h.daw.context,
        builder: (_) => ExportProgressDialog(
          audioEngine: h.engine,
          exportTask: () => exportDone.future,
          onCancel: () {},
        ),
      );
      await h.settle();
      expect(ExportProgressDialog.isExporting, isTrue);

      h.daw.togglePlayPause();
      h.daw.startRecording();
      await h.settle();
      expect(h.daw.isPlaying, isFalse, reason: 'Play waits for the export');
      expect(h.daw.isRecording || h.daw.isCountingIn, isFalse);

      exportDone.complete();
      await h.settle();
      expect(ExportProgressDialog.isExporting, isFalse);
      h.daw.togglePlayPause();
      await h.settle();
      expect(h.daw.isPlaying, isTrue, reason: 'Play works again after');
      h.daw.stopPlayback();
      await h.settle();
    } finally {
      await h.close();
    }
  });
}
