// ignore_for_file: avoid_positional_boolean_parameters
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';
import '../theme/animation_constants.dart';
import '../theme/app_colors.dart';
import '../theme/boojy_icons.dart';
import '../theme/theme_extension.dart';
import '../theme/tokens.dart';
import '../state/ui_layout_state.dart';
import 'shared/boojy_tooltip.dart';
import 'shared/button_hover_mixin.dart';
import 'shared/circular_toggle_button.dart';
import 'shared/boojy_dropdown.dart';
import 'transport_bar/app_menu_button.dart';
import 'transport_bar/count_in_toggle_button.dart';
import 'transport_bar/file_menu_button.dart';
import 'transport_bar/loop_toggle_button.dart';
import 'transport_bar/metronome_toggle_button.dart';
import 'transport_bar/position_display.dart';
import 'transport_bar/signature_dropdown.dart';
import 'transport_bar/snap_split_button.dart';
import 'transport_bar/tempo_controls.dart';
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

  /// Whether the Count-in chip shows its word. It is the one labelled chip in
  /// the modifiers well, and it stays labelled through every tier but the
  /// last — at [TransportDensity.minimum] it drops to a "1" glyph so the rails
  /// keep room for the traffic lights and undo/redo at the 960px window.
  bool get showCountInLabel => this != TransportDensity.minimum;

  /// Whether the Snap value zone gives up its fixed "1/16T"-wide slot and
  /// hugs the current value. Only at [TransportDensity.minimum].
  bool get compactSnapValue => this == TransportDensity.minimum;

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

/// Left inset that clears the macOS traffic lights when the bar is the top
/// chrome (native title bar hidden). MainFlutterWindow nudges the lights 5pt
/// right, so they span x≈12–64; the wordmark starts 17pt past them (Tyr-tuned
/// by eye). In full screen macOS hides the lights and the inset collapses to
/// the plain rail padding, so the whole left group shifts left together.
const double _kTrafficLightInset = 81.0;
const double _kRailPadding = 16.0;

/// Width of everything in the left rail except the inset and the project
/// name's text: wordmark (80) · gap (10) · name pill padding (12) · gap (6) ·
/// undo (26) · gap (2) · redo (26) · gap (6) · Library toggle (26), rounded up;
/// `transport_bar_density_test.dart` pins it. The compact wordmark (narrow
/// windows) is 15px narrower.
const double _kLeftRailFixed = 195.0;
const double _kCompactWordmarkSaving = 15.0;

/// Width of the right rail: padding · Mixer toggle · padding.
const double _kRightRailWidth = _kRailPadding + 26.0 + _kRailPadding;

/// Project-name text budget. It depends on the window width only — never on
/// the current name — so renaming a project can't move a control or change
/// which labels show. [_kNameMinWidth] is "Untitled" in Inter 14 medium with
/// a few px to spare; it grows with the window up to [_kNameMaxWidth]; longer
/// names truncate (full name on hover).
const double _kNameMinWidth = 56.0;
const double _kNameMaxWidth = 220.0;

/// Measured widths of the three centre wells at each density tier, with the
/// app's real typefaces and Capture wired (`transport_bar_density_test.dart`
/// re-measures these when a button changes width). Each well includes its
/// own 8px cluster padding.
class _WellWidths {
  const _WellWidths(this.modifiers, this.transport, this.readouts);
  final double modifiers;
  final double transport;
  final double readouts;
}

const Map<TransportDensity, _WellWidths> _kWellWidths = {
  TransportDensity.comfortable: _WellWidths(221, 146, 219),
  TransportDensity.compact: _WellWidths(218, 143, 175),
  TransportDensity.tight: _WellWidths(215, 140, 169),
  TransportDensity.iconsOnly: _WellWidths(215, 140, 169),
  TransportDensity.compressed: _WellWidths(212, 125, 167),
  TransportDensity.minimum: _WellWidths(161, 113, 72),
};

/// Centre width a tier needs when its three wells simply sit side by side:
/// wells + two cluster gaps + the centre group's 16px padding.
double _centreSumWidth(TransportDensity t) {
  final w = _kWellWidths[t]!;
  return w.modifiers + w.transport + w.readouts + 2 * t.clusterGap + 2 * BT.sm;
}

