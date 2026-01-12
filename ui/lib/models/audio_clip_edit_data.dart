import 'package:flutter/foundation.dart';

/// Non-destructive editing parameters for audio clips.
/// These parameters are stored in the UI and sent to the audio engine
/// for real-time processing during playback.
@immutable
class AudioClipEditData {
  // === Playback Settings ===
  /// Whether clip content loops when stretched beyond its length
  final bool loopEnabled;

  /// Content start offset in beats (skip content before this beat)
  final double startOffsetBeats;

  /// Visible length in beats
  final double lengthBeats;

  /// Time signature numerator (beats per bar)
  final int beatsPerBar;

  /// Time signature denominator (beat unit, e.g., 4 = quarter note)
  final int beatUnit;

  // === Tempo / Stretch ===
  /// Detected or manually set BPM of the audio clip
  final double bpm;

  /// Whether to sync clip playback to project tempo
  final bool syncEnabled;

  /// Time stretch factor (0.5 = half speed, 1.0 = normal, 2.0 = double speed)
  final double stretchFactor;

  // === Pitch ===
  /// Transpose amount in semitones (-48 to +48)
  final int transposeSemitones;

  /// Fine pitch adjustment in cents (-100 to +100)
  final int fineCents;

  // === Level ===
  /// Gain adjustment in decibels (-infinity to +12 dB)
  final double gainDb;

  /// Whether the source audio is stereo (display only, doesn't affect processing)
  final bool isStereo;

  // === Processing ===
  /// Whether to reverse the audio playback
  final bool reversed;

  /// Normalize target level in dB (null = no normalization, else -12 to 0 dB)
  final double? normalizeTargetDb;

  // === Loop Region ===
  /// Loop region start position in beats
  final double loopStartBeats;

  /// Loop region end position in beats
  final double loopEndBeats;

  const AudioClipEditData({
    this.loopEnabled = true,
    this.startOffsetBeats = 0.0,
    this.lengthBeats = 4.0,
    this.beatsPerBar = 4,
    this.beatUnit = 4,
    this.bpm = 120.0,
    this.syncEnabled = false,
    this.stretchFactor = 1.0,
    this.transposeSemitones = 0,
    this.fineCents = 0,
    this.gainDb = 0.0,
    this.isStereo = true,
    this.reversed = false,
    this.normalizeTargetDb,
    this.loopStartBeats = 0.0,
    this.loopEndBeats = 4.0,
  });

  /// Creates a copy with the specified fields replaced
  AudioClipEditData copyWith({
    bool? loopEnabled,
    double? startOffsetBeats,
    double? lengthBeats,
    int? beatsPerBar,
    int? beatUnit,
    double? bpm,
    bool? syncEnabled,
    double? stretchFactor,
    int? transposeSemitones,
    int? fineCents,
    double? gainDb,
    bool? isStereo,
    bool? reversed,
    double? normalizeTargetDb,
    double? loopStartBeats,
    double? loopEndBeats,
    bool clearNormalize = false,
  }) {
    return AudioClipEditData(
      loopEnabled: loopEnabled ?? this.loopEnabled,
      startOffsetBeats: startOffsetBeats ?? this.startOffsetBeats,
      lengthBeats: lengthBeats ?? this.lengthBeats,
      beatsPerBar: beatsPerBar ?? this.beatsPerBar,
      beatUnit: beatUnit ?? this.beatUnit,
      bpm: bpm ?? this.bpm,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      stretchFactor: stretchFactor ?? this.stretchFactor,
      transposeSemitones: transposeSemitones ?? this.transposeSemitones,
      fineCents: fineCents ?? this.fineCents,
      gainDb: gainDb ?? this.gainDb,
      isStereo: isStereo ?? this.isStereo,
      reversed: reversed ?? this.reversed,
      normalizeTargetDb: clearNormalize ? null : (normalizeTargetDb ?? this.normalizeTargetDb),
      loopStartBeats: loopStartBeats ?? this.loopStartBeats,
      loopEndBeats: loopEndBeats ?? this.loopEndBeats,
    );
  }

  /// Loop region length in beats
  double get loopLengthBeats => loopEndBeats - loopStartBeats;

