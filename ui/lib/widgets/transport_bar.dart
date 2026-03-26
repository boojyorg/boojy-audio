// ignore_for_file: avoid_positional_boolean_parameters
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/animation_constants.dart';
import '../theme/app_colors.dart';
import '../theme/theme_extension.dart';
import '../theme/tokens.dart';
import '../state/ui_layout_state.dart';
import 'shared/button_hover_mixin.dart';
import 'shared/circular_toggle_button.dart';
import 'shared/pill_toggle_button.dart';
import 'transport_bar/signature_dropdown.dart';
import 'transport_bar/tempo_controls.dart';
import 'transport_bar/snap_split_button.dart';
import 'transport_bar/metronome_split_button.dart';
import 'transport_bar/file_menu_button.dart';

import 'transport_bar/loop_split_button.dart';
import 'transport_bar/position_display.dart';
import 'transport_bar/record_controls.dart';
import 'transport_bar/status_pill.dart';
import 'transport_bar/transport_bar_models.dart';

export 'transport_bar/transport_bar_models.dart';

/// Responsive density levels for the centre group.
/// Determined by comparing content width to available width.
enum TransportDensity {
  comfortable, // Full spacing, labels, full-size buttons
  compact, // Reduced cluster gaps
  tight, // Minimal gaps
  iconsOnly, // Drop text labels from split buttons
  compressed, // Shrink LCD padding + button sizes
  minimum, // Everything at minimum size
}

extension TransportDensityValues on TransportDensity {
  double get clusterGap {
    switch (this) {
      case TransportDensity.comfortable:
        return 16.0;
      case TransportDensity.compact:
        return 10.0;
      case TransportDensity.tight:
        return 6.0;
      case TransportDensity.iconsOnly:
        return 4.0;
      case TransportDensity.compressed:
        return 3.0;
      case TransportDensity.minimum:
        return 2.0;
    }
  }

  double get withinGap {
    switch (this) {
      case TransportDensity.comfortable:
        return 4.0;
      case TransportDensity.compact:
        return 3.0;
      case TransportDensity.tight:
        return 2.0;
      case TransportDensity.iconsOnly:
        return 2.0;
      case TransportDensity.compressed:
        return 1.0;
      case TransportDensity.minimum:
        return 1.0;
    }
  }

  bool get showLabels {
    switch (this) {
      case TransportDensity.comfortable:
      case TransportDensity.compact:
      case TransportDensity.tight:
        return true;
      case TransportDensity.iconsOnly:
      case TransportDensity.compressed:
      case TransportDensity.minimum:
        return false;
    }
  }

  double get transportButtonSize {
    switch (this) {
      case TransportDensity.comfortable:
      case TransportDensity.compact:
      case TransportDensity.tight:
      case TransportDensity.iconsOnly:
        return 30.0;
      case TransportDensity.compressed:
        return 26.0;
      case TransportDensity.minimum:
        return 24.0;
    }
  }
}

/// Compute density from available width.
/// Approximate preferred content width at comfortable = ~620px.
TransportDensity _computeDensity(double availableWidth) {
  const preferredWidth = 620.0;
  final overflow = preferredWidth - availableWidth;

  if (overflow <= 0) return TransportDensity.comfortable;
  if (overflow <= 40) return TransportDensity.compact;
  if (overflow <= 80) return TransportDensity.tight;
  if (overflow <= 150) return TransportDensity.iconsOnly;
  if (overflow <= 220) return TransportDensity.compressed;
  return TransportDensity.minimum;
}

/// Transport control bar for play/pause/stop/record controls
/// Layout: LEFT GROUP | CENTRE GROUP (expanded) | RIGHT GROUP
class TransportBar extends StatefulWidget {
  // Grouped callback objects
  final FileMenuCallbacks fileMenu;
  final TransportCallbacks transport;
  final PanelCallbacks panels;
  final DividerState dividers;

  // Playback state
  final double playheadPosition;
  final bool isPlaying;
  final bool canPlay;
  final bool isRecording;
  final bool isCountingIn;
  final bool metronomeEnabled;
  final bool virtualPianoEnabled;
  final double tempo;
  final Function(double)? onTempoChanged;
  final Function(int)? onCountInChanged;
  final int countInBars;

  // Count-in ring timer data
  final int countInBeat;
  final double countInProgress;

