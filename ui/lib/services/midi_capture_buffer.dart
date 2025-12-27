import 'package:flutter/foundation.dart';
import '../models/midi_event.dart';

/// Circular buffer for capturing MIDI events for retroactive recording
///
/// Continuously captures MIDI input events for a fixed duration (default 30 seconds).
/// When user triggers "Capture MIDI", recent events are extracted and converted to a clip.
class MidiCaptureBuffer extends ChangeNotifier {
  final int maxDurationSeconds;
  final List<MidiEvent> _buffer = [];
  DateTime? _captureStartTime;
  double _currentBpm = 120.0;

  MidiCaptureBuffer({this.maxDurationSeconds = 30});

  /// Update the current BPM for beat calculation
  void updateBpm(double bpm) {
    _currentBpm = bpm;
  }

  /// Add a MIDI event to the buffer
  void addEvent(MidiEvent event) {
    final now = DateTime.now();

    // Initialize capture start time on first event
    _captureStartTime ??= now;

    // Add event to buffer
    _buffer.add(event);

    // Remove events older than max duration
    _cleanOldEvents(now);

    notifyListeners();
  }

  /// Add a note-on event
  void addNoteOn(int note, int velocity) {
    final now = DateTime.now();
    final beatsFromStart = _calculateBeatsFromStart(now);

    addEvent(MidiEvent.noteOn(
      note: note,
      velocity: velocity,
      timestamp: now,
      beatsFromStart: beatsFromStart,
    ));
  }

  /// Add a note-off event
  void addNoteOff(int note) {
    final now = DateTime.now();
    final beatsFromStart = _calculateBeatsFromStart(now);

    addEvent(MidiEvent.noteOff(
      note: note,
      timestamp: now,
      beatsFromStart: beatsFromStart,
    ));
  }

  /// Get recent events from the last N seconds
  List<MidiEvent> getRecentEvents(int durationSeconds) {
    if (_buffer.isEmpty) return [];

    final now = DateTime.now();
    final cutoffTime = now.subtract(Duration(seconds: durationSeconds));

    // Filter events within the duration
    final recentEvents = _buffer
        .where((event) => event.timestamp.isAfter(cutoffTime))
        .toList();

    // Normalize beat positions to start at 0
    if (recentEvents.isEmpty) return [];

    final firstBeat = recentEvents.first.beatsFromStart;
    return recentEvents.map((event) {
      return MidiEvent(
        note: event.note,
        velocity: event.velocity,
        isNoteOn: event.isNoteOn,
        timestamp: event.timestamp,
        beatsFromStart: event.beatsFromStart - firstBeat,
      );
    }).toList();
  }

  /// Get all events in the buffer
  List<MidiEvent> get allEvents => List.unmodifiable(_buffer);

  /// Get the number of events in the buffer
  int get eventCount => _buffer.length;

  /// Check if buffer has any events
  bool get hasEvents => _buffer.isNotEmpty;

  /// Clear the buffer
  void clear() {
    _buffer.clear();
    _captureStartTime = null;
    notifyListeners();
  }

  /// Calculate beats from capture start based on current BPM
  double _calculateBeatsFromStart(DateTime eventTime) {
    if (_captureStartTime == null) return 0.0;

    final elapsed = eventTime.difference(_captureStartTime!);
    final seconds = elapsed.inMilliseconds / 1000.0;
    final beatsPerSecond = _currentBpm / 60.0;

    return seconds * beatsPerSecond;
  }

  /// Remove events older than max duration
  void _cleanOldEvents(DateTime now) {
    final cutoffTime = now.subtract(Duration(seconds: maxDurationSeconds));

    _buffer.removeWhere((event) => event.timestamp.isBefore(cutoffTime));

    // Reset capture start time if buffer is empty
    if (_buffer.isEmpty) {
      _captureStartTime = null;
    }
  }

  /// Get a preview of recent events (for UI display)
  String getPreview(int durationSeconds) {
    final events = getRecentEvents(durationSeconds);

    if (events.isEmpty) {
      return 'No MIDI events captured in last $durationSeconds seconds';
    }

    final noteOns = events.where((e) => e.isNoteOn).length;
    final duration = events.last.beatsFromStart - events.first.beatsFromStart;

    return '$noteOns notes captured (${duration.toStringAsFixed(1)} beats)';
  }

  @override
  void dispose() {
    _buffer.clear();
    super.dispose();
  }
}
