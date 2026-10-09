import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../utils/audio_file_names.dart';
import 'audio_clip_edit_data.dart';
import 'midi_note_data.dart';

/// Seconds below which loop lengths and starts count as equal (float noise
/// from beat/second conversions). The engine uses the same value.
const double loopEpsilon = 1e-6;

/// Where each half of a split audio clip reads the clip's audio: offset,
/// length and loop start in seconds of the clip's own audio (see
/// [ClipData.splitAt]).
typedef AudioSplit = ({
  double leftOffset,
  double leftDuration,
  double leftLoopStart,
  double rightOffset,
  double rightDuration,
  double rightLoopStart,
});

/// Represents an audio clip on the timeline
class ClipData {
  final int clipId;
  final int trackId;
  final String filePath;
  final double startTime; // in seconds
  final double
  duration; // in seconds (arrangement length - can exceed loopLength when looping)
  final double
  offset; // Start offset within audio file for non-destructive trimming (seconds)
  final List<double> waveformPeaks;
  final Color? color;

  /// Non-destructive editing parameters (transpose, gain, reverse, etc.)
  final AudioClipEditData? editData;

  /// Loop region length in seconds (from Audio Editor's loopEndBeats - loopStartBeats)
  /// This is the content length that repeats when canRepeat is true.
  final double loopLength;

  /// Where in the loop the clip begins, in seconds of its own audio: the
  /// right piece of a split repeating clip carries the pattern on.
  final double loopStart;

  /// Whether looping is enabled (mirrors editData.loopEnabled from Audio Editor)
  /// When true, clip can be extended beyond loopLength and content tiles.
  /// When false, clip cannot be extended beyond loopLength.
  /// Defaults to true to match AudioClipEditData.loopEnabled default.
  final bool canRepeat;

  ClipData({
    required this.clipId,
    required this.trackId,
    required this.filePath,
    required this.startTime,
    required this.duration,
    this.offset = 0.0,
    this.waveformPeaks = const [],
    this.color,
    this.editData,
    double? loopLength,
    this.loopStart = 0.0,
    this.canRepeat =
        true, // Default to true to match AudioClipEditData.loopEnabled
  }) : loopLength =
           loopLength ??
           duration; // Default loopLength to duration if not specified

  /// Convert ClipData to JSON for project persistence
  Map<String, dynamic> toJson() {
    return {
      'clipId': clipId,
      'trackId': trackId,
      'filePath': filePath,
      'startTime': startTime,
      'duration': duration,
      'offset': offset,
      // Waveform peaks are NOT saved: they are recomputed from the audio
      // file on load (they made the layout file ~2 MB).
      'loopLength': loopLength,
      if (loopStart > 0) 'loopStart': loopStart,
      'canRepeat': canRepeat,
      if (color != null) 'color': color!.toARGB32(),
      if (editData != null) 'editData': editData!.toJson(),
    };
  }