/// Most comfortable tier whose wells fit side by side in [availableWidth],
/// else [TransportDensity.minimum] (the wells then overflow rather than
/// shrink; the centre's ClipRect trims them).
TransportDensity _computeDensity(double availableWidth) {
  for (final density in TransportDensity.values) {
    if (availableWidth >= _centreSumWidth(density)) return density;
  }
  return TransportDensity.minimum;
}

/// The single-row bar's width allocation for one window width.
///
/// Priorities, in order: every control visible at its full size; the project
/// name gets at least [_kNameMinWidth]; the transport sits on the window
/// midpoint. When the last two conflict (narrow windows), the transport gives
/// way: it slides right by exactly the shortfall, so a live resize is
/// continuous and nothing is hidden, shrunk or relocated. Below that, the
/// centre sheds density tiers by the side-by-side sum ([_computeDensity]).
class _SingleRowLayout {
  _SingleRowLayout({
    required double windowWidth,
    required double leftInset,
    required bool compactWordmark,
  }) : compactWordmark = compactWordmark {
    final leftFixed =
        leftInset +
        _kLeftRailFixed -
        (compactWordmark ? _kCompactWordmarkSaving : 0);
    const c = TransportDensity.comfortable;
    final comfortable = _kWellWidths[c]!;
    // What the left half must hold besides the name when the transport is
    // centred at the comfortable tier: rail, modifiers well, its cluster
    // gap, half the centre padding, half the transport well.
    final leftHalfFixed =
        leftFixed +
        comfortable.modifiers +
        c.clusterGap +
        BT.sm +
        comfortable.transport / 2;
    nameWidth = (windowWidth / 2 - leftHalfFixed).clamp(
      _kNameMinWidth,
      _kNameMaxWidth,
    );
    leftRailWidth = leftFixed + nameWidth;
    rightRailWidth = _kRightRailWidth;
    centreWidth = windowWidth - leftRailWidth - rightRailWidth;
    density = _computeDensity(centreWidth);

    final wells = _kWellWidths[density]!;
    final modsNeed = wells.modifiers + density.clusterGap + BT.sm;
    final readoutsNeed = wells.readouts + density.clusterGap + BT.sm;
    // Slot that puts the transport on the window midpoint…
    final centredLeftSlot =
        windowWidth / 2 - leftRailWidth - wells.transport / 2;
    // …unless the modifiers can't fit in it: then the transport slides right
    // by the shortfall (never left — the readouts always have room).
    var leftSlot = math.max(centredLeftSlot, modsNeed);
    // Never push the readouts out of the centre either.
    leftSlot = math.min(
      leftSlot,
      math.max(modsNeed, centreWidth - wells.transport - readoutsNeed),
    );
    leftSlotWidth = leftSlot - BT.sm;
    rightSlotWidth = math.max(
      0,
      centreWidth - 2 * BT.sm - leftSlotWidth - wells.transport,
    );
  }

  final bool compactWordmark;
  late final double nameWidth;
  late final double leftRailWidth;
  late final double rightRailWidth;
  late final double centreWidth;
  late final TransportDensity density;

  /// Flank slot widths inside the centre group's padding.
  late final double leftSlotWidth;
  late final double rightSlotWidth;
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

  /// Count-in: Off or one bar. The labelled toggle beside Metronome.
  final bool countInEnabled;
  final VoidCallback? onCountInToggle;

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

  // Snap control: on/off and the grid are separate, so the value stays visible
  // (dimmed) while snap is off.
  final bool snapEnabled;
  final SnapValue snapResolution;
  final VoidCallback? onSnapToggle;
  final ValueChanged<SnapValue>? onSnapResolutionChanged;

  // Loop playback
  final bool loopPlaybackEnabled;

  // Time signature
  final int beatsPerBar;
  final Function(int beatsPerBar, int beatUnit)? onTimeSignatureChanged;

  /// Fired when the time-signature drag gesture starts/ends, so the parent can
  /// coalesce the whole drag into a single undo step.
  final VoidCallback? onTimeSignatureDragStart;
  final VoidCallback? onTimeSignatureDragEnd;

  final bool isLoading;

