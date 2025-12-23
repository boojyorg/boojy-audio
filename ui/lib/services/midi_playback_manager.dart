import 'dart:async';
import 'package:flutter/foundation.dart';
import '../audio_engine.dart';
import '../models/midi_note_data.dart';

/// Manages MIDI clip playback, scheduling, and editing state.
///
/// Extracted from daw_screen.dart to improve maintainability.
class MidiPlaybackManager extends ChangeNotifier {
  final AudioEngine _audioEngine;

  // MIDI editing state
  int? _selectedMidiClipId;
  MidiClipData? _currentEditingClip;
  final List<MidiClipData> _midiClips = [];
  final Map<int, int> _dartToRustClipIds = {}; // Maps Dart clip ID -> Rust clip ID

  MidiPlaybackManager(this._audioEngine);

  // Getters
  int? get selectedClipId => _selectedMidiClipId;
  MidiClipData? get currentEditingClip => _currentEditingClip;
  List<MidiClipData> get midiClips => List.unmodifiable(_midiClips);
  Map<int, int> get dartToRustClipIds => Map.unmodifiable(_dartToRustClipIds);

  /// Select a MIDI clip for editing
  ///
  /// Returns the track ID of the selected clip (for UI to update track selection)
  int? selectClip(int? clipId, MidiClipData? clipData) {
    _selectedMidiClipId = clipId;
    _currentEditingClip = clipData;
    notifyListeners();

    // Return the track ID so UI can update track selection
    return clipData?.trackId;
  }

  /// Update a MIDI clip with new note data
  ///
  /// Handles clip creation and scheduling.
  /// Note: MIDI clips store startTime, duration, and loopLength in BEATS (not seconds)
  /// for tempo-independent visual layout on the timeline.
  ///
  /// Ableton-style clip model:
  /// - `duration`: Arrangement length (user-controlled via timeline resize)
  /// - `loopLength`: Piano roll loop boundary (user-controlled via piano roll)
  /// Both are preserved from the updatedClip - not auto-calculated from notes.
  void updateClip(MidiClipData updatedClip, double tempo, double playheadPosition) {
    // Check if we're editing an existing clip or need to create a new one
    if (updatedClip.clipId == -1) {
      // No clip ID provided - check if we're editing an existing clip
      if (_currentEditingClip != null && _currentEditingClip!.clipId != -1) {
        // Reuse the existing clip we're editing, preserving duration and loopLength
        _currentEditingClip = updatedClip.copyWith(
          clipId: _currentEditingClip!.clipId,
          startTime: _currentEditingClip!.startTime,
          duration: updatedClip.duration > 0 ? updatedClip.duration : _currentEditingClip!.duration,
          loopLength: updatedClip.loopLength > 0 ? updatedClip.loopLength : _currentEditingClip!.loopLength,
        );

        // Update in clips list
        final index = _midiClips.indexWhere((c) => c.clipId == _currentEditingClip!.clipId);
        if (index != -1) {
          _midiClips[index] = _currentEditingClip!;
        }
      } else if (updatedClip.notes.isNotEmpty) {
        // Create a brand new clip only if we have notes and no clip is being edited
        final newClipId = DateTime.now().millisecondsSinceEpoch;

        // Default to 4 bars (16 beats) if no duration/loopLength specified
        final defaultBeats = 16.0;
        _currentEditingClip = updatedClip.copyWith(
          clipId: newClipId,
          startTime: playheadPosition, // playheadPosition should be in beats
          duration: updatedClip.duration > 0 ? updatedClip.duration : defaultBeats,
          loopLength: updatedClip.loopLength > 0 ? updatedClip.loopLength : defaultBeats,
        );
        _selectedMidiClipId = newClipId;

        // Add to clips list for timeline visualization
        _midiClips.add(_currentEditingClip!);
      } else {
        // No notes and no existing clip - just update current editing clip
        _currentEditingClip = updatedClip;
      }
    } else {
      // Clip ID provided - preserve the clip's duration and loopLength
      _currentEditingClip = updatedClip;

      // Update in clips list
      final index = _midiClips.indexWhere((c) => c.clipId == updatedClip.clipId);
      if (index != -1) {
        _midiClips[index] = _currentEditingClip!;
      }
    }

    notifyListeners();

    // Schedule MIDI clip for playback
    if (_currentEditingClip != null) {
      _scheduleMidiClipPlayback(_currentEditingClip!, tempo);
    }
  }

