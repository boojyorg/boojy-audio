import 'dart:math' show pow;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/audio_clip_edit_data.dart';
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

  /// Project tempo (BPM) for warp calculations
  final double projectTempo;

  /// Callback when project tempo changes from Audio Editor
  final Function(double)? onProjectTempoChanged;

  const AudioEditor({
    super.key,
    this.audioEngine,
    this.clipData,
    this.onClose,
    this.onClipUpdated,
    this.toolMode = ToolMode.draw,
    this.onToolModeChanged,
    this.projectTempo = 120.0,
    this.onProjectTempoChanged,
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
    initFromClip(widget.clipData, projectTempo: widget.projectTempo);
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
        updateFromClip(widget.clipData, projectTempo: widget.projectTempo);
      });
    }
    // Recalculate when project tempo changes
    if (widget.projectTempo != oldWidget.projectTempo) {
      setState(() {
        _updateStretchFactor();
        // Recalculate visual beat duration (only affects warp OFF clips)
        recalculateBeatsForTempo(widget.projectTempo);
      });
      sendToAudioEngine();
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
          if (shouldZoomToFit && contentDurationBeats > 0) {
            // Calculate pixelsPerBeat so content fills the view
            // Leave a small margin (subtract 48px for zoom buttons area)
            final effectiveWidth = viewWidth - 48;
            pixelsPerBeat = effectiveWidth / contentDurationBeats;
            shouldZoomToFit = false;
          }

          return ColoredBox(
            color: colors.dark,
            child: Column(
              children: [
                // Row 2: Controls Bar (Loop, Warp, Pitch, Volume, Project BPM)
                AudioEditorControlsBar(
                  loopEnabled: loopEnabled,
                  onLoopToggle: _toggleLoop,
                  startOffsetBeats: loopStartBeats,
                  lengthBeats: loopEndBeats - loopStartBeats,
                  beatsPerBar: beatsPerBar,
                  onStartChanged: _onStartChanged,
                  onLengthChanged: _onLengthChanged,
                  // Warp controls
                  warpEnabled: editData.syncEnabled,
                  onWarpToggle: _toggleWarp,
                  warpMode: editData.warpMode,
                  onWarpModeChanged: _onWarpModeChanged,
                  originalBpm: editData.bpm,
                  onOriginalBpmChanged: _onOriginalBpmChanged,
                  projectBpm: widget.projectTempo,
                  onProjectBpmChanged: widget.onProjectTempoChanged,
                  // Pitch & Volume
                  transposeSemitones: editData.transposeSemitones,
                  onTransposeChanged: setTranspose,
                  gainDb: editData.gainDb,
                  onGainChanged: setGain,
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
                        contentBeats: contentDurationBeats, // Use full audio duration, not loop length
                        activeBeats: getLoopLength(),
                        loopEnabled: loopEnabled,
                        loopStart: loopStartBeats,
                        loopEnd: loopEndBeats,
                        beatsPerBar: beatsPerBar,
                        waveformColor: colors.accent,
                        gridLineColor: colors.divider,
                        barLineColor: colors.textMuted,
                        reversed: editData.reversed,
                        normalizeGain: _calculateVisualGain(),
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

  void _toggleLoop() {
    setState(() {
      loopEnabled = !loopEnabled;
    });
  }

  void _onStartChanged(double beats) {
    // Start controls the loop region start (like Piano Roll contentStartOffset)
    // The length stays the same, only the start position shifts
    final loopLength = loopEndBeats - loopStartBeats;
    setState(() {
      loopStartBeats = beats;
      loopEndBeats = beats + loopLength;
      editData = editData.copyWith(
        startOffsetBeats: beats,
        loopStartBeats: beats,
        loopEndBeats: beats + loopLength,
      );
    });
    notifyClipUpdated();
  }

  void _onLengthChanged(double beats) {
    // Length controls the loop region length (like Piano Roll loopLength)
    // Waveform stays the same length - only loop region changes
    setState(() {
      loopEndBeats = loopStartBeats + beats;
      editData = editData.copyWith(
        loopEndBeats: loopStartBeats + beats,
      );
    });
    notifyClipUpdated();
  }

  void _toggleWarp() {
    saveToHistory();
    final newValue = !editData.syncEnabled;
    setState(() {
      editData = editData.copyWith(syncEnabled: newValue);
      // Recalculate stretch factor when warp is toggled
      _updateStretchFactor();
    });
    notifyClipUpdated();
    sendToAudioEngine();
    commitToHistory(newValue ? 'Enable warp' : 'Disable warp');
  }

  void _onWarpModeChanged(WarpMode mode) {
    saveToHistory();
    setState(() {
      editData = editData.copyWith(warpMode: mode);
    });
    notifyClipUpdated();
    sendToAudioEngine();
    final modeName = mode == WarpMode.warp ? 'Warp' : 'Re-Pitch';
    commitToHistory('Set warp mode to $modeName');
  }

  void _onOriginalBpmChanged(double value) {
    saveToHistory();
    final clampedBpm = value.clamp(20.0, 999.0);
    setState(() {
      editData = editData.copyWith(bpm: clampedBpm);
      // Recalculate stretch factor when original BPM changes
      _updateStretchFactor();
      // Recalculate waveform beat duration (stretches/squeezes waveform display)
      recalculateBeatsForOriginalBpm(clampedBpm);
    });
    notifyClipUpdated();
    sendToAudioEngine();
    commitToHistory('Set original BPM to ${clampedBpm.toStringAsFixed(1)}');
  }

  /// Recalculate stretch factor based on warp state and tempos
  void _updateStretchFactor() {
    if (!editData.syncEnabled) {
      // Warp off - no stretching
      editData = editData.copyWith(stretchFactor: 1.0);
    } else {
      // Warp on - stretch to project tempo
      final projectBpm = widget.projectTempo;
      final clipBpm = editData.bpm;
      if (clipBpm > 0) {
        final stretch = projectBpm / clipBpm;
        editData = editData.copyWith(stretchFactor: stretch.clamp(0.25, 4.0));
      }
    }
  }

  // ============================================
  // HELPERS
  // ============================================

  /// Calculate visual gain factor for waveform display.
  /// Combines volume gain and normalize preview for real-time visual feedback.
  double _calculateVisualGain() {
    // Convert volume dB to linear gain: 10^(dB/20)
    // gainDb range: -70 to +24 dB
    double volumeGain = 1.0;
    if (editData.gainDb > -70) {
      volumeGain = pow(10, editData.gainDb / 20).toDouble();
    } else {
      volumeGain = 0.0; // -infinity = silent
    }

    // Apply normalize preview if set
    double normalizeGain = 1.0;
    if (editData.normalizeTargetDb != null) {
      normalizeGain = 1.0 + (editData.normalizeTargetDb! + 12) / 12;
    }

    return volumeGain * normalizeGain;
  }
}
