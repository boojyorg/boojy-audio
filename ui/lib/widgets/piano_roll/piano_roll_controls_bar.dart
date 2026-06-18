import 'package:flutter/material.dart';
import '../../models/scale_data.dart';
import '../../theme/app_colors.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
import '../../utils/grid_utils.dart';
import '../shared/boojy_dropdown.dart';
import '../transport_bar/signature_dropdown.dart';
import 'loop_time_display.dart';

/// Display mode for responsive icon/label buttons
enum _ButtonDisplayMode {
  wide, // Icon + Label (all icons visible)
  compact, // Label only (all icons hidden at once when space is limited)
}

/// Horizontal controls bar for Piano Roll.
/// Replaces the left sidebar with a compact, wrappable toolbar.
///
/// Layout format:
/// [Loop] Start [1.1.1] Length [5.1.1] Signature [4/4] | [Snap 1/16▼] [Quantize 1/16▼] ...
class PianoRollControlsBar extends StatefulWidget {
  // Clip section
  final bool loopEnabled;
  final double loopStartBeats;
  final double loopLengthBeats;
  final int beatsPerBar;
  final VoidCallback? onLoopToggle;
  final Function(double)? onLoopStartChanged;
  final Function(double)? onLoopLengthChanged;
  final Function(int)? onBeatsPerBarChanged;
  final VoidCallback? onSignatureDragStart;
  final VoidCallback? onSignatureDragEnd;

  // Grid section
  final bool snapEnabled;
  final double gridDivision;
  final bool adaptiveGridEnabled;
  final bool snapTripletEnabled;
  final VoidCallback? onSnapToggle;
  final Function(double?)? onGridDivisionChanged; // null = adaptive
  final ValueChanged<bool>? onSnapTripletChanged;
  final VoidCallback? onQuantize;
  final int quantizeDivision; // 0 = Grid, else 4/8/16/32
  final bool quantizeTripletEnabled;
  final Function(int)? onQuantizeDivisionChanged;
  final ValueChanged<bool>? onQuantizeTripletChanged;

  // View section
  final bool foldEnabled;
  final bool ghostNotesEnabled;
  final VoidCallback? onFoldToggle;
  final VoidCallback? onGhostNotesToggle;

  // Scale section
  final String scaleRoot;
  final ScaleType scaleType;
  final bool highlightEnabled;
  final bool lockEnabled;
  final Function(String)? onRootChanged;
  final Function(ScaleType)? onTypeChanged;
  final VoidCallback? onHighlightToggle;
  final VoidCallback? onLockToggle;

  // Transform section
  final double stretchAmount;
  final VoidCallback? onLegato;
  final Function(double)? onStretchChanged;
  final VoidCallback? onStretchApply;
  final VoidCallback? onReverse;

  // Lane visibility toggles (Randomize/CC type moved to lane headers)
  final bool velocityLaneVisible;
  final VoidCallback? onVelocityLaneToggle;
  final bool ccLaneVisible;
  final VoidCallback? onCCLaneToggle;
  final bool clipAutomationLaneVisible;
  final VoidCallback? onClipAutomationLaneToggle;

  // Virtual Piano toggle
  final bool virtualPianoVisible;
  final VoidCallback? onVirtualPianoToggle;

  // Current effective grid division (for display when adaptive)
  final double effectiveGridDivision;

  const PianoRollControlsBar({
    super.key,
    // Clip section
    this.loopEnabled = false,
    this.loopStartBeats = 0.0,
    this.loopLengthBeats = 4.0,
    this.beatsPerBar = 4,
    this.onLoopToggle,
    this.onLoopStartChanged,
    this.onLoopLengthChanged,
    this.onBeatsPerBarChanged,
    this.onSignatureDragStart,
    this.onSignatureDragEnd,
    // Grid section
    this.snapEnabled = true,
    this.gridDivision = 0.25,
    this.adaptiveGridEnabled = true,
    this.snapTripletEnabled = false,
    this.onSnapToggle,
    this.onGridDivisionChanged,
    this.onSnapTripletChanged,
    this.onQuantize,
    this.quantizeDivision = 0,
    this.quantizeTripletEnabled = false,
    this.onQuantizeDivisionChanged,
    this.onQuantizeTripletChanged,
    this.effectiveGridDivision = 0.25,
    // View section
    this.foldEnabled = false,
    this.ghostNotesEnabled = false,
    this.onFoldToggle,
    this.onGhostNotesToggle,
    // Scale section
    required this.scaleRoot,
    required this.scaleType,
    this.highlightEnabled = false,
    this.lockEnabled = false,
    this.onRootChanged,
    this.onTypeChanged,
    this.onHighlightToggle,
    this.onLockToggle,
    // Transform section
    this.stretchAmount = 1.0,
    this.onLegato,
    this.onStretchChanged,
    this.onStretchApply,
    this.onReverse,
    // Lane visibility toggles
    this.velocityLaneVisible = false,
    this.onVelocityLaneToggle,
    this.ccLaneVisible = false,
    this.onCCLaneToggle,
    this.clipAutomationLaneVisible = false,
    this.onClipAutomationLaneToggle,
    // Virtual Piano toggle
    this.virtualPianoVisible = false,
    this.onVirtualPianoToggle,
  });