  // Engine status. [engineFailed] puts a red dot on the Audio menu as a quiet
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
    this.countInEnabled = true,
    this.onCountInToggle,
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
    this.snapEnabled = true,
    this.snapResolution = SnapValue.bar,
    this.onSnapToggle,
    this.onSnapResolutionChanged,
    this.loopPlaybackEnabled = false,
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

class _TransportBarState extends State<TransportBar> with WindowListener {
  /// macOS full screen hides the traffic lights, so the left inset that clears
  /// them collapses. Tracked here (not in the screen) because only the bar
  /// cares; false everywhere the bar isn't the top chrome.
  bool _isFullScreen = false;
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
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlayBox == null) return;

    final anchor = Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlayBox),
      box.localToGlobal(
        box.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      ),
    );
    final colors = context.themeProvider.colors;

    final selected = await showBoojyMenu<String>(
      context: context,
      anchor: anchor,
      items: [
        BoojyMenuItem(value: 'midi', icon: BI.piano, label: 'New MIDI Track'),
        BoojyMenuItem(
          value: 'audio',
          icon: BI.waveform,
          label: 'New Audio Track',
        ),
      ],
      selectedValue: null,
      colors: colors,
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
    if (_replacesTitleBar) {
      windowManager.addListener(this);
      // Catch a window that is already full screen (relaunch into the saved
      // state). The plugin call is unavailable under `flutter test`; the
      // inset simply stays in place there.
      windowManager
          .isFullScreen()
          .then((full) {
            if (mounted && full != _isFullScreen) {
              setState(() => _isFullScreen = full);
            }
          })
          .catchError((Object _) {});
    }
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _isFullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _isFullScreen = false);
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
    if (_replacesTitleBar) windowManager.removeListener(this);
    widget.dividers.leftDividerNotifier?.removeListener(_onLeftNotifierChanged);
    widget.dividers.rightDividerNotifier?.removeListener(
      _onRightNotifierChanged,
    );
    super.dispose();
  }

  /// macOS hides its native title bar (see WindowTitleService), so the bar
  /// becomes the top chrome: it insets to clear the traffic lights and provides
  /// a drag region for moving the window.
  bool get _replacesTitleBar => defaultTargetPlatform == TargetPlatform.macOS;

  /// Left padding of the left rail: clears the traffic lights on macOS while
  /// windowed, plain rail padding otherwise (Windows, or macOS full screen).
  double get _trafficLightInset =>
      _replacesTitleBar && !_isFullScreen ? _kTrafficLightInset : _kRailPadding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Extra floor on macOS so the two-row variant's left group is wide enough
    // to fully clear the traffic lights even when the sidebar is collapsed.
    final leftMinWidth = _trafficLightInset > _kRailPadding ? 214.0 : 200.0;

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

  /// A/B/D — the standard single-row bar: left rail · centre · right rail,
  /// allocated by [_SingleRowLayout] from the window width alone.
  Widget _buildSingleRowBody(BoojyColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final layout = _SingleRowLayout(
          windowWidth: w,
          leftInset: _trafficLightInset,
          // Narrow windows: the wordmark steps down a size to give the
          // transport back some of its drift.
          compactWordmark: w < 1100,
        );
        return Row(
          children: [
            SizedBox(
              width: layout.leftRailWidth,
              child: _buildLeftGroup(
                colors,
                nameWidth: layout.nameWidth,
                compactWordmark: layout.compactWordmark,
              ),
            ),
            Expanded(child: _buildCentreGroup(colors, layout)),
            SizedBox(
              width: layout.rightRailWidth,
              child: _buildRightGroup(colors),
            ),
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
                child: _buildLeftGroup(
                  colors,
                  nameWidth: _kNameMaxWidth,
                  compactWordmark: false,
                ),
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

  Widget _buildLeftGroup(
    BoojyColors colors, {
    required double nameWidth,
    required bool compactWordmark,
  }) {
    // The wordmark menu + undo/redo + Library toggle keep their spacing at
    // every width; only the project name's slot changes, and only with the
    // window ([_SingleRowLayout.nameWidth]).
    return Padding(
      padding: EdgeInsets.only(left: _trafficLightInset),
      child: Row(
        children: [
          AppMenuButton(
            engineFailed: widget.engineFailed,
            compact: compactWordmark,
            onSettings: widget.fileMenu.onAppSettings,
            onKeyboardShortcuts: widget.fileMenu.onKeyboardShortcuts,
            onStartScreen: widget.fileMenu.onStartScreen,
          ),

          // Breathing room between the brand mark and the project name
          // (Tyr-tuned by eye, 2026-09-13).
          const SizedBox(width: 10),

          // Project name — fixed slot from the window width; long names
          // truncate with an ellipsis and show in full on hover.
          SizedBox(
            width: nameWidth + 12,
            child: FileMenuButton(
              projectName: widget.projectName,
              hasProject: widget.hasProject,
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

          const SizedBox(width: 6),

          // Undo button
          _SvgIconButton(
            assetPath: 'assets/icons/undo.svg',
            enabled: widget.canUndo,
            onTap: widget.transport.onUndo,
            tooltip: widget.canUndo && widget.undoDescription != null
                ? 'Undo: ${widget.undoDescription} (⌘Z)'
                : 'Undo (⌘Z)',
          ),

          const SizedBox(width: 2),

          // Redo button
          _SvgIconButton(
            assetPath: 'assets/icons/redo.svg',
            enabled: widget.canRedo,
            onTap: widget.transport.onRedo,
            tooltip: widget.canRedo && widget.redoDescription != null
                ? 'Redo: ${widget.redoDescription} (⇧⌘Z)'
                : 'Redo (⇧⌘Z)',
          ),

          const SizedBox(width: 6),

          // Library panel toggle — sits above the panel it controls
          _PanelToggleButton(
            assetPath: 'assets/icons/library.svg',
            isActive: widget.libraryVisible,
            onTap: widget.panels.onToggleLibrary,
            tooltip: widget.libraryVisible ? 'Hide Library' : 'Show Library',
          ),
        ],
      ),
    );
  }

  // ============================================
  // CENTRE GROUP
  // ============================================

  Widget _buildCentreGroup(BoojyColors colors, _SingleRowLayout layout) {
    final density = layout.density;
    // The hard clip is the last line of defence: even if a well outgrows
    // its slot for a frame, nothing may paint over the arrangement below.
    return ClipRect(
      clipBehavior: Clip.hardEdge,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: BT.sm),
        child: Row(
          // The flank slots are sized by [_SingleRowLayout]: equal around the
          // window midpoint where the name has its minimum, otherwise the
          // left slot is exactly the modifiers well and the transport sits
          // right of centre by the shortfall.
          //
          // The slots are OverflowBoxes, not FittedBoxes: a well that
          // outgrows its slot keeps its size and runs past the slot edge (the
          // ClipRect above trims it) instead of scaling down.
          children: [
            SizedBox(
              width: layout.leftSlotWidth,
              child: OverflowBox(
                alignment: Alignment.centerRight,
                minWidth: 0,
                maxWidth: double.infinity,
                child: Padding(
                  padding: EdgeInsets.only(right: density.clusterGap),
                  child: _buildModifiersWell(colors, density),
                ),
              ),
            ),
            _buildTransportWell(colors, density),
            // Well 3: Readouts — layout chosen by the UI Labs variant. Fixed
            // size; the density ladder sheds labels ("BPM"/"Tap") before the
            // bar would overflow.
            Expanded(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 0,
                maxWidth: double.infinity,
                child: Padding(
                  padding: EdgeInsets.only(left: density.clusterGap),
                  child: _buildReadoutWell(colors, density),
                ),
              ),
            ),
          ],
        ),
      ),
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

  /// Modifier cluster: Snap · Loop · Metronome · Count-in, the familiar
  /// left-of-transport order. Extracted so both the single-row centre group
  /// and C's row 2 can compose it in either order.
  Widget _buildModifiersWell(BoojyColors colors, TransportDensity density) {
    final wGap = density.withinGap;
    return _ClusterWell(
      // Fixed size on purpose: never a FittedBox here. The single-row centre
      // group gives this well an OverflowBox slot, so a starved slot clips
      // rather than shrinks (the glyphs stay the outer buttons' size).
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SnapSplitButton(
            isEnabled: widget.snapEnabled,
            resolution: widget.snapResolution,
            onToggle: widget.onSnapToggle,
            onResolutionChanged: widget.onSnapResolutionChanged,
            compactValue: density.compactSnapValue,
          ),
          SizedBox(width: wGap),
          LoopToggleButton(
            isActive: widget.loopPlaybackEnabled,
            onToggle: widget.transport.onLoopPlaybackToggle,
          ),
          SizedBox(width: wGap),
          MetronomeToggleButton(
            isActive: widget.metronomeEnabled,
            onToggle: widget.transport.onMetronomeToggle,
          ),
          SizedBox(width: wGap),
          CountInToggleButton(
            isActive: widget.countInEnabled,
            onToggle: widget.onCountInToggle,
            showLabel: density.showCountInLabel,
          ),
        ],
      ),
    );
  }

  /// Transport cluster (play/pause · stop · record · capture). Extracted alongside
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
            size: transportBtnSize,
          ),
          // Capture MIDI — momentary button immediately right of Record: "grab
          // what I just played" belongs with the take controls. Shown only when
          // the backend callback is wired.
          if (widget.transport.onCaptureMidi != null) ...[
            SizedBox(width: wGap + BT.xs),
            _CaptureButton(onCaptureMidi: widget.transport.onCaptureMidi),
          ],
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
          // Fixed size, same as the modifiers well: the centre group's
          // OverflowBox slot absorbs any sub-pixel starvation (the old
          // "RIGHT OVERFLOWED BY 0" sliver) without scaling the readouts.
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
    // Fixed rail mirroring the left, right-aligned to the far edge: just the
    // Mixer toggle, sitting above the panel it controls. Track creation moved
    // into the mixer panel's header (the panel IS the track list).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kRailPadding),
      child: Row(
        children: [
          const Spacer(),
          _PanelToggleButton(
            assetPath: 'assets/icons/mixer.svg',
            isActive: widget.mixerVisible,
            onTap: widget.panels.onToggleMixer,
            tooltip: widget.mixerVisible ? 'Hide Mixer' : 'Show Mixer',
          ),
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
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
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

/// Panel toggle (Library / Mixer): a semantic glyph for the panel, no box.
/// State is carried by brightness alone — a slightly brighter neutral grey
/// while the panel is open, the standard chrome grey while it is closed (still
/// readable, never "disabled"). Hover is distinct from both: white glyph on a
/// soft surface pill, plus the usual press scale (Tyr, 2026-09-13).
class _PanelToggleButton extends StatefulWidget {
  final String assetPath;
  final bool isActive;
  final VoidCallback? onTap;
  final String tooltip;

  const _PanelToggleButton({
    required this.assetPath,
    required this.isActive,
    this.onTap,
    required this.tooltip,
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
    final openGrey =
        Color.lerp(colors.textSecondary, colors.textPrimary, 0.6) ??
        colors.textPrimary;
    final glyphColor = isHovered
        ? colors.textPrimary
        : (widget.isActive ? openGrey : colors.textSecondary);

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
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isHovered ? colors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(BT.radiusMd),
              ),
              child: SvgPicture.asset(
                widget.assetPath,
                width: BT.iconLg,
                height: BT.iconLg,
                colorFilter: ColorFilter.mode(glyphColor, BlendMode.srcIn),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Momentary "Capture MIDI" button — bordered like the metronome, flashes
/// accent on press (same press-flash cue as Quantize) to confirm it fired.
class _CaptureButton extends StatefulWidget {
  final VoidCallback? onCaptureMidi;

  const _CaptureButton({this.onCaptureMidi});

  @override
  State<_CaptureButton> createState() => _CaptureButtonState();
}

class _CaptureButtonState extends State<_CaptureButton> {
  bool _pulse = false;

  void _fire() {
    widget.onCaptureMidi?.call();
    setState(() => _pulse = true);
    Future.delayed(const Duration(milliseconds: 240), () {
      if (mounted) setState(() => _pulse = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final borderColor = _pulse ? colors.accent : colors.textMuted;
    final iconColor = _pulse ? colors.accent : colors.textSecondary;

    return BoojyTooltip(
      title: 'Capture what you just played',
      description: 'Saves the phrase into a new clip at the playhead',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _fire,
          child: DecoratedBox(
            // Foreground border: same pattern as metronome/loop/snap — the
            // fill can't paint over the stroke because it's drawn on top.
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BT.borderMd,
              border: Border.all(color: borderColor, width: 1),
            ),
            child: SizedBox(
              height: BT.splitButtonHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Center(
                  // Lucide "scan" corners (Tyr's pick), keyed so tests can
                  // find the button without an IconData.
                  child: SvgPicture.asset(
                    'assets/icons/scan.svg',
                    key: const Key('captureMidi'),
                    width: BT.iconMd,
                    height: BT.iconMd,
                    colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
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
