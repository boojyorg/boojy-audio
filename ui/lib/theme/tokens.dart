import 'package:flutter/material.dart';

/// Boojy Design Tokens — the single source of truth for spacing, radius,
/// opacity, and typography values across the entire app.
///
/// Usage:
///   Spacing:   SizedBox(width: BT.sm)
///   Padding:   EdgeInsets.all(BT.md)
///   Radius:    BorderRadius.circular(BT.radiusSm)
///   Opacity:   color.withValues(alpha: BT.opacityLight)
///   Text:      style: BT.label(context)
///
/// `BT` is a short alias for `BoojyTokens` — use it everywhere.
typedef BT = BoojyTokens;

class BoojyTokens {
  BoojyTokens._();

  // ============================================
  // SPACING (margins, padding, gaps)
  // ============================================

  /// 2px — hairline gaps, icon-to-icon within tight groups
  static const double xxs = 2.0;

  /// 4px — icon-to-label gap, button internal padding (compact)
  static const double xs = 4.0;

  /// 8px — standard gap between elements, button internal padding
  static const double sm = 8.0;

  /// 12px — gap between button groups, section spacing
  static const double md = 12.0;

  /// 16px — panel padding, large section spacing
  static const double lg = 16.0;

  /// 24px — major section dividers, dialog padding
  static const double xl = 24.0;

  // ============================================
  // BORDER RADIUS
  // ============================================

  /// 2px — buttons, pills, small interactive elements
  static const double radiusSm = 2.0;

  /// 4px — inputs, dropdowns, cards
  static const double radiusMd = 4.0;

  /// 8px — dialogs, overlays, large containers
  static const double radiusLg = 8.0;

  /// Pre-built BorderRadius for convenience
  static final BorderRadius borderSm = BorderRadius.circular(radiusSm);
  static final BorderRadius borderMd = BorderRadius.circular(radiusMd);
  static final BorderRadius borderLg = BorderRadius.circular(radiusLg);

  // ============================================
  // OPACITY (for color.withValues(alpha: ...))
  // ============================================

  /// 0.08 — subtle tint (inactive hover background)
  static const double opacitySubtle = 0.08;

  /// 0.15 — light tint (active button background)
  static const double opacityLight = 0.15;

  /// 0.30 — medium tint (active button border, dividers)
  static const double opacityMedium = 0.30;

  /// 0.50 — strong tint (active+hover border, emphasis)
  static const double opacityStrong = 0.50;

  /// 0.65 — near-opaque (active+hover border accent)
  static const double opacityFull = 0.65;

  // ============================================
  // FONT SIZES
  // ============================================

  /// 9px — captions, compact labels, sidebar buttons
  static const double fontCaption = 9.0;

  /// 11px — labels, button text, secondary info
  static const double fontLabel = 11.0;

  /// 13px — body text, primary content
  static const double fontBody = 13.0;

  /// 15px — monospace displays (tempo, position, signature)
  static const double fontDisplay = 15.0;

  /// 20px — dialog titles, section headings
  static const double fontHeading = 20.0;

  // ============================================
  // FONT FAMILY
  // ============================================

  /// Monospace font for numeric displays
  static const String fontFamilyMono = 'monospace';

  // ============================================
  // TEXT STYLES (factory methods)
  // ============================================

  /// 9px caption — compact labels, sidebar buttons
  static TextStyle caption(Color color, {FontWeight? weight}) => TextStyle(
    fontSize: fontCaption,
    fontWeight: weight ?? weightRegular,
    color: color,
  );

  /// 11px label — button text, secondary info
  static TextStyle label(Color color, {FontWeight? weight}) => TextStyle(
    fontSize: fontLabel,
    fontWeight: weight ?? weightMedium,
    color: color,
  );

  /// 13px body — primary content
  static TextStyle body(Color color, {FontWeight? weight}) => TextStyle(
    fontSize: fontBody,
    fontWeight: weight ?? weightRegular,
    color: color,
  );

  /// 15px display — monospace numeric readouts with tabular figures
  static TextStyle display(Color color, {FontWeight? weight}) => TextStyle(
    fontSize: fontDisplay,
    fontWeight: weight ?? weightSemiBold,
    fontFamily: fontFamilyMono,
    fontFeatures: const [FontFeature.tabularFigures()],
    color: color,
  );

  // ============================================
  // FONT WEIGHTS
  // ============================================

  /// Regular — body text, inactive labels
  static const FontWeight weightRegular = FontWeight.w400;

  /// Medium — labels, emphasized buttons
  static const FontWeight weightMedium = FontWeight.w500;

  /// Semi-bold — active states, track names, headings
  static const FontWeight weightSemiBold = FontWeight.w600;

  // ============================================
  // ICON SIZES
  // ============================================

  /// 12px — compact/sidebar buttons
  static const double iconSm = 12.0;

  /// 14px — standard buttons, toolbar
  static const double iconMd = 14.0;

  /// 18px — large/prominent buttons, headers
  static const double iconLg = 18.0;

  // ============================================
  // BUTTON SIZING (standard & compact)
  // ============================================

  /// Standard button padding (transport bar, toolbars)
  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(
    horizontal: sm,
    vertical: 5.0,
  );

  /// Compact button padding (piano roll sidebar, small controls)
  static const EdgeInsets buttonPaddingCompact = EdgeInsets.symmetric(
    horizontal: 6.0,
    vertical: 3.0,
  );

  /// Standard split button right-zone padding
  static const EdgeInsets splitRightPadding = EdgeInsets.symmetric(
    horizontal: 7.0,
    vertical: 5.0,
  );

  /// Compact split button right-zone padding
  static const EdgeInsets splitRightPaddingCompact = EdgeInsets.symmetric(
    horizontal: 5.0,
    vertical: 3.0,
  );
}
