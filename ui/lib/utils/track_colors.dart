import 'package:flutter/material.dart';

/// Track color utilities for assigning colors to tracks
class TrackColors {
  /// Available track colors (Ableton-style pastels with cooler tones)
  static const List<Color> palette = [
    Color(0xFF7DB3D9), // Light blue
    Color(0xFF6BA3A3), // Teal/cyan (cooler replacement for coral)
    Color(0xFF8B9B85), // Sage grey-green (cooler replacement for brown)
    Color(0xFFA898C4), // Muted lavender (cooler replacement for pink)
    Color(0xFF7FA894), // Sage green
    Color(0xFF9BB0C4), // Steel blue
    Color(0xFF9B8DC4), // Light purple/lavender
    Color(0xFFA0A8B0), // Cool grey
  ];

  /// Master track color
  static const Color masterColor = Color(0xFF4CAF50); // Green

  /// Get color for a track by index (cycles through palette)
  static Color getTrackColor(int trackIndex, {bool isMaster = false}) {
    if (isMaster) return masterColor;
    return palette[trackIndex % palette.length];
  }

  /// Get formatted track name with type and number
  /// Examples: "Audio 1", "MIDI 2 - Bass", "Master"
  /// If track name is the default (same as type), only show "MIDI 1" or "Audio 1"
  /// If user has set a custom name, show "MIDI 1 - Custom Name"
  static String getFormattedTrackName({
    required String trackType,
    required String trackName,
    required int audioCount,
    required int midiCount,
  }) {
    final lowerType = trackType.toLowerCase();
    final lowerName = trackName.toLowerCase();

    if (lowerType == 'master') {
      return trackName; // Just "Master", no number
    } else if (lowerType == 'audio') {
      // If name is just "Audio" or empty, show only "Audio 1"
      // Otherwise show "Audio 1 - Custom Name"
      if (lowerName == 'audio' || trackName.isEmpty) {
        return 'Audio $audioCount';
      }
      return 'Audio $audioCount - $trackName';
    } else if (lowerType == 'midi') {
      // If name is just "MIDI" or empty, show only "MIDI 1"
      // Otherwise show "MIDI 1 - Custom Name"
      if (lowerName == 'midi' || trackName.isEmpty) {
        return 'MIDI $midiCount';
      }
      return 'MIDI $midiCount - $trackName';
    } else {
      return trackName; // Fallback
    }
  }

  /// Get a lighter shade of a color (for clip content like MIDI notes and waveforms)
  /// [factor] controls how much lighter (0.0 = no change, 1.0 = white)
  static Color getLighterShade(Color base, [double factor = 0.3]) {
    final hsl = HSLColor.fromColor(base);
    return hsl.withLightness((hsl.lightness + factor).clamp(0.0, 0.85)).toColor();
  }

  /// Get track emoji based on name or type
  static String getTrackEmoji(String trackName, String trackType) {
    final lowerName = trackName.toLowerCase();
    final lowerType = trackType.toLowerCase();

    if (lowerType == 'master') return '🎚️';
    if (lowerName.contains('guitar')) return '🎸';
    if (lowerName.contains('piano') || lowerName.contains('keys')) return '🎹';
    if (lowerName.contains('drum')) return '🥁';
    if (lowerName.contains('vocal') || lowerName.contains('voice')) return '🎤';
    if (lowerName.contains('bass')) return '🎸';
    if (lowerName.contains('synth')) return '🎹';
    if (lowerName.contains('pluck')) return '🎸';
    if (lowerType == 'midi') return '🎼';
    if (lowerType == 'audio') return '🔊';

    return '🎵'; // Default
  }
}
