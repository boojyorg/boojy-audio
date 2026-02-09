import '../models/clip_data.dart';
import '../models/midi_note_data.dart';
import '../widgets/timeline/gestures/midi_clip_gestures.dart';

/// Minimum clip size (beats for MIDI, seconds for audio).
/// Clips trimmed smaller than this are deleted instead.
const double _minClipSize = 0.25;

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

/// Result of resolving audio clip overlaps.
class AudioOverlapResult {
  /// Clips fully covered by the new region — remove entirely.
  final List<ClipData> removals;

  /// Clips trimmed at start or end. Each entry holds original + updated state.
  final List<AudioClipUpdate> updates;

  /// Clips split into two parts. The original should be removed and
  /// Part A / Part B created in its place.
  final List<AudioSplitOperation> splits;

  const AudioOverlapResult({
    this.removals = const [],
    this.updates = const [],
    this.splits = const [],
  });

  bool get hasChanges =>
      removals.isNotEmpty || updates.isNotEmpty || splits.isNotEmpty;
}

class AudioClipUpdate {
  final ClipData original;
  final ClipData updated;
  const AudioClipUpdate({required this.original, required this.updated});
}

class AudioSplitOperation {
  /// The original clip being split (will be removed).
  final ClipData original;

  /// Part A (left portion). Null if duration < minClipSize.
  final ClipData? partA;

  /// Part B template (right portion). Has clipId = -1 as placeholder;
  /// the caller must assign a real clipId from engine.duplicateAudioClip().
  final ClipData? partBTemplate;

  const AudioSplitOperation({
    required this.original,
    this.partA,
    this.partBTemplate,
  });
}

/// Result of resolving MIDI clip overlaps.
class MidiOverlapResult {
  /// Clips fully covered — remove entirely.
  final List<MidiClipData> removals;

  /// Clips trimmed at start or end.
  final List<MidiClipUpdate> updates;

  /// Clips split into two parts. Original removed, parts added.
  final List<MidiSplitOperation> splits;

  const MidiOverlapResult({
    this.removals = const [],
    this.updates = const [],
    this.splits = const [],
  });

  bool get hasChanges =>
      removals.isNotEmpty || updates.isNotEmpty || splits.isNotEmpty;
}

class MidiClipUpdate {
  final MidiClipData original;
  final MidiClipData updated;
  const MidiClipUpdate({required this.original, required this.updated});
}

class MidiSplitOperation {
  /// The original clip being split (will be removed).
  final MidiClipData original;

  /// Part A (left portion). Null if duration < minClipSize.
  final MidiClipData? partA;

  /// Part B (right portion). Null if duration < minClipSize.
  final MidiClipData? partB;

  const MidiSplitOperation({required this.original, this.partA, this.partB});
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

/// Resolves clip overlaps using "new clip always wins" semantics.
///
/// Handles 4 overlap scenarios for each existing clip:
/// 1. **Complete cover**: new covers existing entirely → delete existing
/// 2. **Overlaps end**: new starts inside existing → trim existing end
/// 3. **Overlaps start**: new ends inside existing → trim existing start
/// 4. **Inside existing**: new is inside existing → split into two parts
///
/// Returns a pure result describing the operations needed. The caller is
/// responsible for applying the result to the engine and UI state.
class ClipOverlapHandler {
  static int _clipIdCounter = 0;

  /// Generate a unique clip ID for split parts.
  static int generateUniqueClipId() {
    return DateTime.now().microsecondsSinceEpoch + (++_clipIdCounter);
  }

