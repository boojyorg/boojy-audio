import 'package:flutter/material.dart';

/// Placement of the tour tooltip relative to the spotlight target
enum TourPlacement { below, above, left, right }

/// Immutable data class describing one step in the guided tour
class TourStep {
  final String title;
  final String description;
  final GlobalKey? targetKey; // null = centered on screen (no spotlight)
  final TourPlacement placement;

  const TourStep({
    required this.title,
    required this.description,
    this.targetKey,
    this.placement = TourPlacement.below,
  });
}
