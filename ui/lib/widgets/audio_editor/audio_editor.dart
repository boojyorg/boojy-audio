import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/clip_data.dart';
import '../../models/tool_mode.dart';
import '../../audio_engine.dart';
import '../../theme/theme_extension.dart';
import '../../theme/app_colors.dart';
import '../shared/editors/unified_nav_bar.dart';
import '../shared/editors/nav_bar_with_zoom.dart';
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
          // Capture view width for zoom calculations (full width, no margins)
          viewWidth = constraints.maxWidth;

          // Auto-zoom to fit content on first load
          if (shouldZoomToFit && editData.lengthBeats > 0) {
            // Calculate pixelsPerBeat so content fills the view
            // Leave a small margin (subtract 48px for zoom buttons area)
            final effectiveWidth = viewWidth - 48;
            pixelsPerBeat = effectiveWidth / editData.lengthBeats;
            shouldZoomToFit = false;
          }

          return ColoredBox(
            color: colors.dark,
            child: Column(
              children: [
                // Row 2: Controls Bar (5 essential controls)
                AudioEditorControlsBar(
                  startOffsetBeats: editData.startOffsetBeats,
                  lengthBeats: editData.lengthBeats,
                  beatsPerBar: beatsPerBar,
                  onStartChanged: _onStartChanged,
                  onLengthChanged: _onLengthChanged,
                  transposeSemitones: editData.transposeSemitones,
                  onTransposeChanged: setTranspose,
                  gainDb: editData.gainDb,
                  onGainChanged: setGain,
                  bpm: editData.bpm,
                  onBpmChanged: _onBpmChanged,
                ),

                // Main content area
                Expanded(
                  child: Column(
                    children: [
                      // Unified navigation bar (loop region + bar numbers + zoom controls)
                      _buildNavBar(colors),

                      // Waveform Area
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

  /// Unified navigation bar (loop region + bar numbers + zoom controls)
  /// Matches Piano Roll's UnifiedNavBar exactly
  Widget _buildNavBar(BoojyColors colors) {
    final totalBeats = calculateTotalBeats();

    return NavBarWithZoom(
      scrollController: loopBarScroll,
      onZoomIn: zoomIn,
      onZoomOut: zoomOut,
      height: 24.0,
      child: UnifiedNavBar(
        config: UnifiedNavBarConfig(
          pixelsPerBeat: pixelsPerBeat,
          totalBeats: totalBeats,
          loopEnabled: loopEnabled,
          loopStart: loopStartBeats,
          loopEnd: loopEndBeats,
          insertMarkerPosition: null, // No insert marker for audio editor
          playheadPosition: null, // TODO: Connect to actual playhead
        ),
        callbacks: UnifiedNavBarCallbacks(
          onHorizontalScroll: _handleNavBarScroll,
          onZoom: _handleNavBarZoom,
          onPlayheadSet: null, // No playhead control for audio editor
          onPlayheadDrag: null,
          onLoopRegionChanged: _handleLoopRegionChanged,
        ),
        scrollController: loopBarScroll,
        height: 24.0,
      ),
    );
  }

  void _handleNavBarScroll(double delta) {
    if (!horizontalScroll.hasClients) return;
    final newOffset = (horizontalScroll.offset + delta).clamp(
      0.0,
      horizontalScroll.position.maxScrollExtent,
    );
    horizontalScroll.jumpTo(newOffset);
  }

  void _handleNavBarZoom(double factor, double anchorBeat) {
    final maxZoom = calculateMaxPixelsPerBeat();
    final minZoom = calculateMinPixelsPerBeat();
    final newPixelsPerBeat = (pixelsPerBeat * factor).clamp(minZoom, maxZoom);

    if (newPixelsPerBeat == pixelsPerBeat) return;

    setState(() {
      pixelsPerBeat = newPixelsPerBeat;
    });

    // Adjust scroll to keep anchor beat in place
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!horizontalScroll.hasClients) return;
      final newAnchorX = anchorBeat * newPixelsPerBeat;
      final viewportCenter = viewWidth / 2;
      final newScroll = (newAnchorX - viewportCenter).clamp(
        0.0,
        horizontalScroll.position.maxScrollExtent,
      );
      horizontalScroll.jumpTo(newScroll);
    });
  }

  void _handleLoopRegionChanged(double start, double end) {
    setState(() {
      loopStartBeats = start;
      loopEndBeats = end;
      editData = editData.copyWith(
        loopStartBeats: start,
        loopEndBeats: end,
      );
    });
    notifyClipUpdated();
  }

  /// Row 5: Waveform Area
  Widget _buildWaveformArea(BoojyColors colors) {
    final totalBeats = calculateTotalBeats();
    final waveformPeaks = currentClip?.waveformPeaks ?? [];

    return Row(
      children: [
        // Waveform area (scrollable, full width - zoom controls overlay the nav bar)
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Capture height before entering SingleChildScrollView
              final availableHeight = constraints.maxHeight;

              return Listener(
                onPointerSignal: (event) {
                  // Scroll wheel/trackpad = horizontal scroll
                  if (event is PointerScrollEvent) {
                    _handleNavBarScroll(event.scrollDelta.dy);
                  }
                },
                child: SingleChildScrollView(
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
                        contentBeats: editData.lengthBeats,
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
                ),
              );
            },
          ),
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
  // CONTROLS BAR CALLBACKS
  // ============================================

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

  void _onBpmChanged(double value) {
    setState(() {
      editData = editData.copyWith(bpm: value);
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
