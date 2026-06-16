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
import '../utils/track_colors.dart';
import 'shared/add_track_button.dart';
import 'shared/boojy_wordmark.dart';
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

  /// Play/stop/record circle size. Slightly larger than the split buttons
  /// (32px) for visual hierarchy, but it DOES shed with the ladder — a fixed
  /// floor here once let the circles dominate the bar at narrow widths (H2).
  double get transportCircleSize {
    switch (this) {
      case TransportDensity.comfortable:
      case TransportDensity.compact:
      case TransportDensity.tight:
      case TransportDensity.iconsOnly:
        return 32.0;
      case TransportDensity.compressed:
        return 28.0;
      case TransportDensity.minimum:
        return 24.0;
    }
  }

  /// Whether the tempo + signature readouts render at all. Shed last, at
  /// [TransportDensity.minimum] — position + transport survive to the end.
  bool get showTempoSig {
    switch (this) {
      case TransportDensity.comfortable:
      case TransportDensity.compact:
      case TransportDensity.tight:
      case TransportDensity.iconsOnly:
      case TransportDensity.compressed:
        return true;
      case TransportDensity.minimum:
        return false;
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

/// Fixed width of the left and right chrome rails in the single-row bar. Both
/// sides are pinned to the SAME width on purpose: with equal rails flanking an
/// Expanded centre, the transport cluster lands on the true window midpoint
/// regardless of the sidebar/mixer panel widths below — and the left chrome
/// (▲udio wordmark + undo/redo + library toggle) never reflows when the Library
/// is collapsed. Wide enough to hold the full left group without clipping the
/// wordmark; the right group (mixer toggle + help) right-aligns within it.
const double _kRailWidth = 320.0;

/// Compute density from available width.
/// The fully-labelled centre group (modifiers + transport + readouts) measures
/// ~700px now that the readouts carry the BPM split button and uniform boxes.
TransportDensity _computeDensity(double availableWidth) {
  // Width at/above which the full labelled layout fits comfortably; below this
  // the bar sheds labels (never scales). Held a touch above the measured
  // labelled content width (~700px) so "comfortable" only triggers with genuine
  // slack — without the margin the readouts sit a sub-pixel over the edge at the
  // boundary and the signature box reports a "RIGHT OVERFLOWED BY 0" sliver.
  const preferredWidth = 724.0;
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
  final VoidCallback? onTempoDragStart;
  final VoidCallback? onTempoDragEnd;
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
  final Function(int beatsPerBar, int beatUnit)? onTimeSignatureChanged;

  /// Fired when the time-signature drag gesture starts/ends, so the parent can
  /// coalesce the whole drag into a single undo step.
  final VoidCallback? onTimeSignatureDragStart;
  final VoidCallback? onTimeSignatureDragEnd;

  final bool isLoading;

  // Engine status. [engineFailed] turns the ▲ wordmark red as a quiet
  // "engine didn't start" cue.
  final bool engineFailed;

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
    this.onTempoDragStart,
    this.onTempoDragEnd,
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
    this.onTimeSignatureChanged,
    this.onTimeSignatureDragStart,
    this.onTimeSignatureDragEnd,
    this.isLoading = false,
    this.engineFailed = false,
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

  /// Anchors the "record to new track" menu shown when record is pressed with
  /// no armed tracks.
  final GlobalKey _recordKey = GlobalKey();

  /// Record pressed with nothing armed → offer to create + arm + record a new
  /// MIDI or Audio track, anchored under the record button.
  Future<void> _showRecordTrackMenu() async {
    final box = _recordKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(
      box.size.bottomLeft(Offset.zero),
      ancestor: overlay,
    );
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        topLeft & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'midi',
          child: Row(
            children: [
              Icon(BI.piano, size: BT.iconMd),
              const SizedBox(width: 8),
              const Text('New MIDI Track'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'audio',
          child: Row(
            children: [
              Icon(BI.waveform, size: BT.iconMd),
              const SizedBox(width: 8),
              const Text('New Audio Track'),
            ],
          ),
        ),
      ],
    );
    if (selected == 'midi') {
      widget.transport.onRecordNewMidiTrack?.call();
    } else if (selected == 'audio') {
      widget.transport.onRecordNewAudioTrack?.call();
    }
  }

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
        : _buildSingleRowBody(colors);

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

  /// A/B/D — the standard single-row bar: fixed left rail · centre clusters ·
  /// fixed right rail. The two rails are pinned to the same [_kRailWidth] so the
  /// transport cluster sits on the true window midpoint and the left chrome
  /// never reflows when the Library panel is collapsed. Panel resizing lives on
  /// the `ResizableDivider`s in the panels below, so the bar no longer carries
  /// its own resize handles (the two-row variant C still does).
  Widget _buildSingleRowBody(BoojyColors colors) {
    // Clamp each rail to at most half the available width so the two fixed
    // rails can never sum past the window — below ~640px they shrink together
    // (the centre Expanded never gets a negative constraint), which kills the
    // RenderFlex "RIGHT OVERFLOWED BY" banner at narrow widths while keeping
    // the rails equal so the transport stays centred. (B-TB1)
    return LayoutBuilder(
      builder: (context, constraints) {
        final railWidth = (constraints.maxWidth / 2).clamp(0.0, _kRailWidth);
        return Row(
          children: [
            // === LEFT RAIL (clamped width) ===
            SizedBox(width: railWidth, child: _buildLeftGroup(colors)),

            // === CENTRE GROUP (expanded → window-centred) ===
            Expanded(child: _buildCentreGroup(colors)),

            // === RIGHT RAIL (clamped width, content right-aligned) ===
            SizedBox(width: railWidth, child: _buildRightGroup(colors)),
          ],
        );
      },
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
        // No visible line in the bar — the top bar reads as one clean band.
        // This stays a silent 4px resize zone (cursor + drag still work, and
        // hovering still lights the panel boundary below via the shared
        // notifier); the actual visible divider lives in the panels below.
        child: Container(width: 4, color: colors.dark),
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
    // Fixed rail (see [_kRailWidth]): the wordmark + undo/redo + toggle sit at a
    // stable position and never reflow when the Library is collapsed. The
    // project name is the only flexible item — it truncates with an ellipsis.
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 0),
      child: Row(
        children: [
          _buildLogo(colors),

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
              onProjectSettings: widget.fileMenu.onProjectSettings,
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

          const SizedBox(width: 8),

          // Sidebar toggle [|]
          _PanelToggleButton(
            assetPath: 'assets/icons/sidebar_toggle.svg',
            isActive: widget.libraryVisible,
            onTap: widget.panels.onToggleLibrary,
            tooltip: widget.libraryVisible ? 'Hide Library' : 'Show Library',
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(BoojyColors colors) {
    // Nudge the whole wordmark up ~2px so its optical centre lines up with the
    // smaller siblings (project name, undo/redo) in the centre-aligned row.
    //
    // The ENTIRE wordmark (▲ + "udio") is the home button — it opens the
    // Start screen (Settings lives on the gear; a logo that opened Settings
    // confounded users, v0.6 dogfood A9). A ~20px triangle alone was too
    // small a target (user testing). The triangle's hover-scale is the
    // affordance, and it still doubles as the engine-health light
    // (red ⇒ engine didn't start).
    return Transform.translate(
      offset: const Offset(0, -2),
      child: MouseRegion(
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
          message: widget.engineFailed
              ? "Audio engine didn't start — check Settings (gear)"
              : 'Start screen',
          child: GestureDetector(
            onTap: () => widget.fileMenu.onStartScreen?.call(),
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              // Bottom-align: the raster's bottom edge IS the letter
              // baseline, matching the triangle's base (per the brand
              // lockup; same maths as BoojyWordmark).
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AnimatedScale(
                  scale: _logoHovered ? AnimationConstants.hoverScale : 1.0,
                  duration: AnimationConstants.hoverDuration,
                  curve: Curves.easeInOut,
                  child: CustomPaint(
                    // Equilateral: height = base * √3/2. ~10% larger than the
                    // first cut so it reads at the wordmark's weight.
                    size: const Size(22, 19.05),
                    painter: BoojyTrianglePainter(
                      widget.engineFailed ? colors.error : colors.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 1.5),
                // Brand "udio" raster (theme-picked black/white) — height
                // scaled to the 19.05px triangle at the lockup's 239:266
                // triangle:art ratio. The fixed left rail gives it a stable
                // home, so it renders at full size and never clips.
                Image.asset(
                  boojyTextAsset(context, 'udio'),
                  height: 19.05 * (266 / 239),
                  filterQuality: FilterQuality.medium,
                ),
              ],
            ),
          ),
        ),
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
        // The hard clip is the last line of defence: even if a well outgrows
        // its slot for a frame, nothing may paint over the arrangement below.
        return ClipRect(
          clipBehavior: Clip.hardEdge,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: BT.sm),
            child: Row(
              // Transport (play/stop/record) is pinned to the centre of the
              // bar; the modifier and readout wells flank it, hugging inward
              // via the flexible side slots. When the bar narrows the Expanded
              // slots collapse to zero and this degrades to the old
              // grouped-centre layout, so the density ladder still prevents
              // overflow.
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _buildModifiersWell(colors, density),
                  ),
                ),
                SizedBox(width: density.clusterGap),
                _buildTransportWell(colors, density),
                SizedBox(width: density.clusterGap),
                // Well 3: Readouts — layout chosen by the UI Labs variant.
                // Fixed size; the density ladder sheds labels (tools → icons,
                // "BPM"/"Tap") before the bar would overflow.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildReadoutWell(colors, density),
                  ),
                ),
              ],
            ),
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
              _buildReadoutWell(colors, density),
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
      // Same scaleDown guard as the readout well: the flank slots split the
      // leftover width evenly, so this well can be starved by a few pixels
      // before the next density tier kicks in. Without the guard that gap
      // rendered as a live "OVERFLOWED BY" banner over the arrangement (H1).
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
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
      ),
    );
  }

  /// Transport cluster (play/pause · stop · record). Extracted alongside
  /// [_buildModifiersWell] so C's row 2 can reorder the clusters.
  Widget _buildTransportWell(BoojyColors colors, TransportDensity density) {
    final wGap = density.withinGap;
    final transportBtnSize = density.transportCircleSize;
    // The transport is "rolling" whenever the playhead is moving — during plain
    // playback AND during a take (count-in or recording). In all of these the
    // primary button acts as Pause, so it must also *look* like Pause; otherwise
    // you get a green play-looking button that actually pauses the recording.
    final transportRolling =
        widget.isPlaying || widget.isRecording || widget.isCountingIn;
    return _ClusterWell(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularToggleButton(
            icon: transportRolling ? BI.pause : BI.play,
            enabled:
                widget.canPlay || widget.isRecording || widget.isCountingIn,
            // Amber while rolling (the pause affordance) so it reads as "hold"
            // and stays distinct from the orange Stop button sitting right next
            // to it — green when stopped (the play affordance).
            enabledColor: transportRolling
                ? colors.transportPause
                : colors.success,
            onPressed: () {
              if (widget.isRecording || widget.isCountingIn) {
                widget.transport.onPauseRecording?.call();
              } else if (widget.isPlaying) {
                widget.transport.onPause?.call();
              } else {
                widget.transport.onPlay?.call();
              }
            },
            tooltip: transportRolling ? 'Pause (Space)' : 'Play (Space)',
            size: transportBtnSize,
            iconSize: BT.iconLg,
          ),
          SizedBox(width: wGap),
          CircularToggleButton(
            icon: BI.stop,
            enabled:
                widget.canPlay || widget.isRecording || widget.isCountingIn,
            enabledColor: colors.transportStop,
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
            key: _recordKey,
            isRecording: widget.isRecording,
            isCountingIn: widget.isCountingIn,
            countInBars: widget.countInBars,
            countInBeat: widget.countInBeat,
            countInProgress: widget.countInProgress,
            beatsPerBar: widget.beatsPerBar,
            // Always live. With a track armed (or mid-record/count-in) it acts
            // as the normal record toggle; with nothing armed it offers to spin
            // up a new MIDI/Audio track, arm it, and roll.
            onPressed: () {
              if (widget.isRecording ||
                  widget.isCountingIn ||
                  widget.hasArmedTracks) {
                widget.transport.onRecord?.call();
              } else {
                _showRecordTrackMenu();
              }
            },
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
  Widget _buildReadoutWell(BoojyColors colors, TransportDensity density) {
    final wGap = density.withinGap;
    final tempo = TempoDisplay(
      tempo: widget.tempo,
      onTempoChanged: widget.onTempoChanged,
      onDragStart: widget.onTempoDragStart,
      onDragEnd: widget.onTempoDragEnd,
      compact: density.compactReadouts,
      // Shed the "BPM" suffix together with the tool labels — the density
      // math assumes the compact tier already dropped it (M22).
      showLabel: density.showLabels,
    );
    final signature = SignatureDropdown(
      beatsPerBar: widget.beatsPerBar,
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
          // The two centre flank slots use equal Expanded flex so the transport
          // pins to the window midpoint — but the readout well is wider than the
          // modifiers well, so the even split can starve this slot by a sub-pixel
          // at certain widths (the "RIGHT OVERFLOWED BY 0" sliver). scaleDown
          // absorbs that fraction invisibly without shedding labels early.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PositionDisplay(
                  playheadPosition: widget.playheadPosition,
                  tempo: widget.tempo,
                  beatsPerBar: widget.beatsPerBar,
                  onPositionChanged: widget.transport.onPositionChanged,
                  // Uniform size with the tempo / signature boxes (no hero scale)
                  // for a cleaner, even readout row.
                  scale: 1.0,
                ),
                // At minimum density the tempo + signature shed entirely —
                // the position readout + transport survive to the end.
                if (density.showTempoSig) ...[
                  SizedBox(width: wGap),
                  // Tempo + tap fused into one split button (tap the BPM zone).
                  tempo,
                  SizedBox(width: wGap),
                  signature,
                ],
              ],
            ),
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.darkest,
                  // Chrome radius (M25) — the bar uses radiusMd for chrome,
                  // radiusLg for overlays; this panel had a stray 6.
                  borderRadius: BT.borderMd,
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
    // Fixed rail mirroring the left, right-aligned to the far edge. Add-track
    // buttons sit just left of the mixer toggle + Help (a small gap separates
    // the "create" group from the panel chrome). Labels collapse to icon-only
    // on a narrow rail so they never overflow.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showLabels = constraints.maxWidth >= 210;
          return Row(
            children: [
              const Spacer(),

              // Add MIDI / Audio track
              AddTrackButton(
                label: showLabels ? 'MIDI' : '',
                typeIcon: BI.piano,
                typeColor:
                    TrackColors.categoryColors[TrackColorCategory.synth]!,
                onTap: widget.panels.onAddMidiTrack,
                tooltip: 'Add MIDI Track',
              ),
              const SizedBox(width: 6),
              AddTrackButton(
                label: showLabels ? 'Audio' : '',
                // Same glyph as the library's Samples category, so "Audio
                // track" and "samples" read as one concept.
                typeIcon: BI.equalizer,
                typeColor:
                    TrackColors.categoryColors[TrackColorCategory.audio]!,
                onTap: widget.panels.onAddAudioTrack,
                tooltip: 'Add Audio Track',
              ),

              const SizedBox(width: 12),

              // Mixer toggle (mirrored sidebar icon)
              _PanelToggleButton(
                assetPath: 'assets/icons/sidebar_toggle.svg',
                isActive: widget.mixerVisible,
                onTap: widget.panels.onToggleMixer,
                tooltip: widget.mixerVisible ? 'Hide Mixer' : 'Show Mixer',
                mirrored: true,
              ),

              const SizedBox(width: 8),

              // Help button — far right
              _HelpButton(onTap: widget.panels.onHelpPressed),
            ],
          );
        },
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

    Widget svgIcon = SvgPicture.asset(
      widget.assetPath,
      width: 18,
      height: 18,
      colorFilter: ColorFilter.mode(
        // Rest colour matches the help (?) glyph — textSecondary, the one
        // chrome-icon grey — and we no longer dim the collapsed-panel state to
        // 0.5, which made these toggles read darker/heavier than the help icon.
        // Deliberately NO active/open treatment (selection fill was tried and
        // rejected 2026-06-09) — these stay quiet chrome.
        isHovered ? colors.textPrimary : colors.textSecondary,
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
              child: svgIcon,
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

/// Filled equilateral triangle used as the "A" in the ▲udio wordmark.