  /// Resolve overlaps between a new audio region and existing audio clips.
  ///
  /// [newStart] / [newEnd] define the new clip's time range (seconds).
  /// [existingClips] is all audio clips (handler filters by trackId).
  /// [excludeClipId] skips a clip (useful for move operations).
  static AudioOverlapResult resolveAudioOverlaps({
    required double newStart,
    required double newEnd,
    required List<ClipData> existingClips,
    required int trackId,
    int? excludeClipId,
  }) {
    final removals = <ClipData>[];
    final updates = <AudioClipUpdate>[];
    final splits = <AudioSplitOperation>[];

    final trackClips = existingClips.where((c) => c.trackId == trackId && c.clipId != excludeClipId).toList();
    print('[OVERLAP] resolveAudioOverlaps: new region ${newStart.toStringAsFixed(3)}-${newEnd.toStringAsFixed(3)}s on track $trackId, checking ${trackClips.length} clips (exclude=$excludeClipId)');

    for (final clip in existingClips) {
      if (clip.trackId != trackId) continue;
      if (clip.clipId == excludeClipId) continue;

      final clipEnd = clip.startTime + clip.duration;

      // No overlap — skip
      if (newEnd <= clip.startTime || newStart >= clipEnd) continue;

      // Case 1: Complete cover → delete
      if (newStart <= clip.startTime && newEnd >= clipEnd) {
        print('[OVERLAP]   Case 1 COMPLETE COVER: clip ${clip.clipId} (${clip.startTime.toStringAsFixed(3)}-${clipEnd.toStringAsFixed(3)}s) → DELETE');
        removals.add(clip);
        continue;
      }

      // Case 2: New overlaps end of existing → trim existing end
      if (newStart > clip.startTime && newStart < clipEnd && newEnd >= clipEnd) {
        final newDuration = newStart - clip.startTime;
        if (newDuration < _minClipSize) {
          print('[OVERLAP]   Case 2 TRIM END: clip ${clip.clipId} too small (${newDuration.toStringAsFixed(3)}s) → DELETE');
          removals.add(clip);
        } else {
          print('[OVERLAP]   Case 2 TRIM END: clip ${clip.clipId} duration ${clip.duration.toStringAsFixed(3)} → ${newDuration.toStringAsFixed(3)}s');
          updates.add(AudioClipUpdate(
            original: clip,
            updated: clip.copyWith(duration: newDuration),
          ));
        }
        continue;
      }

      // Case 3: New overlaps start of existing → trim existing start
      if (newEnd > clip.startTime &&
          newEnd < clipEnd &&
          newStart <= clip.startTime) {
        final newDuration = clipEnd - newEnd;
        if (newDuration < _minClipSize) {
          print('[OVERLAP]   Case 3 TRIM START: clip ${clip.clipId} too small (${newDuration.toStringAsFixed(3)}s) → DELETE');
          removals.add(clip);
        } else {
          final trimDelta = newEnd - clip.startTime;
          print('[OVERLAP]   Case 3 TRIM START: clip ${clip.clipId} start ${clip.startTime.toStringAsFixed(3)} → ${newEnd.toStringAsFixed(3)}s, duration ${clip.duration.toStringAsFixed(3)} → ${newDuration.toStringAsFixed(3)}s');
          updates.add(AudioClipUpdate(
            original: clip,
            updated: clip.copyWith(
              startTime: newEnd,
              duration: newDuration,
              offset: clip.offset + trimDelta,
            ),
          ));
        }
        continue;
      }

      // Case 4: New is inside existing → split into Part A + Part B
      if (newStart > clip.startTime && newEnd < clipEnd) {
        final partADuration = newStart - clip.startTime;
        final partBDuration = clipEnd - newEnd;
        final trimDelta = newEnd - clip.startTime;

        print('[OVERLAP]   Case 4 SPLIT: clip ${clip.clipId} (${clip.startTime.toStringAsFixed(3)}-${clipEnd.toStringAsFixed(3)}s) → partA=${partADuration.toStringAsFixed(3)}s, partB=${partBDuration.toStringAsFixed(3)}s');

        ClipData? partA;
        if (partADuration >= _minClipSize) {
          partA = clip.copyWith(duration: partADuration);
        }

        ClipData? partBTemplate;
        if (partBDuration >= _minClipSize) {
          partBTemplate = clip.copyWith(
            clipId: -1, // Placeholder — caller assigns from engine
            startTime: newEnd,
            duration: partBDuration,
            offset: clip.offset + trimDelta,
          );
        }

        splits.add(AudioSplitOperation(
          original: clip,
          partA: partA,
          partBTemplate: partBTemplate,
        ));
        continue;
      }
    }

    if (removals.isEmpty && updates.isEmpty && splits.isEmpty) {
      print('[OVERLAP]   No overlaps found');
    }

    return AudioOverlapResult(
      removals: removals,
      updates: updates,
      splits: splits,
    );
  }

