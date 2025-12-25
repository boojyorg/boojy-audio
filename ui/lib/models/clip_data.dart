import 'package:flutter/material.dart';

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

  ClipData({
    required this.clipId,
    required this.trackId,
    required this.filePath,
    required this.startTime,
    required this.duration,
    this.offset = 0.0,
    this.waveformPeaks = const [],
    this.color,
  });

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
