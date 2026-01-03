import 'package:flutter/foundation.dart';

/// Project-specific metadata and settings
/// These settings are stored in the .boojy project file
@immutable
class ProjectMetadata {
  final String name;
  final String? style; // e.g., "Travis Scott Type Beat"
  final double bpm;
  final int timeSignatureNumerator;
  final int timeSignatureDenominator;
  final String key; // "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"
  final String scale; // "Major", "Minor"
  final int sampleRate; // 44100 or 48000
  final DateTime? createdDate;
  final DateTime? lastModified;

  const ProjectMetadata({
    required this.name,
    this.style,
    this.bpm = 120.0,
    this.timeSignatureNumerator = 4,
    this.timeSignatureDenominator = 4,
    this.key = 'C',
    this.scale = 'Major',
    this.sampleRate = 48000,
    this.createdDate,
    this.lastModified,
  });

  /// Create ProjectMetadata from JSON
  factory ProjectMetadata.fromJson(Map<String, dynamic> json) {
    return ProjectMetadata(
      name: json['name'] as String? ?? 'Untitled',
      style: json['style'] as String?,
      bpm: (json['bpm'] as num?)?.toDouble() ?? 120.0,
      timeSignatureNumerator: json['timeSignatureNumerator'] as int? ?? 4,
      timeSignatureDenominator: json['timeSignatureDenominator'] as int? ?? 4,
      key: json['key'] as String? ?? 'C',
      scale: json['scale'] as String? ?? 'Major',
      sampleRate: json['sampleRate'] as int? ?? 48000,
      createdDate: json['createdDate'] != null
          ? DateTime.parse(json['createdDate'] as String)
          : null,
      lastModified: json['lastModified'] != null
          ? DateTime.parse(json['lastModified'] as String)
          : null,
    );
  }

  /// Convert ProjectMetadata to JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (style != null) 'style': style,
      'bpm': bpm,
      'timeSignatureNumerator': timeSignatureNumerator,
      'timeSignatureDenominator': timeSignatureDenominator,
      'key': key,
      'scale': scale,
      'sampleRate': sampleRate,
      if (createdDate != null) 'createdDate': createdDate!.toIso8601String(),
      if (lastModified != null) 'lastModified': lastModified!.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  ProjectMetadata copyWith({
    String? name,
    String? style,
    bool clearStyle = false,
    double? bpm,
    int? timeSignatureNumerator,
    int? timeSignatureDenominator,
    String? key,
    String? scale,
    int? sampleRate,
    DateTime? createdDate,
    DateTime? lastModified,
  }) {
    return ProjectMetadata(
      name: name ?? this.name,
      style: clearStyle ? null : (style ?? this.style),
      bpm: bpm ?? this.bpm,
      timeSignatureNumerator: timeSignatureNumerator ?? this.timeSignatureNumerator,
      timeSignatureDenominator: timeSignatureDenominator ?? this.timeSignatureDenominator,
      key: key ?? this.key,
      scale: scale ?? this.scale,
      sampleRate: sampleRate ?? this.sampleRate,
      createdDate: createdDate ?? this.createdDate,
      lastModified: lastModified ?? this.lastModified,
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

  /// Format date for display (e.g., "Jan 15, 2025")
  static String formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// Get formatted created date
  String get formattedCreatedDate => formatDate(createdDate);

  /// Get formatted last modified date
  String get formattedLastModified => formatDate(lastModified);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ProjectMetadata &&
        other.name == name &&
        other.style == style &&
        other.bpm == bpm &&
        other.timeSignatureNumerator == timeSignatureNumerator &&
        other.timeSignatureDenominator == timeSignatureDenominator &&
        other.key == key &&
        other.scale == scale &&
        other.sampleRate == sampleRate &&
        other.createdDate == createdDate &&
        other.lastModified == lastModified;
  }

  @override
  int get hashCode {
    return Object.hash(
      name,
      style,
      bpm,
      timeSignatureNumerator,
      timeSignatureDenominator,
      key,
      scale,
      sampleRate,
      createdDate,
      lastModified,
    );
  }
}
