import 'package:flutter/material.dart';

/// Represents a MIDI note in the piano roll
class MidiNoteData {
  /// MIDI note number (0-127, where 60 = Middle C)
  final int note;

  /// Velocity (0-127, where 0 = silent, 127 = loudest)
  final int velocity;

  /// Start time in beats (quarter notes)
  final double startTime;

  /// Duration in beats (quarter notes)
  final double duration;

  /// Whether this note is currently selected
  final bool isSelected;

  /// Unique identifier for this note instance
  final String id;

  MidiNoteData({
    required this.note,
    required this.velocity,
    required this.startTime,
    required this.duration,
    this.isSelected = false,
    String? id,
  }) : id = id ?? '${note}_${startTime}_${DateTime.now().microsecondsSinceEpoch}';

  /// Get the end time of this note in beats
  double get endTime => startTime + duration;

  /// Get the note name (e.g., "C4", "G#5")
  String get noteName {
    const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (note ~/ 12) - 1; // MIDI note 60 = C4
    final noteName = noteNames[note % 12];
    return '$noteName$octave';
  }

  /// Get color based on velocity (FL Studio mint green style)
  Color get velocityColor {
    // FL Studio uses mint green (#7FD4A0) with brightness based on velocity
    // Higher velocity = brighter green
    final velocityNorm = velocity / 127.0;

    // Base mint green color
    const baseColor = Color(0xFF7FD4A0);

    // Adjust brightness: darker for low velocity, brighter for high velocity
    // Range from 0.4 (dark) to 1.0 (bright)
    final brightness = 0.4 + (velocityNorm * 0.6);

    // Use new Color API (.r/.g/.b return 0-1 values)
    return Color.from(
      alpha: 1.0,
      red: baseColor.r * brightness,
      green: baseColor.g * brightness,
      blue: baseColor.b * brightness,
    );
  }

  /// Convert start time from beats to seconds
  double startTimeInSeconds(double tempo) {
    // tempo = beats per minute
    // seconds = (beats / (beats per minute)) * 60
    return (startTime / tempo) * 60.0;
  }

  /// Convert duration from beats to seconds
  double durationInSeconds(double tempo) {
    return (duration / tempo) * 60.0;
  }

  /// Check if a point (in beats) intersects with this note
  bool contains(double timeInBeats, int midiNote) {
    return midiNote == note &&
           timeInBeats >= startTime &&
           timeInBeats <= endTime;
  }

  /// Check if this note overlaps with another note (same pitch)
  bool overlaps(MidiNoteData other) {
    if (note != other.note) return false;
    return (startTime < other.endTime) && (endTime > other.startTime);
  }

  /// Create a copy with modified properties
  MidiNoteData copyWith({
    int? note,
    int? velocity,
    double? startTime,
    double? duration,
    bool? isSelected,
    String? id,
  }) {
    return MidiNoteData(
      note: note ?? this.note,
      velocity: velocity ?? this.velocity,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      isSelected: isSelected ?? this.isSelected,
      id: id ?? this.id,
    );
  }

  /// Snap start time to grid
  MidiNoteData snapToGrid(double gridSize) {
    final snappedStart = (startTime / gridSize).round() * gridSize;
    return copyWith(startTime: snappedStart);
  }

  /// Quantize both start time and duration to grid
  MidiNoteData quantize(double gridSize) {
    final snappedStart = (startTime / gridSize).round() * gridSize;
    final snappedDuration = (duration / gridSize).round() * gridSize;
    return copyWith(
      startTime: snappedStart,
      duration: snappedDuration.clamp(gridSize, double.infinity),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MidiNoteData &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'MidiNoteData(note: $note ($noteName), velocity: $velocity, start: $startTime, duration: $duration)';
  }
}

/// Represents a MIDI clip containing multiple notes
class MidiClipData {
  /// Unique identifier for this clip
  final int clipId;

  /// Track this clip belongs to
  final int trackId;

  /// Start time on timeline (in BEATS - tempo-independent)
  /// Note: Convert to seconds (startTime / beatsPerSecond) when communicating with audio engine
  final double startTime;

  /// Arrangement length on timeline (in BEATS - tempo-independent)
  /// This is how long the clip appears/plays in the arrangement view
  /// Note: Convert to seconds (duration / beatsPerSecond) when communicating with audio engine
  final double duration;