  /// Schedule MIDI clip notes for playback during transport
  ///
  /// Uses the Ableton-style clip model:
  /// - `loopLength`: The loop boundary in the piano roll (notes loop at this point)
  /// - `duration`: The arrangement length (total playback time on timeline)
  ///
  /// When duration > loopLength: Notes repeat (loop) within the arrangement
  /// When duration < loopLength: Only the portion up to duration plays
  void _scheduleMidiClipPlayback(MidiClipData clip, double tempo) {
    // Check if this Dart clip already has a Rust clip
    int rustClipId;
    bool isNewClip = false;

    if (_dartToRustClipIds.containsKey(clip.clipId)) {
      // Existing clip - reuse the Rust clip ID
      rustClipId = _dartToRustClipIds[clip.clipId]!;

      // Clear existing notes (we'll re-add all of them)
      _audioEngine.clearMidiClip(rustClipId);
    } else {
      // New clip - create in Rust
      rustClipId = _audioEngine.createMidiClip();
      if (rustClipId < 0) {
        debugPrint('❌ Failed to create Rust MIDI clip');
        return;
      }
      _dartToRustClipIds[clip.clipId] = rustClipId;
      isNewClip = true;
    }

    // Ableton-style loop handling:
    // - loopLength: piano roll loop boundary (in beats)
    // - duration: arrangement length on timeline (in beats)
    // - Notes within loopLength repeat if duration > loopLength
    // - Playback stops at duration regardless of loopLength
    final beatsPerSecond = tempo / 60.0;
    final loopLengthSeconds = clip.loopLength / beatsPerSecond;

    // Calculate how many loop iterations fit within the arrangement duration
    // If duration < loopLength, we still play once but truncated
    final numLoops = clip.duration >= clip.loopLength
        ? (clip.duration / clip.loopLength).ceil()
        : 1;

    for (int loop = 0; loop < numLoops; loop++) {
      final loopOffsetBeats = loop * clip.loopLength;
      final loopOffsetSeconds = loop * loopLengthSeconds;

      for (final note in clip.notes) {
        // Only include notes that are within the loopLength boundary
        if (note.startTime >= clip.loopLength) continue;

        // Calculate note position within the arrangement
        final noteStartBeats = loopOffsetBeats + note.startTime;
        final noteEndBeats = loopOffsetBeats + note.startTime + note.duration;

        // Skip notes that start beyond the arrangement duration
        if (noteStartBeats >= clip.duration) continue;

        // Convert to seconds
        final noteStartSeconds = note.startTimeInSeconds(tempo) + loopOffsetSeconds;
        var durationSeconds = note.durationInSeconds(tempo);

        // Truncate note if it extends beyond the arrangement duration
        if (noteEndBeats > clip.duration) {
          final truncatedDurationBeats = clip.duration - noteStartBeats;
          durationSeconds = truncatedDurationBeats / beatsPerSecond;
        }

        // Also truncate if note extends beyond the loop boundary (for looped notes)
        final noteEndInLoop = note.startTime + note.duration;
        if (noteEndInLoop > clip.loopLength) {
          final truncatedDurationBeats = clip.loopLength - note.startTime;
          final truncatedSeconds = truncatedDurationBeats / beatsPerSecond;
          durationSeconds = durationSeconds < truncatedSeconds ? durationSeconds : truncatedSeconds;
        }

        // Only add if we have a positive duration
        if (durationSeconds > 0) {
          _audioEngine.addMidiNoteToClip(
            rustClipId,
            note.note,
            note.velocity,
            noteStartSeconds,
            durationSeconds,
          );
        }
      }
    }

    // Only add to timeline if this is a new clip
    // Convert clip.startTime from beats to seconds for the engine
    if (isNewClip) {
      final clipStartTimeSeconds = clip.startTime / beatsPerSecond;
      final result = _audioEngine.addMidiClipToTrack(
        clip.trackId,
        rustClipId,
        clipStartTimeSeconds,
      );

      if (result != 0) {
        debugPrint('❌ Failed to add MIDI clip to track timeline (result: $result)');
      }
    }
  }

  /// Play MIDI clip immediately (for testing/preview)
  void playClipImmediately(MidiClipData clip, double tempo) {
    for (final note in clip.notes) {
      // Trigger note on
      _audioEngine.sendMidiNoteOn(note.note, note.velocity);

      // Schedule note off after duration
      final durationMs = (note.durationInSeconds(tempo) * 1000).toInt();
      Future.delayed(Duration(milliseconds: durationMs), () {
        _audioEngine.sendMidiNoteOff(note.note, 0);
      });
    }
  }

  /// Add a recorded MIDI clip to the manager
  void addRecordedClip(MidiClipData clip) {
    _midiClips.add(clip);
    notifyListeners();
  }

  /// Copy a MIDI clip to a new position
  ///
  /// Creates a duplicate of the source clip at the specified start time.
  /// The new clip gets a unique ID and is scheduled for playback.
  void copyClip(MidiClipData sourceClip, double newStartTime, double tempo) {
    final newClipId = DateTime.now().millisecondsSinceEpoch;

    // Create a copy with new ID and position
    final copiedClip = sourceClip.copyWith(
      clipId: newClipId,
      startTime: newStartTime,
    );

    // Add to clips list
    _midiClips.add(copiedClip);

    // Schedule for playback (this will create a new Rust clip)
    _scheduleMidiClipPlayback(copiedClip, tempo);

    // Select the new clip
    _selectedMidiClipId = newClipId;
    _currentEditingClip = copiedClip;

    notifyListeners();
  }

  /// Remove a MIDI clip by ID
  void removeClip(int clipId) {
    _midiClips.removeWhere((c) => c.clipId == clipId);
    _dartToRustClipIds.remove(clipId);

    if (_selectedMidiClipId == clipId) {
      _selectedMidiClipId = null;
      _currentEditingClip = null;
    }

    notifyListeners();
  }

  /// Remove all clips for a specific track
  void removeClipsForTrack(int trackId) {
    final clipsToRemove = _midiClips.where((c) => c.trackId == trackId).toList();
    for (final clip in clipsToRemove) {
      _dartToRustClipIds.remove(clip.clipId);
    }

    _midiClips.removeWhere((c) => c.trackId == trackId);

    // Clear current editing clip if it was on this track
    if (_currentEditingClip != null && _currentEditingClip!.trackId == trackId) {
      _currentEditingClip = null;
      _selectedMidiClipId = null;
    }

    notifyListeners();
  }

  /// Clear Dart-to-Rust clip ID mappings (e.g., when loading a new project)
  void clearClipIdMappings() {
    _dartToRustClipIds.clear();
  }

  /// Clear all MIDI state (for new project)
  void clear() {
    _midiClips.clear();
    _dartToRustClipIds.clear();
    _selectedMidiClipId = null;
    _currentEditingClip = null;
    notifyListeners();
  }
}
