import 'package:flutter/foundation.dart';

/// Project-specific metadata and settings
/// These settings are stored in the .boojy project file
@immutable
class ProjectMetadata {
  final String name;
  final double bpm;
  final int timeSignatureNumerator;
  final int timeSignatureDenominator;
  final DateTime? createdDate;
  final DateTime? lastModified;

  const ProjectMetadata({
    required this.name,
    this.bpm = 120.0,
    this.timeSignatureNumerator = 4,
    this.timeSignatureDenominator = 4,
    this.createdDate,
    this.lastModified,
  });

  /// Create ProjectMetadata from JSON
  factory ProjectMetadata.fromJson(Map<String, dynamic> json) {
    return ProjectMetadata(
      name: json['name'] as String? ?? 'Untitled',
      bpm: (json['bpm'] as num?)?.toDouble() ?? 120.0,
      timeSignatureNumerator: json['timeSignatureNumerator'] as int? ?? 4,
      timeSignatureDenominator: json['timeSignatureDenominator'] as int? ?? 4,
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
      'bpm': bpm,
      'timeSignatureNumerator': timeSignatureNumerator,
      'timeSignatureDenominator': timeSignatureDenominator,
      if (createdDate != null) 'createdDate': createdDate!.toIso8601String(),
      if (lastModified != null) 'lastModified': lastModified!.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  ProjectMetadata copyWith({
    String? name,
    double? bpm,
    int? timeSignatureNumerator,
    int? timeSignatureDenominator,
    DateTime? createdDate,
    DateTime? lastModified,
  }) {
    return ProjectMetadata(
      name: name ?? this.name,
      bpm: bpm ?? this.bpm,
      timeSignatureNumerator:
          timeSignatureNumerator ?? this.timeSignatureNumerator,
      timeSignatureDenominator:
          timeSignatureDenominator ?? this.timeSignatureDenominator,
      createdDate: createdDate ?? this.createdDate,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  /// Get time signature as string (e.g., "4/4")
  String get timeSignature =>
      '$timeSignatureNumerator/$timeSignatureDenominator';

  @override
  String toString() {
    return 'ProjectMetadata(name: $name, bpm: $bpm, timeSignature: $timeSignature)';
  }

  /// Format date for display (e.g., "Jan 15, 2025")
  static String formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
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
        other.bpm == bpm &&
        other.timeSignatureNumerator == timeSignatureNumerator &&
        other.timeSignatureDenominator == timeSignatureDenominator &&
        other.createdDate == createdDate &&
        other.lastModified == lastModified;
  }

  @override
  int get hashCode {
    return Object.hash(
      name,
      bpm,
      timeSignatureNumerator,
      timeSignatureDenominator,
      createdDate,
      lastModified,
    );
  }
}
