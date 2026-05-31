// ignore_for_file: avoid_positional_boolean_parameters
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';
import '../theme/animation_constants.dart';
import '../theme/app_colors.dart';
import '../theme/boojy_icons.dart';
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
        return true;
      // Drop tool labels + compact the readouts (BPM suffix) as soon as the bar
      // is tighter than comfortable, so it fits at fixed size by shedding labels
      // rather than scaling or clipping.
      case TransportDensity.compact:
      case TransportDensity.tight:
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

  /// Compact the LCD readouts ("120 BPM" → "120", Tap → narrow). One stage
  /// later than [showLabels], so the tool names shed first.
  bool get compactReadouts {
    switch (this) {
      case TransportDensity.comfortable:
      case TransportDensity.compact:
        return false;
      case TransportDensity.tight:
      case TransportDensity.iconsOnly:
      case TransportDensity.compressed:
      case TransportDensity.minimum:
        return true;
    }
  }
}

/// Compute density from available width.
/// Approximate preferred content width at comfortable = ~620px.
TransportDensity _computeDensity(double availableWidth) {
  // Width at/above which the full labelled layout fits comfortably; below this
  // the bar sheds labels (never scales). A margin over the measured labelled
  // content width so "comfortable" only triggers when labels genuinely fit.
  const preferredWidth = 700.0;
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

  /// True when a separate macOS title strip is drawn above the bar (it hosts the
  /// traffic lights), so the bar no longer needs to inset its left group to
  /// clear them — the wordmark can sit at the true left edge.
  final bool hasTitleStrip;

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

  /// Fired when the time-signature drag gesture starts/ends, so the parent can
  /// coalesce the whole drag into a single undo step.
  final VoidCallback? onTimeSignatureDragStart;
  final VoidCallback? onTimeSignatureDragEnd;

  final bool isLoading;

  // Engine status (for status pill)
  final bool isEngineReady;
  final int? sampleRate;
  final double? latencyMs;
  final String? audioOutputDevice;

  // Add track callbacks
  final VoidCallback? onAddMidiTrack;
  final VoidCallback? onAddAudioTrack;

  /// Active top-bar layout variant (dev "UI Labs" A/B). Drives the readout
  /// layout, the bar height, and (for C) the two-row structure.
  final TopBarVariant topBarVariant;

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
    this.hasTitleStrip = false,
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
    this.onTimeSignatureDragStart,
    this.onTimeSignatureDragEnd,
    this.isLoading = false,
    this.isEngineReady = false,
    this.sampleRate,
    this.latencyMs,
    this.audioOutputDevice,
    this.onAddMidiTrack,
    this.onAddAudioTrack,
    this.topBarVariant = TopBarVariant.inline,
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

  /// macOS hides its native title bar (see WindowTitleService), so the bar
  /// becomes the top chrome: it insets to clear the traffic lights and provides
  /// a drag region for moving the window.
  bool get _replacesTitleBar =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Extra floor on macOS so the left group is wide enough to fully clear the
    // traffic lights (78px) even when the sidebar is collapsed. When a title
    // strip hosts the lights above the bar, that clearance is unnecessary.
    final needsTrafficLightClearance =
        _replacesTitleBar && !widget.hasTitleStrip;
    final leftMinWidth = needsTrafficLightClearance ? 214.0 : 200.0;

    // C splits the bar into two rows; A/B/D keep the single-row layout.
    final body = widget.topBarVariant == TopBarVariant.twoRow
        ? _buildTwoRowBody(colors, leftMinWidth)
        : _buildSingleRowBody(colors, leftMinWidth);

    return Container(
      height: widget.topBarVariant.barHeight,
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
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Window-drag region for the empty parts of the bar (macOS, native
          // title hidden). Sits beneath the controls; interactive widgets and
          // the divider handles claim their own gestures, empty gaps fall
          // through to here.
          if (_replacesTitleBar) const DragToMoveArea(child: SizedBox.expand()),
          body,
        ],
      ),
    );
  }

  /// A/B/D — the standard single-row bar: left group · centre clusters · right
  /// group, with the sidebar/mixer resize handles aligned to the panels below.
  Widget _buildSingleRowBody(BoojyColors colors, double leftMinWidth) {
    return Row(
      children: [
        // === LEFT GROUP: constrained to sidebar width ===
        SizedBox(
          width: math.max(widget.dividers.sidebarWidth, leftMinWidth),
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
    );
  }

  /// C — two-row bar. Row 1 keeps the brand/chrome plus the centred project
  /// title, and preserves the resize handles + sidebar/mixer column alignment.
  /// Row 2 carries the transport · readout · modifier clusters, grouped and
  /// centred (the cleanest grouping, at ~2× the single-row height).
  Widget _buildTwoRowBody(BoojyColors colors, double leftMinWidth) {
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              SizedBox(
                width: math.max(widget.dividers.sidebarWidth, leftMinWidth),
                child: _buildLeftGroup(colors),
              ),
              _buildSidebarHandle(colors),
              Expanded(child: Center(child: _buildCentredTitle(colors))),
              _buildMixerHandle(colors),
              SizedBox(
                width: widget.dividers.mixerWidth,
                child: _buildRightGroup(colors),
              ),
            ],
          ),
        ),
        Container(height: 1, color: colors.divider),
        Expanded(child: _buildSecondRow(colors)),
      ],
    );
  }

  /// Centred project title for C's row 1 — its natural home, since the row has
  /// the horizontal space the single-row variants don't. IgnorePointer so it
  /// never blocks a window drag in the empty middle.
  Widget _buildCentredTitle(BoojyColors colors) {
    return IgnorePointer(
      child: Text(
        widget.projectName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.textMuted,
          fontSize: BT.fontLabel,
          fontWeight: FontWeight.w500,
        ),
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

          // Fixed: ▲(22)+gap(12)+gap(12)+undo(25)+gap(4)+redo(25)+gap(8)+toggle(27)
          const fixedWidth = 135.0;
          const maxAudiClip = 77.5;
          const nameComfortWidth = 120.0;

          // macOS hides the native title bar, so the bar runs under the traffic
          // lights — push the logo right to clear them (the 16px base gutter
          // plus this extra, ~78px total). Bounded so the fixed controls always
          // fit; the left-group floor in build() keeps it at the full clearance
          // in the common collapsed-sidebar case. Off-macOS, or when a title
          // strip hosts the lights above the bar, this is 0.
          final extraLeftInset = (_replacesTitleBar && !widget.hasTitleStrip)
              ? math.max(0.0, math.min(78.0, available - 119.0) - 16.0)
              : 0.0;

          // Shrink priority: 1) spacer  2) audi clip  3) name truncate
          final flexSpace = available - fixedWidth - extraLeftInset;
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
              // Traffic-light clearance (macOS, native title hidden; 0 elsewhere).
              SizedBox(width: extraLeftInset),

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
    // Nudge the whole wordmark up ~2px so its optical centre lines up with the
    // smaller siblings (project name, undo/redo) in the centre-aligned row.
    return Transform.translate(
      offset: const Offset(0, -2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ▲ = the "A": a filled equilateral triangle that doubles as the
          // Settings button (carries the brand accent and hover-scales, exactly
          // as the old blue dot did).
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) {
              if (!_logoHovered) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _logoHovered = true);
                });
              }
            },
            onExit: (_) {
              if (_logoHovered) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _logoHovered = false);
                });
              }
            },
            child: Tooltip(
              message: 'Settings',
              child: GestureDetector(
                onTap: () => widget.fileMenu.onAppSettings?.call(),
                child: AnimatedScale(
                  scale: _logoHovered ? AnimationConstants.hoverScale : 1.0,
                  duration: AnimationConstants.hoverDuration,
                  curve: Curves.easeInOut,
                  child: Transform.translate(
                    // Baseline nudge in px (Offset(0, dy), positive = down).
                    offset: Offset.zero,
                    child: CustomPaint(
                      // Equilateral: height = base * √3/2. ~10% larger than the
                      // first cut so it reads at the wordmark's weight.
                      size: const Size(22, 19.05),
                      painter: _LogoTrianglePainter(colors.accent),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          // "udio" wordmark in the UI font (Inter). Clips gracefully when the bar
          // narrows — the same shrink-priority slot the old "Audi" lockup used.
          ClipRect(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: audiClipWidth),
              child: Text(
                'udio',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: BT.weightSemiBold,
                  color: colors.textPrimary,
                  letterSpacing: -0.5,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // CENTRE GROUP
  // ============================================

  Widget _buildCentreGroup(BoojyColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final density = _computeDensity(constraints.maxWidth);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: BT.sm),
          child: Row(
            // Clusters grouped together and centered (small fixed gaps),
            // instead of spread to the edges with Spacers.
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildModifiersWell(colors, density),
              SizedBox(width: density.clusterGap),
              _buildTransportWell(colors, density),
              SizedBox(width: density.clusterGap),
              // Well 3: Readouts — layout chosen by the UI Labs variant. Fixed
              // size; the density ladder sheds labels (tools → icons,
              // "BPM"/"Tap") before the bar would overflow.
              _buildReadoutWell(
                colors,
                compactReadouts: density.compactReadouts,
                wGap: density.withinGap,
              ),
            ],
          ),
        );
      },
    );
  }

  /// C — row 2: transport · readout · modifiers, grouped and centred (the
  /// review's preferred two-row ordering, transport-first). Reuses the same
  /// density ladder and well builders as the single-row centre group.
  Widget _buildSecondRow(BoojyColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final density = _computeDensity(constraints.maxWidth);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: BT.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTransportWell(colors, density),
              SizedBox(width: density.clusterGap),
              _buildReadoutWell(
                colors,
                compactReadouts: density.compactReadouts,
                wGap: density.withinGap,
              ),
              SizedBox(width: density.clusterGap),
              _buildModifiersWell(colors, density),
            ],
          ),
        );
      },
    );
  }

  /// Modifier cluster (loop · snap · metronome). Extracted so both the
  /// single-row centre group and C's row 2 can compose it in either order.
  Widget _buildModifiersWell(BoojyColors colors, TransportDensity density) {
    final showLabels = density.showLabels;
    final wGap = density.withinGap;
    return _ClusterWell(
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
            showLabel: showLabels,
            onToggle: widget.transport.onMetronomeToggle,
            onCountInChanged: widget.onCountInChanged,
          ),
        ],
      ),
    );
  }

  /// Transport cluster (play/pause · stop · record). Extracted alongside
  /// [_buildModifiersWell] so C's row 2 can reorder the clusters.
  Widget _buildTransportWell(BoojyColors colors, TransportDensity density) {
    final wGap = density.withinGap;
    // Transport buttons are slightly larger (32px) for visual hierarchy.
    final transportBtnSize = math.max(density.transportButtonSize, 32.0);
    return _ClusterWell(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularToggleButton(
            icon: widget.isPlaying ? BI.pause : BI.play,
            enabled:
                widget.canPlay || widget.isRecording || widget.isCountingIn,
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
            tooltip: widget.isPlaying ? 'Pause (Space)' : 'Play (Space)',
            size: transportBtnSize,
            iconSize: BT.iconLg,
          ),
          SizedBox(width: wGap),
          CircularToggleButton(
            icon: BI.stop,
            enabled:
                widget.canPlay || widget.isRecording || widget.isCountingIn,
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
          // MIDI Capture button removed (v0.2.1) — backend logic retained
        ],
      ),
    );
  }

  /// Well 3 — the position / tempo / signature readouts. The dev "UI Labs"
  /// variant chooses the layout: [TopBarVariant.inline] keeps the one-row
  /// readout with the position promoted to a hero size; [TopBarVariant.lcd]
  /// groups it into a bordered LCD panel with tempo/sig as dim satellites
  /// beneath (the taller bar gives the vertical room).
  Widget _buildReadoutWell(
    BoojyColors colors, {
    required bool compactReadouts,
    required double wGap,
  }) {
    final tapTempo = TapTempoPill(
      tempo: widget.tempo,
      onTempoChanged: widget.onTempoChanged,
      mode: compactReadouts ? ButtonDisplayMode.narrow : ButtonDisplayMode.wide,
    );
    final tempo = TempoDisplay(
      tempo: widget.tempo,
      onTempoChanged: widget.onTempoChanged,
      compact: compactReadouts,
    );
    final signature = SignatureDropdown(
      beatsPerBar: widget.beatsPerBar,
      beatUnit: widget.beatUnit,
      onChanged: widget.onTimeSignatureChanged,
      onDragStart: widget.onTimeSignatureDragStart,
      onDragEnd: widget.onTimeSignatureDragEnd,
    );

    switch (widget.topBarVariant) {
      case TopBarVariant.inline:
      case TopBarVariant.twoRow:
      case TopBarVariant.arrangementPinned:
        // A (also C's row 2 and D's compact bar) — one row, position promoted
        // to the hero readout. For D the bigger readout also lives pinned in
        // the arrangement; this inline copy stays as the in-bar reference.
        return _ClusterWell(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PositionDisplay(
                playheadPosition: widget.playheadPosition,
                tempo: widget.tempo,
                beatsPerBar: widget.beatsPerBar,
                onPositionChanged: widget.transport.onPositionChanged,
                scale: 1.25,
              ),
              SizedBox(width: wGap + BT.xs),
              tapTempo,
              SizedBox(width: wGap),
              tempo,
              SizedBox(width: wGap),
              signature,
            ],
          ),
        );
      case TopBarVariant.lcd:
        // B — bordered LCD panel: hero position over dim tempo/sig satellites.
        // Horizontal-only padding (no _ClusterWell) so the panel gets the full
        // bar height.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: BT.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              tapTempo,
              SizedBox(width: wGap + BT.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.darkest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: colors.accent.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PositionDisplay(
                      playheadPosition: widget.playheadPosition,
                      tempo: widget.tempo,
                      beatsPerBar: widget.beatsPerBar,
                      onPositionChanged: widget.transport.onPositionChanged,
                      scale: 1.3,
                      chromeless: true,
                    ),
                    const SizedBox(height: 1),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        tempo,
                        SizedBox(width: wGap + BT.xs),
                        signature,
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
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

          // (+) Add track — accent circle
          if (widget.isEngineReady)
            _AddTrackButton(
              onAddMidiTrack: widget.onAddMidiTrack,
              onAddAudioTrack: widget.onAddAudioTrack,
            ),

          if (widget.isEngineReady) const SizedBox(width: 10),

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

/// Spacing-only container for transport bar cluster grouping.
/// No border or background — spacing alone defines the groups.
class _ClusterWell extends StatelessWidget {
  final Widget child;

  const _ClusterWell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BT.xs, vertical: BT.xs),
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
                BI.help,
                size: BT.iconLg,
                color: isHovered ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Accent-colored circular (+) button that opens a dropdown for adding tracks.
class _AddTrackButton extends StatefulWidget {
  final VoidCallback? onAddMidiTrack;
  final VoidCallback? onAddAudioTrack;

  const _AddTrackButton({this.onAddMidiTrack, this.onAddAudioTrack});

  @override
  State<_AddTrackButton> createState() => _AddTrackButtonState();
}

class _AddTrackButtonState extends State<_AddTrackButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Tooltip(
      message: 'Add Track',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (!_isHovered) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isHovered = true);
            });
          }
        },
        onExit: (_) {
          if (_isHovered) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isHovered = false);
            });
          }
        },
        child: PopupMenuButton<String>(
          tooltip: 'Add Track',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          position: PopupMenuPosition.under,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: colors.divider),
          ),
          color: colors.darkest,
          elevation: 8,
          onSelected: (value) {
            if (value == 'midi') {
              widget.onAddMidiTrack?.call();
            } else if (value == 'audio') {
              widget.onAddAudioTrack?.call();
            }
          },
          itemBuilder: (menuContext) => [
            PopupMenuItem<String>(
              value: 'midi',
              height: 36,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(BI.piano, size: 14, color: colors.textMuted),
                  const SizedBox(width: 8),
                  Text(
                    'MIDI Track',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: BT.fontLabel,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'audio',
              height: 36,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(BI.waveform, size: 14, color: colors.textMuted),
                  const SizedBox(width: 8),
                  Text(
                    'Audio Track',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: BT.fontLabel,
                    ),
                  ),
                ],
              ),
            ),
          ],
          child: Icon(
            BI.addCircle,
            size: 20,
            color: _isHovered ? colors.textPrimary : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Filled equilateral triangle used as the "A" in the ▲udio wordmark.
class _LogoTrianglePainter extends CustomPainter {
  const _LogoTrianglePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final path = Path()
      ..moveTo(size.width / 2, 0) // apex (top centre)
      ..lineTo(size.width, size.height) // bottom right
      ..lineTo(0, size.height) // bottom left
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LogoTrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}
