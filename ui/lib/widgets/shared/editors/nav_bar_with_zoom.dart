import 'package:flutter/material.dart';
import '../../../theme/boojy_icons.dart';
import '../../../theme/theme_extension.dart';
import '../../../theme/tokens.dart';
import 'zoom_button.dart';

/// A wrapper widget that combines a nav bar with zoom controls.
/// The nav bar is horizontally scrollable, and zoom controls are
/// overlaid at the right edge (no background, transparent).
///
/// Used by both Piano Roll and Arrangement views for consistent behavior.
class NavBarWithZoom extends StatelessWidget {
  /// The nav bar content (e.g., UnifiedNavBar)
  final Widget child;

  /// Controller for horizontal scrolling of the nav bar
  final ScrollController scrollController;

  /// Callback when zoom in button is pressed
  final VoidCallback onZoomIn;

  /// Callback when zoom out button is pressed
  final VoidCallback onZoomOut;

  /// Height of the nav bar (default 24.0)
  final double height;

  /// Horizontal zoom (px per beat). When provided together with [beatsPerBar],
  /// a pinned "orientation chip" shows the bar at the left edge once the ruler
  /// is scrolled past bar 1. Leave null on editors that don't want the chip
  /// (e.g. the piano roll).
  final double? pixelsPerBeat;

  /// Time-signature numerator, paired with [pixelsPerBeat] for the chip.
  final int? beatsPerBar;

  const NavBarWithZoom({
    super.key,
    required this.child,
    required this.scrollController,
    required this.onZoomIn,
    required this.onZoomOut,
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
          // Zoom controls pinned at the right edge. Opaque backing (like the
          // orientation chip on the left) so scrolling bar numbers don't
          // collide with the buttons underneath them.
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: context.colors.dark,
                border: Border(left: BorderSide(color: context.colors.divider)),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ZoomButton(
                      icon: BI.remove,
                      tooltip: 'Zoom out',
                      onTap: onZoomOut,
                    ),
                    const SizedBox(width: 2),
                    ZoomButton(
                      icon: BI.add,
                      tooltip: 'Zoom in',
                      onTap: onZoomIn,
                    ),
                  ],
                ),
              ),
            ),
          ),
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
