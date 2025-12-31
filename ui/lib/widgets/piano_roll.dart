import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../models/midi_note_data.dart';
import '../models/midi_cc_data.dart';
import '../models/scale_data.dart';
import '../audio_engine.dart';
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
import 'shared/mini_knob.dart';
import 'context_menus/note_context_menu.dart';

/// Interaction modes for piano roll (internal tracking during gestures)
enum InteractionMode { draw, select, move, resize }

/// Tool modes for piano roll toolbar buttons
enum ToolMode {
  draw,      // Default: click to create notes
  select,    // Select and move notes
  eraser,    // Delete notes on click
  duplicate, // Duplicate notes on click/drag
  slice,     // Split notes at click position
}

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

  const PianoRoll({
    super.key,
    this.audioEngine,
    this.clipData,
    this.onClose,
    this.onClipUpdated,
    this.ghostNotes = const [],
    this.toolMode = ToolMode.draw,
    this.onToolModeChanged,
  });

  @override
  State<PianoRoll> createState() => _PianoRollState();
}

class _PianoRollState extends State<PianoRoll>
    with PianoRollStateMixin,
         NoteOperationsMixin,
         ClipboardOperationsMixin,
         SelectionOperationsMixin,
         NoteGestureHandlerMixin {
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

    // Listen for undo/redo changes to update our state
    undoRedoManager.addListener(_onUndoRedoChanged);

    // Listen for hardware keyboard events (for modifier key cursor updates)
    HardwareKeyboard.instance.addHandler(_onHardwareKey);

    // Sync horizontal scroll between ruler and grid
    horizontalScroll.addListener(_syncRulerFromGrid);
    rulerScroll.addListener(_syncGridFromRuler);

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
    isSyncingScroll = false;
  }

  void _syncGridFromRuler() {
    if (isSyncingScroll) return;
    if (!rulerScroll.hasClients || !horizontalScroll.hasClients) return;
    isSyncingScroll = true;
    horizontalScroll.jumpTo(rulerScroll.offset.clamp(0.0, horizontalScroll.position.maxScrollExtent));
    isSyncingScroll = false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    undoRedoManager.removeListener(_onUndoRedoChanged);
    horizontalScroll.removeListener(_syncRulerFromGrid);
    rulerScroll.removeListener(_syncGridFromRuler);
    focusNode.dispose();
    horizontalScroll.dispose();
    rulerScroll.dispose();
    verticalScroll.dispose();
    super.dispose();
  }

  /// Handle hardware keyboard events for modifier key cursor updates
  bool _onHardwareKey(KeyEvent event) {
    // Update cursor when Alt or Cmd/Ctrl is pressed or released
    if (event.logicalKey == LogicalKeyboardKey.alt ||
        event.logicalKey == LogicalKeyboardKey.altLeft ||
        event.logicalKey == LogicalKeyboardKey.altRight ||
        event.logicalKey == LogicalKeyboardKey.meta ||
        event.logicalKey == LogicalKeyboardKey.metaLeft ||
        event.logicalKey == LogicalKeyboardKey.metaRight ||
        event.logicalKey == LogicalKeyboardKey.control ||
        event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight) {
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

  /// Start sustained audition - note plays until _stopAudition is called (FL Studio style)
  void _startAudition(int midiNote, int velocity) {
    if (!auditionEnabled) return;

    // Stop any currently held note first
    _stopAudition();

    final trackId = currentClip?.trackId;
    if (trackId != null && widget.audioEngine != null) {
      widget.audioEngine!.sendTrackMidiNoteOn(trackId, midiNote, velocity);
      currentlyHeldNote = midiNote;
    }
  }

  /// Stop the currently held audition note
  void _stopAudition() {
    if (currentlyHeldNote != null) {
      final trackId = currentClip?.trackId;
      if (trackId != null && widget.audioEngine != null) {
        widget.audioEngine!.sendTrackMidiNoteOff(trackId, currentlyHeldNote!, 64);
      }
      currentlyHeldNote = null;
    }
  }

  /// Change the audition pitch while holding (for dragging notes up/down)
  void _changeAuditionPitch(int newMidiNote, int velocity) {
    if (!auditionEnabled) return;
    if (newMidiNote == currentlyHeldNote) return; // Same note, no change needed

    final trackId = currentClip?.trackId;
    if (trackId != null && widget.audioEngine != null) {
      // Stop old note
      if (currentlyHeldNote != null) {
        widget.audioEngine!.sendTrackMidiNoteOff(trackId, currentlyHeldNote!, 64);
      }
      // Start new note
      widget.audioEngine!.sendTrackMidiNoteOn(trackId, newMidiNote, velocity);
      currentlyHeldNote = newMidiNote;
    }
  }

  /// Toggle note audition on/off
  void _toggleAudition() {
    setState(() {
      auditionEnabled = !auditionEnabled;
    });
  }

  /// Preview/audition a chord (play all notes simultaneously)
  void _previewChord(List<int> midiNotes) {
    if (!auditionEnabled) return;
    final trackId = currentClip?.trackId;
    if (trackId == null || widget.audioEngine == null) return;

    // Play all notes in the chord
    for (final midiNote in midiNotes) {
      widget.audioEngine!.sendTrackMidiNoteOn(trackId, midiNote, 100);
    }
    // Stop notes after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      for (final midiNote in midiNotes) {
        widget.audioEngine?.sendTrackMidiNoteOff(trackId, midiNote, 64);
      }
    });
  }

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
    _previewChord(newNotes.map((n) => n.note).toList());
  }

  /// Toggle velocity lane on/off
  void _toggleVelocityLane() {
    setState(() {
      velocityLaneExpanded = !velocityLaneExpanded;
    });
  }

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

  /// Calculate max pixelsPerBeat (zoom in limit)
  /// 1 sixteenth note (0.25 beats) should fill the view width
  double _calculateMaxPixelsPerBeat() {
    // 1 sixteenth = 0.25 beats should fill viewWidth
    // pixelsPerBeat = viewWidth / 0.25
    return viewWidth / 0.25;
  }

  /// Calculate min pixelsPerBeat (zoom out limit)
  /// Clip length + 4 bars should fit in view
  double _calculateMinPixelsPerBeat() {
    final clipLength = getLoopLength();
    final totalBeatsToShow = clipLength + 16.0; // clip + 4 bars (16 beats)
    // pixelsPerBeat = viewWidth / totalBeatsToShow
    return viewWidth / totalBeatsToShow;
  }

  void _zoomIn() {
    setState(() {
      // 50% zoom in per click (1.5x multiplier)
      final maxZoom = _calculateMaxPixelsPerBeat();
      final minZoom = _calculateMinPixelsPerBeat();
      pixelsPerBeat = (pixelsPerBeat * 1.5).clamp(minZoom, maxZoom);
    });
  }

  void _zoomOut() {
    setState(() {
      // 50% zoom out per click (divide by 1.5)
      final maxZoom = _calculateMaxPixelsPerBeat();
      final minZoom = _calculateMinPixelsPerBeat();
      pixelsPerBeat = (pixelsPerBeat / 1.5).clamp(minZoom, maxZoom);
    });
  }

  void _toggleSnap() {
    setState(() {
      snapEnabled = !snapEnabled;
    });
  }

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
                  onPreview: _previewChord,
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
    // Total beats extends beyond loop for scrolling
    final totalBeats = calculateTotalBeats();

    final canvasWidth = totalBeats * pixelsPerBeat;
    final canvasHeight = (PianoRollStateMixin.maxMidiNote - PianoRollStateMixin.minMidiNote + 1) * pixelsPerNote;

    return Expanded(
      child: Column(
        children: [
          // Horizontal controls bar (replaces left sidebar)
          PianoRollControlsBar(
            // Clip section
            loopEnabled: loopEnabled,
            loopStartBeats: loopStartBeats,
            loopLengthBeats: getLoopLength(),
            beatsPerBar: beatsPerBar,
            beatUnit: beatUnit,
            onLoopToggle: () => setState(() => loopEnabled = !loopEnabled),
            onLoopStartChanged: (beats) => setState(() => loopStartBeats = beats),
            onLoopLengthChanged: (beats) {
              if (currentClip == null) return;
              final newLength = beats.clamp(4.0, 256.0);
              setState(() {
                currentClip = currentClip!.copyWith(loopLength: newLength);
              });
              notifyClipUpdated();
            },
            onBeatsPerBarChanged: (value) => setState(() => beatsPerBar = value),
            onBeatUnitChanged: (value) => setState(() => beatUnit = value),
            // Grid section
            snapEnabled: snapEnabled,
            gridDivision: gridDivision,
            onSnapToggle: _toggleSnap,
            onGridDivisionChanged: (division) => setState(() => gridDivision = division),
            onQuantize: _quantizeClip,
            swingAmount: swingAmount,
            onSwingChanged: (v) => setState(() => swingAmount = v),
            onSwingApply: applySwing,
            // View section
            foldEnabled: foldViewEnabled,
            ghostNotesEnabled: ghostNotesEnabled,
            onFoldToggle: () => setState(() => foldViewEnabled = !foldViewEnabled),
            onGhostNotesToggle: () => setState(() => ghostNotesEnabled = !ghostNotesEnabled),
            // Scale section
            scaleRoot: scaleRoot,
            scaleType: scaleType,
            highlightEnabled: scaleHighlightEnabled,
            lockEnabled: scaleLockEnabled,
            chordsEnabled: chordPaletteVisible,
            onRootChanged: (root) => setState(() => scaleRoot = root),
            onTypeChanged: (type) => setState(() => scaleType = type),
            onHighlightToggle: () => setState(() => scaleHighlightEnabled = !scaleHighlightEnabled),
            onLockToggle: () => setState(() => scaleLockEnabled = !scaleLockEnabled),
            onChordsToggle: () => setState(() => chordPaletteVisible = !chordPaletteVisible),
            // Transform section
            stretchAmount: stretchAmount,
            humanizeAmount: humanizeAmount,
            onLegato: applyLegato,
            onStretchChanged: (v) => setState(() => stretchAmount = v),
            onStretchApply: applyStretch,
            onHumanizeChanged: (v) => setState(() => humanizeAmount = v),
            onHumanizeApply: applyHumanize,
            onReverse: reverseNotes,
            // Lane visibility toggles (Randomize/CC type are in lane headers)
            velocityLaneVisible: velocityLaneExpanded,
            onVelocityLaneToggle: _toggleVelocityLane,
            ccLaneVisible: ccLaneExpanded,
            onCCLaneToggle: () => setState(() => ccLaneExpanded = !ccLaneExpanded),
          ),
          // Main content area
          Expanded(
            child: Column(
              children: [
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
                            Container(
                              width: 80,
                              decoration: BoxDecoration(
                                color: context.colors.elevated,
                                border: Border(
                                  right: BorderSide(color: context.colors.elevated, width: 1),
                                ),
                              ),
                              child: Column(
                                children: List.generate(
                                  PianoRollStateMixin.maxMidiNote - PianoRollStateMixin.minMidiNote + 1,
                                  (index) {
                                    final midiNote = PianoRollStateMixin.maxMidiNote - index;
                                    return _buildPianoKey(midiNote);
                                  },
                                ),
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
                                        } else if (event.buttons == kPrimaryMouseButton) {
                                          final isAltPressed = HardwareKeyboard.instance.isAltPressed;
                                          if (isAltPressed) {
                                            final note = _findNoteAtPosition(event.localPosition);
                                            if (note != null) {
                                              deleteNote(note);
                                            }
                                          }
                                        }
                                      },
                                      onPointerMove: (event) {
                                        if (event.buttons == kPrimaryMouseButton) {
                                          final isAltPressed = HardwareKeyboard.instance.isAltPressed;
                                          if (isAltPressed) {
                                            if (!isErasing) {
                                              _startErasing(event.localPosition);
                                            } else {
                                              _eraseNotesAt(event.localPosition);
                                            }
                                          }
                                        }
                                      },
                                      onPointerUp: (event) {
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
                                        _stopAudition();
                                      },
                                      child: MouseRegion(
                                        cursor: currentCursor,
                                        onHover: _onHover,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.translucent,
                                          onTapDown: _onTapDown,
                                          onTapUp: (_) => _stopAudition(),
                                          onTapCancel: _stopAudition,
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
                                                    gridDivision: gridDivision,
                                                    maxMidiNote: PianoRollStateMixin.maxMidiNote,
                                                    minMidiNote: PianoRollStateMixin.minMidiNote,
                                                    totalBeats: totalBeats,
                                                    activeBeats: activeBeats,
                                                    loopEnabled: loopEnabled,
                                                    loopStart: loopStartBeats,
                                                    loopEnd: loopStartBeats + getLoopLength(),
                                                    beatsPerBar: beatsPerBar,
                                                    blackKeyBackground: context.colors.standard,
                                                    whiteKeyBackground: context.colors.elevated,
                                                    separatorLine: context.colors.elevated,
                                                    subdivisionGridLine: context.colors.surface,
                                                    beatGridLine: context.colors.hover,
                                                    barGridLine: context.colors.textMuted,
                                                    scaleHighlightEnabled: scaleHighlightEnabled,
                                                    scaleRootMidi: ScaleRoot.midiNoteFromName(scaleRoot),
                                                    scaleIntervals: scaleType.intervals,
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
                                                  ),
                                                ),
                                                _buildLoopEndMarker(activeBeats, canvasHeight),
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
                onPanStart: _onVelocityPanStart,
                onPanUpdate: _onVelocityPanUpdate,
                onPanEnd: _onVelocityPanEnd,
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

  /// Handle velocity lane pan start
  void _onVelocityPanStart(DragStartDetails details) {
    final note = _findNoteAtVelocityPosition(details.localPosition);
    if (note != null) {
      saveToHistory();
      velocityDragNoteId = note.id;
    }
  }

  /// Handle velocity lane pan update
  void _onVelocityPanUpdate(DragUpdateDetails details) {
    if (velocityDragNoteId == null) return;

    // Calculate new velocity based on Y position (inverted - top = high velocity)
    final newVelocity = ((1 - (details.localPosition.dy / PianoRollStateMixin.velocityLaneHeight)) * 127)
        .round()
        .clamp(1, 127);

    setState(() {
      currentClip = currentClip?.copyWith(
        notes: currentClip!.notes.map((n) {
          if (n.id == velocityDragNoteId) {
            return n.copyWith(velocity: newVelocity);
          }
          return n;
        }).toList(),
      );
    });
    notifyClipUpdated();
  }

  /// Handle velocity lane pan end
  void _onVelocityPanEnd(DragEndDetails details) {
    if (velocityDragNoteId != null) {
      commitToHistory('Change velocity');
      velocityDragNoteId = null;
    }
  }

  /// Find note at velocity lane position
  MidiNoteData? _findNoteAtVelocityPosition(Offset position) {
    final beat = _getBeatAtX(position.dx);

    for (final note in currentClip?.notes ?? <MidiNoteData>[]) {
      if (beat >= note.startTime && beat < note.endTime) {
        return note;
      }
    }
    return null;
  }

  /// Build the draggable loop end marker
  Widget _buildLoopEndMarker(double loopLength, double canvasHeight) {
    final markerX = loopLength * pixelsPerBeat;
    const handleWidth = 12.0;

    return Positioned(
      left: markerX - handleWidth / 2,
      top: 0,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) {
            isDraggingLoopEnd = true;
            loopDragStartX = details.globalPosition.dx;
            loopLengthAtDragStart = currentClip?.loopLength ?? loopLength;
          },
          onHorizontalDragUpdate: (details) {
            if (!isDraggingLoopEnd || currentClip == null) return;

            // Calculate delta from drag start position
            final deltaX = details.globalPosition.dx - loopDragStartX;
            final deltaBeats = deltaX / pixelsPerBeat;

            // Calculate new loop length from initial value + delta
            var newLoopLength = loopLengthAtDragStart + deltaBeats;

            // Snap to grid
            newLoopLength = snapToGrid(newLoopLength);

            // Minimum 1 bar (4 beats)
            newLoopLength = newLoopLength.clamp(4.0, 256.0);

            // Update clip with new loop length
            setState(() {
              currentClip = currentClip!.copyWith(loopLength: newLoopLength);
            });

            notifyClipUpdated();
          },
          onHorizontalDragEnd: (details) {
            isDraggingLoopEnd = false;
          },
          child: Container(
            width: handleWidth,
            height: canvasHeight,
            decoration: BoxDecoration(
              // Vertical line
              border: Border(
                left: BorderSide(
                  color: context.colors.warning.withValues(alpha: 0.8), // Orange line
                  width: 2,
                ),
              ),
            ),
            child: Center(
              child: Container(
                width: handleWidth,
                height: 40,
                decoration: BoxDecoration(
                  color: context.colors.warning, // Orange handle
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [
                    BoxShadow(
                      color: context.colors.darkest.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.drag_indicator,
                  size: 10,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

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

  /// Quantize all notes in the clip to the specified grid division
  void _quantizeClip(int gridDivision) {
    if (currentClip == null || widget.audioEngine == null) {
      return;
    }

    final clipId = currentClip!.clipId;

    // Call the Rust engine to quantize
    widget.audioEngine!.quantizeMidiClip(clipId, gridDivision);

    // Reload notes from clip to show updated positions
    loadClipFromEngine();
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

    return Container(
      height: pixelsPerNote,
      decoration: BoxDecoration(
        // Dark theme piano keys - dark grey for black keys, medium grey for white keys
        color: isBlackKey ? context.colors.standard : context.colors.elevated,
        border: Border(
          bottom: BorderSide(
            color: context.colors.surface, // Subtle border
            width: 0.5,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            noteName,
            style: TextStyle(
              color: isBlackKey ? context.colors.textMuted : context.colors.textPrimary,
              fontSize: isC ? 9 : 8, // C notes slightly larger
              fontWeight: isC ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  bool _isBlackKey(int midiNote) {
    final noteInOctave = midiNote % 12;
    return [1, 3, 6, 8, 10].contains(noteInOctave); // C#, D#, F#, G#, A#
  }

  String _getNoteNameForKey(int midiNote) {
    const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (midiNote ~/ 12) - 1;
    final noteName = noteNames[midiNote % 12];
    return '$noteName$octave';
  }

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
            onTap: _zoomOut,
            tooltip: 'Zoom out',
          ),
          const SizedBox(width: 4),
          // Zoom in button
          _buildZoomButton(
            context,
            icon: Icons.add,
            onTap: _zoomIn,
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
          onTap: _toggleAudition,
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

  /// Build bar number ruler with Ableton-style drag interaction
  /// Drag vertically: down = zoom in, up = zoom out (anchored to cursor)
  /// Drag horizontally: pan timeline (move left = scroll left, move right = scroll right)
  /// Click: place insert marker (spec v2.0)
  /// When loop enabled: drag loop markers to adjust loop region
  Widget _buildBarRuler(double totalBeats, double canvasWidth) {
    return GestureDetector(
      onTapUp: (details) {
        // Click ruler to place insert marker (spec v2.0)
        final scrollOffset = rulerScroll.hasClients ? rulerScroll.offset : 0.0;
        final xInContent = details.localPosition.dx + scrollOffset;
        final beats = xInContent / pixelsPerBeat;
        setState(() {
          insertMarkerBeats = beats.clamp(0.0, double.infinity);
        });
      },
      onPanStart: (details) {
        final scrollOffset = rulerScroll.hasClients ? rulerScroll.offset : 0.0;
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
            return;
          }

          // Check end marker
          if ((beatAtCursor - loopEnd).abs() < hitRadius) {
            _loopMarkerDrag = LoopMarkerDrag.end;
            loopDragStartBeat = loopEnd;
            return;
          }

          // Check middle region
          if (beatAtCursor > loopStartBeats && beatAtCursor < loopEnd) {
            _loopMarkerDrag = LoopMarkerDrag.middle;
            loopDragStartBeat = beatAtCursor;
            return;
          }
        }

        // Normal pan/zoom behavior
        _loopMarkerDrag = null;
        zoomDragStartY = details.globalPosition.dy;
        zoomStartPixelsPerBeat = pixelsPerBeat;
        zoomAnchorLocalX = details.localPosition.dx;
        zoomAnchorBeat = beatAtCursor;
      },
      onPanUpdate: (details) {
        // Handle loop marker dragging
        if (_loopMarkerDrag != null && loopEnabled) {
          final scrollOffset = rulerScroll.hasClients ? rulerScroll.offset : 0.0;
          final xInContent = details.localPosition.dx + scrollOffset;
          final beatAtCursor = xInContent / pixelsPerBeat;
          final snappedBeat = snapToGrid(beatAtCursor);

          switch (_loopMarkerDrag!) {
            case LoopMarkerDrag.start:
              // Move start marker, keep end fixed
              final loopEnd = loopStartBeats + getLoopLength();
              final newStart = snappedBeat.clamp(0.0, loopEnd - gridDivision);
              final newLength = loopEnd - newStart;
              setState(() {
                loopStartBeats = newStart;
                updateLoopLength(newLength);
              });
              break;

            case LoopMarkerDrag.end:
              // Move end marker, keep start fixed
              final newEnd = snappedBeat.clamp(loopStartBeats + gridDivision, double.infinity);
              final newLength = newEnd - loopStartBeats;
              setState(() {
                updateLoopLength(newLength);
              });
              // Auto-extend canvas if needed
              autoExtendCanvasIfNeeded(newEnd);
              break;

            case LoopMarkerDrag.middle:
              // Move entire loop region
              final delta = snappedBeat - snapToGrid(loopDragStartBeat);
              final newStart = (loopStartBeats + delta).clamp(0.0, double.infinity);
              // Only move if not trying to go negative
              if (newStart >= 0) {
                setState(() {
                  loopStartBeats = newStart;
                });
                loopDragStartBeat = snappedBeat;
                // Auto-extend canvas if needed
                autoExtendCanvasIfNeeded(newStart + getLoopLength());
              }
              break;
          }
          return;
        }

        // Normal pan/zoom behavior
        // Calculate drag delta (positive = dragged down = zoom in)
        final deltaY = details.globalPosition.dy - zoomDragStartY;

        // Sensitivity: ~100 pixels of drag = 2x zoom change
        // Positive deltaY (drag down) = zoom in, Negative (drag up) = zoom out
        final zoomFactor = 1.0 + (deltaY / 100.0);
        final minZoom = _calculateMinPixelsPerBeat();
        final maxZoom = _calculateMaxPixelsPerBeat();
        final newPixelsPerBeat = (zoomStartPixelsPerBeat * zoomFactor).clamp(minZoom, maxZoom);

        // Calculate new scroll position to keep anchor beat under cursor
        // anchorBeat * newPixelsPerBeat = newXInContent
        // newScrollOffset = newXInContent - localX
        final newXInContent = zoomAnchorBeat * newPixelsPerBeat;

        // Also apply horizontal panning: drag left = scroll left (same direction)
        // details.delta.dx is positive when dragging right, negative when dragging left
        // We want scroll to move in the same direction as mouse (drag left = view moves left)
        final panOffset = -details.delta.dx; // Invert so drag left = scroll left

        final targetScrollOffset = (newXInContent - zoomAnchorLocalX) + panOffset;

        // Update anchor position to account for pan (so zoom stays anchored correctly)
        zoomAnchorLocalX += details.delta.dx;

        setState(() {
          pixelsPerBeat = newPixelsPerBeat;
        });

        // Defer scroll adjustment to after the layout rebuild
        // This avoids issues with maxScrollExtent being outdated
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (horizontalScroll.hasClients) {
            final maxScroll = horizontalScroll.position.maxScrollExtent;
            horizontalScroll.jumpTo(targetScrollOffset.clamp(0.0, maxScroll));
          }
        });
      },
      onPanEnd: (details) {
        // Reset loop marker drag state
        _loopMarkerDrag = null;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.grab, // Visual hint for pan/zoom
        child: Container(
          height: 30,
          width: canvasWidth,
          decoration: BoxDecoration(
            color: context.colors.elevated, // Dark background
            border: Border(
              bottom: BorderSide(color: context.colors.elevated, width: 1),
            ),
          ),
          child: CustomPaint(
            size: Size(canvasWidth, 30),
            painter: BarRulerPainter(
              pixelsPerBeat: pixelsPerBeat,
              totalBeats: totalBeats,
              playheadPosition: 0.0, // TODO: Sync with actual playhead
              loopEnabled: loopEnabled,
              loopStart: loopStartBeats,
              loopEnd: loopStartBeats + getLoopLength(),
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
  /// Called when Alt/Cmd/Ctrl pressed/released for hold modifier support
  void _updateCursorForModifiers() {
    // Don't update cursor during active drag operations
    if (currentMode == InteractionMode.move || currentMode == InteractionMode.resize) {
      return;
    }

    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
    final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;

    setState(() {
      if (isAltPressed) {
        // Alt held = temporary erase mode
        tempModeOverride = ToolMode.eraser;
        currentCursor = SystemMouseCursors.forbidden;
      } else if (isCtrlOrCmd) {
        // Cmd/Ctrl held = context-sensitive (duplicate on note, slice on empty)
        // We set duplicate as the temp mode; slice handled in tap handler
        tempModeOverride = ToolMode.duplicate;
        currentCursor = SystemMouseCursors.copy;
      } else {
        // No modifier = clear temp override
        tempModeOverride = null;
        currentCursor = SystemMouseCursors.basic;
      }
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
    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
    final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final toolMode = effectiveToolMode;

    // Tool-mode-aware cursor logic
    if (hoveredNote != null) {
      // On a note
      if (isAltPressed || toolMode == ToolMode.eraser) {
        // Eraser mode - show delete cursor
        setState(() {
          currentCursor = SystemMouseCursors.forbidden;
        });
      } else if (toolMode == ToolMode.slice) {
        // Slice mode - show vertical split cursor
        setState(() {
          currentCursor = SystemMouseCursors.verticalText;
        });
      } else if (isCtrlOrCmd || toolMode == ToolMode.duplicate) {
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
      if (isAltPressed || toolMode == ToolMode.eraser) {
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
    final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final toolMode = effectiveToolMode;

    // ============================================
    // TOOL MODE BEHAVIOR
    // ============================================

    // Alt+click OR Erase tool = delete note
    if (isAltPressed || toolMode == ToolMode.eraser) {
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
    if (toolMode == ToolMode.duplicate || (isCtrlOrCmd && clickedNote != null)) {
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
        _startAudition(clickedNote.note, clickedNote.velocity);
      }
      return;
    }

    // Select tool = only select notes, don't create new ones
    if (toolMode == ToolMode.select) {
      if (clickedNote != null) {
        // Shift+click = toggle selection (add/remove from selection)
        if (isShiftPressed) {
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
        } else {
          // Regular click = select this note, deselect others
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
        _startAudition(clickedNote.note, clickedNote.velocity);
      } else {
        // Click on empty space = deselect all
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
    if (isCtrlOrCmd && clickedNote == null) {
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

    if (clickedNote != null) {
      // Shift+click on note = toggle selection (add/remove from selection)
      if (isShiftPressed) {
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
        notifyClipUpdated();
        return;
      }

      // Regular click on note = select it (deselect others) or toggle if already selected
      setState(() {
        currentClip = currentClip?.copyWith(
          notes: currentClip!.notes.map((n) {
            if (n.id == clickedNote.id) {
              // Toggle selection: if already selected, deselect; otherwise select
              return n.copyWith(isSelected: !n.isSelected);
            } else {
              // Deselect all other notes
              return n.copyWith(isSelected: false);
            }
          }).toList(),
        );
      });
      notifyClipUpdated();

      // Start sustained audition (will stop on mouse up)
      _startAudition(clickedNote.note, clickedNote.velocity);

      // Clear just-created tracking since we clicked on existing note
      justCreatedNoteId = null;
    } else {
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
      _startAudition(noteRow, 100);
    }
  }

  void _onPanStart(DragStartDetails details) {
    // Request focus to enable keyboard events (delete, undo, etc.)
    focusNode.requestFocus();

    dragStart = details.localPosition;
    final clickedNote = _findNoteAtPosition(details.localPosition);
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
    final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final toolMode = effectiveToolMode;

    // Skip normal pan handling if Alt is held OR eraser tool is active
    if (isAltPressed || toolMode == ToolMode.eraser) {
      return;
    }

    // Box selection: Shift+drag on empty OR Select tool drag on empty
    if ((isShiftPressed || toolMode == ToolMode.select) && clickedNote == null) {
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
              } else if (!isShiftPressed) {
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
      _startAudition(clickedNote.note, clickedNote.velocity);
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

      _startAudition(clickedNote.note, clickedNote.velocity);
      return;
    }

    // Slice tool: skip pan handling (slicing is done on tap)
    if (toolMode == ToolMode.slice) {
      return;
    }

    // ============================================
    // DRAW TOOL (default) behavior below
    // ============================================

    if (isCtrlOrCmd && clickedNote != null) {
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

      _startAudition(clickedNote.note, clickedNote.velocity);
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
      // Check if we're near the edge for resizing (FL Studio style)
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
        _startAudition(clickedNote.note, clickedNote.velocity);
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
        _changeAuditionPitch(newPitchForAudition!, velocityForAudition ?? 100);
      }

      notifyClipUpdated();
    } else if (currentMode == InteractionMode.resize && resizingNoteId != null) {
      // Resize note from left or right edge (FL Studio style)
      // Shift key bypasses grid snap for fine adjustment
      final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
      MidiNoteData? resizedNote;
      setState(() {
        currentClip = currentClip?.copyWith(
          notes: currentClip!.notes.map((n) {
            if (n.id == resizingNoteId) {
              final rawBeat = _getBeatAtX(details.localPosition.dx);
              final newBeat = isShiftPressed ? rawBeat : snapToGrid(rawBeat);

              if (resizingEdge == 'right') {
                // Right edge: change duration only
                final newDuration = (newBeat - n.startTime).clamp(gridDivision, 64.0);
                resizedNote = n.copyWith(duration: newDuration);
                return resizedNote!;
              } else if (resizingEdge == 'left') {
                // Left edge: change start time and duration
                final oldEndTime = n.endTime;
                final newStartTime = newBeat.clamp(0.0, oldEndTime - gridDivision);
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
    _stopAudition();

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
