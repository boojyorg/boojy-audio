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

/// Volume conversion utilities using Boojy curve (matches CapsuleFader)
/// Piecewise linear interpolation: 0.0 = -60 dB, 0.7 = 0 dB, 1.0 = +6 dB
class VolumeConversion {
  // Boojy volume curve points (same as CapsuleFader)
  static const List<double> _sliderPoints = [0.01, 0.05, 0.10, 0.30, 0.50, 0.70, 0.85, 1.00];
  static const List<double> _dbPoints = [-60.0, -52.0, -45.0, -24.0, -10.0, 0.0, 3.0, 6.0];

  /// Convert normalized (0-1) to dB using Boojy curve
  /// 0.0 = -60 dB (treated as -∞), 0.7 = 0 dB, 1.0 = +6 dB
  static double normalizedToDb(double normalized) {
    if (normalized <= 0.0) return -96.0; // Treat as -∞
    if (normalized <= 0.01) return -60.0;
    if (normalized >= 1.0) return 6.0;

    // Find segment and interpolate
    for (int i = 0; i < _sliderPoints.length - 1; i++) {
      if (normalized <= _sliderPoints[i + 1]) {
        final t = (normalized - _sliderPoints[i]) / (_sliderPoints[i + 1] - _sliderPoints[i]);
        return _dbPoints[i] + t * (_dbPoints[i + 1] - _dbPoints[i]);
      }
    }
    return 6.0; // fallback to max
  }

  /// Convert dB to normalized (0-1) using Boojy curve
  static double dbToNormalized(double db) {
    if (db <= -60.0) return 0.0;
    if (db >= 6.0) return 1.0;

    // Find segment and interpolate
    for (int i = 0; i < _dbPoints.length - 1; i++) {
      if (db <= _dbPoints[i + 1]) {
        final t = (db - _dbPoints[i]) / (_dbPoints[i + 1] - _dbPoints[i]);
        return _sliderPoints[i] + t * (_sliderPoints[i + 1] - _sliderPoints[i]);
      }
    }
    return 0.7; // fallback to unity
  }

  /// Convert normalized to display string
  static String normalizedToDisplayString(double normalized) {
    final db = normalizedToDb(normalized);
    if (db <= -60.0) return '-∞ dB';
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
    return other is AutomationPoint &&
        other.id == id &&
        other.time == time &&
        other.value == value &&
        other.isSelected == isSelected;
  }

  @override
  int get hashCode => Object.hash(id, time, value, isSelected);

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
@immutable
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

  /// Get points sorted by time (points are kept sorted on insert)
  List<AutomationPoint> get sortedPoints => points;

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

  /// Add a point to the lane (inserted in sorted order by time)
  TrackAutomationLane addPoint(AutomationPoint point) {
    // Clamp value to parameter range
    final clampedPoint = point.copyWith(
      value: point.value.clamp(parameter.minValue, parameter.maxValue),
    );
    // Insert in sorted order by time
    final newPoints = List<AutomationPoint>.from(points);
    int insertIndex = newPoints.length;
    for (int i = 0; i < newPoints.length; i++) {
      if (newPoints[i].time > clampedPoint.time) {
        insertIndex = i;
        break;
      }
    }
    newPoints.insert(insertIndex, clampedPoint);
    return copyWith(points: newPoints);
  }

  /// Remove a point from the lane
  TrackAutomationLane removePoint(String pointId) {
    return copyWith(points: points.where((p) => p.id != pointId).toList());
  }

  /// Update a point in the lane (maintains sorted order if time changes)
  TrackAutomationLane updatePoint(String pointId, AutomationPoint newPoint) {
    // Clamp value to parameter range
    final clampedPoint = newPoint.copyWith(
      value: newPoint.value.clamp(parameter.minValue, parameter.maxValue),
    );
    // Remove old point and re-insert to maintain sorted order
    final withoutOld = points.where((p) => p.id != pointId).toList();
    int insertIndex = withoutOld.length;
    for (int i = 0; i < withoutOld.length; i++) {
      if (withoutOld[i].time > clampedPoint.time) {
        insertIndex = i;
        break;
      }
    }
    withoutOld.insert(insertIndex, clampedPoint);
    return copyWith(points: withoutOld);
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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TrackAutomationLane) return false;
    return id == other.id &&
        trackId == other.trackId &&
        parameter == other.parameter &&
        listEquals(points, other.points) &&
        isExpanded == other.isExpanded;
  }

  @override
  int get hashCode => Object.hash(id, trackId, parameter, Object.hashAll(points), isExpanded);

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

  /// Convert points to engine CSV format with time in seconds and value in dB
  /// Format: "time_seconds,db;time_seconds,db;..."
  /// This is what the Rust engine expects for volume automation
  String toEngineDbCsv(double tempo) {
    if (points.isEmpty) return '';

    final sorted = sortedPoints;
    return sorted.map((p) {
      // Convert beats to seconds: seconds = beats * 60 / tempo
      final timeSeconds = p.time * 60.0 / tempo;
      // Convert normalized (0-1) to dB
      final db = VolumeConversion.normalizedToDb(p.value);
      return '${timeSeconds.toStringAsFixed(6)},${db.toStringAsFixed(2)}';
    }).join(';');
  }
}
