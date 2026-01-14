import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../models/midi_note_data.dart';
import '../models/midi_cc_data.dart';
import '../models/scale_data.dart';
import '../models/tool_mode.dart';
import '../audio_engine.dart';
import '../services/tool_mode_resolver.dart';
import '../theme/theme_extension.dart';
import 'painters/painters.dart';
import 'piano_roll/piano_roll_controls_bar.dart';
import 'piano_roll/piano_roll_cc_lane.dart';
import 'piano_roll/chord_palette.dart';
import 'piano_roll/piano_roll_state.dart';
import 'piano_roll/operations/note_operations.dart';
import 'piano_roll/operations/clipboard_operations.dart';
import 'piano_roll/operations/selection_operations.dart';
import 'piano_roll/gestures/note_gesture_handler.dart';
import 'piano_roll/utilities/piano_roll_coordinates.dart';
import 'piano_roll/audition_mixin.dart';
import 'piano_roll/velocity_lane_mixin.dart';
import 'piano_roll/zoom_mixin.dart';
import 'shared/mini_knob.dart';
import 'context_menus/note_context_menu.dart';

/// Interaction modes for piano roll (internal tracking during gestures)
enum InteractionMode { draw, select, move, resize }

/// Piano Roll MIDI editor widget
class PianoRoll extends StatefulWidget {
  final AudioEngine? audioEngine;
  final MidiClipData? clipData;
  final VoidCallback? onClose;
  final Function(MidiClipData)? onClipUpdated;

  /// Ghost notes from other MIDI tracks (displayed at 30% opacity)
  final List<MidiNoteData> ghostNotes;

  /// Current tool mode (managed by parent EditorPanel)
  final ToolMode toolMode;

  /// Callback when tool mode changes (e.g., via keyboard shortcut)
  final Function(ToolMode)? onToolModeChanged;

  /// MIDI note to highlight (from Virtual Piano input)
  final int? highlightedNote;

  /// Whether virtual piano is visible
  final bool virtualPianoVisible;

  /// Callback to toggle virtual piano visibility
  final VoidCallback? onVirtualPianoToggle;

  const PianoRoll({
    super.key,
    this.audioEngine,
    this.clipData,
    this.onClose,
    this.onClipUpdated,
    this.ghostNotes = const [],
    this.toolMode = ToolMode.draw,
    this.onToolModeChanged,
    this.highlightedNote,
    this.virtualPianoVisible = false,
    this.onVirtualPianoToggle,
  });

  @override
  State<PianoRoll> createState() => _PianoRollState();
}

