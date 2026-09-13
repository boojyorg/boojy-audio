import 'package:flutter/material.dart';
import '../../../theme/theme_extension.dart';
import '../../../theme/tokens.dart';

/// Horizontally scrolling wrapper for an editor's ruler (nav bar), with an
/// optional pinned orientation chip at the left edge.
///
/// Zooming is a ruler gesture (drag vertically / scroll wheel), so there are
/// no zoom buttons here. Used by the arrangement, piano roll, audio editor
/// and sampler for consistent behaviour.
class ScrollableNavBar extends StatelessWidget {
  /// The nav bar content (e.g., UnifiedNavBar)
  final Widget child;

  /// Controller for horizontal scrolling of the nav bar
  final ScrollController scrollController;

  /// Height of the nav bar (default 24.0)
  final double height;

  /// Horizontal zoom (px per beat). When provided together with [beatsPerBar],
  /// a pinned "orientation chip" shows the bar at the left edge once the ruler
  /// is scrolled past bar 1. Leave null on editors that don't want the chip
  /// (e.g. the piano roll).
  final double? pixelsPerBeat;

  /// Time-signature numerator, paired with [pixelsPerBeat] for the chip.
  final int? beatsPerBar;

  const ScrollableNavBar({
    super.key,
    required this.child,
    required this.scrollController,
    this.height = 24.0,
    this.pixelsPerBeat,
    this.beatsPerBar,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity, // Fill available width
      child: Stack(
        children: [
          // Full-width scrollable nav bar
          SingleChildScrollView(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: child,
          ),
          // Orientation chip: the bar at the left edge, pinned (non-scrolling),
          // shown once scrolled past bar 1. Opt-in via pixelsPerBeat/beatsPerBar.
          if (pixelsPerBeat != null && beatsPerBar != null)
            _buildOrientationChip(context),
        ],
      ),
    );
  }

  /// A small pinned LCD showing the bar at the left edge of the scrolled
  /// viewport — a "where am I in the song" cue. Repaints on scroll via the
  /// shared [scrollController]; hidden until you scroll past bar 1.
  Widget _buildOrientationChip(BuildContext context) {
    final ppb = pixelsPerBeat!;
    final bpb = beatsPerBar!;
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: scrollController,
          builder: (context, _) {
            final offset = scrollController.hasClients
                ? scrollController.offset
                : 0.0;
            // Bar containing the left edge of the viewport (1-indexed).
            final leftBar = (ppb > 0 && bpb > 0)
                ? (offset / ppb / bpb).floor() + 1
                : 1;
            if (leftBar <= 1) return const SizedBox.shrink();
            final colors = context.colors;
            return Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: colors.dark,
                border: Border(
                  right: BorderSide(color: colors.accent, width: 1.5),
                ),
              ),
              child: Text(
                '$leftBar',
                style: BT.label(colors.textPrimary, weight: BT.weightSemiBold),
              ),
            );
          },
        ),
      ),
    );
  }
}