  /// Resolve overlaps between a new MIDI region and existing MIDI clips.
  ///
  /// [newStart] / [newEnd] define the new clip's time range (beats).
  /// [existingClips] is all MIDI clips (handler filters by trackId).
  /// [excludeClipId] skips a clip (useful for move operations).
  static MidiOverlapResult resolveMidiOverlaps({
    required double newStart,
    required double newEnd,
    required List<MidiClipData> existingClips,
    required int trackId,
    int? excludeClipId,
  }) {
    final removals = <MidiClipData>[];
    final updates = <MidiClipUpdate>[];
    final splits = <MidiSplitOperation>[];

    final trackClips = existingClips.where((c) => c.trackId == trackId && c.clipId != excludeClipId).toList();
    print('[OVERLAP] resolveMidiOverlaps: new region ${newStart.toStringAsFixed(3)}-${newEnd.toStringAsFixed(3)} beats on track $trackId, checking ${trackClips.length} clips (exclude=$excludeClipId)');

    for (final clip in existingClips) {
      if (clip.trackId != trackId) continue;
      if (clip.clipId == excludeClipId) continue;

      final clipEnd = clip.startTime + clip.duration;

      // No overlap — skip
      if (newEnd <= clip.startTime || newStart >= clipEnd) continue;

      // Case 1: Complete cover → delete
      if (newStart <= clip.startTime && newEnd >= clipEnd) {
        print('[OVERLAP]   Case 1 COMPLETE COVER: MIDI clip ${clip.clipId} "${clip.name}" (${clip.startTime.toStringAsFixed(3)}-${clipEnd.toStringAsFixed(3)} beats) → DELETE');
        removals.add(clip);
        continue;
      }

      // Case 2: New overlaps end of existing → trim existing end
      if (newStart > clip.startTime && newStart < clipEnd && newEnd >= clipEnd) {
        final newDuration = newStart - clip.startTime;
        if (newDuration < _minClipSize) {
          print('[OVERLAP]   Case 2 TRIM END: MIDI clip ${clip.clipId} too small (${newDuration.toStringAsFixed(3)} beats) → DELETE');
          removals.add(clip);
        } else {
          print('[OVERLAP]   Case 2 TRIM END: MIDI clip ${clip.clipId} duration ${clip.duration.toStringAsFixed(3)} → ${newDuration.toStringAsFixed(3)} beats');
          updates.add(MidiClipUpdate(
            original: clip,
            updated: clip.copyWith(duration: newDuration),
          ));
        }
        continue;
      }

      // Case 3: New overlaps start of existing → trim existing start
      if (newEnd > clip.startTime &&
          newEnd < clipEnd &&
          newStart <= clip.startTime) {
        final newDuration = clipEnd - newEnd;
        if (newDuration < _minClipSize) {
          print('[OVERLAP]   Case 3 TRIM START: MIDI clip ${clip.clipId} too small (${newDuration.toStringAsFixed(3)} beats) → DELETE');
          removals.add(clip);
        } else {
          final trimOffset = newEnd - clip.startTime;
          print('[OVERLAP]   Case 3 TRIM START: MIDI clip ${clip.clipId} start ${clip.startTime.toStringAsFixed(3)} → ${newEnd.toStringAsFixed(3)} beats, duration ${clip.duration.toStringAsFixed(3)} → ${newDuration.toStringAsFixed(3)} beats');
          final adjustedNotes = MidiClipGestureUtils.adjustNotesForTrim(
            notes: clip.notes,
            trimOffset: trimOffset,
          );
          updates.add(MidiClipUpdate(
            original: clip,
            updated: clip.copyWith(
              startTime: newEnd,
              duration: newDuration,
              notes: adjustedNotes,
            ),
          ));
        }
        continue;
      }

      // Case 4: New is inside existing → split into Part A + Part B
      if (newStart > clip.startTime && newEnd < clipEnd) {
        final partADuration = newStart - clip.startTime;
        final partBDuration = clipEnd - newEnd;
        final splitOffset = newEnd - clip.startTime;

        print('[OVERLAP]   Case 4 SPLIT: MIDI clip ${clip.clipId} "${clip.name}" (${clip.startTime.toStringAsFixed(3)}-${clipEnd.toStringAsFixed(3)} beats) → partA=${partADuration.toStringAsFixed(3)}, partB=${partBDuration.toStringAsFixed(3)} beats');

        MidiClipData? partA;
        if (partADuration >= _minClipSize) {
          partA = clip.copyWith(
            clipId: generateUniqueClipId(),
            duration: partADuration,
            name: '${clip.name} (L)',
          );
        }

        MidiClipData? partB;
        if (partBDuration >= _minClipSize) {
          final adjustedNotes = MidiClipGestureUtils.adjustNotesForTrim(
            notes: clip.notes,
            trimOffset: splitOffset,
          );
          partB = clip.copyWith(
            clipId: generateUniqueClipId(),
            startTime: newEnd,
            duration: partBDuration,
            notes: adjustedNotes,
            name: '${clip.name} (R)',
          );
        }

        splits.add(MidiSplitOperation(
          original: clip,
          partA: partA,
          partB: partB,
        ));
        continue;
      }
    }

    if (removals.isEmpty && updates.isEmpty && splits.isEmpty) {
      print('[OVERLAP]   No MIDI overlaps found');
    }

    return MidiOverlapResult(
      removals: removals,
      updates: updates,
      splits: splits,
    );
  }

