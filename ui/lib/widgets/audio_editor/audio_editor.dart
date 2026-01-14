import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/clip_data.dart';
import '../../models/tool_mode.dart';
import '../../audio_engine.dart';
import '../../theme/theme_extension.dart';
import '../../theme/app_colors.dart';
import '../painters/painters.dart';
import 'audio_editor_state.dart';
import 'audio_editor_controls_bar.dart';
import 'painters/waveform_editor_painter.dart';
import 'operations/parameter_operations.dart';

/// Audio Editor widget for editing audio clip parameters.
/// Displays waveform visualization and provides controls for
/// transpose, gain, reverse, normalize, and other audio parameters.
class AudioEditor extends StatefulWidget {
  final AudioEngine? audioEngine;
  final ClipData? clipData;
  final VoidCallback? onClose;
  final Function(ClipData)? onClipUpdated;

  /// Current tool mode (managed by parent EditorPanel)
  /// Note: Tools are greyed out in v1 but we keep the prop for consistency
  final ToolMode toolMode;

  /// Callback when tool mode changes
  final Function(ToolMode)? onToolModeChanged;

  const AudioEditor({
    super.key,
    this.audioEngine,
    this.clipData,
    this.onClose,
    this.onClipUpdated,
    this.toolMode = ToolMode.draw,
    this.onToolModeChanged,
  });

  @override
  State<AudioEditor> createState() => _AudioEditorState();
}

