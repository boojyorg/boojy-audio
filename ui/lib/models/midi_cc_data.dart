import 'package:uuid/uuid.dart';

/// Common MIDI CC types with their numbers and names
enum MidiCCType {
  modWheel(1, 'Mod Wheel', 0, 127),
  breath(2, 'Breath', 0, 127),
  volume(7, 'Volume', 0, 127),
  pan(10, 'Pan', 0, 127),
  expression(11, 'Expression', 0, 127),
  sustainPedal(64, 'Sustain', 0, 127),
  pitchBend(-1, 'Pitch Bend', -8192, 8191); // Special case: not a CC

  final int ccNumber;
  final String displayName;
  final int minValue;
  final int maxValue;

  const MidiCCType(this.ccNumber, this.displayName, this.minValue, this.maxValue);

  /// Get center value (useful for pan, pitch bend)
  int get centerValue => (minValue + maxValue) ~/ 2;

  /// Check if this is pitch bend (special handling)
  bool get isPitchBend => ccNumber == -1;
}

/// A single automation point in a CC lane
class MidiCCPoint {
  final String id;
  final double time; // Position in beats
  final int value; // CC value (0-127 for most, -8192 to 8191 for pitch bend)
  final bool isSelected;

  MidiCCPoint({
    String? id,
    required this.time,
    required this.value,
    this.isSelected = false,
  }) : id = id ?? const Uuid().v4();

  MidiCCPoint copyWith({
    String? id,
    double? time,
    int? value,
    bool? isSelected,
  }) {
    return MidiCCPoint(
      id: id ?? this.id,
      time: time ?? this.time,
      value: value ?? this.value,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MidiCCPoint && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// A CC automation lane containing points for a specific CC type
class MidiCCLane {
  final String id;
  final MidiCCType ccType;
  final List<MidiCCPoint> points;
  final bool isExpanded;

  MidiCCLane({
    String? id,
    required this.ccType,
    List<MidiCCPoint>? points,
    this.isExpanded = true,
  })  : id = id ?? const Uuid().v4(),
        points = points ?? [];

  /// Get sorted points by time
  List<MidiCCPoint> get sortedPoints {
    final sorted = List<MidiCCPoint>.from(points);
    sorted.sort((a, b) => a.time.compareTo(b.time));
    return sorted;
  }

  /// Get value at a specific time (linear interpolation between points)
  int getValueAtTime(double time) {
    if (points.isEmpty) return ccType.centerValue;

    final sorted = sortedPoints;

    // Before first point
    if (time <= sorted.first.time) return sorted.first.value;

    // After last point
    if (time >= sorted.last.time) return sorted.last.value;

    // Find surrounding points and interpolate
    for (int i = 0; i < sorted.length - 1; i++) {
      final p1 = sorted[i];
      final p2 = sorted[i + 1];

      if (time >= p1.time && time <= p2.time) {
        // Linear interpolation
        final t = (time - p1.time) / (p2.time - p1.time);
        return (p1.value + (p2.value - p1.value) * t).round();
      }
    }

    return ccType.centerValue;
  }

  /// Add a point to the lane
  MidiCCLane addPoint(MidiCCPoint point) {
    return copyWith(points: [...points, point]);
  }

  /// Remove a point from the lane
  MidiCCLane removePoint(String pointId) {
    return copyWith(points: points.where((p) => p.id != pointId).toList());
  }

  /// Update a point in the lane
  MidiCCLane updatePoint(String pointId, MidiCCPoint newPoint) {
    return copyWith(
      points: points.map((p) => p.id == pointId ? newPoint : p).toList(),
    );
  }

  /// Get selected points
  List<MidiCCPoint> get selectedPoints => points.where((p) => p.isSelected).toList();

  MidiCCLane copyWith({
    String? id,
    MidiCCType? ccType,
    List<MidiCCPoint>? points,
    bool? isExpanded,
  }) {
    return MidiCCLane(
      id: id ?? this.id,
      ccType: ccType ?? this.ccType,
      points: points ?? this.points,
      isExpanded: isExpanded ?? this.isExpanded,
    );
  }

  /// Convert to JSON for serialization
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ccType': ccType.ccNumber,
      'points': points.map((p) => {
        'id': p.id,
        'time': p.time,
        'value': p.value,
      }).toList(),
      'isExpanded': isExpanded,
    };
  }

  /// Create from JSON
  factory MidiCCLane.fromJson(Map<String, dynamic> json) {
    final ccNumber = json['ccType'] as int;
    final ccType = MidiCCType.values.firstWhere(
      (t) => t.ccNumber == ccNumber,
      orElse: () => MidiCCType.modWheel,
    );

    return MidiCCLane(
      id: json['id'] as String?,
      ccType: ccType,
      points: (json['points'] as List<dynamic>?)?.map((p) {
        return MidiCCPoint(
          id: p['id'] as String?,
          time: (p['time'] as num).toDouble(),
          value: (p['value'] as num).toInt(),
        );
      }).toList(),
      isExpanded: json['isExpanded'] as bool? ?? true,
    );
  }
}
