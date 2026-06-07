part of '../timeline_view.dart';

/// Track row list and per-track clip area wiring for [TimelineView].
mixin TimelineTrackListMixin
    on
        State<TimelineView>,
        TimelineViewStateMixin,
        ClipPreviewBuildersMixin,
        TimelineFileHandlersMixin,
        TimelineContextMenusMixin,
        TimelineGestureLayerMixin {
  Widget _buildTracks(
    double width,
    double totalBeats, {
    double emptyAreaHeight = 100.0,
  }) {
    // Only show empty state if audio engine is not initialized
    // Master track should always exist, so empty tracks means audio engine issue
    if (tracks.isEmpty && widget.audioEngine == null) {
      // Show empty state only if no audio engine
      return Container(
        height: 200,
        color: context.colors.editor,
        child: Center(
          child: Text(
            'Audio engine not initialized',
            style: TextStyle(color: context.colors.textMuted, fontSize: 14),
          ),
        ),
      );
    }

    // Regular tracks (excluding returns and master). Returns are rendered
    // outside this widget (in timeline_view, pinned above the master section)
    // so the visual order matches the mixer: regular → returns → master.
    final regularTracks = tracks
        .where(
          (t) =>
              t.type.toLowerCase() != 'master' &&
              t.type.toLowerCase() != 'return',
        )
        .toList();

    // Count audio and MIDI tracks for numbering
    int audioCount = 0;
    int midiCount = 0;

    return Column(
      mainAxisSize: MainAxisSize.min, // Don't expand, use actual content size
      children: [
        // Regular tracks (with automation lanes inside when visible)
        ...regularTracks.asMap().entries.map((entry) {
          final index = entry.key;
          final track = entry.value;

          // Increment counters for track numbering
          if (track.type.toLowerCase() == 'audio') {
            audioCount++;
          } else if (track.type.toLowerCase() == 'midi') {
            midiCount++;
          }

          // Use auto-detected color with override support, fallback to index-based
          final trackColor =
              widget.getTrackColor?.call(track.id, track.name, track.type) ??
              TrackColors.getTrackColor(index);
          final currentAudioCount = track.type.toLowerCase() == 'audio'
              ? audioCount
              : 0;
          final currentMidiCount = track.type.toLowerCase() == 'midi'
              ? midiCount
              : 0;

          // Check if automation is visible for this track
          final showAutomation =
              UIConstants.enableAutomation &&
              widget.automationVisibleTrackId == track.id;

          return RepaintBoundary(
            child: _buildTrack(
              width,
              track,
              trackColor,
              currentAudioCount,
              currentMidiCount,
              showAutomation: showAutomation,
              totalBeats: totalBeats,
              laneIndex: index,
            ),
          );
        }),

        // Empty space drop target - fills remaining viewport height
        // Supports: instruments, VST3 plugins, audio files, AND drag-to-create
        SizedBox(
          height: emptyAreaHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (details) {
              final startBeats = calculateBeatPosition(details.localPosition);
              setState(() {
                isDraggingNewClip = true;
                newClipStartBeats = snapToGrid(startBeats);
                newClipEndBeats = newClipStartBeats;
                newClipTrackId = null; // null = create new track
              });
            },
            onHorizontalDragUpdate: (details) {
              if (!isDraggingNewClip) return;
              final currentBeats = calculateBeatPosition(details.localPosition);
              setState(() {
                newClipEndBeats = snapToGrid(currentBeats);
              });
            },
            onHorizontalDragEnd: (details) {
              if (!isDraggingNewClip) return;

              // Calculate final start and duration (handle reverse drag)
              final startBeats = math.min(newClipStartBeats, newClipEndBeats);
              final endBeats = math.max(newClipStartBeats, newClipEndBeats);
              final durationBeats = endBeats - startBeats;

              // Minimum clip length is 1 bar (4 beats)
              if (durationBeats >= UIConstants.minDragCreateDurationBeats) {
                // Show track type selection popup
                showTrackTypePopup(
                  context,
                  details.globalPosition,
                  startBeats,
                  durationBeats,
                );
              }

              setState(() {
                isDraggingNewClip = false;
              });
            },
            onHorizontalDragCancel: () {
              setState(() {
                isDraggingNewClip = false;
              });
            },
            // Library panel MidiFileItem drag target (outermost)
            child: DragTarget<MidiFileItem>(
              onWillAcceptWithDetails: (details) => true,
              onMove: (details) {
                // Load MIDI data if this is a new file being dragged
                if (previewMidiFilePath != details.data.filePath) {
                  previewMidiFilePath = details.data.filePath;
                  loadMidiNotesForPreview(details.data.filePath);
                }

                // Calculate beat position from mouse
                final RenderBox? box = context.findRenderObject() as RenderBox?;
                final localPos =
                    box?.globalToLocal(details.offset) ?? Offset.zero;
                final scrollOffset = scrollController.hasClients
                    ? scrollController.offset
                    : 0.0;
                final xInContent = localPos.dx + scrollOffset;
                final rawBeats = xInContent / pixelsPerBeat;
                final snappedBeats = GridUtils.snapToGridRound(
                  rawBeats,
                  GridUtils.getTimelineGridResolution(pixelsPerBeat),
                );
                final startTime =
                    snappedBeats.clamp(0.0, double.infinity) /
                    (widget.tempo / 60.0);
                final durationSeconds = previewMidiDuration != null
                    ? previewMidiDuration! / (widget.tempo / 60.0)
                    : null;

                // Coalesce: skip the rebuild when the ghost would render
                // identically (position + track unchanged since last frame).
                final existing = previewClip;
                if (existing != null &&
                    existing.trackId == -2 &&
                    existing.startTime == startTime &&
                    isMidiFileDraggingOverEmpty) {
                  return;
                }

                setState(() {
                  isMidiFileDraggingOverEmpty = true;
                  previewClip = PreviewClip(
                    fileName: details.data.name,
                    filePath: details.data.filePath,
                    startTime: startTime,
                    trackId: -2,
                    mousePosition: localPos,
                    duration: durationSeconds,
                    midiNotes: previewMidiNotes,
                    isMidi: true,
                  );
                });
              },
              onLeave: (data) {
                setState(() {
                  isMidiFileDraggingOverEmpty = false;
                  if (previewClip?.trackId == -2) previewClip = null;
                });
              },
              onAcceptWithDetails: (details) {
                // Calculate beat position from drop location
                final RenderBox? box = context.findRenderObject() as RenderBox?;
                final localPos =
                    box?.globalToLocal(details.offset) ?? Offset.zero;
                final scrollOffset = scrollController.hasClients
                    ? scrollController.offset
                    : 0.0;
                final xInContent = localPos.dx + scrollOffset;
                final rawBeats = xInContent / pixelsPerBeat;
                final snappedBeats = GridUtils.snapToGridRound(
                  rawBeats,
                  GridUtils.getTimelineGridResolution(pixelsPerBeat),
                ).clamp(0.0, double.infinity);

                clearMidiPreviewCache();
                setState(() {
                  previewClip = null;
                  isMidiFileDraggingOverEmpty = false;
                });
                widget.dragDropCallbacks.onMidiFileDroppedOnEmpty?.call(
                  details.data.filePath,
                  snappedBeats,
                );
              },
              builder: (context, candidateMidiFiles, rejectedMidiFiles) {
                // Library panel AudioFileItem drag target
                return DragTarget<AudioFileItem>(
                  onWillAcceptWithDetails: (details) => true,
                  onMove: (details) {
                    // Load waveform data if this is a new file being dragged
                    if (previewWaveformPath != details.data.filePath) {
                      previewWaveformPath = details.data.filePath;
                      loadWaveformForPreview(details.data.filePath);
                    }

                    // Calculate beat position from mouse
                    final RenderBox? box =
                        context.findRenderObject() as RenderBox?;
                    final localPos =
                        box?.globalToLocal(details.offset) ?? Offset.zero;
                    final scrollOffset = scrollController.hasClients
                        ? scrollController.offset
                        : 0.0;
                    final xInContent = localPos.dx + scrollOffset;
                    final rawBeats = xInContent / pixelsPerBeat;
                    final snappedBeats = GridUtils.snapToGridRound(
                      rawBeats,
                      GridUtils.getTimelineGridResolution(pixelsPerBeat),
                    );
                    final startTime =
                        snappedBeats.clamp(0.0, double.infinity) /
                        (widget.tempo / 60.0);

                    // Coalesce: onMove fires ~60Hz, but the ghost is rendered
                    // purely from (startTime, trackId) — mousePosition is unused
                    // for layout. Skip the rebuild when neither has changed.
                    final existing = previewClip;
                    if (existing != null &&
                        existing.trackId == -1 &&
                        existing.startTime == startTime &&
                        isAudioFileDraggingOverEmpty) {
                      return;
                    }

                    setState(() {
                      isAudioFileDraggingOverEmpty = true;
                      previewClip = PreviewClip(
                        fileName: details.data.name,
                        filePath: details.data.filePath,
                        startTime: startTime,
                        trackId: -1,
                        mousePosition: localPos,
                        duration: previewWaveformDuration,
                        waveformPeaks: previewWaveformPeaks,
                      );
                    });
                  },
                  onLeave: (data) {
                    setState(() {
                      isAudioFileDraggingOverEmpty = false;
                      if (previewClip?.trackId == -1) previewClip = null;
                    });
                  },
                  onAcceptWithDetails: (details) {
                    // Calculate beat position from drop location
                    final RenderBox? box =
                        context.findRenderObject() as RenderBox?;
                    final localPos =
                        box?.globalToLocal(details.offset) ?? Offset.zero;
                    final scrollOffset = scrollController.hasClients
                        ? scrollController.offset
                        : 0.0;
                    final xInContent = localPos.dx + scrollOffset;
                    final rawBeats = xInContent / pixelsPerBeat;
                    final snappedBeats = GridUtils.snapToGridRound(
                      rawBeats,
                      GridUtils.getTimelineGridResolution(pixelsPerBeat),
                    ).clamp(0.0, double.infinity);

                    clearWaveformPreviewCache();
                    setState(() {
                      previewClip = null;
                      isAudioFileDraggingOverEmpty = false;
                    });
                    widget.dragDropCallbacks.onAudioFileDroppedOnEmpty?.call(
                      details.data.filePath,
                      snappedBeats,
                    );
                  },
                  builder: (context, candidateLibraryAudioFiles, rejectedLibraryAudioFiles) {
                    final isLibraryAudioHovering =
                        candidateLibraryAudioFiles.isNotEmpty;

                    return PlatformDropTarget(
                      onDragDone: (details) {
                        // Calculate beat position from Finder drop location
                        final RenderBox? box =
                            context.findRenderObject() as RenderBox?;
                        final localPos =
                            box?.globalToLocal(details.localPosition) ??
                            Offset.zero;
                        final scrollOffset = scrollController.hasClients
                            ? scrollController.offset
                            : 0.0;
                        final xInContent = localPos.dx + scrollOffset;
                        final rawBeats = xInContent / pixelsPerBeat;
                        final snappedBeats = GridUtils.snapToGridRound(
                          rawBeats,
                          GridUtils.getTimelineGridResolution(pixelsPerBeat),
                        ).clamp(0.0, double.infinity);

                        // Handle file drops from Finder
                        for (final file in details.files) {
                          final ext = file.path.split('.').last.toLowerCase();
                          if (['mid', 'midi'].contains(ext)) {
                            widget.dragDropCallbacks.onMidiFileDroppedOnEmpty
                                ?.call(file.path, snappedBeats);
                            return;
                          }
                          if ([
                            'wav',
                            'mp3',
                            'flac',
                            'aif',
                            'aiff',
                          ].contains(ext)) {
                            widget.dragDropCallbacks.onAudioFileDroppedOnEmpty
                                ?.call(file.path, snappedBeats);
                            return;
                          }
                        }
                      },
                      onDragEntered: (details) {
                        setState(() {
                          isAudioFileDraggingOverEmpty = true;
                        });
                      },
                      onDragExited: (details) {
                        setState(() {
                          isAudioFileDraggingOverEmpty = false;
                        });
                      },
                      child: DragTarget<Vst3Plugin>(
                        onWillAcceptWithDetails: (details) {
                          return details
                              .data
                              .isInstrument; // Only accept VST3 instruments
                        },
                        onAcceptWithDetails: (details) {
                          widget
                              .dragDropCallbacks
                              .onVst3InstrumentDroppedOnEmpty
                              ?.call(details.data);
                        },
                        builder: (context, candidateVst3Plugins, rejectedVst3Plugins) {
                          final isVst3PluginHovering =
                              candidateVst3Plugins.isNotEmpty;

                          return DragTarget<Instrument>(
                            onWillAcceptWithDetails: (details) {
                              return true; // Always accept instruments
                            },
                            onAcceptWithDetails: (details) {
                              widget
                                  .dragDropCallbacks
                                  .onInstrumentDroppedOnEmpty
                                  ?.call(details.data);
                            },
                            builder: (context, candidateInstruments, rejectedInstruments) {
                              final isInstrumentHovering =
                                  candidateInstruments.isNotEmpty ||
                                  isVst3PluginHovering;
                              final isMidiFileHovering =
                                  candidateMidiFiles.isNotEmpty;
                              final isAudioHovering =
                                  isAudioFileDraggingOverEmpty ||
                                  isLibraryAudioHovering;
                              final isFileHovering =
                                  isAudioHovering || isMidiFileHovering;
                              final isAnyHovering =
                                  isInstrumentHovering || isFileHovering;

                              // Helper to truncate filename for display
                              String truncateFilename(
                                String name, {
                                int maxLength = 30,
                              }) {
                                if (name.length <= maxLength) return name;
                                return '${name.substring(0, maxLength - 3)}...';
                              }

                              // Determine label text
                              String dropLabel;
                              if (isMidiFileHovering &&
                                  candidateMidiFiles.isNotEmpty) {
                                final fileName = truncateFilename(
                                  candidateMidiFiles.first!.name,
                                );
                                dropLabel =
                                    'Drop to create new MIDI track with $fileName';
                              } else if (isLibraryAudioHovering &&
                                  candidateLibraryAudioFiles.isNotEmpty) {
                                final fileName = truncateFilename(
                                  candidateLibraryAudioFiles.first!.name,
                                );
                                dropLabel =
                                    'Drop to create new Audio track with $fileName';
                              } else if (isAudioFileDraggingOverEmpty) {
                                dropLabel = 'Drop to create new Audio track';
                              } else if (isMidiFileDraggingOverEmpty) {
                                dropLabel = 'Drop to create new MIDI track';
                              } else if (candidateVst3Plugins.isNotEmpty) {
                                dropLabel =
                                    'Drop to create new MIDI track with ${candidateVst3Plugins.first?.name}';
                              } else if (candidateInstruments.isNotEmpty) {
                                dropLabel =
                                    'Drop to create new MIDI track with ${candidateInstruments.first?.name ?? "instrument"}';
                              } else {
                                dropLabel = 'Drop to create new track';
                              }

                              // Check if we have a file preview for the empty area
                              final hasFilePreview =
                                  previewClip != null &&
                                  (previewClip!.trackId == -1 ||
                                      previewClip!.trackId == -2);

                              return Stack(
                                children: [
                                  if (hasFilePreview) ...[
                                    // Clip-shaped preview at mouse position
                                    buildEmptyAreaPreviewClip(previewClip!),
                                    // Label pill at bottom
                                    Positioned(
                                      bottom: 4,
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: context.colors.success
                                                .withValues(alpha: 0.8),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                BI.addCircle,
                                                color:
                                                    context.colors.textPrimary,
                                                size: 16,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                dropLabel,
                                                style: TextStyle(
                                                  color: context
                                                      .colors
                                                      .textPrimary,
                                                  fontSize: 12,
                                                  fontWeight: BT.weightSemiBold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ] else if (isAnyHovering) ...[
                                    // Instrument/VST3 drag — full-width track strip
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      top: 0,
                                      height: UIConstants.defaultClipHeight,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: context.colors.accent
                                              .withValues(alpha: 0.08),
                                          border: Border.all(
                                            color: context.colors.accent
                                                .withValues(alpha: 0.5),
                                            width: 1,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            left: 16,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                BI.addCircle,
                                                color: context
                                                    .colors
                                                    .textSecondary,
                                                size: 16,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                dropLabel,
                                                style: TextStyle(
                                                  color: context
                                                      .colors
                                                      .textSecondary,
                                                  fontSize: 13,
                                                  fontWeight: BT.weightMedium,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ] else
                                    const SizedBox.expand(),
                                  // Drag-to-create preview (for empty space)
                                  if (isDraggingNewClip &&
                                      newClipTrackId == null)
                                    buildDragToCreatePreview(),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
        // Master track is now rendered outside scroll area (in build method)
      ],
    );
  }

  Widget _buildAutomationLane(
    int trackId,
    Color trackColor,
    double width,
    double totalBeats,
  ) {
    final lane = widget.automationCallbacks.getAutomationLane?.call(trackId);
    final automationHeight =
        widget.trackHeightState.automationHeights[trackId] ??
        UIConstants.defaultAutomationHeight;

    // Create empty lane if none provided
    final automationLane =
        lane ??
        TrackAutomationLane(
          trackId: trackId,
          parameter: AutomationParameter.volume,
          points: const [],
        );

    return TrackAutomationLaneWidget(
      lane: automationLane,
      pixelsPerBeat: pixelsPerBeat,
      totalBeats: totalBeats,
      laneHeight: automationHeight,
      horizontalScrollController: scrollController,
      trackColor: trackColor,
      toolMode: widget.toolMode,
      snapEnabled: !snapBypassActive,
      snapResolution: getGridSnapResolution(),
      beatsPerBar: 4,
      onPointAdded: (point) =>
          widget.automationCallbacks.onPointAdded?.call(trackId, point),
      onPointUpdated: (pointId, point) => widget
          .automationCallbacks
          .onPointUpdated
          ?.call(trackId, pointId, point),
      onPointDragEnd: (pointId) =>
          widget.automationCallbacks.onPointDragEnd?.call(trackId, pointId),
      onPointDeleted: (pointId) =>
          widget.automationCallbacks.onPointDeleted?.call(trackId, pointId),
      onHeightChanged: (newHeight) => widget
          .trackHeightState
          .onAutomationHeightChanged
          ?.call(trackId, newHeight),
      onPreviewValue: (value) =>
          widget.automationCallbacks.onPreviewValue?.call(trackId, value),
    );
  }

  Widget _buildTrack(
    double width,
    TimelineTrackData track,
    Color trackColor,
    int audioCount,
    int midiCount, {
    bool showAutomation = false,
    double totalBeats = 0.0,
    int laneIndex = 0,
  }) {
    // Find clips for this track
    final trackClips = clips.where((c) => c.trackId == track.id).toList();
    final trackMidiClips = widget.midiClips
        .where((c) => c.trackId == track.id)
        .toList();
    final isHovered = dragHoveredTrackId == track.id;
    final isMidiTrack = track.type.toLowerCase() == 'midi';
    final clipHeight =
        widget.trackHeightState.clipHeights[track.id] ??
        UIConstants.defaultClipHeight;

    // Detect active recording region on this track (for visual masking)
    double? recStartBeat;
    double? recEndBeat;
    if (widget.isRecording) {
      final liveClip = trackMidiClips
          .where((c) => c.clipId == LiveRecordingNotifier.liveClipId)
          .firstOrNull;
      if (liveClip != null) {
        recStartBeat = liveClip.startTime;
        recEndBeat = liveClip.startTime + liveClip.duration;
      }
    }

    // Build the clip area widget
    final clipAreaWidget = DragTarget<MidiFileItem>(
      onWillAcceptWithDetails: (details) {
        // Only accept MIDI files on MIDI tracks
        return isMidiTrack;
      },
      onMove: (details) {
        if (!isMidiTrack) return;

        // Load MIDI data if this is a new file being dragged
        if (previewMidiFilePath != details.data.filePath) {
          previewMidiFilePath = details.data.filePath;
          loadMidiNotesForPreview(details.data.filePath);
        }

        // Convert global offset to local coordinates
        final RenderBox? box = context.findRenderObject() as RenderBox?;
        final localPos = box?.globalToLocal(details.offset) ?? Offset.zero;
        final scrollOffset = scrollController.hasClients
            ? scrollController.offset
            : 0.0;
        final xInContent = localPos.dx + scrollOffset;
        final rawBeats = xInContent / pixelsPerBeat;

        // Snap to grid
        final snappedBeats = GridUtils.snapToGridRound(
          rawBeats,
          GridUtils.getTimelineGridResolution(pixelsPerBeat),
        );
        final startTime =
            snappedBeats.clamp(0.0, double.infinity) / (widget.tempo / 60.0);

        // Duration in beats -> convert to seconds for consistent PreviewClip
        final durationSeconds = previewMidiDuration != null
            ? previewMidiDuration! / (widget.tempo / 60.0)
            : null;

        // Coalesce: skip the rebuild when position + track are unchanged.
        final existing = previewClip;
        if (existing != null &&
            existing.trackId == track.id &&
            existing.startTime == startTime &&
            dragHoveredTrackId == track.id) {
          return;
        }

        setState(() {
          dragHoveredTrackId = track.id;
          previewClip = PreviewClip(
            fileName: details.data.name,
            filePath: details.data.filePath,
            startTime: startTime,
            trackId: track.id,
            mousePosition: localPos,
            duration: durationSeconds,
            midiNotes: previewMidiNotes,
            isMidi: true,
          );
        });
      },
      onLeave: (data) {
        if (previewClip?.trackId == track.id) {
          setState(() {
            dragHoveredTrackId = null;
            previewClip = null;
          });
        }
      },
      onAcceptWithDetails: (details) {
        clearMidiPreviewCache();
        setState(() {
          previewClip = null;
          dragHoveredTrackId = null;
        });

        final RenderBox? box = context.findRenderObject() as RenderBox?;
        final localPos = box?.globalToLocal(details.offset) ?? Offset.zero;
        final scrollOffset = scrollController.hasClients
            ? scrollController.offset
            : 0.0;
        final xInContent = localPos.dx + scrollOffset;
        final rawBeats = xInContent / pixelsPerBeat;
        final snappedBeats = GridUtils.snapToGridRound(
          rawBeats,
          GridUtils.getTimelineGridResolution(pixelsPerBeat),
        );
        widget.dragDropCallbacks.onMidiFileDroppedOnTrack?.call(
          track.id,
          details.data.filePath,
          snappedBeats.clamp(0.0, double.infinity),
        );
      },
      builder: (context, candidateMidiFiles, rejectedMidiFiles) {
        return DragTarget<AudioFileItem>(
          onWillAcceptWithDetails: (details) {
            // Only accept on Audio tracks, reject on MIDI tracks
            return !isMidiTrack;
          },
          onMove: (details) {
            // Library audio file drag - show preview with file info
            if (isMidiTrack) return;

            // Load waveform data if this is a new file being dragged
            if (previewWaveformPath != details.data.filePath) {
              previewWaveformPath = details.data.filePath;
              loadWaveformForPreview(details.data.filePath);
            }

            // Convert global offset to local coordinates
            final RenderBox? box = context.findRenderObject() as RenderBox?;
            final localPos = box?.globalToLocal(details.offset) ?? Offset.zero;
            final scrollOffset = scrollController.hasClients
                ? scrollController.offset
                : 0.0;
            final xInContent = localPos.dx + scrollOffset;
            final rawBeats = xInContent / pixelsPerBeat;

            // Snap to grid
            final snappedBeats = GridUtils.snapToGridRound(
              rawBeats,
              GridUtils.getTimelineGridResolution(pixelsPerBeat),
            );
            final startTime =
                snappedBeats.clamp(0.0, double.infinity) /
                (widget.tempo / 60.0);

            // Coalesce: skip the rebuild when position + track are unchanged.
            final existing = previewClip;
            if (existing != null &&
                existing.trackId == track.id &&
                existing.startTime == startTime &&
                dragHoveredTrackId == track.id) {
              return;
            }

            setState(() {
              dragHoveredTrackId = track.id;
              previewClip = PreviewClip(
                fileName: details.data.name,
                filePath: details.data.filePath,
                startTime: startTime,
                trackId: track.id,
                mousePosition: localPos,
                duration: previewWaveformDuration,
                waveformPeaks: previewWaveformPeaks,
              );
            });
          },
          onLeave: (data) {
            // Clear preview when leaving this track
            if (previewClip?.trackId == track.id) {
              setState(() {
                dragHoveredTrackId = null;
                previewClip = null;
              });
            }
          },
          onAcceptWithDetails: (details) {
            // Clear preview and waveform cache on drop
            clearWaveformPreviewCache();
            setState(() {
              previewClip = null;
              dragHoveredTrackId = null;
            });

            // Calculate drop position with scroll offset
            final RenderBox? box = context.findRenderObject() as RenderBox?;
            final localPos = box?.globalToLocal(details.offset) ?? Offset.zero;
            final scrollOffset = scrollController.hasClients
                ? scrollController.offset
                : 0.0;
            final xInContent = localPos.dx + scrollOffset;
            final rawBeats = xInContent / pixelsPerBeat;

            // Snap to grid
            final snappedBeats = GridUtils.snapToGridRound(
              rawBeats,
              GridUtils.getTimelineGridResolution(pixelsPerBeat),
            );

            widget.dragDropCallbacks.onAudioFileDroppedOnTrack?.call(
              track.id,
              details.data.filePath,
              snappedBeats.clamp(0.0, double.infinity),
            );
          },
          builder: (context, candidateAudioFiles, rejectedAudioFiles) {
            final isAudioFileRejected = rejectedAudioFiles.isNotEmpty;

            // Wrap with VST3Plugin drag target
            return DragTarget<Vst3Plugin>(
              onWillAcceptWithDetails: (details) {
                return isMidiTrack && details.data.isInstrument;
              },
              onAcceptWithDetails: (details) {
                widget.dragDropCallbacks.onVst3InstrumentDropped?.call(
                  track.id,
                  details.data,
                );
              },
              builder: (context, candidateVst3Plugins, rejectedVst3Plugins) {
                // Note: candidateVst3Plugins/rejectedVst3Plugins available for visual feedback

                // Nest Instrument drag target inside
                return DragTarget<Instrument>(
                  onWillAcceptWithDetails: (details) {
                    return isMidiTrack;
                  },
                  onAcceptWithDetails: (details) {
                    widget.dragDropCallbacks.onInstrumentDropped?.call(
                      track.id,
                      details.data,
                    );
                  },
                  builder: (context, candidateInstruments, rejectedInstruments) {
                    // Note: candidateInstruments/rejectedInstruments and isVst3PluginHovering/Rejected
                    // are available for visual feedback if needed in the future

                    return PlatformDropTarget(
                      onDragEntered: (details) {
                        // Only show hover state if not MIDI track (for audio file drops)
                        if (!isMidiTrack) {
                          setState(() {
                            dragHoveredTrackId = track.id;
                          });
                        } else {
                          // Track platform drag over MIDI for visual feedback
                          setState(() {
                            platformDragOverMidiTrackId = track.id;
                          });
                        }
                      },
                      onDragExited: (details) {
                        setState(() {
                          dragHoveredTrackId = null;
                          previewClip = null;
                          platformDragOverMidiTrackId = null;
                        });
                      },
                      onDragUpdated: (details) {
                        // Only show preview on Audio tracks
                        if (isMidiTrack) return;

                        // Update preview position (Finder drag - no file info yet)
                        final startTime = calculateTimelinePosition(
                          details.localPosition,
                        );

                        setState(() {
                          previewClip = PreviewClip(
                            fileName: 'Audio File',
                            filePath: '', // Unknown until drop
                            startTime: startTime,
                            trackId: track.id,
                            mousePosition: details.localPosition,
                          );
                        });
                      },
                      onDragDone: (details) async {
                        await handleFileDrop(
                          details.files,
                          track.id,
                          details.localPosition,
                        );
                      },
                      child: GestureDetector(
                        onTapDown: (details) {
                          // Handle deselection on tap down (before drag can intercept)
                          // But DON'T deselect if modifier keys are held (user might be Cmd+clicking to drag duplicate)
                          final modifiers = ModifierKeyState.current();
                          if (modifiers.isCtrlOrCmd || modifiers.isAltPressed) {
                            // Don't clear selection when modifier keys are held - let clip gesture handle it
                            return;
                          }

                          final beatPosition = calculateBeatPosition(
                            details.localPosition,
                          );
                          final isOnClip = _isPositionOnClip(
                            beatPosition,
                            track.id,
                            trackClips,
                            trackMidiClips,
                          );

                          // Click on empty space - deselect all clips (like piano roll)
                          if (!isOnClip) {
                            setState(() {
                              selectedAudioClipIds.clear();
                              selectedMidiClipIds.clear();
                              selectedAudioClipId = null;
                            });
                            widget.midiClipCallbacks.onSelected?.call(
                              null,
                              null,
                            );
                            widget.audioClipCallbacks.onSelected?.call(
                              null,
                              null,
                            );
                          }
                        },
                        onTapUp: (details) {
                          // Draw tool: single click on empty space just deselects (handled in onTapDown)
                          // Use click+drag to create new clips, or double-click for quick creation
                          // Note: Duplicate tool only works via drag, not click (Ableton-style)
                        },
                        onDoubleTapDown: isMidiTrack
                            ? (details) {
                                // Double-click: create a default MIDI clip at this position (spec v2.0: 1 bar)
                                final beatPosition = calculateBeatPosition(
                                  details.localPosition,
                                );
                                final isOnClip = _isPositionOnClip(
                                  beatPosition,
                                  track.id,
                                  trackClips,
                                  trackMidiClips,
                                );

                                if (!isOnClip) {
                                  // Create a 1-bar clip at the clicked position (snapped to grid)
                                  final startBeats = snapToGrid(beatPosition);
                                  const durationBeats =
                                      4.0; // 1 bar (spec v2.0)
                                  widget.dragDropCallbacks.onCreateClipOnTrack
                                      ?.call(
                                        track.id,
                                        startBeats,
                                        durationBeats,
                                      );
                                }
                              }
                            : null,
                        onHorizontalDragStart: (details) {
                          final tool = effectiveToolMode;
                          final beatPosition = calculateBeatPosition(
                            details.localPosition,
                          );
                          final isOnClip = _isPositionOnClip(
                            beatPosition,
                            track.id,
                            trackClips,
                            trackMidiClips,
                          );

                          // SELECT TOOL: Start box selection on empty space
                          if (tool == ToolMode.select && !isOnClip) {
                            // Calculate this track's Y offset within the content area
                            // (localPosition.dy is relative to this track widget, not the whole timeline)
                            final regularTracks = tracks
                                .where((t) => t.type != 'Master')
                                .toList();
                            final trackIndex = regularTracks.indexWhere(
                              (t) => t.id == track.id,
                            );
                            double trackYOffset = 0.0;
                            for (int i = 0; i < trackIndex; i++) {
                              trackYOffset +=
                                  widget
                                      .trackHeightState
                                      .clipHeights[regularTracks[i].id] ??
                                  UIConstants.defaultClipHeight;
                              // Include automation height if visible for this track
                              if (widget.automationVisibleTrackId ==
                                  regularTracks[i].id) {
                                trackYOffset +=
                                    widget
                                        .trackHeightState
                                        .automationHeights[regularTracks[i]
                                        .id] ??
                                    UIConstants.defaultAutomationHeight;
                              }
                            }

                            final scrollOffset = scrollController.hasClients
                                ? scrollController.offset
                                : 0.0;
                            final verticalOffset =
                                widget.verticalScrollController?.hasClients ==
                                    true
                                ? widget.verticalScrollController!.offset
                                : 0.0;

                            // Calculate visible Y position (for overlay rendering)
                            // localPosition.dy is relative to the track, trackYOffset is the track's position in content
                            // Subtract verticalOffset to get visible position
                            final visibleY =
                                details.localPosition.dy +
                                trackYOffset -
                                verticalOffset;

                            // Capture shift state at drag START for proper additive behavior
                            final shiftHeld =
                                ModifierKeyState.current().isShiftPressed;

                            setState(() {
                              isBoxSelecting = true;
                              // Store position in VISIBLE coordinates (for overlay rendering)
                              // Selection logic will convert back to content coordinates
                              boxSelectionStart = Offset(
                                details.localPosition.dx + scrollOffset,
                                visibleY,
                              );
                              boxSelectionEnd = boxSelectionStart;
                              boxSelectionScrollOffset = scrollOffset;
                              boxSelectionTrackYOffset = trackYOffset;
                              // Capture shift state and initial selection for proper additive behavior
                              boxSelectionShiftHeld = shiftHeld;
                              boxSelectionInitialMidiIds = shiftHeld
                                  ? Set.from(selectedMidiClipIds)
                                  : {};
                              boxSelectionInitialAudioIds = shiftHeld
                                  ? Set.from(selectedAudioClipIds)
                                  : {};
                            });
                            return;
                          }

                          // DRAW TOOL: Drag-to-create on MIDI tracks
                          if (tool == ToolMode.draw &&
                              !isOnClip &&
                              isMidiTrack) {
                            setState(() {
                              isDraggingNewClip = true;
                              newClipStartBeats = snapToGrid(beatPosition);
                              newClipEndBeats = newClipStartBeats;
                              newClipTrackId = track.id;
                            });
                          }
                        },
                        onHorizontalDragUpdate: (details) {
                          // Box selection update
                          if (isBoxSelecting) {
                            final scrollOffset = scrollController.hasClients
                                ? scrollController.offset
                                : 0.0;
                            final verticalOffset =
                                widget.verticalScrollController?.hasClients ==
                                    true
                                ? widget.verticalScrollController!.offset
                                : 0.0;

                            // Calculate visible Y position (for overlay rendering)
                            final visibleY =
                                details.localPosition.dy +
                                boxSelectionTrackYOffset -
                                verticalOffset;

                            setState(() {
                              // Update end position in VISIBLE coordinates (for overlay rendering)
                              boxSelectionEnd = Offset(
                                details.localPosition.dx + scrollOffset,
                                visibleY,
                              );
                            });
                            // Live selection update - select clips within the box
                            updateBoxSelection();
                            return;
                          }

                          // Drag-to-create update
                          if (isDraggingNewClip && newClipTrackId == track.id) {
                            final currentBeats = calculateBeatPosition(
                              details.localPosition,
                            );
                            setState(() {
                              newClipEndBeats = snapToGrid(currentBeats);
                            });
                          }
                        },
                        onHorizontalDragEnd: (details) {
                          // Box selection end
                          if (isBoxSelecting) {
                            // If nothing was selected, notify parent to deselect current clip
                            if (selectedMidiClipIds.isEmpty &&
                                selectedAudioClipIds.isEmpty) {
                              widget.midiClipCallbacks.onSelected?.call(
                                null,
                                null,
                              );
                              widget.audioClipCallbacks.onSelected?.call(
                                null,
                                null,
                              );
                            }
                            setState(() {
                              isBoxSelecting = false;
                              boxSelectionStart = null;
                              boxSelectionEnd = null;
                            });
                            return;
                          }

                          // Drag-to-create end
                          if (isDraggingNewClip && newClipTrackId == track.id) {
                            // Calculate final start and duration (handle reverse drag)
                            final startBeats = math.min(
                              newClipStartBeats,
                              newClipEndBeats,
                            );
                            final endBeats = math.max(
                              newClipStartBeats,
                              newClipEndBeats,
                            );
                            final durationBeats = endBeats - startBeats;

                            // Minimum clip length is 1 bar (4 beats)
                            if (durationBeats >=
                                UIConstants.minDragCreateDurationBeats) {
                              widget.dragDropCallbacks.onCreateClipOnTrack
                                  ?.call(track.id, startBeats, durationBeats);
                            }

                            setState(() {
                              isDraggingNewClip = false;
                              newClipTrackId = null;
                            });
                          }
                        },
                        onHorizontalDragCancel: () {
                          if (newClipTrackId == track.id) {
                            setState(() {
                              isDraggingNewClip = false;
                              newClipTrackId = null;
                            });
                          }
                        },
                        onSecondaryTapUp: (details) {
                          // Right-click on empty area: show context menu
                          final beatPosition = calculateBeatPosition(
                            details.localPosition,
                          );
                          final isOnClip = _isPositionOnClip(
                            beatPosition,
                            track.id,
                            trackClips,
                            trackMidiClips,
                          );
                          if (!isOnClip) {
                            showEmptyAreaContextMenu(
                              details.globalPosition,
                              details.localPosition,
                              track,
                              isMidiTrack,
                            );
                          }
                        },
                        child: Container(
                          height:
                              widget.trackHeightState.clipHeights[track.id] ??
                              UIConstants.defaultClipHeight,
                          decoration: BoxDecoration(
                            // Normally transparent (shows the canvas + grid
                            // through); the tinted-lanes bg variant washes
                            // alternating lanes for Logic-style structure.
                            color: isHovered
                                ? context.colors.accent.withValues(alpha: 0.1)
                                : (laneIndex.isOdd
                                          ? widget.canvasBgVariant.laneTint
                                          : null) ??
                                      Colors.transparent,
                            border: Border(
                              top: isHovered
                                  ? BorderSide(
                                      color: context.colors.accent.withValues(
                                        alpha: 0.5,
                                      ),
                                      width: 2,
                                    )
                                  : BorderSide.none,
                              bottom: BorderSide(
                                color: isHovered
                                    ? context.colors.accent.withValues(
                                        alpha: 0.5,
                                      )
                                    : context.colors.hover,
                                width: isHovered ? 2 : 1,
                              ),
                            ),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            clipBehavior: Clip.none,
                            children: [
                              // Grid pattern
                              CustomPaint(painter: GridPatternPainter()),

                              // Render audio clips for this track (hide erased + cull off-screen)
                              ...trackClips
                                  .where(
                                    (clip) => !erasedAudioClipIds.contains(
                                      clip.clipId,
                                    ),
                                  )
                                  .where(
                                    (clip) => isClipVisible(
                                      clip.startTime * pixelsPerSecond,
                                      clip.duration * pixelsPerSecond,
                                    ),
                                  )
                                  .map(
                                    (clip) => _buildClip(
                                      clip,
                                      trackColor,
                                      widget.trackHeightState.clipHeights[track
                                              .id] ??
                                          UIConstants.defaultClipHeight,
                                      recStartBeat: recStartBeat,
                                      recEndBeat: recEndBeat,
                                    ),
                                  ),

                              // Ghost preview for audio clip copy drag (all selected clips)
                              ...trackClips
                                  .where(
                                    (clip) =>
                                        isCopyDrag &&
                                        draggingClipId != null &&
                                        selectedAudioClipIds.contains(
                                          clip.clipId,
                                        ),
                                  )
                                  .expand(
                                    (clip) => buildAudioCopyDragPreviews(
                                      clip,
                                      trackColor,
                                      widget.trackHeightState.clipHeights[track
                                              .id] ??
                                          UIConstants.defaultClipHeight,
                                    ),
                                  ),

                              // Ghost preview for audio clips during MIDI drag (cross-type)
                              ...trackClips
                                  .where(
                                    (clip) =>
                                        isCopyDrag &&
                                        draggingMidiClipId != null &&
                                        selectedAudioClipIds.contains(
                                          clip.clipId,
                                        ),
                                  )
                                  .expand(
                                    (clip) =>
                                        buildAudioCopyDragPreviewsForMidiDrag(
                                          clip,
                                          trackColor,
                                          widget
                                                  .trackHeightState
                                                  .clipHeights[track.id] ??
                                              UIConstants.defaultClipHeight,
                                        ),
                                  ),

                              // Render MIDI clips for this track (hide erased + cull off-screen)
                              ...trackMidiClips
                                  .where(
                                    (midiClip) => !erasedMidiClipIds.contains(
                                      midiClip.clipId,
                                    ),
                                  )
                                  .where(
                                    (midiClip) => isClipVisible(
                                      midiClip.startTime * pixelsPerBeat,
                                      midiClip.duration * pixelsPerBeat,
                                    ),
                                  )
                                  .map(
                                    (midiClip) => _buildMidiClip(
                                      midiClip,
                                      trackColor,
                                      widget.trackHeightState.clipHeights[track
                                              .id] ??
                                          UIConstants.defaultClipHeight,
                                      recStartBeat: recStartBeat,
                                      recEndBeat: recEndBeat,
                                    ),
                                  ),

                              // Ghost preview for MIDI clip copy drag (all selected clips)
                              ...trackMidiClips
                                  .where(
                                    (midiClip) =>
                                        isCopyDrag &&
                                        draggingMidiClipId != null &&
                                        selectedMidiClipIds.contains(
                                          midiClip.clipId,
                                        ),
                                  )
                                  .expand(
                                    (midiClip) => buildCopyDragPreviews(
                                      midiClip,
                                      trackColor,
                                      widget.trackHeightState.clipHeights[track
                                              .id] ??
                                          UIConstants.defaultClipHeight,
                                    ),
                                  ),

                              // Ghost preview for MIDI clips during audio drag (cross-type)
                              ...trackMidiClips
                                  .where(
                                    (midiClip) =>
                                        isCopyDrag &&
                                        draggingClipId != null &&
                                        selectedMidiClipIds.contains(
                                          midiClip.clipId,
                                        ),
                                  )
                                  .expand(
                                    (midiClip) =>
                                        buildMidiCopyDragPreviewsForAudioDrag(
                                          midiClip,
                                          trackColor,
                                          widget
                                                  .trackHeightState
                                                  .clipHeights[track.id] ??
                                              UIConstants.defaultClipHeight,
                                        ),
                                  ),

                              // Show preview clip if hovering over this track
                              if (previewClip != null &&
                                  previewClip!.trackId == track.id)
                                buildPreviewClip(previewClip!),

                              // Drag-to-create preview for this track
                              if (isDraggingNewClip &&
                                  newClipTrackId == track.id)
                                buildDragToCreatePreviewOnTrack(
                                  trackColor,
                                  widget.trackHeightState.clipHeights[track
                                          .id] ??
                                      UIConstants.defaultClipHeight,
                                ),

                              // Red rejection overlay when dragging audio onto MIDI track
                              if (isAudioFileRejected ||
                                  platformDragOverMidiTrackId == track.id)
                                Positioned.fill(
                                  child: ColoredBox(
                                    color: context.colors.error.withValues(
                                      alpha: 0.15,
                                    ),
                                    child: Center(
                                      child: Icon(
                                        BI.pluginOff,
                                        color: context.colors.error.withValues(
                                          alpha: 0.6,
                                        ),
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );

    // If automation is not visible, return just the clip area
    if (!showAutomation) {
      return clipAreaWidget;
    }

    // When automation is visible, wrap clip and automation in a Column
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Clip area with resize handle at bottom
        Stack(
          children: [
            clipAreaWidget,
            // Resize handle between clip and automation
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: UIConstants.trackResizeHandleHeight,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeRow,
                child: GestureDetector(
                  onVerticalDragUpdate: (details) {
                    final newHeight = (clipHeight + details.delta.dy).clamp(
                      UIConstants.trackMinHeight,
                      UIConstants.trackMaxHeight,
                    );
                    widget.trackHeightState.onClipHeightChanged?.call(
                      track.id,
                      newHeight,
                    );
                  },
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
          ],
        ),
        // Automation lane (includes its own resize handle at bottom)
        _buildAutomationLane(track.id, trackColor, width, totalBeats),
      ],
    );
  }

  Widget _buildMasterTrack(double width, TimelineTrackData track) {
    final masterColor = context.colors.accent;
    const headerHeight = UIConstants.clipHeaderHeight;

    // Match the MIDI/Audio clip style - spans full width like a clip
    // Content area is transparent so grid shows through from behind
    return Container(
      width: width,
      height: widget.trackHeightState.masterTrackHeight,
      margin: const EdgeInsets.only(left: 2, right: 2, top: 1, bottom: 1),
      decoration: BoxDecoration(
        // Rounded corners like clips
        borderRadius: BorderRadius.circular(4),
        // Border matching clip style (1px when not selected)
        border: Border.all(color: masterColor, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3), // Inside border radius
        child: Column(
          children: [
            // Header bar (like clip header)
            Container(
              height: headerHeight,
              color: masterColor,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ClipRect(
                child: Row(
                  children: [
                    // Icon (headphones)
                    const Text('🎧', style: TextStyle(fontSize: BT.fontLabel)),
                    const SizedBox(width: 4),
                    // "Master" text (white)
                    Text(
                      'Master',
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: BT.fontLabel,
                        fontWeight: BT.weightSemiBold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Content area - transparent so grid shows through
            const Expanded(child: SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}
