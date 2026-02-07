import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:cross_file/cross_file.dart';
import '../../models/clip_data.dart';
import '../../services/midi_file_service.dart';
import '../../theme/theme_extension.dart';
import 'timeline_state.dart';
import '../timeline_view.dart';

/// Mixin containing file drop and preview loading methods for TimelineView.
/// Separates file handling logic from main timeline code.
mixin TimelineFileHandlersMixin on State<TimelineView>, TimelineViewStateMixin {
  /// Handle file drop on track
  Future<void> handleFileDrop(List<XFile> files, int trackId, Offset localPosition) async {
    if (files.isEmpty || widget.audioEngine == null) return;

    final file = files.first;
    final filePath = file.path;
    final ext = filePath.split('.').last.toLowerCase();

    // Handle MIDI files via callback
    if (ext == 'mid' || ext == 'midi') {
      final startBeats = calculateBeatPosition(localPosition);
      widget.onMidiFileDroppedOnTrack?.call(trackId, filePath, startBeats);
      return;
    }

    // Only accept audio files
    if (!['wav', 'mp3', 'aif', 'aiff', 'flac'].contains(ext)) {
      return;
    }

    try {
      // Load audio file
      final clipId = widget.audioEngine!.loadAudioFile(filePath);
      if (clipId < 0) {
        return;
      }

      // Get duration and waveform
      final duration = widget.audioEngine!.getClipDuration(clipId);
      // Store high-resolution peaks (8000/sec) - LOD downsampling happens at render time
      final peakResolution = (duration * 8000).clamp(8000, 240000).toInt();
      final peaks = widget.audioEngine!.getWaveformPeaks(clipId, peakResolution);

      // Calculate drop position
      final startTime = calculateTimelinePosition(localPosition);

      // Create clip
      final clip = ClipData(
        clipId: clipId,
        trackId: trackId,
        filePath: filePath,
        startTime: startTime,
        duration: duration,
        waveformPeaks: peaks,
        color: context.colors.success,
      );

      setState(() {
        clips.add(clip);
        previewClip = null;
        dragHoveredTrackId = null;
      });

    } catch (e) {
      debugPrint('TimelineView: Error loading audio file: $e');
    }
  }

  /// Load waveform data for drag preview.
  /// Uses the engine's preview system to get duration and waveform without creating a clip.
  void loadWaveformForPreview(String filePath) {
    final engine = widget.audioEngine;
    if (engine == null) return;

    // Load file into engine's preview system
    final result = engine.previewLoadAudio(filePath);
    if (result.startsWith('Error')) return;

    final duration = engine.previewGetDuration();
    final rawPeaks = engine.previewGetWaveform(500); // Low-res for preview

    // Convert single-value peaks to [min, max] pairs
    // WaveformPainter expects [min, max, min, max, ...] format
    // Mirror the max values to create min values for proper waveform display
    final peaks = <double>[];
    for (final value in rawPeaks) {
      peaks.add(-value.abs()); // min (negative/bottom)
      peaks.add(value.abs());  // max (positive/top)
    }

    // Only update if we're still previewing this file
    if (mounted && previewWaveformPath == filePath) {
      setState(() {
        previewWaveformDuration = duration;
        previewWaveformPeaks = peaks;
      });
    }
  }

  /// Clear cached waveform preview data.
  void clearWaveformPreviewCache() {
    previewWaveformPath = null;
    previewWaveformDuration = null;
    previewWaveformPeaks = null;
  }

  /// Load MIDI note data for drag preview.
  /// Decodes the MIDI file to extract notes and duration for preview rendering.
  Future<void> loadMidiNotesForPreview(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final result = MidiFileService.decode(bytes);
      if (result.notes.isEmpty) return;

      // Calculate duration from max note end
      double maxEnd = 0;
      for (final note in result.notes) {
        final end = note.startTime + note.duration;
        if (end > maxEnd) maxEnd = end;
      }
      final durationBeats = maxEnd > 0 ? maxEnd : 4.0;

      // Only update if we're still previewing this file
      if (mounted && previewMidiFilePath == filePath) {
        setState(() {
          previewMidiDuration = durationBeats;
          previewMidiNotes = result.notes;
        });
      }
    } catch (e) {
      debugPrint('TimelineView: Error loading MIDI preview: $e');
    }
  }

  /// Clear cached MIDI preview data.
  void clearMidiPreviewCache() {
    previewMidiFilePath = null;
    previewMidiDuration = null;
    previewMidiNotes = null;
  }
}
