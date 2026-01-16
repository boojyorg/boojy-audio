import 'package:flutter/material.dart';
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

  const NavBarWithZoom({
    super.key,
    required this.child,
    required this.scrollController,
    required this.onZoomIn,
    required this.onZoomOut,
    this.height = 24.0,
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
          // Zoom controls overlaid at right edge (no background)
          Positioned(
            right: 4,
            top: 0,
            bottom: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ZoomButton(
                    icon: Icons.remove,
                    tooltip: 'Zoom out',
                    onTap: onZoomOut,
                  ),
                  const SizedBox(width: 2),
                  ZoomButton(
                    icon: Icons.add,
                    tooltip: 'Zoom in',
                    onTap: onZoomIn,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
