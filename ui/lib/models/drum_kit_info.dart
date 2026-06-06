/// Drum-kit state for the Drum Kit editor UI (v0.6).
///
/// Parsed from the JSON returned by `get_drum_kit_info_ffi`, which serializes
/// the engine's `DrumKitData { slots: [DrumSlotData] }`. A drum kit is N pads,
/// each a one-shot sampler pinned to a fixed MIDI note — see `engine/src/drum_kit.rs`.
class DrumKitInfo {
  final List<DrumPadInfo> pads;

  const DrumKitInfo({required this.pads});

  factory DrumKitInfo.fromJson(Map<String, dynamic> json) {
    final slots = (json['slots'] as List<dynamic>? ?? const [])
        .map((s) => DrumPadInfo.fromJson(s as Map<String, dynamic>))
        .toList();
    return DrumKitInfo(pads: slots);
  }

  /// The pad firing on [pinnedNote], or null if no pad is pinned there.
  DrumPadInfo? padForNote(int pinnedNote) {
    for (final pad in pads) {
      if (pad.pinnedNote == pinnedNote) return pad;
    }
    return null;
  }

  /// A copy with the pad at [padIndex] replaced — for optimistic UI updates
  /// while the engine call settles, avoiding a full re-fetch per knob tick.
  DrumKitInfo withPad(DrumPadInfo updated) {
    return DrumKitInfo(
      pads: pads
          .map((p) => p.padIndex == updated.padIndex ? updated : p)
          .toList(),
    );
  }
}

/// One pad: its pinned MIDI note (stable identity), per-pad mix state, and the
/// loaded sample's parameters (null when the pad has no sample yet).
class DrumPadInfo {
  final int padIndex;
  final int pinnedNote;
  final double pan; // -1.0..1.0
  final bool muted;
  final bool soloed;
  final int? chokeGroup; // reserved, unused in v0.6

  /// Null when the pad is empty (no sample loaded).
  final String? samplePath;
  final double volumeDb;
  final double attackMs;
  final double releaseMs;
  final int transposeSemitones;
  final int fineCents;
  final bool reversed;

  const DrumPadInfo({
    required this.padIndex,
    required this.pinnedNote,
    this.pan = 0.0,
    this.muted = false,
    this.soloed = false,
    this.chokeGroup,
    this.samplePath,
    this.volumeDb = 0.0,
    this.attackMs = 0.0,
    this.releaseMs = 0.0,
    this.transposeSemitones = 0,
    this.fineCents = 0,
    this.reversed = false,
  });

  DrumPadInfo copyWith({
    double? pan,
    bool? muted,
    bool? soloed,
    double? volumeDb,
    double? attackMs,
    double? releaseMs,
    int? transposeSemitones,
    bool? reversed,
    String? samplePath,
  }) {
    return DrumPadInfo(
      padIndex: padIndex,
      pinnedNote: pinnedNote,
      pan: pan ?? this.pan,
      muted: muted ?? this.muted,
      soloed: soloed ?? this.soloed,
      chokeGroup: chokeGroup,
      samplePath: samplePath ?? this.samplePath,
      volumeDb: volumeDb ?? this.volumeDb,
      attackMs: attackMs ?? this.attackMs,
      releaseMs: releaseMs ?? this.releaseMs,
      transposeSemitones: transposeSemitones ?? this.transposeSemitones,
      fineCents: fineCents,
      reversed: reversed ?? this.reversed,
    );
  }

  bool get hasSample => samplePath != null && samplePath!.isNotEmpty;

  /// A user-facing name derived from the sample file, or "Pad N" when empty.
  String get displayName {
    final path = samplePath;
    if (path == null || path.isEmpty) return 'Pad ${padIndex + 1}';
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    final file = slash >= 0 ? path.substring(slash + 1) : path;
    final dot = file.lastIndexOf('.');
    return dot > 0 ? file.substring(0, dot) : file;
  }

  factory DrumPadInfo.fromJson(Map<String, dynamic> json) {
    final sampler = json['sampler'] as Map<String, dynamic>?;
    return DrumPadInfo(
      padIndex: (json['pad_index'] as num).toInt(),
      pinnedNote: (json['pinned_note'] as num).toInt(),
      pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
      muted: json['muted'] as bool? ?? false,
      soloed: json['soloed'] as bool? ?? false,
      chokeGroup: (json['choke_group'] as num?)?.toInt(),
      samplePath: sampler?['sample_path'] as String?,
      volumeDb: (sampler?['volume_db'] as num?)?.toDouble() ?? 0.0,
      attackMs: (sampler?['attack_ms'] as num?)?.toDouble() ?? 0.0,
      releaseMs: (sampler?['release_ms'] as num?)?.toDouble() ?? 0.0,
      transposeSemitones:
          (sampler?['transpose_semitones'] as num?)?.toInt() ?? 0,
      fineCents: (sampler?['fine_cents'] as num?)?.toInt() ?? 0,
      reversed: sampler?['reversed'] as bool? ?? false,
    );
  }
}
