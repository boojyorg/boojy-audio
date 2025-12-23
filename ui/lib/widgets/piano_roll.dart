import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../models/midi_note_data.dart';
import '../audio_engine.dart';
import '../services/undo_redo_manager.dart';
import '../services/commands/clip_commands.dart';

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
  static const int _defaultViewStartNote = 36; // C2
  static const int _defaultViewEndNote = 84;   // C6 (4 octaves)

  // Clip state
  MidiClipData? _currentClip;

  // UI state
  bool _isDrawingNote = false;
  MidiNoteData? _previewNote;
  Offset? _dragStart;

  // Interaction mode
  InteractionMode _currentMode = InteractionMode.draw;

  // Selection state
  MidiNoteData? _hoveredNote;
  String? _hoveredEdge; // 'left', 'right', or null
  bool _isResizing = false;
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

  // Eraser mode state (right-click drag to delete multiple notes)
  bool _isErasing = false;
  Set<String> _erasedNoteIds = {};

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

  // Global undo/redo manager
  final UndoRedoManager _undoRedoManager = UndoRedoManager();

  @override
  void initState() {
    super.initState();
    _currentClip = widget.clipData;

    // Listen for undo/redo changes to update our state
    _undoRedoManager.addListener(_onUndoRedoChanged);

    // Scroll to default view (middle of piano)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToDefaultView();
    });
  }

  @override
  void dispose() {
    _undoRedoManager.removeListener(_onUndoRedoChanged);
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
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
      onHover: _onHover,
      child: Focus(
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
                              // Listener captures right-click drag for eraser mode
                              child: Listener(
                                onPointerDown: (event) {
                                  if (event.buttons == kSecondaryMouseButton) {
                                    _startErasing(event.localPosition);
                                  }
                                },
                                onPointerMove: (event) {
                                  if (_isErasing && event.buttons == kSecondaryMouseButton) {
                                    _eraseNotesAt(event.localPosition);
                                  }
                                },
                                onPointerUp: (event) {
                                  if (_isErasing) {
                                    _stopErasing();
                                  }
                                  // Stop sustained audition when mouse released
                                  _stopAudition();
                                },
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTapDown: _onTapDown,
                                  onTapUp: (_) => _stopAudition(),
                                  onTapCancel: _stopAudition,
                                  onSecondaryTapDown: _onRightClick,
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
                                          painter: _GridPainter(
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
                                          painter: _NotePainter(
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
                                      ],
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
                  painter: _VelocityLanePainter(
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
  Widget _buildBarRuler(double totalBeats, double canvasWidth) {
    return GestureDetector(
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
            painter: _BarRulerPainter(
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
    const edgeThreshold = 6.0; // 6 pixels (FL Studio style, zoom-aware)

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

  // Handle hover for cursor feedback (smart context-aware cursors)
  void _onHover(PointerHoverEvent event) {
    // Don't update cursor during active drag operations
    if (_currentMode == InteractionMode.move || _currentMode == InteractionMode.resize) {
      return;
    }

    final position = event.localPosition;
    final hoveredNote = _findNoteAtPosition(position);
    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
    final isSliceActive = _sliceModeEnabled || isAltPressed;

    if (hoveredNote != null) {
      if (isSliceActive) {
        // Slice mode - show vertical split cursor
        setState(() {
          _currentCursor = SystemMouseCursors.verticalText; // Vertical line cursor for slicing
          _hoveredNote = hoveredNote;
          _hoveredEdge = null;
        });
      } else {
        final edge = _getEdgeAtPosition(position, hoveredNote);

        if (edge != null) {
          // Near edge - show resize cursor
          setState(() {
            _currentCursor = SystemMouseCursors.resizeLeftRight;
            _hoveredNote = hoveredNote;
            _hoveredEdge = edge;
          });
        } else {
          // On note body - show grab cursor
          setState(() {
            _currentCursor = SystemMouseCursors.grab;
            _hoveredNote = hoveredNote;
            _hoveredEdge = null;
          });
        }
      }
    } else {
      // Empty space - default cursor for note creation
      setState(() {
        _currentCursor = SystemMouseCursors.basic; // Default cursor
        _hoveredNote = null;
        _hoveredEdge = null;
      });
    }
  }

  void _onTapDown(TapDownDetails details) {
    final clickedNote = _findNoteAtPosition(details.localPosition);
    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
    final isSliceActive = _sliceModeEnabled || isAltPressed;

    if (clickedNote != null) {
      // Check if slice mode is active
      if (isSliceActive) {
        // Slice the note at click position
        final beatPosition = _getBeatAtX(details.localPosition.dx);
        _sliceNoteAt(clickedNote, beatPosition);
        return;
      }

      // Start sustained audition (will stop on mouse up)
      _startAudition(clickedNote.note, clickedNote.velocity);

      // Clear just-created tracking since we clicked on existing note
      _justCreatedNoteId = null;
    } else if (!isSliceActive) {
      // Empty space click - create note immediately
      _saveToHistory();
      final beat = _snapToGrid(_getBeatAtX(details.localPosition.dx));
      final note = _getNoteAtY(details.localPosition.dy);

      final newNote = MidiNoteData(
        note: note,
        velocity: 100,
        startTime: beat,
        duration: _lastNoteDuration,
      );

      setState(() {
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
    _dragStart = details.localPosition;
    final clickedNote = _findNoteAtPosition(details.localPosition);
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
    final isSliceActive = _sliceModeEnabled || isAltPressed;

    if (isShiftPressed && clickedNote == null) {
      // Start multi-select with shift+drag
      setState(() {
        _isSelecting = true;
        _selectionStart = details.localPosition;
        _selectionEnd = details.localPosition;
        _currentMode = InteractionMode.select;
      });
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
    } else if (clickedNote != null && !isSliceActive) {
      // Check if we're near the edge for resizing (FL Studio style)
      final edge = _getEdgeAtPosition(details.localPosition, clickedNote);

      if (edge != null) {
        // Start resizing from left or right edge
        _saveToHistory(); // Save before resizing
        setState(() {
          _isResizing = true;
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
      // Update selection rectangle
      setState(() {
        _selectionEnd = details.localPosition;
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
                final newStartTime = _snapToGrid(originalNote.startTime + deltaBeat).clamp(0.0, 64.0);
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
      MidiNoteData? resizedNote;
      setState(() {
        _currentClip = _currentClip?.copyWith(
          notes: _currentClip!.notes.map((n) {
            if (n.id == _resizingNoteId) {
              final newBeat = _snapToGrid(_getBeatAtX(details.localPosition.dx));

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
      // Apply selection rectangle
      if (_selectionStart != null && _selectionEnd != null) {
        final startBeat = _getBeatAtX(_selectionStart!.dx.clamp(0, double.infinity));
        final endBeat = _getBeatAtX(_selectionEnd!.dx.clamp(0, double.infinity));
        final startNote = _getNoteAtY(_selectionStart!.dy.clamp(0, double.infinity));
        final endNote = _getNoteAtY(_selectionEnd!.dy.clamp(0, double.infinity));

        final minBeat = startBeat < endBeat ? startBeat : endBeat;
        final maxBeat = startBeat < endBeat ? endBeat : startBeat;
        final minNote = startNote < endNote ? startNote : endNote;
        final maxNote = startNote < endNote ? endNote : startNote;

        setState(() {
          _currentClip = _currentClip?.copyWith(
            notes: _currentClip!.notes.map((note) {
              final isInRange = note.startTime >= minBeat &&
                                note.endTime <= maxBeat &&
                                note.note >= minNote &&
                                note.note <= maxNote;
              return note.copyWith(isSelected: isInRange);
            }).toList(),
          );
        });
      }

      setState(() {
        _isSelecting = false;
        _selectionStart = null;
        _selectionEnd = null;
      });
    }

    // Commit move operation to history
    if (_currentMode == InteractionMode.move) {
      final selectedCount = _currentClip?.selectedNotes.length ?? 0;
      if (selectedCount > 0) {
        _commitToHistory(selectedCount == 1 ? 'Move note' : 'Move $selectedCount notes');
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
      _isResizing = false;
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
    }
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

    // Paste at current view position (center of visible area)
    // Or use a reasonable default position
    final pasteTime = 0.0; // Paste at start for now - could be improved to use playhead

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

  /// Handle right-click on canvas (single click delete)
  void _onRightClick(TapDownDetails details) {
    final clickedNote = _findNoteAtPosition(details.localPosition);

    if (clickedNote != null) {
      // Right-clicked on a note - delete it immediately
      _saveToHistory(); // Save before deleting
      setState(() {
        _currentClip = _currentClip?.copyWith(
          notes: _currentClip!.notes.where((n) => n.id != clickedNote.id).toList(),
        );
      });
      _notifyClipUpdated();
      _commitToHistory('Delete note: ${clickedNote.noteName}');
      debugPrint('🗑️ Deleted note: ${clickedNote.noteName}');
    }
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

/// Custom painter for grid background
class _GridPainter extends CustomPainter {
  final double pixelsPerBeat;
  final double pixelsPerNote;
  final double gridDivision;
  final int maxMidiNote;
  final double totalBeats;
  final double activeBeats; // Active region boundary

  _GridPainter({
    required this.pixelsPerBeat,
    required this.pixelsPerNote,
    required this.gridDivision,
    required this.maxMidiNote,
    required this.totalBeats,
    required this.activeBeats,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // STEP 1: Draw backgrounds FIRST (so vertical lines can be drawn on top)
    for (int note = 0; note <= maxMidiNote; note++) {
      final y = (maxMidiNote - note) * pixelsPerNote;
      final isBlackKey = _isBlackKey(note);

      // Draw background color (dark theme to match DAW UI)
      final bgPaint = Paint()
        ..color = isBlackKey ? const Color(0xFF242424) : const Color(0xFF363636);

      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, pixelsPerNote),
        bgPaint,
      );

      // Draw horizontal separator line
      final linePaint = Paint()
        ..color = const Color(0xFF333333) // Subtle dark line
        ..strokeWidth = 0.5;

      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // STEP 2: Draw vertical grid lines ON TOP (so they're visible)
    // Dark theme grid colors
    final subdivisionPaint = Paint()
      ..color = const Color(0xFF404040) // Dark grey for 16th note lines
      ..strokeWidth = 1.0;

    final beatPaint = Paint()
      ..color = const Color(0xFF505050) // Medium grey for beats
      ..strokeWidth = 1.5;

    final barPaint = Paint()
      ..color = const Color(0xFF606060) // Lighter grey for bars
      ..strokeWidth = 2.5;

    // Vertical lines (beats and bars)
    for (double beat = 0; beat <= totalBeats; beat += gridDivision) {
      final x = beat * pixelsPerBeat;
      final isBar = (beat % 4.0) == 0.0; // 4/4 time
      final isBeat = (beat % 1.0) == 0.0;

      final paint = isBar ? barPaint : (isBeat ? beatPaint : subdivisionPaint);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Note: Grey shaded overlay removed per user preference
    // Orange loop end marker is drawn by _buildLoopEndMarker widget
  }

  bool _isBlackKey(int midiNote) {
    final noteInOctave = midiNote % 12;
    return [1, 3, 6, 8, 10].contains(noteInOctave);
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) {
    return pixelsPerBeat != oldDelegate.pixelsPerBeat ||
           pixelsPerNote != oldDelegate.pixelsPerNote ||
           gridDivision != oldDelegate.gridDivision ||
           totalBeats != oldDelegate.totalBeats ||
           activeBeats != oldDelegate.activeBeats;
  }
}

/// Custom painter for MIDI notes
class _NotePainter extends CustomPainter {
  final List<MidiNoteData> notes;
  final MidiNoteData? previewNote;
  final double pixelsPerBeat;
  final double pixelsPerNote;
  final int maxMidiNote;
  final Offset? selectionStart;
  final Offset? selectionEnd;

  _NotePainter({
    required this.notes,
    this.previewNote,
    required this.pixelsPerBeat,
    required this.pixelsPerNote,
    required this.maxMidiNote,
    this.selectionStart,
    this.selectionEnd,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw all notes
    for (final note in notes) {
      _drawNote(canvas, note, isSelected: note.isSelected);
    }

    // Draw preview note
    if (previewNote != null) {
      _drawNote(canvas, previewNote!, isPreview: true);
    }

    // Draw selection rectangle
    if (selectionStart != null && selectionEnd != null) {
      final rect = Rect.fromPoints(selectionStart!, selectionEnd!);

      // Fill
      final fillPaint = Paint()
        ..color = const Color(0xFF00BCD4).withValues(alpha: 0.2) // Cyan fill
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fillPaint);

      // Border
      final borderPaint = Paint()
        ..color = const Color(0xFF00BCD4) // Cyan border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(rect, borderPaint);
    }
  }

  void _drawNote(Canvas canvas, MidiNoteData note, {bool isSelected = false, bool isPreview = false}) {
    final x = note.startTime * pixelsPerBeat;
    final y = (maxMidiNote - note.note) * pixelsPerNote;
    final width = note.duration * pixelsPerBeat;
    final height = pixelsPerNote - 2; // Small gap between notes

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y + 1, width, height),
      const Radius.circular(4), // Slightly rounded corners
    );

    // Note fill - cyan theme
    final fillPaint = Paint()
      ..color = isPreview
          ? const Color(0xFF00BCD4).withValues(alpha: 0.5) // Cyan preview
          : const Color(0xFF00BCD4); // Solid cyan for notes

    canvas.drawRRect(rect, fillPaint);

    // Note border
    final borderPaint = Paint()
      ..color = isSelected
          ? Colors.white // White border when selected (visible on dark bg)
          : const Color(0xFF00838F) // Darker cyan border normally
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 2.5 : 1.5;

    canvas.drawRRect(rect, borderPaint);

    // Draw note name inside
    if (width > 30) { // Only show label if note is wide enough
      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
      );

      textPainter.text = TextSpan(
        text: note.noteName, // e.g., "G5", "D#4", "C3"
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.9), // White text on cyan background
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      );

      textPainter.layout();

      // Position label at left edge with small padding
      final textX = x + 4;
      final textY = y + (height / 2) - (textPainter.height / 2) + 1;

      textPainter.paint(canvas, Offset(textX, textY));
    }

    // Draw resize handles on selected notes (touch-friendly)
    if (isSelected && !isPreview) {
      final handlePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      const handleWidth = 6.0;
      final noteRect = Rect.fromLTWH(x, y + 1, width, height);

      // Left handle
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(noteRect.left - 1, noteRect.top, handleWidth, noteRect.height),
          const Radius.circular(2),
        ),
        handlePaint,
      );

      // Right handle
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(noteRect.right - handleWidth + 1, noteRect.top, handleWidth, noteRect.height),
          const Radius.circular(2),
        ),
        handlePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_NotePainter oldDelegate) {
    return notes != oldDelegate.notes ||
           previewNote != oldDelegate.previewNote ||
           pixelsPerBeat != oldDelegate.pixelsPerBeat ||
           pixelsPerNote != oldDelegate.pixelsPerNote ||
           selectionStart != oldDelegate.selectionStart ||
           selectionEnd != oldDelegate.selectionEnd;
  }
}


/// Painter for bar number ruler (FL Studio style)
class _BarRulerPainter extends CustomPainter {
  final double pixelsPerBeat;
  final double totalBeats;
  final double playheadPosition; // in beats

  _BarRulerPainter({
    required this.pixelsPerBeat,
    required this.totalBeats,
    required this.playheadPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    // Draw bar numbers (every 4 beats)
    final totalBars = (totalBeats / 4).ceil();
    for (int bar = 0; bar < totalBars; bar++) {
      final barStartBeat = bar * 4.0;
      final x = barStartBeat * pixelsPerBeat;

      // Bar number
      final barNumber = bar + 1; // 1-indexed
      textPainter.text = TextSpan(
        text: "$barNumber",
        style: const TextStyle(
          color: Color(0xFFE0E0E0), // Light text on dark background
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      );

      textPainter.layout();
      // Draw bar number at LEFT edge of bar (not centered)
      textPainter.paint(
        canvas,
        Offset(x + 4, 7), // 4px padding from left edge
      );

      // Draw beat ticks
      for (int beat = 0; beat < 4; beat++) {
        final beatX = (barStartBeat + beat) * pixelsPerBeat;
        final tickPaint = Paint()
          ..color = const Color(0xFF606060) // Dark grey ticks
          ..strokeWidth = 1;

        canvas.drawLine(
          Offset(beatX, size.height - 5),
          Offset(beatX, size.height),
          tickPaint,
        );
      }
    }

    // Draw playhead triangle (orange)
    if (playheadPosition >= 0 && playheadPosition <= totalBeats) {
      final playheadX = playheadPosition * pixelsPerBeat;

      final trianglePath = Path()
        ..moveTo(playheadX, size.height - 2)
        ..lineTo(playheadX - 8, 0)
        ..lineTo(playheadX + 8, 0)
        ..close();

      final playheadPaint = Paint()
        ..color = const Color(0xFFFF9800) // Orange
        ..style = PaintingStyle.fill;

      canvas.drawPath(trianglePath, playheadPaint);

      // Playhead border for definition
      final borderPaint = Paint()
        ..color = const Color(0xFFE65100) // Darker orange border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawPath(trianglePath, borderPaint);
    }
  }

  @override
  bool shouldRepaint(_BarRulerPainter oldDelegate) {
    return playheadPosition != oldDelegate.playheadPosition ||
           pixelsPerBeat != oldDelegate.pixelsPerBeat ||
           totalBeats != oldDelegate.totalBeats;
  }
}

/// Painter for velocity editing lane (Ableton-style)
class _VelocityLanePainter extends CustomPainter {
  final List<MidiNoteData> notes;
  final double pixelsPerBeat;
  final double laneHeight;
  final double totalBeats;

  _VelocityLanePainter({
    required this.notes,
    required this.pixelsPerBeat,
    required this.laneHeight,
    required this.totalBeats,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background
    final bgPaint = Paint()
      ..color = const Color(0xFF1E1E1E);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Draw horizontal grid lines at 25%, 50%, 75%, 100%
    final gridPaint = Paint()
      ..color = const Color(0xFF333333)
      ..strokeWidth = 1;

    for (var i = 1; i <= 4; i++) {
      final y = size.height * (1 - i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw vertical bar lines (every 4 beats)
    final barPaint = Paint()
      ..color = const Color(0xFF404040)
      ..strokeWidth = 1;

    for (double beat = 0; beat <= totalBeats; beat += 4) {
      final x = beat * pixelsPerBeat;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), barPaint);
    }

    // Draw velocity bars for each note
    final barFillPaint = Paint()
      ..color = const Color(0xFF00BCD4) // Cyan to match notes
      ..style = PaintingStyle.fill;

    final barBorderPaint = Paint()
      ..color = const Color(0xFF00838F) // Darker cyan border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final note in notes) {
      final x = note.startTime * pixelsPerBeat;
      final width = (note.duration * pixelsPerBeat).clamp(4.0, double.infinity);
      final barHeight = (note.velocity / 127) * laneHeight;
      final y = laneHeight - barHeight;

      // Draw velocity bar
      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 1, y, width - 2, barHeight),
        const Radius.circular(2),
      );

      canvas.drawRRect(barRect, barFillPaint);
      canvas.drawRRect(barRect, barBorderPaint);

      // Draw velocity value text for wider notes
      if (width > 25) {
        final textPainter = TextPainter(
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );

        textPainter.text = TextSpan(
          text: '${note.velocity}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        );

        textPainter.layout();
        final textX = x + (width - textPainter.width) / 2;
        final textY = y + 2;

        if (barHeight > 14) {
          textPainter.paint(canvas, Offset(textX, textY));
        }
      }
    }
  }

  @override
  bool shouldRepaint(_VelocityLanePainter oldDelegate) {
    return notes != oldDelegate.notes ||
           pixelsPerBeat != oldDelegate.pixelsPerBeat ||
           laneHeight != oldDelegate.laneHeight ||
           totalBeats != oldDelegate.totalBeats;
  }
}

