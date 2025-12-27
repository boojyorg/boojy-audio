/// Project-specific metadata and settings
/// These settings are stored in the .boojy project file
class ProjectMetadata {
  final String name;
  final double bpm;
  final int timeSignatureNumerator;
  final int timeSignatureDenominator;
  final String key; // "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"
  final String scale; // "Major", "Minor"
  final int sampleRate; // 44100 or 48000

  const ProjectMetadata({
    required this.name,
    this.bpm = 120.0,
    this.timeSignatureNumerator = 4,
    this.timeSignatureDenominator = 4,
    this.key = 'C',
    this.scale = 'Major',
    this.sampleRate = 48000,
  });

  /// Create ProjectMetadata from JSON
  factory ProjectMetadata.fromJson(Map<String, dynamic> json) {
    return ProjectMetadata(
      name: json['name'] as String? ?? 'Untitled',
      bpm: (json['bpm'] as num?)?.toDouble() ?? 120.0,
      timeSignatureNumerator: json['timeSignatureNumerator'] as int? ?? 4,
      timeSignatureDenominator: json['timeSignatureDenominator'] as int? ?? 4,
      key: json['key'] as String? ?? 'C',
      scale: json['scale'] as String? ?? 'Major',
      sampleRate: json['sampleRate'] as int? ?? 48000,
    );
  }

  /// Convert ProjectMetadata to JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'bpm': bpm,
      'timeSignatureNumerator': timeSignatureNumerator,
      'timeSignatureDenominator': timeSignatureDenominator,
      'key': key,
      'scale': scale,
      'sampleRate': sampleRate,
    };
  }

  /// Create a copy with updated fields
  ProjectMetadata copyWith({
    String? name,
    double? bpm,
    int? timeSignatureNumerator,
    int? timeSignatureDenominator,
    String? key,
    String? scale,
    int? sampleRate,
  }) {
    return ProjectMetadata(
      name: name ?? this.name,
      bpm: bpm ?? this.bpm,
      timeSignatureNumerator: timeSignatureNumerator ?? this.timeSignatureNumerator,
      timeSignatureDenominator: timeSignatureDenominator ?? this.timeSignatureDenominator,
      key: key ?? this.key,
      scale: scale ?? this.scale,
      sampleRate: sampleRate ?? this.sampleRate,
    );
  }

  /// Get time signature as string (e.g., "4/4")
  String get timeSignature => '$timeSignatureNumerator/$timeSignatureDenominator';

  /// Get key and scale as string (e.g., "C Major")
  String get keyAndScale => '$key $scale';

  @override
  String toString() {
    return 'ProjectMetadata(name: $name, bpm: $bpm, timeSignature: $timeSignature, key: $keyAndScale, sampleRate: $sampleRate)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ProjectMetadata &&
        other.name == name &&
        other.bpm == bpm &&
        other.timeSignatureNumerator == timeSignatureNumerator &&
        other.timeSignatureDenominator == timeSignatureDenominator &&
        other.key == key &&
        other.scale == scale &&
        other.sampleRate == sampleRate;
  }

  @override
  int get hashCode {
    return Object.hash(
      name,
      bpm,
      timeSignatureNumerator,
      timeSignatureDenominator,
      key,
      scale,
      sampleRate,
    );
  }
}
