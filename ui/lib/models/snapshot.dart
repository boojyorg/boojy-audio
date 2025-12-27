import 'package:uuid/uuid.dart';

/// Represents a project snapshot (version control)
/// Snapshots are saved copies of the project at a specific point in time
class Snapshot {
  final String id;
  final String name;
  final String? note;
  final DateTime created;
  final String fileName; // e.g., "Chorus Idea 1.boojy"

  const Snapshot({
    required this.id,
    required this.name,
    this.note,
    required this.created,
    required this.fileName,
  });

  /// Create a new snapshot with generated ID and current timestamp
  factory Snapshot.create({
    required String name,
    String? note,
  }) {
    final id = const Uuid().v4();
    final timestamp = DateTime.now();

    // Create a safe filename from the name
    final safeFileName = _sanitizeFileName(name);
    final fileName = '$safeFileName.boojy';

    return Snapshot(
      id: id,
      name: name,
      note: note,
      created: timestamp,
      fileName: fileName,
    );
  }

  /// Create Snapshot from JSON
  factory Snapshot.fromJson(Map<String, dynamic> json) {
    return Snapshot(
      id: json['id'] as String,
      name: json['name'] as String,
      note: json['note'] as String?,
      created: DateTime.parse(json['created'] as String),
      fileName: json['fileName'] as String,
    );
  }

  /// Convert Snapshot to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'note': note,
      'created': created.toIso8601String(),
      'fileName': fileName,
    };
  }

  /// Create a copy with updated fields
  Snapshot copyWith({
    String? id,
    String? name,
    String? note,
    DateTime? created,
    String? fileName,
  }) {
    return Snapshot(
      id: id ?? this.id,
      name: name ?? this.name,
      note: note ?? this.note,
      created: created ?? this.created,
      fileName: fileName ?? this.fileName,
    );
  }

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
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[created.month - 1]} ${created.day}, ${created.year}';
    }
  }

  @override
  String toString() {
    return 'Snapshot(id: $id, name: $name, created: $created, fileName: $fileName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Snapshot &&
        other.id == id &&
        other.name == name &&
        other.note == note &&
        other.created == created &&
        other.fileName == fileName;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      name,
      note,
      created,
      fileName,
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

    return sanitized.isEmpty ? 'Snapshot' : sanitized;
  }
}
