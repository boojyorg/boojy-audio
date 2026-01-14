import 'package:flutter/material.dart';
import '../../theme/animation_constants.dart';

/// Mixin providing common hover and press state tracking for buttons.
///
/// Usage:
/// ```dart
/// class _MyButtonState extends State<MyButton> with ButtonHoverMixin {
///   @override
///   Widget build(BuildContext context) {
///     return MouseRegion(
///       onEnter: handleHoverEnter,
///       onExit: handleHoverExit,
///       child: GestureDetector(
///         onTapDown: handleTapDown,
///         onTapUp: handleTapUp,
///         onTapCancel: handleTapCancel,
///         child: AnimatedScale(
///           scale: scale,
///           duration: AnimationConstants.pressDuration,
///           child: ...
///         ),
///       ),
///     );
///   }
/// }
/// ```
mixin ButtonHoverMixin<T extends StatefulWidget> on State<T> {
  /// Whether the pointer is currently hovering over this button
  bool isHovered = false;

  /// Whether this button is currently being pressed
  bool isPressed = false;

  /// Computed scale factor based on hover/press state.
  /// Uses [hoverScale] and [pressScale] which can be overridden.
  double get scale {
    if (isPressed) return pressScale;
    if (isHovered) return hoverScale;
    return 1.0;
  }

  /// Scale factor when hovered (override to customize)
  double get hoverScale => AnimationConstants.hoverScale;

  /// Scale factor when pressed (override to customize)
  double get pressScale => AnimationConstants.pressScale;

  /// Call this from MouseRegion.onEnter
  void handleHoverEnter(PointerEvent _) {
    setState(() => isHovered = true);
  }

  /// Call this from MouseRegion.onExit
  void handleHoverExit(PointerEvent _) {
    setState(() => isHovered = false);
  }

  /// Call this from GestureDetector.onTapDown
  void handleTapDown(TapDownDetails _) {
    setState(() => isPressed = true);
  }

  /// Call this from GestureDetector.onTapUp
  void handleTapUp(TapUpDetails _) {
    setState(() => isPressed = false);
  }

  /// Call this from GestureDetector.onTapCancel
  void handleTapCancel() {
    setState(() => isPressed = false);
  }

  /// Reset both hover and press states
  void resetButtonState() {
    setState(() {
      isHovered = false;
      isPressed = false;
    });
  }
}

/// Mixin for buttons with separate hover zones (e.g., split buttons).
///
/// Tracks hover state for two independent zones: label and dropdown.
mixin SplitButtonHoverMixin<T extends StatefulWidget> on State<T> {
  /// Whether hovering over the label/primary action zone
  bool isLabelHovered = false;

  /// Whether hovering over the dropdown/secondary zone
  bool isDropdownHovered = false;

  /// Whether either zone is hovered
  bool get isAnyHovered => isLabelHovered || isDropdownHovered;

  /// Call this from label MouseRegion.onEnter
  void handleLabelHoverEnter(PointerEvent _) {
    setState(() => isLabelHovered = true);
  }

  /// Call this from label MouseRegion.onExit
  void handleLabelHoverExit(PointerEvent _) {
    setState(() => isLabelHovered = false);
  }

  /// Call this from dropdown MouseRegion.onEnter
  void handleDropdownHoverEnter(PointerEvent _) {
    setState(() => isDropdownHovered = true);
  }

  /// Call this from dropdown MouseRegion.onExit
  void handleDropdownHoverExit(PointerEvent _) {
    setState(() => isDropdownHovered = false);
  }

  /// Reset all hover states
  void resetSplitHoverState() {
    setState(() {
      isLabelHovered = false;
      isDropdownHovered = false;
    });
  }
}