  // Project name
  final String projectName;
  final bool hasProject;

  // Panel visibility state
  final bool libraryVisible;
  final bool mixerVisible;
  final bool editorVisible;
  final bool pianoVisible;

  // Undo/Redo state
  final bool canUndo;
  final bool canRedo;
  final bool hasArmedTracks;
  final String? undoDescription;
  final String? redoDescription;

  // Snap control
  final SnapValue arrangementSnap;
  final Function(SnapValue)? onSnapChanged;

  // Loop playback
  final bool loopPlaybackEnabled;

  // Punch in/out
  final bool punchInEnabled;
  final bool punchOutEnabled;

  // Time signature
  final int beatsPerBar;
  final int beatUnit;
  final Function(int beatsPerBar, int beatUnit)? onTimeSignatureChanged;

  final bool isLoading;

  // MIDI capture state
  final bool midiCaptureHasEvents;

  // Engine status (for status pill)
  final bool isEngineReady;
  final int? sampleRate;
  final double? latencyMs;
  final String? audioOutputDevice;

  const TransportBar({
    super.key,
    this.fileMenu = const FileMenuCallbacks(),
    this.transport = const TransportCallbacks(),
    this.panels = const PanelCallbacks(),
    this.dividers = const DividerState(),
    required this.playheadPosition,
    this.isPlaying = false,
    this.canPlay = false,
    this.isRecording = false,
    this.isCountingIn = false,
    this.metronomeEnabled = true,
    this.virtualPianoEnabled = false,
    this.tempo = 120.0,
    this.onTempoChanged,
    this.onCountInChanged,
    this.countInBars = 1,
    this.countInBeat = 0,
    this.countInProgress = 0.0,
    this.projectName = 'Untitled',
    this.hasProject = false,
    this.libraryVisible = true,
    this.mixerVisible = true,
    this.editorVisible = true,
    this.pianoVisible = false,
    this.canUndo = false,
    this.canRedo = false,
    this.hasArmedTracks = true,
    this.undoDescription,
    this.redoDescription,
    this.arrangementSnap = SnapValue.bar,
    this.onSnapChanged,
    this.loopPlaybackEnabled = false,
    this.punchInEnabled = false,
    this.punchOutEnabled = false,
    this.beatsPerBar = 4,
    this.beatUnit = 4,
    this.onTimeSignatureChanged,
    this.isLoading = false,
    this.midiCaptureHasEvents = false,
    this.isEngineReady = false,
    this.sampleRate,
    this.latencyMs,
    this.audioOutputDevice,
  });

  @override
  State<TransportBar> createState() => _TransportBarState();
}

class _TransportBarState extends State<TransportBar> {
  bool _logoHovered = false;
  bool _sidebarHandleHovered = false;
  bool _sidebarHandleDragging = false;
  bool _mixerHandleHovered = false;
  bool _mixerHandleDragging = false;

  void _onLeftNotifierChanged() {
    if (mounted) setState(() {});
  }