  /// Combined pitch shift in cents (semitones * 100 + fine cents)
  int get totalPitchCents => (transposeSemitones * 100) + fineCents;

  /// Whether any pitch shifting is applied
  bool get hasPitchShift => transposeSemitones != 0 || fineCents != 0;

  /// Whether any processing is applied
  bool get hasProcessing => reversed || normalizeTargetDb != null;

  /// Whether any tempo modification is applied
  bool get hasTempoModification => syncEnabled || stretchFactor != 1.0;

  /// Serialize to JSON for project save
  Map<String, dynamic> toJson() {
    return {
      'loopEnabled': loopEnabled,
      'startOffsetBeats': startOffsetBeats,
      'lengthBeats': lengthBeats,
      'beatsPerBar': beatsPerBar,
      'beatUnit': beatUnit,
      'bpm': bpm,
      'syncEnabled': syncEnabled,
      'stretchFactor': stretchFactor,
      'transposeSemitones': transposeSemitones,
      'fineCents': fineCents,
      'gainDb': gainDb,
      'isStereo': isStereo,
      'reversed': reversed,
      'normalizeTargetDb': normalizeTargetDb,
      'loopStartBeats': loopStartBeats,
      'loopEndBeats': loopEndBeats,
    };
  }

  /// Deserialize from JSON for project load
  factory AudioClipEditData.fromJson(Map<String, dynamic> json) {
    return AudioClipEditData(
      loopEnabled: json['loopEnabled'] as bool? ?? true,
      startOffsetBeats: (json['startOffsetBeats'] as num?)?.toDouble() ?? 0.0,
      lengthBeats: (json['lengthBeats'] as num?)?.toDouble() ?? 4.0,
      beatsPerBar: json['beatsPerBar'] as int? ?? 4,
      beatUnit: json['beatUnit'] as int? ?? 4,
      bpm: (json['bpm'] as num?)?.toDouble() ?? 120.0,
      syncEnabled: json['syncEnabled'] as bool? ?? false,
      stretchFactor: (json['stretchFactor'] as num?)?.toDouble() ?? 1.0,
      transposeSemitones: json['transposeSemitones'] as int? ?? 0,
      fineCents: json['fineCents'] as int? ?? 0,
      gainDb: (json['gainDb'] as num?)?.toDouble() ?? 0.0,
      isStereo: json['isStereo'] as bool? ?? true,
      reversed: json['reversed'] as bool? ?? false,
      normalizeTargetDb: (json['normalizeTargetDb'] as num?)?.toDouble(),
      loopStartBeats: (json['loopStartBeats'] as num?)?.toDouble() ?? 0.0,
      loopEndBeats: (json['loopEndBeats'] as num?)?.toDouble() ?? 4.0,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AudioClipEditData &&
        other.loopEnabled == loopEnabled &&
        other.startOffsetBeats == startOffsetBeats &&
        other.lengthBeats == lengthBeats &&
        other.beatsPerBar == beatsPerBar &&
        other.beatUnit == beatUnit &&
        other.bpm == bpm &&
        other.syncEnabled == syncEnabled &&
        other.stretchFactor == stretchFactor &&
        other.transposeSemitones == transposeSemitones &&
        other.fineCents == fineCents &&
        other.gainDb == gainDb &&
        other.isStereo == isStereo &&
        other.reversed == reversed &&
        other.normalizeTargetDb == normalizeTargetDb &&
        other.loopStartBeats == loopStartBeats &&
        other.loopEndBeats == loopEndBeats;
  }

  @override
  int get hashCode {
    return Object.hash(
      loopEnabled,
      startOffsetBeats,
      lengthBeats,
      beatsPerBar,
      beatUnit,
      bpm,
      syncEnabled,
      stretchFactor,
      transposeSemitones,
      fineCents,
      gainDb,
      isStereo,
      reversed,
      normalizeTargetDb,
      loopStartBeats,
      loopEndBeats,
    );
  }

  @override
  String toString() {
    return 'AudioClipEditData('
        'loop: $loopEnabled, '
        'bpm: $bpm, '
        'stretch: ${stretchFactor}x, '
        'transpose: ${transposeSemitones}st, '
        'gain: ${gainDb}dB, '
        'reversed: $reversed'
        ')';
  }
}
