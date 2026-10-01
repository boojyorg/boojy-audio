import 'dart:ui' as ui;

import 'package:boojy_audio/widgets/timeline/painters/waveform_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void paintPeaks(List<double> peaks, Size size, {double? duration}) {
  final recorder = ui.PictureRecorder();
  WaveformPainter(
    peaks: peaks,
    color: Colors.white,
    contentDuration: duration,
  ).paint(Canvas(recorder), size);
  recorder.endRecording();
}

List<double> pairs(int count) => [
  for (var i = 0; i < count; i++) ...[-0.5, 0.5],
];

void main() {
  testWidgets('already-recorded audio keeps its shape as a live clip grows', (
    tester,
  ) async {
    // Live peaks are 2 per pixel at the default zoom. Adding one peak (an
    // odd count, so the last merged group is half full) used to respace the
    // whole waveform, so old audio looked like it changed volume.
    await tester.runAsync(() async {
      final before = await columnHeights(1000, 0.5);
      final after = await columnHeights(1001, 0.5);
      expect(after.sublist(0, 450), before.sublist(0, 450));
    });
  });

  test(
    "a clip with fewer than 100 peaks paints (a live take's first second)",
    () {
      // Threw "Invalid argument(s): 100" from clamp(100, 50).
      expect(
        () => paintPeaks(pairs(50), const Size(25, 40), duration: 0.5),
        returnsNormally,
      );
    },
  );

  test('a growing live clip keeps one group size (no flicker)', () {
    // Live peaks arrive 100/s; at the default zoom (50 px/s) that is exactly
    // 2 per pixel. The old rule flipped between 1 and 2 as the count grew.
    final sizes = <int>{};
    for (var count = 200; count < 1200; count++) {
      final width = count / 100 * 50;
      sizes.add(WaveformPainter.lodGroupSize(count, width));
    }
    expect(sizes, {2});
  });

  test('group size follows peaks per pixel', () {
    expect(WaveformPainter.lodGroupSize(1000, 1000), 1);
    expect(WaveformPainter.lodGroupSize(1999, 1000), 1);
    expect(WaveformPainter.lodGroupSize(8000, 1000), 8);
    // Narrow clips still draw at least 100 peaks.
    expect(WaveformPainter.lodGroupSize(1000, 20), 10);
    expect(WaveformPainter.lodGroupSize(50, 20), 1);
    expect(WaveformPainter.lodGroupSize(0, 100), 1);
  });
}

Future<List<int>> columnHeights(int peakCount, double pxPerPeak) async {
  // Deterministic "noisy" peaks, so neighbouring peaks differ like real audio.
  final peaks = <double>[];
  for (var i = 0; i < peakCount; i++) {
    final v = 0.2 + 0.7 * ((i * 7919) % 101) / 100;
    peaks
      ..add(-v)
      ..add(v);
  }
  final width = (peakCount * pxPerPeak).ceilToDouble();
  const height = 40.0;
  final recorder = ui.PictureRecorder();
  WaveformPainter(
    peaks: peaks,
    color: Colors.white,
    contentDuration: peakCount / 100,
  ).paint(Canvas(recorder), Size(peakCount * pxPerPeak, height));
  final image = await recorder.endRecording().toImage(
    width.toInt(),
    height.toInt(),
  );
  final bytes = (await image.toByteData())!.buffer.asUint8List();
  // Lit pixels per column (alpha > 128): how tall the waveform is there.
  return [
    for (var x = 0; x < image.width; x++)
      [
        for (var y = 0; y < image.height; y++)
          if (bytes[(y * image.width + x) * 4 + 3] > 128) 1,
      ].length,
  ];
}
