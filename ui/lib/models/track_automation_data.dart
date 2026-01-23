import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// Track automation parameter types
enum AutomationParameter {
  volume('Volume', 0.0, 1.0, 0.833), // 0.833 ≈ 0 dB unity gain
  pan('Pan', -1.0, 1.0, 0.0); // Center

  final String displayName;
  final double minValue;
  final double maxValue;
  final double defaultValue;

  const AutomationParameter(
    this.displayName,
    this.minValue,
    this.maxValue,
    this.defaultValue,
  );

  /// Get center value (useful for pan)
  double get centerValue => (minValue + maxValue) / 2;

  /// Check if this is a bipolar parameter (has negative values)
  bool get isBipolar => minValue < 0;
}

/// Volume conversion utilities
class VolumeConversion {
  /// Convert normalized (0-1) to dB
  /// 0.0 = -∞ dB, 0.833 = 0 dB, 1.0 = +6 dB
  static double normalizedToDb(double normalized) {
    if (normalized <= 0.0001) return -96.0; // Treat as -∞
    // Logarithmic mapping: 0 dB at ~0.833 (1/1.2), +6 dB at 1.0
    return 20 * math.log(normalized * 1.2) / math.ln10;
  }

  /// Convert dB to normalized (0-1)
  static double dbToNormalized(double db) {
    if (db <= -96.0) return 0.0;
    return math.pow(10, db / 20) / 1.2;
  }

  /// Convert normalized to display string
  static String normalizedToDisplayString(double normalized) {
    final db = normalizedToDb(normalized);
    if (db <= -96.0) return '-∞ dB';
    return '${db.toStringAsFixed(1)} dB';
  }
}

/// A single automation point in a track automation lane
@immutable
class AutomationPoint {
  final String id;
  final double time; // Position in beats
  final double value; // Normalized value within parameter range
  final bool isSelected;

  AutomationPoint({
    String? id,
    required this.time,
    required this.value,
    this.isSelected = false,
  }) : id = id ?? const Uuid().v4();

  AutomationPoint copyWith({
    String? id,
    double? time,
    double? value,
    bool? isSelected,
  }) {
    return AutomationPoint(
      id: id ?? this.id,
      time: time ?? this.time,
      value: value ?? this.value,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AutomationPoint && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'time': time,
      'value': value,
    };
  }

  factory AutomationPoint.fromJson(Map<String, dynamic> json) {
    return AutomationPoint(
      id: json['id'] as String?,
      time: (json['time'] as num).toDouble(),
      value: (json['value'] as num).toDouble(),
    );
  }
}

/// A track automation lane containing points for a specific parameter
class TrackAutomationLane {
  final String id;
  final int trackId;
  final AutomationParameter parameter;
  final List<AutomationPoint> points;
  final bool isExpanded;

  TrackAutomationLane({
    String? id,
    required this.trackId,
    required this.parameter,
    List<AutomationPoint>? points,
    this.isExpanded = true,
  })  : id = id ?? const Uuid().v4(),
        points = points ?? [];

  /// Create an empty lane for a track/parameter
  factory TrackAutomationLane.empty(int trackId, AutomationParameter parameter) {
    return TrackAutomationLane(
      trackId: trackId,
      parameter: parameter,
    );
  }

  /// Get sorted points by time
  List<AutomationPoint> get sortedPoints {
    return List<AutomationPoint>.from(points)
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  /// Get value at a specific time (linear interpolation between points)
  double getValueAtTime(double time) {
    if (points.isEmpty) return parameter.defaultValue;

    final sorted = sortedPoints;

    // Before first point - use first point's value
    if (time <= sorted.first.time) return sorted.first.value;

    // After last point - use last point's value
    if (time >= sorted.last.time) return sorted.last.value;

    // Find surrounding points and interpolate
    for (int i = 0; i < sorted.length - 1; i++) {
      final p1 = sorted[i];
      final p2 = sorted[i + 1];

      if (time >= p1.time && time <= p2.time) {
        // Linear interpolation
        final t = (time - p1.time) / (p2.time - p1.time);
        return p1.value + (p2.value - p1.value) * t;
      }
    }

    return parameter.defaultValue;
  }

  /// Check if there are any automation points
  bool get hasAutomation => points.isNotEmpty;

  /// Add a point to the lane
  TrackAutomationLane addPoint(AutomationPoint point) {
    // Clamp value to parameter range
    final clampedPoint = point.copyWith(
      value: point.value.clamp(parameter.minValue, parameter.maxValue),
    );
    return copyWith(points: [...points, clampedPoint]);
  }

  /// Remove a point from the lane
  TrackAutomationLane removePoint(String pointId) {
    return copyWith(points: points.where((p) => p.id != pointId).toList());
  }

  /// Update a point in the lane
  TrackAutomationLane updatePoint(String pointId, AutomationPoint newPoint) {
    // Clamp value to parameter range
    final clampedPoint = newPoint.copyWith(
      value: newPoint.value.clamp(parameter.minValue, parameter.maxValue),
    );
    return copyWith(
      points: points.map((p) => p.id == pointId ? clampedPoint : p).toList(),
    );
  }

  /// Get selected points
  List<AutomationPoint> get selectedPoints =>
      points.where((p) => p.isSelected).toList();

  /// Select all points
  TrackAutomationLane selectAll() {
    return copyWith(
      points: points.map((p) => p.copyWith(isSelected: true)).toList(),
    );
  }

  /// Deselect all points
  TrackAutomationLane deselectAll() {
    return copyWith(
      points: points.map((p) => p.copyWith(isSelected: false)).toList(),
    );
  }

  /// Delete selected points
  TrackAutomationLane deleteSelected() {
    return copyWith(points: points.where((p) => !p.isSelected).toList());
  }

  /// Clear all points
  TrackAutomationLane clear() {
    return copyWith(points: []);
  }

  TrackAutomationLane copyWith({
    String? id,
    int? trackId,
    AutomationParameter? parameter,
    List<AutomationPoint>? points,
    bool? isExpanded,
  }) {
    return TrackAutomationLane(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      parameter: parameter ?? this.parameter,
      points: points ?? this.points,
      isExpanded: isExpanded ?? this.isExpanded,
    );
  }

  /// Convert to JSON for serialization
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'trackId': trackId,
      'parameter': parameter.name,
      'points': points.map((p) => p.toJson()).toList(),
      'isExpanded': isExpanded,
    };
  }

  /// Create from JSON
  factory TrackAutomationLane.fromJson(Map<String, dynamic> json) {
    final paramName = json['parameter'] as String;
    final parameter = AutomationParameter.values.firstWhere(
      (p) => p.name == paramName,
      orElse: () => AutomationParameter.volume,
    );

    return TrackAutomationLane(
      id: json['id'] as String?,
      trackId: (json['trackId'] as num).toInt(),
      parameter: parameter,
      points: (json['points'] as List<dynamic>?)
          ?.map((dynamic p) => AutomationPoint.fromJson(p as Map<String, dynamic>))
          .toList(),
      isExpanded: json['isExpanded'] as bool? ?? true,
    );
  }

  /// Convert points to CSV format for engine (time,value;time,value;...)
  String toEngineCsv() {
    final sorted = sortedPoints;
    return sorted.map((p) => '${p.time},${p.value}').join(';');
  }
}