class _AudioEditorState extends State<AudioEditor>
    with AudioEditorStateMixin,
         ParameterOperationsMixin {
  @override
  void initState() {
    super.initState();
    initFromClip(widget.clipData);
    initScrollListeners();

    // Listen for undo/redo changes
    undoRedoManager.addListener(_onUndoRedoChanged);
  }

  @override
  void dispose() {
    undoRedoManager.removeListener(_onUndoRedoChanged);
    disposeScrollListeners();
    focusNode.dispose();
    horizontalScroll.dispose();
    rulerScroll.dispose();
    loopBarScroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AudioEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.clipData != oldWidget.clipData) {
      setState(() {
        updateFromClip(widget.clipData);
      });
    }
  }

  void _onUndoRedoChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (currentClip == null) {
      return _buildEmptyState(colors);
    }

    return Focus(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Capture view width for zoom calculations
          viewWidth = constraints.maxWidth - 80 - 48; // Subtract corners

          return ColoredBox(
            color: colors.dark,
            child: Column(
              children: [
                // Row 2: Controls Bar
                AudioEditorControlsBar(
                  loopEnabled: loopEnabled,
                  startOffsetBeats: editData.startOffsetBeats,
                  lengthBeats: editData.lengthBeats,
                  beatsPerBar: beatsPerBar,
                  beatUnit: beatUnit,
                  onLoopToggle: _onLoopToggle,
                  onStartChanged: _onStartChanged,
                  onLengthChanged: _onLengthChanged,
                  onBeatsPerBarChanged: _onBeatsPerBarChanged,
                  onBeatUnitChanged: _onBeatUnitChanged,
                  // Tempo
                  bpm: editData.bpm,
                  syncEnabled: editData.syncEnabled,
                  stretchFactor: editData.stretchFactor,
                  onBpmChanged: _onBpmChanged,
                  onSyncToggle: _onSyncToggle,
                  onStretchChanged: _onStretchChanged,
                  // Pitch
                  transposeSemitones: editData.transposeSemitones,
                  fineCents: editData.fineCents,
                  onTransposeChanged: setTranspose,
                  onFineChanged: setFineCents,
                  // Level
                  gainDb: editData.gainDb,
                  isStereo: editData.isStereo,
                  onGainChanged: setGain,
                  // Actions
                  reversed: editData.reversed,
                  normalizeTargetDb: editData.normalizeTargetDb,
                  onReverseToggle: toggleReverse,
                  onNormalizeChanged: setNormalize,
                ),

                // Main content area
                Expanded(
                  child: Column(
                    children: [
                      // Row 3: Loop Region Bar
                      _buildLoopBarRow(colors),

                      // Row 4: Timeline/Ruler
                      _buildRulerRow(colors),

                      // Row 5: Waveform Area
                      Expanded(child: _buildWaveformArea(colors)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BoojyColors colors) {
    return ColoredBox(
      color: colors.dark,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.audio_file,
              size: 64,
              color: colors.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'Audio Editor',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select an audio clip to start editing',
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Row 3: Loop Region Bar
  Widget _buildLoopBarRow(BoojyColors colors) {
    final totalBeats = calculateTotalBeats();

    return SizedBox(
      height: 20,
      child: Row(
        children: [
          // Left corner (aligned with waveform left margin)
          SizedBox(
            width: 80,
            child: Container(color: colors.dark),
          ),

          // Loop bar (scrollable, synced)
          Expanded(
            child: GestureDetector(
              onHorizontalDragStart: _onLoopBarDragStart,
              onHorizontalDragUpdate: _onLoopBarDragUpdate,
              onHorizontalDragEnd: _onLoopBarDragEnd,
              child: MouseRegion(
                onHover: _onLoopBarHover,
                onExit: (_) => setState(() => loopBarHoverBeat = null),
                cursor: _getLoopBarCursor(),
                child: SingleChildScrollView(
                  controller: loopBarScroll,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: SizedBox(
                    width: totalBeats * pixelsPerBeat,
                    child: CustomPaint(
                      painter: LoopBarPainter(
                        pixelsPerBeat: pixelsPerBeat,
                        totalBeats: totalBeats,
                        loopEnabled: loopEnabled,
                        loopStart: loopStartBeats,
                        loopEnd: loopEndBeats,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Right corner (aligned with zoom controls)
          SizedBox(
            width: 48,
            child: Container(color: colors.dark),
          ),
        ],
      ),
    );
  }

  /// Row 4: Timeline/Ruler
  Widget _buildRulerRow(BoojyColors colors) {
    final totalBeats = calculateTotalBeats();

    return SizedBox(
      height: 20,
      child: Row(
        children: [
          // Left corner
          SizedBox(
            width: 80,
            child: Container(color: colors.dark),
          ),

          // Ruler (scrollable, synced)
          Expanded(
            child: GestureDetector(
              onVerticalDragStart: _onZoomDragStart,
              onVerticalDragUpdate: _onZoomDragUpdate,
              child: SingleChildScrollView(
                controller: rulerScroll,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: totalBeats * pixelsPerBeat,
                  child: CustomPaint(
                    painter: BarRulerPainter(
                      pixelsPerBeat: pixelsPerBeat,
                      totalBeats: totalBeats,
                      playheadPosition: 0, // TODO: Connect to actual playhead
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Zoom controls
          SizedBox(
            width: 48,
            child: Container(
              color: colors.dark,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildZoomButton(Icons.remove, zoomOut, colors),
                  _buildZoomButton(Icons.add, zoomIn, colors),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onTap, BoojyColors colors) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 14,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// Row 5: Waveform Area
  Widget _buildWaveformArea(BoojyColors colors) {
    final totalBeats = calculateTotalBeats();
    final waveformPeaks = currentClip?.waveformPeaks ?? [];

    return Row(
      children: [
        // Left margin (placeholder for future controls)
        SizedBox(
          width: 80,
          child: Container(
            color: colors.dark,
          ),
        ),

        // Waveform area (scrollable)
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Capture height before entering SingleChildScrollView
              final availableHeight = constraints.maxHeight;

              return SingleChildScrollView(
                controller: horizontalScroll,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: totalBeats * pixelsPerBeat,
                  height: availableHeight,
                  child: CustomPaint(
                    size: Size(totalBeats * pixelsPerBeat, availableHeight),
                    painter: WaveformEditorPainter(
                      peaks: waveformPeaks,
                      pixelsPerBeat: pixelsPerBeat,
                      totalBeats: totalBeats,
                      activeBeats: getLoopLength(),
                      loopEnabled: loopEnabled,
                      loopStart: loopStartBeats,
                      loopEnd: loopEndBeats,
                      beatsPerBar: beatsPerBar,
                      waveformColor: colors.accent,
                      gridLineColor: colors.divider,
                      barLineColor: colors.textMuted,
                      reversed: editData.reversed,
                      normalizeGain: _calculateNormalizeGain(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Right margin
        SizedBox(
          width: 48,
          child: Container(color: colors.dark),
        ),
      ],
    );
  }

  // ============================================
  // KEYBOARD HANDLING
  // ============================================

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      // Undo/Redo
      final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed;

      if (isCtrlOrCmd && event.logicalKey == LogicalKeyboardKey.keyZ) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          undoRedoManager.redo();
        } else {
          undoRedoManager.undo();
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // ============================================
  // LOOP BAR INTERACTION
  // ============================================

  MouseCursor _getLoopBarCursor() {
    if (loopBarHoverBeat == null) return SystemMouseCursors.basic;

    const handleWidth = 8.0;
    final handleWidthBeats = handleWidth / pixelsPerBeat;

    if ((loopBarHoverBeat! - loopStartBeats).abs() < handleWidthBeats) {
      return SystemMouseCursors.resizeLeftRight;
    }
    if ((loopBarHoverBeat! - loopEndBeats).abs() < handleWidthBeats) {
      return SystemMouseCursors.resizeLeftRight;
    }
    if (loopBarHoverBeat! > loopStartBeats && loopBarHoverBeat! < loopEndBeats) {
      return SystemMouseCursors.move;
    }

    return SystemMouseCursors.basic;
  }

  void _onLoopBarHover(PointerHoverEvent event) {
    final beat = (event.localPosition.dx + loopBarScroll.offset) / pixelsPerBeat;
    setState(() {
      loopBarHoverBeat = beat;
    });
  }

  void _onLoopBarDragStart(DragStartDetails details) {
    final beat = (details.localPosition.dx + loopBarScroll.offset) / pixelsPerBeat;
    const handleWidth = 8.0;
    final handleWidthBeats = handleWidth / pixelsPerBeat;

    if ((beat - loopStartBeats).abs() < handleWidthBeats) {
      loopMarkerDrag = LoopMarkerDrag.start;
    } else if ((beat - loopEndBeats).abs() < handleWidthBeats) {
      loopMarkerDrag = LoopMarkerDrag.end;
    } else if (beat > loopStartBeats && beat < loopEndBeats) {
      loopMarkerDrag = LoopMarkerDrag.middle;
      loopDragStartBeat = beat;
    } else {
      // Click outside loop: create new loop
      isCreatingLoop = true;
      loopMarkerDrag = LoopMarkerDrag.end;
      setState(() {
        loopStartBeats = _snapToGrid(beat);
        loopEndBeats = loopStartBeats;
      });
    }
  }

  void _onLoopBarDragUpdate(DragUpdateDetails details) {
    final beat = (details.localPosition.dx + loopBarScroll.offset) / pixelsPerBeat;
    final snappedBeat = _snapToGrid(beat);

    setState(() {
      switch (loopMarkerDrag) {
        case LoopMarkerDrag.start:
          loopStartBeats = snappedBeat.clamp(0, loopEndBeats - 0.25);
          break;
        case LoopMarkerDrag.end:
          loopEndBeats = snappedBeat.clamp(loopStartBeats + 0.25, calculateTotalBeats());
          break;
        case LoopMarkerDrag.middle:
          final delta = beat - loopDragStartBeat;
          final length = loopEndBeats - loopStartBeats;
          var newStart = _snapToGrid(loopStartBeats + delta);
          newStart = newStart.clamp(0, calculateTotalBeats() - length);
          loopStartBeats = newStart;
          loopEndBeats = newStart + length;
          loopDragStartBeat = beat;
          break;
        case null:
          break;
      }
    });
  }

  void _onLoopBarDragEnd(DragEndDetails details) {
    loopMarkerDrag = null;
    isCreatingLoop = false;

    // Update edit data with new loop region
    _updateLoopRegion();
  }

  void _updateLoopRegion() {
    setState(() {
      editData = editData.copyWith(
        loopStartBeats: loopStartBeats,
        loopEndBeats: loopEndBeats,
        loopEnabled: loopEnabled,
      );
    });
    notifyClipUpdated();
  }

  double _snapToGrid(double beat) {
    const gridDivision = 0.25; // 1/16th note
    return (beat / gridDivision).round() * gridDivision;
  }

  // ============================================
  // ZOOM DRAG (Ableton-style)
  // ============================================

  void _onZoomDragStart(DragStartDetails details) {
    zoomDragStartY = details.localPosition.dy;
    zoomStartPixelsPerBeat = pixelsPerBeat;
    zoomAnchorBeat = (details.localPosition.dx + rulerScroll.offset) / pixelsPerBeat;
    zoomAnchorLocalX = details.localPosition.dx;
  }

  void _onZoomDragUpdate(DragUpdateDetails details) {
    final deltaY = details.localPosition.dy - zoomDragStartY;
    final zoomFactor = 1.0 + (deltaY / 100);

    setState(() {
      final maxZoom = calculateMaxPixelsPerBeat();
      final minZoom = calculateMinPixelsPerBeat();
      pixelsPerBeat = (zoomStartPixelsPerBeat * zoomFactor).clamp(minZoom, maxZoom);

      // Adjust scroll to keep anchor beat under cursor
      if (horizontalScroll.hasClients) {
        final newOffset = zoomAnchorBeat * pixelsPerBeat - zoomAnchorLocalX;
        horizontalScroll.jumpTo(newOffset.clamp(0, horizontalScroll.position.maxScrollExtent));
      }
    });
  }

  // ============================================
  // CONTROLS BAR CALLBACKS
  // ============================================

  void _onLoopToggle(bool enabled) {
    setState(() {
      loopEnabled = enabled;
      editData = editData.copyWith(loopEnabled: enabled);
    });
    notifyClipUpdated();
  }

  void _onStartChanged(double beats) {
    setState(() {
      editData = editData.copyWith(startOffsetBeats: beats);
    });
    notifyClipUpdated();
  }

  void _onLengthChanged(double beats) {
    setState(() {
      editData = editData.copyWith(lengthBeats: beats);
    });
    notifyClipUpdated();
  }

  void _onBeatsPerBarChanged(int value) {
    setState(() {
      beatsPerBar = value;
      editData = editData.copyWith(beatsPerBar: value);
    });
    notifyClipUpdated();
  }

  void _onBeatUnitChanged(int value) {
    setState(() {
      beatUnit = value;
      editData = editData.copyWith(beatUnit: value);
    });
    notifyClipUpdated();
  }

  void _onBpmChanged(double value) {
    setState(() {
      editData = editData.copyWith(bpm: value);
    });
    notifyClipUpdated();
    sendToAudioEngine();
  }

  void _onSyncToggle(bool enabled) {
    setState(() {
      editData = editData.copyWith(syncEnabled: enabled);
    });
    notifyClipUpdated();
    sendToAudioEngine();
  }

  void _onStretchChanged(double value) {
    setState(() {
      editData = editData.copyWith(stretchFactor: value);
    });
    notifyClipUpdated();
    sendToAudioEngine();
  }

  // ============================================
  // HELPERS
  // ============================================

  /// Calculate visual gain factor for normalize preview
  double _calculateNormalizeGain() {
    if (editData.normalizeTargetDb == null) return 1.0;
    // Convert dB difference to linear gain for visual scaling
    // This is a rough approximation for visual feedback
    final targetDb = editData.normalizeTargetDb!;
    return 1.0 + (targetDb + 12) / 12; // Range: 0.0 to 2.0
  }
}