class _PianoRollState extends State<PianoRoll>
    with PianoRollStateMixin,
         NoteOperationsMixin,
         ClipboardOperationsMixin,
         SelectionOperationsMixin,
         NoteGestureHandlerMixin,
         AuditionMixin,
         VelocityLaneMixin,
         ZoomMixin {
  // ============================================
  // ALL STATE VARIABLES NOW COME FROM PianoRollStateMixin
  // Operations come from NoteOperationsMixin, ClipboardOperationsMixin, SelectionOperationsMixin
  // Gesture handling comes from NoteGestureHandlerMixin
  // ============================================

  // Local-only state (loop marker drag uses private enum)
  LoopMarkerDrag? _loopMarkerDrag;

  @override
  void initState() {
    super.initState();
    currentClip = widget.clipData;
    // Initialize loopStartBeats from clip's contentStartOffset
    if (currentClip != null) {
      loopStartBeats = currentClip!.contentStartOffset;
    }

    // Listen for undo/redo changes to update our state
    undoRedoManager.addListener(_onUndoRedoChanged);

    // Listen for hardware keyboard events (for modifier key cursor updates)
    HardwareKeyboard.instance.addHandler(_onHardwareKey);

    // Sync horizontal scroll between ruler, loop bar, and grid
    horizontalScroll.addListener(_syncRulerFromGrid);
    rulerScroll.addListener(_syncGridFromRuler);
    loopBarScroll.addListener(_syncGridFromLoopBar);

    // Initialize cursor based on initial tool mode
    currentCursor = ToolModeResolver.getCursor(widget.toolMode);

    // Scroll to default view (middle of piano)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToDefaultView();
    });
  }

  void _syncRulerFromGrid() {
    if (isSyncingScroll) return;
    if (!rulerScroll.hasClients || !horizontalScroll.hasClients) return;
    isSyncingScroll = true;
    rulerScroll.jumpTo(horizontalScroll.offset.clamp(0.0, rulerScroll.position.maxScrollExtent));
    if (loopBarScroll.hasClients) {
      loopBarScroll.jumpTo(horizontalScroll.offset.clamp(0.0, loopBarScroll.position.maxScrollExtent));
    }
    isSyncingScroll = false;
  }

  void _syncGridFromRuler() {
    if (isSyncingScroll) return;
    if (!rulerScroll.hasClients || !horizontalScroll.hasClients) return;
    isSyncingScroll = true;
    horizontalScroll.jumpTo(rulerScroll.offset.clamp(0.0, horizontalScroll.position.maxScrollExtent));
    if (loopBarScroll.hasClients) {
      loopBarScroll.jumpTo(rulerScroll.offset.clamp(0.0, loopBarScroll.position.maxScrollExtent));
    }
    isSyncingScroll = false;
  }

  void _syncGridFromLoopBar() {
    if (isSyncingScroll) return;
    if (!loopBarScroll.hasClients || !horizontalScroll.hasClients) return;
    isSyncingScroll = true;
    horizontalScroll.jumpTo(loopBarScroll.offset.clamp(0.0, horizontalScroll.position.maxScrollExtent));
    if (rulerScroll.hasClients) {
      rulerScroll.jumpTo(loopBarScroll.offset.clamp(0.0, rulerScroll.position.maxScrollExtent));
    }
    isSyncingScroll = false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    undoRedoManager.removeListener(_onUndoRedoChanged);
    horizontalScroll.removeListener(_syncRulerFromGrid);
    rulerScroll.removeListener(_syncGridFromRuler);
    loopBarScroll.removeListener(_syncGridFromLoopBar);
    focusNode.dispose();
    horizontalScroll.dispose();
    rulerScroll.dispose();
    loopBarScroll.dispose();
    verticalScroll.dispose();
    super.dispose();
  }

  /// Handle hardware keyboard events for modifier key cursor updates
  bool _onHardwareKey(KeyEvent event) {
    // Update cursor when Shift, Alt, or Cmd/Ctrl is pressed or released
    if (ToolModeResolver.isModifierKey(event.logicalKey)) {
      _updateCursorForModifiers();
    }
    return false; // Don't consume the event, let other handlers process it
  }

  @override
  void didUpdateWidget(PianoRoll oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update local clip state when parent passes new clip data
    if (widget.clipData != oldWidget.clipData) {
      setState(() {
        currentClip = widget.clipData;
        // Sync loopStartBeats from clip's contentStartOffset
        if (currentClip != null) {
          loopStartBeats = currentClip!.contentStartOffset;
        }
      });
    }
    // Update cursor when tool mode changes (from toolbar button click)
    if (widget.toolMode != oldWidget.toolMode && tempModeOverride == null) {
      setState(() {
        currentCursor = ToolModeResolver.getCursor(widget.toolMode);
      });
    }
  }

  /// Called when global undo/redo state changes
  void _onUndoRedoChanged() {
    // Force rebuild to reflect any state changes
    if (mounted) {
      setState(() {});
    }
  }

  void _scrollToDefaultView() {
    // Safety check: only scroll if controller is attached
    if (!verticalScroll.hasClients) return;

    // Scroll to show C2-C6 range by default
    final scrollOffset = _calculateNoteY(PianoRollStateMixin.defaultViewEndNote);
    verticalScroll.jumpTo(scrollOffset);
  }

  // Audition methods now provided by AuditionMixin:
  // - startAudition(), stopAudition(), changeAuditionPitch()
  // - toggleAudition(), previewChord()

  /// Stamp a chord at the given position
  /// The chord is placed relative to the clicked note position
  void _stampChordAt(double beat, int baseNote) {
    if (currentClip == null) return;

    // Get the chord's MIDI notes based on current configuration
    // Transpose the chord so its lowest note is at the clicked position
    final chordNotes = chordConfig.midiNotes;
    if (chordNotes.isEmpty) return;

    // Calculate the offset to place the chord's lowest note at baseNote
    final lowestChordNote = chordNotes.reduce((a, b) => a < b ? a : b);
    final offset = baseNote - lowestChordNote;

    // Create notes for the chord
    final newNotes = <MidiNoteData>[];
    for (final midiNote in chordNotes) {
      final transposedNote = midiNote + offset;
      // Clamp to valid MIDI range
      if (transposedNote >= 0 && transposedNote <= 127) {
        newNotes.add(MidiNoteData(
          note: transposedNote,
          velocity: 100,
          startTime: beat,
          duration: lastNoteDuration,
          isSelected: true,
        ));
      }
    }

    if (newNotes.isEmpty) return;

    setState(() {
      // Deselect all existing notes
      currentClip = currentClip?.copyWith(
        notes: currentClip!.notes.map((n) => n.copyWith(isSelected: false)).toList(),
      );
      // Add all chord notes
      for (final note in newNotes) {
        currentClip = currentClip?.addNote(note);
        autoExtendLoopIfNeeded(note);
      }
    });

    commitToHistory('Add chord');
    notifyClipUpdated();

    // Preview the chord
    previewChord(newNotes.map((n) => n.note).toList());
  }

  // Velocity lane toggle now provided by VelocityLaneMixin: toggleVelocityLane()

  double _calculateNoteY(int midiNote) {
    // Higher notes = lower Y coordinate (inverted)
    return (PianoRollStateMixin.maxMidiNote - midiNote) * pixelsPerNote;
  }

  double _calculateBeatX(double beat) {
    return beat * pixelsPerBeat;
  }

  int _getNoteAtY(double y) {
    final rawNote = PianoRollStateMixin.maxMidiNote - (y / pixelsPerNote).floor();
    // Apply scale lock if enabled
    if (scaleLockEnabled) {
      return snapNoteToScale(rawNote);
    }
    return rawNote;
  }

  double _getBeatAtX(double x) {
    return x / pixelsPerBeat;
  }

  // Zoom methods now provided by ZoomMixin:
  // - calculateMaxPixelsPerBeat(), calculateMinPixelsPerBeat()
  // - zoomIn(), zoomOut(), toggleSnap()

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: currentCursor,
      // onHover is handled by the inner MouseRegion in the grid area
      child: Focus(
        focusNode: focusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          // Don't intercept keys when a TextField has focus (e.g., loop time inputs)
          final primaryFocus = FocusManager.instance.primaryFocus;
          if (primaryFocus != null && primaryFocus != focusNode) {
            final focusContext = primaryFocus.context;
            if (focusContext != null) {
              final widget = focusContext.widget;
              if (widget is EditableText) {
                return KeyEventResult.ignored;
              }
            }
          }
          _handleKeyEvent(event);
          return KeyEventResult.handled;
        },
        child: Stack(
          children: [
            ColoredBox(
              color: context.colors.standard, // Dark background
              child: Column(
                children: [
                  _buildPianoRollContent(),
                ],
              ),
            ),
            // Chord palette overlay
            if (chordPaletteVisible)
              Positioned(
                right: 16,
                top: 100,
                child: ChordPalette(
                  configuration: chordConfig,
                  previewEnabled: chordPreviewEnabled,
                  onConfigurationChanged: (config) {
                    setState(() => chordConfig = config);
                  },
                  onPreview: previewChord,
                  onPreviewToggle: (enabled) {
                    setState(() => chordPreviewEnabled = enabled);
                  },
                  onClose: () {
                    setState(() => chordPaletteVisible = false);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPianoRollContent() {
    // Loop length is the active region (before the shaded area)
    final activeBeats = getLoopLength();
    // Total beats extends to fill viewport width or furthest note
    final totalBeats = calculateTotalBeats(
      viewportWidth: viewWidth,
      pixelsPerBeat: pixelsPerBeat,
    );

    final canvasWidth = totalBeats * pixelsPerBeat;
    // Use visibleRowCount for canvas height (fold-aware)
    final canvasHeight = visibleRowCount * pixelsPerNote;

    return Expanded(
      child: Column(
        children: [
          // Horizontal controls bar (replaces left sidebar)
          PianoRollControlsBar(
            // Clip section - loopEnabled controls clip's canRepeat property
            loopEnabled: currentClip?.canRepeat ?? true,
            loopStartBeats: loopStartBeats,
            loopLengthBeats: getLoopLength(),
            beatsPerBar: beatsPerBar,
            beatUnit: beatUnit,
            onLoopToggle: () {
              if (currentClip == null) return;
              setState(() {
                currentClip = currentClip!.copyWith(canRepeat: !currentClip!.canRepeat);
              });
              notifyClipUpdated();
            },
            onLoopStartChanged: (beats) {
              // When typing Start value: Keep LENGTH fixed, only change contentStartOffset
              // (Length is controlled separately by the Length field)
              final newStart = beats.clamp(0.0, double.infinity);
              debugPrint('[onLoopStartChanged] newStart=$newStart, before: duration=${currentClip?.duration}, loopLength=${currentClip?.loopLength}');
              setState(() {
                loopStartBeats = newStart;
                // Only update contentStartOffset - loopLength and duration stay the same
                if (currentClip != null) {
                  currentClip = currentClip!.copyWith(contentStartOffset: newStart);
                }
              });
              debugPrint('[onLoopStartChanged] after: duration=${currentClip?.duration}, loopLength=${currentClip?.loopLength}');
              notifyClipUpdated();
            },
            onLoopLengthChanged: (beats) {
              if (currentClip == null) return;
              // Allow very small loops (1/16th note = 0.25 beats)
              final newLength = beats.clamp(0.25, 256.0);
              setState(() {
                // Update both loopLength AND duration for one-way sync
                // Piano Roll loop length changes sync to Arrangement clip duration
                currentClip = currentClip!.copyWith(
                  loopLength: newLength,
                  duration: newLength,
                );
              });
              notifyClipUpdated();
            },
            onBeatsPerBarChanged: (value) => setState(() => beatsPerBar = value),
            onBeatUnitChanged: (value) => setState(() => beatUnit = value),
            // Grid section
            snapEnabled: snapEnabled,
            gridDivision: gridDivision,
            adaptiveGridEnabled: adaptiveGridEnabled,
            snapTripletEnabled: snapTripletEnabled,
            effectiveGridDivision: getEffectiveGridDivision(),
            onSnapToggle: toggleSnap,
            onGridDivisionChanged: (division) {
              setState(() {
                if (division == null) {
                  // Adaptive mode
                  adaptiveGridEnabled = true;
                } else {
                  // Fixed division
                  adaptiveGridEnabled = false;
                  gridDivision = division;
                }
              });
            },
            onSnapTripletToggle: () => setState(() => snapTripletEnabled = !snapTripletEnabled),
            onQuantize: quantizeSelectedNotes,
            quantizeDivision: quantizeDivision,
            quantizeTripletEnabled: quantizeTripletEnabled,
            onQuantizeDivisionChanged: (div) => setState(() => quantizeDivision = div),
            onQuantizeTripletToggle: () => setState(() => quantizeTripletEnabled = !quantizeTripletEnabled),
            // View section
            foldEnabled: foldViewEnabled,
            ghostNotesEnabled: ghostNotesEnabled,
            onFoldToggle: () => setState(() => foldViewEnabled = !foldViewEnabled),
            onGhostNotesToggle: () => setState(() => ghostNotesEnabled = !ghostNotesEnabled),
            // Scale section
            scaleRoot: scaleRoot,
            scaleType: scaleType,
            highlightEnabled: scaleHighlightEnabled,
            onRootChanged: (root) => setState(() => scaleRoot = root),
            onTypeChanged: (type) => setState(() => scaleType = type),
            onHighlightToggle: () => setState(() => scaleHighlightEnabled = !scaleHighlightEnabled),
            // Transform section
            stretchAmount: stretchAmount,
            onLegato: applyLegato,
            onStretchChanged: (v) => setState(() => stretchAmount = v),
            onStretchApply: applyStretch,
            onReverse: reverseNotes,
            // Lane visibility toggles (Randomize/CC type are in lane headers)
            velocityLaneVisible: velocityLaneExpanded,
            onVelocityLaneToggle: toggleVelocityLane,
            // Virtual Piano toggle
            virtualPianoVisible: widget.virtualPianoVisible,
            onVirtualPianoToggle: widget.onVirtualPianoToggle,
          ),
          // Main content area
          Expanded(
            child: Column(
              children: [
                // Loop bar row (dedicated row for loop region control)
                Row(
                  children: [
                    // Empty corner aligned with piano keys
                    SizedBox(
                      width: 80,
                      height: 20,
                      child: Container(color: context.colors.dark),
                    ),
                    // Loop bar (scrollable) - synced with grid
                    Expanded(
                      child: SingleChildScrollView(
                        controller: loopBarScroll,
                        scrollDirection: Axis.horizontal,
                        child: _buildLoopBar(totalBeats, canvasWidth),
                      ),
                    ),
                    // Empty corner aligned with zoom controls
                    SizedBox(
                      width: 48,
                      height: 20,
                      child: Container(color: context.colors.dark),
                    ),
                  ],
                ),
                // Bar ruler row with audition button on left and zoom on right
                Row(
                  children: [
                    // Audition button (aligned with piano keys width)
                    _buildAuditionCorner(context),
                    // Bar ruler (scrollable) - uses rulerScroll synced with horizontalScroll
                    Expanded(
                      child: SingleChildScrollView(
                        controller: rulerScroll,
                        scrollDirection: Axis.horizontal,
                        child: _buildBarRuler(totalBeats, canvasWidth),
                      ),
                    ),
                    // Zoom controls at end of timeline
                    _buildZoomControls(context),
                  ],
                ),
                // Content row - ONE vertical scroll for both piano keys and grid
                Expanded(
                  child: Scrollbar(
                    controller: verticalScroll,
                    child: SingleChildScrollView(
                      controller: verticalScroll,
                      scrollDirection: Axis.vertical,
                      child: SizedBox(
                        height: canvasHeight,
                        child: Row(
                          children: [
                            // Piano keys (no separate scroll - inside shared vertical scroll)
                            // Uses foldedPitches when fold mode is enabled
                            Container(
                              width: 80,
                              decoration: BoxDecoration(
                                color: context.colors.elevated,
                                border: Border(
                                  right: BorderSide(color: context.colors.elevated, width: 1),
                                ),
                              ),
                              child: Column(
                                children: foldedPitches.map((midiNote) {
                                  return _buildPianoKey(midiNote);
                                }).toList(),
                              ),
                            ),
                            // Grid with horizontal scroll (no scrollbar, no separate vertical scroll)
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  // Capture view width for dynamic zoom limits
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (viewWidth != constraints.maxWidth && constraints.maxWidth > 0) {
                                      setState(() {
                                        viewWidth = constraints.maxWidth;
                                      });
                                    }
                                  });
                                  return SingleChildScrollView(
                                    controller: horizontalScroll,
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      width: canvasWidth,
                                      height: canvasHeight,
                                      // Listener captures right-click for context menu and Ctrl/Cmd for eraser/delete
                                      child: Listener(
                                      onPointerDown: (event) {
                                        if (event.buttons == kSecondaryMouseButton) {
                                          rightClickStartPosition = event.localPosition;
                                          rightClickNote = _findNoteAtPosition(event.localPosition);
                                        } else if (event.buttons == kMiddleMouseButton) {
                                          // Middle mouse button: start drag zoom (Ableton-style)
                                          startDragZoom(event.localPosition.dx, event.position.dy);
                                        } else if (event.buttons == kPrimaryMouseButton) {
                                          if (ModifierKeyState.current().isAltPressed) {
                                            final note = _findNoteAtPosition(event.localPosition);
                                            if (note != null) {
                                              deleteNote(note);
                                            }
                                          }
                                        }
                                      },
                                      onPointerMove: (event) {
                                        // Handle drag zoom with middle mouse button
                                        if (isDragZooming) {
                                          updateDragZoom(event.position.dy);
                                          return;
                                        }
                                        if (event.buttons == kPrimaryMouseButton) {
                                          if (ModifierKeyState.current().isAltPressed) {
                                            if (!isErasing) {
                                              _startErasing(event.localPosition);
                                            } else {
                                              _eraseNotesAt(event.localPosition);
                                            }
                                          }
                                        }
                                      },
                                      onPointerUp: (event) {
                                        // End drag zoom if active
                                        if (isDragZooming) {
                                          endDragZoom();
                                          return;
                                        }
                                        if (rightClickNote != null && rightClickStartPosition != null) {
                                          final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
                                          if (renderBox != null) {
                                            final globalPosition = renderBox.localToGlobal(rightClickStartPosition!);
                                            _showNoteContextMenu(globalPosition, rightClickNote!);
                                          }
                                        }
                                        rightClickStartPosition = null;
                                        rightClickNote = null;
                                        if (isErasing) {
                                          _stopErasing();
                                        }
                                        stopAudition();
                                      },
                                      child: MouseRegion(
                                        cursor: currentCursor,
                                        onHover: _onHover,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.translucent,
                                          onTapDown: _onTapDown,
                                          onTapUp: _onTapUp,
                                          onTapCancel: () {
                                            stopAudition();
                                            pendingNoteTapSelection = null;
                                          },
                                          onPanStart: _onPanStart,
                                          onPanUpdate: _onPanUpdate,
                                          onPanEnd: _onPanEnd,
                                          child: ColoredBox(
                                            color: Colors.transparent,
                                            child: Stack(
                                              children: [
                                                CustomPaint(
                                                  size: Size(canvasWidth, canvasHeight),
                                                  painter: GridPainter(
                                                    pixelsPerBeat: pixelsPerBeat,
                                                    pixelsPerNote: pixelsPerNote,
                                                    gridDivision: getEffectiveGridDivision(),
                                                    maxMidiNote: PianoRollStateMixin.maxMidiNote,
                                                    minMidiNote: PianoRollStateMixin.minMidiNote,
                                                    totalBeats: totalBeats,
                                                    activeBeats: activeBeats,
                                                    loopEnabled: loopEnabled,
                                                    loopStart: loopStartBeats,
                                                    loopEnd: loopStartBeats + getLoopLength(),
                                                    beatsPerBar: beatsPerBar,
                                                    tripletEnabled: snapTripletEnabled,
                                                    blackKeyBackground: context.colors.standard,
                                                    whiteKeyBackground: context.colors.elevated,
                                                    separatorLine: context.colors.elevated,
                                                    subdivisionGridLine: context.colors.surface,
                                                    beatGridLine: context.colors.hover,
                                                    barGridLine: context.colors.textMuted,
                                                    scaleHighlightEnabled: scaleHighlightEnabled,
                                                    scaleRootMidi: ScaleRoot.midiNoteFromName(scaleRoot),
                                                    scaleIntervals: scaleType.intervals,
                                                    foldedPitches: foldViewEnabled ? foldedPitches : null,
                                                  ),
                                                ),
                                                CustomPaint(
                                                  size: Size(canvasWidth, canvasHeight),
                                                  painter: NotePainter(
                                                    notes: currentClip?.notes ?? [],
                                                    previewNote: previewNote,
                                                    pixelsPerBeat: pixelsPerBeat,
                                                    pixelsPerNote: pixelsPerNote,
                                                    maxMidiNote: PianoRollStateMixin.maxMidiNote,
                                                    selectionStart: selectionStart,
                                                    selectionEnd: selectionEnd,
                                                    ghostNotes: widget.ghostNotes,
                                                    showGhostNotes: ghostNotesEnabled,
                                                    foldedPitches: foldViewEnabled ? foldedPitches : null,
                                                  ),
                                                ),
                                                _buildInsertMarker(canvasHeight),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Velocity editing lane (Ableton-style)
                if (velocityLaneExpanded)
                  _buildVelocityLane(totalBeats, canvasWidth),
                // CC automation lane
                if (ccLaneExpanded)
                  _buildCCLane(totalBeats, canvasWidth),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build the CC automation lane
  Widget _buildCCLane(double totalBeats, double canvasWidth) {
    return PianoRollCCLane(
      lane: ccLane,
      pixelsPerBeat: pixelsPerBeat,
      totalBeats: totalBeats,
      laneHeight: PianoRollStateMixin.ccLaneHeight,
      horizontalScrollController: horizontalScroll,
      onCCTypeChanged: (type) {
        setState(() {
          ccLane = ccLane.copyWith(ccType: type, points: []);
        });
      },
      onPointAdded: (point) {
        saveToHistory();
        setState(() {
          ccLane = ccLane.addPoint(point);
        });
        commitToHistory('Add CC point');
      },
      onPointUpdated: (pointId, newPoint) {
        setState(() {
          ccLane = ccLane.updatePoint(pointId, newPoint);
        });
      },
      onPointDeleted: (pointId) {
        saveToHistory();
        setState(() {
          ccLane = ccLane.removePoint(pointId);
        });
        commitToHistory('Delete CC point');
      },
      onDrawValue: (time, value) {
        // Add a point at this position (for drawing mode)
        final newPoint = MidiCCPoint(time: time, value: value);
        setState(() {
          ccLane = ccLane.addPoint(newPoint);
        });
      },
      onClose: () {
        setState(() {
          ccLaneExpanded = false;
        });
      },
    );
  }

  /// Build the velocity editing lane
  Widget _buildVelocityLane(double totalBeats, double canvasWidth) {
    return Container(
      height: PianoRollStateMixin.velocityLaneHeight,
      decoration: BoxDecoration(
        color: context.colors.darkest,
        border: Border(
          top: BorderSide(color: context.colors.surface, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Label area with randomize control (same width as piano keys)
          Container(
            width: 80,
            height: PianoRollStateMixin.velocityLaneHeight,
            decoration: BoxDecoration(
              color: context.colors.standard,
              border: Border(
                right: BorderSide(color: context.colors.surface, width: 1),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Velocity',
                  style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                // Randomize button with dropdown - opens knob popup
                _buildVelocityRandomizeButton(context),
              ],
            ),
          ),
          // Velocity bars area (scrolls with note grid)
          Expanded(
            child: SingleChildScrollView(
              controller: horizontalScroll,
              scrollDirection: Axis.horizontal,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: onVelocityPanStart,
                onPanUpdate: onVelocityPanUpdate,
                onPanEnd: onVelocityPanEnd,
                child: CustomPaint(
                  size: Size(canvasWidth, PianoRollStateMixin.velocityLaneHeight),
                  painter: VelocityLanePainter(
                    notes: currentClip?.notes ?? [],
                    pixelsPerBeat: pixelsPerBeat,
                    laneHeight: PianoRollStateMixin.velocityLaneHeight,
                    totalBeats: totalBeats,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Velocity pan handlers now provided by VelocityLaneMixin:
  // - onVelocityPanStart(), onVelocityPanUpdate(), onVelocityPanEnd()
  // Note finding: findNoteAtVelocityPosition() is in NoteGestureHandlerMixin

  /// Build insert marker (blue dashed line) - spec v2.0
  Widget _buildInsertMarker(double canvasHeight) {
    if (insertMarkerBeats == null) return const SizedBox.shrink();

    final markerX = insertMarkerBeats! * pixelsPerBeat;

    return Positioned(
      left: markerX - 1, // Center the 2px line
      top: 0,
      child: IgnorePointer(
        child: SizedBox(
          width: 2,
          height: canvasHeight,
          child: CustomPaint(
            painter: DashedLinePainter(
              color: context.colors.accent, // Accent color
              strokeWidth: 2,
              dashLength: 6,
              gapLength: 4,
            ),
          ),
        ),
      ),
    );
  }

  /// Build the Randomize button with dropdown for velocity lane header
  Widget _buildVelocityRandomizeButton(BuildContext context) {
    final colors = context.colors;
    final displayValue = '${(velocityRandomizeAmount * 100).round()}%';

    return GestureDetector(
      onTap: () => _showVelocityRandomizePopup(context),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Rand $displayValue',
                style: TextStyle(color: colors.textPrimary, fontSize: 9),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 12, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  /// Show popup with knob for randomize amount
  void _showVelocityRandomizePopup(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);

    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Tap outside to close
          Positioned.fill(
            child: GestureDetector(
              onTap: () => overlayEntry.remove(),
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent),
            ),
          ),
          // Popup
          Positioned(
            left: buttonPosition.dx,
            top: buttonPosition.dy + button.size.height + 4,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: this.context.colors.elevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: this.context.colors.surface),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Randomize',
                      style: TextStyle(
                        color: this.context.colors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 8),
                    StatefulBuilder(
                      builder: (context, setPopupState) => MiniKnob(
                        value: velocityRandomizeAmount,
                        min: 0.0,
                        max: 1.0,
                        size: 48,
                        valueFormatter: (v) => '${(v * 100).round()}%',
                        arcColor: this.context.colors.accent,
                        onChanged: (v) {
                          setState(() => velocityRandomizeAmount = v);
                          setPopupState(() {});
                        },
                        onChangeEnd: () {
                          applyVelocityRandomize();
                          overlayEntry.remove();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(overlayEntry);
  }

  Widget _buildPianoKey(int midiNote) {
    final isBlackKey = _isBlackKey(midiNote);
    final noteName = _getNoteNameForKey(midiNote);
    final isC = midiNote % 12 == 0;
    final isHighlighted = widget.highlightedNote == midiNote;

    return Container(
      height: pixelsPerNote,
      decoration: BoxDecoration(
        // Highlighted when virtual piano plays this note
        color: isHighlighted
            ? context.colors.accent
            : (isBlackKey ? context.colors.standard : context.colors.elevated),
        border: Border(
          bottom: BorderSide(
            color: context.colors.surface, // Subtle border
            width: 0.5,
          ),
          // Add left border highlight for visual emphasis
          left: isHighlighted
              ? BorderSide(color: context.colors.accent, width: 3)
              : BorderSide.none,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            noteName,
            style: TextStyle(
              color: isHighlighted
                  ? context.colors.textPrimary
                  : (isBlackKey ? context.colors.textMuted : context.colors.textPrimary),
              fontSize: isC ? 9 : 8, // C notes slightly larger
              fontWeight: isC || isHighlighted ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  // Use shared utility from NoteNameUtils
  bool _isBlackKey(int midiNote) => NoteNameUtils.isBlackKey(midiNote);

  String _getNoteNameForKey(int midiNote) => NoteNameUtils.getNoteName(midiNote);

  /// Build zoom controls (at end of timeline row)
  Widget _buildZoomControls(BuildContext context) {
    final colors = context.colors;

    return Container(
      height: 24, // Match bar ruler height
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: colors.standard,
        border: Border(
          left: BorderSide(color: colors.surface, width: 1),
          bottom: BorderSide(color: colors.surface, width: 1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Zoom out button
          _buildZoomButton(
            context,
            icon: Icons.remove,
            onTap: zoomOut,
            tooltip: 'Zoom out',
          ),
          const SizedBox(width: 4),
          // Zoom in button
          _buildZoomButton(
            context,
            icon: Icons.add,
            onTap: zoomIn,
            tooltip: 'Zoom in',
          ),
        ],
      ),
    );
  }

  Widget _buildZoomButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    final colors = context.colors;

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: colors.dark,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Icon(
              icon,
              size: 14,
              color: colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  /// Build audition button corner (top-left, above piano keys)
  Widget _buildAuditionCorner(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 80, // Match piano keys width
      height: 30, // Match bar ruler height
      decoration: BoxDecoration(
        color: colors.standard,
        border: Border(
          right: BorderSide(color: colors.surface, width: 1),
          bottom: BorderSide(color: colors.surface, width: 1),
        ),
      ),
      child: Tooltip(
        message: auditionEnabled ? 'Disable audition' : 'Enable audition',
        child: GestureDetector(
          onTap: toggleAudition,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Center(
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: auditionEnabled ? colors.accent : colors.dark,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Icon(
                  auditionEnabled ? Icons.volume_up : Icons.volume_off,
                  size: 14,
                  color: auditionEnabled ? colors.elevated : colors.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Build dedicated loop bar row for loop region control.
  /// Drag loop markers to resize, drag middle to move, drag empty area to create new loop.
  Widget _buildLoopBar(double totalBeats, double canvasWidth) {
    return GestureDetector(
      onPanStart: (details) {
        final scrollOffset = loopBarScroll.hasClients ? loopBarScroll.offset : 0.0;
        final xInContent = details.localPosition.dx + scrollOffset;
        final beatAtCursor = xInContent / pixelsPerBeat;

        // Check if clicking on loop markers (when loop is enabled)
        if (loopEnabled) {
          final loopEnd = loopStartBeats + getLoopLength();
          final hitRadius = 10.0 / pixelsPerBeat; // 10px hit radius in beats

          // Check start marker
          if ((beatAtCursor - loopStartBeats).abs() < hitRadius) {
            _loopMarkerDrag = LoopMarkerDrag.start;
            loopDragStartBeat = loopStartBeats;
            isCreatingLoop = false;
            return;
          }

          // Check end marker
          if ((beatAtCursor - loopEnd).abs() < hitRadius) {
            _loopMarkerDrag = LoopMarkerDrag.end;
            loopDragStartBeat = loopEnd;
            isCreatingLoop = false;
            return;
          }

          // Check middle region - drag to move
          if (beatAtCursor > loopStartBeats && beatAtCursor < loopEnd) {
            _loopMarkerDrag = LoopMarkerDrag.middle;
            loopDragStartBeat = beatAtCursor;
            isCreatingLoop = false;
            return;
          }
        }

        // Clicking outside loop or loop disabled → create new loop
        setState(() {
          loopStartBeats = snapToGrid(beatAtCursor);
          loopEnabled = true;
          isCreatingLoop = true;
        });
        _loopMarkerDrag = LoopMarkerDrag.end;
        loopDragStartBeat = loopStartBeats;
      },
      onPanUpdate: (details) {
        final scrollOffset = loopBarScroll.hasClients ? loopBarScroll.offset : 0.0;
        final xInContent = details.localPosition.dx + scrollOffset;
        final beatAtCursor = xInContent / pixelsPerBeat;
        final snappedBeat = snapToGrid(beatAtCursor);

        if (_loopMarkerDrag == null) return;

        switch (_loopMarkerDrag!) {
          case LoopMarkerDrag.start:
            // Move start marker - only changes contentStartOffset (where playback begins)
            // Arrangement clip length (duration) stays the same - controlled by Length field
            final newStart = snappedBeat.clamp(0.0, double.infinity);
            debugPrint('[LoopMarkerDrag.start] newStart=$newStart, before: duration=${currentClip?.duration}, loopLength=${currentClip?.loopLength}, contentStartOffset=${currentClip?.contentStartOffset}');
            setState(() {
              loopStartBeats = newStart;
              // Only update contentStartOffset - duration stays the same
              if (currentClip != null) {
                currentClip = currentClip!.copyWith(contentStartOffset: newStart);
              }
            });
            debugPrint('[LoopMarkerDrag.start] after: duration=${currentClip?.duration}, loopLength=${currentClip?.loopLength}, contentStartOffset=${currentClip?.contentStartOffset}');
            // Live sync to arrangement during drag
            notifyClipUpdated();
            break;

          case LoopMarkerDrag.end:
            // Move end marker, keep start fixed
            // The end position is the absolute beat, but the length is always
            // relative to loopStartBeats (which represents contentStartOffset visually)
            final newEnd = snappedBeat.clamp(loopStartBeats + gridDivision, double.infinity);
            final newLength = newEnd - loopStartBeats;
            debugPrint('[LoopMarkerDrag.end] newEnd=$newEnd, loopStartBeats=$loopStartBeats, newLength=$newLength, before: duration=${currentClip?.duration}, loopLength=${currentClip?.loopLength}');
            setState(() {
              updateLoopLength(newLength);
            });
            debugPrint('[LoopMarkerDrag.end] after: duration=${currentClip?.duration}, loopLength=${currentClip?.loopLength}');
            // Note: Don't call autoExtendCanvasIfNeeded here - updateLoopLength already
            // sets the correct duration. autoExtendCanvasIfNeeded would overwrite it
            // with a bar-aligned value, causing the duration bug.
            // Live sync to arrangement during drag
            notifyClipUpdated();
            break;

          case LoopMarkerDrag.middle:
            // Move entire loop region (only changes contentStartOffset, not duration)
            final delta = snappedBeat - snapToGrid(loopDragStartBeat);
            final newStart = (loopStartBeats + delta).clamp(0.0, double.infinity);
            if (newStart >= 0) {
              debugPrint('[LoopMarkerDrag.middle] newStart=$newStart, before: duration=${currentClip?.duration}, loopLength=${currentClip?.loopLength}, contentStartOffset=${currentClip?.contentStartOffset}');
              setState(() {
                loopStartBeats = newStart;
                // Sync to clip's contentStartOffset (determines where in content playback begins)
                // Duration stays the same - controlled by Length field only
                if (currentClip != null) {
                  currentClip = currentClip!.copyWith(contentStartOffset: newStart);
                }
              });
              loopDragStartBeat = snappedBeat;
              // Don't call autoExtendCanvasIfNeeded - it can overwrite duration
              debugPrint('[LoopMarkerDrag.middle] after: duration=${currentClip?.duration}, loopLength=${currentClip?.loopLength}, contentStartOffset=${currentClip?.contentStartOffset}');
              // Live sync to arrangement during drag
              notifyClipUpdated();
            }
            break;
        }
      },
      onPanEnd: (details) {
        _loopMarkerDrag = null;
        isCreatingLoop = false;
      },
      child: MouseRegion(
        cursor: _getLoopBarCursor(),
        onHover: (event) {
          // Track hover position for cursor updates
          final scrollOffset = loopBarScroll.hasClients ? loopBarScroll.offset : 0.0;
          final xInContent = event.localPosition.dx + scrollOffset;
          final beat = xInContent / pixelsPerBeat;
          if (loopBarHoverBeat != beat) {
            setState(() {
              loopBarHoverBeat = beat;
            });
          }
        },
        onExit: (event) {
          setState(() {
            loopBarHoverBeat = null;
          });
        },
        child: Container(
          height: 20,
          width: canvasWidth,
          decoration: BoxDecoration(
            color: context.colors.dark,
            border: Border(
              bottom: BorderSide(color: context.colors.surface, width: 1),
            ),
          ),
          child: CustomPaint(
            size: Size(canvasWidth, 20),
            painter: LoopBarPainter(
              pixelsPerBeat: pixelsPerBeat,
              totalBeats: totalBeats,
              loopEnabled: loopEnabled,
              loopStart: loopStartBeats,
              loopEnd: loopStartBeats + getLoopLength(),
            ),
          ),
        ),
      ),
    );
  }

  /// Get cursor for loop bar based on current hover position.
  MouseCursor _getLoopBarCursor() {
    if (!loopEnabled || loopBarHoverBeat == null) {
      return SystemMouseCursors.click;
    }

    final loopEnd = loopStartBeats + getLoopLength();
    final hitRadius = 10.0 / pixelsPerBeat; // 10px in beats

    // Check if hovering over start edge
    if ((loopBarHoverBeat! - loopStartBeats).abs() < hitRadius) {
      return SystemMouseCursors.resizeLeftRight;
    }

    // Check if hovering over end edge
    if ((loopBarHoverBeat! - loopEnd).abs() < hitRadius) {
      return SystemMouseCursors.resizeLeftRight;
    }

    // Check if hovering over middle region
    if (loopBarHoverBeat! > loopStartBeats && loopBarHoverBeat! < loopEnd) {
      return SystemMouseCursors.move;
    }

    // Outside loop region
    return SystemMouseCursors.click;
  }

  /// Build bar number ruler with scroll/zoom interaction.
  /// Drag vertically: down = zoom in, up = zoom out (anchored to cursor)
  /// Drag horizontally: pan timeline
  /// Click: place insert marker
  /// Double-click: reset zoom to default
  Widget _buildBarRuler(double totalBeats, double canvasWidth) {
    return GestureDetector(
      onTapUp: (details) {
        // Click ruler to place insert marker
        final scrollOffset = rulerScroll.hasClients ? rulerScroll.offset : 0.0;
        final xInContent = details.localPosition.dx + scrollOffset;
        final beats = xInContent / pixelsPerBeat;
        setState(() {
          insertMarkerBeats = beats.clamp(0.0, double.infinity);
        });
      },
      onDoubleTap: () {
        // Double-click to reset zoom to default
        setState(() {
          pixelsPerBeat = 80.0;
        });
      },
      onPanStart: (details) {
        final scrollOffset = rulerScroll.hasClients ? rulerScroll.offset : 0.0;
        final xInContent = details.localPosition.dx + scrollOffset;
        final beatAtCursor = xInContent / pixelsPerBeat;

        // Store initial state for pan/zoom
        zoomDragStartY = details.globalPosition.dy;
        zoomStartPixelsPerBeat = pixelsPerBeat;
        zoomAnchorLocalX = details.localPosition.dx;
        zoomAnchorBeat = beatAtCursor;
      },
      onPanUpdate: (details) {
        // Calculate drag delta (positive = dragged down = zoom in)
        final deltaY = details.globalPosition.dy - zoomDragStartY;

        // Sensitivity: ~100 pixels of drag = 2x zoom change
        final zoomFactor = 1.0 + (deltaY / 100.0);
        final minZoom = calculateMinPixelsPerBeat();
        final maxZoom = calculateMaxPixelsPerBeat();
        final newPixelsPerBeat = (zoomStartPixelsPerBeat * zoomFactor).clamp(minZoom, maxZoom);

        // Calculate new scroll position to keep anchor beat under cursor
        final newXInContent = zoomAnchorBeat * newPixelsPerBeat;

        // Apply horizontal panning
        final panOffset = -details.delta.dx;
        final targetScrollOffset = (newXInContent - zoomAnchorLocalX) + panOffset;

        // Update anchor position to account for pan
        zoomAnchorLocalX += details.delta.dx;

        setState(() {
          pixelsPerBeat = newPixelsPerBeat;
        });

        // Defer scroll adjustment to after layout rebuild
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (horizontalScroll.hasClients) {
            final maxScroll = horizontalScroll.position.maxScrollExtent;
            horizontalScroll.jumpTo(targetScrollOffset.clamp(0.0, maxScroll));
          }
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Container(
          height: 30,
          width: canvasWidth,
          decoration: BoxDecoration(
            color: context.colors.elevated,
            border: Border(
              bottom: BorderSide(color: context.colors.elevated, width: 1),
            ),
          ),
          child: CustomPaint(
            size: Size(canvasWidth, 30),
            painter: BarRulerPainter(
              pixelsPerBeat: pixelsPerBeat,
              totalBeats: totalBeats,
              playheadPosition: 0.0,
            ),
          ),
        ),
      ),
    );
  }

  // Find note at position
  MidiNoteData? _findNoteAtPosition(Offset position) {
    final beat = _getBeatAtX(position.dx);
    final note = _getNoteAtY(position.dy);

    for (final midiNote in currentClip?.notes ?? <MidiNoteData>[]) {
      if (midiNote.contains(beat, note)) {
        return midiNote;
      }
    }
    return null;
  }

  // Check if position is near left or right edge of note (FL Studio style)
  // Returns 'left', 'right', or null
  String? _getEdgeAtPosition(Offset position, MidiNoteData note) {
    const edgeThreshold = 9.0; // 9 pixels for easier edge detection

    final noteStartX = _calculateBeatX(note.startTime);
    final noteEndX = _calculateBeatX(note.endTime);
    final noteY = _calculateNoteY(note.note);

    // Check vertical range (allow some tolerance - within note height)
    final isInVerticalRange = (position.dy >= noteY) && (position.dy <= noteY + pixelsPerNote);

    if (!isInVerticalRange) return null;

    // Check left edge first (priority if both are close)
    if ((position.dx - noteStartX).abs() < edgeThreshold) {
      return 'left';
    }

    // Check right edge
    if ((position.dx - noteEndX).abs() < edgeThreshold) {
      return 'right';
    }

    return null; // Not near any edge
  }

  /// Update cursor and temp mode override based on current modifier key state
  /// Called when Shift/Alt/Cmd/Ctrl pressed/released for hold modifier support
  void _updateCursorForModifiers() {
    // Don't update cursor during active drag operations
    if (currentMode == InteractionMode.move || currentMode == InteractionMode.resize) {
      return;
    }

    final modifiers = ModifierKeyState.current();
    final overrideMode = modifiers.getOverrideToolMode();

    setState(() {
      tempModeOverride = overrideMode;
      currentCursor = ToolModeResolver.getCursor(overrideMode ?? widget.toolMode);
    });
  }

  // Handle hover for cursor feedback (smart context-aware cursors)
  void _onHover(PointerHoverEvent event) {
    // Don't update cursor during active drag operations
    if (currentMode == InteractionMode.move || currentMode == InteractionMode.resize) {
      return;
    }

    final position = event.localPosition;
    final hoveredNote = _findNoteAtPosition(position);
    final modifiers = ModifierKeyState.current();
    final toolMode = effectiveToolMode;

    // Tool-mode-aware cursor logic
    if (hoveredNote != null) {
      // On a note
      if (modifiers.isAltPressed || toolMode == ToolMode.eraser) {
        // Eraser mode - show delete cursor
        setState(() {
          currentCursor = SystemMouseCursors.forbidden;
        });
      } else if (toolMode == ToolMode.slice) {
        // Slice mode - show vertical split cursor
        setState(() {
          currentCursor = SystemMouseCursors.verticalText;
        });
      } else if (modifiers.isCtrlOrCmd || toolMode == ToolMode.duplicate) {
        // Duplicate mode - show copy cursor
        setState(() {
          currentCursor = SystemMouseCursors.copy;
        });
      } else if (toolMode == ToolMode.select) {
        // Select mode - show pointer on notes
        final edge = _getEdgeAtPosition(position, hoveredNote);
        if (edge != null) {
          setState(() {
            currentCursor = SystemMouseCursors.resizeLeftRight;
          });
        } else {
          setState(() {
            currentCursor = SystemMouseCursors.click;
          });
        }
      } else {
        // Draw mode (default)
        final edge = _getEdgeAtPosition(position, hoveredNote);
        if (edge != null) {
          // Near edge - show resize cursor
          setState(() {
            currentCursor = SystemMouseCursors.resizeLeftRight;
          });
        } else {
          // On note body - show grab cursor
          setState(() {
            currentCursor = SystemMouseCursors.grab;
          });
        }
      }
    } else {
      // Empty space
      if (modifiers.isAltPressed || toolMode == ToolMode.eraser) {
        // Eraser mode on empty space
        setState(() {
          currentCursor = SystemMouseCursors.forbidden;
        });
      } else if (toolMode == ToolMode.select) {
        // Select mode on empty - basic cursor (will do box select on drag)
        setState(() {
          currentCursor = SystemMouseCursors.basic;
        });
      } else if (toolMode == ToolMode.slice) {
        // Slice mode on empty - show slice cursor
        setState(() {
          currentCursor = SystemMouseCursors.verticalText;
        });
      } else if (toolMode == ToolMode.duplicate) {
        // Duplicate on empty - nothing to duplicate
        setState(() {
          currentCursor = SystemMouseCursors.basic;
        });
      } else {
        // Draw mode (default) - crosshair for note creation
        setState(() {
          currentCursor = SystemMouseCursors.precise;
        });
      }
    }
  }

  void _onTapDown(TapDownDetails details) {
    // Request focus to enable keyboard events (delete, undo, etc.)
    focusNode.requestFocus();

    final clickedNote = _findNoteAtPosition(details.localPosition);
    final modifiers = ModifierKeyState.current();
    final toolMode = effectiveToolMode;

    // ============================================
    // TOOL MODE BEHAVIOR
    // ============================================

    // Alt+click OR Erase tool = delete note
    if (modifiers.isAltPressed || toolMode == ToolMode.eraser) {
      if (clickedNote != null) {
        saveToHistory();
        setState(() {
          currentClip = currentClip?.copyWith(
            notes: currentClip!.notes.where((n) => n.id != clickedNote.id).toList(),
          );
        });
        commitToHistory('Delete note');
        notifyClipUpdated();
      }
      return;
    }

    // Slice tool OR Cmd+click = slice
    if (toolMode == ToolMode.slice) {
      if (clickedNote != null) {
        final beatPosition = _getBeatAtX(details.localPosition.dx);
        sliceNoteAt(clickedNote, beatPosition);
      }
      return;
    }

    // Duplicate tool OR Cmd+click on note = duplicate in place
    if (toolMode == ToolMode.duplicate || (modifiers.isCtrlOrCmd && clickedNote != null)) {
      if (clickedNote != null) {
        saveToHistory();
        final duplicate = clickedNote.copyWith(
          id: '${clickedNote.note}_${DateTime.now().microsecondsSinceEpoch}',
          isSelected: false,
        );
        setState(() {
          currentClip = currentClip?.addNote(duplicate);
        });
        commitToHistory('Duplicate note');
        notifyClipUpdated();
        startAudition(clickedNote.note, clickedNote.velocity);
      }
      return;
    }

    // Select tool = only select notes, don't create new ones
    if (toolMode == ToolMode.select) {
      if (clickedNote != null) {
        // Shift+click = toggle selection (add/remove from selection)
        if (modifiers.isShiftPressed) {
          pendingNoteTapSelection = null;
          setState(() {
            currentClip = currentClip?.copyWith(
              notes: currentClip!.notes.map((n) {
                if (n.id == clickedNote.id) {
                  return n.copyWith(isSelected: !n.isSelected);
                }
                return n;
              }).toList(),
            );
          });
        } else if (clickedNote.isSelected) {
          // Clicking on already-selected note: defer single-selection to tap-up
          // (allows multi-drag if user drags instead of clicking)
          pendingNoteTapSelection = clickedNote.id;
        } else {
          // Regular click on unselected note = select only this note
          pendingNoteTapSelection = null;
          setState(() {
            currentClip = currentClip?.copyWith(
              notes: currentClip!.notes.map((n) {
                if (n.id == clickedNote.id) {
                  return n.copyWith(isSelected: true);
                } else {
                  return n.copyWith(isSelected: false);
                }
              }).toList(),
            );
          });
        }
        notifyClipUpdated();
        startAudition(clickedNote.note, clickedNote.velocity);
      } else {
        // Click on empty space = deselect all
        pendingNoteTapSelection = null;
        setState(() {
          currentClip = currentClip?.copyWith(
            notes: currentClip!.notes.map((n) => n.copyWith(isSelected: false)).toList(),
          );
        });
        notifyClipUpdated();
      }
      return;
    }

    // ============================================
    // DRAW TOOL (default behavior)
    // ============================================

    // Cmd+click on empty space = slice any note at that beat position
    if (modifiers.isCtrlOrCmd && clickedNote == null) {
      final beat = _getBeatAtX(details.localPosition.dx);
      final noteToSlice = currentClip?.notes.firstWhere(
        (n) => n.startTime < beat && (n.startTime + n.duration) > beat,
        orElse: () => MidiNoteData(note: -1, velocity: 0, startTime: 0, duration: 0),
      );
      if (noteToSlice != null && noteToSlice.note >= 0) {
        sliceNoteAt(noteToSlice, beat);
      }
      return;
    }

    // DRAW TOOL: Click on existing note = select it (FL Studio style)
    if (clickedNote != null) {
      // Select this note, deselect others (unless Shift held or note already selected)
      if (modifiers.isShiftPressed) {
        // Toggle selection
        pendingNoteTapSelection = null;
        setState(() {
          currentClip = currentClip?.copyWith(
            notes: currentClip!.notes.map((n) {
              if (n.id == clickedNote.id) {
                return n.copyWith(isSelected: !n.isSelected);
              }
              return n;
            }).toList(),
          );
        });
      } else if (clickedNote.isSelected) {
        // Clicking on already-selected note: defer single-selection to tap-up
        // (allows multi-drag if user drags instead of clicking)
        pendingNoteTapSelection = clickedNote.id;
      } else {
        // Select only this note (unselected note clicked)
        pendingNoteTapSelection = null;
        setState(() {
          currentClip = currentClip?.copyWith(
            notes: currentClip!.notes.map((n) {
              if (n.id == clickedNote.id) {
                return n.copyWith(isSelected: true);
              } else {
                return n.copyWith(isSelected: false);
              }
            }).toList(),
          );
        });
      }
      notifyClipUpdated();
      startAudition(clickedNote.note, clickedNote.velocity);
      return;
    }

    // DRAW TOOL: Click on empty space = create new note
    {
      // Single-click on empty space = create note (Draw tool)
      final beat = _getBeatAtX(details.localPosition.dx);
      final noteRow = _getNoteAtY(details.localPosition.dy);

      saveToHistory();
      final snappedBeat = snapToGrid(beat);

      // Check if chord palette is visible - stamp chord instead of single note
      if (chordPaletteVisible) {
        _stampChordAt(snappedBeat, noteRow);
        return;
      }

      // Create single note (FL Studio style)
      final newNote = MidiNoteData(
        note: noteRow,
        velocity: 100,
        startTime: snappedBeat,
        duration: lastNoteDuration,
        isSelected: true,  // Auto-select new note for immediate manipulation
      );

      setState(() {
        // Deselect all existing notes, then add the new selected note
        currentClip = currentClip?.copyWith(
          notes: currentClip!.notes.map((n) => n.copyWith(isSelected: false)).toList(),
        );
        currentClip = currentClip?.addNote(newNote);

        // Auto-extend loop length if note extends beyond current loop
        autoExtendLoopIfNeeded(newNote);
      });

      // Track this note for immediate drag-to-move if user drags
      justCreatedNoteId = newNote.id;

      commitToHistory('Add note');
      notifyClipUpdated();
      // Start sustained audition (will stop on mouse up)
      startAudition(noteRow, 100);
    }
  }

  void _onTapUp(TapUpDetails details) {
    stopAudition();

    // If we had a pending tap selection (clicked on already-selected note),
    // now reduce to single selection since no drag occurred
    if (pendingNoteTapSelection != null) {
      final noteId = pendingNoteTapSelection!;
      setState(() {
        currentClip = currentClip?.copyWith(
          notes: currentClip!.notes.map((n) {
            if (n.id == noteId) {
              return n.copyWith(isSelected: true);
            } else {
              return n.copyWith(isSelected: false);
            }
          }).toList(),
        );
      });
      notifyClipUpdated();
      pendingNoteTapSelection = null;
    }
  }

  void _onPanStart(DragStartDetails details) {
    // Clear pending tap selection - user is dragging, not clicking
    pendingNoteTapSelection = null;

    // Request focus to enable keyboard events (delete, undo, etc.)
    focusNode.requestFocus();

    dragStart = details.localPosition;
    final clickedNote = _findNoteAtPosition(details.localPosition);
    final modifiers = ModifierKeyState.current();
    // Get effective tool mode using resolver (handles modifier key overrides)
    final toolMode = ToolModeResolver.resolve(widget.toolMode);

    // Skip normal pan handling if Alt is held OR eraser tool is active
    if (modifiers.isAltPressed || toolMode == ToolMode.eraser) {
      return;
    }

    // Box selection: Shift+drag on empty OR Select tool drag on empty
    if ((modifiers.isShiftPressed || toolMode == ToolMode.select) && clickedNote == null) {
      // Marquee/box select
      setState(() {
        isSelecting = true;
        selectionStart = details.localPosition;
        selectionEnd = details.localPosition;
        currentMode = InteractionMode.select;
      });
      return;
    }

    // Select tool: drag on a note = move the note (not create new)
    if (toolMode == ToolMode.select && clickedNote != null) {
      // Move note(s) - similar to normal drag on note
      saveToHistory();
      setState(() {
        // Select the clicked note if not already selected
        if (!clickedNote.isSelected) {
          currentClip = currentClip?.copyWith(
            notes: currentClip!.notes.map((n) {
              if (n.id == clickedNote.id) {
                return n.copyWith(isSelected: true);
              } else if (!modifiers.isShiftPressed) {
                return n.copyWith(isSelected: false);
              }
              return n;
            }).toList(),
          );
        }
        // Store original positions for all selected notes
        dragStartNotes = {};
        for (final note in currentClip!.selectedNotes) {
          dragStartNotes[note.id] = note;
        }
        movingNoteId = clickedNote.id;
        currentMode = InteractionMode.move;
        currentCursor = SystemMouseCursors.grabbing;
      });
      startAudition(clickedNote.note, clickedNote.velocity);
      return;
    }

    // Duplicate tool: drag on note = duplicate and move
    if (toolMode == ToolMode.duplicate && clickedNote != null) {
      saveToHistory();
      isDuplicating = true;

      final selectedNotes = currentClip?.selectedNotes ?? [];
      final notesToDuplicate = selectedNotes.isNotEmpty && selectedNotes.any((n) => n.id == clickedNote.id)
          ? selectedNotes
          : [clickedNote];

      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final duplicatedNotes = <MidiNoteData>[];
      dragStartNotes = {};

      for (int i = 0; i < notesToDuplicate.length; i++) {
        final sourceNote = notesToDuplicate[i];
        final duplicatedNote = sourceNote.copyWith(
          id: '${sourceNote.note}_${sourceNote.startTime}_${timestamp}_$i',
          isSelected: false,
        );
        duplicatedNotes.add(duplicatedNote);
        dragStartNotes[duplicatedNote.id] = duplicatedNote;
      }

      final primaryDuplicate = duplicatedNotes.first;

      setState(() {
        final deselectedNotes = currentClip!.notes.map((n) => n.copyWith(isSelected: false)).toList();
        currentClip = currentClip?.copyWith(
          notes: [...deselectedNotes, ...duplicatedNotes],
        );
        currentClip = currentClip?.copyWith(
          notes: currentClip!.notes.map((n) {
            if (duplicatedNotes.any((dup) => dup.id == n.id)) {
              return n.copyWith(isSelected: true);
            }
            return n;
          }).toList(),
        );
        movingNoteId = primaryDuplicate.id;
        currentMode = InteractionMode.move;
        currentCursor = SystemMouseCursors.copy;
      });

      startAudition(clickedNote.note, clickedNote.velocity);
      return;
    }

    // Slice tool: skip pan handling (slicing is done on tap)
    if (toolMode == ToolMode.slice) {
      return;
    }

    // ============================================
    // DRAW TOOL (default) behavior below
    // ============================================

    if (modifiers.isCtrlOrCmd && clickedNote != null) {
      // Cmd/Ctrl+drag on note = duplicate mode (supports multiple selected notes)
      saveToHistory();
      isDuplicating = true;

      // Determine which notes to duplicate: all selected notes, or just the clicked note if none selected
      final selectedNotes = currentClip?.selectedNotes ?? [];
      final notesToDuplicate = selectedNotes.isNotEmpty && selectedNotes.any((n) => n.id == clickedNote.id)
          ? selectedNotes  // Duplicate all selected notes (clicked note is part of selection)
          : [clickedNote]; // Just duplicate the single clicked note

      // Create duplicates for all notes to be duplicated
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final duplicatedNotes = <MidiNoteData>[];
      dragStartNotes = {};

      for (int i = 0; i < notesToDuplicate.length; i++) {
        final sourceNote = notesToDuplicate[i];
        final duplicatedNote = sourceNote.copyWith(
          id: '${sourceNote.note}_${sourceNote.startTime}_${timestamp}_$i',
          isSelected: false,
        );
        duplicatedNotes.add(duplicatedNote);
        // Store original positions for proper delta calculation
        dragStartNotes[duplicatedNote.id] = duplicatedNote;
      }

      // Track the first duplicate as the "primary" moving note (for audition)
      final primaryDuplicate = duplicatedNotes.first;

      setState(() {
        // Deselect all original notes, then add all duplicates
        final deselectedNotes = currentClip!.notes.map((n) => n.copyWith(isSelected: false)).toList();
        currentClip = currentClip?.copyWith(
          notes: [...deselectedNotes, ...duplicatedNotes],
        );
        // Mark all duplicates as selected so they move together
        currentClip = currentClip?.copyWith(
          notes: currentClip!.notes.map((n) {
            if (duplicatedNotes.any((dup) => dup.id == n.id)) {
              return n.copyWith(isSelected: true);
            }
            return n;
          }).toList(),
        );
        movingNoteId = primaryDuplicate.id; // Track primary duplicate
        currentMode = InteractionMode.move;
        currentCursor = SystemMouseCursors.copy;
      });

      startAudition(clickedNote.note, clickedNote.velocity);
    } else if (justCreatedNoteId != null) {
      // User is dragging from where they just created a note - move it (FL Studio style)
      final createdNote = currentClip?.notes.firstWhere(
        (n) => n.id == justCreatedNoteId,
        orElse: () => MidiNoteData(note: 60, velocity: 100, startTime: 0, duration: 1),
      );

      if (createdNote != null && createdNote.id == justCreatedNoteId) {
        // Start moving the just-created note
        saveToHistory();

        // Store original positions of all notes for proper delta calculation
        dragStartNotes = {
          for (final n in currentClip?.notes ?? <MidiNoteData>[]) n.id: n
        };

        // Mark this note as the one being moved (for _onPanUpdate)
        movingNoteId = justCreatedNoteId;

        setState(() {
          currentMode = InteractionMode.move;
          currentCursor = SystemMouseCursors.grabbing;
        });

      }

      // Clear just-created tracking
      justCreatedNoteId = null;
    } else if (clickedNote != null && !isSliceModeActive) {
      // DRAW TOOL: Allow moving/resizing existing notes (FL Studio style)
      // Check if we're near the edge for resizing
      final edge = _getEdgeAtPosition(details.localPosition, clickedNote);

      if (edge != null) {
        // Start resizing from left or right edge
        saveToHistory(); // Save before resizing
        setState(() {
          resizingNoteId = clickedNote.id;
          resizingEdge = edge; // Store which edge ('left' or 'right')
          currentMode = InteractionMode.resize;
          currentCursor = SystemMouseCursors.resizeLeftRight;
        });
      } else {
        // Start moving the note (clicked on body)
        saveToHistory(); // Save before moving

        // Store original positions of all notes for proper delta calculation
        dragStartNotes = {
          for (final n in currentClip?.notes ?? <MidiNoteData>[]) n.id: n
        };

        // Mark this note as the one being moved (no selection highlight)
        movingNoteId = clickedNote.id;

        setState(() {
          currentMode = InteractionMode.move;
          currentCursor = SystemMouseCursors.grabbing; // Closed hand while dragging
        });

        // Start sustained audition when starting to drag (FL Studio style)
        startAudition(clickedNote.note, clickedNote.velocity);
      }
    }
    // Note: No longer need to handle drawing here - single-click in _onTapDown creates notes
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (currentMode == InteractionMode.select && isSelecting) {
      // Update selection rectangle and select notes LIVE
      setState(() {
        selectionEnd = details.localPosition;

        // Live selection - update note selection as rectangle changes
        if (selectionStart != null && selectionEnd != null) {
          final startBeat = _getBeatAtX(selectionStart!.dx.clamp(0, double.infinity));
          final endBeat = _getBeatAtX(selectionEnd!.dx.clamp(0, double.infinity));
          final startNote = _getNoteAtY(selectionStart!.dy.clamp(0, double.infinity));
          final endNote = _getNoteAtY(selectionEnd!.dy.clamp(0, double.infinity));

          final minBeat = startBeat < endBeat ? startBeat : endBeat;
          final maxBeat = startBeat < endBeat ? endBeat : startBeat;
          final minNote = startNote < endNote ? startNote : endNote;
          final maxNote = startNote < endNote ? endNote : startNote;

          currentClip = currentClip?.copyWith(
            notes: currentClip!.notes.map((note) {
              // Overlap detection: note is selected if it overlaps the selection box
              // (not requiring full containment)
              final isInRange = note.startTime < maxBeat &&   // Note starts before selection ends
                                note.endTime > minBeat &&     // Note ends after selection starts
                                note.note >= minNote &&
                                note.note <= maxNote;
              return note.copyWith(isSelected: isInRange);
            }).toList(),
          );
        }
      });
    } else if (isPainting && paintNote != null) {
      // Paint mode - create additional notes as user drags right
      final currentBeat = snapToGrid(_getBeatAtX(details.localPosition.dx));
      final nextNoteBeat = lastPaintedBeat + lastNoteDuration;

      // Only create note if we've dragged far enough for the next note
      if (currentBeat >= nextNoteBeat) {
        final newNote = MidiNoteData(
          note: paintNote!,
          velocity: 100,
          startTime: nextNoteBeat,
          duration: lastNoteDuration,
        );

        setState(() {
          currentClip = currentClip?.addNote(newNote);
          lastPaintedBeat = nextNoteBeat;
          // Auto-extend loop if note extends beyond current loop boundary
          autoExtendLoopIfNeeded(newNote);
        });

      }
    } else if (currentMode == InteractionMode.move && dragStart != null) {
      // Move selected notes - use delta from original drag start position
      // Shift key bypasses grid snap for fine adjustment
      final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
      final deltaX = details.localPosition.dx - dragStart!.dx;
      final deltaY = details.localPosition.dy - dragStart!.dy;

      final deltaBeat = deltaX / pixelsPerBeat;
      final deltaNote = -(deltaY / pixelsPerNote).round(); // Inverted Y

      // Track pitch changes for audition
      int? newPitchForAudition;
      int? velocityForAudition;

      // Track moved notes for auto-extend
      final List<MidiNoteData> movedNotes = [];

      setState(() {
        currentClip = currentClip?.copyWith(
          notes: currentClip!.notes.map((n) {
            // Move the note being dragged (by movingNoteId) or any selected notes
            if (n.id == movingNoteId || n.isSelected) {
              // Use original position from drag start, not current position
              final originalNote = dragStartNotes[n.id];
              if (originalNote != null) {
                final rawStartTime = originalNote.startTime + deltaBeat;
                final newStartTime = (isShiftPressed ? rawStartTime : snapToGrid(rawStartTime)).clamp(0.0, 64.0);
                var newNote = (originalNote.note + deltaNote).clamp(0, 127);

                // Apply scale lock if enabled
                if (scaleLockEnabled) {
                  newNote = snapNoteToScale(newNote);
                }

                // Capture the new pitch for audition
                if (newPitchForAudition == null) {
                  newPitchForAudition = newNote;
                  velocityForAudition = n.velocity;
                }

                final movedNote = n.copyWith(
                  startTime: newStartTime,
                  note: newNote,
                );
                movedNotes.add(movedNote);
                return movedNote;
              }
            }
            return n;
          }).toList(),
        );

        // Auto-extend loop if any moved note extends beyond loop boundary
        for (final movedNote in movedNotes) {
          autoExtendLoopIfNeeded(movedNote);
        }
        // Don't update dragStart here - keep original for cumulative delta
      });

      // Change audition pitch when dragging note up/down
      if (newPitchForAudition != null) {
        changeAuditionPitch(newPitchForAudition!, velocityForAudition ?? 100);
      }

      notifyClipUpdated();
    } else if (currentMode == InteractionMode.resize && resizingNoteId != null) {
      // Resize note from left or right edge (FL Studio style)
      // Shift key bypasses grid snap for fine adjustment
      final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
      // When snap is off or shift is pressed, allow very small notes (like Ableton)
      // Otherwise use effective grid division as minimum
      final minDuration = (!snapEnabled || isShiftPressed)
          ? 0.01 // ~1-2px at typical zoom, allows very short notes
          : getEffectiveGridDivision();
      MidiNoteData? resizedNote;
      setState(() {
        currentClip = currentClip?.copyWith(
          notes: currentClip!.notes.map((n) {
            if (n.id == resizingNoteId) {
              final rawBeat = _getBeatAtX(details.localPosition.dx);
              final newBeat = isShiftPressed ? rawBeat : snapToGrid(rawBeat);

              if (resizingEdge == 'right') {
                // Right edge: change duration only
                final newDuration = (newBeat - n.startTime).clamp(minDuration, 64.0);
                resizedNote = n.copyWith(duration: newDuration);
                return resizedNote!;
              } else if (resizingEdge == 'left') {
                // Left edge: change start time and duration
                final oldEndTime = n.endTime;
                final newStartTime = newBeat.clamp(0.0, oldEndTime - minDuration);
                final newDuration = oldEndTime - newStartTime;
                resizedNote = n.copyWith(
                  startTime: newStartTime,
                  duration: newDuration,
                );
                return resizedNote!;
              }
            }
            return n;
          }).toList(),
        );

        // Auto-extend loop if note was resized beyond loop boundary
        if (resizedNote != null) {
          autoExtendLoopIfNeeded(resizedNote!);
        }
      });
      notifyClipUpdated();
    }
  }

  void _onPanEnd(DragEndDetails details) {
    // Clear just-created tracking on any pan end
    justCreatedNoteId = null;

    // Handle paint mode completion (legacy - kept for potential future use)
    if (isPainting) {
      final paintedNotes = lastPaintedBeat - (paintStartBeat ?? 0);
      final additionalNotes = (paintedNotes / lastNoteDuration).round();

      // Only commit if we actually painted additional notes (beyond the initial click-created one)
      if (additionalNotes > 0) {
        saveToHistory();
        commitToHistory('Paint ${additionalNotes + 1} notes');
        notifyClipUpdated();
      }

      setState(() {
        isPainting = false;
        paintStartBeat = null;
        paintNote = null;
        lastPaintedBeat = 0.0;
      });
      return;
    }

    if (currentMode == InteractionMode.select && isSelecting) {
      // Selection is already applied live in _onPanUpdate()
      // Just clean up selection state here
      setState(() {
        isSelecting = false;
        selectionStart = null;
        selectionEnd = null;
      });
    }

    // Commit move or duplicate operation to history
    if (currentMode == InteractionMode.move) {
      if (isDuplicating) {
        final duplicateCount = currentClip?.selectedNotes.length ?? 1;
        commitToHistory(duplicateCount == 1 ? 'Duplicate note' : 'Duplicate $duplicateCount notes');
      } else {
        final selectedCount = currentClip?.selectedNotes.length ?? 0;
        if (selectedCount > 0) {
          commitToHistory(selectedCount == 1 ? 'Move note' : 'Move $selectedCount notes');
        }
      }
    }

    // Remember duration of resized note for next creation
    if (currentMode == InteractionMode.resize && resizingNoteId != null) {
      final resizedNote = currentClip?.notes.firstWhere((n) => n.id == resizingNoteId);
      if (resizedNote != null) {
        lastNoteDuration = resizedNote.duration;
        commitToHistory('Resize note');
      }
    }

    // Stop audition when mouse released
    stopAudition();

    // Reset state
    setState(() {
      dragStart = null;
      dragStartNotes = {}; // Clear stored original positions
      movingNoteId = null; // Clear moving note tracking
      isDuplicating = false; // Clear duplicate mode
      resizingNoteId = null;
      resizingEdge = null;
      currentMode = InteractionMode.draw;
      currentCursor = SystemMouseCursors.basic; // Reset cursor to default
    });
  }

  // Handle keyboard events for deletion, undo/redo, and copy/paste
  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // Delete key
      if (event.logicalKey == LogicalKeyboardKey.delete ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        if (currentClip?.selectedNotes.isNotEmpty ?? false) {
          saveToHistory();
          deleteSelectedNotes();
        }
      }
      // Undo (Cmd+Z or Ctrl+Z)
      else if ((event.logicalKey == LogicalKeyboardKey.keyZ) &&
          (HardwareKeyboard.instance.isMetaPressed ||
           HardwareKeyboard.instance.isControlPressed) &&
          !HardwareKeyboard.instance.isShiftPressed) {
        undo();
      }
      // Redo (Cmd+Shift+Z or Ctrl+Shift+Z)
      else if ((event.logicalKey == LogicalKeyboardKey.keyZ) &&
          (HardwareKeyboard.instance.isMetaPressed ||
           HardwareKeyboard.instance.isControlPressed) &&
          HardwareKeyboard.instance.isShiftPressed) {
        redo();
      }
      // Copy (Cmd+C or Ctrl+C)
      else if ((event.logicalKey == LogicalKeyboardKey.keyC) &&
          (HardwareKeyboard.instance.isMetaPressed ||
           HardwareKeyboard.instance.isControlPressed)) {
        copySelectedNotes();
      }
      // Paste (Cmd+V or Ctrl+V)
      else if ((event.logicalKey == LogicalKeyboardKey.keyV) &&
          (HardwareKeyboard.instance.isMetaPressed ||
           HardwareKeyboard.instance.isControlPressed)) {
        pasteNotes();
      }
      // Q to quantize selected notes
      else if (event.logicalKey == LogicalKeyboardKey.keyQ &&
          !HardwareKeyboard.instance.isMetaPressed &&
          !HardwareKeyboard.instance.isControlPressed) {
        quantizeSelectedNotes();
      }
      // Cmd+D or Ctrl+D to duplicate selected notes
      else if ((event.logicalKey == LogicalKeyboardKey.keyD) &&
          (HardwareKeyboard.instance.isMetaPressed ||
           HardwareKeyboard.instance.isControlPressed)) {
        duplicateSelectedNotes();
      }
      // Cmd+B or Ctrl+B to duplicate selected notes (FL Studio style)
      else if ((event.logicalKey == LogicalKeyboardKey.keyB) &&
          (HardwareKeyboard.instance.isMetaPressed ||
           HardwareKeyboard.instance.isControlPressed)) {
        duplicateSelectedNotes();
      }
      // Cmd+A or Ctrl+A to select all notes
      else if ((event.logicalKey == LogicalKeyboardKey.keyA) &&
          (HardwareKeyboard.instance.isMetaPressed ||
           HardwareKeyboard.instance.isControlPressed)) {
        selectAllNotes();
      }
      // Escape to deselect all notes / cancel action
      else if (event.logicalKey == LogicalKeyboardKey.escape) {
        deselectAllNotes();
      }
      // Cut (Cmd+X or Ctrl+X)
      else if ((event.logicalKey == LogicalKeyboardKey.keyX) &&
          (HardwareKeyboard.instance.isMetaPressed ||
           HardwareKeyboard.instance.isControlPressed)) {
        cutSelectedNotes();
      }
      // ============================================
      // STICKY TOOL SHORTCUTS (ZXCVB)
      // Press once to switch tool, stays active until switched again
      // ============================================
      // Z = Draw tool
      else if (event.logicalKey == LogicalKeyboardKey.keyZ &&
          !HardwareKeyboard.instance.isMetaPressed &&
          !HardwareKeyboard.instance.isControlPressed) {
        widget.onToolModeChanged?.call(ToolMode.draw);
      }
      // X = Select tool
      else if (event.logicalKey == LogicalKeyboardKey.keyX &&
          !HardwareKeyboard.instance.isMetaPressed &&
          !HardwareKeyboard.instance.isControlPressed) {
        widget.onToolModeChanged?.call(ToolMode.select);
      }
      // C = Erase tool (without Cmd/Ctrl - Cmd+C is copy)
      else if (event.logicalKey == LogicalKeyboardKey.keyC &&
          !HardwareKeyboard.instance.isMetaPressed &&
          !HardwareKeyboard.instance.isControlPressed) {
        widget.onToolModeChanged?.call(ToolMode.eraser);
      }
      // V = Duplicate tool (without Cmd/Ctrl - Cmd+V is paste)
      else if (event.logicalKey == LogicalKeyboardKey.keyV &&
          !HardwareKeyboard.instance.isMetaPressed &&
          !HardwareKeyboard.instance.isControlPressed) {
        widget.onToolModeChanged?.call(ToolMode.duplicate);
      }
      // B = Slice tool
      else if (event.logicalKey == LogicalKeyboardKey.keyB &&
          !HardwareKeyboard.instance.isMetaPressed &&
          !HardwareKeyboard.instance.isControlPressed) {
        widget.onToolModeChanged?.call(ToolMode.slice);
      }
      // K key to toggle chord palette
      else if (event.logicalKey == LogicalKeyboardKey.keyK &&
          !HardwareKeyboard.instance.isMetaPressed &&
          !HardwareKeyboard.instance.isControlPressed) {
        setState(() => chordPaletteVisible = !chordPaletteVisible);
      }
      // ============================================
      // TRANSPOSE SHORTCUTS
      // ============================================
      // Up arrow = transpose up 1 semitone
      // Shift+Up = transpose up 1 octave (12 semitones)
      else if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
          !HardwareKeyboard.instance.isMetaPressed &&
          !HardwareKeyboard.instance.isControlPressed) {
        if (currentClip?.selectedNotes.isNotEmpty ?? false) {
          final semitones = HardwareKeyboard.instance.isShiftPressed ? 12 : 1;
          transposeSelectedNotes(semitones);
        }
      }
      // Down arrow = transpose down 1 semitone
      // Shift+Down = transpose down 1 octave (12 semitones)
      else if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
          !HardwareKeyboard.instance.isMetaPressed &&
          !HardwareKeyboard.instance.isControlPressed) {
        if (currentClip?.selectedNotes.isNotEmpty ?? false) {
          final semitones = HardwareKeyboard.instance.isShiftPressed ? -12 : -1;
          transposeSelectedNotes(semitones);
        }
      }
    } else if (event is KeyUpEvent) {
      // Hold modifiers are handled via tempModeOverride in _updateCursorForModifiers
    }
  }

  /// Show context menu for a note
  void _showNoteContextMenu(Offset position, MidiNoteData note) {
    final selectedNotes = currentClip?.selectedNotes ?? [];
    final bool hasSelection = selectedNotes.isNotEmpty;
    final int selectedCount = hasSelection ? selectedNotes.length : 1;

    showNoteContextMenu(
      context: context,
      position: position,
      selectedCount: selectedCount,
      velocity: note.velocity,
      canPaste: clipboard.isNotEmpty,
    ).then((value) {
      if (value == null) return;

      switch (value) {
        case 'delete':
          if (hasSelection) {
            deleteSelectedNotes();
          } else {
            deleteNote(note);
          }
          break;
        case 'duplicate':
          if (hasSelection) {
            duplicateSelectedNotes();
          } else {
            duplicateNote(note);
          }
          break;
        case 'cut':
          cutSelectedNotes();
          break;
        case 'copy':
          copySelectedNotes();
          break;
        case 'paste':
          pasteNotes();
          break;
        case 'velocity':
          setState(() => velocityLaneExpanded = true);
          break;
        case 'quantize':
          quantizeSelectedNotes();
          break;
      }
    });
  }

  /// Start eraser mode (right-click drag)
  void _startErasing(Offset position) {
    saveToHistory();
    isErasing = true;
    erasedNoteIds = {};
    setState(() => currentCursor = SystemMouseCursors.forbidden);
    _eraseNotesAt(position);
  }

  /// Erase notes at the given position
  void _eraseNotesAt(Offset position) {
    final note = _findNoteAtPosition(position);
    if (note != null && !erasedNoteIds.contains(note.id)) {
      erasedNoteIds.add(note.id);
      setState(() {
        currentClip = currentClip?.copyWith(
          notes: currentClip!.notes.where((n) => n.id != note.id).toList(),
        );
      });
      notifyClipUpdated();
    }
  }

  /// Stop eraser mode
  void _stopErasing() {
    if (erasedNoteIds.isNotEmpty) {
      commitToHistory('Delete ${erasedNoteIds.length} notes');
    }
    isErasing = false;
    erasedNoteIds = {};
    setState(() => currentCursor = SystemMouseCursors.basic);
  }
}
