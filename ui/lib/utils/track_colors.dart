import 'package:flutter/material.dart';

/// Track color categories for auto-detection
enum TrackColorCategory {
  drums,
  bass,
  synth,
  guitar,
  vocals,
  orchestral,
  fx,
  audio,
  master,
}

/// Track color utilities for assigning colors to tracks
class TrackColors {
  /// Category-based colors for auto-detection (Row 1 - Vibrant)
  static const Map<TrackColorCategory, Color> categoryColors = {
    TrackColorCategory.drums: Color(0xFFFF6B6B), // Coral Red
    TrackColorCategory.bass: Color(0xFF4DABF7), // Ocean Blue
    TrackColorCategory.synth: Color(0xFFF06ACD), // Hot Pink
    TrackColorCategory.guitar: Color(0xFFFFD43B), // Sunflower
    TrackColorCategory.vocals: Color(0xFF69DB7C), // Lime Green
    TrackColorCategory.orchestral: Color(0xFFFF922B), // Tangerine
    TrackColorCategory.fx: Color(0xFF9775FA), // Violet
    TrackColorCategory.audio: Color(0xFF868E96), // Slate Grey
    TrackColorCategory.master: Color(0xFF74C0FC), // Sky Blue
  };

  /// 16-color manual palette for user override (2 rows of 8)
  /// Row 1: Softer variants (rainbow order + pink before grey)
  /// Row 2: Vibrant colors (rainbow order + pink before grey)
  static const List<Color> manualPalette = [
    // Row 1: Softer variants (rainbow order + pink before grey)
    Color(0xFFFFA8A8), // Salmon (soft red)
    Color(0xFFFFC078), // Peach (soft orange)
    Color(0xFFFFF3BF), // Butter (soft yellow)
    Color(0xFF96F2D7), // Mint (soft green)
    Color(0xFF74C0FC), // Sky Blue (soft blue)
    Color(0xFFB197FC), // Lavender (soft purple)
    Color(0xFFFCC2D7), // Light Pink
    Color(0xFFCED4DA), // Silver (soft grey)
    // Row 2: Vibrant colors (rainbow order + pink before grey)
    Color(0xFFFF6B6B), // Coral Red
    Color(0xFFFF922B), // Tangerine
    Color(0xFFFFD43B), // Sunflower
    Color(0xFF69DB7C), // Lime Green
    Color(0xFF4DABF7), // Ocean Blue
    Color(0xFF9775FA), // Violet
    Color(0xFFF06595), // Hot Pink
    Color(0xFF868E96), // Slate Grey
  ];

  /// Legacy palette for backwards compatibility (cycles through for index-based access)
  static const List<Color> palette = [
    Color(0xFF4DABF7), // Ocean Blue
    Color(0xFFF06ACD), // Hot Pink
    Color(0xFF69DB7C), // Lime Green
    Color(0xFFFFD43B), // Sunflower
    Color(0xFF9775FA), // Violet
    Color(0xFFFF922B), // Tangerine
    Color(0xFF868E96), // Slate Grey
    Color(0xFFFF6B6B), // Coral Red
  ];

  /// Master track color
  static const Color masterColor = Color(0xFF74C0FC); // Sky Blue

  /// Detect category from track name, type, instrument, and plugin
  static TrackColorCategory detectCategory(
    String trackName,
    String trackType, {
    String? instrumentType,
    String? pluginName,
  }) {
    if (trackType.toLowerCase() == 'master') {
      return TrackColorCategory.master;
    }

    // Combine all sources for keyword matching
    final searchText = '$trackName ${instrumentType ?? ''} ${pluginName ?? ''}'.toLowerCase();

    // Check keywords for each category (order matters - more specific first)
    if (_matchesKeywords(searchText, [
      'drum', 'percussion', 'beat', 'kit', '808', 'kick', 'snare',
      'hi-hat', 'hihat', 'cymbal', 'tom', 'clap', 'hats'
    ])) {
      return TrackColorCategory.drums;
    }
    if (_matchesKeywords(searchText, ['bass', 'sub', 'low', '808 bass'])) {
      return TrackColorCategory.bass;
    }
    if (_matchesKeywords(searchText, [
      'synth', 'piano', 'keys', 'keyboard', 'pad', 'lead', 'pluck',
      'arp', 'chord', 'organ', 'electric piano', 'rhodes'
    ])) {
      return TrackColorCategory.synth;
    }
    if (_matchesKeywords(searchText, [
      'guitar', 'string', 'violin', 'cello', 'acoustic', 'ukulele',
      'banjo', 'mandolin', 'harp'
    ])) {
      return TrackColorCategory.guitar;
    }
    if (_matchesKeywords(searchText, [
      'vocal', 'voice', 'vox', 'choir', 'sing', 'acapella', 'harmony'
    ])) {
      return TrackColorCategory.vocals;
    }
    if (_matchesKeywords(searchText, [
      'orchestra', 'brass', 'woodwind', 'horn', 'trumpet', 'flute',
      'clarinet', 'oboe', 'trombone', 'tuba', 'french horn'
    ])) {
      return TrackColorCategory.orchestral;
    }
    if (_matchesKeywords(searchText, [
      'fx', 'effect', 'ambience', 'ambient', 'noise', 'riser',
      'impact', 'sweep', 'transition', 'foley', 'sfx'
    ])) {
      return TrackColorCategory.fx;
    }

    // Default based on track type
    return trackType.toLowerCase() == 'midi'
        ? TrackColorCategory.synth // Default MIDI to synth (pink)
        : TrackColorCategory.audio; // Default audio to grey
  }

  static bool _matchesKeywords(String text, List<String> keywords) {
    return keywords.any((kw) => text.contains(kw));
  }

  /// Get color for a category
  static Color getColorForCategory(TrackColorCategory category) {
    return categoryColors[category] ?? categoryColors[TrackColorCategory.audio]!;
  }

  /// Get color for a track by index (legacy - cycles through palette)
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
