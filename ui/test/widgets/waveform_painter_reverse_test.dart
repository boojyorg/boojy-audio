import 'dart:ui' as ui;

import 'package:boojy_audio/widgets/timeline/painters/waveform_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 2 s clip whose waveform grows steadily louder: 200 points, 0.05 → 1.0.
final _ramp = [
  for (var i = 0; i < 200; i++) ...[
    -(0.05 + i * 0.95 / 199),
    0.05 + i * 0.95 / 199,
  ],
];

/// Lit pixels per column (how tall the waveform is there), 200 × 40 px.
Future<List<int>> _heights({
  bool reversed = false,
  double startOffset = 0,
  double? visibleDuration,
}) async {
  const size = Size(200, 40);
  final recorder = ui.PictureRecorder();
  WaveformPainter(
    peaks: _ramp,
    color: Colors.white,
    contentDuration: 2.0,
    startOffset: startOffset,
    visibleDuration: visibleDuration,
    reversed: reversed,
  ).paint(Canvas(recorder), size);
  final image = await recorder.endRecording().toImage(200, 40);
  final bytes = (await image.toByteData())!.buffer.asUint8List();
  return [
    for (var x = 0; x < 200; x++)
      [
        for (var y = 0; y < 40; y++)
          if (bytes[(y * 200 + x) * 4 + 3] > 128) 1,
      ].length,
  ];
}

void main() {
  // The engine played reversed clips backwards but the arrangement drew
  // them forwards (only the audio editor flipped its waveform).
  testWidgets('a reversed clip draws its waveform backwards', (tester) async {
    await tester.runAsync(() async {
      final forward = await _heights();
      final backward = await _heights(reversed: true);
      expect(forward.first, lessThan(forward.last));
      expect(backward.first, greaterThan(backward.last));
      expect(backward.first, forward.last);
    });
  });

  testWidgets('a trimmed reversed clip flips only its visible part', (
    tester,
  ) async {
    // Trimmed to the second half (1–2 s, the louder half), as the engine
    // reverses the trimmed window: loudest at the left, the middle at right.
    await tester.runAsync(() async {
      final window = await _heights(startOffset: 1, visibleDuration: 1);
      final flipped = await _heights(
        startOffset: 1,
        visibleDuration: 1,
        reversed: true,
      );
      expect(flipped.first, window.last);
      expect(flipped.last, window.first);
    });
  });

  test("reversing keeps each point's pair together", () {
    expect(WaveformPainter.reversePeakPairs([-1, 1, -2, 2, -3, 3]), [
      -3,
      3,
      -2,
      2,
      -1,
      1,
    ]);
  });
}
