import '../../../models/clip_data.dart';
import '../../../models/midi_note_data.dart';

/// Utility class for clip manipulation operations.
/// Includes splitting, duplicating, and quantizing clips.
class ClipOperations {
  /// Split an audio clip at the given position.
  /// Returns a tuple of (leftClip, rightClip) or null if split is invalid.
  /// Automation is sliced at the split point with new edge nodes created.
  static (ClipData, ClipData)? splitAudioClip(ClipData clip, double splitTimeSeconds, {double tempo = 120.0}) {
    // Check if split point is within clip bounds
    if (splitTimeSeconds <= clip.startTime || splitTimeSeconds >= clip.endTime) {
      return null;
    }

    // Calculate split point relative to clip start (in seconds)
    final splitRelative = splitTimeSeconds - clip.startTime;

    // Convert to beats for automation slicing: beats = seconds * tempo / 60
    final splitBeat = splitRelative * tempo / 60.0;

    // Generate new clip IDs
    final leftClipId = DateTime.now().millisecondsSinceEpoch;
    final rightClipId = leftClipId + 1;

    // Slice automation at the split beat
    final leftAutomation = clip.automation.sliceLeft(splitBeat);
    final rightAutomation = clip.automation.sliceRight(splitBeat);

    // Create left clip (same start, shorter duration)
    final leftClip = clip.copyWith(
      clipId: leftClipId,
      duration: splitRelative,
      automation: leftAutomation,
    );

    // Create right clip (starts at split point, uses offset for audio position)
    final rightClip = clip.copyWith(
      clipId: rightClipId,
      startTime: splitTimeSeconds,
      duration: clip.duration - splitRelative,
      offset: clip.offset + splitRelative,
      automation: rightAutomation,
    );

    return (leftClip, rightClip);
  }

  /// Split a MIDI clip at the given beat position.
  /// Returns a tuple of (leftClip, rightClip) or null if split is invalid.
  /// Notes and automation are sliced at the split point.
  static (MidiClipData, MidiClipData)? splitMidiClip(MidiClipData clip, double splitBeat) {
    // Check if split point is within clip bounds
    if (splitBeat <= clip.startTime || splitBeat >= clip.endTime) {
      return null;
    }

    final splitRelative = splitBeat - clip.startTime;

    // Partition notes into left and right based on their start time relative to split point
    final leftNotes = <MidiNoteData>[];
    final rightNotes = <MidiNoteData>[];

    for (final note in clip.notes) {
      if (note.startTime < splitRelative) {
        // Note starts before split - goes to left clip
        // Truncate if note extends past split point
        if (note.endTime > splitRelative) {
          leftNotes.add(note.copyWith(duration: splitRelative - note.startTime));
        } else {
          leftNotes.add(note);
        }
      } else {
        // Note starts at or after split - goes to right clip
        // Adjust start time relative to right clip's start
        rightNotes.add(note.copyWith(
          startTime: note.startTime - splitRelative,
        ));
      }
    }

    // Generate new clip IDs
    final leftClipId = DateTime.now().millisecondsSinceEpoch;
    final rightClipId = leftClipId + 1;

    // Slice automation at the split beat (already in beats, relative to clip start)
    final leftAutomation = clip.automation.sliceLeft(splitRelative);
    final rightAutomation = clip.automation.sliceRight(splitRelative);

    // Create left clip
    final leftClip = clip.copyWith(
      clipId: leftClipId,
      duration: splitRelative,
      loopLength: splitRelative,
      notes: leftNotes,
      automation: leftAutomation,
    );

    // Create right clip
    final rightClip = clip.copyWith(
      clipId: rightClipId,
      startTime: splitBeat,
      duration: clip.duration - splitRelative,
      loopLength: clip.duration - splitRelative,
      notes: rightNotes,
      automation: rightAutomation,
    );

    return (leftClip, rightClip);
  }

  /// Duplicate an audio clip with a new position.
  /// Automation is deep-copied with new point IDs.
  static ClipData duplicateAudioClip(ClipData clip, double newStartTime) {
    return clip.copyWith(
      clipId: DateTime.now().millisecondsSinceEpoch,
      startTime: newStartTime,
      automation: clip.automation.deepCopy(),
    );
  }

  /// Duplicate a MIDI clip with a new position.
  /// Automation is deep-copied with new point IDs.
  static MidiClipData duplicateMidiClip(MidiClipData clip, double newStartTime) {
    return clip.copyWith(
      clipId: DateTime.now().millisecondsSinceEpoch,
      startTime: newStartTime,
      automation: clip.automation.deepCopy(),
    );
  }

  /// Quantize an audio clip's start time to the grid.
  static ClipData quantizeAudioClip(ClipData clip, double gridSizeSeconds) {
    final quantizedStart = (clip.startTime / gridSizeSeconds).round() * gridSizeSeconds;
    return clip.copyWith(startTime: quantizedStart);
  }

  /// Quantize a MIDI clip's start time to the grid.
  static MidiClipData quantizeMidiClip(MidiClipData clip, double gridSizeBeats) {
    final quantizedStart = (clip.startTime / gridSizeBeats).round() * gridSizeBeats;
    return clip.copyWith(startTime: quantizedStart);
  }

  /// Check if a point (in beats) is within a MIDI clip's bounds.
  static bool isPointInMidiClip(MidiClipData clip, double beatPosition) {
    return beatPosition >= clip.startTime && beatPosition < clip.endTime;
  }

  /// Check if a point (in seconds) is within an audio clip's bounds.
  static bool isPointInAudioClip(ClipData clip, double timeSeconds) {
    return timeSeconds >= clip.startTime && timeSeconds < clip.endTime;
  }

  /// Calculate the X position of a clip's left edge.
  static double calculateClipLeftEdgeX(double clipStartTime, double pixelsPerUnit) {
    return clipStartTime * pixelsPerUnit;
  }

  /// Calculate the X position of a clip's right edge.
  static double calculateClipRightEdgeX(double clipEndTime, double pixelsPerUnit) {
    return clipEndTime * pixelsPerUnit;
  }

  /// Calculate clip width in pixels.
  static double calculateClipWidth(double duration, double pixelsPerUnit) {
    return duration * pixelsPerUnit;
  }
}
