import 'package:flutter/widgets.dart';
import '../theme/boojy_icons.dart';

/// One fixed icon per track type, matching the "+ MIDI" / "+ Audio" buttons.
/// There is no per-track picker and no guessing from the track name.
class TrackIcons {
  TrackIcons._();

  /// MIDI (and anything unrecognised) → piano, Audio and Return → waveform,
  /// Master → headphones.
  static IconData forType(String trackType) {
    switch (trackType.toLowerCase()) {
      case 'master':
        return BI.headphones;
      case 'audio':
      case 'return':
        return BI.waveform;
      default:
        return BI.piano;
    }
  }
}
