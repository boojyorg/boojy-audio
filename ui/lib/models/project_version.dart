import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'version_type.dart';

/// Represents a project version (evolved from Snapshot)
/// Versions are saved copies of the project at a specific point in time
/// with version type (Demo, Mix, Master) and global incrementing number
@immutable
class ProjectVersion {
  final String id;
  final String name;
  final String? note;
  final DateTime created;
  final String fileName; // e.g., "Demo 1.boojy"
  final VersionType versionType;
  final int versionNumber; // Global incrementing number (1, 2, 3, ...)

  const ProjectVersion({
    required this.id,
    required this.name,
    this.note,
    required this.created,
    required this.fileName,
    this.versionType = VersionType.demo,
    required this.versionNumber,
  });

  /// Create a new version with generated ID and current timestamp
  factory ProjectVersion.create({
    required String name,
    String? note,
    required VersionType versionType,
    required int versionNumber,
  }) {
    final id = const Uuid().v4();
    final timestamp = DateTime.now();

    // Create a safe filename from the name
    final safeFileName = _sanitizeFileName(name);
    final fileName = '$safeFileName.boojy';

    return ProjectVersion(
      id: id,
      name: name,
      note: note,
      created: timestamp,
      fileName: fileName,
      versionType: versionType,
      versionNumber: versionNumber,
    );
  }

  /// Create ProjectVersion from JSON (with backward compatibility for old Snapshot format)
  factory ProjectVersion.fromJson(Map<String, dynamic> json, {int? fallbackVersionNumber}) {
    return ProjectVersion(
      id: json['id'] as String,
      name: json['name'] as String,
      note: json['note'] as String?,
      created: DateTime.parse(json['created'] as String),
      fileName: json['fileName'] as String,
      versionType: VersionType.fromJson(json['versionType'] as String?),
      versionNumber: json['versionNumber'] as int? ?? fallbackVersionNumber ?? 1,
    );
  }

  /// Convert ProjectVersion to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'note': note,
      'created': created.toIso8601String(),
      'fileName': fileName,
      'versionType': versionType.toJson(),
      'versionNumber': versionNumber,
    };
  }

  /// Create a copy with updated fields
  ProjectVersion copyWith({
    String? id,
    String? name,
    String? note,
    DateTime? created,
    String? fileName,
    VersionType? versionType,
    int? versionNumber,
  }) {
    return ProjectVersion(
      id: id ?? this.id,
      name: name ?? this.name,
      note: note ?? this.note,
      created: created ?? this.created,
      fileName: fileName ?? this.fileName,
      versionType: versionType ?? this.versionType,
      versionNumber: versionNumber ?? this.versionNumber,
    );
  }

  /// Get display label: "Demo 1", "Mix 2", "Master 3"
  String get displayLabel => versionType.displayLabel(versionNumber);

  /// Get short label: "D1", "M2", "Ma3"
  String get shortLabel => versionType.shortLabel(versionNumber);

  /// Format created date for display
  String get formattedDate {
    final now = DateTime.now();
    final diff = now.difference(created);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        if (diff.inMinutes == 0) {
          return 'Just now';
        }
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      // Format as "Jan 15, 2025"
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[created.month - 1]} ${created.day}, ${created.year}';
    }
  }

  /// Format created date with time for version list
  String get formattedDateTime {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = created.hour;
    final minute = created.minute.toString().padLeft(2, '0');
    final amPm = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '${months[created.month - 1]} ${created.day}, ${created.year} $hour12:$minute $amPm';
  }

  @override
  String toString() {
    return 'ProjectVersion(id: $id, name: $name, $displayLabel, created: $created)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ProjectVersion &&
        other.id == id &&
        other.name == name &&
        other.note == note &&
        other.created == created &&
        other.fileName == fileName &&
        other.versionType == versionType &&
        other.versionNumber == versionNumber;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      name,
      note,
      created,
      fileName,
      versionType,
      versionNumber,
    );
  }

  /// Sanitize a string to be used as a filename
  static String _sanitizeFileName(String name) {
    // Remove or replace invalid filename characters
    final sanitized = name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Limit length to avoid filesystem issues
    if (sanitized.length > 100) {
      return sanitized.substring(0, 100);
    }

    return sanitized.isEmpty ? 'Version' : sanitized;
  }
}

/// Backward compatibility alias
@Deprecated('Use ProjectVersion instead')
typedef Snapshot = ProjectVersion;