  void _onRightNotifierChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.dividers.leftDividerNotifier?.addListener(_onLeftNotifierChanged);
    widget.dividers.rightDividerNotifier?.addListener(_onRightNotifierChanged);
  }

  @override
  void didUpdateWidget(TransportBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dividers.leftDividerNotifier !=
        widget.dividers.leftDividerNotifier) {
      oldWidget.dividers.leftDividerNotifier?.removeListener(
        _onLeftNotifierChanged,
      );
      widget.dividers.leftDividerNotifier?.addListener(_onLeftNotifierChanged);
    }
    if (oldWidget.dividers.rightDividerNotifier !=
        widget.dividers.rightDividerNotifier) {
      oldWidget.dividers.rightDividerNotifier?.removeListener(
        _onRightNotifierChanged,
      );
      widget.dividers.rightDividerNotifier?.addListener(
        _onRightNotifierChanged,
      );
    }
  }

  @override
  void dispose() {
    widget.dividers.leftDividerNotifier?.removeListener(_onLeftNotifierChanged);
    widget.dividers.rightDividerNotifier?.removeListener(
      _onRightNotifierChanged,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: colors.dark,
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, 2),
            blurRadius: 8,
            color: Colors.black.withValues(alpha: 0.3),
          ),
        ],
      ),
      child: Row(
        children: [
          // === LEFT GROUP: constrained to sidebar width (min 150px) ===
          SizedBox(
            width: math.max(widget.dividers.sidebarWidth, 200),
            child: _buildLeftGroup(colors),
          ),

          // === LEFT DIVIDER (aligned with content divider below) ===
          _buildSidebarHandle(colors),

          // === CENTRE GROUP (expanded) ===
          Expanded(child: _buildCentreGroup(colors)),

          // === RIGHT DIVIDER (aligned with mixer divider below) ===
          _buildMixerHandle(colors),

          // === RIGHT GROUP: constrained to mixer width ===
          SizedBox(
            width: widget.dividers.mixerWidth,
            child: _buildRightGroup(colors),
          ),
        ],
      ),
    );
  }

  void _setSidebarHandleActive(bool hovered, bool dragging) {
    setState(() {
      _sidebarHandleHovered = hovered;
      _sidebarHandleDragging = dragging;
    });
    widget.dividers.leftDividerNotifier?.value = hovered || dragging;
  }

  void _setMixerHandleActive(bool hovered, bool dragging) {
    setState(() {
      _mixerHandleHovered = hovered;
      _mixerHandleDragging = dragging;
    });
    widget.dividers.rightDividerNotifier?.value = hovered || dragging;
  }

  Widget _buildDividerHandle({
    required BoojyColors colors,
    required bool isActive,
    required Function(double) onDrag,
    required VoidCallback onDoubleClick,
    required void Function(bool hovered, bool dragging) setActive,
    required bool isHovered,
    required bool isDragging,
    VoidCallback? onDragStart,
    VoidCallback? onDragEnd,
  }) {
    return GestureDetector(
      onPanStart: (_) {
        setActive(isHovered, true);
        onDragStart?.call();
      },
      onPanUpdate: (details) => onDrag(details.delta.dx),
      onPanEnd: (_) {
        setActive(isHovered, false);
        onDragEnd?.call();
      },
      onDoubleTap: onDoubleClick,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setActive(true, isDragging),
        onExit: (_) => setActive(false, isDragging),
        child: Container(
          width: 4,
          color: isActive ? colors.accent : colors.dark,
          child: isActive
              ? null
              : Center(
                  child: SizedBox(
                    width: 1,
                    height: double.infinity,
                    child: ColoredBox(color: colors.divider),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildSidebarHandle(BoojyColors colors) {
    final isActive =
        _sidebarHandleHovered ||
        _sidebarHandleDragging ||
        (widget.dividers.leftDividerNotifier?.value ?? false);

    return _buildDividerHandle(
      colors: colors,
      isActive: isActive,
      onDrag: (delta) => widget.dividers.onSidebarDividerDrag?.call(delta),
      onDoubleClick: () => widget.dividers.onSidebarDividerDoubleClick?.call(),
      setActive: _setSidebarHandleActive,
      isHovered: _sidebarHandleHovered,
      isDragging: _sidebarHandleDragging,
      onDragStart: widget.dividers.onSidebarDividerDragStart,
      onDragEnd: widget.dividers.onSidebarDividerDragEnd,
    );
  }

  Widget _buildMixerHandle(BoojyColors colors) {
    final isActive =
        _mixerHandleHovered ||
        _mixerHandleDragging ||
        (widget.dividers.rightDividerNotifier?.value ?? false);

    return _buildDividerHandle(
      colors: colors,
      isActive: isActive,
      onDrag: (delta) => widget.dividers.onMixerDividerDrag?.call(delta),
      onDoubleClick: () => widget.dividers.onMixerDividerDoubleClick?.call(),
      setActive: _setMixerHandleActive,
      isHovered: _mixerHandleHovered,
      isDragging: _mixerHandleDragging,
      onDragStart: widget.dividers.onMixerDividerDragStart,
      onDragEnd: widget.dividers.onMixerDividerDragEnd,
    );
  }

  // ============================================
  // LEFT GROUP
  // ============================================

  Widget _buildLeftGroup(BoojyColors colors) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth;

          // Fixed: O(19)+gap(12)+gap(12)+undo(25)+gap(4)+redo(25)+gap(8)+toggle(27)
          const fixedWidth = 132.0;
          const maxAudiClip = 77.5;
          const nameComfortWidth = 120.0;

          // Shrink priority: 1) spacer  2) audi clip  3) name truncate
          final flexSpace = available - fixedWidth;
          final audiClipWidth = math.min(
            maxAudiClip,
            math.max(0.0, flexSpace - nameComfortWidth),
          );
          final spacerWidth = math.max(
            0.0,
            flexSpace - nameComfortWidth - audiClipWidth,
          );

          return Row(
            children: [
              _buildLogo(colors, audiClipWidth: audiClipWidth),

              const SizedBox(width: 12),

              // Project name — only flexible item, truncates with ellipsis
              Flexible(
                child: FileMenuButton(
                  projectName: widget.projectName,
                  hasProject: widget.hasProject,
                  mode: ButtonDisplayMode.wide,
                  onNewProject: widget.fileMenu.onNewProject,
                  onOpenProject: widget.fileMenu.onOpenProject,
                  onSaveProject: widget.fileMenu.onSaveProject,
                  onSaveProjectAs: widget.fileMenu.onSaveProjectAs,
                  onRenameProject: widget.fileMenu.onRenameProject,
                  onSaveNewVersion: widget.fileMenu.onSaveNewVersion,
                  onExportAudio: widget.fileMenu.onExportAudio,
                  onExportMp3: widget.fileMenu.onExportMp3,
                  onExportWav: widget.fileMenu.onExportWav,
                  onExportMidi: widget.fileMenu.onExportMidi,
                  onCloseProject: widget.fileMenu.onCloseProject,
                ),
              ),

              const SizedBox(width: 12),

              // Undo button
              _SvgIconButton(
                assetPath: 'assets/icons/undo.svg',
                enabled: widget.canUndo,
                onTap: widget.transport.onUndo,
                tooltip: widget.canUndo && widget.undoDescription != null
                    ? 'Undo: ${widget.undoDescription} (⌘Z)'
                    : 'Undo (⌘Z)',
              ),

              const SizedBox(width: 4),

              // Redo button
              _SvgIconButton(
                assetPath: 'assets/icons/redo.svg',
                enabled: widget.canRedo,
                onTap: widget.transport.onRedo,
                tooltip: widget.canRedo && widget.redoDescription != null
                    ? 'Redo: ${widget.redoDescription} (⇧⌘Z)'
                    : 'Redo (⇧⌘Z)',
              ),

              // Spacer between redo and toggle — shrinks first
              SizedBox(width: 5 + spacerWidth),

              // Sidebar toggle [|]
              _PanelToggleButton(
                assetPath: 'assets/icons/sidebar_toggle.svg',
                isActive: widget.libraryVisible,
                onTap: widget.panels.onToggleLibrary,
                tooltip: widget.libraryVisible
                    ? 'Hide Library'
                    : 'Show Library',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLogo(BoojyColors colors, {required double audiClipWidth}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // "Audi" text: always rendered, smoothly clipped to available width
        ClipRect(
          child: SizedBox(
            width: audiClipWidth,
            child: OverflowBox(
              alignment: AlignmentDirectional.centerStart,
              maxWidth: double.infinity,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SvgPicture.asset(
                  'assets/images/boojy_audio_audi.svg',
                  height: 30,
                ),
              ),
            ),
          ),
        ),
        // Blue circle "O" — settings button
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _logoHovered = true),
          onExit: (_) => setState(() => _logoHovered = false),
          child: Tooltip(
            message: 'Settings',
            child: GestureDetector(
              onTap: () => widget.fileMenu.onAppSettings?.call(),
              child: AnimatedScale(
                scale: _logoHovered ? 1.05 : 1.0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeInOut,
                child: Container(
                  width: 21,
                  height: 21,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================
  // CENTRE GROUP
  // ============================================

  Widget _buildCentreGroup(BoojyColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final density = _computeDensity(constraints.maxWidth);
        final cGap = density.clusterGap;
        final wGap = density.withinGap;
        final showLabels = density.showLabels;
        final btnSize = density.transportButtonSize;

        // Transport buttons are slightly larger (32px) for visual hierarchy
        final transportBtnSize = math.max(btnSize, 32.0);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: BT.sm),
          child: Row(
            children: [
              // ── Well 1: Modifiers — LEFT-aligned ──
              _ClusterWell(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LoopSplitButton(
                      loopEnabled: widget.loopPlaybackEnabled,
                      punchInEnabled: widget.punchInEnabled,
                      punchOutEnabled: widget.punchOutEnabled,
                      showLabel: showLabels,
                      onLoopToggle: widget.transport.onLoopPlaybackToggle,
                      onPunchInToggle: widget.transport.onPunchInToggle,
                      onPunchOutToggle: widget.transport.onPunchOutToggle,
                    ),
                    SizedBox(width: wGap),
                    SnapSplitButton(
                      value: widget.arrangementSnap,
                      onChanged: widget.onSnapChanged,
                      mode: ButtonDisplayMode.wide,
                      isIconOnly: !showLabels,
                    ),
                    SizedBox(width: wGap),
                    MetronomeSplitButton(
                      isActive: widget.metronomeEnabled,
                      countInBars: widget.countInBars,
                      onToggle: widget.transport.onMetronomeToggle,
                      onCountInChanged: widget.onCountInChanged,
                    ),
                  ],
                ),
              ),

              SizedBox(width: cGap),
              const Spacer(),

              // ── Well 2: Transport — CENTERED ──
              _ClusterWell(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularToggleButton(
                      icon: widget.isPlaying ? Icons.pause : Icons.play_arrow,
                      enabled:
                          widget.canPlay ||
                          widget.isRecording ||
                          widget.isCountingIn,
                      enabledColor: widget.isPlaying
                          ? const Color(0xFFF97316)
                          : const Color(0xFF22C55E),
                      onPressed: () {
                        if (widget.isRecording || widget.isCountingIn) {
                          widget.transport.onPauseRecording?.call();
                        } else if (widget.isPlaying) {
                          widget.transport.onPause?.call();
                        } else {
                          widget.transport.onPlay?.call();
                        }
                      },
                      tooltip: widget.isPlaying
                          ? 'Pause (Space)'
                          : 'Play (Space)',
                      size: transportBtnSize,
                      iconSize: BT.iconLg,
                    ),
                    SizedBox(width: wGap),
                    CircularToggleButton(
                      icon: Icons.stop,
                      enabled:
                          widget.canPlay ||
                          widget.isRecording ||
                          widget.isCountingIn,
                      enabledColor: const Color(0xFFF97316),
                      onPressed: () {
                        if (widget.isRecording || widget.isCountingIn) {
                          widget.transport.onStopRecording?.call();
                        } else {
                          widget.transport.onStop?.call();
                        }
                      },
                      tooltip: 'Stop',
                      size: transportBtnSize,
                      iconSize: BT.iconLg,
                    ),
                    SizedBox(width: wGap),
                    RecordButton(
                      isRecording: widget.isRecording,
                      isCountingIn: widget.isCountingIn,
                      countInBars: widget.countInBars,
                      countInBeat: widget.countInBeat,
                      countInProgress: widget.countInProgress,
                      beatsPerBar: widget.beatsPerBar,
                      onPressed:
                          (widget.hasArmedTracks ||
                              widget.isRecording ||
                              widget.isCountingIn)
                          ? widget.transport.onRecord
                          : null,
                      onCountInChanged: widget.onCountInChanged,
                      size: transportBtnSize,
                    ),
                    SizedBox(width: wGap),
                    _MidiCaptureButton(
                      hasEvents: widget.midiCaptureHasEvents,
                      isRecording: widget.isRecording || widget.isCountingIn,
                      onTap: widget.transport.onCaptureMidi,
                    ),
                  ],
                ),
              ),

              const Spacer(),
              SizedBox(width: cGap),

              // ── Well 3: Readouts — RIGHT-aligned ──
              _ClusterWell(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PositionDisplay(
                      playheadPosition: widget.playheadPosition,
                      tempo: widget.tempo,
                      beatsPerBar: widget.beatsPerBar,
                      onPositionChanged: widget.transport.onPositionChanged,
                    ),
                    SizedBox(width: wGap + BT.xs),
                    TapTempoPill(
                      tempo: widget.tempo,
                      onTempoChanged: widget.onTempoChanged,
                      mode: ButtonDisplayMode.wide,
                    ),
                    SizedBox(width: wGap),
                    TempoDisplay(
                      tempo: widget.tempo,
                      onTempoChanged: widget.onTempoChanged,
                    ),
                    SizedBox(width: wGap),
                    SignatureDropdown(
                      beatsPerBar: widget.beatsPerBar,
                      beatUnit: widget.beatUnit,
                      onChanged: widget.onTimeSignatureChanged,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================
  // RIGHT GROUP
  // ============================================

  Widget _buildRightGroup(BoojyColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Mixer toggle (mirrored sidebar icon)
          _PanelToggleButton(
            assetPath: 'assets/icons/sidebar_toggle.svg',
            isActive: widget.mixerVisible,
            onTap: widget.panels.onToggleMixer,
            tooltip: widget.mixerVisible ? 'Hide Mixer' : 'Show Mixer',
            mirrored: true,
          ),

          const SizedBox(width: 8),

          // Status pill [✓ Ready]
          StatusPill(
            isReady: widget.isEngineReady,
            sampleRate: widget.sampleRate,
            latencyMs: widget.latencyMs,
            audioOutputDevice: widget.audioOutputDevice,
          ),

          const Spacer(),

          // Help button — far right
          _HelpButton(onTap: widget.panels.onHelpPressed),
        ],
      ),
    );
  }
}

// ============================================
// HELPER WIDGETS
// ============================================

/// Recessed "well" container for transport bar cluster grouping.
/// Uses darkest bg with divider border to create visual separation
/// against the dark chrome background.
class _ClusterWell extends StatelessWidget {
  final Widget child;

  const _ClusterWell({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: BT.sm, vertical: BT.xs),
      decoration: BoxDecoration(
        color: colors.darkest,
        borderRadius: BT.borderMd,
        border: Border.all(color: colors.divider, width: 1),
      ),
      child: child,
    );
  }
}

/// SVG icon button for undo/redo
class _SvgIconButton extends StatefulWidget {
  final String assetPath;
  final bool enabled;
  final VoidCallback? onTap;
  final String tooltip;

  const _SvgIconButton({
    required this.assetPath,
    required this.enabled,
    this.onTap,
    required this.tooltip,
  });

  @override
  State<_SvgIconButton> createState() => _SvgIconButtonState();
}

class _SvgIconButtonState extends State<_SvgIconButton> with ButtonHoverMixin {
  @override
  double get hoverScale => AnimationConstants.subtleHoverScale;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final opacity = widget.enabled ? 1.0 : 0.3;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: widget.enabled ? handleHoverEnter : null,
        onExit: widget.enabled ? handleHoverExit : null,
        child: GestureDetector(
          onTapDown: widget.enabled ? handleTapDown : null,
          onTapUp: widget.enabled
              ? (details) {
                  handleTapUp(details);
                  widget.onTap?.call();
                }
              : null,
          onTapCancel: widget.enabled ? handleTapCancel : null,
          child: AnimatedScale(
            scale: widget.enabled ? scale : 1.0,
            duration: AnimationConstants.pressDuration,
            curve: AnimationConstants.standardCurve,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 5),
              decoration: BoxDecoration(
                color: isHovered ? colors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Opacity(
                opacity: opacity,
                child: SvgPicture.asset(
                  widget.assetPath,
                  width: 18,
                  height: 18,
                  colorFilter: ColorFilter.mode(
                    colors.textPrimary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Panel toggle button using SVG sidebar icon
class _PanelToggleButton extends StatefulWidget {
  final String assetPath;
  final bool isActive;
  final VoidCallback? onTap;
  final String tooltip;
  final bool mirrored;

  const _PanelToggleButton({
    required this.assetPath,
    required this.isActive,
    this.onTap,
    required this.tooltip,
    this.mirrored = false,
  });

  @override
  State<_PanelToggleButton> createState() => _PanelToggleButtonState();
}

class _PanelToggleButtonState extends State<_PanelToggleButton>
    with ButtonHoverMixin {
  @override
  double get hoverScale => AnimationConstants.subtleHoverScale;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconOpacity = widget.isActive ? 1.0 : 0.5;

    Widget svgIcon = SvgPicture.asset(
      widget.assetPath,
      width: 18,
      height: 18,
      colorFilter: ColorFilter.mode(
        isHovered ? colors.textPrimary : colors.textMuted,
        BlendMode.srcIn,
      ),
    );

    if (widget.mirrored) {
      svgIcon = Transform.flip(flipX: true, child: svgIcon);
    }

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: handleHoverEnter,
        onExit: handleHoverExit,
        child: GestureDetector(
          onTapDown: handleTapDown,
          onTapUp: (details) {
            handleTapUp(details);
            widget.onTap?.call();
          },
          onTapCancel: handleTapCancel,
          child: AnimatedScale(
            scale: scale,
            duration: AnimationConstants.pressDuration,
            curve: AnimationConstants.standardCurve,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isHovered ? colors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Opacity(opacity: iconOpacity, child: svgIcon),
            ),
          ),
        ),
      ),
    );
  }
}

/// Help button with consistent sizing.
class _HelpButton extends StatefulWidget {
  final VoidCallback? onTap;

  const _HelpButton({this.onTap});

  @override
  State<_HelpButton> createState() => _HelpButtonState();
}

class _HelpButtonState extends State<_HelpButton> with ButtonHoverMixin {
  @override
  double get hoverScale => AnimationConstants.subtleHoverScale;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Tooltip(
      message: 'Keyboard Shortcuts (?)',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: handleHoverEnter,
        onExit: handleHoverExit,
        child: GestureDetector(
          onTapDown: handleTapDown,
          onTapUp: (details) {
            handleTapUp(details);
            widget.onTap?.call();
          },
          onTapCancel: handleTapCancel,
          child: AnimatedScale(
            scale: scale,
            duration: AnimationConstants.pressDuration,
            curve: AnimationConstants.standardCurve,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isHovered ? colors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Icons.help_outline,
                size: 18,
                color: isHovered ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// MIDI Capture button — captures recent MIDI input into a clip.
/// Shows corner-bracket icon. Dims when recording, brightens when buffer has events.
class _MidiCaptureButton extends StatefulWidget {
  final bool hasEvents;
  final bool isRecording;
  final VoidCallback? onTap;

  const _MidiCaptureButton({
    required this.hasEvents,
    required this.isRecording,
    this.onTap,
  });

  @override
  State<_MidiCaptureButton> createState() => _MidiCaptureButtonState();
}

class _MidiCaptureButtonState extends State<_MidiCaptureButton>
    with ButtonHoverMixin {
  @override
  double get hoverScale => AnimationConstants.subtleHoverScale;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isEnabled = widget.hasEvents && !widget.isRecording;
    final opacity = widget.isRecording ? 0.3 : (widget.hasEvents ? 1.0 : 0.5);

    return Tooltip(
      message: 'Capture MIDI — saves what you just played',
      child: MouseRegion(
        cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: isEnabled ? handleHoverEnter : null,
        onExit: isEnabled ? handleHoverExit : null,
        child: GestureDetector(
          onTapDown: isEnabled ? handleTapDown : null,
          onTapUp: isEnabled
              ? (details) {
                  handleTapUp(details);
                  widget.onTap?.call();
                }
              : null,
          onTapCancel: isEnabled ? handleTapCancel : null,
          child: AnimatedScale(
            scale: isEnabled ? scale : 1.0,
            duration: AnimationConstants.pressDuration,
            curve: AnimationConstants.standardCurve,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: isHovered ? colors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: CustomPaint(
                  size: const Size(26, 26),
                  painter: _CaptureIconPainter(
                    color: widget.hasEvents
                        ? colors.textSecondary
                        : colors.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the MIDI capture icon — four corner brackets forming a frame.
class _CaptureIconPainter extends CustomPainter {
  final Color color;

  _CaptureIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    const inset = 6.0;
    const len = 5.0;
    final right = size.width - inset;
    final bottom = size.height - inset;

    // Top-left corner
    canvas.drawLine(
      const Offset(inset, inset + len),
      const Offset(inset, inset),
      paint,
    );
    canvas.drawLine(
      const Offset(inset, inset),
      const Offset(inset + len, inset),
      paint,
    );

    // Top-right corner
    canvas.drawLine(Offset(right - len, inset), Offset(right, inset), paint);
    canvas.drawLine(Offset(right, inset), Offset(right, inset + len), paint);

    // Bottom-left corner
    canvas.drawLine(Offset(inset, bottom - len), Offset(inset, bottom), paint);
    canvas.drawLine(Offset(inset, bottom), Offset(inset + len, bottom), paint);

    // Bottom-right corner
    canvas.drawLine(Offset(right - len, bottom), Offset(right, bottom), paint);
    canvas.drawLine(Offset(right, bottom - len), Offset(right, bottom), paint);
  }

  @override
  bool shouldRepaint(_CaptureIconPainter oldDelegate) {
    return color != oldDelegate.color;
  }
}
