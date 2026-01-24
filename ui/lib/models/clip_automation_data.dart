import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'track_automation_data.dart';

/// A single automation point in a clip automation lane.
/// Time is relative to clip start (in beats).
@immutable
class ClipAutomationPoint {
  final String id;
  final double time; // Position in beats, relative to clip start
  final double value; // Normalized value within parameter range
  final bool isSelected;

  ClipAutomationPoint({
    String? id,
    required this.time,
    required this.value,
    this.isSelected = false,
  }) : id = id ?? const Uuid().v4();

  ClipAutomationPoint copyWith({
    String? id,
    double? time,
    double? value,
    bool? isSelected,
  }) {
    return ClipAutomationPoint(
      id: id ?? this.id,
      time: time ?? this.time,
      value: value ?? this.value,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ClipAutomationPoint &&
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

  factory ClipAutomationPoint.fromJson(Map<String, dynamic> json) {
    return ClipAutomationPoint(
      id: json['id'] as String?,
      time: (json['time'] as num).toDouble(),
      value: (json['value'] as num).toDouble(),
    );
  }
}

/// A clip automation lane containing points for a specific parameter.
/// All times are relative to clip start.
@immutable
class ClipAutomationLane {
  final String id;
  final AutomationParameter parameter;
  final List<ClipAutomationPoint> points;

  ClipAutomationLane({
    String? id,
    required this.parameter,
    List<ClipAutomationPoint>? points,
  })  : id = id ?? const Uuid().v4(),
        points = points ?? [];

  /// Create an empty lane for a parameter
  factory ClipAutomationLane.empty(AutomationParameter parameter) {
    return ClipAutomationLane(parameter: parameter);
  }

  /// Get points sorted by time
  List<ClipAutomationPoint> get sortedPoints {
    final sorted = List<ClipAutomationPoint>.from(points);
    sorted.sort((a, b) => a.time.compareTo(b.time));
    return sorted;
  }

  /// Get value at a specific time (linear interpolation with edge hold).
  /// Edge behavior: holds first point's value before first point,
  /// holds last point's value after last point.
  double getValueAtTime(double time) {
    if (points.isEmpty) return parameter.defaultValue;

    final sorted = sortedPoints;

    // Before first point - hold first point's value (Option B)
    if (time <= sorted.first.time) return sorted.first.value;

    // After last point - hold last point's value (Option B)
    if (time >= sorted.last.time) return sorted.last.value;

    // Find surrounding points and interpolate (linear only)
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
  ClipAutomationLane addPoint(ClipAutomationPoint point) {
    // Clamp value to parameter range
    final clampedPoint = point.copyWith(
      value: point.value.clamp(parameter.minValue, parameter.maxValue),
    );
    // Insert in sorted order by time
    final newPoints = List<ClipAutomationPoint>.from(points);
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
  ClipAutomationLane removePoint(String pointId) {
    return copyWith(points: points.where((p) => p.id != pointId).toList());
  }

  /// Update a point in the lane (maintains sorted order if time changes)
  ClipAutomationLane updatePoint(String pointId, ClipAutomationPoint newPoint) {
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
  List<ClipAutomationPoint> get selectedPoints =>
      points.where((p) => p.isSelected).toList();

  /// Select all points
  ClipAutomationLane selectAll() {
    return copyWith(
      points: points.map((p) => p.copyWith(isSelected: true)).toList(),
    );
  }

  /// Deselect all points
  ClipAutomationLane deselectAll() {
    return copyWith(
      points: points.map((p) => p.copyWith(isSelected: false)).toList(),
    );
  }

  /// Delete selected points
  ClipAutomationLane deleteSelected() {
    return copyWith(points: points.where((p) => !p.isSelected).toList());
  }

  /// Clear all points
  ClipAutomationLane clear() {
    return copyWith(points: []);
  }

  /// Slice automation at a specific beat position.
  /// Returns the left portion (from 0 to splitBeat) with a new edge node.
  ClipAutomationLane sliceLeft(double splitBeat) {
    if (points.isEmpty) return this;

    final sorted = sortedPoints;

    // Get the interpolated value at split point
    final valueAtSplit = getValueAtTime(splitBeat);

    // Get all points before the split
    final pointsBefore = sorted.where((p) => p.time < splitBeat).toList();

    // Add edge node at split position if we have any automation
    final edgePoint = ClipAutomationPoint(
      time: splitBeat,
      value: valueAtSplit,
    );

    return copyWith(points: [...pointsBefore, edgePoint]);
  }

  /// Slice automation at a specific beat position.
  /// Returns the right portion (from splitBeat onwards) with times shifted to start at 0.
  ClipAutomationLane sliceRight(double splitBeat) {
    if (points.isEmpty) return this;

    final sorted = sortedPoints;

    // Get the interpolated value at split point
    final valueAtSplit = getValueAtTime(splitBeat);

    // Get all points after the split, shift times to be relative to new clip start
    final pointsAfter = sorted
        .where((p) => p.time > splitBeat)
        .map((p) => p.copyWith(
              id: const Uuid().v4(), // New ID for the copied point
              time: p.time - splitBeat,
            ))
        .toList();

    // Add edge node at position 0 (start of new clip)
    final edgePoint = ClipAutomationPoint(
      time: 0.0,
      value: valueAtSplit,
    );

    return copyWith(points: [edgePoint, ...pointsAfter]);
  }

  /// Shift all points by a time offset (used when clip is moved)
  /// Note: For clip-based automation this usually isn't needed since
  /// times are relative to clip start, but useful for edge cases.
  ClipAutomationLane shiftTime(double offset) {
    return copyWith(
      points: points.map((p) => p.copyWith(time: p.time + offset)).toList(),
    );
  }

  /// Deep copy all points with new IDs (for clip duplication)
  ClipAutomationLane deepCopy() {
    return ClipAutomationLane(
      id: const Uuid().v4(),
      parameter: parameter,
      points: points
          .map((p) => ClipAutomationPoint(
                id: const Uuid().v4(),
                time: p.time,
                value: p.value,
                isSelected: false,
              ))
          .toList(),
    );
  }

  ClipAutomationLane copyWith({
    String? id,
    AutomationParameter? parameter,
    List<ClipAutomationPoint>? points,
  }) {
    return ClipAutomationLane(
      id: id ?? this.id,
      parameter: parameter ?? this.parameter,
      points: points ?? this.points,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ClipAutomationLane) return false;
    return id == other.id &&
        parameter == other.parameter &&
        listEquals(points, other.points);
  }

  @override
  int get hashCode => Object.hash(id, parameter, Object.hashAll(points));

  /// Convert to JSON for serialization
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'parameter': parameter.name,
      'points': points.map((p) => p.toJson()).toList(),
    };
  }

  /// Create from JSON
  factory ClipAutomationLane.fromJson(Map<String, dynamic> json) {
    final paramName = json['parameter'] as String;
    final parameter = AutomationParameter.values.firstWhere(
      (p) => p.name == paramName,
      orElse: () => AutomationParameter.volume,
    );

    return ClipAutomationLane(
      id: json['id'] as String?,
      parameter: parameter,
      points: (json['points'] as List<dynamic>?)
              ?.map((dynamic p) =>
                  ClipAutomationPoint.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// Convert points to engine CSV format with time in seconds and value in dB.
  /// clipStartSeconds: the clip's start time on timeline in seconds
  /// tempo: current project tempo
  /// Format: "time_seconds,db;time_seconds,db;..."
  String toEngineDbCsv(double clipStartSeconds, double tempo) {
    if (points.isEmpty) return '';

    final sorted = sortedPoints;
    return sorted.map((p) {
      // Convert beats to seconds: seconds = beats * 60 / tempo
      // Add clip start time to get absolute timeline position
      final timeSeconds = clipStartSeconds + (p.time * 60.0 / tempo);
      // Convert normalized (0-1) to dB
      final db = VolumeConversion.normalizedToDb(p.value);
      return '${timeSeconds.toStringAsFixed(6)},${db.toStringAsFixed(2)}';
    }).join(';');
  }
}

/// Helper class for managing automation across all parameters in a clip
@immutable
class ClipAutomation {
  final Map<AutomationParameter, ClipAutomationLane> lanes;

  const ClipAutomation({
    this.lanes = const {},
  });

  /// Create empty automation
  factory ClipAutomation.empty() => const ClipAutomation();

  /// Check if any automation exists
  bool get hasAutomation => lanes.values.any((lane) => lane.hasAutomation);

  /// Get lane for a parameter (creates empty lane if doesn't exist)
  ClipAutomationLane getLane(AutomationParameter parameter) {
    return lanes[parameter] ?? ClipAutomationLane.empty(parameter);
  }

  /// Update lane for a parameter
  ClipAutomation updateLane(AutomationParameter parameter, ClipAutomationLane lane) {
    return ClipAutomation(
      lanes: {...lanes, parameter: lane},
    );
  }

  /// Remove lane for a parameter
  ClipAutomation removeLane(AutomationParameter parameter) {
    final newLanes = Map<AutomationParameter, ClipAutomationLane>.from(lanes);
    newLanes.remove(parameter);
    return ClipAutomation(lanes: newLanes);
  }

  /// Slice all automation lanes at a specific beat position (left portion)
  ClipAutomation sliceLeft(double splitBeat) {
    return ClipAutomation(
      lanes: lanes.map((param, lane) => MapEntry(param, lane.sliceLeft(splitBeat))),
    );
  }

  /// Slice all automation lanes at a specific beat position (right portion)
  ClipAutomation sliceRight(double splitBeat) {
    return ClipAutomation(
      lanes: lanes.map((param, lane) => MapEntry(param, lane.sliceRight(splitBeat))),
    );
  }

  /// Deep copy all automation (for clip duplication)
  ClipAutomation deepCopy() {
    return ClipAutomation(
      lanes: lanes.map((param, lane) => MapEntry(param, lane.deepCopy())),
    );
  }

  /// Deselect all points in all lanes
  ClipAutomation deselectAll() {
    return ClipAutomation(
      lanes: lanes.map((param, lane) => MapEntry(param, lane.deselectAll())),
    );
  }

  ClipAutomation copyWith({
    Map<AutomationParameter, ClipAutomationLane>? lanes,
  }) {
    return ClipAutomation(
      lanes: lanes ?? this.lanes,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ClipAutomation) return false;
    return mapEquals(lanes, other.lanes);
  }

  @override
  int get hashCode => Object.hashAll(lanes.entries);

  /// Convert to JSON for serialization
  Map<String, dynamic> toJson() {
    return {
      'lanes': lanes.map((param, lane) => MapEntry(param.name, lane.toJson())),
    };
  }

  /// Create from JSON
  factory ClipAutomation.fromJson(Map<String, dynamic> json) {
    final lanesJson = json['lanes'] as Map<String, dynamic>?;
    if (lanesJson == null) return ClipAutomation.empty();

    final lanes = <AutomationParameter, ClipAutomationLane>{};
    for (final entry in lanesJson.entries) {
      final parameter = AutomationParameter.values.firstWhere(
        (p) => p.name == entry.key,
        orElse: () => AutomationParameter.volume,
      );
      lanes[parameter] = ClipAutomationLane.fromJson(entry.value as Map<String, dynamic>);
    }

    return ClipAutomation(lanes: lanes);
  }
}
