/// Represents a MIDI event with timestamp
///
/// Used for MIDI capture buffer to enable retroactive recording
class MidiEvent {
  final int note;
  final int velocity;
  final bool isNoteOn; // true for note on, false for note off
  final DateTime timestamp;
  final double beatsFromStart; // Position in beats relative to capture start

  const MidiEvent({
    required this.note,
    required this.velocity,
    required this.isNoteOn,
    required this.timestamp,
    required this.beatsFromStart,
  });

  /// Create a note-on event
  factory MidiEvent.noteOn({
    required int note,
    required int velocity,
    required DateTime timestamp,
    required double beatsFromStart,
  }) {
    return MidiEvent(
      note: note,
      velocity: velocity,
      isNoteOn: true,
      timestamp: timestamp,
      beatsFromStart: beatsFromStart,
    );
  }

  /// Create a note-off event
  factory MidiEvent.noteOff({
    required int note,
    required DateTime timestamp,
    required double beatsFromStart,
  }) {
    return MidiEvent(
      note: note,
      velocity: 0,
      isNoteOn: false,
      timestamp: timestamp,
      beatsFromStart: beatsFromStart,
    );
  }

  /// Create MidiEvent from JSON
  factory MidiEvent.fromJson(Map<String, dynamic> json) {
    return MidiEvent(
      note: json['note'] as int,
      velocity: json['velocity'] as int,
      isNoteOn: json['isNoteOn'] as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
      beatsFromStart: (json['beatsFromStart'] as num).toDouble(),
    );
  }

  /// Convert MidiEvent to JSON
  Map<String, dynamic> toJson() {
    return {
      'note': note,
      'velocity': velocity,
      'isNoteOn': isNoteOn,
      'timestamp': timestamp.toIso8601String(),
      'beatsFromStart': beatsFromStart,
    };
  }

  @override
  String toString() {
    return 'MidiEvent(${isNoteOn ? 'ON' : 'OFF'} note=$note vel=$velocity beats=$beatsFromStart)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is MidiEvent &&
        other.note == note &&
        other.velocity == velocity &&
        other.isNoteOn == isNoteOn &&
        other.timestamp == timestamp &&
        other.beatsFromStart == beatsFromStart;
  }

  @override
  int get hashCode {
    return Object.hash(
      note,
      velocity,
      isNoteOn,
      timestamp,
      beatsFromStart,
    );
  }
}
