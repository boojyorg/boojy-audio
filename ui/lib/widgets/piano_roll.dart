import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../models/midi_note_data.dart';
import '../audio_engine.dart';
import '../services/undo_redo_manager.dart';
import '../services/commands/clip_commands.dart';
import 'painters/painters.dart';

/// Interaction modes for piano roll
enum InteractionMode { draw, select, move, resize }

/// Piano Roll MIDI editor widget
class PianoRoll extends StatefulWidget {
  final AudioEngine? audioEngine;
  final MidiClipData? clipData;
  final VoidCallback? onClose;
  final Function(MidiClipData)? onClipUpdated;

  const PianoRoll({
    super.key,
    this.audioEngine,
    this.clipData,
    this.onClose,
    this.onClipUpdated,
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
  final ScrollController _verticalScroll = ScrollController();

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

  // Slice mode state
  bool _sliceModeEnabled = false;

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

    // Scroll to default view (middle of piano)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToDefaultView();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _undoRedoManager.removeListener(_onUndoRedoChanged);
    _focusNode.dispose();
    _horizontalScroll.dispose();
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

  /// Toggle slice mode on/off
  void _toggleSliceMode() {
    setState(() {
      _sliceModeEnabled = !_sliceModeEnabled;
    });
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
    debugPrint('✂️ Sliced note ${note.noteName} at beat $splitBeat');
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
  void _undo() async {
    await _undoRedoManager.undo();
  }

  /// Redo last undone action - delegates to global manager
  void _redo() async {
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
    return _maxMidiNote - (y / _pixelsPerNote).floor();
  }

  double _getBeatAtX(double x) {
    return x / _pixelsPerBeat;
  }

  double _snapToGrid(double beat) {
    if (!_snapEnabled) return beat;
    return (beat / _gridDivision).floor() * _gridDivision;
  }

  void _zoomIn() {
    setState(() {
      _pixelsPerBeat = (_pixelsPerBeat * 1.2).clamp(20.0, 500.0);
    });
  }

  void _zoomOut() {
    setState(() {
      _pixelsPerBeat = (_pixelsPerBeat / 1.2).clamp(20.0, 500.0);
    });
  }

  void _toggleSnap() {
    setState(() {
      _snapEnabled = !_snapEnabled;
    });
  }

  void _changeGridDivision() {
    setState(() {
      // Cycle through: 1/4, 1/8, 1/16, 1/32
      if (_gridDivision == 0.25) {
        _gridDivision = 0.125;
      } else if (_gridDivision == 0.125) {
        _gridDivision = 0.0625;
      } else if (_gridDivision == 0.0625) {
        _gridDivision = 0.03125;
      } else {
        _gridDivision = 0.25;
      }
    });
  }

  String _getGridDivisionLabel() {
    if (_gridDivision == 0.25) return '1/16';
    if (_gridDivision == 0.125) return '1/32';
    if (_gridDivision == 0.0625) return '1/64';
    if (_gridDivision == 0.03125) return '1/128';
    return '1/16';
  }

  /// Get the loop length (active region in piano roll)
  /// This is the boundary shown as the loop end marker
  double _getLoopLength() {
    return _currentClip?.loopLength ?? 16.0; // Default 4 bars
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
          _handleKeyEvent(event);
          return KeyEventResult.handled;
        },
        child: Container(
          color: const Color(0xFF242424), // Dark background
          child: Column(
            children: [
              _buildHeader(),
              _buildPianoRollContent(),
            ],
          ),
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
          // Bar ruler row - FIXED at top (outside vertical scroll)
          Row(
            children: [
              // Spacer for piano keys width
              Container(
                width: 60,
                height: 30,
                decoration: const BoxDecoration(
                  color: Color(0xFF363636),
                  border: Border(
                    right: BorderSide(color: Color(0xFF363636), width: 1),
                    bottom: BorderSide(color: Color(0xFF363636), width: 1),
                  ),
                ),
              ),
              // Bar ruler with horizontal scroll
              Expanded(
                child: Scrollbar(
                  controller: _horizontalScroll,
                  child: SingleChildScrollView(
                    controller: _horizontalScroll,
                    scrollDirection: Axis.horizontal,
                    child: _buildBarRuler(totalBeats, canvasWidth),
                  ),
                ),
              ),
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
                        width: 60,
                        decoration: const BoxDecoration(
                          color: Color(0xFF363636),
                          border: Border(
                            right: BorderSide(color: Color(0xFF363636), width: 1),
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
                      // Grid with horizontal scroll (no separate vertical scroll)
                      Expanded(
                        child: Scrollbar(
                          controller: _horizontalScroll,
                          child: SingleChildScrollView(
                            controller: _horizontalScroll,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: canvasWidth,
                              height: canvasHeight,
                              // Listener captures right-click for context menu and Ctrl/Cmd for eraser/delete
                              child: Listener(
                                onPointerDown: (event) {
                                  if (event.buttons == kSecondaryMouseButton) {
                                    // Right-click: record position for context menu on release
                                    _rightClickStartPosition = event.localPosition;
                                    _rightClickNote = _findNoteAtPosition(event.localPosition);
                                  } else if (event.buttons == kPrimaryMouseButton) {
                                    // Left-click with Alt: prepare for delete/eraser
                                    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
                                    if (isAltPressed) {
                                      final note = _findNoteAtPosition(event.localPosition);
                                      if (note != null) {
                                        // Alt+click on note = instant delete
                                        _deleteNote(note);
                                      }
                                    }
                                  }
                                },
                                onPointerMove: (event) {
                                  if (event.buttons == kPrimaryMouseButton) {
                                    // Alt+drag = eraser mode
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
                                  // Show context menu on right-click release
                                  if (_rightClickNote != null && _rightClickStartPosition != null) {
                                    // Convert local position to global for menu positioning
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
                                  // Stop sustained audition when mouse released
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
                                    // Right-click handled by Listener above (context menu on release, eraser on drag)
                                    // Removed long-press deletion - it conflicts with hold-to-preview
                                    // Touch users can use secondary tap or swipe gestures instead
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
                                            totalBeats: totalBeats,
                                            activeBeats: activeBeats,
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
                                          ),
                                        ),
                                        // Loop end marker (draggable)
                                        _buildLoopEndMarker(activeBeats, canvasHeight),
                                        // Insert marker (blue dashed line)
                                        _buildInsertMarker(canvasHeight),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
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
        ],
      ),
    );
  }

  /// Build the velocity editing lane
  Widget _buildVelocityLane(double totalBeats, double canvasWidth) {
    return Container(
      height: _velocityLaneHeight,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          top: BorderSide(color: Color(0xFF404040), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Label area (same width as piano keys)
          Container(
            width: 60,
            height: _velocityLaneHeight,
            decoration: const BoxDecoration(
              color: Color(0xFF2A2A2A),
              border: Border(
                right: BorderSide(color: Color(0xFF404040), width: 1),
              ),
            ),
            child: const Center(
              child: Text(
                'Vel',
                style: TextStyle(
                  color: Color(0xFF808080),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
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
            debugPrint('🔄 Loop length set to ${_currentClip?.loopLength} beats');
          },
          child: Container(
            width: handleWidth,
            height: canvasHeight,
            decoration: BoxDecoration(
              // Vertical line
              border: Border(
                left: BorderSide(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.8), // Orange line
                  width: 2,
                ),
              ),
            ),
            child: Center(
              child: Container(
                width: handleWidth,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800), // Orange handle
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.drag_indicator,
                  size: 10,
                  color: Colors.white,
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
              color: const Color(0xFF2196F3), // Blue color
              strokeWidth: 2,
              dashLength: 6,
              gapLength: 4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF363636), // Dark header
        border: Border(
          bottom: BorderSide(color: Color(0xFF363636), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.piano_outlined,
            color: Color(0xFFE0E0E0), // Light icon on dark background
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Piano Roll - ${widget.clipData?.name ?? "Unnamed Clip"}',
            style: const TextStyle(
              color: Color(0xFFE0E0E0), // Light text on dark background
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),

          // Snap toggle
          _buildHeaderButton(
            icon: Icons.grid_on,
            label: 'Snap: ${_snapEnabled ? _getGridDivisionLabel() : "OFF"}',
            isActive: _snapEnabled,
            onTap: _toggleSnap,
            onLongPress: _changeGridDivision,
          ),

          const SizedBox(width: 8),

          // Slice mode toggle
          _buildHeaderButton(
            icon: Icons.content_cut,
            label: 'Slice',
            isActive: _sliceModeEnabled,
            onTap: _toggleSliceMode,
          ),

          const SizedBox(width: 8),

          // Quantize dropdown
          _buildQuantizeButton(),

          const SizedBox(width: 8),

          // Audition toggle (hear notes when creating/selecting)
          _buildHeaderButton(
            icon: _auditionEnabled ? Icons.volume_up : Icons.volume_off,
            label: 'Audition',
            isActive: _auditionEnabled,
            onTap: _toggleAudition,
          ),

          const SizedBox(width: 8),

          // Velocity lane toggle
          _buildHeaderButton(
            icon: Icons.equalizer,
            label: 'Velocity',
            isActive: _velocityLaneExpanded,
            onTap: _toggleVelocityLane,
          ),

          const SizedBox(width: 8),

          // Zoom controls
          _buildHeaderButton(
            icon: Icons.remove,
            label: 'Zoom Out',
            onTap: _zoomOut,
          ),
          const SizedBox(width: 4),
          Text(
            '${_pixelsPerBeat.toInt()}px',
            style: const TextStyle(
              color: Color(0xFFE0E0E0), // Light text
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 4),
          _buildHeaderButton(
            icon: Icons.add,
            label: 'Zoom In',
            onTap: _zoomIn,
          ),

          const SizedBox(width: 16),

          // Close button
          IconButton(
            icon: const Icon(Icons.close),
            color: const Color(0xFFE0E0E0), // Light icon
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: widget.onClose,
            tooltip: 'Close Piano Roll',
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required String label,
    bool isActive = false,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF00BCD4) : const Color(0xFF333333), // Dark grey when inactive, cyan when active
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? Colors.white : const Color(0xFFE0E0E0), // Light when inactive
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : const Color(0xFFE0E0E0), // Light when inactive
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Build quantize dropdown button
  Widget _buildQuantizeButton() {
    return PopupMenuButton<int>(
      tooltip: 'Quantize notes to grid',
      offset: const Offset(0, 40),
      color: const Color(0xFF2A2A2A),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF333333),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.align_horizontal_left,
              size: 14,
              color: Color(0xFFE0E0E0),
            ),
            SizedBox(width: 4),
            Text(
              'Quantize',
              style: TextStyle(
                color: Color(0xFFE0E0E0),
                fontSize: 11,
              ),
            ),
            SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 14,
              color: Color(0xFFE0E0E0),
            ),
          ],
        ),
      ),
      onSelected: (division) {
        _quantizeClip(division);
      },
      itemBuilder: (context) => [
        const PopupMenuItem<int>(
          value: 4,
          child: Text('1/4 Note (Quarter)', style: TextStyle(color: Colors.white)),
        ),
        const PopupMenuItem<int>(
          value: 8,
          child: Text('1/8 Note (Eighth)', style: TextStyle(color: Colors.white)),
        ),
        const PopupMenuItem<int>(
          value: 16,
          child: Text('1/16 Note (Sixteenth)', style: TextStyle(color: Colors.white)),
        ),
        const PopupMenuItem<int>(
          value: 32,
          child: Text('1/32 Note (Thirty-second)', style: TextStyle(color: Colors.white)),
        ),
      ],
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

  Widget _buildPianoKey(int midiNote) {
    final isBlackKey = _isBlackKey(midiNote);
    final noteName = _getNoteNameForKey(midiNote);
    final isC = midiNote % 12 == 0; // Only show labels for C notes

    return Container(
      height: _pixelsPerNote,
      decoration: BoxDecoration(
        // Dark theme piano keys - dark grey for black keys, medium grey for white keys
        color: isBlackKey ? const Color(0xFF242424) : const Color(0xFF303030),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFF404040), // Subtle border
            width: 0.5,
          ),
        ),
      ),
      child: Center(
        child: isC // Only show note names for C notes
            ? Text(
                noteName,
                style: TextStyle(
                  color: isBlackKey ? const Color(0xFF808080) : const Color(0xFFE0E0E0), // Light text on dark keys
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              )
            : const SizedBox.shrink(),
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

  /// Build bar number ruler with Ableton-style drag-to-zoom
  /// Click and drag vertically: up = zoom in, down = zoom out
  /// Click: place insert marker (spec v2.0)
  Widget _buildBarRuler(double totalBeats, double canvasWidth) {
    return GestureDetector(
      onTapUp: (details) {
        // Click ruler to place insert marker (spec v2.0)
        final scrollOffset = _horizontalScroll.hasClients ? _horizontalScroll.offset : 0.0;
        final xInContent = details.localPosition.dx + scrollOffset;
        final beats = xInContent / _pixelsPerBeat;
        setState(() {
          _insertMarkerBeats = beats.clamp(0.0, double.infinity);
        });
      },
      onVerticalDragStart: (details) {
        _zoomDragStartY = details.globalPosition.dy;
        _zoomStartPixelsPerBeat = _pixelsPerBeat;
      },
      onVerticalDragUpdate: (details) {
        // Calculate drag delta (negative = dragged up = zoom in)
        final deltaY = details.globalPosition.dy - _zoomDragStartY;

        // Sensitivity: ~100 pixels of drag = 2x zoom change
        // Negative deltaY (drag up) = positive zoom multiplier
        final zoomFactor = 1.0 - (deltaY / 100.0);

        setState(() {
          _pixelsPerBeat = (_zoomStartPixelsPerBeat * zoomFactor).clamp(20.0, 500.0);
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown, // Visual hint for zoom
        child: Container(
          height: 30,
          width: canvasWidth,
          decoration: const BoxDecoration(
            color: Color(0xFF363636), // Dark background
            border: Border(
              bottom: BorderSide(color: Color(0xFF363636), width: 1),
            ),
          ),
          child: CustomPaint(
            size: Size(canvasWidth, 30),
            painter: BarRulerPainter(
              pixelsPerBeat: _pixelsPerBeat,
              totalBeats: totalBeats,
              playheadPosition: 0.0, // TODO: Sync with actual playhead
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

  /// Update cursor based on current modifier key state (called when Alt/Cmd/Ctrl pressed)
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
        // Alt = delete mode
        _currentCursor = SystemMouseCursors.forbidden;
      } else if (isCtrlOrCmd) {
        // Cmd/Ctrl = duplicate mode (only meaningful when over a note, but show anyway)
        _currentCursor = SystemMouseCursors.copy;
      } else {
        // No modifier = default cursor
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

    if (hoveredNote != null) {
      if (isAltPressed) {
        // Alt held - show delete cursor
        setState(() {
          _currentCursor = SystemMouseCursors.forbidden;
        });
      } else if (_sliceModeEnabled) {
        // Slice mode (toggle button only) - show vertical split cursor
        setState(() {
          _currentCursor = SystemMouseCursors.verticalText;
        });
      } else if (isCtrlOrCmd) {
        // Cmd/Ctrl held - show copy cursor for duplicate
        setState(() {
          _currentCursor = SystemMouseCursors.copy;
        });
      } else {
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
      if (isAltPressed) {
        // Alt held - show delete cursor even on empty space (eraser mode)
        setState(() {
          _currentCursor = SystemMouseCursors.forbidden;
        });
      } else {
        // Default cursor for note creation
        setState(() {
          _currentCursor = SystemMouseCursors.basic;
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

    // Alt+click = delete (handled by Listener, but skip normal handling)
    if (isAltPressed) {
      return;
    }

    // Cmd/Ctrl+click on note = duplicate in place
    if (isCtrlOrCmd && clickedNote != null) {
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
      debugPrint('📋 Cmd+click duplicated ${clickedNote.noteName}');
      return;
    }

    if (clickedNote != null) {
      // Check if slice mode is active (toggle button only, Cmd/Ctrl is now for duplicate)
      if (_sliceModeEnabled) {
        // Slice the note at click position
        final beatPosition = _getBeatAtX(details.localPosition.dx);
        _sliceNoteAt(clickedNote, beatPosition);
        return;
      }

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
      // Single-click on empty space creates a note (FL Studio style)
      _saveToHistory();
      final beat = _snapToGrid(_getBeatAtX(details.localPosition.dx));
      final note = _getNoteAtY(details.localPosition.dy);

      final newNote = MidiNoteData(
        note: note,
        velocity: 100,
        startTime: beat,
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
      _startAudition(note, 100);
      debugPrint('🎵 Created note at beat $beat');
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
      debugPrint('🔄 Auto-extended loop to $newLoopLength beats');
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

    // Skip normal pan handling if Alt is held (eraser mode handled by Listener)
    if (isAltPressed) {
      return;
    }

    if (isShiftPressed && clickedNote == null) {
      // Shift+drag on empty = marquee select
      setState(() {
        _isSelecting = true;
        _selectionStart = details.localPosition;
        _selectionEnd = details.localPosition;
        _currentMode = InteractionMode.select;
      });
    } else if (isCtrlOrCmd && clickedNote != null) {
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
      debugPrint('📋 Started Cmd+drag duplicate of ${duplicatedNotes.length} note(s)');
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

        debugPrint('🎵 Started moving just-created note');
      }

      // Clear just-created tracking
      _justCreatedNoteId = null;
    } else if (clickedNote != null && !_sliceModeEnabled) {
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

        debugPrint('🎨 Painted note at beat $nextNoteBeat');
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
                final newNote = (originalNote.note + deltaNote).clamp(0, 127);

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
        debugPrint('📋 Cmd+drag duplicate completed ($duplicateCount notes)');
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
        debugPrint('📝 Remembered note duration: $_lastNoteDuration beats');
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
      // Escape to deselect all notes
      else if (event.logicalKey == LogicalKeyboardKey.escape) {
        _deselectAllNotes();
      }
    }
  }

  /// Deselect all notes
  void _deselectAllNotes() {
    if (_currentClip == null) return;

    final hasSelection = _currentClip!.notes.any((n) => n.isSelected);
    if (!hasSelection) {
      debugPrint('⚠️ No notes selected to deselect');
      return;
    }

    setState(() {
      _currentClip = _currentClip?.copyWith(
        notes: _currentClip!.notes.map((n) => n.copyWith(isSelected: false)).toList(),
      );
    });

    debugPrint('⎋ Deselected all notes');
  }

  /// Copy selected notes to clipboard
  void _copySelectedNotes() {
    final selectedNotes = _currentClip?.selectedNotes ?? [];
    if (selectedNotes.isEmpty) {
      debugPrint('⚠️ No notes selected to copy');
      return;
    }

    // Store copies of selected notes (deselected)
    _clipboard = selectedNotes.map((note) => note.copyWith(isSelected: false)).toList();
    debugPrint('📋 Copied ${_clipboard.length} notes to clipboard');
  }

  /// Cut selected notes (copy to clipboard, then delete)
  void _cutSelectedNotes() {
    final selectedNotes = _currentClip?.selectedNotes ?? [];
    if (selectedNotes.isEmpty) {
      debugPrint('⚠️ No notes selected to cut');
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
    debugPrint('✂️ Cut ${_clipboard.length} notes to clipboard');
  }

  /// Paste notes from clipboard
  void _pasteNotes() {
    if (_clipboard.isEmpty) {
      debugPrint('⚠️ Clipboard is empty');
      return;
    }

    if (_currentClip == null) {
      debugPrint('⚠️ No clip to paste into');
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
    debugPrint('📌 Pasted ${newNotes.length} notes');
  }

  /// Duplicate selected notes (place copies after originals)
  void _duplicateSelectedNotes() {
    final selectedNotes = _currentClip?.selectedNotes ?? [];
    if (selectedNotes.isEmpty) {
      debugPrint('⚠️ No notes selected to duplicate');
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
    debugPrint('📋 Duplicated ${duplicates.length} notes');
  }

  /// Select all notes in the current clip
  void _selectAllNotes() {
    if (_currentClip == null || _currentClip!.notes.isEmpty) {
      debugPrint('⚠️ No notes to select');
      return;
    }

    setState(() {
      _currentClip = _currentClip?.copyWith(
        notes: _currentClip!.notes.map((n) => n.copyWith(isSelected: true)).toList(),
      );
    });

    debugPrint('🎯 Selected all ${_currentClip!.notes.length} notes');
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
              Text('⌘⌫', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
              Text('⌘D', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
              Text('⌘X', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
              Text('⌘C', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
              Text('⌘V', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'quantize',
          child: Row(
            children: [
              Icon(Icons.grid_on, size: 18),
              SizedBox(width: 8),
              Text('Quantize'),
              Spacer(),
              Text('Q', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
    debugPrint('🗑️ Deleted note: ${note.noteName}');
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
    debugPrint('📋 Duplicated note: ${note.noteName}');
  }

  /// Quantize selected notes to grid
  void _quantizeSelectedNotes() {
    final selectedNotes = _currentClip?.notes.where((n) => n.isSelected).toList() ?? [];
    if (selectedNotes.isEmpty) {
      debugPrint('No notes selected for quantize');
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
    debugPrint('📐 Quantized ${selectedNotes.length} notes to grid');
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
      debugPrint('🧹 Erased note: ${note.noteName}');
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
