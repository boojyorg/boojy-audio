import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../theme/theme_extension.dart';
import '../../models/clip_data.dart';
import '../../models/midi_note_data.dart';
import '../../utils/track_colors.dart';
import 'painters/painters.dart';
import 'timeline_state.dart';
import '../timeline_view.dart';

/// Mixin containing clip preview builder methods for TimelineView.
/// Separates preview rendering from main timeline logic.
mixin ClipPreviewBuildersMixin on State<TimelineView>, TimelineViewStateMixin {
  /// Build ghost preview widget for MIDI clip copy drag
  List<Widget> buildCopyDragPreviews(MidiClipData sourceClip, Color trackColor, double trackHeight) {
    final clipWidth = sourceClip.duration * pixelsPerBeat;
    final totalHeight = trackHeight - 3.0;
    const headerHeight = 18.0;

    // Calculate ghost position using snapped delta from the primary dragged clip
    final dragDeltaBeats = (midiDragCurrentX - midiDragStartX) / pixelsPerBeat;

    // Calculate snapped delta based on the primary dragged clip
    var snappedDeltaBeats = dragDeltaBeats;
    if (!snapBypassActive) {
      final snapResolution = getGridSnapResolution();
      final draggedClipNewPos = midiDragStartTime + dragDeltaBeats;
      final snappedPos = (draggedClipNewPos / snapResolution).round() * snapResolution;
      snappedDeltaBeats = snappedPos - midiDragStartTime;
    }

    // Apply the snapped delta to this source clip
    final newStartBeats = (sourceClip.startTime + snappedDeltaBeats).clamp(0.0, double.infinity);
    final copyX = newStartBeats * pixelsPerBeat;

    return [
      Positioned(
        key: ValueKey('midi_clip_ghost_${sourceClip.clipId}'),
        left: copyX,
        top: 0,
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.5,
            child: SizedBox(
              width: clipWidth,
              height: totalHeight,
              child: Stack(
                children: [
                  // Background and border
                  Container(
                    decoration: BoxDecoration(
                      color: trackColor.withValues(alpha: 0.3),
                      border: Border.all(
                        color: trackColor.withValues(alpha: 0.8),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  // Content
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Column(
                      children: [
                        // Header
                        Container(
                          height: headerHeight,
                          clipBehavior: Clip.hardEdge,
                          decoration: BoxDecoration(color: trackColor),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ClipRect(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.piano,
                                  size: 10,
                                  color: context.colors.textPrimary,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    sourceClip.name,
                                    style: TextStyle(
                                      color: context.colors.textPrimary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Notes content
                        Expanded(
                          child: sourceClip.notes.isNotEmpty
                              ? LayoutBuilder(
                                  builder: (context, constraints) {
                                    return CustomPaint(
                                      size: Size(constraints.maxWidth, constraints.maxHeight),
                                      painter: MidiClipPainter(
                                        notes: sourceClip.notes,
                                        clipDuration: sourceClip.duration,
                                        loopLength: sourceClip.loopLength,
                                        trackColor: trackColor,
                                        contentStartOffset: sourceClip.contentStartOffset,
                                      ),
                                    );
                                  },
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// Build ghost preview widget for audio clip copy drag
  List<Widget> buildAudioCopyDragPreviews(ClipData sourceClip, Color trackColor, double trackHeight) {
    // Calculate width respecting warp state
    final double clipWidth;
    if (sourceClip.editData?.syncEnabled ?? false) {
      final beatsInClip = sourceClip.duration * ((sourceClip.editData?.bpm ?? 120.0) / 60.0);
      clipWidth = beatsInClip * pixelsPerBeat;
    } else {
      clipWidth = sourceClip.duration * pixelsPerSecond;
    }
    final totalHeight = trackHeight - 3.0;
    const headerHeight = 20.0;

    // Calculate ghost position using snapped delta from the primary dragged clip
    final dragDeltaSeconds = (dragCurrentX - dragStartX) / pixelsPerSecond;

    // Snap the delta: convert to beats, snap dragged clip's new position, derive delta
    final beatsPerSecond = widget.tempo / 60.0;
    final rawBeats = (dragStartTime + dragDeltaSeconds) * beatsPerSecond;
    final snappedBeats = snapToGrid(rawBeats);
    final snappedNewStartTime = snappedBeats / beatsPerSecond;
    final snappedDeltaSeconds = snappedNewStartTime - dragStartTime;

    // Apply the snapped delta to this source clip
    final newStartTime = (sourceClip.startTime + snappedDeltaSeconds).clamp(0.0, double.infinity);
    final copyX = newStartTime * pixelsPerSecond;

    return [
      Positioned(
        key: ValueKey('audio_clip_ghost_${sourceClip.clipId}'),
        left: copyX,
        top: 0,
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.5,
            child: SizedBox(
              width: clipWidth,
              height: totalHeight,
              child: Stack(
                children: [
                  // Background and border
                  Container(
                    decoration: BoxDecoration(
                      color: trackColor.withValues(alpha: 0.3),
                      border: Border.all(
                        color: trackColor.withValues(alpha: 0.8),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  // Content
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Column(
                      children: [
                        // Header
                        Container(
                          height: headerHeight,
                          clipBehavior: Clip.hardEdge,
                          decoration: BoxDecoration(color: trackColor),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ClipRect(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.audiotrack,
                                  size: 12,
                                  color: context.colors.textPrimary,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    sourceClip.fileName,
                                    style: TextStyle(
                                      color: context.colors.textPrimary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Waveform content
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              // Calculate visual gain from clip's editData
                              final clipGainDb = sourceClip.editData?.gainDb ?? 0.0;
                              final clipVisualGain = clipGainDb > -70
                                  ? math.pow(10, clipGainDb / 20).toDouble()
                                  : 0.0;
                              return CustomPaint(
                                size: Size(constraints.maxWidth, constraints.maxHeight),
                                painter: WaveformPainter(
                                  peaks: sourceClip.waveformPeaks,
                                  color: TrackColors.getLighterShade(trackColor),
                                  visualGain: clipVisualGain,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// Build ghost preview for audio clip during MIDI drag (cross-type)
  List<Widget> buildAudioCopyDragPreviewsForMidiDrag(ClipData sourceClip, Color trackColor, double trackHeight) {
    // Calculate width respecting warp state
    final double clipWidth;
    if (sourceClip.editData?.syncEnabled ?? false) {
      final beatsInClip = sourceClip.duration * ((sourceClip.editData?.bpm ?? 120.0) / 60.0);
      clipWidth = beatsInClip * pixelsPerBeat;
    } else {
      clipWidth = sourceClip.duration * pixelsPerSecond;
    }
    final totalHeight = trackHeight - 3.0;
    const headerHeight = 20.0;

    // Calculate delta from MIDI drag state (in beats), convert to seconds
    final beatsPerSecond = widget.tempo / 60.0;
    final dragDeltaBeats = (midiDragCurrentX - midiDragStartX) / pixelsPerBeat;

    // Calculate snapped delta based on MIDI drag
    var snappedDeltaBeats = dragDeltaBeats;
    if (!snapBypassActive) {
      final snapResolution = getGridSnapResolution();
      final draggedClipNewPos = midiDragStartTime + dragDeltaBeats;
      final snappedPos = (draggedClipNewPos / snapResolution).round() * snapResolution;
      snappedDeltaBeats = snappedPos - midiDragStartTime;
    }

    // Convert delta to seconds for audio clip positioning
    final snappedDeltaSeconds = snappedDeltaBeats / beatsPerSecond;

    // Apply the snapped delta to this source clip
    final newStartTime = (sourceClip.startTime + snappedDeltaSeconds).clamp(0.0, double.infinity);
    final copyX = newStartTime * pixelsPerSecond;

    return [
      Positioned(
        key: ValueKey('audio_clip_ghost_cross_${sourceClip.clipId}'),
        left: copyX,
        top: 0,
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.5,
            child: SizedBox(
              width: clipWidth,
              height: totalHeight,
              child: Stack(
                children: [
                  // Background and border
                  Container(
                    decoration: BoxDecoration(
                      color: trackColor.withValues(alpha: 0.3),
                      border: Border.all(
                        color: trackColor.withValues(alpha: 0.8),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  // Content
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Column(
                      children: [
                        // Header
                        Container(
                          height: headerHeight,
                          clipBehavior: Clip.hardEdge,
                          decoration: BoxDecoration(color: trackColor),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ClipRect(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.audiotrack,
                                  size: 12,
                                  color: context.colors.textPrimary,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    sourceClip.fileName,
                                    style: TextStyle(
                                      color: context.colors.textPrimary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Waveform content
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final clipGainDb = sourceClip.editData?.gainDb ?? 0.0;
                              final clipVisualGain = clipGainDb > -70
                                  ? math.pow(10, clipGainDb / 20).toDouble()
                                  : 0.0;
                              return CustomPaint(
                                size: Size(constraints.maxWidth, constraints.maxHeight),
                                painter: WaveformPainter(
                                  peaks: sourceClip.waveformPeaks,
                                  color: TrackColors.getLighterShade(trackColor),
                                  visualGain: clipVisualGain,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// Build ghost preview for MIDI clip during audio drag (cross-type)
  List<Widget> buildMidiCopyDragPreviewsForAudioDrag(MidiClipData sourceClip, Color trackColor, double trackHeight) {
    final clipWidth = sourceClip.duration * pixelsPerBeat;
    final totalHeight = trackHeight - 3.0;
    const headerHeight = 18.0;

    // Calculate delta from audio drag state (in seconds), convert to beats
    final beatsPerSecond = widget.tempo / 60.0;
    final dragDeltaSeconds = (dragCurrentX - dragStartX) / pixelsPerSecond;

    // Snap the delta: convert to beats, snap based on audio drag position
    final rawBeats = (dragStartTime + dragDeltaSeconds) * beatsPerSecond;
    final snappedBeats = snapToGrid(rawBeats);
    final snappedNewStartTime = snappedBeats / beatsPerSecond;
    final snappedDeltaSeconds = snappedNewStartTime - dragStartTime;

    // Convert delta to beats for MIDI clip positioning
    final snappedDeltaBeats = snappedDeltaSeconds * beatsPerSecond;

    // Apply the snapped delta to this source clip
    final newStartBeats = (sourceClip.startTime + snappedDeltaBeats).clamp(0.0, double.infinity);
    final copyX = newStartBeats * pixelsPerBeat;

    return [
      Positioned(
        key: ValueKey('midi_clip_ghost_cross_${sourceClip.clipId}'),
        left: copyX,
        top: 0,
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.5,
            child: SizedBox(
              width: clipWidth,
              height: totalHeight,
              child: Stack(
                children: [
                  // Background and border
                  Container(
                    decoration: BoxDecoration(
                      color: trackColor.withValues(alpha: 0.3),
                      border: Border.all(
                        color: trackColor.withValues(alpha: 0.8),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  // Content
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Column(
                      children: [
                        // Header
                        Container(
                          height: headerHeight,
                          clipBehavior: Clip.hardEdge,
                          decoration: BoxDecoration(color: trackColor),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ClipRect(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.piano,
                                  size: 10,
                                  color: context.colors.textPrimary,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    sourceClip.name,
                                    style: TextStyle(
                                      color: context.colors.textPrimary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Notes content
                        Expanded(
                          child: sourceClip.notes.isNotEmpty
                              ? LayoutBuilder(
                                  builder: (context, constraints) {
                                    return CustomPaint(
                                      size: Size(constraints.maxWidth, constraints.maxHeight),
                                      painter: MidiClipPainter(
                                        notes: sourceClip.notes,
                                        clipDuration: sourceClip.duration,
                                        loopLength: sourceClip.loopLength,
                                        trackColor: trackColor,
                                        contentStartOffset: sourceClip.contentStartOffset,
                                      ),
                                    );
                                  },
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// Build preview clip widget for drag-and-drop from library
  Widget buildPreviewClip(PreviewClip preview) {
    final previewDuration = preview.duration ?? 3.0;
    final clipWidth = previewDuration * pixelsPerSecond;
    final clipX = preview.startTime * pixelsPerSecond;
    final trackHeight = widget.clipHeights[preview.trackId] ?? 100.0;
    final totalHeight = trackHeight - 3.0;
    const headerHeight = 20.0;

    // Get actual track color - match how real clips get color
    final track = tracks.where((t) => t.id == preview.trackId).firstOrNull;
    final trackIndex = track != null ? tracks.indexOf(track) : 0;
    final trackColor = track != null
        ? (widget.getTrackColor?.call(track.id, track.name, track.type)
            ?? TrackColors.getTrackColor(trackIndex))
        : TrackColors.getTrackColor(0);

    return Positioned(
      left: clipX,
      top: 0,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.5,
          child: SizedBox(
            width: clipWidth,
            height: totalHeight,
            child: Stack(
              children: [
                // Background and border
                Container(
                  decoration: BoxDecoration(
                    color: trackColor.withValues(alpha: 0.3),
                    border: Border.all(
                      color: trackColor.withValues(alpha: 0.8),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                // Content
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Column(
                    children: [
                      // Header
                      Container(
                        height: headerHeight,
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(color: trackColor),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ClipRect(
                          child: Row(
                            children: [
                              Icon(
                                Icons.audiotrack,
                                size: 12,
                                color: context.colors.textPrimary,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  preview.fileName,
                                  style: TextStyle(
                                    color: context.colors.textPrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Waveform content
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            if (preview.waveformPeaks == null || preview.waveformPeaks!.isEmpty) {
                              return const SizedBox();
                            }
                            return CustomPaint(
                              size: Size(constraints.maxWidth, constraints.maxHeight),
                              painter: WaveformPainter(
                                peaks: preview.waveformPeaks!,
                                color: TrackColors.getLighterShade(trackColor),
                                contentDuration: previewDuration,
                                visibleDuration: previewDuration,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build the drag-to-create preview rectangle (empty area)
  Widget buildDragToCreatePreview() {
    // Calculate positions (handle reverse drag)
    final startBeats = math.min(newClipStartBeats, newClipEndBeats);
    final endBeats = math.max(newClipStartBeats, newClipEndBeats);
    final durationBeats = endBeats - startBeats;

    // Convert to pixels
    final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;
    final startX = (startBeats * pixelsPerBeat) - scrollOffset;
    final width = durationBeats * pixelsPerBeat;

    // Calculate bars for label
    final bars = durationBeats / 4.0;
    final barsLabel = bars >= 1.0
        ? '${bars.toStringAsFixed(bars == bars.roundToDouble() ? 0 : 1)} bar${bars != 1.0 ? 's' : ''}'
        : '${durationBeats.toStringAsFixed(1)} beats';

    return Positioned(
      left: startX,
      top: 8,
      child: Container(
        width: math.max(width, 20.0),
        height: 60,
        decoration: BoxDecoration(
          color: context.colors.success.withValues(alpha: 0.3),
          border: Border.all(
            color: context.colors.success,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            barsLabel,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  /// Build drag-to-create preview for an existing track
  Widget buildDragToCreatePreviewOnTrack(Color trackColor, double trackHeight) {
    // Calculate positions (handle reverse drag)
    final startBeats = math.min(newClipStartBeats, newClipEndBeats);
    final endBeats = math.max(newClipStartBeats, newClipEndBeats);
    final durationBeats = endBeats - startBeats;

    // Convert to pixels
    final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;
    final startX = (startBeats * pixelsPerBeat) - scrollOffset;
    final width = durationBeats * pixelsPerBeat;

    // Calculate bars for label
    final bars = durationBeats / 4.0;
    final barsLabel = bars >= 1.0
        ? '${bars.toStringAsFixed(bars == bars.roundToDouble() ? 0 : 1)} bar${bars != 1.0 ? 's' : ''}'
        : '${durationBeats.toStringAsFixed(1)} beats';

    return Positioned(
      left: startX,
      top: 0,
      child: Container(
        width: math.max(width, 20.0),
        height: trackHeight - 3,
        decoration: BoxDecoration(
          color: trackColor.withValues(alpha: 0.3),
          border: Border.all(
            color: trackColor,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            barsLabel,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  /// Build the box selection rectangle overlay
  Widget buildBoxSelectionOverlay() {
    if (!isBoxSelecting || boxSelectionStart == null || boxSelectionEnd == null) {
      return const SizedBox.shrink();
    }

    // Get horizontal scroll offset to convert X from content to visible coordinates
    final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;

    // X coordinates are in content space, convert to visible
    final visibleStartX = boxSelectionStart!.dx - scrollOffset;
    final visibleEndX = boxSelectionEnd!.dx - scrollOffset;

    // Y coordinates are already in visible space
    final visibleStartY = boxSelectionStart!.dy;
    final visibleEndY = boxSelectionEnd!.dy;

    final left = math.min(visibleStartX, visibleEndX);
    final top = math.min(visibleStartY, visibleEndY);
    final width = (visibleStartX - visibleEndX).abs();
    final height = (visibleStartY - visibleEndY).abs();

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: context.colors.accent.withValues(alpha: 0.15),
            border: Border.all(
              color: context.colors.accent,
              width: 1,
            ),
          ),
        ),
      ),
    );
  }
}