  // -------------------------------------------------------------------------
  // Apply helpers — execute overlap results against engine + UI
  // -------------------------------------------------------------------------

  /// Apply audio overlap result to engine and UI.
  ///
  /// Engine callbacks perform Rust FFI operations (trim, remove, duplicate).
  /// UI callbacks update the Flutter clip list.
  static void applyAudioResult({
    required AudioOverlapResult result,
    void Function(int trackId, int clipId)? engineRemoveClip,
    void Function(int trackId, int clipId, double startTime)? engineSetStartTime,
    void Function(int trackId, int clipId, double offset)? engineSetOffset,
    void Function(int trackId, int clipId, double duration)? engineSetDuration,
    int Function(int trackId, int clipId, double newStart)? engineDuplicateClip,
    void Function(int clipId)? uiRemoveClip,
    void Function(ClipData clip)? uiUpdateClip,
    void Function(ClipData clip)? uiAddClip,
  }) {
    if (!result.hasChanges) return;

    print('[OVERLAP] applyAudioResult: ${result.removals.length} removals, ${result.updates.length} updates, ${result.splits.length} splits');

    // Removals
    for (final clip in result.removals) {
      print('[OVERLAP]   APPLY REMOVE: clip ${clip.clipId} from track ${clip.trackId}');
      engineRemoveClip?.call(clip.trackId, clip.clipId);
      uiRemoveClip?.call(clip.clipId);
    }

    // Updates (trims)
    for (final update in result.updates) {
      final clip = update.updated;
      final orig = update.original;
      print('[OVERLAP]   APPLY TRIM: clip ${clip.clipId} start=${clip.startTime.toStringAsFixed(3)}s dur=${clip.duration.toStringAsFixed(3)}s offset=${clip.offset.toStringAsFixed(3)}s');
      if (clip.startTime != orig.startTime) {
        engineSetStartTime?.call(clip.trackId, clip.clipId, clip.startTime);
      }
      if (clip.offset != orig.offset) {
        engineSetOffset?.call(clip.trackId, clip.clipId, clip.offset);
      }
      if (clip.duration != orig.duration) {
        engineSetDuration?.call(clip.trackId, clip.clipId, clip.duration);
      }
      uiUpdateClip?.call(clip);
    }

    // Splits — Part B must be duplicated BEFORE modifying original
    for (final split in result.splits) {
      final orig = split.original;

      if (split.partBTemplate != null) {
        final tmpl = split.partBTemplate!;
        final partBId = engineDuplicateClip?.call(
              orig.trackId, orig.clipId, tmpl.startTime) ??
            -1;
        if (partBId > 0) {
          print('[OVERLAP]   APPLY SPLIT partB: new clip $partBId at ${tmpl.startTime.toStringAsFixed(3)}s dur=${tmpl.duration.toStringAsFixed(3)}s');
          engineSetOffset?.call(orig.trackId, partBId, tmpl.offset);
          engineSetDuration?.call(orig.trackId, partBId, tmpl.duration);
          uiAddClip?.call(tmpl.copyWith(clipId: partBId));
        }
      }

      if (split.partA != null) {
        print('[OVERLAP]   APPLY SPLIT partA: clip ${orig.clipId} trimmed to dur=${split.partA!.duration.toStringAsFixed(3)}s');
        engineSetDuration?.call(
            orig.trackId, orig.clipId, split.partA!.duration);
        uiUpdateClip?.call(split.partA!);
      } else {
        print('[OVERLAP]   APPLY SPLIT: no partA, removing original clip ${orig.clipId}');
        engineRemoveClip?.call(orig.trackId, orig.clipId);
        uiRemoveClip?.call(orig.clipId);
      }
    }
  }

