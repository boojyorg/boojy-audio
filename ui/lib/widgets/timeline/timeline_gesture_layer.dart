part of '../timeline_view.dart';

/// Audio/MIDI clip gesture handlers (drag, trim, resize) for [TimelineView].
mixin TimelineGestureLayerMixin
    on
        State<TimelineView>,
        TimelineViewStateMixin,
        TimelineSelectionMixin,
        TimelineContextMenusMixin {
  /// Build a MIDI clip move command, or null if the move is a no-op.
  /// Multi-clip drags collect these and submit them as a single
  /// [CompositeCommand] via [_executeGroupedMoves] (one undo step).
  Command? _buildMidiClipMoveCommand(
    MidiClipData clip,
    double oldStartBeats,
    double newStartBeats,
  ) {
    if ((newStartBeats - oldStartBeats).abs() < 0.001) return null;

    return MoveMidiClipPositionCommand(
      originalClip: clip,
      oldStartTime: oldStartBeats,
      newStartTime: newStartBeats,
      onClipMoved: (clipId, startTime) {
        final current = widget.midiClips.firstWhere(
          (c) => c.clipId == clipId,
          orElse: () => clip,
        );
        widget.midiClipCallbacks.onUpdated?.call(
          current.copyWith(startTime: startTime),
        );
      },
    );
  }

  /// Submit a batch of clip-move commands as a single undo step. A multi-clip
  /// drag previously called `execute()` once per clip, so one Ctrl+Z reverted
  /// only a single clip; wrapping them in a [CompositeCommand] fixes that.
  Future<void> _executeGroupedMoves(List<Command> commands) async {
    if (commands.isEmpty) return;
    final command = commands.length == 1
        ? commands.first
        : CompositeCommand(commands, 'Move ${commands.length} clips');
    await UndoRedoManager().execute(command);
  }

  Future<void> _commitMidiClipSnapshot(
    MidiClipData before,
    MidiClipData after,
    String description,
  ) async {
    final changed =
        before.startTime != after.startTime ||
        before.duration != after.duration ||
        before.notes.length != after.notes.length;
    if (!changed) return;

    final command = MidiClipSnapshotCommand(
      beforeState: before,
      afterState: after,
      actionDescription: description,
      onApplyState: widget.midiClipCallbacks.onUpdated,
    );
    await UndoRedoManager().execute(command);
  }

  /// Get cursor based on current tool mode
  MouseCursor _getCursorForTool(ToolMode tool, {bool isOverClip = false}) {
    switch (tool) {
      case ToolMode.draw:
        return SystemMouseCursors.precise;
      case ToolMode.select:
        return isOverClip ? SystemMouseCursors.grab : SystemMouseCursors.basic;
      case ToolMode.eraser:
        return SystemMouseCursors.forbidden;
      case ToolMode.duplicate:
        return SystemMouseCursors.copy;
      case ToolMode.slice:
        return SystemMouseCursors.verticalText;
    }
  }

  // ========================================================================
  // ERASER MODE (Ctrl/Cmd+drag to delete multiple clips)
  // ========================================================================

  /// Start eraser mode
  // Pending clips to delete (for batched eraser undo)
  final List<ClipData> _pendingAudioClipsToErase = [];
  final List<(int clipId, int trackId)> _pendingMidiClipsToErase = [];

  void _startErasing(Offset globalPosition) {
    setState(() {
      isErasing = true;
      erasedAudioClipIds.clear();
      erasedMidiClipIds.clear();
      _pendingAudioClipsToErase.clear();
      _pendingMidiClipsToErase.clear();
    });
    _eraseClipsAt(globalPosition);
  }

  /// Mark clips for erasing at the given position (batched deletion on stop)
  void _eraseClipsAt(Offset globalPosition) {
    if (!isErasing) return;

    // Convert global position to local position relative to timeline content
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPosition = box.globalToLocal(globalPosition);

    // Calculate beat position from mouse X (accounting for horizontal scroll)
    final scrollOffset = scrollController.hasClients
        ? scrollController.offset
        : 0.0;
    final beatPosition = (localPosition.dx + scrollOffset) / pixelsPerBeat;

    // Calculate Y position in track coordinate space
    // localPosition.dy is relative to TimelineView top
    // We need to account for:
    // 1. Nav bar height (24px) - subtract this to get position relative to tracks area
    // 2. Vertical scroll offset - add this to convert from visible to content coordinates
    const navBarHeight = UIConstants.navBarHeight;
    final verticalScrollOffset =
        widget.verticalScrollController?.hasClients == true
        ? widget.verticalScrollController!.offset
        : 0.0;
    final trackAreaY = localPosition.dy - navBarHeight + verticalScrollOffset;

    // Use regularTracks (non-Master) for Y position calculations to match visual layout
    final regularTracks = tracks.where((t) => t.type != 'Master').toList();

    // Check audio clips
    for (final clip in clips) {
      if (erasedAudioClipIds.contains(clip.clipId)) continue;

      // Convert clip times from seconds to beats for comparison
      final beatsPerSecond = widget.tempo / 60.0;
      final clipStartBeats = clip.startTime * beatsPerSecond;
      final clipEndBeats = (clip.startTime + clip.duration) * beatsPerSecond;

      // Find track Y position using actual track heights (regularTracks matches rendering order)
      final trackIndex = regularTracks.indexWhere((t) => t.id == clip.trackId);
      if (trackIndex < 0) continue;

      double trackTop = 0.0;
      for (int i = 0; i < trackIndex; i++) {
        trackTop +=
            widget.trackHeightState.clipHeights[regularTracks[i].id] ??
            UIConstants.defaultClipHeight;
        // Include automation height when lanes are shown (global toggle)
        if (UIConstants.enableAutomation && widget.automationVisible) {
          trackTop +=
              widget.trackHeightState.automationHeights[regularTracks[i].id] ??
              UIConstants.defaultAutomationHeight;
        }
      }
      // Only use clip height for hit testing (clips are in clip area only)
      final trackHeight =
          widget.trackHeightState.clipHeights[regularTracks[trackIndex].id] ??
          UIConstants.defaultClipHeight;
      final trackBottom = trackTop + trackHeight;

      // Check if mouse is within clip bounds
      if (beatPosition >= clipStartBeats &&
          beatPosition <= clipEndBeats &&
          trackAreaY >= trackTop &&
          trackAreaY <= trackBottom) {
        erasedAudioClipIds.add(clip.clipId);
        _pendingAudioClipsToErase.add(clip);
        // Update UI immediately to show clip as "erased" (visual feedback)
        setState(() {});
      }
    }

    // Check MIDI clips
    for (final midiClip in widget.midiClips) {
      if (erasedMidiClipIds.contains(midiClip.clipId)) continue;

      final clipStartBeats = midiClip.startTime;
      final clipEndBeats = midiClip.startTime + midiClip.duration;

      // Find track Y position using actual track heights (regularTracks matches rendering order)
      final trackIndex = regularTracks.indexWhere(
        (t) => t.id == midiClip.trackId,
      );
      if (trackIndex < 0) continue;

      double trackTop = 0.0;
      for (int i = 0; i < trackIndex; i++) {
        trackTop +=
            widget.trackHeightState.clipHeights[regularTracks[i].id] ??
            UIConstants.defaultClipHeight;
        // Include automation height when lanes are shown (global toggle)
        if (UIConstants.enableAutomation && widget.automationVisible) {
          trackTop +=
              widget.trackHeightState.automationHeights[regularTracks[i].id] ??
              UIConstants.defaultAutomationHeight;
        }
      }
      // Only use clip height for hit testing (clips are in clip area only)
      final trackHeight =
          widget.trackHeightState.clipHeights[regularTracks[trackIndex].id] ??
          UIConstants.defaultClipHeight;
      final trackBottom = trackTop + trackHeight;

      // Check if mouse is within clip bounds
      if (beatPosition >= clipStartBeats &&
          beatPosition <= clipEndBeats &&
          trackAreaY >= trackTop &&
          trackAreaY <= trackBottom) {
        erasedMidiClipIds.add(midiClip.clipId);
        _pendingMidiClipsToErase.add((midiClip.clipId, midiClip.trackId));
        // Update UI immediately to show clip as "erased" (visual feedback)
        setState(() {});
      }
    }
  }

  /// Stop eraser mode and batch-delete all marked clips (single undo action)
  void _stopErasing() {
    if (isErasing) {
      // Batch delete all pending clips (single undo action for all)
      if (_pendingMidiClipsToErase.isNotEmpty) {
        widget.midiClipCallbacks.onBatchDeleted?.call(
          _pendingMidiClipsToErase.toList(),
        );
      }
      if (_pendingAudioClipsToErase.isNotEmpty) {
        widget.audioClipCallbacks.onBatchDeleted?.call(
          _pendingAudioClipsToErase.toList(),
        );
      }
    }
    setState(() {
      isErasing = false;
      erasedAudioClipIds.clear();
      erasedMidiClipIds.clear();
      _pendingAudioClipsToErase.clear();
      _pendingMidiClipsToErase.clear();
    });
  }

  // ========================================================================
  // SPLIT PREVIEW (hover shows line, Alt+click splits)
  // ========================================================================

  /// Update split preview for MIDI clip
  void _updateMidiClipSplitPreview(
    int clipId,
    double localX,
    double clipWidth,
    MidiClipData clip,
  ) {
    // Convert local X position to beat position within clip
    final positionRatio = localX / clipWidth;
    final beatPosition = positionRatio * clip.duration;

    setState(() {
      splitPreviewAudioClipId = null;
      splitPreviewMidiClipId = clipId;
      splitPreviewBeatPosition = beatPosition;
    });
  }

  /// Clear split preview
  void _clearSplitPreview() {
    setState(() {
      splitPreviewAudioClipId = null;
      splitPreviewMidiClipId = null;
    });
  }

  /// Split audio clip at preview position (slice tool)
  void _splitAudioClipAtPreview(ClipData clip) {
    if (splitPreviewAudioClipId != clip.clipId) return;

    // Convert beat position back to seconds
    final splitTimeRelative = splitPreviewBeatPosition * (60.0 / widget.tempo);
    final splitTimeAbsolute = clip.startTime + splitTimeRelative;

    runAudioSplit(clip, splitTimeAbsolute);
    _clearSplitPreview();
  }

  /// The one true audio split: an undoable [SplitAudioClipCommand] that owns all
  /// engine work (trim the left clip, register/remove the right clip), with these
  /// callbacks only mutating the on-screen `clips` list. Shared by the slice tool
  /// and the Cmd+E path so audio split is always engine-synced and undoable
  /// (the Cmd+E path used to mutate the UI only and never touch the engine).
  void runAudioSplit(ClipData clip, double splitTimeAbsolute) {
    final splitTimeRelative = splitTimeAbsolute - clip.startTime;

    // Validate split point is within clip bounds.
    if (splitTimeRelative <= 0 || splitTimeRelative >= clip.duration) return;

    final originalClip = clip;

    // The engine assigns the right clip's id when the command runs; remember it
    // so undo can remove exactly that clip from the UI list.
    int? rightUiClipId;

    final command = SplitAudioClipCommand(
      originalClipId: clip.clipId,
      originalTrackId: clip.trackId,
      originalFilePath: clip.filePath,
      originalStartTime: clip.startTime,
      originalDuration: clip.duration,
      originalOffset: clip.offset,
      originalWaveformPeaks: clip.waveformPeaks,
      splitPointSeconds: splitTimeAbsolute,
      onSplit: (rightEngineClipId) {
        if (!mounted) return;
        rightUiClipId = rightEngineClipId;

        // Left clip (original, shortened - reuse original ID)
        final leftClip = clip.copyWith(duration: splitTimeRelative);

        // Right clip (new, starting at split point) using the engine id
        final rightClip = clip.copyWith(
          clipId: rightEngineClipId,
          startTime: splitTimeAbsolute,
          duration: clip.duration - splitTimeRelative,
          offset: clip.offset + splitTimeRelative,
        );

        setState(() {
          final index = clips.indexWhere((c) => c.clipId == clip.clipId);
          if (index >= 0) {
            clips[index] = leftClip;
            clips.add(rightClip);
          }
          selectedAudioClipId = rightEngineClipId; // continued-editing focus
        });
      },
      onUndo: () {
        if (!mounted) return;
        setState(() {
          // Remove the right clip (by the engine id assigned on split)
          if (rightUiClipId != null) {
            clips.removeWhere((c) => c.clipId == rightUiClipId);
          }
          // Restore original left clip
          final index = clips.indexWhere((c) => c.clipId == clip.clipId);
          if (index >= 0) {
            clips[index] = originalClip;
          } else {
            clips.add(originalClip);
          }
          selectedAudioClipId = originalClip.clipId;
        });
      },
    );

    UndoRedoManager().execute(command);
  }

  /// Split MIDI clip at preview position
  Future<void> _splitMidiClipAtPreview(MidiClipData clip) async {
    if (splitPreviewMidiClipId != clip.clipId) return;

    // Split point in beats relative to clip start
    final splitPointBeats = splitPreviewBeatPosition;

    // Validate split point is within clip bounds
    if (splitPointBeats <= 0 || splitPointBeats >= clip.duration) {
      _clearSplitPreview();
      return;
    }

    // Route through the daw layer, which builds an undoable SplitMidiClipCommand
    // with engine+manager primitives. Must NOT go through onCopied/onDeleted —
    // those nest commands and destroy the right region on undo.
    widget.midiClipCallbacks.onSplit?.call(clip, splitPointBeats);
    _clearSplitPreview();
  }

  Widget _applyRecordingMask({
    required Widget child,
    required double clipX,
    required double clipWidth,
    required double pixelsPerUnit,
    double? recStart,
    double? recEnd,
    bool exclude = false,
  }) {
    if (exclude || recStart == null || recEnd == null) return child;
    final recStartPx = recStart * pixelsPerUnit - clipX;
    final recEndPx = recEnd * pixelsPerUnit - clipX;
    if (recStartPx >= clipWidth || recEndPx <= 0) return child;
    return ClipPath(
      clipper: RecordingMaskClipper(
        excludeStartPx: recStartPx,
        excludeEndPx: recEndPx,
      ),
      child: child,
    );
  }

  Widget _buildClip(
    ClipData clip,
    Color trackColor,
    double trackHeight, {
    double? recStartBeat,
    double? recEndBeat,
  }) {
    // Calculate clip width based on warp state:
    // - Warp ON: clip syncs to project tempo, so it covers a fixed number of beats
    // - Warp OFF: clip is fixed-length in seconds, so width changes with tempo
    final double clipWidth;
    if (clip.editData?.syncEnabled ?? false) {
      // Warp ON: use beat-based width (fixed visual size regardless of tempo)
      final beatsInClip =
          clip.duration * ((clip.editData?.bpm ?? 120.0) / 60.0);
      clipWidth = beatsInClip * pixelsPerBeat;
    } else {
      // Warp OFF: use time-based width (stretches with tempo)
      clipWidth = clip.duration * pixelsPerSecond;
    }
    // Use dragged position if this clip is being dragged OR is part of the selection being dragged
    // BUT NOT for copy drags - the original stays in place, only the ghost moves
    double displayStartTime;

    // Check if being dragged via audio clip drag
    final isBeingDraggedViaAudio =
        draggingClipId != null &&
        (draggingClipId == clip.clipId ||
            selectedAudioClipIds.contains(clip.clipId)) &&
        !isCopyDrag;

    // Check if being dragged via MIDI clip drag (cross-type multi-track selection)
    final isBeingDraggedViaMidi =
        draggingMidiClipId != null &&
        selectedAudioClipIds.contains(clip.clipId) &&
        !isCopyDrag;

    if (isBeingDraggedViaAudio) {
      // Calculate delta in seconds from audio drag
      final dragDeltaSeconds = (dragCurrentX - dragStartX) / pixelsPerSecond;

      // Snap the delta: convert to beats, snap dragged clip's new position, derive delta
      final beatsPerSecond = widget.tempo / 60.0;
      final rawBeats = (dragStartTime + dragDeltaSeconds) * beatsPerSecond;
      final snappedBeats = snapToGrid(rawBeats);
      final snappedNewStartTime = snappedBeats / beatsPerSecond;
      final snappedDeltaSeconds = snappedNewStartTime - dragStartTime;

      // Apply the same delta to this clip
      displayStartTime = (clip.startTime + snappedDeltaSeconds).clamp(
        0.0,
        double.infinity,
      );
    } else if (isBeingDraggedViaMidi) {
      // Calculate delta from MIDI drag (beats) and convert to seconds
      final dragDeltaBeats =
          (midiDragCurrentX - midiDragStartX) / pixelsPerBeat;

      // Snap the delta based on the MIDI drag position
      var snappedDeltaBeats = dragDeltaBeats;
      if (!snapBypassActive) {
        final snapResolution = getGridSnapResolution();
        final draggedClipNewPos = midiDragStartTime + dragDeltaBeats;
        final snappedPos =
            (draggedClipNewPos / snapResolution).round() * snapResolution;
        snappedDeltaBeats = snappedPos - midiDragStartTime;
      }

      // Convert beats delta to seconds delta
      final beatsPerSecond = widget.tempo / 60.0;
      final snappedDeltaSeconds = snappedDeltaBeats / beatsPerSecond;

      // Apply the same delta to this clip
      displayStartTime = (clip.startTime + snappedDeltaSeconds).clamp(
        0.0,
        double.infinity,
      );
    } else {
      displayStartTime = clip.startTime;
    }
    final clipX =
        displayStartTime.clamp(0.0, double.infinity) * pixelsPerSecond;
    final isDragging = draggingClipId == clip.clipId;
    final isSelected = selectedAudioClipIds.contains(clip.clipId);

    const headerHeight = UIConstants.clipHeaderHeight;
    final totalHeight =
        trackHeight -
        UIConstants.clipContentPadding; // Track height minus padding

    // Check if this clip has split preview active
    final hasSplitPreview = splitPreviewAudioClipId == clip.clipId;
    final splitPreviewX = hasSplitPreview
        ? (splitPreviewBeatPosition / (clip.duration * (widget.tempo / 60.0))) *
              clipWidth
        : 0.0;

    return Positioned(
      key: ValueKey('audio_clip_${clip.clipId}'),
      left: clipX,
      top: 0,
      child: _applyRecordingMask(
        clipX: clipX,
        clipWidth: clipWidth,
        pixelsPerUnit: pixelsPerBeat,
        recStart: recStartBeat,
        recEnd: recEndBeat,
        child: GestureDetector(
          onTapDown: (details) {
            // Check modifier keys directly at click time (more reliable than cached tempToolMode)
            final modifiers = ModifierKeyState.current();
            final tool = modifiers.getOverrideToolMode() ?? widget.toolMode;

            // IMPORTANT: Capture copy modifier state at tap down
            // This is needed because by the time onHorizontalDragStart fires,
            // the modifier key state may have changed (widget rebuild, etc.)
            audioPointerDownWasCopyModifier =
                modifiers.isCtrlOrCmd || tool == ToolMode.duplicate;

            // Eraser tool: start batched erasing (supports drag-to-delete like piano roll)
            if (tool == ToolMode.eraser) {
              // Convert local click position to global for eraser system
              final RenderBox? box = context.findRenderObject() as RenderBox?;
              if (box != null) {
                final globalPos = box.localToGlobal(details.localPosition);
                _startErasing(globalPos);
              }
              return;
            }

            // Slice tool: split at click position
            if (tool == ToolMode.slice) {
              // Calculate split position from click (audio clips use seconds)
              final clickXInClip = details.localPosition.dx;
              final clickSecondsInClip = clickXInClip / pixelsPerSecond;
              if (clickSecondsInClip > 0 &&
                  clickSecondsInClip < clip.duration) {
                // Convert to beats for split preview
                final beatsPerSecond = widget.tempo / 60.0;
                setState(() {
                  splitPreviewAudioClipId = clip.clipId;
                  splitPreviewBeatPosition =
                      clickSecondsInClip * beatsPerSecond;
                });
                _splitAudioClipAtPreview(clip);
              }
              return;
            }

            // DRAW, SELECT, or DUPLICATE TOOL: Handle selection on tap down
            // (Duplicate only creates copy on drag-end, not click)
            final wasAlreadySelected = selectedAudioClipIds.contains(
              clip.clipId,
            );

            // If clicking on already-selected clip without Shift, defer single-selection to tap-up
            // (allows multi-drag if user drags instead of clicking)
            if (wasAlreadySelected && !modifiers.isShiftPressed) {
              pendingAudioClipTapSelection = clip.clipId;
              audioSelectionBeforeReplace = null;
            } else {
              pendingAudioClipTapSelection = null;
              // Snapshot the selection a plain click is about to replace, so
              // tap-up can repair it if Shift turns out to be held (missed
              // modifier read — see field doc).
              audioSelectionBeforeReplace =
                  !modifiers.isShiftPressed && !wasAlreadySelected
                  ? Set.from(selectedAudioClipIds)
                  : null;
              selectAudioClipMulti(
                clip.clipId,
                addToSelection: false,
                toggleSelection: modifiers.isShiftPressed,
              );
            }
            // Deselect any MIDI clip (notify parent)
            widget.midiClipCallbacks.onSelected?.call(null, null);
          },
          onTapUp: (details) {
            // Stop erasing if in eraser mode (single click delete)
            if (isErasing) {
              _stopErasing();
              return;
            }

            // Re-read Shift at tap-up: the pointer-down read can miss a
            // modifier pressed while the window wasn't key.
            final shiftAtTapUp = ModifierKeyState.current().isShiftPressed;

            // If we had a pending tap selection (clicked on already-selected clip),
            // now reduce to single selection since no drag occurred — unless
            // Shift is held (shift-click must not collapse the multi-selection)
            if (pendingAudioClipTapSelection == clip.clipId && !shiftAtTapUp) {
              selectAudioClipMulti(clip.clipId, forceSelect: true);
            } else if (shiftAtTapUp && audioSelectionBeforeReplace != null) {
              // Shift was missed at pointer-down and a plain-click replace
              // ran — repair it into the intended additive shift-click.
              setState(() {
                selectedAudioClipIds
                  ..addAll(audioSelectionBeforeReplace!)
                  ..add(clip.clipId);
              });
            }
            pendingAudioClipTapSelection = null;
            audioSelectionBeforeReplace = null;
          },
          onSecondaryTapDown: (details) {
            // Right-click: show context menu
            showAudioClipContextMenu(details.globalPosition, clip);
          },
          onHorizontalDragStart: (details) {
            // Clear pending tap selection - user is dragging, not clicking
            pendingAudioClipTapSelection = null;
            audioSelectionBeforeReplace = null;

            // Check modifier keys at drag start
            final modifiers = ModifierKeyState.current();
            final tool = modifiers.getOverrideToolMode() ?? widget.toolMode;

            // Eraser mode: block all drag operations (erasing handled by onTapDown + onHorizontalDragUpdate)
            if (tool == ToolMode.eraser) return;

            // Slice mode: block drag (slicing is handled by onTapDown)
            if (tool == ToolMode.slice) return;

            // Check copy modifier: use captured state from tap down, OR check current state
            // (onTapDown might not fire if drag starts immediately)
            final isDuplicate =
                audioPointerDownWasCopyModifier ||
                modifiers.isCtrlOrCmd ||
                tool == ToolMode.duplicate;

            // Check if this clip is in the multi-selection
            final isInMultiSelection = selectedAudioClipIds.contains(
              clip.clipId,
            );

            // Capture the clips to drag/copy at drag START (before any state changes)
            final Set<int> clipIdsToProcess;
            if (isInMultiSelection) {
              // Dragging a selected clip - process all selected clips
              clipIdsToProcess = Set.from(selectedAudioClipIds);
            } else {
              // Dragging an unselected clip - only process this clip
              clipIdsToProcess = {clip.clipId};
            }

            setState(() {
              // Update audio selection to match what we're processing
              // NOTE: Don't clear MIDI selection - we want to drag both types together
              selectedAudioClipIds.clear();
              selectedAudioClipIds.addAll(clipIdsToProcess);

              selectedAudioClipId = clip.clipId;
              draggingClipId = clip.clipId;
              dragStartTime = clip.startTime;
              dragStartX = details.globalPosition.dx;
              dragCurrentX = details.globalPosition.dx;
              isCopyDrag =
                  isDuplicate; // Duplicate tool or Cmd/Ctrl = copy drag
            });
          },
          onHorizontalDragUpdate: (details) {
            // Continue erasing if in eraser mode
            if (isErasing) {
              _eraseClipsAt(details.globalPosition);
              return;
            }

            // Skip in eraser/slice mode (Draw mode allows moving)
            final tool = effectiveToolMode;
            if (tool == ToolMode.eraser || tool == ToolMode.slice) return;

            setState(() {
              dragCurrentX = details.globalPosition.dx;
            });
          },
          onHorizontalDragEnd: (details) async {
            // Stop erasing if in eraser mode
            if (isErasing) {
              _stopErasing();
              return;
            }

            if (draggingClipId == null) return;

            // Calculate delta in seconds
            final dragDeltaSeconds =
                (dragCurrentX - dragStartX) / pixelsPerSecond;

            // Snap the delta: convert to beats, snap dragged clip's new position, derive delta
            final beatsPerSecond = widget.tempo / 60.0;
            final rawBeats =
                (dragStartTime + dragDeltaSeconds) * beatsPerSecond;
            final snappedBeats = snapToGrid(rawBeats);
            final snappedNewStartTime = snappedBeats / beatsPerSecond;
            final snappedDeltaSeconds = snappedNewStartTime - dragStartTime;

            if (isCopyDrag) {
              // Get all selected clips BEFORE clearing selection
              final audioClipsToCopy = clips
                  .where((c) => selectedAudioClipIds.contains(c.clipId))
                  .toList();
              final midiClipsToCopy = widget.midiClips
                  .where((c) => selectedMidiClipIds.contains(c.clipId))
                  .toList();

              // Convert delta to beats for MIDI clips
              final snappedDeltaBeats = snappedDeltaSeconds * beatsPerSecond;

              // Clear internal selection - we'll select new clips after duplication
              selectedAudioClipIds.clear();
              selectedMidiClipIds.clear();

              // Duplicate ALL selected audio clips with same offset delta
              for (final selectedClip in audioClipsToCopy) {
                final newStartTime =
                    (selectedClip.startTime + snappedDeltaSeconds).clamp(
                      0.0,
                      double.infinity,
                    );
                duplicateAudioClip(selectedClip, atPosition: newStartTime);
              }

              // Duplicate ALL selected MIDI clips with same offset delta (in beats)
              for (final midiClip in midiClipsToCopy) {
                final newStartBeats = (midiClip.startTime + snappedDeltaBeats)
                    .clamp(0.0, double.infinity);
                widget.midiClipCallbacks.onCopied?.call(
                  midiClip,
                  newStartBeats,
                );
              }

              // After all copies are made, select the new clips
              // Use addPostFrameCallback to wait for the widget tree to rebuild
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                // Store original clip IDs for exclusion
                final originalAudioClipIds = audioClipsToCopy
                    .map((c) => c.clipId)
                    .toSet();
                final originalMidiClipIds = midiClipsToCopy
                    .map((c) => c.clipId)
                    .toSet();

                setState(() {
                  // Select new audio clips
                  for (final originalClip in audioClipsToCopy) {
                    final expectedNewStart =
                        (originalClip.startTime + snappedDeltaSeconds).clamp(
                          0.0,
                          double.infinity,
                        );
                    // Find a clip at this position that wasn't an original
                    final newClip = clips
                        .where(
                          (c) =>
                              (c.startTime - expectedNewStart).abs() <
                                  0.01 && // Slightly larger tolerance
                              c.trackId == originalClip.trackId &&
                              !originalAudioClipIds.contains(c.clipId),
                        )
                        .firstOrNull;
                    if (newClip != null) {
                      selectedAudioClipIds.add(newClip.clipId);
                    }
                  }

                  // Select new MIDI clips
                  for (final originalClip in midiClipsToCopy) {
                    final expectedNewStart =
                        (originalClip.startTime + snappedDeltaBeats).clamp(
                          0.0,
                          double.infinity,
                        );
                    // Find a clip at this position that wasn't an original
                    final newClip = widget.midiClips
                        .where(
                          (c) =>
                              (c.startTime - expectedNewStart).abs() < 0.01 &&
                              c.trackId == originalClip.trackId &&
                              !originalMidiClipIds.contains(c.clipId),
                        )
                        .firstOrNull;
                    if (newClip != null) {
                      selectedMidiClipIds.add(newClip.clipId);
                    }
                  }
                });
              });
            } else {
              // Move: update ALL selected clips by the same delta

              // Convert delta to beats for MIDI clips
              final snappedDeltaBeats = snappedDeltaSeconds * beatsPerSecond;

              // Collect every clip's move command so the whole drag is a single
              // undo step (one Ctrl+Z reverts all moved clips, not just one).
              final moveCommands = <Command>[];

              // Move audio clips
              final selectedAudioClips = clips
                  .where((c) => selectedAudioClipIds.contains(c.clipId))
                  .toList();

              for (final selectedClip in selectedAudioClips) {
                final newStartTime =
                    (selectedClip.startTime + snappedDeltaSeconds).clamp(
                      0.0,
                      double.infinity,
                    );

                // Only create command if position actually changed
                if ((newStartTime - selectedClip.startTime).abs() > 0.001) {
                  Log.d(
                    '[OVERLAP] Audio clip drag-end: clip ${selectedClip.clipId} moved ${selectedClip.startTime.toStringAsFixed(3)} → ${newStartTime.toStringAsFixed(3)}s on track ${selectedClip.trackId}',
                  );

                  // Resolve overlaps at the new position (exclude the moved clip).
                  final overlapResult = ClipOverlapHandler.resolveAudioOverlaps(
                    newStart: newStartTime,
                    newEnd: newStartTime + selectedClip.duration,
                    existingClips: List<ClipData>.from(clips),
                    trackId: selectedClip.trackId,
                    excludeClipId: selectedClip.clipId,
                  );
                  // H-11: the overlap destruction used to be applied here
                  // destructively (un-undoable). Compose it into the same undo
                  // step as the move so one Ctrl+Z restores both the moved clip
                  // and any overwritten neighbour. Added before the move command
                  // so execute resolves overlaps then moves, and undo reverses.
                  if (overlapResult.hasChanges) {
                    moveCommands.add(
                      ResolveAudioOverlapCommand(
                        result: overlapResult,
                        uiRemoveClip: (cId) =>
                            clips.removeWhere((c) => c.clipId == cId),
                        uiUpdateClip: (clip) {
                          final idx = clips.indexWhere(
                            (c) => c.clipId == clip.clipId,
                          );
                          if (idx >= 0) {
                            clips[idx] = clip;
                          } else {
                            clips.add(clip);
                          }
                        },
                        uiAddClip: (clip) => clips.add(clip),
                      ),
                    );
                  }

                  moveCommands.add(
                    MoveAudioClipCommand(
                      trackId: selectedClip.trackId,
                      clipId: selectedClip.clipId,
                      clipName: selectedClip.fileName,
                      newStartTime: newStartTime,
                      oldStartTime: selectedClip.startTime,
                      onClipMoved: (cId, startTime) {
                        final idx = clips.indexWhere((c) => c.clipId == cId);
                        if (idx >= 0) {
                          clips[idx] = clips[idx].copyWith(
                            startTime: startTime,
                          );
                        }
                      },
                    ),
                  );
                }
              }
              // Single setState to flush all audio clip move + overlap changes
              if (selectedAudioClips.isNotEmpty) {
                setState(() {});
              }

              // Move MIDI clips
              final selectedMidiClips = widget.midiClips
                  .where((c) => selectedMidiClipIds.contains(c.clipId))
                  .toList();

              for (final midiClip in selectedMidiClips) {
                final newStartBeats = (midiClip.startTime + snappedDeltaBeats)
                    .clamp(0.0, double.infinity);

                Log.d(
                  '[OVERLAP] MIDI clip drag-end: clip ${midiClip.clipId} "${midiClip.name}" moved ${midiClip.startTime.toStringAsFixed(3)} → ${newStartBeats.toStringAsFixed(3)} beats on track ${midiClip.trackId}',
                );
                // Resolve MIDI overlaps at new position (exclude the moved clip)
                final midiOverlap = ClipOverlapHandler.resolveMidiOverlaps(
                  newStart: newStartBeats,
                  newEnd: newStartBeats + midiClip.duration,
                  existingClips: List<MidiClipData>.from(widget.midiClips),
                  trackId: midiClip.trackId,
                  excludeClipId: midiClip.clipId,
                );
                // H-11: compose the overlap destruction into the same undo step
                // as the move (was applied destructively via onOverlapResolved).
                if (midiOverlap.hasChanges) {
                  final overlapCmd = widget
                      .midiClipCallbacks
                      .buildMidiOverlapCommand
                      ?.call(midiOverlap);
                  if (overlapCmd != null) moveCommands.add(overlapCmd);
                }

                final newStartTimeSeconds = newStartBeats / beatsPerSecond;
                final rustClipId =
                    widget.getRustClipId?.call(midiClip.clipId) ??
                    midiClip.clipId;
                widget.audioEngine?.setClipStartTime(
                  midiClip.trackId,
                  rustClipId,
                  newStartTimeSeconds,
                );
                final updatedClip = midiClip.copyWith(startTime: newStartBeats);
                widget.midiClipCallbacks.onUpdated?.call(updatedClip);
                final midiMove = _buildMidiClipMoveCommand(
                  midiClip,
                  midiClip.startTime,
                  newStartBeats,
                );
                if (midiMove != null) moveCommands.add(midiMove);
              }

              // Submit all moves (audio + MIDI) as one undo step.
              await _executeGroupedMoves(moveCommands);

              // Force UI refresh after parent processes MIDI updates
              if (selectedMidiClips.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() {});
                });
              }
            }

            setState(() {
              draggingClipId = null;
              isCopyDrag = false;
            });
          },
          child: MouseRegion(
            cursor: trimmingAudioClipId == clip.clipId
                ? (isTrimmingLeftEdge
                      ? SystemMouseCursors.resizeLeft
                      : SystemMouseCursors.resizeRight)
                : _getCursorForTool(effectiveToolMode, isOverClip: true),
            onHover: (event) {
              // Update temp tool mode on hover (in case modifier keys changed)
              updateTempToolMode();
            },
            onExit: (_) {
              if (splitPreviewAudioClipId == clip.clipId) {
                _clearSplitPreview();
              }
            },
            child: Builder(
              builder: (context) {
                // Calculate loop boundary positions for audio clips (like MIDI clips)
                // loopLength is in seconds, need to calculate loop boundary X positions in pixels
                final loopWidthPixels = clip.loopLength * pixelsPerSecond;
                final isLooped =
                    clip.canRepeat && clip.duration > clip.loopLength;
                final loopBoundaryPositions = isLooped
                    ? _calculateLoopBoundaryPositions(
                        loopWidthPixels, // loopLength in pixels
                        clipWidth, // clipDuration in pixels
                        clipWidth,
                      )
                    : <double>[];

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Main clip container with notched border (like MIDI clips)
                    ClipPath(
                      clipper: ClipPathClipper(
                        cornerRadius: 4,
                        notchRadius: 4,
                        loopBoundaryXPositions: loopBoundaryPositions,
                      ),
                      child: SizedBox(
                        width: clipWidth,
                        height: totalHeight,
                        child: Column(
                          children: [
                            // Header with track color (simplified when clip is too narrow)
                            Container(
                              height: headerHeight,
                              decoration: BoxDecoration(
                                color: trackColor,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3),
                                ),
                              ),
                              padding: clipWidth > 30
                                  ? const EdgeInsets.symmetric(horizontal: 6)
                                  : null,
                              child: clipWidth > 30
                                  ? Row(
                                      children: [
                                        Icon(
                                          BI.musicNote,
                                          size: 12,
                                          color: context.colors.textPrimary,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            clip.fileName,
                                            style: TextStyle(
                                              color: context.colors.textPrimary,
                                              fontSize: BT.fontLabel,
                                              fontWeight: BT.weightMedium,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    )
                                  : null, // Just show colored bar for very narrow clips
                            ),
                            // Content area with waveform (transparent background)
                            Expanded(
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(3),
                                ),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    // Calculate visual gain from clip's editData
                                    final clipGainDb =
                                        clip.editData?.gainDb ?? 0.0;
                                    final clipVisualGain = clipGainDb > -70
                                        ? math
                                              .pow(10, clipGainDb / 20)
                                              .toDouble()
                                        : 0.0;
                                    // Calculate visible duration for non-looped clips
                                    // For looped: each iteration shows full loopLength
                                    // For non-looped: show only clip.duration (may be trimmed)
                                    final visibleDuration = isLooped
                                        ? clip.loopLength
                                        : clip.duration;
                                    return CustomPaint(
                                      size: Size(
                                        constraints.maxWidth,
                                        constraints.maxHeight,
                                      ),
                                      painter: WaveformPainter(
                                        peaks: clip.waveformPeaks,
                                        color: TrackColors.getLighterShade(
                                          trackColor,
                                        ),
                                        visualGain: clipVisualGain,
                                        loopWidth: isLooped
                                            ? loopWidthPixels
                                            : null,
                                        contentDuration: clip
                                            .loopLength, // Full content duration
                                        startOffset:
                                            clip.offset, // Left trim offset
                                        visibleDuration:
                                            visibleDuration, // How much is actually visible
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Border with integrated notches (like MIDI clips)
                    CustomPaint(
                      size: Size(clipWidth, totalHeight),
                      painter: ClipBorderPainter(
                        borderColor: isSelected
                            ? context.colors.textPrimary
                            : trackColor.withValues(alpha: 0.7),
                        trackColor: trackColor,
                        headerHeight: headerHeight,
                        borderWidth: isDragging || isSelected ? 2 : 1,
                        cornerRadius: 4,
                        loopBoundaryXPositions: loopBoundaryPositions,
                      ),
                    ),
                    // Left edge trim handle
                    Positioned(
                      left: 0,
                      top: 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (details) {
                          setState(() {
                            trimmingAudioClipId = clip.clipId;
                            isTrimmingLeftEdge = true;
                            audioTrimStartTime = clip.startTime;
                            audioTrimStartDuration = clip.duration;
                            audioTrimStartOffset = clip.offset;
                            audioTrimStartX = details.globalPosition.dx;
                          });
                        },
                        onHorizontalDragUpdate: (details) {
                          if (trimmingAudioClipId != clip.clipId ||
                              !isTrimmingLeftEdge) {
                            return;
                          }
                          final deltaX =
                              details.globalPosition.dx - audioTrimStartX;
                          final deltaSeconds = deltaX / pixelsPerSecond;

                          // Calculate new start time and duration
                          var newStartTime = audioTrimStartTime + deltaSeconds;
                          var newDuration =
                              audioTrimStartDuration - deltaSeconds;
                          var newOffset = audioTrimStartOffset + deltaSeconds;

                          // Clamp to valid bounds
                          double minStartTime = 0.0;

                          // Overlap blocking: clamp to nearest clip on the left
                          final leftSiblings = clips.where(
                            (c) =>
                                c.trackId == clip.trackId &&
                                c.clipId != clip.clipId,
                          );
                          for (final sibling in leftSiblings) {
                            final siblingEnd =
                                sibling.startTime + sibling.duration;
                            if (siblingEnd <=
                                    audioTrimStartTime +
                                        audioTrimStartDuration &&
                                siblingEnd > minStartTime) {
                              minStartTime = siblingEnd;
                            }
                          }

                          newStartTime = newStartTime.clamp(
                            minStartTime,
                            audioTrimStartTime + audioTrimStartDuration - 0.1,
                          );
                          newDuration =
                              (audioTrimStartTime + audioTrimStartDuration) -
                              newStartTime;
                          newDuration = newDuration.clamp(0.1, double.infinity);
                          newOffset = newOffset.clamp(0.0, double.infinity);

                          setState(() {
                            final index = clips.indexWhere(
                              (c) => c.clipId == clip.clipId,
                            );
                            if (index >= 0) {
                              clips[index] = clips[index].copyWith(
                                startTime: newStartTime,
                                duration: newDuration,
                                offset: newOffset,
                              );
                            }
                          });
                        },
                        onHorizontalDragEnd: (details) async {
                          // Get the trimmed clip values
                          final trimmedClip = clips.firstWhere(
                            (c) => c.clipId == clip.clipId,
                            orElse: () => clip,
                          );

                          // Only create command if values actually changed
                          if ((trimmedClip.startTime - audioTrimStartTime)
                                      .abs() >
                                  0.001 ||
                              (trimmedClip.duration - audioTrimStartDuration)
                                      .abs() >
                                  0.001) {
                            final command = ResizeAudioClipCommand(
                              trackId: trimmedClip.trackId,
                              clipId: trimmedClip.clipId,
                              clipName: trimmedClip.fileName,
                              oldDuration: audioTrimStartDuration,
                              newDuration: trimmedClip.duration,
                              oldOffset: audioTrimStartOffset,
                              newOffset: trimmedClip.offset,
                              oldStartTime: audioTrimStartTime,
                              newStartTime: trimmedClip.startTime,
                              onClipResized:
                                  (clipId, duration, offset, startTime) {
                                    setState(() {
                                      final index = clips.indexWhere(
                                        (c) => c.clipId == clipId,
                                      );
                                      if (index >= 0) {
                                        clips[index] = clips[index].copyWith(
                                          duration: duration,
                                          offset: offset,
                                          startTime: startTime,
                                        );
                                      }
                                    });
                                  },
                            );
                            await UndoRedoManager().execute(command);
                          }

                          if (mounted) {
                            setState(() {
                              trimmingAudioClipId = null;
                              isTrimmingLeftEdge = false;
                            });
                          }
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeLeft,
                          child: Container(
                            width: UIConstants.clipResizeHandleWidth,
                            height: totalHeight,
                            color: Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                    // Right edge trim handle
                    // Audio clips: canRepeat=false limits to loopLength, canRepeat=true allows looping
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Builder(
                        builder: (context) {
                          // Determine if clip can be extended (looping enabled)
                          final canExtend = clip.canRepeat;
                          // Check if we're at or beyond the loop limit
                          final atLoopLimit =
                              !canExtend &&
                              clip.duration >= clip.loopLength - 0.001;

                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragStart: (details) {
                              setState(() {
                                trimmingAudioClipId = clip.clipId;
                                isTrimmingLeftEdge = false;
                                audioTrimStartDuration = clip.duration;
                                audioTrimStartX = details.globalPosition.dx;
                              });
                            },
                            onHorizontalDragUpdate: (details) {
                              if (trimmingAudioClipId != clip.clipId ||
                                  isTrimmingLeftEdge) {
                                return;
                              }
                              final deltaX =
                                  details.globalPosition.dx - audioTrimStartX;
                              final deltaSeconds = deltaX / pixelsPerSecond;

                              // Calculate new duration
                              var newDuration =
                                  audioTrimStartDuration + deltaSeconds;

                              // Audio clips: limit based on canRepeat
                              if (clip.canRepeat) {
                                // Loop enabled: can extend beyond loopLength (content tiles)
                                newDuration = newDuration.clamp(
                                  0.1,
                                  double.infinity,
                                );
                              } else {
                                // Loop disabled: cannot extend beyond loopLength
                                newDuration = newDuration.clamp(
                                  0.1,
                                  clip.loopLength,
                                );
                              }

                              // Overlap blocking: clamp to nearest clip on the right
                              final siblingClips = clips.where(
                                (c) =>
                                    c.trackId == clip.trackId &&
                                    c.clipId != clip.clipId,
                              );
                              for (final sibling in siblingClips) {
                                if (sibling.startTime > clip.startTime) {
                                  final maxDuration =
                                      sibling.startTime - clip.startTime;
                                  if (newDuration > maxDuration) {
                                    newDuration = maxDuration;
                                  }
                                }
                              }

                              setState(() {
                                final index = clips.indexWhere(
                                  (c) => c.clipId == clip.clipId,
                                );
                                if (index >= 0) {
                                  clips[index] = clips[index].copyWith(
                                    duration: newDuration,
                                  );
                                }
                              });
                            },
                            onHorizontalDragEnd: (details) async {
                              // Get the trimmed clip values
                              final trimmedClip = clips.firstWhere(
                                (c) => c.clipId == clip.clipId,
                                orElse: () => clip,
                              );

                              // Only create command if duration actually changed
                              if ((trimmedClip.duration -
                                          audioTrimStartDuration)
                                      .abs() >
                                  0.001) {
                                final command = ResizeAudioClipCommand(
                                  trackId: trimmedClip.trackId,
                                  clipId: trimmedClip.clipId,
                                  clipName: trimmedClip.fileName,
                                  oldDuration: audioTrimStartDuration,
                                  newDuration: trimmedClip.duration,
                                  onClipResized:
                                      (clipId, duration, offset, startTime) {
                                        setState(() {
                                          final index = clips.indexWhere(
                                            (c) => c.clipId == clipId,
                                          );
                                          if (index >= 0) {
                                            clips[index] = clips[index]
                                                .copyWith(duration: duration);
                                          }
                                        });
                                      },
                                );
                                await UndoRedoManager().execute(command);
                              }

                              if (mounted) {
                                setState(() {
                                  trimmingAudioClipId = null;
                                });
                              }
                            },
                            child: Tooltip(
                              message: atLoopLimit
                                  ? 'Drag left to trim, or enable Loop to extend'
                                  : 'Drag to resize',
                              child: MouseRegion(
                                cursor: SystemMouseCursors.resizeRight,
                                child: Container(
                                  width: UIConstants.clipResizeHandleWidth,
                                  height: totalHeight,
                                  color: Colors.transparent,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Split preview line (shown when Alt is pressed and hovering)
                    if (hasSplitPreview)
                      Positioned(
                        left: splitPreviewX,
                        top: 0,
                        child: Container(
                          width: 2,
                          height: totalHeight,
                          color: context.colors.textPrimary.withValues(
                            alpha: 0.8,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMidiClip(
    MidiClipData midiClip,
    Color trackColor,
    double trackHeight, {
    double? recStartBeat,
    double? recEndBeat,
  }) {
    // MIDI clips use beat-based positioning (tempo-independent visual layout)
    final clipStartBeats = midiClip.startTime;
    final clipDurationBeats = midiClip.duration;
    // Ensure minimum width to prevent layout errors (Stack requires finite size)
    final clipWidth = (clipDurationBeats * pixelsPerBeat).clamp(
      10.0,
      double.infinity,
    );

    // Use dragged position if this clip is being dragged OR is part of the selection being dragged
    // BUT NOT for copy drags - the original stays in place, only the ghost moves
    double displayStartBeats;

    // Check if being dragged via MIDI clip drag
    final isBeingDraggedViaMidi =
        draggingMidiClipId != null &&
        (draggingMidiClipId == midiClip.clipId ||
            selectedMidiClipIds.contains(midiClip.clipId)) &&
        !isCopyDrag;

    // Check if being dragged via audio clip drag (cross-type multi-track selection)
    final isBeingDraggedViaAudio =
        draggingClipId != null &&
        selectedMidiClipIds.contains(midiClip.clipId) &&
        !isCopyDrag;

    if (isBeingDraggedViaMidi) {
      final dragDeltaBeats =
          (midiDragCurrentX - midiDragStartX) / pixelsPerBeat;

      // Calculate snapped delta based on the primary dragged clip
      var snappedDeltaBeats = dragDeltaBeats;
      if (!snapBypassActive) {
        final snapResolution = getGridSnapResolution();
        // Snap based on the dragged clip's new position
        final draggedClipNewPos = midiDragStartTime + dragDeltaBeats;
        final snappedPos =
            (draggedClipNewPos / snapResolution).round() * snapResolution;
        snappedDeltaBeats = snappedPos - midiDragStartTime;
      }

      // Apply the same delta to this clip
      displayStartBeats = (clipStartBeats + snappedDeltaBeats).clamp(
        0.0,
        double.infinity,
      );
    } else if (isBeingDraggedViaAudio) {
      // Calculate delta from audio drag (seconds) and convert to beats
      final dragDeltaSeconds = (dragCurrentX - dragStartX) / pixelsPerSecond;

      // Snap the delta: convert to beats, snap dragged clip's new position, derive delta
      final beatsPerSecond = widget.tempo / 60.0;
      final rawBeats = (dragStartTime + dragDeltaSeconds) * beatsPerSecond;
      final snappedBeats = snapToGrid(rawBeats);
      final snappedNewStartTime = snappedBeats / beatsPerSecond;
      final snappedDeltaSeconds = snappedNewStartTime - dragStartTime;

      // Convert seconds delta to beats delta
      final snappedDeltaBeats = snappedDeltaSeconds * beatsPerSecond;

      // Apply the same delta to this clip
      displayStartBeats = (clipStartBeats + snappedDeltaBeats).clamp(
        0.0,
        double.infinity,
      );
    } else {
      displayStartBeats = clipStartBeats;
    }
    final clipX = displayStartBeats * pixelsPerBeat;

    // Use both widget prop (single) and internal multi-selection
    final isSelected =
        widget.selectedMidiClipId == midiClip.clipId ||
        selectedMidiClipIds.contains(midiClip.clipId);
    final isDragging = draggingMidiClipId == midiClip.clipId;

    const headerHeight = UIConstants.clipHeaderHeight;
    final totalHeight =
        trackHeight -
        UIConstants.clipContentPadding; // Track height minus padding
    final isLiveRecording = midiClip.clipId == LiveRecordingNotifier.liveClipId;
    final recordingColor = context.colors.error; // Red for recording indicator

    // Check if this clip has split preview active
    final hasSplitPreview = splitPreviewMidiClipId == midiClip.clipId;
    final splitPreviewX = hasSplitPreview
        ? (splitPreviewBeatPosition / midiClip.duration) * clipWidth
        : 0.0;

    return Positioned(
      key: ValueKey('midi_clip_${midiClip.clipId}'),
      left: clipX,
      top: 0,
      child: _applyRecordingMask(
        clipX: clipX,
        clipWidth: clipWidth,
        pixelsPerUnit: pixelsPerBeat,
        recStart: recStartBeat,
        recEnd: recEndBeat,
        exclude: isLiveRecording,
        child: Listener(
          onPointerDown: isLiveRecording
              ? null
              : (event) {
                  // Immediate selection feedback on pointer down (no gesture delay)
                  if (event.buttons == kPrimaryButton) {
                    // Check modifier keys directly at click time (more reliable than cached tempToolMode)
                    final modifiers = ModifierKeyState.current();
                    final tool =
                        modifiers.getOverrideToolMode() ?? widget.toolMode;

                    // IMPORTANT: Capture copy modifier state at pointer down
                    // This is needed because by the time onHorizontalDragStart fires,
                    // the modifier key state may have changed (widget rebuild, etc.)
                    midiPointerDownWasCopyModifier =
                        modifiers.isCtrlOrCmd || tool == ToolMode.duplicate;

                    // Eraser tool: start batched erasing (supports drag-to-delete like piano roll)
                    if (tool == ToolMode.eraser) {
                      // Convert local click position to global for eraser system
                      final RenderBox? box =
                          context.findRenderObject() as RenderBox?;
                      if (box != null) {
                        final globalPos = box.localToGlobal(
                          event.localPosition,
                        );
                        _startErasing(globalPos);
                      }
                      return;
                    }

                    // Slice tool: split at click position
                    if (tool == ToolMode.slice) {
                      final clickXInClip = event.localPosition.dx;
                      final clickBeatsInClip = clickXInClip / pixelsPerBeat;
                      if (clickBeatsInClip > 0 &&
                          clickBeatsInClip < midiClip.duration) {
                        setState(() {
                          splitPreviewMidiClipId = midiClip.clipId;
                          splitPreviewBeatPosition = clickBeatsInClip;
                        });
                        _splitMidiClipAtPreview(midiClip);
                      }
                      return;
                    }

                    // DRAW, SELECT, or DUPLICATE TOOL: Handle selection
                    // (Duplicate only creates copy on drag-end, not click)
                    final wasAlreadySelected = selectedMidiClipIds.contains(
                      midiClip.clipId,
                    );

                    // If clicking on already-selected clip without Shift, defer single-selection to tap-up
                    // (allows multi-drag if user drags instead of clicking)
                    if (wasAlreadySelected && !modifiers.isShiftPressed) {
                      pendingMidiClipTapSelection = midiClip.clipId;
                      midiSelectionBeforeReplace = null;
                    } else {
                      pendingMidiClipTapSelection = null;
                      // Snapshot the selection a plain click is about to
                      // replace, so tap-up can repair it if Shift turns out
                      // to be held (missed modifier read — see field doc).
                      midiSelectionBeforeReplace =
                          !modifiers.isShiftPressed && !wasAlreadySelected
                          ? Set.from(selectedMidiClipIds)
                          : null;
                      selectMidiClipMulti(
                        midiClip.clipId,
                        addToSelection: false,
                        toggleSelection: modifiers.isShiftPressed,
                      );
                    }

                    // Notify parent about selection
                    if (!modifiers.isShiftPressed ||
                        selectedMidiClipIds.contains(midiClip.clipId)) {
                      widget.midiClipCallbacks.onSelected?.call(
                        midiClip.clipId,
                        midiClip,
                      );
                    } else if (selectedMidiClipIds.isEmpty) {
                      widget.midiClipCallbacks.onSelected?.call(null, null);
                    }
                  }
                },
          child: GestureDetector(
            onSecondaryTapDown: isLiveRecording
                ? null
                : (details) {
                    showMidiClipContextMenu(details.globalPosition, midiClip);
                  },
            onTapUp: isLiveRecording
                ? null
                : (details) {
                    // Stop erasing if in eraser mode (single click delete)
                    if (isErasing) {
                      _stopErasing();
                      return;
                    }

                    // Re-read Shift at tap-up: the pointer-down read can miss
                    // a modifier pressed while the window wasn't key.
                    final shiftAtTapUp =
                        ModifierKeyState.current().isShiftPressed;

                    // If we had a pending tap selection (clicked on already-selected clip),
                    // now reduce to single selection since no drag occurred —
                    // unless Shift is held, which means this was a shift-click
                    // and collapsing would destroy the multi-selection.
                    if (pendingMidiClipTapSelection == midiClip.clipId &&
                        !shiftAtTapUp) {
                      selectMidiClipMulti(midiClip.clipId, forceSelect: true);
                      widget.midiClipCallbacks.onSelected?.call(
                        midiClip.clipId,
                        midiClip,
                      );
                    } else if (shiftAtTapUp &&
                        midiSelectionBeforeReplace != null) {
                      // Shift was missed at pointer-down and a plain-click
                      // replace ran — repair it into the intended additive
                      // shift-click (previous selection + this clip).
                      setState(() {
                        selectedMidiClipIds
                          ..addAll(midiSelectionBeforeReplace!)
                          ..add(midiClip.clipId);
                      });
                    }
                    pendingMidiClipTapSelection = null;
                    midiSelectionBeforeReplace = null;
                  },
            onHorizontalDragStart: isLiveRecording
                ? null
                : (details) {
                    // Clear pending tap selection - user is dragging, not clicking
                    pendingMidiClipTapSelection = null;
                    midiSelectionBeforeReplace = null;

                    // Check modifier keys at drag start
                    final modifiers = ModifierKeyState.current();
                    final tool =
                        modifiers.getOverrideToolMode() ?? widget.toolMode;

                    // Eraser mode: block all drag operations (erasing handled by onPointerDown + onHorizontalDragUpdate)
                    if (tool == ToolMode.eraser) return;

                    // Slice mode: block drag (slicing is handled by onPointerDown)
                    if (tool == ToolMode.slice) return;

                    // Check copy modifier: use captured state from pointer down, OR check current state
                    // (ensures duplicate works even if pointer down didn't capture the state)
                    final isDuplicate =
                        midiPointerDownWasCopyModifier ||
                        modifiers.isCtrlOrCmd ||
                        tool == ToolMode.duplicate;

                    // Check if this clip is in the multi-selection
                    final isInMultiSelection = selectedMidiClipIds.contains(
                      midiClip.clipId,
                    );

                    // Capture the clips to drag/copy at drag START (before any state changes)
                    // This ensures we have a stable list even if selection changes during drag
                    final Set<int> clipIdsToProcess;
                    if (isInMultiSelection) {
                      // Dragging a selected clip - process all selected clips
                      clipIdsToProcess = Set.from(selectedMidiClipIds);
                    } else {
                      // Dragging an unselected clip - only process this clip
                      clipIdsToProcess = {midiClip.clipId};
                    }

                    setState(() {
                      // Update MIDI selection to match what we're processing
                      // NOTE: Don't clear audio selection - we want to drag both types together
                      selectedMidiClipIds.clear();
                      selectedMidiClipIds.addAll(clipIdsToProcess);

                      draggingMidiClipId = midiClip.clipId;
                      midiDragStartTime = midiClip.startTime;
                      midiDragStartX = details.globalPosition.dx;
                      midiDragCurrentX = details.globalPosition.dx;
                      isCopyDrag =
                          isDuplicate; // Use captured state from pointer down
                    });
                  },
            onHorizontalDragUpdate: isLiveRecording
                ? null
                : (details) {
                    // Continue erasing if in eraser mode
                    if (isErasing) {
                      _eraseClipsAt(details.globalPosition);
                      return;
                    }

                    // Skip in eraser/slice mode (Draw mode allows moving)
                    final tool = effectiveToolMode;
                    if (tool == ToolMode.eraser || tool == ToolMode.slice) {
                      return;
                    }

                    // Shift bypasses snap (spec v2.0)
                    final bypassSnap =
                        ModifierKeyState.current().isShiftPressed;

                    setState(() {
                      midiDragCurrentX = details.globalPosition.dx;
                      snapBypassActive = bypassSnap;
                    });
                  },
            onHorizontalDragEnd: isLiveRecording
                ? null
                : (details) async {
                    // Stop erasing if in eraser mode
                    if (isErasing) {
                      _stopErasing();
                      return;
                    }

                    if (draggingMidiClipId == null) return;

                    // Calculate delta in beats
                    final dragDeltaBeats =
                        (midiDragCurrentX - midiDragStartX) / pixelsPerBeat;

                    // Snap the delta (not absolute position) for consistent multi-clip movement
                    var snappedDeltaBeats = dragDeltaBeats;
                    if (!snapBypassActive) {
                      final snapResolution = getGridSnapResolution();
                      // Snap the dragged clip's new position, then derive delta
                      final newStartBeats =
                          ((midiDragStartTime + dragDeltaBeats) /
                                  snapResolution)
                              .round() *
                          snapResolution;
                      snappedDeltaBeats = newStartBeats - midiDragStartTime;
                    }

                    // Convert delta to seconds for audio clips
                    final beatsPerSecond = widget.tempo / 60.0;
                    final snappedDeltaSeconds =
                        snappedDeltaBeats / beatsPerSecond;

                    if (isCopyDrag) {
                      // Get all selected clips BEFORE clearing selection
                      final midiClipsToCopy = widget.midiClips
                          .where((c) => selectedMidiClipIds.contains(c.clipId))
                          .toList();
                      final audioClipsToCopy = clips
                          .where((c) => selectedAudioClipIds.contains(c.clipId))
                          .toList();

                      // Clear internal selection - new copies will be selected after creation
                      selectedMidiClipIds.clear();
                      selectedAudioClipIds.clear();

                      // Copy ALL selected MIDI clips with same offset delta
                      // The parent will handle selecting the new clips via onMidiClipCopied callback
                      for (final clip in midiClipsToCopy) {
                        final newStartBeats =
                            (clip.startTime + snappedDeltaBeats).clamp(
                              0.0,
                              double.infinity,
                            );
                        widget.midiClipCallbacks.onCopied?.call(
                          clip,
                          newStartBeats,
                        );
                      }

                      // Copy ALL selected audio clips with same offset delta (in seconds)
                      for (final audioClip in audioClipsToCopy) {
                        final newStartTime =
                            (audioClip.startTime + snappedDeltaSeconds).clamp(
                              0.0,
                              double.infinity,
                            );
                        duplicateAudioClip(audioClip, atPosition: newStartTime);
                      }

                      // After all copies are made, we need to select the new clips
                      // The new clips should now be at the end of widget.midiClips
                      // Select them by finding clips that match the expected new positions
                      // Use addPostFrameCallback to wait for the widget tree to rebuild after all
                      // duplicate commands have executed (they're async via undo/redo manager)
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          // Store original clip IDs for exclusion
                          final originalMidiClipIds = midiClipsToCopy
                              .map((c) => c.clipId)
                              .toSet();
                          final originalAudioClipIds = audioClipsToCopy
                              .map((c) => c.clipId)
                              .toSet();

                          // Find newly created MIDI clips by their positions
                          for (final originalClip in midiClipsToCopy) {
                            final expectedNewStart =
                                (originalClip.startTime + snappedDeltaBeats)
                                    .clamp(0.0, double.infinity);
                            // Find a clip at this position that wasn't an original
                            final newClip = widget.midiClips
                                .where(
                                  (c) =>
                                      (c.startTime - expectedNewStart).abs() <
                                          0.01 && // Slightly larger tolerance
                                      c.trackId == originalClip.trackId &&
                                      !originalMidiClipIds.contains(c.clipId),
                                )
                                .firstOrNull;
                            if (newClip != null) {
                              selectedMidiClipIds.add(newClip.clipId);
                            }
                          }

                          // Find newly created audio clips by their positions
                          for (final originalClip in audioClipsToCopy) {
                            final expectedNewStart =
                                (originalClip.startTime + snappedDeltaSeconds)
                                    .clamp(0.0, double.infinity);
                            final newClip = clips
                                .where(
                                  (c) =>
                                      (c.startTime - expectedNewStart).abs() <
                                          0.01 &&
                                      c.trackId == originalClip.trackId &&
                                      !originalAudioClipIds.contains(c.clipId),
                                )
                                .firstOrNull;
                            if (newClip != null) {
                              selectedAudioClipIds.add(newClip.clipId);
                            }
                          }
                        });
                      });
                    } else {
                      // Move: update ALL selected clips by the same delta

                      // Collect every clip's move command so the whole drag is
                      // a single undo step (one Ctrl+Z reverts all moved clips).
                      final moveCommands = <Command>[];

                      // Move MIDI clips
                      final selectedMidiClips = widget.midiClips
                          .where((c) => selectedMidiClipIds.contains(c.clipId))
                          .toList();

                      for (final clip in selectedMidiClips) {
                        final newStartBeats =
                            (clip.startTime + snappedDeltaBeats).clamp(
                              0.0,
                              double.infinity,
                            );

                        // Resolve MIDI overlaps at new position (exclude the moved clip)
                        final midiOverlap =
                            ClipOverlapHandler.resolveMidiOverlaps(
                              newStart: newStartBeats,
                              newEnd: newStartBeats + clip.duration,
                              existingClips: List<MidiClipData>.from(
                                widget.midiClips,
                              ),
                              trackId: clip.trackId,
                              excludeClipId: clip.clipId,
                            );
                        // H-11: compose overlap destruction into the undo step.
                        if (midiOverlap.hasChanges) {
                          final overlapCmd = widget
                              .midiClipCallbacks
                              .buildMidiOverlapCommand
                              ?.call(midiOverlap);
                          if (overlapCmd != null) moveCommands.add(overlapCmd);
                        }

                        final newStartTimeSeconds =
                            newStartBeats / beatsPerSecond;
                        final rustClipId =
                            widget.getRustClipId?.call(clip.clipId) ??
                            clip.clipId;
                        widget.audioEngine?.setClipStartTime(
                          clip.trackId,
                          rustClipId,
                          newStartTimeSeconds,
                        );
                        final updatedClip = clip.copyWith(
                          startTime: newStartBeats,
                        );
                        widget.midiClipCallbacks.onUpdated?.call(updatedClip);
                        final midiMove = _buildMidiClipMoveCommand(
                          clip,
                          clip.startTime,
                          newStartBeats,
                        );
                        if (midiMove != null) moveCommands.add(midiMove);
                      }

                      // Force UI refresh after parent processes MIDI updates
                      if (selectedMidiClips.isNotEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() {});
                        });
                      }

                      // Move audio clips
                      final selectedAudioClips = clips
                          .where((c) => selectedAudioClipIds.contains(c.clipId))
                          .toList();

                      for (final audioClip in selectedAudioClips) {
                        final newStartTime =
                            (audioClip.startTime + snappedDeltaSeconds).clamp(
                              0.0,
                              double.infinity,
                            );

                        // Only create command if position actually changed
                        if ((newStartTime - audioClip.startTime).abs() >
                            0.001) {
                          // Resolve overlaps at new position (exclude the moved clip itself)
                          final overlapResult =
                              ClipOverlapHandler.resolveAudioOverlaps(
                                newStart: newStartTime,
                                newEnd: newStartTime + audioClip.duration,
                                existingClips: List<ClipData>.from(clips),
                                trackId: audioClip.trackId,
                                excludeClipId: audioClip.clipId,
                              );
                          // H-11: compose the overlap destruction into the undo
                          // step instead of applying it destructively (see block 1).
                          if (overlapResult.hasChanges) {
                            moveCommands.add(
                              ResolveAudioOverlapCommand(
                                result: overlapResult,
                                uiRemoveClip: (cId) =>
                                    clips.removeWhere((c) => c.clipId == cId),
                                uiUpdateClip: (clip) {
                                  final idx = clips.indexWhere(
                                    (c) => c.clipId == clip.clipId,
                                  );
                                  if (idx >= 0) {
                                    clips[idx] = clip;
                                  } else {
                                    clips.add(clip);
                                  }
                                },
                                uiAddClip: (clip) => clips.add(clip),
                              ),
                            );
                          }

                          moveCommands.add(
                            MoveAudioClipCommand(
                              trackId: audioClip.trackId,
                              clipId: audioClip.clipId,
                              clipName: audioClip.fileName,
                              newStartTime: newStartTime,
                              oldStartTime: audioClip.startTime,
                              onClipMoved: (cId, startTime) {
                                final idx = clips.indexWhere(
                                  (c) => c.clipId == cId,
                                );
                                if (idx >= 0) {
                                  clips[idx] = clips[idx].copyWith(
                                    startTime: startTime,
                                  );
                                }
                              },
                            ),
                          );
                        }
                      }

                      // Submit all moves (audio + MIDI) as one undo step.
                      await _executeGroupedMoves(moveCommands);
                    }

                    setState(() {
                      draggingMidiClipId = null;
                      isCopyDrag = false;
                      snapBypassActive = false;
                    });
                  },
            child: MouseRegion(
              cursor: resizingMidiClipId == midiClip.clipId
                  ? SystemMouseCursors.resizeRight
                  : _getCursorForTool(effectiveToolMode, isOverClip: true),
              onHover: (event) {
                // Update temp tool mode on hover (in case modifier keys changed)
                updateTempToolMode();
                // Track hover position for split preview (when using slice tool)
                if (effectiveToolMode == ToolMode.slice) {
                  _updateMidiClipSplitPreview(
                    midiClip.clipId,
                    event.localPosition.dx,
                    clipWidth,
                    midiClip,
                  );
                }
              },
              onExit: (_) {
                if (splitPreviewMidiClipId == midiClip.clipId) {
                  _clearSplitPreview();
                }
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Main clip container with integrated loop boundary notches
                  SizedBox(
                    width: clipWidth,
                    height: totalHeight,
                    child: Stack(
                      children: [
                        // Content clipped to notched shape
                        ClipPath(
                          clipper: ClipPathClipper(
                            cornerRadius: 4,
                            notchRadius: 4,
                            loopBoundaryXPositions:
                                _calculateLoopBoundaryPositions(
                                  midiClip.loopLength,
                                  clipDurationBeats,
                                  clipWidth,
                                ),
                          ),
                          child: Column(
                            children: [
                              // Header (simplified when clip is too narrow)
                              Container(
                                height: headerHeight,
                                decoration: BoxDecoration(
                                  color: isLiveRecording
                                      ? recordingColor
                                      : trackColor,
                                ),
                                padding: clipWidth > 26
                                    ? const EdgeInsets.symmetric(horizontal: 4)
                                    : null,
                                child: clipWidth > 26
                                    ? Row(
                                        children: [
                                          Icon(
                                            BI.piano,
                                            size: 10,
                                            color: context.colors.textPrimary,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              midiClip.name,
                                              style: TextStyle(
                                                color:
                                                    context.colors.textPrimary,
                                                fontSize: 10,
                                                fontWeight: BT.weightSemiBold,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      )
                                    : null, // Just show colored bar for very narrow clips
                              ),
                              // Content area with notes (transparent background)
                              Expanded(
                                child: midiClip.notes.isNotEmpty
                                    ? LayoutBuilder(
                                        builder: (context, constraints) {
                                          return CustomPaint(
                                            size: Size(
                                              constraints.maxWidth,
                                              constraints.maxHeight,
                                            ),
                                            painter: MidiClipPainter(
                                              notes: midiClip.notes,
                                              clipDuration: clipDurationBeats,
                                              loopLength: midiClip.loopLength,
                                              trackColor: isLiveRecording
                                                  ? recordingColor
                                                  : trackColor,
                                              contentStartOffset:
                                                  midiClip.contentStartOffset,
                                            ),
                                          );
                                        },
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                        // Border with integrated notches
                        CustomPaint(
                          size: Size(clipWidth, totalHeight),
                          painter: ClipBorderPainter(
                            borderColor: isLiveRecording
                                ? recordingColor
                                : isSelected
                                ? context.colors.textPrimary
                                : trackColor.withValues(alpha: 0.7),
                            trackColor: isLiveRecording
                                ? recordingColor
                                : trackColor,
                            headerHeight: headerHeight,
                            borderWidth: isDragging || isSelected ? 2 : 1,
                            cornerRadius: 4,
                            loopBoundaryXPositions:
                                _calculateLoopBoundaryPositions(
                                  midiClip.loopLength,
                                  clipDurationBeats,
                                  clipWidth,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Left edge trim handle (hidden during live recording)
                  if (!isLiveRecording)
                    Positioned(
                      left: 0,
                      top: 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (details) {
                          setState(() {
                            trimmingMidiClipId = midiClip.clipId;
                            trimStartTime = midiClip.startTime;
                            trimStartDuration = midiClip.duration;
                            trimStartX = details.globalPosition.dx;
                            trimStartClipSnapshot = midiClip;
                          });
                        },
                        onHorizontalDragUpdate: (details) {
                          if (trimmingMidiClipId != midiClip.clipId) return;
                          final deltaX = details.globalPosition.dx - trimStartX;
                          final deltaBeats = deltaX / pixelsPerBeat;

                          // Calculate new start time and duration
                          var newStartTime = trimStartTime + deltaBeats;
                          var newDuration = trimStartDuration - deltaBeats;

                          // Snap to grid
                          final snapResolution = getGridSnapResolution();
                          newStartTime =
                              (newStartTime / snapResolution).round() *
                              snapResolution;

                          // Overlap blocking: clamp to nearest MIDI clip on the left
                          double midiMinStartTime = 0.0;
                          final midiLeftSiblings = widget.midiClips.where(
                            (c) =>
                                c.trackId == midiClip.trackId &&
                                c.clipId != midiClip.clipId,
                          );
                          for (final sibling in midiLeftSiblings) {
                            final siblingEnd =
                                sibling.startTime + sibling.duration;
                            if (siblingEnd <=
                                    trimStartTime + trimStartDuration &&
                                siblingEnd > midiMinStartTime) {
                              midiMinStartTime = siblingEnd;
                            }
                          }

                          newStartTime = newStartTime.clamp(
                            midiMinStartTime,
                            trimStartTime + trimStartDuration - 1.0,
                          );

                          // Recalculate duration based on snapped start
                          newDuration =
                              (trimStartTime + trimStartDuration) -
                              newStartTime;
                          newDuration = newDuration.clamp(1.0, 256.0);

                          // Filter notes that are now outside the clip (cropped by left trim)
                          final trimOffset = newStartTime - midiClip.startTime;
                          final filteredNotes = midiClip.notes
                              .where((note) {
                                // Keep notes that end after the new start
                                return note.endTime > trimOffset;
                              })
                              .map((note) {
                                // Adjust note start times relative to new clip start
                                final adjustedStart =
                                    note.startTime - trimOffset;
                                if (adjustedStart < 0) {
                                  // Note starts before new clip start - truncate it
                                  return note.copyWith(
                                    startTime: 0,
                                    duration:
                                        note.duration +
                                        adjustedStart, // Reduce duration
                                  );
                                }
                                return note.copyWith(startTime: adjustedStart);
                              })
                              .where((note) => note.duration > 0)
                              .toList();

                          final updatedClip = midiClip.copyWith(
                            startTime: newStartTime,
                            duration: newDuration,
                            loopLength: newDuration.clamp(
                              0.25,
                              midiClip.loopLength,
                            ),
                            notes: filteredNotes,
                          );
                          widget.midiClipCallbacks.onUpdated?.call(updatedClip);
                        },
                        onHorizontalDragEnd: (details) async {
                          final before = trimStartClipSnapshot;
                          if (before != null &&
                              trimmingMidiClipId == midiClip.clipId) {
                            final after = widget.midiClips.firstWhere(
                              (c) => c.clipId == midiClip.clipId,
                              orElse: () => before,
                            );
                            await _commitMidiClipSnapshot(
                              before,
                              after,
                              'Trim MIDI Clip: ${before.name}',
                            );
                          }
                          setState(() {
                            trimmingMidiClipId = null;
                            trimStartClipSnapshot = null;
                          });
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeLeft,
                          child: Container(
                            width: UIConstants.clipResizeHandleWidth,
                            height: totalHeight,
                            color: Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                  // Right edge resize handle (hidden during live recording)
                  if (!isLiveRecording)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (details) {
                          // Don't allow resize if canRepeat is false and already at loopLength
                          if (!midiClip.canRepeat &&
                              midiClip.duration >= midiClip.loopLength) {
                            return;
                          }
                          setState(() {
                            resizingMidiClipId = midiClip.clipId;
                            resizeStartDuration = midiClip.duration;
                            resizeStartX = details.globalPosition.dx;
                            resizeStartClipSnapshot = midiClip;
                          });
                        },
                        onHorizontalDragUpdate: (details) {
                          if (resizingMidiClipId != midiClip.clipId) return;
                          final deltaX =
                              details.globalPosition.dx - resizeStartX;
                          final deltaBeats = deltaX / pixelsPerBeat;
                          var newDuration = (resizeStartDuration + deltaBeats)
                              .clamp(1.0, 256.0);

                          // Snap to grid
                          final snapResolution = getGridSnapResolution();
                          newDuration =
                              (newDuration / snapResolution).round() *
                              snapResolution;
                          newDuration = newDuration.clamp(1.0, 256.0);

                          // Constrain to loopLength if canRepeat is false
                          if (!midiClip.canRepeat) {
                            newDuration = newDuration.clamp(
                              1.0,
                              midiClip.loopLength,
                            );
                          }

                          // Overlap blocking: clamp to nearest MIDI clip on the right
                          final midiSiblings = widget.midiClips.where(
                            (c) =>
                                c.trackId == midiClip.trackId &&
                                c.clipId != midiClip.clipId,
                          );
                          for (final sibling in midiSiblings) {
                            if (sibling.startTime > midiClip.startTime) {
                              final maxDuration =
                                  sibling.startTime - midiClip.startTime;
                              if (newDuration > maxDuration) {
                                newDuration = maxDuration;
                              }
                            }
                          }

                          final updatedClip = midiClip.copyWith(
                            duration: newDuration,
                          );
                          widget.midiClipCallbacks.onUpdated?.call(updatedClip);
                        },
                        onHorizontalDragEnd: (details) async {
                          final before = resizeStartClipSnapshot;
                          if (before != null &&
                              resizingMidiClipId == midiClip.clipId) {
                            final after = widget.midiClips.firstWhere(
                              (c) => c.clipId == midiClip.clipId,
                              orElse: () => before,
                            );
                            await _commitMidiClipSnapshot(
                              before,
                              after,
                              'Resize MIDI Clip: ${before.name}',
                            );
                          }
                          setState(() {
                            resizingMidiClipId = null;
                            resizeStartClipSnapshot = null;
                          });
                        },
                        child: Tooltip(
                          message: midiClip.canRepeat
                              ? 'Drag to resize clip'
                              : 'Enable clip loop to stretch beyond content',
                          child: MouseRegion(
                            // Show forbidden cursor if canRepeat is false and at max length
                            cursor:
                                !midiClip.canRepeat &&
                                    midiClip.duration >= midiClip.loopLength
                                ? SystemMouseCursors.forbidden
                                : SystemMouseCursors.resizeRight,
                            child: Container(
                              width: UIConstants.clipResizeHandleWidth,
                              height: totalHeight,
                              color: Colors.transparent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Split preview line (shown when Alt is pressed and hovering, hidden during recording)
                  if (hasSplitPreview && !isLiveRecording)
                    Positioned(
                      left: splitPreviewX,
                      top: 0,
                      child: Container(
                        width: 2,
                        height: totalHeight,
                        color: context.colors.textPrimary.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Calculate X positions of loop boundaries within a clip
  List<double> _calculateLoopBoundaryPositions(
    double loopLength,
    double clipDuration,
    double clipWidth,
  ) {
    final positions = <double>[];
    final clipPixelsPerBeat = clipWidth / clipDuration;
    var loopBeat = loopLength;
    while (loopBeat < clipDuration) {
      positions.add(loopBeat * clipPixelsPerBeat);
      loopBeat += loopLength;
    }
    return positions;
  }

  /// Check if a beat position is on an existing clip
  bool _isPositionOnClip(
    double beatPosition,
    int trackId,
    List<ClipData> audioClips,
    List<MidiClipData> midiClips,
  ) {
    // Check audio clips (convert seconds to beats for comparison)
    final beatsPerSecond = widget.tempo / 60.0;
    for (final clip in audioClips) {
      final clipStartBeats = clip.startTime * beatsPerSecond;
      final clipEndBeats = (clip.startTime + clip.duration) * beatsPerSecond;
      if (beatPosition >= clipStartBeats && beatPosition <= clipEndBeats) {
        return true;
      }
    }

    // Check MIDI clips (already in beats)
    for (final clip in midiClips) {
      if (beatPosition >= clip.startTime && beatPosition <= clip.endTime) {
        return true;
      }
    }

    return false;
  }

  // ============================================
  // UNIFIED NAV BAR HANDLERS
  // ============================================

  /// Sync nav bar scroll with main scroll controller.
  void _syncNavBarScroll() {
    if (navBarScrollController.hasClients && scrollController.hasClients) {
      if ((navBarScrollController.offset - scrollController.offset).abs() >
          0.1) {
        navBarScrollController.jumpTo(scrollController.offset);
      }
    }
  }
}
