import 'package:flutter/material.dart';

/// Version type for categorizing project versions
enum VersionType {
  demo('Demo', 'D', Color(0xFF3B82F6)),    // Blue
  mix('Mix', 'M', Color(0xFF8B5CF6)),      // Purple
  master('Master', 'Ma', Color(0xFFF59E0B)); // Gold

  final String displayName;
  final String shortPrefix;
  final Color color;

  const VersionType(this.displayName, this.shortPrefix, this.color);

  /// Get short label like "D1", "M2", "Ma3"
  String shortLabel(int number) => '$shortPrefix$number';

  /// Get display label like "Demo 1", "Mix 2", "Master 3"
  String displayLabel(int number) => '$displayName $number';

  /// Parse from JSON string
  static VersionType fromJson(String? value) {
    switch (value) {
      case 'demo':
        return VersionType.demo;
      case 'mix':
        return VersionType.mix;
      case 'master':
        return VersionType.master;
      default:
        return VersionType.demo; // Default for backward compatibility
    }
  }

  /// Convert to JSON string
  String toJson() => name;
}
