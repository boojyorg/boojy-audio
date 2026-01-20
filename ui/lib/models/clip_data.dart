import 'package:flutter/material.dart';
import 'audio_clip_edit_data.dart';

/// Represents an audio clip on the timeline
class ClipData {
  final int clipId;
  final int trackId;
  final String filePath;
  final double startTime; // in seconds
  final double duration; // in seconds
  final double offset; // Start offset within audio file for non-destructive trimming (seconds)
  final List<double> waveformPeaks;
  final Color? color;

  /// Non-destructive editing parameters (transpose, gain, reverse, etc.)
  final AudioClipEditData? editData;

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
  });

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
      if (color != null) 'color': color!.toARGB32(),
      if (editData != null) 'editData': editData!.toJson(),
    };
  }

  /// Create ClipData from JSON
  factory ClipData.fromJson(Map<String, dynamic> json) {
    return ClipData(
      clipId: json['clipId'] as int,
      trackId: json['trackId'] as int,
      filePath: json['filePath'] as String,
      startTime: (json['startTime'] as num).toDouble(),
      duration: (json['duration'] as num).toDouble(),
      offset: (json['offset'] as num?)?.toDouble() ?? 0.0,
      waveformPeaks: (json['waveformPeaks'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [],
      color: json['color'] != null ? Color(json['color'] as int) : null,
      editData: json['editData'] != null
          ? AudioClipEditData.fromJson(json['editData'] as Map<String, dynamic>)
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
    );
  }
}

/// Preview clip shown during drag operation
class PreviewClip {
  final String fileName;
  final double startTime;
  final int trackId;
  final Offset mousePosition;

  PreviewClip({
    required this.fileName,
    required this.startTime,
    required this.trackId,
    required this.mousePosition,
  });
}
