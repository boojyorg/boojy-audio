import 'package:flutter/material.dart';

/// Standardized animation timing and values for consistent UI feel.
/// Use these constants across all buttons and interactive elements.
class AnimationConstants {
  AnimationConstants._();

  // ============================================
  // DURATIONS
  // ============================================

  /// Standard hover transition duration (background color changes)
  static const Duration hoverDuration = Duration(milliseconds: 100);

  /// Standard press transition duration (scale changes)
  static const Duration pressDuration = Duration(milliseconds: 150);

  /// Fast transition for small, subtle changes
  static const Duration fastDuration = Duration(milliseconds: 50);

  /// Slower transition for larger animations
  static const Duration slowDuration = Duration(milliseconds: 200);

  // ============================================
  // SCALE VALUES
  // ============================================

  /// Scale factor when element is hovered
  static const double hoverScale = 1.05;

  /// Subtle hover scale for less prominent elements
  static const double subtleHoverScale = 1.02;

  /// Scale factor when element is pressed
  static const double pressScale = 0.95;

  // ============================================
  // CURVES
  // ============================================

  /// Standard curve for hover/press animations
  static const Curve standardCurve = Curves.easeOutCubic;

  /// Curve for bounce-back effects
  static const Curve bounceCurve = Curves.elasticOut;

  // ============================================
  // OPACITY VALUES
  // ============================================

  /// Background opacity for hovered state
  static const double hoverBgOpacity = 0.3;

  /// Background opacity for default state
  static const double defaultBgOpacity = 0.2;

  /// Divider line opacity
  static const double dividerOpacity = 0.2;

  /// Disabled element opacity
  static const double disabledOpacity = 0.3;

  // ============================================
  // GLOW / SHADOW
  // ============================================

  /// Glow opacity for active+hovered elements
  static const double glowOpacity = 0.3;

  /// Glow blur radius
  static const double glowBlurRadius = 8.0;

  /// Glow spread radius
  static const double glowSpreadRadius = 1.0;
}
