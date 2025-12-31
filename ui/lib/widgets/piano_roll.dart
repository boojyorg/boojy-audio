import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../models/midi_note_data.dart';
import '../models/midi_cc_data.dart';
import '../models/scale_data.dart';
import '../models/chord_data.dart';
import '../audio_engine.dart';
import '../services/undo_redo_manager.dart';
import '../services/commands/clip_commands.dart';
import '../theme/theme_extension.dart';
import 'painters/painters.dart';
import 'piano_roll/piano_roll_sidebar.dart';
import 'piano_roll/piano_roll_controls_bar.dart';
import 'piano_roll/piano_roll_cc_lane.dart';
import 'piano_roll/chord_palette.dart';
import 'shared/mini_knob.dart';

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

/// Loop marker being dragged in ruler
enum _LoopMarkerDrag {
  start,  // Dragging start marker
  end,    // Dragging end marker
  middle, // Dragging the entire loop region
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

class _PianoRollState extends State<PianoRoll> {
  // Zoom levels
  double _pixelsPerBeat = 80.0; // Horizontal zoom
  double _pixelsPerNote = 16.0; // Vertical zoom (height of each piano key)

  // Scroll controllers
  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _rulerScroll = ScrollController(); // Separate controller for ruler
  final ScrollController _verticalScroll = ScrollController();
  bool _isSyncingScroll = false; // Prevent infinite sync loops

  // Grid settings
  double _gridDivision = 0.25; // 1/16th note (quarter / 4)
  bool _snapEnabled = true;

  // View range (88 piano keys: A0 = 21 to C8 = 108)
  static const int _minMidiNote = 0;
  static const int _maxMidiNote = 127;
  static const int _defaultViewEndNote = 84; // C6 (default scroll position)

  // Clip state
  MidiClipData? _currentClip;

  // UI state
  MidiNoteData? _previewNote;
  Offset? _dragStart;

  // Interaction mode
  InteractionMode _currentMode = InteractionMode.draw;

  // Selection state
  String? _resizingNoteId;
  String? _resizingEdge; // 'left' or 'right'

  // Cursor state
  MouseCursor _currentCursor = SystemMouseCursors.basic; // Default cursor for empty space

  // Temporary mode override via modifier keys
  ToolMode? _tempModeOverride;

  /// Get effective tool mode (temp override or widget prop)
  ToolMode get _effectiveToolMode => _tempModeOverride ?? widget.toolMode;

  /// True if slice mode is active
  bool get _isSliceModeActive => _effectiveToolMode == ToolMode.slice;

  // Paint mode state (drag to create multiple notes)
  bool _isPainting = false;
  double? _paintStartBeat;
  int? _paintNote;
  double _lastPaintedBeat = 0.0;

  // Track note just created by click (for immediate drag-to-move)
  String? _justCreatedNoteId;

  // Track note currently being moved (without selection highlight)
  String? _movingNoteId;

  // Eraser mode state (Ctrl/Cmd+drag to delete multiple notes)
  bool _isErasing = false;
  Set<String> _erasedNoteIds = {};
  Offset? _rightClickStartPosition; // Track right-click start for context menu
  MidiNoteData? _rightClickNote; // Note under right-click for context menu on release

  // Duplicate mode state (Cmd/Ctrl+drag to duplicate notes)
  bool _isDuplicating = false;


  // Velocity lane state
  bool _velocityLaneExpanded = false;
  static const double _velocityLaneHeight = 80.0;
  String? _velocityDragNoteId; // Note being velocity-edited
  double _velocityRandomizeAmount = 0.0; // 0-100% randomization

  // CC automation lane state
  bool _ccLaneExpanded = false;
  static const double _ccLaneHeight = 80.0;
  MidiCCLane _ccLane = MidiCCLane(ccType: MidiCCType.modWheel);

  // Multi-select state
  bool _isSelecting = false;
  Offset? _selectionStart;
  Offset? _selectionEnd;

  // Snapshot for undo - stores state before an operation
  MidiClipData? _snapshotBeforeAction;

  // Clipboard for copy/paste
  List<MidiNoteData> _clipboard = [];

  // Loop boundary dragging state
  bool _isDraggingLoopEnd = false;
  double _loopDragStartX = 0;
  double _loopLengthAtDragStart = 0;

  // Zoom drag state (Ableton-style ruler zoom)
  double _zoomDragStartY = 0;
  double _zoomStartPixelsPerBeat = 0;
  double _zoomAnchorBeat = 0; // Beat position to keep under cursor during zoom
  double _zoomAnchorLocalX = 0; // Local X position of cursor at drag start

  // Remember last note duration (default = 1 beat = quarter note)
  double _lastNoteDuration = 1.0;

  // Note audition (preview) when creating/selecting notes
  bool _auditionEnabled = true;

  // Track currently held note for sustained audition (FL Studio style)
  int? _currentlyHeldNote;

  // Store original note positions at drag start for proper delta calculation
  Map<String, MidiNoteData> _dragStartNotes = {};

  // Insert marker position (in beats, separate from playhead)
  double? _insertMarkerBeats;

  // Loop settings
  bool _loopEnabled = true; // Loop ON by default
  double _loopStartBeats = 0.0;

  // Loop marker drag state
  _LoopMarkerDrag? _loopMarkerDrag;
  double _loopDragStartBeat = 0.0; // Beat position when drag started

  // Transform tool values
  double _stretchAmount = 1.0;
  double _humanizeAmount = 0.0;
  double _swingAmount = 0.0;

  // Scale settings
  String _scaleRoot = 'C';
  ScaleType _scaleType = ScaleType.major;
  bool _scaleHighlightEnabled = false;
  bool _scaleLockEnabled = false;
  bool _foldViewEnabled = false;
  bool _ghostNotesEnabled = false;

  // Time signature
  int _beatsPerBar = 4;
  int _beatUnit = 4;

  // View width for dynamic zoom limits (captured from LayoutBuilder)
  double _viewWidth = 800.0;

  /// Get current scale for calculations
  Scale get _currentScale => Scale(root: _scaleRoot, type: _scaleType);

  // Chord palette state
  bool _chordPaletteVisible = false;
  ChordConfiguration _chordConfig = const ChordConfiguration(
    root: ChordRoot.c,
    type: ChordType.major,
  );
  bool _chordPreviewEnabled = true;

  // Focus node for keyboard events
  final FocusNode _focusNode = FocusNode();

  // Global undo/redo manager
  final UndoRedoManager _undoRedoManager = UndoRedoManager();

