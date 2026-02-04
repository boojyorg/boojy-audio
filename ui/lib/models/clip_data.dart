import 'package:flutter/material.dart';
import 'audio_clip_edit_data.dart';
import 'clip_automation_data.dart';
import 'midi_note_data.dart';

/// Represents an audio clip on the timeline
class ClipData {
  final int clipId;
  final int trackId;
  final String filePath;
  final double startTime; // in seconds
  final double duration; // in seconds (arrangement length - can exceed loopLength when looping)
  final double offset; // Start offset within audio file for non-destructive trimming (seconds)
  final List<double> waveformPeaks;
  final Color? color;

  /// Non-destructive editing parameters (transpose, gain, reverse, etc.)
  final AudioClipEditData? editData;

  /// Loop region length in seconds (from Audio Editor's loopEndBeats - loopStartBeats)
  /// This is the content length that repeats when canRepeat is true.
  final double loopLength;

  /// Whether looping is enabled (mirrors editData.loopEnabled from Audio Editor)
  /// When true, clip can be extended beyond loopLength and content tiles.
  /// When false, clip cannot be extended beyond loopLength.
  /// Defaults to true to match AudioClipEditData.loopEnabled default.
  final bool canRepeat;

  /// Clip-based automation data. Automation lives inside the clip and moves,
  /// copies, slices, and loops with the clip content.
  final ClipAutomation automation;

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
    this.canRepeat = true, // Default to true to match AudioClipEditData.loopEnabled
    ClipAutomation? automation,
  })  : loopLength = loopLength ?? duration, // Default loopLength to duration if not specified
        automation = automation ?? ClipAutomation.empty();

  /// Convert ClipData to JSON for project persistence
  Map<String, dynamic> toJson() {
    return {
      'clipId': clipId,
      'trackId': trackId,
      'filePath': filePath,
      'startTime': startTime,
      'duration': duration,
      'offset': offset,
      'waveformPeaks': waveformPeaks,
      'loopLength': loopLength,
      'canRepeat': canRepeat,
      if (color != null) 'color': color!.toARGB32(),
      if (editData != null) 'editData': editData!.toJson(),
      if (automation.hasAutomation) 'automation': automation.toJson(),
    };
  }

  /// Create ClipData from JSON
  factory ClipData.fromJson(Map<String, dynamic> json) {
    final duration = (json['duration'] as num).toDouble();
    return ClipData(
      clipId: json['clipId'] as int,
      trackId: json['trackId'] as int,
      filePath: json['filePath'] as String,
      startTime: (json['startTime'] as num).toDouble(),
      duration: duration,
      offset: (json['offset'] as num?)?.toDouble() ?? 0.0,
      waveformPeaks: (json['waveformPeaks'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [],
      loopLength: (json['loopLength'] as num?)?.toDouble() ?? duration,
      canRepeat: json['canRepeat'] as bool? ?? true, // Default to true to match AudioClipEditData.loopEnabled
      color: json['color'] != null ? Color(json['color'] as int) : null,
      editData: json['editData'] != null
          ? AudioClipEditData.fromJson(json['editData'] as Map<String, dynamic>)
          : null,
      automation: json['automation'] != null
          ? ClipAutomation.fromJson(json['automation'] as Map<String, dynamic>)
          : null,
    );
  }

  String get fileName {
    return filePath.split('/').last;
  }

  double get endTime => startTime + duration;

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
    bool? canRepeat,
    ClipAutomation? automation,
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
      canRepeat: canRepeat ?? this.canRepeat,
      automation: automation ?? this.automation,
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
    );
  }
}
