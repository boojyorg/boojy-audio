import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The one zoom implementation shared by the arrangement, the piano roll and
/// the audio editor: how a ruler drag maps to a zoom ratio, and how to change
/// zoom and scroll together so the beat under the pointer stays put.
///
/// Every editor keeps its own zoom state and scroll controllers (the piano
/// roll and audio editor have a ruler controller mirrored from the grid), so
/// this is a set of functions rather than a widget: the maths lives here,
/// the editors call it.

/// Vertical ruler-drag travel that doubles (or halves) the zoom.
const double kRulerDragPixelsPerDoubling = 100.0;

/// Zoom ratio for [deltaY] pixels of vertical ruler drag, down positive.
///
/// Exponential, so equal travel is an equal ratio in both directions and a
/// round trip lands back on the zoom it started from (a linear per-event
/// factor drifted: ×0.95 then ×1.05 is not 1). Drag down = zoom in, matching
/// Ableton's beat-time ruler.
double rulerDragZoomFactor(double deltaY) =>
    math.pow(2.0, deltaY / kRulerDragPixelsPerDoubling).toDouble();

/// The scroll offset at which [anchorBeat] sits [anchorViewportX] pixels from
/// the left edge of the viewport once the zoom is [pixelsPerBeat].
double anchoredScrollOffset({
  required double anchorBeat,
  required double anchorViewportX,
  required double pixelsPerBeat,
}) => anchorBeat * pixelsPerBeat - anchorViewportX;

/// Scroll every controller in [controllers] to [offset] in the same frame as
/// a zoom change whose new content width is [contentWidth].
///
/// Call this right after setting the new zoom (inside or after `setState`),
/// never in a post-frame callback: a correction one frame late paints the
/// new zoom against the old scroll for a frame, which is the wobble the
/// editors used to have.
///
/// A plain `jumpTo` is not enough on its own. The controller still holds the
/// pre-zoom scroll extent until the viewport lays out, so a target past that
/// extent (zooming in near the end of the content) counts as out of range and
/// starts a spring-back animation. Telling the position its post-zoom extent
/// first keeps the jump in range; the viewport's own layout then reports the
/// same numbers and nothing moves twice. Controllers without a viewport yet
/// are skipped.
void applyZoomScroll({
  required Iterable<ScrollController> controllers,
  required double offset,
  required double contentWidth,
}) {
  for (final controller in controllers) {
    if (!controller.hasClients) continue;
    final position = controller.position;
    if (!position.hasViewportDimension) continue;
    final maxExtent = math.max(0.0, contentWidth - position.viewportDimension);
    position.applyContentDimensions(0.0, maxExtent);
    controller.jumpTo(offset.clamp(0.0, maxExtent));
  }
}
