import 'package:flutter/foundation.dart';
import '../audio_engine.dart';
import '../models/midi_note_data.dart';
import '../services/midi_playback_manager.dart';

/// Manages MIDI clip operations including selection, creation, copying, and deletion.
/// Acts as an orchestration layer between daw_screen and MidiPlaybackManager.
class MidiClipController extends ChangeNotifier {
  AudioEngine? _audioEngine;
  MidiPlaybackManager? _midiPlaybackManager;

  // Clipboard for copy/paste operations
  MidiClipData? _clipboardClip;

  // Tempo for beat/time conversions (synced from RecordingController)
  double _tempo = 120.0;

  MidiClipController();

  // Getters
  MidiClipData? get clipboardClip => _clipboardClip;
  double get tempo => _tempo;
  int? get selectedClipId => _midiPlaybackManager?.selectedClipId;
  MidiClipData? get currentEditingClip => _midiPlaybackManager?.currentEditingClip;
  List<MidiClipData> get midiClips => _midiPlaybackManager?.midiClips ?? [];

  /// Initialize with audio engine and MIDI playback manager
  void initialize(AudioEngine engine, MidiPlaybackManager manager) {
    _audioEngine = engine;
    _midiPlaybackManager = manager;
  }

  /// Update tempo (called when RecordingController tempo changes)
  void setTempo(double bpm) {
    _tempo = bpm.clamp(20.0, 300.0);
  }

  /// Convert seconds to beats using current tempo
  double secondsToBeats(double seconds) {
    final beatsPerSecond = _tempo / 60.0;
    return seconds * beatsPerSecond;
  }

  /// Convert beats to seconds using current tempo
  double beatsToSeconds(double beats) {
    final secondsPerBeat = 60.0 / _tempo;
    return beats * secondsPerBeat;
  }

  /// Select a MIDI clip for editing
  /// Returns the track ID for UI to update track selection
  int? selectClip(int? clipId, MidiClipData? clipData) {
    return _midiPlaybackManager?.selectClip(clipId, clipData);
  }

  /// Update a MIDI clip with new note data
  void updateClip(MidiClipData updatedClip, double playheadPositionSeconds) {
    final playheadPositionBeats = secondsToBeats(playheadPositionSeconds);
    _midiPlaybackManager?.updateClip(updatedClip, _tempo, playheadPositionBeats);
    notifyListeners();
  }

  /// Copy a clip to a new start time
  void copyClipToTime(MidiClipData sourceClip, double newStartTimeBeats) {
    _midiPlaybackManager?.copyClip(sourceClip, newStartTimeBeats, _tempo);
    notifyListeners();
  }

  /// Copy clip to clipboard for paste operation
  void copyToClipboard(MidiClipData clip) {
    _clipboardClip = clip;
    notifyListeners();
  }

  /// Duplicate the currently selected clip immediately after it
  void duplicateSelectedClip() {
    final clip = _midiPlaybackManager?.currentEditingClip;
    if (clip == null) return;

    // Place duplicate immediately after original
    final newStartTime = clip.startTime + clip.duration;
    _midiPlaybackManager?.copyClip(clip, newStartTime, _tempo);
    notifyListeners();
  }

  /// Delete a MIDI clip by ID
  void deleteClip(int clipId, int trackId) {
    // Get Rust clip ID before removing from Dart side
    final rustClipId = _midiPlaybackManager?.dartToRustClipIds[clipId];

    // Remove from Dart side (MidiPlaybackManager)
    _midiPlaybackManager?.removeClip(clipId);

    // Remove from Rust engine
    if (rustClipId != null) {
      _audioEngine?.removeMidiClip(trackId, rustClipId);
    }
    notifyListeners();
  }

  /// Create a default MIDI clip on a track
  MidiClipData createDefaultClip({
    required int trackId,
    double? startTimeBeats,
    double durationBeats = 16.0, // 4 bars
    String name = 'New MIDI Clip',
  }) {
    final clipId = DateTime.now().millisecondsSinceEpoch;
    return MidiClipData(
      clipId: clipId,
      trackId: trackId,
      startTime: startTimeBeats ?? 0.0,
      duration: durationBeats,
      loopLength: durationBeats,
      name: name,
      notes: [],
    );
  }

  /// Create a MIDI clip with specific parameters
  MidiClipData createClipWithParams({
    required int trackId,
    required double startTimeBeats,
    required double durationBeats,
    double? loopLengthBeats,
    String name = 'New MIDI Clip',
    List<MidiNoteData>? notes,
  }) {
    final clipId = DateTime.now().millisecondsSinceEpoch;
    return MidiClipData(
      clipId: clipId,
      trackId: trackId,
      startTime: startTimeBeats,
      duration: durationBeats,
      loopLength: loopLengthBeats ?? durationBeats,
      name: name,
      notes: notes ?? [],
    );
  }

  /// Add a clip to the manager and notify
  void addClip(MidiClipData clip) {
    _midiPlaybackManager?.addRecordedClip(clip);
    notifyListeners();
  }

  /// Clear clipboard
  void clearClipboard() {
    _clipboardClip = null;
    notifyListeners();
  }

  /// Clear all state (for new project)
  void clear() {
    _clipboardClip = null;
    notifyListeners();
  }
}