  /// Create ClipData from JSON.
  ///
  /// Files saved by older builds carry `waveformPeaks`; they are still read
  /// (and reused instead of recomputing) but never written back.
  factory ClipData.fromJson(Map<String, dynamic> json) {
    final duration = (json['duration'] as num).toDouble();
    return ClipData(
      clipId: json['clipId'] as int,
      trackId: json['trackId'] as int,
      filePath: json['filePath'] as String,
      startTime: (json['startTime'] as num).toDouble(),
      duration: duration,
      offset: (json['offset'] as num?)?.toDouble() ?? 0.0,
      waveformPeaks:
          (json['waveformPeaks'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [],
      loopLength: (json['loopLength'] as num?)?.toDouble() ?? duration,
      loopStart: (json['loopStart'] as num?)?.toDouble() ?? 0.0,
      canRepeat:
          json['canRepeat'] as bool? ??
          true, // Default to true to match AudioClipEditData.loopEnabled
      color: json['color'] != null ? Color(json['color'] as int) : null,
      editData: json['editData'] != null
          ? AudioClipEditData.fromJson(json['editData'] as Map<String, dynamic>)
          : null,
    );
  }

  /// The name to show for this clip (no `NNN-` bookkeeping prefix when the
  /// file sits in a project's audio folder).
  String get fileName => cleanAudioFileName(filePath);

  /// Whether the clip repeats its loop: it is longer than the loop, or
  /// begins partway into it. Mirrors the engine's `TimelineClip::active_loop`.
  bool get isLooped =>
      canRepeat &&
      loopLength > loopEpsilon &&
      (duration > loopLength + loopEpsilon || loopStart > loopEpsilon);

  /// The loop length the engine repeats (`<= 0` = no repeats).
  double get engineLoopLength => canRepeat ? loopLength : 0.0;

  /// Seconds on the timeline that [sourceSeconds] of this clip's audio fills
  /// at [projectBpm]. Duration, offset and loop length are in seconds of the
  /// clip's own audio; warp stretches that to the project tempo.
  double timelineSeconds(double sourceSeconds, double projectBpm) =>
      sourceSeconds / (editData?.stretchAt(projectBpm) ?? 1.0);

  /// Seconds the clip covers on the timeline at [projectBpm]. [duration] is
  /// in the clip's own seconds, so it is this only when the clip isn't
  /// warped: use this for anything compared with timeline positions.
  double timelineLength(double projectBpm) =>
      timelineSeconds(duration, projectBpm);

  /// Where the clip ends on the timeline at [projectBpm].
  double timelineEnd(double projectBpm) =>
      startTime + timelineLength(projectBpm);

  /// This clip with its edges moved to [start] and [end] (seconds on the
  /// timeline): a trim, an overlap trim, or dragging an edge back out. The
  /// audio under what stays never moves, however the clip plays (see
  /// [_window]). [audioSeconds] is the length of the clip's audio file,
  /// which a clip that can't repeat can't be dragged past; the returned
  /// clip's start says how far its left edge got.
  ClipData withEdges({
    required double start,
    required double end,
    required double projectBpm,
    double? audioSeconds,
  }) {
    final stretch = editData?.stretchAt(projectBpm) ?? 1.0;
    final w = _window(
      (start - startTime) * stretch,
      (end - start) * stretch,
      audioSeconds,
    );
    return copyWith(
      startTime: startTime + w.from / stretch,
      offset: w.offset,
      duration: w.duration,
      loopStart: w.loopStart,
    );
  }

  /// Where in its audio the clip's loop begins (the Audio Editor's loop
  /// Start). A clip that doesn't repeat yet plays from its loop's top;
  /// reversed, from its loop's end, so the loop ends where its window does.
  double get loopWindowStart {
    if (isLooped || !(editData?.reversed ?? false)) return offset;
    return math.max(0.0, offset + duration - loopLength);
  }

  /// This clip repeating the [length] seconds of its audio from [start]
  /// (the Audio Editor's loop region), played from the region's beginning.
  ClipData withLoopWindow(double start, double length) {
    final moved = copyWith(offset: start, loopLength: length, loopStart: 0.0);
    // Inside one pass a reversed clip is the plain window at the loop's end.
    if ((editData?.reversed ?? false) && duration <= length + loopEpsilon) {
      return moved.copyWith(offset: start + length - duration);
    }
    return moved;
  }

  /// This clip as one plain window of its audio, starting where it does
  /// now: what it becomes when Loop is turned off, since the engine reads a
  /// loop start only while the clip can repeat.
  ClipData asOneWindow() {
    if (loopStart <= loopEpsilon) return this;
    final reversed = editData?.reversed ?? false;
    return copyWith(
      offset: reversed
          ? math.max(0.0, offset + loopLength - loopStart - duration)
          : offset + loopStart,
      loopStart: 0.0,
    );
  }

  /// Split at [splitTime] (seconds on the timeline): each piece keeps the
  /// audio it had (see [withEdges]). Warp stretches the timeline distance
  /// into the clip's own seconds.
  AudioSplit splitAt(double splitTime, double projectBpm) {
    final cut =
        (splitTime - startTime) * (editData?.stretchAt(projectBpm) ?? 1.0);
    final left = _window(0.0, cut, null);
    final right = _window(cut, duration - cut, null);
    return (
      leftOffset: left.offset,
      leftDuration: cut,
      leftLoopStart: left.loopStart,
      rightOffset: right.offset,
      rightDuration: duration - cut,
      rightLoopStart: right.loopStart,
    );
  }

  /// Where the stretch of this clip from [from] to [from] + [length]
  /// seconds (of its own audio, counted from the clip's start; either end
  /// may lie outside the clip) reads its audio.
  ///
  /// A clip that can repeat (Loop on) is a window onto its loop, repeated
  /// both ways: the loop is [loopLength] seconds of audio from [offset], and
  /// the clip enters it [loopStart] seconds in. Moving an edge changes only
  /// how far in the clip enters and how long it is, so the pattern stays
  /// where it is; a piece that starts at the loop's top and fits in one pass
  /// is the plain window the engine plays without the loop. A clip that
  /// can't repeat (Loop off) plays one window of its audio, which an edge
  /// can uncover up to the file's ends.
  ///
  /// A reversed clip plays each pass backwards, so its audio is counted from
  /// the window's end: dragging its left edge in cuts the end of its audio.
  ({double offset, double duration, double loopStart, double from}) _window(
    double from,
    double length,
    double? audioSeconds,
  ) {
    final reversed = editData?.reversed ?? false;
    if (canRepeat && loopLength > loopEpsilon) {
      final loop = loopLength;
      // Where the clip's loop starts in the audio, and how far into it the
      // clip starts. A clip that doesn't repeat yet plays from the loop's
      // top; reversed, its window's end is the loop's end. (One whose
      // window ends too early for that came from an older trim: enter its
      // loop further in instead, which plays the same.)
      var windowStart = loopWindowStart;
      var phase = isLooped ? loopStart : 0.0;
      if (!isLooped && reversed && offset + duration - loop < -loopEpsilon) {
        windowStart = offset;
        phase = loop - duration;
      }
      var into = (phase + from) % loop;
      if (into < loopEpsilon || loop - into < loopEpsilon) into = 0.0;
      if (into == 0.0 && length <= loop + loopEpsilon) {
        return (
          offset: reversed ? windowStart + loop - length : windowStart,
          duration: length,
          loopStart: 0.0,
          from: from,
        );
      }
      return (
        offset: windowStart,
        duration: length,
        loopStart: into,
        from: from,
      );
    }
    // One window: the clip x seconds in plays the audio at offset + x
    // (reversed: offset + duration - x), which must lie inside the file.
    final file = audioSeconds ?? double.infinity;
    final lowest = reversed ? offset + duration - file : -offset;
    final highest = reversed ? offset + duration : file - offset;
    final lo = math.max(from, lowest);
    final hi = math.min(from + length, highest);
    return (
      offset: reversed ? offset + duration - hi : offset + lo,
      duration: math.max(0.0, hi - lo),
      loopStart: 0.0,
      from: lo,
    );
  }

  ClipData copyWith({
    int? clipId,
    int? trackId,
    String? filePath,
    double? startTime,
    double? duration,
    double? offset,
    List<double>? waveformPeaks,
    Color? color,
    AudioClipEditData? editData,
    double? loopLength,
    double? loopStart,
    bool? canRepeat,
  }) {
    return ClipData(
      clipId: clipId ?? this.clipId,
      trackId: trackId ?? this.trackId,
      filePath: filePath ?? this.filePath,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      offset: offset ?? this.offset,
      waveformPeaks: waveformPeaks ?? this.waveformPeaks,
      color: color ?? this.color,
      editData: editData ?? this.editData,
      loopLength: loopLength ?? this.loopLength,
      loopStart: loopStart ?? this.loopStart,
      canRepeat: canRepeat ?? this.canRepeat,
    );
  }
}

/// Preview clip shown during drag operation
class PreviewClip {
  final String fileName;
  final String filePath;
  final double startTime;
  final int trackId;
  final Offset mousePosition;
  final double? duration;
  final List<double>? waveformPeaks;
  final List<MidiNoteData>? midiNotes;
  final bool isMidi;

  /// A Finder drag: position known, file unknown until drop.
  final bool isPlaceholder;

  const PreviewClip({
    required this.fileName,
    required this.filePath,
    required this.startTime,
    required this.trackId,
    required this.mousePosition,
    this.duration,
    this.waveformPeaks,
    this.midiNotes,
    this.isMidi = false,
    this.isPlaceholder = false,
  });

  PreviewClip copyWith({
    String? fileName,
    String? filePath,
    double? startTime,
    int? trackId,
    Offset? mousePosition,
    double? duration,
    List<double>? waveformPeaks,
    List<MidiNoteData>? midiNotes,
    bool? isMidi,
  }) {
    return PreviewClip(
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      startTime: startTime ?? this.startTime,
      trackId: trackId ?? this.trackId,
      mousePosition: mousePosition ?? this.mousePosition,
      duration: duration ?? this.duration,
      waveformPeaks: waveformPeaks ?? this.waveformPeaks,
      midiNotes: midiNotes ?? this.midiNotes,
      isMidi: isMidi ?? this.isMidi,
      isPlaceholder: isPlaceholder,
    );
  }
}