  @override
  State<PianoRollControlsBar> createState() => _PianoRollControlsBarState();
}

class _PianoRollControlsBarState extends State<PianoRollControlsBar> {
  _ButtonDisplayMode _displayMode = _ButtonDisplayMode.wide;
  final GlobalKey _wrapKey = GlobalKey();
  double _lastWidth = 0;

  // Hover states for split button styling
  bool _isHoveringSnapLabel = false;
  bool _isHoveringSnapDropdown = false;
  bool _isHoveringQuantizeLabel = false;
  bool _isHoveringQuantizeDropdown = false;

  // One-shot actions pulse accent on press to confirm they fired, then settle
  // back to neutral. This is the visual cue that it applied rather than toggled.
  bool _quantizePulse = false;
  bool _legatoPulse = false;

  void _fireQuantize() {
    widget.onQuantize?.call();
    setState(() => _quantizePulse = true);
    Future.delayed(const Duration(milliseconds: 240), () {
      if (mounted) setState(() => _quantizePulse = false);
    });
  }

  void _fireLegato() {
    widget.onLegato?.call();
    setState(() => _legatoPulse = true);
    Future.delayed(const Duration(milliseconds: 240), () {
      if (mounted) setState(() => _legatoPulse = false);
    });
  }

  // Keys for computing menu anchor rects
  final GlobalKey _snapButtonKey = GlobalKey();
  final GlobalKey _quantizeButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Check layout after first frame
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkIfFitsOnOneLine(),
    );
  }

  void _checkIfFitsOnOneLine() {
    if (!mounted) return;

    final wrapBox = _wrapKey.currentContext?.findRenderObject() as RenderBox?;
    if (wrapBox == null) return;

    // Get the actual height of the Wrap widget
    final wrapHeight = wrapBox.size.height;

    // Single line height is approximately 24px (button height + some padding)
    // If wrap height > ~30px, content has wrapped to multiple lines
    const singleLineMaxHeight = 30.0;

    if (wrapHeight > singleLineMaxHeight) {
      // Content wrapped - switch to compact mode (hide all icons at once)
      if (_displayMode == _ButtonDisplayMode.wide) {
        setState(() => _displayMode = _ButtonDisplayMode.compact);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        // When width changes significantly, reset to wide and re-check
        if ((constraints.maxWidth - _lastWidth).abs() > 50) {
          _lastWidth = constraints.maxWidth;
          if (_displayMode != _ButtonDisplayMode.wide) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _displayMode = _ButtonDisplayMode.wide);
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _checkIfFitsOnOneLine(),
                );
              }
            });
          } else {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _checkIfFitsOnOneLine(),
            );
          }
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.darkest,
            border: Border(bottom: BorderSide(color: colors.surface, width: 1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  key: _wrapKey,
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.start, // Left-align
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // === CLIP GROUP ===
                    _buildClipGroup(context),
                    _buildSeparator(context),

                    // === GRID GROUP ===
                    _buildGridGroup(context),
                    _buildSeparator(context),

                    // === SCALE GROUP ===
                    _buildScaleGroup(context),
                    _buildSeparator(context),

                    // === TRANSFORM GROUP (Legato) ===
                    _buildTransformGroup(context),
                    _buildSeparator(context),

                    // === LANES GROUP (velocity / CC lane toggles) ===
                    _buildLanesGroup(context),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSeparator(BuildContext context) {
    return Container(width: 1, height: 20, color: context.colors.surface);
  }

  // ============ CLIP GROUP ============
  Widget _buildClipGroup(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Loop toggle - controls clip's canRepeat property
        _buildToggleButton(
          context,
          icon: BI.loop,
          label: 'Loop',
          isActive: widget.loopEnabled,
          onTap: widget.onLoopToggle,
          tooltip: 'Loop clip content (allows repeating in arrangement)',
        ),
        const SizedBox(width: 8),
        // Start label + input
        Text(
          'Start',
          style: TextStyle(color: colors.textMuted, fontSize: BT.fontCaption),
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BT.borderMd,
            border: Border.all(color: colors.surface, width: 1),
          ),
          child: LoopTimeDisplay(
            beats: widget.loopStartBeats,
            label: '',
            onChanged: widget.onLoopStartChanged,
            beatsPerBar: widget.beatsPerBar,
            isPosition: true, // 1-indexed position (1.1.1 = start)
          ),
        ),
        const SizedBox(width: 8),
        // Length label + input
        Text(
          'Length',
          style: TextStyle(color: colors.textMuted, fontSize: BT.fontCaption),
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BT.borderMd,
            border: Border.all(color: colors.surface, width: 1),
          ),
          child: LoopTimeDisplay(
            beats: widget.loopLengthBeats,
            label: '',
            onChanged: widget.onLoopLengthChanged,
            beatsPerBar: widget.beatsPerBar,
            isPosition: false, // 0-indexed length (1.0.0 = 1 bar)
          ),
        ),
        const SizedBox(width: 8),
        // Signature label + input
        Text(
          'Signature',
          style: TextStyle(color: colors.textMuted, fontSize: BT.fontCaption),
        ),
        const SizedBox(width: 4),
        // Same control as the transport bar: click anywhere on the box for
        // the n/4 menu, drag up/down to scrub. The old numerator-only
        // click-to-type target was ~10px wide and read as "not editable".
        SignatureDropdown(
          beatsPerBar: widget.beatsPerBar,
          onChanged: (numerator, _) =>
              widget.onBeatsPerBarChanged?.call(numerator),
          onDragStart: widget.onSignatureDragStart,
          onDragEnd: widget.onSignatureDragEnd,
        ),
      ],
    );
  }

  // ============ SCALE GROUP ============
  // Minimal Scale Highlight toggle. The root/type pickers and Lock are still
  // plumbed through this widget but not yet rendered — this one toggle makes
  // the existing scale-highlight rendering (root band + out-of-scale dimming)
  // reachable, keyed to the default root/scale (C major).
  Widget _buildScaleGroup(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildToggleButton(
          context,
          icon: BI.piano,
          label: 'Scale',
          isActive: widget.highlightEnabled,
          onTap: widget.onHighlightToggle,
          tooltip:
              'Highlight the scale: mark root-note rows and dim out-of-scale notes',
        ),
      ],
    );
  }

  // ============ TRANSFORM GROUP ============
  // Minimal: Legato only. Stretch/Reverse/Humanize remain plumbed but unrendered.
  // Legato is a one-shot action — uses the same press-flash pattern as Quantize.
  Widget _buildTransformGroup(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActionButton(
          context,
          icon: BI.linearScale,
          label: 'Legato',
          pulse: _legatoPulse,
          onTap: widget.onLegato != null ? _fireLegato : null,
          tooltip: 'Legato — extend each note to the start of the next',
        ),
      ],
    );
  }

  // ============ LANES GROUP ============
  // Toggle velocity lane open/closed. CC lane deferred (no opener shipped yet).
  Widget _buildLanesGroup(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildToggleButton(
          context,
          icon: BI.chartLine,
          label: 'Velocity',
          isActive: widget.velocityLaneVisible,
          onTap: widget.onVelocityLaneToggle,
          tooltip: 'Toggle velocity lane',
        ),
      ],
    );
  }

  // ============ GRID GROUP ============
  Widget _buildGridGroup(BuildContext context) {
    // Snap label: "Snap" when adaptive, "Snap (T)" with triplet, "Snap 1/16T" when fixed
    String snapLabel;
    if (widget.adaptiveGridEnabled) {
      snapLabel = widget.snapTripletEnabled ? 'Snap (T)' : 'Snap';
    } else {
      snapLabel =
          'Snap ${GridUtils.gridDivisionToLabel(widget.gridDivision, triplet: widget.snapTripletEnabled)}';
    }

    // Quantize label: "Quantize" when grid, "Quantize (T)" with triplet, "Quantize 1/16T" when fixed
    String quantizeLabel;
    if (widget.quantizeDivision == 0) {
      quantizeLabel = widget.quantizeTripletEnabled
          ? 'Quantize (T)'
          : 'Quantize';
    } else {
      final suffix = widget.quantizeTripletEnabled ? 'T' : '';
      quantizeLabel = 'Quantize 1/${widget.quantizeDivision}$suffix';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Snap split button with adaptive + triplet
        _buildSnapDropdown(context, snapLabel),
        const SizedBox(width: 4),
        // Quantize split button with grid + triplet
        _buildQuantizeDropdown(context, quantizeLabel),
      ],
    );
  }

  Widget _buildSnapDropdown(BuildContext context, String label) {
    final colors = context.colors;
    // Outlined + soft-tint grammar, matching the transport bar's Snap button
    // via the shared selection tokens.
    final bgColor = widget.snapEnabled ? colors.selectionFill : colors.surface;
    final textColor = widget.snapEnabled
        ? colors.textPrimary
        : colors.textSecondary;
    final iconColor = widget.snapEnabled ? colors.accent : colors.textSecondary;

    return DecoratedBox(
      key: _snapButtonKey,
      // Foreground border so the hover zone fills (painted full-height by the
      // stretch below) can't cover the stroke — DecoratedBox doesn't inset its
      // child the way Container does, so a background border would vanish
      // under them. The bg colour lives on the inner box instead.
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BT.borderMd,
        border: Border.all(
          color: widget.snapEnabled ? colors.selectionBorder : colors.textMuted,
          width: 1,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(color: bgColor, borderRadius: BT.borderMd),
        // IntrinsicHeight + stretch so the inter-zone divider spans the full
        // chip height instead of a fixed 15px slug.
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left side: Label (clickable for toggle)
              MouseRegion(
                onEnter: (_) {
                  if (!_isHoveringSnapLabel) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _isHoveringSnapLabel = true);
                    });
                  }
                },
                onExit: (_) {
                  if (_isHoveringSnapLabel) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _isHoveringSnapLabel = false);
                    });
                  }
                },
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: widget.onSnapToggle,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _isHoveringSnapLabel
                          ? (widget.snapEnabled
                                ? colors.selectionFillHover
                                : colors.textPrimary.withValues(alpha: 0.1))
                          : Colors.transparent,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(BT.radiusMd - 1),
                        bottomLeft: Radius.circular(BT.radiusMd - 1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Show icon only in wide mode
                        if (_displayMode == _ButtonDisplayMode.wide) ...[
                          Icon(BI.gridOn, size: 13, color: iconColor),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          label,
                          style: TextStyle(color: textColor, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Divider line — selection-border when engaged, like the transport
              // split button
              Container(
                width: 1,
                color: widget.snapEnabled
                    ? colors.selectionBorder
                    : colors.textMuted,
              ),

              // Right side: Dropdown arrow
              MouseRegion(
                onEnter: (_) {
                  if (!_isHoveringSnapDropdown) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => _isHoveringSnapDropdown = true);
                      }
                    });
                  }
                },
                onExit: (_) {
                  if (_isHoveringSnapDropdown) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => _isHoveringSnapDropdown = false);
                      }
                    });
                  }
                },
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _showSnapMenu(context, colors),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _isHoveringSnapDropdown
                          ? (widget.snapEnabled
                                ? colors.selectionFillHover
                                : colors.textPrimary.withValues(alpha: 0.1))
                          : Colors.transparent,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(BT.radiusMd - 1),
                        bottomRight: Radius.circular(BT.radiusMd - 1),
                      ),
                    ),
                    child: Icon(BI.caretDown, size: 15, color: textColor),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnapMenu(BuildContext context, BoojyColors colors) {
    final button =
        _snapButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (button == null || overlayBox == null) return;

    final anchor = Rect.fromPoints(
      button.localToGlobal(Offset.zero, ancestor: overlayBox),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      ),
    );

    showBoojyMenu<String>(
      context: context,
      anchor: anchor,
      items: _snapMenuItems,
      selectedValue: _currentSnapKey(),
      colors: colors,
    ).then((picked) {
      if (picked != null && mounted) _applySnapPick(picked);
    });
  }

  static const List<BoojyMenuItem<String>> _snapMenuItems = [
    BoojyMenuItem(value: 'adaptive', label: 'Adaptive'),
    BoojyMenuItem(value: '1/4', label: '1/4'),
    BoojyMenuItem(value: '1/4T', label: '1/4T'),
    BoojyMenuItem(value: '1/8', label: '1/8'),
    BoojyMenuItem(value: '1/8T', label: '1/8T'),
    BoojyMenuItem(value: '1/16', label: '1/16'),
    BoojyMenuItem(value: '1/16T', label: '1/16T'),
    BoojyMenuItem(value: '1/32', label: '1/32'),
    BoojyMenuItem(value: '1/32T', label: '1/32T'),
  ];

  String _currentSnapKey() {
    if (widget.adaptiveGridEnabled) return 'adaptive';
    final base = GridUtils.gridDivisionToLabel(widget.gridDivision);
    return widget.snapTripletEnabled ? '${base}T' : base;
  }

  void _applySnapPick(String key) {
    if (key == 'adaptive') {
      widget.onGridDivisionChanged?.call(null);
      widget.onSnapTripletChanged?.call(false);
      return;
    }
    final triplet = key.endsWith('T');
    final base = triplet ? key.substring(0, key.length - 1) : key;
    final div = const <String, double>{
      '1 Bar': 4.0,
      '1/2': 2.0,
      '1/4': 1.0,
      '1/8': 0.5,
      '1/16': 0.25,
      '1/32': 0.125,
    }[base];
    if (div != null) {
      widget.onGridDivisionChanged?.call(div);
      widget.onSnapTripletChanged?.call(triplet);
    }
  }

  Widget _buildQuantizeDropdown(BuildContext context, String label) {
    final colors = context.colors;
    // Action grammar (distinct from the toggle chips beside it):
    // - at rest: neutral chip with a *softer* border than the toggles' off-state
    //   and an always-accent magnet glyph, signalling "this does an accent
    //   action" without implying an on-state;
    // - on press: the whole chip flashes accent, then settles back.
    final pulsing = _quantizePulse;
    final textColor = pulsing ? colors.accent : colors.textPrimary;
    final glyphColor = colors.accent;
    final caretColor = pulsing ? colors.accent : colors.textSecondary;
    final dividerColor = pulsing
        ? colors.accent.withValues(alpha: 0.8)
        : colors.divider;

    // NB: DecoratedBox (not Container/AnimatedContainer) to match the Snap
    // button's height exactly — a Container reserves layout space for its
    // border (+2px tall), DecoratedBox only paints it. The press flash is an
    // instant colour swap rather than a fade.
    return DecoratedBox(
      key: _quantizeButtonKey,
      // Foreground border for the same reason as the Snap chip: the hover
      // zone fills would otherwise paint over a background stroke.
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BT.borderMd,
        border: Border.all(color: dividerColor, width: 1),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: pulsing
              ? colors.accent.withValues(alpha: 0.22)
              : colors.surface,
          borderRadius: BT.borderMd,
        ),
        // IntrinsicHeight + stretch so the inter-zone divider spans the full
        // chip height instead of a fixed 15px slug.
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left side: Icon + Label (clickable for quantize action)
              MouseRegion(
                onEnter: (_) {
                  if (!_isHoveringQuantizeLabel) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => _isHoveringQuantizeLabel = true);
                      }
                    });
                  }
                },
                onExit: (_) {
                  if (_isHoveringQuantizeLabel) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => _isHoveringQuantizeLabel = false);
                      }
                    });
                  }
                },
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _fireQuantize,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _isHoveringQuantizeLabel
                          ? colors.textPrimary.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(BT.radiusMd - 1),
                        bottomLeft: Radius.circular(BT.radiusMd - 1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Show icon only in wide mode
                        if (_displayMode == _ButtonDisplayMode.wide) ...[
                          Image.asset(
                            'assets/images/magnet.png',
                            width: 13,
                            height: 13,
                            color: glyphColor,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          label,
                          style: TextStyle(color: textColor, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Divider line
              Container(width: 1, color: dividerColor),

              // Right side: Dropdown arrow
              MouseRegion(
                onEnter: (_) {
                  if (!_isHoveringQuantizeDropdown) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => _isHoveringQuantizeDropdown = true);
                      }
                    });
                  }
                },
                onExit: (_) {
                  if (_isHoveringQuantizeDropdown) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => _isHoveringQuantizeDropdown = false);
                      }
                    });
                  }
                },
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _showQuantizeMenu(context, colors),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _isHoveringQuantizeDropdown
                          ? colors.textPrimary.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(BT.radiusMd - 1),
                        bottomRight: Radius.circular(BT.radiusMd - 1),
                      ),
                    ),
                    child: Icon(BI.caretDown, size: 15, color: caretColor),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQuantizeMenu(BuildContext context, BoojyColors colors) {
    final button =
        _quantizeButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (button == null || overlayBox == null) return;

    final anchor = Rect.fromPoints(
      button.localToGlobal(Offset.zero, ancestor: overlayBox),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      ),
    );

    showBoojyMenu<String>(
      context: context,
      anchor: anchor,
      items: _quantizeMenuItems,
      selectedValue: _currentQuantizeKey(),
      colors: colors,
    ).then((picked) {
      if (picked != null && mounted) _applyQuantizePick(picked);
    });
  }

  static const List<BoojyMenuItem<String>> _quantizeMenuItems = [
    BoojyMenuItem(value: 'grid', label: 'Grid'),
    BoojyMenuItem(value: '1/4', label: '1/4'),
    BoojyMenuItem(value: '1/4T', label: '1/4T'),
    BoojyMenuItem(value: '1/8', label: '1/8'),
    BoojyMenuItem(value: '1/8T', label: '1/8T'),
    BoojyMenuItem(value: '1/16', label: '1/16'),
    BoojyMenuItem(value: '1/16T', label: '1/16T'),
    BoojyMenuItem(value: '1/32', label: '1/32'),
    BoojyMenuItem(value: '1/32T', label: '1/32T'),
  ];

  String _currentQuantizeKey() {
    if (widget.quantizeDivision == 0) return 'grid';
    final suffix = widget.quantizeTripletEnabled ? 'T' : '';
    return '1/${widget.quantizeDivision}$suffix';
  }

  void _applyQuantizePick(String key) {
    if (key == 'grid') {
      widget.onQuantizeDivisionChanged?.call(0);
      widget.onQuantizeTripletChanged?.call(false);
      return;
    }
    final triplet = key.endsWith('T');
    final base = triplet ? key.substring(0, key.length - 1) : key;
    // base is '1/16', '1/8', etc.
    final slashIdx = base.lastIndexOf('/');
    if (slashIdx >= 0) {
      final div = int.tryParse(base.substring(slashIdx + 1));
      if (div != null) {
        widget.onQuantizeDivisionChanged?.call(div);
        widget.onQuantizeTripletChanged?.call(triplet);
      }
    }
  }

  // ============ HELPER WIDGETS ============

  // One-shot action button: same chip shape as toggle buttons but uses a pulse
  // bool rather than a persistent isActive state. Neutral at rest; flashes
  // accent for ~240ms on press to confirm the action fired (like Quantize).
  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool pulse,
    VoidCallback? onTap,
    String? tooltip,
  }) {
    final colors = context.colors;
    final mode = _displayMode;

    final button = GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: pulse
                ? colors.accent.withValues(alpha: BT.opacityLight)
                : colors.surface,
            borderRadius: BT.borderMd,
            border: Border.all(
              color: pulse
                  ? colors.accent.withValues(alpha: 0.7)
                  : colors.textMuted,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mode == _ButtonDisplayMode.wide) ...[
                Icon(
                  icon,
                  size: 13,
                  color: pulse ? colors.accent : colors.textSecondary,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: pulse ? colors.textPrimary : colors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: button);
    }
    return button;
  }

  Widget _buildToggleButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isActive,
    VoidCallback? onTap,
    String? tooltip,
  }) {
    final colors = context.colors;
    final mode = _displayMode;

    final button = GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          // Match the main transport bar's toggle grammar: an outlined chip that
          // fills with a soft accent tint when engaged (not a solid block), so
          // the piano-roll Loop/Snap read the same as the top bar.
          decoration: BoxDecoration(
            color: isActive
                ? colors.accent.withValues(alpha: BT.opacityLight)
                : colors.surface,
            borderRadius: BT.borderMd,
            border: Border.all(
              color: isActive
                  ? colors.accent.withValues(alpha: 0.7)
                  : colors.textMuted,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Show icon only in wide mode
              if (mode == _ButtonDisplayMode.wide) ...[
                Icon(
                  icon,
                  size: 13,
                  color: isActive ? colors.accent : colors.textSecondary,
                ),
                const SizedBox(width: 4),
              ],
              // Always show label
              Text(
                label,
                style: TextStyle(
                  color: isActive ? colors.textPrimary : colors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: button);
    }
    return button;
  }
}