  @override
  void initState() {
    super.initState();
    _currentClip = widget.clipData;

    // Listen for undo/redo changes to update our state
    _undoRedoManager.addListener(_onUndoRedoChanged);

    // Listen for hardware keyboard events (for modifier key cursor updates)
    HardwareKeyboard.instance.addHandler(_onHardwareKey);

    // Sync horizontal scroll between ruler and grid
    _horizontalScroll.addListener(_syncRulerFromGrid);
    _rulerScroll.addListener(_syncGridFromRuler);

    // Scroll to default view (middle of piano)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToDefaultView();
    });
  }

  void _syncRulerFromGrid() {
    if (_isSyncingScroll) return;
    if (!_rulerScroll.hasClients || !_horizontalScroll.hasClients) return;
    _isSyncingScroll = true;
    _rulerScroll.jumpTo(_horizontalScroll.offset.clamp(0.0, _rulerScroll.position.maxScrollExtent));
    _isSyncingScroll = false;
  }

  void _syncGridFromRuler() {
    if (_isSyncingScroll) return;
    if (!_rulerScroll.hasClients || !_horizontalScroll.hasClients) return;
    _isSyncingScroll = true;
    _horizontalScroll.jumpTo(_rulerScroll.offset.clamp(0.0, _horizontalScroll.position.maxScrollExtent));
    _isSyncingScroll = false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _undoRedoManager.removeListener(_onUndoRedoChanged);
    _horizontalScroll.removeListener(_syncRulerFromGrid);
    _rulerScroll.removeListener(_syncGridFromRuler);
    _focusNode.dispose();
    _horizontalScroll.dispose();
    _rulerScroll.dispose();
    _verticalScroll.dispose();
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
        _currentClip = widget.clipData;
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
    if (!_verticalScroll.hasClients) return;

    // Scroll to show C2-C6 range by default
    final scrollOffset = _calculateNoteY(_defaultViewEndNote);
    _verticalScroll.jumpTo(scrollOffset);
  }

  /// Notify parent widget that clip has been updated
  void _notifyClipUpdated() {
    if (widget.onClipUpdated != null && _currentClip != null) {
      widget.onClipUpdated!(_currentClip!);
    }

    // Trigger rebuild to recalculate totalBeats and update grey overlay
    setState(() {});
  }

  /// Start sustained audition - note plays until _stopAudition is called (FL Studio style)
  void _startAudition(int midiNote, int velocity) {
    if (!_auditionEnabled) return;

    // Stop any currently held note first
    _stopAudition();

    final trackId = _currentClip?.trackId;
    if (trackId != null && widget.audioEngine != null) {
      widget.audioEngine!.sendTrackMidiNoteOn(trackId, midiNote, velocity);
      _currentlyHeldNote = midiNote;
    }
  }

  /// Stop the currently held audition note
  void _stopAudition() {
    if (_currentlyHeldNote != null) {
      final trackId = _currentClip?.trackId;
      if (trackId != null && widget.audioEngine != null) {
        widget.audioEngine!.sendTrackMidiNoteOff(trackId, _currentlyHeldNote!, 64);
      }
      _currentlyHeldNote = null;
    }
  }

  /// Change the audition pitch while holding (for dragging notes up/down)
  void _changeAuditionPitch(int newMidiNote, int velocity) {
    if (!_auditionEnabled) return;
    if (newMidiNote == _currentlyHeldNote) return; // Same note, no change needed

    final trackId = _currentClip?.trackId;
    if (trackId != null && widget.audioEngine != null) {
      // Stop old note
      if (_currentlyHeldNote != null) {
        widget.audioEngine!.sendTrackMidiNoteOff(trackId, _currentlyHeldNote!, 64);
      }
      // Start new note
      widget.audioEngine!.sendTrackMidiNoteOn(trackId, newMidiNote, velocity);
      _currentlyHeldNote = newMidiNote;
    }
  }

  /// Toggle note audition on/off
  void _toggleAudition() {
    setState(() {
      _auditionEnabled = !_auditionEnabled;
    });
  }

  /// Preview/audition a chord (play all notes simultaneously)
  void _previewChord(List<int> midiNotes) {
    if (!_auditionEnabled) return;
    final trackId = _currentClip?.trackId;
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
    if (_currentClip == null) return;

    // Get the chord's MIDI notes based on current configuration
    // Transpose the chord so its lowest note is at the clicked position
    final chordNotes = _chordConfig.midiNotes;
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
          duration: _lastNoteDuration,
          isSelected: true,
        ));
      }
    }

    if (newNotes.isEmpty) return;

    setState(() {
      // Deselect all existing notes
      _currentClip = _currentClip?.copyWith(
        notes: _currentClip!.notes.map((n) => n.copyWith(isSelected: false)).toList(),
      );
      // Add all chord notes
      for (final note in newNotes) {
        _currentClip = _currentClip?.addNote(note);
        _autoExtendLoopIfNeeded(note);
      }
    });

    _commitToHistory('Add chord');
    _notifyClipUpdated();

    // Preview the chord
    _previewChord(newNotes.map((n) => n.note).toList());
  }

  /// Toggle velocity lane on/off
  void _toggleVelocityLane() {
    setState(() {
      _velocityLaneExpanded = !_velocityLaneExpanded;
    });
  }

  /// Slice a note at the given beat position
  void _sliceNoteAt(MidiNoteData note, double beatPosition) {
    // Calculate split point (snap to grid if enabled)
    final splitBeat = _snapEnabled ? _snapToGrid(beatPosition) : beatPosition;

    // Validate split is within note bounds
    if (splitBeat <= note.startTime || splitBeat >= note.endTime) return;

    _saveToHistory();

    // Create two notes from one
    final leftNote = note.copyWith(
      duration: splitBeat - note.startTime,
      id: '${DateTime.now().microsecondsSinceEpoch}_left',
    );
    final rightNote = note.copyWith(
      startTime: splitBeat,
      duration: note.endTime - splitBeat,
      id: '${DateTime.now().microsecondsSinceEpoch}_right',
    );

    // Replace original with two new notes
    setState(() {
      _currentClip = _currentClip?.copyWith(
        notes: _currentClip!.notes
            .where((n) => n.id != note.id)
            .followedBy([leftNote, rightNote])
            .toList(),
      );
    });

    _commitToHistory('Slice note');
    _notifyClipUpdated();
  }

  /// Save current state snapshot before making changes
  /// Call this BEFORE modifying _currentClip
  void _saveToHistory() {
    if (_currentClip == null) return;
    _snapshotBeforeAction = _currentClip!.copyWith(
      notes: List.from(_currentClip!.notes),
    );
  }

  /// Commit the change to global undo history with a description
  /// Call this AFTER modifying _currentClip
  void _commitToHistory(String actionDescription) {
    if (_snapshotBeforeAction == null || _currentClip == null) return;

    final command = MidiClipSnapshotCommand(
      beforeState: _snapshotBeforeAction!,
      afterState: _currentClip!.copyWith(
        notes: List.from(_currentClip!.notes),
      ),
      actionDescription: actionDescription,
      onApplyState: _applyClipState,
    );

    // Execute without re-applying (we already applied the change)
    _undoRedoManager.execute(command);
    _snapshotBeforeAction = null;
  }

  /// Callback for undo/redo to apply clip state
  void _applyClipState(MidiClipData clipData) {
    if (!mounted) return;
    setState(() {
      _currentClip = clipData;
    });
    _notifyClipUpdated();
  }

  /// Undo last action - delegates to global manager
  Future<void> _undo() async {
    await _undoRedoManager.undo();
  }

  /// Redo last undone action - delegates to global manager
  Future<void> _redo() async {
    await _undoRedoManager.redo();
  }

  double _calculateNoteY(int midiNote) {
    // Higher notes = lower Y coordinate (inverted)
    return (_maxMidiNote - midiNote) * _pixelsPerNote;
  }

  double _calculateBeatX(double beat) {
    return beat * _pixelsPerBeat;
  }

  int _getNoteAtY(double y) {
    final rawNote = _maxMidiNote - (y / _pixelsPerNote).floor();
    // Apply scale lock if enabled
    if (_scaleLockEnabled) {
      return _snapNoteToScale(rawNote);
    }
    return rawNote;
  }

  /// Snap a MIDI note to the nearest note in the current scale
  int _snapNoteToScale(int midiNote) {
    if (_currentScale.containsNote(midiNote)) return midiNote;

    // Find nearest note in scale
    int below = midiNote;
    int above = midiNote;

    while (!_currentScale.containsNote(below) && below >= 0) {
      below--;
    }
    while (!_currentScale.containsNote(above) && above <= 127) {
      above++;
    }

    // Return the closest one
    if (below < 0) return above;
    if (above > 127) return below;

    return (midiNote - below <= above - midiNote) ? below : above;
  }

  double _getBeatAtX(double x) {
    return x / _pixelsPerBeat;
  }

  double _snapToGrid(double beat) {
    if (!_snapEnabled) return beat;
    return (beat / _gridDivision).floor() * _gridDivision;
  }

  /// Calculate max pixelsPerBeat (zoom in limit)
  /// 1 sixteenth note (0.25 beats) should fill the view width
  double _calculateMaxPixelsPerBeat() {
    // 1 sixteenth = 0.25 beats should fill viewWidth
    // pixelsPerBeat = viewWidth / 0.25
    return _viewWidth / 0.25;
  }

  /// Calculate min pixelsPerBeat (zoom out limit)
  /// Clip length + 4 bars should fit in view
  double _calculateMinPixelsPerBeat() {
    final clipLength = _getLoopLength();
    final totalBeatsToShow = clipLength + 16.0; // clip + 4 bars (16 beats)
    // pixelsPerBeat = viewWidth / totalBeatsToShow
    return _viewWidth / totalBeatsToShow;
  }

  void _zoomIn() {
    setState(() {
      // 50% zoom in per click (1.5x multiplier)
      final maxZoom = _calculateMaxPixelsPerBeat();
      final minZoom = _calculateMinPixelsPerBeat();
      _pixelsPerBeat = (_pixelsPerBeat * 1.5).clamp(minZoom, maxZoom);
    });
  }

  void _zoomOut() {
    setState(() {
      // 50% zoom out per click (divide by 1.5)
      final maxZoom = _calculateMaxPixelsPerBeat();
      final minZoom = _calculateMinPixelsPerBeat();
      _pixelsPerBeat = (_pixelsPerBeat / 1.5).clamp(minZoom, maxZoom);
    });
  }

  void _toggleSnap() {
    setState(() {
      _snapEnabled = !_snapEnabled;
    });
  }

  /// Get the loop length (active region in piano roll)
  /// This is the boundary shown as the loop end marker
  double _getLoopLength() {
    return _currentClip?.loopLength ?? 4.0; // Default 1 bar
  }

  /// Calculate total visible beats (extends beyond loop for scrolling)
  /// Shows at least 1 bar beyond the loop end or furthest note
  double _calculateTotalBeats() {
    final loopLength = _getLoopLength();

    if (_currentClip == null || _currentClip!.notes.isEmpty) {
      // Show loop length + 1 bar for scrolling room
      return loopLength + 4.0;
    }

    // Find the furthest note end time
    final furthestBeat = _currentClip!.notes
        .map((note) => note.startTime + note.duration)
        .reduce((a, b) => a > b ? a : b);

    // Total is max of loop length or furthest note, plus 1 bar for room
    final maxBeat = furthestBeat > loopLength ? furthestBeat : loopLength;

    // Round up to next bar boundary and add 1 bar
    final requiredBars = (maxBeat / 4).ceil();
    return (requiredBars + 1) * 4.0;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _currentCursor,
      // onHover is handled by the inner MouseRegion in the grid area
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          // Don't intercept keys when a TextField has focus (e.g., loop time inputs)
          final primaryFocus = FocusManager.instance.primaryFocus;
          if (primaryFocus != null && primaryFocus != _focusNode) {
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
            if (_chordPaletteVisible)
              Positioned(
                right: 16,
                top: 100,
                child: ChordPalette(
                  configuration: _chordConfig,
                  previewEnabled: _chordPreviewEnabled,
                  onConfigurationChanged: (config) {
                    setState(() => _chordConfig = config);
                  },
                  onPreview: _previewChord,
                  onPreviewToggle: (enabled) {
                    setState(() => _chordPreviewEnabled = enabled);
                  },
                  onClose: () {
                    setState(() => _chordPaletteVisible = false);
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
    final activeBeats = _getLoopLength();
    // Total beats extends beyond loop for scrolling
    final totalBeats = _calculateTotalBeats();

    final canvasWidth = totalBeats * _pixelsPerBeat;
    final canvasHeight = (_maxMidiNote - _minMidiNote + 1) * _pixelsPerNote;

    return Expanded(
      child: Column(
        children: [
          // Horizontal controls bar (replaces left sidebar)
          PianoRollControlsBar(
            // Clip section
            loopEnabled: _loopEnabled,
            loopStartBeats: _loopStartBeats,
            loopLengthBeats: _getLoopLength(),
            beatsPerBar: _beatsPerBar,
            beatUnit: _beatUnit,
            onLoopToggle: () => setState(() => _loopEnabled = !_loopEnabled),
            onLoopStartChanged: (beats) => setState(() => _loopStartBeats = beats),
            onLoopLengthChanged: (beats) {
              if (_currentClip == null) return;
              final newLength = beats.clamp(4.0, 256.0);
              setState(() {
                _currentClip = _currentClip!.copyWith(loopLength: newLength);
              });
              _notifyClipUpdated();
            },
            onBeatsPerBarChanged: (value) => setState(() => _beatsPerBar = value),
            onBeatUnitChanged: (value) => setState(() => _beatUnit = value),
            // Grid section
            snapEnabled: _snapEnabled,
            gridDivision: _gridDivision,
            onSnapToggle: _toggleSnap,
            onGridDivisionChanged: (division) => setState(() => _gridDivision = division),
            onQuantize: _quantizeClip,
            swingAmount: _swingAmount,
            onSwingChanged: (v) => setState(() => _swingAmount = v),
            onSwingApply: _applySwing,
            // View section
            foldEnabled: _foldViewEnabled,
            ghostNotesEnabled: _ghostNotesEnabled,
            onFoldToggle: () => setState(() => _foldViewEnabled = !_foldViewEnabled),
            onGhostNotesToggle: () => setState(() => _ghostNotesEnabled = !_ghostNotesEnabled),
            // Scale section
            scaleRoot: _scaleRoot,
            scaleType: _scaleType,
            highlightEnabled: _scaleHighlightEnabled,
            lockEnabled: _scaleLockEnabled,
            chordsEnabled: _chordPaletteVisible,
            onRootChanged: (root) => setState(() => _scaleRoot = root),
            onTypeChanged: (type) => setState(() => _scaleType = type),
            onHighlightToggle: () => setState(() => _scaleHighlightEnabled = !_scaleHighlightEnabled),
            onLockToggle: () => setState(() => _scaleLockEnabled = !_scaleLockEnabled),
            onChordsToggle: () => setState(() => _chordPaletteVisible = !_chordPaletteVisible),
            // Transform section
            stretchAmount: _stretchAmount,
            humanizeAmount: _humanizeAmount,
            onLegato: _applyLegato,
            onStretchChanged: (v) => setState(() => _stretchAmount = v),
            onStretchApply: _applyStretch,
            onHumanizeChanged: (v) => setState(() => _humanizeAmount = v),
            onHumanizeApply: _applyHumanize,
            onReverse: _reverseNotes,
            // Lane visibility toggles (Randomize/CC type are in lane headers)
            velocityLaneVisible: _velocityLaneExpanded,
            onVelocityLaneToggle: _toggleVelocityLane,
            ccLaneVisible: _ccLaneExpanded,
            onCCLaneToggle: () => setState(() => _ccLaneExpanded = !_ccLaneExpanded),
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
                    // Bar ruler (scrollable) - uses _rulerScroll synced with _horizontalScroll
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _rulerScroll,
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
                    controller: _verticalScroll,
                    child: SingleChildScrollView(
                      controller: _verticalScroll,
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
                                  _maxMidiNote - _minMidiNote + 1,
                                  (index) {
                                    final midiNote = _maxMidiNote - index;
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
                                    if (_viewWidth != constraints.maxWidth && constraints.maxWidth > 0) {
                                      setState(() {
                                        _viewWidth = constraints.maxWidth;
                                      });
                                    }
                                  });
                                  return SingleChildScrollView(
                                    controller: _horizontalScroll,
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      width: canvasWidth,
                                      height: canvasHeight,
                                      // Listener captures right-click for context menu and Ctrl/Cmd for eraser/delete
                                      child: Listener(
                                      onPointerDown: (event) {
                                        if (event.buttons == kSecondaryMouseButton) {
                                          _rightClickStartPosition = event.localPosition;
                                          _rightClickNote = _findNoteAtPosition(event.localPosition);
                                        } else if (event.buttons == kPrimaryMouseButton) {
                                          final isAltPressed = HardwareKeyboard.instance.isAltPressed;
                                          if (isAltPressed) {
                                            final note = _findNoteAtPosition(event.localPosition);
                                            if (note != null) {
                                              _deleteNote(note);
                                            }
                                          }
                                        }
                                      },
                                      onPointerMove: (event) {
                                        if (event.buttons == kPrimaryMouseButton) {
                                          final isAltPressed = HardwareKeyboard.instance.isAltPressed;
                                          if (isAltPressed) {
                                            if (!_isErasing) {
                                              _startErasing(event.localPosition);
                                            } else {
                                              _eraseNotesAt(event.localPosition);
                                            }
                                          }
                                        }
                                      },
                                      onPointerUp: (event) {
                                        if (_rightClickNote != null && _rightClickStartPosition != null) {
                                          final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
                                          if (renderBox != null) {
                                            final globalPosition = renderBox.localToGlobal(_rightClickStartPosition!);
                                            _showNoteContextMenu(globalPosition, _rightClickNote!);
                                          }
                                        }
                                        _rightClickStartPosition = null;
                                        _rightClickNote = null;
                                        if (_isErasing) {
                                          _stopErasing();
                                        }
                                        _stopAudition();
                                      },
                                      child: MouseRegion(
                                        cursor: _currentCursor,
                                        onHover: _onHover,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.translucent,
                                          onTapDown: _onTapDown,
                                          onTapUp: (_) => _stopAudition(),
                                          onTapCancel: _stopAudition,
                                          onPanStart: _onPanStart,
                                          onPanUpdate: _onPanUpdate,
                                          onPanEnd: _onPanEnd,
                                          child: Container(
                                            color: Colors.transparent,
                                            child: Stack(
                                              children: [
                                                CustomPaint(
                                                  size: Size(canvasWidth, canvasHeight),
                                                  painter: GridPainter(
                                                    pixelsPerBeat: _pixelsPerBeat,
                                                    pixelsPerNote: _pixelsPerNote,
                                                    gridDivision: _gridDivision,
                                                    maxMidiNote: _maxMidiNote,
                                                    minMidiNote: _minMidiNote,
                                                    totalBeats: totalBeats,
                                                    activeBeats: activeBeats,
                                                    loopEnabled: _loopEnabled,
                                                    loopStart: _loopStartBeats,
                                                    loopEnd: _loopStartBeats + _getLoopLength(),
                                                    beatsPerBar: _beatsPerBar,
                                                    blackKeyBackground: context.colors.standard,
                                                    whiteKeyBackground: context.colors.elevated,
                                                    separatorLine: context.colors.elevated,
                                                    subdivisionGridLine: context.colors.surface,
                                                    beatGridLine: context.colors.hover,
                                                    barGridLine: context.colors.textMuted,
                                                    scaleHighlightEnabled: _scaleHighlightEnabled,
                                                    scaleRootMidi: ScaleRoot.midiNoteFromName(_scaleRoot),
                                                    scaleIntervals: _scaleType.intervals,
                                                  ),
                                                ),
                                                CustomPaint(
                                                  size: Size(canvasWidth, canvasHeight),
                                                  painter: NotePainter(
                                                    notes: _currentClip?.notes ?? [],
                                                    previewNote: _previewNote,
                                                    pixelsPerBeat: _pixelsPerBeat,
                                                    pixelsPerNote: _pixelsPerNote,
                                                    maxMidiNote: _maxMidiNote,
                                                    selectionStart: _selectionStart,
                                                    selectionEnd: _selectionEnd,
                                                    ghostNotes: widget.ghostNotes,
                                                    showGhostNotes: _ghostNotesEnabled,
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
                if (_velocityLaneExpanded)
                  _buildVelocityLane(totalBeats, canvasWidth),
                // CC automation lane
                if (_ccLaneExpanded)
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
      lane: _ccLane,
      pixelsPerBeat: _pixelsPerBeat,
      totalBeats: totalBeats,
      laneHeight: _ccLaneHeight,
      horizontalScrollController: _horizontalScroll,
      onCCTypeChanged: (type) {
        setState(() {
          _ccLane = _ccLane.copyWith(ccType: type, points: []);
        });
      },
      onPointAdded: (point) {
        _saveToHistory();
        setState(() {
          _ccLane = _ccLane.addPoint(point);
        });
        _commitToHistory('Add CC point');
      },
      onPointUpdated: (pointId, newPoint) {
        setState(() {
          _ccLane = _ccLane.updatePoint(pointId, newPoint);
        });
      },
      onPointDeleted: (pointId) {
        _saveToHistory();
        setState(() {
          _ccLane = _ccLane.removePoint(pointId);
        });
        _commitToHistory('Delete CC point');
      },
      onDrawValue: (time, value) {
        // Add a point at this position (for drawing mode)
        final newPoint = MidiCCPoint(time: time, value: value);
        setState(() {
          _ccLane = _ccLane.addPoint(newPoint);
        });
      },
      onClose: () {
        setState(() {
          _ccLaneExpanded = false;
        });
      },
    );
  }

  /// Build the velocity editing lane
  Widget _buildVelocityLane(double totalBeats, double canvasWidth) {
    return Container(
      height: _velocityLaneHeight,
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
            height: _velocityLaneHeight,
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
              controller: _horizontalScroll,
              scrollDirection: Axis.horizontal,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: _onVelocityPanStart,
                onPanUpdate: _onVelocityPanUpdate,
                onPanEnd: _onVelocityPanEnd,
                child: CustomPaint(
                  size: Size(canvasWidth, _velocityLaneHeight),
                  painter: VelocityLanePainter(
                    notes: _currentClip?.notes ?? [],
                    pixelsPerBeat: _pixelsPerBeat,
                    laneHeight: _velocityLaneHeight,
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
      _saveToHistory();
      _velocityDragNoteId = note.id;
    }
  }

  /// Handle velocity lane pan update
  void _onVelocityPanUpdate(DragUpdateDetails details) {
    if (_velocityDragNoteId == null) return;

    // Calculate new velocity based on Y position (inverted - top = high velocity)
    final newVelocity = ((1 - (details.localPosition.dy / _velocityLaneHeight)) * 127)
        .round()
        .clamp(1, 127);

    setState(() {
      _currentClip = _currentClip?.copyWith(
        notes: _currentClip!.notes.map((n) {
          if (n.id == _velocityDragNoteId) {
            return n.copyWith(velocity: newVelocity);
          }
          return n;
        }).toList(),
      );
    });
    _notifyClipUpdated();
  }

  /// Handle velocity lane pan end
  void _onVelocityPanEnd(DragEndDetails details) {
    if (_velocityDragNoteId != null) {
      _commitToHistory('Change velocity');
      _velocityDragNoteId = null;
    }
  }

  /// Find note at velocity lane position
  MidiNoteData? _findNoteAtVelocityPosition(Offset position) {
    final beat = _getBeatAtX(position.dx);

    for (final note in _currentClip?.notes ?? []) {
      if (beat >= note.startTime && beat < note.endTime) {
        return note;
      }
    }
    return null;
  }

  /// Build the draggable loop end marker
  Widget _buildLoopEndMarker(double loopLength, double canvasHeight) {
    final markerX = loopLength * _pixelsPerBeat;
    const handleWidth = 12.0;

    return Positioned(
      left: markerX - handleWidth / 2,
      top: 0,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) {
            _isDraggingLoopEnd = true;
            _loopDragStartX = details.globalPosition.dx;
            _loopLengthAtDragStart = _currentClip?.loopLength ?? loopLength;
          },
          onHorizontalDragUpdate: (details) {
            if (!_isDraggingLoopEnd || _currentClip == null) return;

            // Calculate delta from drag start position
            final deltaX = details.globalPosition.dx - _loopDragStartX;
            final deltaBeats = deltaX / _pixelsPerBeat;

            // Calculate new loop length from initial value + delta
            var newLoopLength = _loopLengthAtDragStart + deltaBeats;

            // Snap to grid
            newLoopLength = _snapToGrid(newLoopLength);

            // Minimum 1 bar (4 beats)
            newLoopLength = newLoopLength.clamp(4.0, 256.0);

            // Update clip with new loop length
            setState(() {
              _currentClip = _currentClip!.copyWith(loopLength: newLoopLength);
            });

            _notifyClipUpdated();
          },
          onHorizontalDragEnd: (details) {
            _isDraggingLoopEnd = false;
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
    if (_insertMarkerBeats == null) return const SizedBox.shrink();

    final markerX = _insertMarkerBeats! * _pixelsPerBeat;

    return Positioned(
      left: markerX - 1, // Center the 2px line
      top: 0,
      child: IgnorePointer(
        child: SizedBox(
          width: 2,
          height: canvasHeight,
          child: CustomPaint(
            painter: _DashedLinePainter(
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
    if (_currentClip == null || widget.audioEngine == null) {
      return;
    }

    final clipId = _currentClip!.clipId;

    // Call the Rust engine to quantize
    widget.audioEngine!.quantizeMidiClip(clipId, gridDivision);

    // Reload notes from clip to show updated positions
    _loadClipFromEngine();
  }

  /// Reload clip notes from engine after quantization
  void _loadClipFromEngine() {
    if (_currentClip == null) return;

    // Notify parent to refresh clip data from engine
    widget.onClipUpdated?.call(_currentClip!);
    setState(() {});
  }

  /// Apply swing to selected notes (shifts off-beat notes)
  void _applySwing() {
    if (_currentClip == null) return;

    final selectedNotes = _currentClip!.notes.where((n) => n.isSelected).toList();
    if (selectedNotes.isEmpty) return;

    _saveToHistory();

    // Swing affects notes on off-beats (8th notes: 0.5, 1.5, 2.5, etc.)
    // At 50% swing = triplet feel, 100% = hard swing (2:1 ratio)
    // Swing amount 0-1 maps to delay 0 to 0.33 beats for off-beat notes
    final swingDelay = _swingAmount * 0.33;

    setState(() {
      _currentClip = _currentClip!.copyWith(
        notes: _currentClip!.notes.map((note) {
          if (!note.isSelected) return note;

          // Check if note is on an off-beat (odd 8th note positions)
          final eighthNotePosition = (note.startTime / 0.5).round();
          final isOffBeat = eighthNotePosition % 2 == 1;

          if (isOffBeat) {
            // Delay this note by swing amount
            final newStart = note.startTime + swingDelay;
            return note.copyWith(startTime: newStart);
          }
          return note;
        }).toList(),
      );
    });

    _commitToHistory('Apply swing');
    _notifyClipUpdated();
  }

  /// Apply stretch to selected notes (time scaling)
  void _applyStretch() {
    if (_currentClip == null) return;

    final selectedNotes = _currentClip!.notes.where((n) => n.isSelected).toList();
    if (selectedNotes.isEmpty) return;

    _saveToHistory();

    // Find selection start point as anchor
    final selectionStart = selectedNotes.map((n) => n.startTime).reduce((a, b) => a < b ? a : b);

    setState(() {
      _currentClip = _currentClip!.copyWith(
        notes: _currentClip!.notes.map((note) {
          if (!note.isSelected) return note;

          // Scale timing relative to selection start
          final relativeStart = note.startTime - selectionStart;
          final newStart = selectionStart + (relativeStart * _stretchAmount);
          final newDuration = note.duration * _stretchAmount;

          return note.copyWith(
            startTime: newStart,
            duration: newDuration,
          );
        }).toList(),
      );
    });

    _commitToHistory('Stretch notes');
    _notifyClipUpdated();
  }

  /// Apply humanize to selected notes (random timing variation)
  void _applyHumanize() {
    if (_currentClip == null) return;

    final selectedNotes = _currentClip!.notes.where((n) => n.isSelected).toList();
    if (selectedNotes.isEmpty) return;

    _saveToHistory();

    // Max timing variation: ±50ms at 100% humanize
    // Convert to beats (assuming 120 BPM, 1 beat = 500ms)
    final maxVariationBeats = 0.1 * _humanizeAmount; // ±0.1 beats at 100%
    final random = Random();

    setState(() {
      _currentClip = _currentClip!.copyWith(
        notes: _currentClip!.notes.map((note) {
          if (!note.isSelected) return note;

          // Random offset between -maxVariation and +maxVariation
          final offset = (random.nextDouble() * 2 - 1) * maxVariationBeats;
          final newStart = (note.startTime + offset).clamp(0.0, double.infinity);

          return note.copyWith(startTime: newStart);
        }).toList(),
      );
    });

    _commitToHistory('Humanize notes');
    _notifyClipUpdated();
  }

  /// Build the Randomize button with dropdown for velocity lane header
  Widget _buildVelocityRandomizeButton(BuildContext context) {
    final colors = context.colors;
    final displayValue = '${(_velocityRandomizeAmount * 100).round()}%';

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
                        value: _velocityRandomizeAmount,
                        min: 0.0,
                        max: 1.0,
                        size: 48,
                        valueFormatter: (v) => '${(v * 100).round()}%',
                        arcColor: this.context.colors.accent,
                        onChanged: (v) {
                          setState(() => _velocityRandomizeAmount = v);
                          setPopupState(() {});
                        },
                        onChangeEnd: () {
                          _applyVelocityRandomize();
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

  /// Randomize velocity of selected notes (or all notes if none selected)
  void _applyVelocityRandomize() {
    if (_currentClip == null || _velocityRandomizeAmount <= 0) return;

    final notes = _currentClip!.notes;
    final selectedNotes = notes.where((n) => n.isSelected).toList();
    final targetNotes = selectedNotes.isNotEmpty ? selectedNotes : notes;

    if (targetNotes.isEmpty) return;

    _saveToHistory();

    // Max variation: ±50 velocity units at 100%
    final maxVariation = (_velocityRandomizeAmount * 50).round();
    final random = Random();

    setState(() {
      _currentClip = _currentClip!.copyWith(
        notes: _currentClip!.notes.map((note) {
          final isTarget = selectedNotes.isNotEmpty
              ? note.isSelected
              : true;
          if (!isTarget) return note;

          // Random variation per note
          final variation = random.nextInt(maxVariation * 2 + 1) - maxVariation;
          final newVelocity = (note.velocity + variation).clamp(1, 127);

          return note.copyWith(velocity: newVelocity);
        }).toList(),
      );
    });

    _commitToHistory('Randomize velocity');
    _notifyClipUpdated();
  }

  /// Convert MidiCCType to sidebar CCType enum
  CCType _ccTypeFromLane(MidiCCType midiCCType) {
    switch (midiCCType) {
      case MidiCCType.pitchBend:
        return CCType.pitchBend;
      case MidiCCType.modWheel:
        return CCType.modWheel;
      case MidiCCType.expression:
        return CCType.expression;
      case MidiCCType.sustainPedal:
        return CCType.sustain;
      case MidiCCType.volume:
        return CCType.volume;
      default:
        return CCType.modWheel;
    }
  }

  /// Handle CC type change from sidebar dropdown
  void _handleCCTypeChanged(CCType ccType) {
    MidiCCType midiType;
    switch (ccType) {
      case CCType.pitchBend:
        midiType = MidiCCType.pitchBend;
        break;
      case CCType.modWheel:
        midiType = MidiCCType.modWheel;
        break;
      case CCType.expression:
        midiType = MidiCCType.expression;
        break;
      case CCType.sustain:
        midiType = MidiCCType.sustainPedal;
        break;
      case CCType.volume:
        midiType = MidiCCType.volume;
        break;
    }
    setState(() {
      _ccLane = MidiCCLane(ccType: midiType, points: _ccLane.points);
    });
  }

  /// Apply legato - extend each note to touch the next note at same pitch
  void _applyLegato() {
    if (_currentClip == null) return;

    final selectedNotes = _currentClip!.notes.where((n) => n.isSelected).toList();
    if (selectedNotes.isEmpty) return;

    _saveToHistory();

    // Group selected notes by pitch
    final notesByPitch = <int, List<MidiNoteData>>{};
    for (final note in selectedNotes) {
      notesByPitch.putIfAbsent(note.note, () => []).add(note);
    }

    // Sort each pitch group by start time
    for (final notes in notesByPitch.values) {
      notes.sort((a, b) => a.startTime.compareTo(b.startTime));
    }

    setState(() {
      _currentClip = _currentClip!.copyWith(
        notes: _currentClip!.notes.map((note) {
          if (!note.isSelected) return note;

          final pitchNotes = notesByPitch[note.note]!;
          final index = pitchNotes.indexWhere((n) => n.id == note.id);

          // If there's a next note at same pitch, extend to it
          if (index < pitchNotes.length - 1) {
            final nextNote = pitchNotes[index + 1];
            final newDuration = nextNote.startTime - note.startTime;
            return note.copyWith(duration: newDuration);
          }

          return note;
        }).toList(),
      );
    });

    _commitToHistory('Apply legato');
    _notifyClipUpdated();
  }

  /// Reverse selected notes in time (mirror around center point)
  void _reverseNotes() {
    if (_currentClip == null) return;

    final selectedNotes = _currentClip!.notes.where((n) => n.isSelected).toList();
    if (selectedNotes.isEmpty) return;

    _saveToHistory();

    // Find selection bounds
    final selectionStart = selectedNotes.map((n) => n.startTime).reduce((a, b) => a < b ? a : b);
    final selectionEnd = selectedNotes.map((n) => n.endTime).reduce((a, b) => a > b ? a : b);
    final selectionCenter = (selectionStart + selectionEnd) / 2;

    setState(() {
      _currentClip = _currentClip!.copyWith(
        notes: _currentClip!.notes.map((note) {
          if (!note.isSelected) return note;

          // Mirror note position around center
          final noteCenter = note.startTime + note.duration / 2;
          final distanceFromCenter = noteCenter - selectionCenter;
          final newNoteCenter = selectionCenter - distanceFromCenter;
          final newStart = newNoteCenter - note.duration / 2;

          return note.copyWith(startTime: newStart.clamp(0.0, double.infinity));
        }).toList(),
      );
    });

    _commitToHistory('Reverse notes');
    _notifyClipUpdated();
  }

  Widget _buildPianoKey(int midiNote) {
    final isBlackKey = _isBlackKey(midiNote);
    final noteName = _getNoteNameForKey(midiNote);
    final isC = midiNote % 12 == 0;

    return Container(
      height: _pixelsPerNote,
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
        message: _auditionEnabled ? 'Disable audition' : 'Enable audition',
        child: GestureDetector(
          onTap: _toggleAudition,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Center(
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _auditionEnabled ? colors.accent : colors.dark,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Icon(
                  _auditionEnabled ? Icons.volume_up : Icons.volume_off,
                  size: 14,
                  color: _auditionEnabled ? colors.elevated : colors.textMuted,
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
        final scrollOffset = _rulerScroll.hasClients ? _rulerScroll.offset : 0.0;
        final xInContent = details.localPosition.dx + scrollOffset;
        final beats = xInContent / _pixelsPerBeat;
        setState(() {
          _insertMarkerBeats = beats.clamp(0.0, double.infinity);
        });
      },
      onPanStart: (details) {
        final scrollOffset = _rulerScroll.hasClients ? _rulerScroll.offset : 0.0;
        final xInContent = details.localPosition.dx + scrollOffset;
        final beatAtCursor = xInContent / _pixelsPerBeat;

        // Check if clicking on loop markers (when loop is enabled)
        if (_loopEnabled) {
          final loopEnd = _loopStartBeats + _getLoopLength();
          final hitRadius = 10.0 / _pixelsPerBeat; // 10px hit radius in beats

          // Check start marker
          if ((beatAtCursor - _loopStartBeats).abs() < hitRadius) {
            _loopMarkerDrag = _LoopMarkerDrag.start;
            _loopDragStartBeat = _loopStartBeats;
            return;
          }

          // Check end marker
          if ((beatAtCursor - loopEnd).abs() < hitRadius) {
            _loopMarkerDrag = _LoopMarkerDrag.end;
            _loopDragStartBeat = loopEnd;
            return;
          }

          // Check middle region
          if (beatAtCursor > _loopStartBeats && beatAtCursor < loopEnd) {
            _loopMarkerDrag = _LoopMarkerDrag.middle;
            _loopDragStartBeat = beatAtCursor;
            return;
          }
        }

        // Normal pan/zoom behavior
        _loopMarkerDrag = null;
        _zoomDragStartY = details.globalPosition.dy;
        _zoomStartPixelsPerBeat = _pixelsPerBeat;
        _zoomAnchorLocalX = details.localPosition.dx;
        _zoomAnchorBeat = beatAtCursor;
      },
      onPanUpdate: (details) {
        // Handle loop marker dragging
        if (_loopMarkerDrag != null && _loopEnabled) {
          final scrollOffset = _rulerScroll.hasClients ? _rulerScroll.offset : 0.0;
          final xInContent = details.localPosition.dx + scrollOffset;
          final beatAtCursor = xInContent / _pixelsPerBeat;
          final snappedBeat = _snapToGrid(beatAtCursor);

          switch (_loopMarkerDrag!) {
            case _LoopMarkerDrag.start:
              // Move start marker, keep end fixed
              final loopEnd = _loopStartBeats + _getLoopLength();
              final newStart = snappedBeat.clamp(0.0, loopEnd - _gridDivision);
              final newLength = loopEnd - newStart;
              setState(() {
                _loopStartBeats = newStart;
                _updateLoopLength(newLength);
              });
              break;

            case _LoopMarkerDrag.end:
              // Move end marker, keep start fixed
              final newEnd = snappedBeat.clamp(_loopStartBeats + _gridDivision, double.infinity);
              final newLength = newEnd - _loopStartBeats;
              setState(() {
                _updateLoopLength(newLength);
              });
              // Auto-extend canvas if needed
              _autoExtendCanvasIfNeeded(newEnd);
              break;

            case _LoopMarkerDrag.middle:
              // Move entire loop region
              final delta = snappedBeat - _snapToGrid(_loopDragStartBeat);
              final newStart = (_loopStartBeats + delta).clamp(0.0, double.infinity);
              // Only move if not trying to go negative
              if (newStart >= 0) {
                setState(() {
                  _loopStartBeats = newStart;
                });
                _loopDragStartBeat = snappedBeat;
                // Auto-extend canvas if needed
                _autoExtendCanvasIfNeeded(newStart + _getLoopLength());
              }
              break;
          }
          return;
        }

        // Normal pan/zoom behavior
        // Calculate drag delta (positive = dragged down = zoom in)
        final deltaY = details.globalPosition.dy - _zoomDragStartY;

        // Sensitivity: ~100 pixels of drag = 2x zoom change
        // Positive deltaY (drag down) = zoom in, Negative (drag up) = zoom out
        final zoomFactor = 1.0 + (deltaY / 100.0);
        final minZoom = _calculateMinPixelsPerBeat();
        final maxZoom = _calculateMaxPixelsPerBeat();
        final newPixelsPerBeat = (_zoomStartPixelsPerBeat * zoomFactor).clamp(minZoom, maxZoom);

        // Calculate new scroll position to keep anchor beat under cursor
        // anchorBeat * newPixelsPerBeat = newXInContent
        // newScrollOffset = newXInContent - localX
        final newXInContent = _zoomAnchorBeat * newPixelsPerBeat;

        // Also apply horizontal panning: drag left = scroll left (same direction)
        // details.delta.dx is positive when dragging right, negative when dragging left
        // We want scroll to move in the same direction as mouse (drag left = view moves left)
        final panOffset = -details.delta.dx; // Invert so drag left = scroll left

        final targetScrollOffset = (newXInContent - _zoomAnchorLocalX) + panOffset;

        // Update anchor position to account for pan (so zoom stays anchored correctly)
        _zoomAnchorLocalX += details.delta.dx;

        setState(() {
          _pixelsPerBeat = newPixelsPerBeat;
        });

        // Defer scroll adjustment to after the layout rebuild
        // This avoids issues with maxScrollExtent being outdated
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_horizontalScroll.hasClients) {
            final maxScroll = _horizontalScroll.position.maxScrollExtent;
            _horizontalScroll.jumpTo(targetScrollOffset.clamp(0.0, maxScroll));
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
              pixelsPerBeat: _pixelsPerBeat,
              totalBeats: totalBeats,
              playheadPosition: 0.0, // TODO: Sync with actual playhead
              loopEnabled: _loopEnabled,
              loopStart: _loopStartBeats,
              loopEnd: _loopStartBeats + _getLoopLength(),
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

    for (final midiNote in _currentClip?.notes ?? []) {
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
    final isInVerticalRange = (position.dy >= noteY) && (position.dy <= noteY + _pixelsPerNote);

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
    if (_currentMode == InteractionMode.move || _currentMode == InteractionMode.resize) {
      return;
    }

    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
    final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;

    setState(() {
      if (isAltPressed) {
        // Alt held = temporary erase mode
        _tempModeOverride = ToolMode.eraser;
        _currentCursor = SystemMouseCursors.forbidden;
      } else if (isCtrlOrCmd) {
        // Cmd/Ctrl held = context-sensitive (duplicate on note, slice on empty)
        // We set duplicate as the temp mode; slice handled in tap handler
        _tempModeOverride = ToolMode.duplicate;
        _currentCursor = SystemMouseCursors.copy;
      } else {
        // No modifier = clear temp override
        _tempModeOverride = null;
        _currentCursor = SystemMouseCursors.basic;
      }
    });
  }

  // Handle hover for cursor feedback (smart context-aware cursors)
  void _onHover(PointerHoverEvent event) {
    // Don't update cursor during active drag operations
    if (_currentMode == InteractionMode.move || _currentMode == InteractionMode.resize) {
      return;
    }

    final position = event.localPosition;
    final hoveredNote = _findNoteAtPosition(position);
    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
    final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final toolMode = _effectiveToolMode;

    // Tool-mode-aware cursor logic
    if (hoveredNote != null) {
      // On a note
      if (isAltPressed || toolMode == ToolMode.eraser) {
        // Eraser mode - show delete cursor
        setState(() {
          _currentCursor = SystemMouseCursors.forbidden;
        });
      } else if (toolMode == ToolMode.slice) {
        // Slice mode - show vertical split cursor
        setState(() {
          _currentCursor = SystemMouseCursors.verticalText;
        });
      } else if (isCtrlOrCmd || toolMode == ToolMode.duplicate) {
        // Duplicate mode - show copy cursor
        setState(() {
          _currentCursor = SystemMouseCursors.copy;
        });
      } else if (toolMode == ToolMode.select) {
        // Select mode - show pointer on notes
        final edge = _getEdgeAtPosition(position, hoveredNote);
        if (edge != null) {
          setState(() {
            _currentCursor = SystemMouseCursors.resizeLeftRight;
          });
        } else {
          setState(() {
            _currentCursor = SystemMouseCursors.click;
          });
        }
      } else {
        // Draw mode (default)
        final edge = _getEdgeAtPosition(position, hoveredNote);
        if (edge != null) {
          // Near edge - show resize cursor
          setState(() {
            _currentCursor = SystemMouseCursors.resizeLeftRight;
          });
        } else {
          // On note body - show grab cursor
          setState(() {
            _currentCursor = SystemMouseCursors.grab;
          });
        }
      }
    } else {
      // Empty space
      if (isAltPressed || toolMode == ToolMode.eraser) {
        // Eraser mode on empty space
        setState(() {
          _currentCursor = SystemMouseCursors.forbidden;
        });
      } else if (toolMode == ToolMode.select) {
        // Select mode on empty - basic cursor (will do box select on drag)
        setState(() {
          _currentCursor = SystemMouseCursors.basic;
        });
      } else if (toolMode == ToolMode.slice) {
        // Slice mode on empty - show slice cursor
        setState(() {
          _currentCursor = SystemMouseCursors.verticalText;
        });
      } else if (toolMode == ToolMode.duplicate) {
        // Duplicate on empty - nothing to duplicate
        setState(() {
          _currentCursor = SystemMouseCursors.basic;
        });
      } else {
        // Draw mode (default) - crosshair for note creation
        setState(() {
          _currentCursor = SystemMouseCursors.precise;
        });
      }
    }
  }

  void _onTapDown(TapDownDetails details) {
    // Request focus to enable keyboard events (delete, undo, etc.)
    _focusNode.requestFocus();

    final clickedNote = _findNoteAtPosition(details.localPosition);
    final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final toolMode = _effectiveToolMode;

    // ============================================
    // TOOL MODE BEHAVIOR
    // ============================================

    // Alt+click OR Erase tool = delete note
    if (isAltPressed || toolMode == ToolMode.eraser) {
      if (clickedNote != null) {
        _saveToHistory();
        setState(() {
          _currentClip = _currentClip?.copyWith(
            notes: _currentClip!.notes.where((n) => n.id != clickedNote.id).toList(),
          );
        });
        _commitToHistory('Delete note');
        _notifyClipUpdated();
      }
      return;
    }

    // Slice tool OR Cmd+click = slice
    if (toolMode == ToolMode.slice) {
      if (clickedNote != null) {
        final beatPosition = _getBeatAtX(details.localPosition.dx);
        _sliceNoteAt(clickedNote, beatPosition);
      }
      return;
    }

    // Duplicate tool OR Cmd+click on note = duplicate in place
    if (toolMode == ToolMode.duplicate || (isCtrlOrCmd && clickedNote != null)) {
      if (clickedNote != null) {
        _saveToHistory();
        final duplicate = clickedNote.copyWith(
          id: '${clickedNote.note}_${DateTime.now().microsecondsSinceEpoch}',
          isSelected: false,
        );
        setState(() {
          _currentClip = _currentClip?.addNote(duplicate);
        });
        _commitToHistory('Duplicate note');
        _notifyClipUpdated();
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
            _currentClip = _currentClip?.copyWith(
              notes: _currentClip!.notes.map((n) {
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
            _currentClip = _currentClip?.copyWith(
              notes: _currentClip!.notes.map((n) {
                if (n.id == clickedNote.id) {
                  return n.copyWith(isSelected: true);
                } else {
                  return n.copyWith(isSelected: false);
                }
              }).toList(),
            );
          });
        }
        _notifyClipUpdated();
        _startAudition(clickedNote.note, clickedNote.velocity);
      } else {
        // Click on empty space = deselect all
        setState(() {
          _currentClip = _currentClip?.copyWith(
            notes: _currentClip!.notes.map((n) => n.copyWith(isSelected: false)).toList(),
          );
        });
        _notifyClipUpdated();
      }
      return;
    }

    // ============================================
    // DRAW TOOL (default behavior)
    // ============================================

    // Cmd+click on empty space = slice any note at that beat position
    if (isCtrlOrCmd && clickedNote == null) {
      final beat = _getBeatAtX(details.localPosition.dx);
      final noteToSlice = _currentClip?.notes.firstWhere(
        (n) => n.startTime < beat && (n.startTime + n.duration) > beat,
        orElse: () => MidiNoteData(note: -1, velocity: 0, startTime: 0, duration: 0),
      );
      if (noteToSlice != null && noteToSlice.note >= 0) {
        _sliceNoteAt(noteToSlice, beat);
      }
      return;
    }

    if (clickedNote != null) {
      // Shift+click on note = toggle selection (add/remove from selection)
      if (isShiftPressed) {
        setState(() {
          _currentClip = _currentClip?.copyWith(
            notes: _currentClip!.notes.map((n) {
              if (n.id == clickedNote.id) {
                return n.copyWith(isSelected: !n.isSelected);
              }
              return n;
            }).toList(),
          );
        });
        _notifyClipUpdated();
        return;
      }

      // Regular click on note = select it (deselect others) or toggle if already selected
      setState(() {
        _currentClip = _currentClip?.copyWith(
          notes: _currentClip!.notes.map((n) {
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
      _notifyClipUpdated();

      // Start sustained audition (will stop on mouse up)
      _startAudition(clickedNote.note, clickedNote.velocity);

      // Clear just-created tracking since we clicked on existing note
      _justCreatedNoteId = null;
    } else {
      // Single-click on empty space = create note (Draw tool)
      final beat = _getBeatAtX(details.localPosition.dx);
      final noteRow = _getNoteAtY(details.localPosition.dy);

      _saveToHistory();
      final snappedBeat = _snapToGrid(beat);

      // Check if chord palette is visible - stamp chord instead of single note
      if (_chordPaletteVisible) {
        _stampChordAt(snappedBeat, noteRow);
        return;
      }

      // Create single note (FL Studio style)
      final newNote = MidiNoteData(
        note: noteRow,
        velocity: 100,
        startTime: snappedBeat,
        duration: _lastNoteDuration,
        isSelected: true,  // Auto-select new note for immediate manipulation
      );

      setState(() {
        // Deselect all existing notes, then add the new selected note
        _currentClip = _currentClip?.copyWith(
          notes: _currentClip!.notes.map((n) => n.copyWith(isSelected: false)).toList(),
        );
        _currentClip = _currentClip?.addNote(newNote);

        // Auto-extend loop length if note extends beyond current loop
        _autoExtendLoopIfNeeded(newNote);
      });

      // Track this note for immediate drag-to-move if user drags
      _justCreatedNoteId = newNote.id;

      _commitToHistory('Add note');
      _notifyClipUpdated();
      // Start sustained audition (will stop on mouse up)
      _startAudition(noteRow, 100);
    }
  }

  /// Auto-extend loop length if a note extends beyond the current loop boundary
  void _autoExtendLoopIfNeeded(MidiNoteData note) {
    if (_currentClip == null) return;

    final noteEndTime = note.startTime + note.duration;
    final currentLoopLength = _currentClip!.loopLength;

    if (noteEndTime > currentLoopLength) {
      // Round up to next bar boundary (4 beats)
      final newLoopLength = ((noteEndTime / 4).ceil() * 4).toDouble();
      _currentClip = _currentClip!.copyWith(loopLength: newLoopLength);
    }
  }

  /// Update the loop length in the current clip
  void _updateLoopLength(double newLength) {
    if (_currentClip == null) return;
    final clampedLength = newLength.clamp(_gridDivision, 256.0);
    _currentClip = _currentClip!.copyWith(loopLength: clampedLength);
  }

  /// Auto-extend the canvas/clip if loop end exceeds current bounds
  void _autoExtendCanvasIfNeeded(double loopEndBeats) {
    if (_currentClip == null) return;
    // If the loop end goes beyond current clip duration, extend it
    if (loopEndBeats > _currentClip!.duration) {
      // Round up to next bar boundary
      final newDuration = ((loopEndBeats / _beatsPerBar).ceil() * _beatsPerBar).toDouble();
      _currentClip = _currentClip!.copyWith(duration: newDuration);
    }
  }

  void _onPanStart(DragStartDetails details) {
    // Request focus to enable keyboard events (delete, undo, etc.)
    _focusNode.requestFocus();

    _dragStart = details.localPosition;
    final clickedNote = _findNoteAtPosition(details.localPosition);
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
    final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final toolMode = _effectiveToolMode;

    // Skip normal pan handling if Alt is held OR eraser tool is active
    if (isAltPressed || toolMode == ToolMode.eraser) {
      return;
    }

    // Box selection: Shift+drag on empty OR Select tool drag on empty
    if ((isShiftPressed || toolMode == ToolMode.select) && clickedNote == null) {
      // Marquee/box select
      setState(() {
        _isSelecting = true;
        _selectionStart = details.localPosition;
        _selectionEnd = details.localPosition;
        _currentMode = InteractionMode.select;
      });
      return;
    }

    // Select tool: drag on a note = move the note (not create new)
    if (toolMode == ToolMode.select && clickedNote != null) {
      // Move note(s) - similar to normal drag on note
      _saveToHistory();
      setState(() {
        // Select the clicked note if not already selected
        if (!clickedNote.isSelected) {
          _currentClip = _currentClip?.copyWith(
            notes: _currentClip!.notes.map((n) {
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
        _dragStartNotes = {};
        for (final note in _currentClip!.selectedNotes) {
          _dragStartNotes[note.id] = note;
        }
        _movingNoteId = clickedNote.id;
        _currentMode = InteractionMode.move;
        _currentCursor = SystemMouseCursors.grabbing;
      });
      _startAudition(clickedNote.note, clickedNote.velocity);
      return;
    }

    // Duplicate tool: drag on note = duplicate and move
    if (toolMode == ToolMode.duplicate && clickedNote != null) {
      _saveToHistory();
      _isDuplicating = true;

      final selectedNotes = _currentClip?.selectedNotes ?? [];
      final notesToDuplicate = selectedNotes.isNotEmpty && selectedNotes.any((n) => n.id == clickedNote.id)
          ? selectedNotes
          : [clickedNote];

      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final duplicatedNotes = <MidiNoteData>[];
      _dragStartNotes = {};

      for (int i = 0; i < notesToDuplicate.length; i++) {
        final sourceNote = notesToDuplicate[i];
        final duplicatedNote = sourceNote.copyWith(
          id: '${sourceNote.note}_${sourceNote.startTime}_${timestamp}_$i',
          isSelected: false,
        );
        duplicatedNotes.add(duplicatedNote);
        _dragStartNotes[duplicatedNote.id] = duplicatedNote;
      }

      final primaryDuplicate = duplicatedNotes.first;

      setState(() {
        final deselectedNotes = _currentClip!.notes.map((n) => n.copyWith(isSelected: false)).toList();
        _currentClip = _currentClip?.copyWith(
          notes: [...deselectedNotes, ...duplicatedNotes],
        );
        _currentClip = _currentClip?.copyWith(
          notes: _currentClip!.notes.map((n) {
            if (duplicatedNotes.any((dup) => dup.id == n.id)) {
              return n.copyWith(isSelected: true);
            }
            return n;
          }).toList(),
        );
        _movingNoteId = primaryDuplicate.id;
        _currentMode = InteractionMode.move;
        _currentCursor = SystemMouseCursors.copy;
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
      _saveToHistory();
      _isDuplicating = true;

      // Determine which notes to duplicate: all selected notes, or just the clicked note if none selected
      final selectedNotes = _currentClip?.selectedNotes ?? [];
      final notesToDuplicate = selectedNotes.isNotEmpty && selectedNotes.any((n) => n.id == clickedNote.id)
          ? selectedNotes  // Duplicate all selected notes (clicked note is part of selection)
          : [clickedNote]; // Just duplicate the single clicked note

      // Create duplicates for all notes to be duplicated
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final duplicatedNotes = <MidiNoteData>[];
      _dragStartNotes = {};

      for (int i = 0; i < notesToDuplicate.length; i++) {
        final sourceNote = notesToDuplicate[i];
        final duplicatedNote = sourceNote.copyWith(
          id: '${sourceNote.note}_${sourceNote.startTime}_${timestamp}_$i',
          isSelected: false,
        );
        duplicatedNotes.add(duplicatedNote);
        // Store original positions for proper delta calculation
        _dragStartNotes[duplicatedNote.id] = duplicatedNote;
      }

      // Track the first duplicate as the "primary" moving note (for audition)
      final primaryDuplicate = duplicatedNotes.first;

      setState(() {
        // Deselect all original notes, then add all duplicates
        final deselectedNotes = _currentClip!.notes.map((n) => n.copyWith(isSelected: false)).toList();
        _currentClip = _currentClip?.copyWith(
          notes: [...deselectedNotes, ...duplicatedNotes],
        );
        // Mark all duplicates as selected so they move together
        _currentClip = _currentClip?.copyWith(
          notes: _currentClip!.notes.map((n) {
            if (duplicatedNotes.any((dup) => dup.id == n.id)) {
              return n.copyWith(isSelected: true);
            }
            return n;
          }).toList(),
        );
        _movingNoteId = primaryDuplicate.id; // Track primary duplicate
        _currentMode = InteractionMode.move;
        _currentCursor = SystemMouseCursors.copy;
      });

      _startAudition(clickedNote.note, clickedNote.velocity);
    } else if (_justCreatedNoteId != null) {
      // User is dragging from where they just created a note - move it (FL Studio style)
      final createdNote = _currentClip?.notes.firstWhere(
        (n) => n.id == _justCreatedNoteId,
        orElse: () => MidiNoteData(note: 60, velocity: 100, startTime: 0, duration: 1),
      );

      if (createdNote != null && createdNote.id == _justCreatedNoteId) {
        // Start moving the just-created note
        _saveToHistory();

        // Store original positions of all notes for proper delta calculation
        _dragStartNotes = {
          for (final n in _currentClip?.notes ?? []) n.id: n
        };

        // Mark this note as the one being moved (for _onPanUpdate)
        _movingNoteId = _justCreatedNoteId;

        setState(() {
          _currentMode = InteractionMode.move;
          _currentCursor = SystemMouseCursors.grabbing;
        });

      }

      // Clear just-created tracking
      _justCreatedNoteId = null;
    } else if (clickedNote != null && !_isSliceModeActive) {
      // Check if we're near the edge for resizing (FL Studio style)
      final edge = _getEdgeAtPosition(details.localPosition, clickedNote);

      if (edge != null) {
        // Start resizing from left or right edge
        _saveToHistory(); // Save before resizing
        setState(() {
          _resizingNoteId = clickedNote.id;
          _resizingEdge = edge; // Store which edge ('left' or 'right')
          _currentMode = InteractionMode.resize;
          _currentCursor = SystemMouseCursors.resizeLeftRight;
        });
      } else {
        // Start moving the note (clicked on body)
        _saveToHistory(); // Save before moving

        // Store original positions of all notes for proper delta calculation
        _dragStartNotes = {
          for (final n in _currentClip?.notes ?? []) n.id: n
        };

        // Mark this note as the one being moved (no selection highlight)
        _movingNoteId = clickedNote.id;

        setState(() {
          _currentMode = InteractionMode.move;
          _currentCursor = SystemMouseCursors.grabbing; // Closed hand while dragging
        });

        // Start sustained audition when starting to drag (FL Studio style)
        _startAudition(clickedNote.note, clickedNote.velocity);
      }
    }
    // Note: No longer need to handle drawing here - single-click in _onTapDown creates notes
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_currentMode == InteractionMode.select && _isSelecting) {
      // Update selection rectangle and select notes LIVE
      setState(() {
        _selectionEnd = details.localPosition;

        // Live selection - update note selection as rectangle changes
        if (_selectionStart != null && _selectionEnd != null) {
          final startBeat = _getBeatAtX(_selectionStart!.dx.clamp(0, double.infinity));
          final endBeat = _getBeatAtX(_selectionEnd!.dx.clamp(0, double.infinity));
          final startNote = _getNoteAtY(_selectionStart!.dy.clamp(0, double.infinity));
          final endNote = _getNoteAtY(_selectionEnd!.dy.clamp(0, double.infinity));

          final minBeat = startBeat < endBeat ? startBeat : endBeat;
          final maxBeat = startBeat < endBeat ? endBeat : startBeat;
          final minNote = startNote < endNote ? startNote : endNote;
          final maxNote = startNote < endNote ? endNote : startNote;

          _currentClip = _currentClip?.copyWith(
            notes: _currentClip!.notes.map((note) {
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
    } else if (_isPainting && _paintNote != null) {
      // Paint mode - create additional notes as user drags right
      final currentBeat = _snapToGrid(_getBeatAtX(details.localPosition.dx));
      final nextNoteBeat = _lastPaintedBeat + _lastNoteDuration;

      // Only create note if we've dragged far enough for the next note
      if (currentBeat >= nextNoteBeat) {
        final newNote = MidiNoteData(
          note: _paintNote!,
          velocity: 100,
          startTime: nextNoteBeat,
          duration: _lastNoteDuration,
        );

        setState(() {
          _currentClip = _currentClip?.addNote(newNote);
          _lastPaintedBeat = nextNoteBeat;
        });

      }
    } else if (_currentMode == InteractionMode.move && _dragStart != null) {
      // Move selected notes - use delta from original drag start position
      // Shift key bypasses grid snap for fine adjustment
      final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
      final deltaX = details.localPosition.dx - _dragStart!.dx;
      final deltaY = details.localPosition.dy - _dragStart!.dy;

      final deltaBeat = deltaX / _pixelsPerBeat;
      final deltaNote = -(deltaY / _pixelsPerNote).round(); // Inverted Y

      // Track pitch changes for audition
      int? newPitchForAudition;
      int? velocityForAudition;

      // Track moved notes for auto-extend
      final List<MidiNoteData> movedNotes = [];

      setState(() {
        _currentClip = _currentClip?.copyWith(
          notes: _currentClip!.notes.map((n) {
            // Move the note being dragged (by _movingNoteId) or any selected notes
            if (n.id == _movingNoteId || n.isSelected) {
              // Use original position from drag start, not current position
              final originalNote = _dragStartNotes[n.id];
              if (originalNote != null) {
                final rawStartTime = originalNote.startTime + deltaBeat;
                final newStartTime = (isShiftPressed ? rawStartTime : _snapToGrid(rawStartTime)).clamp(0.0, 64.0);
                var newNote = (originalNote.note + deltaNote).clamp(0, 127);

                // Apply scale lock if enabled
                if (_scaleLockEnabled) {
                  newNote = _snapNoteToScale(newNote);
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
          _autoExtendLoopIfNeeded(movedNote);
        }
        // Don't update _dragStart here - keep original for cumulative delta
      });

      // Change audition pitch when dragging note up/down
      if (newPitchForAudition != null) {
        _changeAuditionPitch(newPitchForAudition!, velocityForAudition ?? 100);
      }

      _notifyClipUpdated();
    } else if (_currentMode == InteractionMode.resize && _resizingNoteId != null) {
      // Resize note from left or right edge (FL Studio style)
      // Shift key bypasses grid snap for fine adjustment
      final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
      MidiNoteData? resizedNote;
      setState(() {
        _currentClip = _currentClip?.copyWith(
          notes: _currentClip!.notes.map((n) {
            if (n.id == _resizingNoteId) {
              final rawBeat = _getBeatAtX(details.localPosition.dx);
              final newBeat = isShiftPressed ? rawBeat : _snapToGrid(rawBeat);

              if (_resizingEdge == 'right') {
                // Right edge: change duration only
                final newDuration = (newBeat - n.startTime).clamp(_gridDivision, 64.0);
                resizedNote = n.copyWith(duration: newDuration);
                return resizedNote!;
              } else if (_resizingEdge == 'left') {
                // Left edge: change start time and duration
                final oldEndTime = n.endTime;
                final newStartTime = newBeat.clamp(0.0, oldEndTime - _gridDivision);
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
          _autoExtendLoopIfNeeded(resizedNote!);
        }
      });
      _notifyClipUpdated();
    }
  }

  void _onPanEnd(DragEndDetails details) {
    // Clear just-created tracking on any pan end
    _justCreatedNoteId = null;

    // Handle paint mode completion (legacy - kept for potential future use)
    if (_isPainting) {
      final paintedNotes = _lastPaintedBeat - (_paintStartBeat ?? 0);
      final additionalNotes = (paintedNotes / _lastNoteDuration).round();

      // Only commit if we actually painted additional notes (beyond the initial click-created one)
      if (additionalNotes > 0) {
        _saveToHistory();
        _commitToHistory('Paint ${additionalNotes + 1} notes');
        _notifyClipUpdated();
      }

      setState(() {
        _isPainting = false;
        _paintStartBeat = null;
        _paintNote = null;
        _lastPaintedBeat = 0.0;
      });
      return;
    }

    if (_currentMode == InteractionMode.select && _isSelecting) {
      // Selection is already applied live in _onPanUpdate()
      // Just clean up selection state here
      setState(() {
        _isSelecting = false;
        _selectionStart = null;
        _selectionEnd = null;
      });
    }

    // Commit move or duplicate operation to history
    if (_currentMode == InteractionMode.move) {
      if (_isDuplicating) {
        final duplicateCount = _currentClip?.selectedNotes.length ?? 1;
        _commitToHistory(duplicateCount == 1 ? 'Duplicate note' : 'Duplicate $duplicateCount notes');
      } else {
        final selectedCount = _currentClip?.selectedNotes.length ?? 0;
        if (selectedCount > 0) {
          _commitToHistory(selectedCount == 1 ? 'Move note' : 'Move $selectedCount notes');
        }
      }
    }

    // Remember duration of resized note for next creation
    if (_currentMode == InteractionMode.resize && _resizingNoteId != null) {
      final resizedNote = _currentClip?.notes.firstWhere((n) => n.id == _resizingNoteId);
      if (resizedNote != null) {
        _lastNoteDuration = resizedNote.duration;
        _commitToHistory('Resize note');
      }
    }

    // Stop audition when mouse released
    _stopAudition();

    // Reset state
    setState(() {
      _dragStart = null;
      _dragStartNotes = {}; // Clear stored original positions
      _movingNoteId = null; // Clear moving note tracking
      _isDuplicating = false; // Clear duplicate mode
      _resizingNoteId = null;
      _resizingEdge = null;
      _currentMode = InteractionMode.draw;
      _currentCursor = SystemMouseCursors.basic; // Reset cursor to default
    });
  }

  // Handle keyboard events for deletion, undo/redo, and copy/paste
  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // Delete key
      if (event.logicalKey == LogicalKeyboardKey.delete ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        if (_currentClip?.selectedNotes.isNotEmpty ?? false) {
          _saveToHistory();
          _deleteSelectedNotes();
        }
      }
      // Undo (Cmd+Z or Ctrl+Z)
      else if ((event.logicalKey == LogicalKeyboardKey.keyZ) &&
          (HardwareKeyboard.instance.isMetaPressed ||
           HardwareKeyboard.instance.isControlPressed) &&
          !HardwareKeyboard.instance.isShiftPressed) {
        _undo();
      }
      // Redo (Cmd+Shift+Z or Ctrl+Shift+Z)
      else if ((event.logicalKey == LogicalKeyboardKey.keyZ) &&
          (HardwareKeyboard.instance.isMetaPressed ||
           HardwareKeyboard.instance.isControlPressed) &&
          HardwareKeyboard.instance.isShiftPressed) {
        _redo();
      }
      // Copy (Cmd+C or Ctrl+C)
      else if ((event.logicalKey == LogicalKeyboardKey.keyC) &&
          (HardwareKeyboard.instance.isMetaPressed ||
           HardwareKeyboard.instance.isControlPressed)) {
        _copySelectedNotes();
      }
      // Paste (Cmd+V or Ctrl+V)
      else if ((event.logicalKey == LogicalKeyboardKey.keyV) &&
          (HardwareKeyboard.instance.isMetaPressed ||
           HardwareKeyboard.instance.isControlPressed)) {
        _pasteNotes();
      }
      // Q to quantize selected notes
      else if (event.logicalKey == LogicalKeyboardKey.keyQ &&
          !HardwareKeyboard.instance.isMetaPressed &&
          !HardwareKeyboard.instance.isControlPressed) {
        _quantizeSelectedNotes();
      }
      // Cmd+D or Ctrl+D to duplicate selected notes
      else if ((event.logicalKey == LogicalKeyboardKey.keyD) &&
          (HardwareKeyboard.instance.isMetaPressed ||
           HardwareKeyboard.instance.isControlPressed)) {
        _duplicateSelectedNotes();
      }
      // Cmd+B or Ctrl+B to duplicate selected notes (FL Studio style)
      else if ((event.logicalKey == LogicalKeyboardKey.keyB) &&
          (HardwareKeyboard.instance.isMetaPressed ||
           HardwareKeyboard.instance.isControlPressed)) {
        _duplicateSelectedNotes();
      }
      // Cmd+A or Ctrl+A to select all notes
      else if ((event.logicalKey == LogicalKeyboardKey.keyA) &&
          (HardwareKeyboard.instance.isMetaPressed ||
           HardwareKeyboard.instance.isControlPressed)) {
        _selectAllNotes();
      }
      // Escape to deselect all notes / cancel action
      else if (event.logicalKey == LogicalKeyboardKey.escape) {
        _deselectAllNotes();
      }
      // Cut (Cmd+X or Ctrl+X)
      else if ((event.logicalKey == LogicalKeyboardKey.keyX) &&
          (HardwareKeyboard.instance.isMetaPressed ||
           HardwareKeyboard.instance.isControlPressed)) {
        _cutSelectedNotes();
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
        setState(() => _chordPaletteVisible = !_chordPaletteVisible);
      }
    } else if (event is KeyUpEvent) {
      // Hold modifiers are handled via _tempModeOverride in _updateCursorForModifiers
    }
  }

  /// Deselect all notes
  void _deselectAllNotes() {
    if (_currentClip == null) return;

    final hasSelection = _currentClip!.notes.any((n) => n.isSelected);
    if (!hasSelection) {
      return;
    }

    setState(() {
      _currentClip = _currentClip?.copyWith(
        notes: _currentClip!.notes.map((n) => n.copyWith(isSelected: false)).toList(),
      );
    });

  }

  /// Copy selected notes to clipboard
  void _copySelectedNotes() {
    final selectedNotes = _currentClip?.selectedNotes ?? [];
    if (selectedNotes.isEmpty) {
      return;
    }

    // Store copies of selected notes (deselected)
    _clipboard = selectedNotes.map((note) => note.copyWith(isSelected: false)).toList();
  }

  /// Cut selected notes (copy to clipboard, then delete)
  void _cutSelectedNotes() {
    final selectedNotes = _currentClip?.selectedNotes ?? [];
    if (selectedNotes.isEmpty) {
      return;
    }

    // Copy to clipboard first
    _clipboard = selectedNotes.map((note) => note.copyWith(isSelected: false)).toList();

    // Then delete the selected notes
    _saveToHistory();
    final selectedIds = selectedNotes.map((n) => n.id).toSet();
    setState(() {
      _currentClip = _currentClip?.copyWith(
        notes: _currentClip!.notes.where((n) => !selectedIds.contains(n.id)).toList(),
      );
    });
    _notifyClipUpdated();
    _commitToHistory(selectedNotes.length == 1 ? 'Cut note' : 'Cut ${selectedNotes.length} notes');
  }

  /// Paste notes from clipboard
  void _pasteNotes() {
    if (_clipboard.isEmpty) {
      return;
    }

    if (_currentClip == null) {
      return;
    }

    _saveToHistory(); // Save before pasting

    // Find the earliest note in clipboard to use as reference point
    final earliestTime = _clipboard.map((n) => n.startTime).reduce((a, b) => a < b ? a : b);

    // Paste at insert marker position if set, otherwise at start
    final pasteTime = _insertMarkerBeats ?? 0.0;

    // Calculate offset
    final timeOffset = pasteTime - earliestTime;

    // Create new notes with offset and new IDs
    final newNotes = _clipboard.map((note) {
      return note.copyWith(
        id: DateTime.now().microsecondsSinceEpoch.toString() + '_${note.note}',
        startTime: note.startTime + timeOffset,
        isSelected: true, // Select pasted notes
      );
    }).toList();

    // Deselect all existing notes and add new ones
    setState(() {
      _currentClip = _currentClip?.copyWith(
        notes: [
          ..._currentClip!.notes.map((n) => n.copyWith(isSelected: false)),
          ...newNotes,
        ],
      );
    });

    _notifyClipUpdated();
    _commitToHistory(newNotes.length == 1 ? 'Paste note' : 'Paste ${newNotes.length} notes');
  }

  /// Duplicate selected notes (place copies after originals)
  void _duplicateSelectedNotes() {
    final selectedNotes = _currentClip?.selectedNotes ?? [];
    if (selectedNotes.isEmpty) {
      return;
    }

    _saveToHistory();

    // Find duration of selection to offset duplicates
    final minStart = selectedNotes.map((n) => n.startTime).reduce((a, b) => a < b ? a : b);
    final maxEnd = selectedNotes.map((n) => n.endTime).reduce((a, b) => a > b ? a : b);
    final selectionDuration = maxEnd - minStart;

    // Create duplicates offset by selection duration
    final duplicates = selectedNotes.map((note) {
      return note.copyWith(
        id: '${note.note}_${note.startTime + selectionDuration}_${DateTime.now().microsecondsSinceEpoch}',
        startTime: note.startTime + selectionDuration,
        isSelected: true,
      );
    }).toList();

    // Deselect originals and add duplicates
    setState(() {
      _currentClip = _currentClip?.copyWith(
        notes: [
          ..._currentClip!.notes.map((n) => n.copyWith(isSelected: false)),
          ...duplicates,
        ],
      );

      // Auto-extend loop if needed
      for (final note in duplicates) {
        _autoExtendLoopIfNeeded(note);
      }
    });

    _notifyClipUpdated();
    _commitToHistory(duplicates.length == 1 ? 'Duplicate note' : 'Duplicate ${duplicates.length} notes');
  }

  /// Select all notes in the current clip
  void _selectAllNotes() {
    if (_currentClip == null || _currentClip!.notes.isEmpty) {
      return;
    }

    setState(() {
      _currentClip = _currentClip?.copyWith(
        notes: _currentClip!.notes.map((n) => n.copyWith(isSelected: true)).toList(),
      );
    });

  }

  void _deleteSelectedNotes() {
    final selectedCount = _currentClip?.selectedNotes.length ?? 0;
    setState(() {
      final selectedIds = _currentClip?.selectedNotes.map((n) => n.id).toSet() ?? {};
      _currentClip = _currentClip?.copyWith(
        notes: _currentClip!.notes.where((n) => !selectedIds.contains(n.id)).toList(),
      );
    });
    _notifyClipUpdated();
    _commitToHistory(selectedCount == 1 ? 'Delete note' : 'Delete $selectedCount notes');
  }

  /// Show context menu for a note
  void _showNoteContextMenu(Offset position, MidiNoteData note) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selectedNotes = _currentClip?.selectedNotes ?? [];
    final bool hasSelection = selectedNotes.isNotEmpty;
    final int selectedCount = hasSelection ? selectedNotes.length : 1;
    final String noteLabel = selectedCount == 1 ? 'Note' : '$selectedCount Notes';

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 18),
              const SizedBox(width: 8),
              Text('Delete $noteLabel'),
              const Spacer(),
              Text('⌘⌫', style: TextStyle(fontSize: 12, color: context.colors.textMuted)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'duplicate',
          child: Row(
            children: [
              const Icon(Icons.content_copy, size: 18),
              const SizedBox(width: 8),
              Text('Duplicate $noteLabel'),
              const Spacer(),
              Text('⌘D', style: TextStyle(fontSize: 12, color: context.colors.textMuted)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'cut',
          child: Row(
            children: [
              const Icon(Icons.content_cut, size: 18),
              const SizedBox(width: 8),
              Text('Cut $noteLabel'),
              const Spacer(),
              Text('⌘X', style: TextStyle(fontSize: 12, color: context.colors.textMuted)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: [
              const Icon(Icons.copy, size: 18),
              const SizedBox(width: 8),
              Text('Copy $noteLabel'),
              const Spacer(),
              Text('⌘C', style: TextStyle(fontSize: 12, color: context.colors.textMuted)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'paste',
          enabled: _clipboard.isNotEmpty,
          child: Row(
            children: [
              const Icon(Icons.paste, size: 18),
              const SizedBox(width: 8),
              const Text('Paste'),
              const Spacer(),
              Text('⌘V', style: TextStyle(fontSize: 12, color: context.colors.textMuted)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'quantize',
          child: Row(
            children: [
              const Icon(Icons.grid_on, size: 18),
              const SizedBox(width: 8),
              const Text('Quantize'),
              const Spacer(),
              Text('Q', style: TextStyle(fontSize: 12, color: context.colors.textMuted)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'velocity',
          child: Row(
            children: [
              const Icon(Icons.speed, size: 18),
              const SizedBox(width: 8),
              Text('Velocity: ${note.velocity}'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;

      switch (value) {
        case 'delete':
          if (hasSelection) {
            _deleteSelectedNotes();
          } else {
            _deleteNote(note);
          }
          break;
        case 'duplicate':
          if (hasSelection) {
            _duplicateSelectedNotes();
          } else {
            _duplicateNote(note);
          }
          break;
        case 'cut':
          _cutSelectedNotes();
          break;
        case 'copy':
          _copySelectedNotes();
          break;
        case 'paste':
          _pasteNotes();
          break;
        case 'velocity':
          // Show velocity dialog - for now just toggle velocity lane
          setState(() => _velocityLaneExpanded = true);
          break;
        case 'quantize':
          _quantizeSelectedNotes();
          break;
      }
    });
  }

  /// Delete a specific note
  void _deleteNote(MidiNoteData note) {
    _saveToHistory();
    setState(() {
      _currentClip = _currentClip?.copyWith(
        notes: _currentClip!.notes.where((n) => n.id != note.id).toList(),
      );
    });
    _notifyClipUpdated();
    _commitToHistory('Delete note: ${note.noteName}');
  }

  /// Duplicate a note (place copy slightly after original)
  void _duplicateNote(MidiNoteData note) {
    _saveToHistory();
    final newNote = note.copyWith(
      startTime: note.startTime + note.duration,
      id: '${note.note}_${note.startTime + note.duration}_${DateTime.now().microsecondsSinceEpoch}',
    );
    setState(() {
      _currentClip = _currentClip?.copyWith(
        notes: [..._currentClip!.notes, newNote],
      );
    });
    _notifyClipUpdated();
    _commitToHistory('Duplicate note: ${note.noteName}');
  }

  /// Quantize selected notes to grid
  void _quantizeSelectedNotes() {
    final selectedNotes = _currentClip?.notes.where((n) => n.isSelected).toList() ?? [];
    if (selectedNotes.isEmpty) {
      return;
    }

    _saveToHistory();
    final gridSize = _gridDivision;
    setState(() {
      _currentClip = _currentClip?.copyWith(
        notes: _currentClip!.notes.map((n) {
          if (n.isSelected) {
            return n.quantize(gridSize);
          }
          return n;
        }).toList(),
      );
    });
    _notifyClipUpdated();
    _commitToHistory('Quantize ${selectedNotes.length} notes');
  }

  /// Start eraser mode (right-click drag)
  void _startErasing(Offset position) {
    _saveToHistory();
    _isErasing = true;
    _erasedNoteIds = {};
    setState(() => _currentCursor = SystemMouseCursors.forbidden);
    _eraseNotesAt(position);
  }

  /// Erase notes at the given position
  void _eraseNotesAt(Offset position) {
    final note = _findNoteAtPosition(position);
    if (note != null && !_erasedNoteIds.contains(note.id)) {
      _erasedNoteIds.add(note.id);
      setState(() {
        _currentClip = _currentClip?.copyWith(
          notes: _currentClip!.notes.where((n) => n.id != note.id).toList(),
        );
      });
      _notifyClipUpdated();
    }
  }

  /// Stop eraser mode
  void _stopErasing() {
    if (_erasedNoteIds.isNotEmpty) {
      _commitToHistory('Delete ${_erasedNoteIds.length} notes');
    }
    _isErasing = false;
    _erasedNoteIds = {};
    setState(() => _currentCursor = SystemMouseCursors.basic);
  }
}

/// Painter for dashed vertical line (insert marker)
class _DashedLinePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  _DashedLinePainter({
    required this.color,
    this.strokeWidth = 2,
    this.dashLength = 6,
    this.gapLength = 4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    double y = 0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, (y + dashLength).clamp(0, size.height)),
        paint,
      );
      y += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.gapLength != gapLength;
  }
}