  /// Apply MIDI overlap result to MIDI clip controller and playback manager.
  static void applyMidiResult({
    required MidiOverlapResult result,
    void Function(int clipId, int trackId)? deleteClip,
    void Function(MidiClipData clip)? updateClipInPlace,
    void Function(MidiClipData clip, double tempo)? rescheduleClip,
    void Function(MidiClipData clip)? addClip,
    required double tempo,
  }) {
    if (!result.hasChanges) return;

    print('[OVERLAP] applyMidiResult: ${result.removals.length} removals, ${result.updates.length} updates, ${result.splits.length} splits');

    // Removals
    for (final clip in result.removals) {
      print('[OVERLAP]   APPLY MIDI REMOVE: clip ${clip.clipId} "${clip.name}" from track ${clip.trackId}');
      deleteClip?.call(clip.clipId, clip.trackId);
    }

    // Splits: remove originals
    for (final split in result.splits) {
      print('[OVERLAP]   APPLY MIDI SPLIT REMOVE: original clip ${split.original.clipId} "${split.original.name}"');
      deleteClip?.call(split.original.clipId, split.original.trackId);
    }

    // Updates (trims)
    for (final update in result.updates) {
      print('[OVERLAP]   APPLY MIDI TRIM: clip ${update.updated.clipId} start=${update.updated.startTime.toStringAsFixed(3)} dur=${update.updated.duration.toStringAsFixed(3)} beats');
      updateClipInPlace?.call(update.updated);
      rescheduleClip?.call(update.updated, tempo);
    }

    // Splits: add new parts
    for (final split in result.splits) {
      if (split.partA != null) {
        print('[OVERLAP]   APPLY MIDI SPLIT partA: clip ${split.partA!.clipId} "${split.partA!.name}" dur=${split.partA!.duration.toStringAsFixed(3)} beats');
        addClip?.call(split.partA!);
        rescheduleClip?.call(split.partA!, tempo);
      }
      if (split.partB != null) {
        print('[OVERLAP]   APPLY MIDI SPLIT partB: clip ${split.partB!.clipId} "${split.partB!.name}" at ${split.partB!.startTime.toStringAsFixed(3)} dur=${split.partB!.duration.toStringAsFixed(3)} beats');
        addClip?.call(split.partB!);
        rescheduleClip?.call(split.partB!, tempo);
      }
    }
  }
}
