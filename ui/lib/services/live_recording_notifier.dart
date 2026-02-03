import 'package:flutter/foundation.dart';
import '../models/midi_note_data.dart';

/// Tracks an active (held) note during live recording
class _ActiveNote {
  final int note;
  final int velocity;
  final double startBeat; // relative to clip start (beat 0)

  _ActiveNote({
    required this.note,
    required this.velocity,
    required this.startBeat,
  });
}

/// Service that builds live MidiClipData from Rust engine events during recording.
///
/// Polls the engine's MIDI recorder via CSV at 33ms intervals, pairs NoteOn/NoteOff
/// events into MidiNoteData, and tracks held notes whose duration extends in real-time.
class LiveRecordingNotifier extends ChangeNotifier {
  /// Sentinel clip ID used to identify the live recording clip
  static const int liveClipId = -999;

  static const double _sampleRate = 48000.0;

  // Completed notes (NoteOn paired with NoteOff)
  final List<MidiNoteData> _completedNotes = [];

  // Active notes (NoteOn without matching NoteOff yet) — key is MIDI note number
  final Map<int, _ActiveNote> _activeNotes = {};

  // Recording state
  double _recordingStartBeat = 0.0;
  double _currentBeat = 0.0;
  int _trackId = 0;
  bool _isActive = false;
  String _clipName = 'Recording';

  // Incremental event processing — track how many events we've already processed
  int _lastProcessedEventCount = 0;

  // Getters
  bool get isActive => _isActive;
  int get trackId => _trackId;

  /// Start a new live recording session
  void startRecording({
    required double startBeat,
    required int trackId,
    String clipName = 'Recording',
  }) {
    _completedNotes.clear();
    _activeNotes.clear();
    _recordingStartBeat = startBeat;
    _currentBeat = startBeat;
    _trackId = trackId;
    _clipName = clipName;
    _isActive = true;
    _lastProcessedEventCount = 0;
    notifyListeners();
  }

  /// Process engine events CSV and update live note data.
  ///
  /// CSV format: "note,velocity,type,timestamp_samples;..."
  /// type: 0=NoteOff, 1=NoteOn
  ///
  /// Uses incremental processing: only parses events beyond [_lastProcessedEventCount].
  void processEngineEvents(String eventsCSV, double currentBeat, double tempo) {
    if (!_isActive) return;

    _currentBeat = currentBeat;

    if (eventsCSV.isEmpty) {
      notifyListeners();
      return;
    }

    final entries = eventsCSV.split(';');
    final totalEvents = entries.length;

    // Only process new events since last poll
    if (totalEvents <= _lastProcessedEventCount) {
      // No new events, but still notify for held-note duration updates
      notifyListeners();
      return;
    }

    final beatsPerSecond = tempo / 60.0;

    for (int i = _lastProcessedEventCount; i < totalEvents; i++) {
      final parts = entries[i].split(',');
      if (parts.length < 4) continue;

      final note = int.tryParse(parts[0]);
      final velocity = int.tryParse(parts[1]);
      final type = int.tryParse(parts[2]);
      final timestampSamples = int.tryParse(parts[3]);

      if (note == null || velocity == null || type == null || timestampSamples == null) continue;

      // Convert sample timestamp to beats (relative to clip start = beat 0)
      final beatPosition = (timestampSamples / _sampleRate) * beatsPerSecond;

      if (type == 1) {
        // NoteOn — add to active notes
        _activeNotes[note] = _ActiveNote(
          note: note,
          velocity: velocity,
          startBeat: beatPosition,
        );
      } else {
        // NoteOff — finalize the active note into a completed note
        final active = _activeNotes.remove(note);
        if (active != null) {
          final duration = (beatPosition - active.startBeat).clamp(0.01, double.infinity);
          _completedNotes.add(MidiNoteData(
            note: active.note,
            velocity: active.velocity,
            startTime: active.startBeat,
            duration: duration,
          ));
        }
      }
    }

    _lastProcessedEventCount = totalEvents;
    notifyListeners();
  }

  /// Build a live MidiClipData snapshot for rendering.
  ///
  /// Completed notes have their final duration.
  /// Active (held) notes have duration extended to current playhead beat.
  MidiClipData? buildLiveClipData() {
    if (!_isActive) return null;

    final clipDurationBeats = _currentBeat - _recordingStartBeat;
    if (clipDurationBeats <= 0) {
      return MidiClipData(
        clipId: liveClipId,
        trackId: _trackId,
        startTime: _recordingStartBeat,
        duration: 0.01, // minimal width so clip is visible
        name: _clipName,
      );
    }

    // Build notes list: completed + active (with live-extending duration)
    final allNotes = <MidiNoteData>[..._completedNotes];

    for (final active in _activeNotes.values) {
      final liveDuration = (clipDurationBeats - active.startBeat).clamp(0.01, double.infinity);
      allNotes.add(MidiNoteData(
        note: active.note,
        velocity: active.velocity,
        startTime: active.startBeat,
        duration: liveDuration,
      ));
    }

    return MidiClipData(
      clipId: liveClipId,
      trackId: _trackId,
      startTime: _recordingStartBeat,
      duration: clipDurationBeats,
      loopLength: clipDurationBeats,
      notes: allNotes,
      name: _clipName,
      canRepeat: false,
    );
  }

  /// Clear all live recording state
  void clear() {
    _completedNotes.clear();
    _activeNotes.clear();
    _isActive = false;
    _lastProcessedEventCount = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _completedNotes.clear();
    _activeNotes.clear();
    super.dispose();
  }
}
