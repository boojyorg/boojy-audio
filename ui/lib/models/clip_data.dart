import 'package:flutter/material.dart';
import '../utils/audio_file_names.dart';
import 'audio_clip_edit_data.dart';
import 'midi_note_data.dart';

/// Seconds below which loop lengths and starts count as equal (float noise
/// from beat/second conversions). The engine uses the same value.
const double loopEpsilon = 1e-6;

/// Where each half of a split audio clip reads the clip's audio: offset,
/// length and loop start in seconds of the clip's own audio.
typedef AudioSplit = ({
  double leftOffset,
  double leftDuration,
  double leftLoopStart,
  double rightOffset,
  double rightDuration,
  double rightLoopStart,
});

/// Split a clip [cut] seconds (of its own audio) after its start on the
/// timeline. The clip plays the window [offset], [offset] + [duration] of its
/// audio, or, when it repeats, the [loopLength] from [offset] again and
/// again, starting [loopStart] into it.
///
/// A piece inside one pass of that audio becomes an ordinary trimmed window.
/// A piece that crosses the loop's end keeps the loop and starts as far into
/// it as the cut is, so the pattern carries on. A reversed clip plays each
/// pass backwards, so a piece's audio is counted from the window's end:
/// cutting from its start gave each half the other's audio.
AudioSplit splitAudioWindow({
  required double offset,
  required double duration,
  required double cut,
  required bool reversed,
  double? loopLength,
  double loopStart = 0.0,
}) {
  final window = loopLength ?? duration;
  var rightPhase = (loopStart + cut) % window;
  if (window - rightPhase < loopEpsilon) rightPhase = 0.0;
  final left = _splitPiece(offset, window, loopStart, cut, reversed);
  final right = _splitPiece(
    offset,
    window,
    rightPhase,
    duration - cut,
    reversed,
  );
  return (
    leftOffset: left.offset,
    leftDuration: cut,
    leftLoopStart: left.loopStart,
    rightOffset: right.offset,
    rightDuration: duration - cut,
    rightLoopStart: right.loopStart,
  );
}

/// Where a piece [length] long, starting [phase] into a clip's [window] of
/// audio from [offset], reads it (see [splitAudioWindow]).
({double offset, double loopStart}) _splitPiece(
  double offset,
  double window,
  double phase,
  double length,
  bool reversed,
) {
  if (phase + length > window + loopEpsilon) {
    return (offset: offset, loopStart: phase);
  }
  return (
    offset: reversed ? offset + window - phase - length : offset + phase,
    loopStart: 0.0,
  );
}

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

  double get endTime => startTime + duration;

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

  /// [splitAudioWindow] at [splitTime] (seconds on the timeline): warp
  /// stretches the timeline distance into the clip's own seconds.
  AudioSplit splitAt(double splitTime, double projectBpm) => splitAudioWindow(
    offset: offset,
    duration: duration,
    cut: (splitTime - startTime) * (editData?.stretchAt(projectBpm) ?? 1.0),
    reversed: editData?.reversed ?? false,
    loopLength: isLooped ? loopLength : null,
    loopStart: isLooped ? loopStart : 0.0,
  );

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