  /// Loop length in piano roll (in BEATS - tempo-independent)
  /// This is the loop boundary shown in the piano roll editor
  /// When duration > loopLength, the clip content repeats
  /// When duration < loopLength, playback truncates at duration
  final double loopLength;

  /// Number of times this clip loops (DEPRECATED - use duration/loopLength instead)
  final int loopCount;

  /// List of MIDI notes in this clip
  final List<MidiNoteData> notes;

  /// Clip name
  final String name;

  /// Clip color (inherited from track)
  final Color? color;

  /// Whether this clip is muted
  final bool isMuted;

  /// Whether this clip is looping (vs one-shot)
  final bool isLooping;

  MidiClipData({
    required this.clipId,
    required this.trackId,
    required this.startTime,
    required this.duration,
    double? loopLength,
    this.loopCount = 1,
    this.notes = const [],
    this.name = 'MIDI Clip',
    this.color,
    this.isMuted = false,
    this.isLooping = false,
  }) : loopLength = loopLength ?? duration; // Default loopLength to duration if not specified

  /// Total duration including all loop iterations
  double get totalDuration => duration * loopCount;

  /// Get end time on timeline (including loops)
  double get endTime => startTime + totalDuration;

  /// Add a note to this clip
  MidiClipData addNote(MidiNoteData note) {
    return MidiClipData(
      clipId: clipId,
      trackId: trackId,
      startTime: startTime,
      duration: duration,
      loopLength: loopLength,
      loopCount: loopCount,
      notes: [...notes, note],
      name: name,
      color: color,
      isMuted: isMuted,
      isLooping: isLooping,
    );
  }

  /// Remove a note from this clip
  MidiClipData removeNote(String noteId) {
    return MidiClipData(
      clipId: clipId,
      trackId: trackId,
      startTime: startTime,
      duration: duration,
      loopLength: loopLength,
      loopCount: loopCount,
      notes: notes.where((n) => n.id != noteId).toList(),
      name: name,
      color: color,
      isMuted: isMuted,
      isLooping: isLooping,
    );
  }

  /// Update a note in this clip
  MidiClipData updateNote(String noteId, MidiNoteData updatedNote) {
    return MidiClipData(
      clipId: clipId,
      trackId: trackId,
      startTime: startTime,
      duration: duration,
      loopLength: loopLength,
      loopCount: loopCount,
      notes: notes.map((n) => n.id == noteId ? updatedNote : n).toList(),
      name: name,
      color: color,
      isMuted: isMuted,
      isLooping: isLooping,
    );
  }

  /// Get all selected notes
  List<MidiNoteData> get selectedNotes => notes.where((n) => n.isSelected).toList();

  /// Select notes within a rectangle
  MidiClipData selectNotesInRect(double startBeat, double endBeat, int minNote, int maxNote) {
    return MidiClipData(
      clipId: clipId,
      trackId: trackId,
      startTime: startTime,
      duration: duration,
      loopLength: loopLength,
      loopCount: loopCount,
      notes: notes.map((note) {
        final inTimeRange = note.startTime >= startBeat && note.endTime <= endBeat;
        final inPitchRange = note.note >= minNote && note.note <= maxNote;
        return note.copyWith(isSelected: inTimeRange && inPitchRange);
      }).toList(),
      name: name,
      color: color,
      isMuted: isMuted,
      isLooping: isLooping,
    );
  }

  /// Clear all selections
  MidiClipData clearSelection() {
    return MidiClipData(
      clipId: clipId,
      trackId: trackId,
      startTime: startTime,
      duration: duration,
      loopLength: loopLength,
      loopCount: loopCount,
      notes: notes.map((n) => n.copyWith(isSelected: false)).toList(),
      name: name,
      color: color,
      isMuted: isMuted,
      isLooping: isLooping,
    );
  }

  /// Copy with modified properties
  MidiClipData copyWith({
    int? clipId,
    int? trackId,
    double? startTime,
    double? duration,
    double? loopLength,
    int? loopCount,
    List<MidiNoteData>? notes,
    String? name,
    Color? color,
    bool? isMuted,
    bool? isLooping,
  }) {
    return MidiClipData(
      clipId: clipId ?? this.clipId,
      trackId: trackId ?? this.trackId,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      loopLength: loopLength ?? this.loopLength,
      loopCount: loopCount ?? this.loopCount,
      notes: notes ?? this.notes,
      name: name ?? this.name,
      color: color ?? this.color,
      isMuted: isMuted ?? this.isMuted,
      isLooping: isLooping ?? this.isLooping,
    );
  }
}
