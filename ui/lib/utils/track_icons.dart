import 'package:flutter/widgets.dart';
import '../theme/boojy_icons.dart';

/// Track icons: one BI (Material) icon language for track identity.
///
/// Replaces the old emoji icons (🎹/🔊/🎧…), which were a second icon
/// language fighting the BI facade and rendered differently on Windows.
///
/// Persistence stays string-based: a track's `customIcon` now stores a stable
/// key from [pickerKeys] (e.g. 'mic'). Legacy projects that saved an emoji
/// string keep working via [_legacyEmojiToKey].
class TrackIcons {
  TrackIcons._();

  /// Picker grid (2×8), keys are what `customIcon` persists.
  static final Map<String, IconData> pickerIcons = {
    'mic': BI.mic,
    'piano': BI.piano,
    'guitar': BI.audiotrack,
    'drums': BI.multitrackAudio,
    'note': BI.musicNote,
    'notes': BI.musicNotes,
    'volume': BI.speakerHigh,
    'speaker': BI.speaker,
    'headphones': BI.headphones,
    'waveform': BI.waveform,
    'eq': BI.equalizer,
    'sliders': BI.sliders,
    'album': BI.album,
    'radio': BI.radio,
    'library': BI.libraryMusic,
    'surround': BI.surroundSound,
  };

  /// Emoji strings persisted by pre-icon-language projects → nearest key.
  static const Map<String, String> _legacyEmojiToKey = {
    '🎤': 'mic',
    '🎙️': 'mic',
    '🎸': 'guitar',
    '🪕': 'guitar',
    '🎹': 'piano',
    '🥁': 'drums',
    '🪘': 'drums',
    '🎺': 'note',
    '🎷': 'note',
    '🎻': 'notes',
    '🎼': 'notes',
    '🎵': 'note',
    '🎶': 'notes',
    '🎧': 'headphones',
    '🔊': 'volume',
    '🎚️': 'sliders',
    '🪗': 'sliders',
  };

  /// Resolve a stored `customIcon` (new key or legacy emoji) to a key, or
  /// null if unrecognized/unset.
  static String? keyFor(String? customIcon) {
    if (customIcon == null) return null;
    if (pickerIcons.containsKey(customIcon)) return customIcon;
    return _legacyEmojiToKey[customIcon];
  }

  /// Default key from track name/type — mirrors the old emoji heuristics.
  static String defaultKey(String trackName, String trackType) {
    final lowerName = trackName.toLowerCase();
    final lowerType = trackType.toLowerCase();

    if (lowerType == 'master') return 'headphones';
    if (lowerName.contains('guitar')) return 'guitar';
    if (lowerName.contains('piano') || lowerName.contains('keys')) {
      return 'piano';
    }
    if (lowerName.contains('drum')) return 'drums';
    if (lowerName.contains('vocal') || lowerName.contains('voice')) {
      return 'mic';
    }
    if (lowerName.contains('bass')) return 'guitar';
    if (lowerName.contains('synth')) return 'piano';
    if (lowerType == 'midi') return 'notes';
    if (lowerType == 'audio') return 'volume';
    return 'note';
  }

  /// The icon for a track: custom (key or legacy emoji) if set, else the
  /// name/type default.
  static IconData iconFor({
    String? customIcon,
    required String trackName,
    required String trackType,
  }) {
    final key = keyFor(customIcon) ?? defaultKey(trackName, trackType);
    return pickerIcons[key] ?? BI.musicNote;
  }
}
