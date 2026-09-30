import 'package:flutter/material.dart';

/// Track color utilities for assigning colors to tracks
class TrackColors {
  /// Type colours for the "+ MIDI" / "+ Audio" buttons (palette members).
  static const Color midiTypeColor = Color(0xFF69DB7C); // Lime Green
  static const Color audioTypeColor = Color(0xFF868E96); // Slate Grey

  /// 16-color manual palette for user override (2 rows of 8)
  /// Row 1: Softer variants (rainbow order + pink before grey)
  /// Row 2: Vibrant colors (rainbow order + pink before grey)
  static const List<Color> manualPalette = [
    // Row 1: Softer variants (rainbow order + pink before grey)
    Color(0xFFFFA8A8), // Salmon (soft red)
    Color(0xFFFFC078), // Peach (soft orange)
    Color(0xFFFFE066), // Butter (soft yellow — deepened, #FFF3BF read as cream)
    Color(0xFF96F2D7), // Mint (soft green)
    Color(0xFF74C0FC), // Sky Blue (soft blue)
    Color(0xFFB197FC), // Lavender (soft purple)
    Color(0xFFFCC2D7), // Light Pink
    Color(0xFFCED4DA), // Silver (soft grey)
    // Row 2: Vibrant colors (rainbow order + pink before grey)
    Color(0xFFF03E3E), // True Red (deepened from coral — read too pink)
    Color(0xFFFF922B), // Tangerine
    Color(0xFFFFD43B), // Sunflower
    Color(0xFF69DB7C), // Lime Green
    Color(0xFF40B3E8), // Boojy Blue (matches the brand accent / Master)
    Color(0xFF9775FA), // Violet
    Color(0xFFF06595), // Hot Pink
    Color(0xFF868E96), // Slate Grey
  ];

  /// The colours new tracks take in turn (creation order, by track id).
  /// Members of [manualPalette] only, so the picker can always reproduce a
  /// track's colour.
  static const List<Color> palette = [
    Color(0xFF40B3E8), // Boojy Blue
    Color(0xFFF06595), // Hot Pink
    Color(0xFF69DB7C), // Lime Green
    Color(0xFFFFD43B), // Sunflower
    Color(0xFF9775FA), // Violet
    Color(0xFFFF922B), // Tangerine
    Color(0xFF868E96), // Slate Grey
    Color(0xFFF03E3E), // True Red
  ];

  /// Master track color (the brand accent blue — also a manualPalette swatch)
  static const Color masterColor = Color(0xFF40B3E8); // Boojy Blue

  /// Colour for a track by index (cycles through [palette]).
  static Color getTrackColor(int trackIndex, {bool isMaster = false}) {
    if (isMaster) return masterColor;
    return palette[trackIndex % palette.length];
  }

  /// Get a lighter shade of a color (for clip content like MIDI notes and waveforms)
  /// [factor] controls how much lighter (0.0 = no change, 1.0 = white)
  static Color getLighterShade(Color base, [double factor = 0.3]) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withLightness((hsl.lightness + factor).clamp(0.0, 0.85))
        .toColor();
  }
}
