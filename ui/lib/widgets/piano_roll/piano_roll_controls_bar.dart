import 'package:flutter/material.dart';
import '../../models/scale_data.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
import 'loop_time_display.dart';
import 'time_signature_display.dart';

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
  final int beatUnit;
  final VoidCallback? onLoopToggle;
  final Function(double)? onLoopStartChanged;
  final Function(double)? onLoopLengthChanged;
  final Function(int)? onBeatsPerBarChanged;

  // Grid section
  final bool snapEnabled;
  final double gridDivision;
  final bool adaptiveGridEnabled;
  final bool snapTripletEnabled;
  final VoidCallback? onSnapToggle;
  final Function(double?)? onGridDivisionChanged; // null = adaptive
  final VoidCallback? onSnapTripletToggle;
  final VoidCallback? onQuantize;
  final int quantizeDivision; // 0 = Grid, else 4/8/16/32
  final bool quantizeTripletEnabled;
  final Function(int)? onQuantizeDivisionChanged;
  final VoidCallback? onQuantizeTripletToggle;

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
    this.beatUnit = 4,
    this.onLoopToggle,
    this.onLoopStartChanged,
    this.onLoopLengthChanged,
    this.onBeatsPerBarChanged,
    // Grid section
    this.snapEnabled = true,
    this.gridDivision = 0.25,
    this.adaptiveGridEnabled = true,
    this.snapTripletEnabled = false,
    this.onSnapToggle,
    this.onGridDivisionChanged,
    this.onSnapTripletToggle,
    this.onQuantize,
    this.quantizeDivision = 0,
    this.quantizeTripletEnabled = false,
    this.onQuantizeDivisionChanged,
    this.onQuantizeTripletToggle,
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

  // Quantize is a one-shot action, not a toggle: it briefly flashes accent on
  // press to confirm it fired, then settles back to neutral (a toggle would
  // instead *stay* lit). This is the visual cue that it applies rather than
  // turning something on/off.
  bool _quantizePulse = false;

  void _fireQuantize() {
    widget.onQuantize?.call();
    setState(() => _quantizePulse = true);
    Future.delayed(const Duration(milliseconds: 240), () {
      if (mounted) setState(() => _quantizePulse = false);
    });
  }

  // Keys and overlays for dropdown menus
  final GlobalKey _snapButtonKey = GlobalKey();
  final GlobalKey _quantizeButtonKey = GlobalKey();
  OverlayEntry? _snapOverlay;
  OverlayEntry? _quantizeOverlay;

  @override
  void initState() {
    super.initState();
    // Check layout after first frame
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkIfFitsOnOneLine(),
    );
  }

  @override
  void dispose() {
    _removeSnapOverlay();
    _removeQuantizeOverlay();
    super.dispose();
  }

  void _removeSnapOverlay() {
    _snapOverlay?.remove();
    _snapOverlay = null;
  }

  void _removeQuantizeOverlay() {
    _quantizeOverlay?.remove();
    _quantizeOverlay = null;
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
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
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
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: colors.surface, width: 1),
          ),
          child: TimeSignatureDisplay(
            beatsPerBar: widget.beatsPerBar,
            beatUnit: widget.beatUnit,
            onBeatsPerBarChanged: widget.onBeatsPerBarChanged,
          ),
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
          'Snap ${_getGridDivisionLabel(widget.gridDivision, triplet: widget.snapTripletEnabled)}';
    }

    // Quantize label: "Quantize" when grid, "Quantize (T)" with triplet, "Quantize 1/16T" when fixed
    String quantizeLabel;
    if (widget.quantizeDivision == 0) {
      quantizeLabel = widget.quantizeTripletEnabled
          ? 'Quantize (T)'
          : 'Quantize';
    } else {
      quantizeLabel =
          'Quantize ${_getQuantizeDivisionLabel(widget.quantizeDivision, triplet: widget.quantizeTripletEnabled)}';
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
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BT.borderSm,
        border: Border.all(
          color: widget.snapEnabled ? colors.selectionBorder : colors.textMuted,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: _isHoveringSnapLabel
                      ? (widget.snapEnabled
                            ? colors.selectionFillHover
                            : colors.textPrimary.withValues(alpha: 0.1))
                      : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(2),
                    bottomLeft: Radius.circular(2),
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
            height: 15,
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
              onTap: () => _showSnapMenu(context),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                decoration: BoxDecoration(
                  color: _isHoveringSnapDropdown
                      ? (widget.snapEnabled
                            ? colors.selectionFillHover
                            : colors.textPrimary.withValues(alpha: 0.1))
                      : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(2),
                    bottomRight: Radius.circular(2),
                  ),
                ),
                child: Icon(BI.caretDown, size: 15, color: textColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnapMenu(BuildContext context) {
    if (_snapOverlay != null) {
      _removeSnapOverlay();
      return;
    }

    final RenderBox? button =
        _snapButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (button == null) return;

    final buttonPosition = button.localToGlobal(Offset.zero);
    final buttonSize = button.size;

    _snapOverlay = OverlayEntry(
      builder: (context) => _SnapMenuOverlay(
        position: Offset(
          buttonPosition.dx,
          buttonPosition.dy + buttonSize.height + 2,
        ),
        adaptiveGridEnabled: widget.adaptiveGridEnabled,
        gridDivision: widget.gridDivision,
        snapTripletEnabled: widget.snapTripletEnabled,
        onDivisionChanged: (div) {
          widget.onGridDivisionChanged?.call(div);
        },
        onTripletToggle: () {
          widget.onSnapTripletToggle?.call();
        },
        onClose: _removeSnapOverlay,
      ),
    );

    Overlay.of(context).insert(_snapOverlay!);
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
      decoration: BoxDecoration(
        color: pulsing ? colors.accent.withValues(alpha: 0.22) : colors.surface,
        borderRadius: BT.borderSm,
        border: Border.all(color: dividerColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: _isHoveringQuantizeLabel
                      ? colors.textPrimary.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(2),
                    bottomLeft: Radius.circular(2),
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
          Container(width: 1, height: 15, color: dividerColor),

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
              onTap: () => _showQuantizeMenu(context),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                decoration: BoxDecoration(
                  color: _isHoveringQuantizeDropdown
                      ? colors.textPrimary.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(2),
                    bottomRight: Radius.circular(2),
                  ),
                ),
                child: Icon(BI.caretDown, size: 15, color: caretColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showQuantizeMenu(BuildContext context) {
    if (_quantizeOverlay != null) {
      _removeQuantizeOverlay();
      return;
    }

    final RenderBox? button =
        _quantizeButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (button == null) return;

    final buttonPosition = button.localToGlobal(Offset.zero);
    final buttonSize = button.size;

    _quantizeOverlay = OverlayEntry(
      builder: (context) => _QuantizeMenuOverlay(
        position: Offset(
          buttonPosition.dx,
          buttonPosition.dy + buttonSize.height + 2,
        ),
        quantizeDivision: widget.quantizeDivision,
        quantizeTripletEnabled: widget.quantizeTripletEnabled,
        onDivisionChanged: (div) {
          widget.onQuantizeDivisionChanged?.call(div);
        },
        onTripletToggle: () {
          widget.onQuantizeTripletToggle?.call();
        },
        onClose: _removeQuantizeOverlay,
      ),
    );

    Overlay.of(context).insert(_quantizeOverlay!);
  }

  // ============ HELPER WIDGETS ============

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
            borderRadius: BT.borderSm,
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

  // ============ FORMATTERS ============

  String _getGridDivisionLabel(double division, {bool triplet = false}) {
    final suffix = triplet ? 'T' : '';
    if (division >= 4.0) return '1 Bar$suffix';
    if (division >= 2.0) return '1/2$suffix';
    if (division >= 1.0) return '1/4$suffix';
    if (division >= 0.5) return '1/8$suffix';
    if (division >= 0.25) return '1/16$suffix';
    if (division >= 0.125) return '1/32$suffix';
    if (division >= 0.0625) return '1/64$suffix';
    return '1/128$suffix';
  }

  String _getQuantizeDivisionLabel(int division, {bool triplet = false}) {
    final suffix = triplet ? 'T' : '';
    return '1/$division$suffix';
  }
}

/// Overlay menu for Snap settings - stays open until explicitly closed
class _SnapMenuOverlay extends StatefulWidget {
  final Offset position;
  final bool adaptiveGridEnabled;
  final double gridDivision;
  final bool snapTripletEnabled;
  final Function(double?) onDivisionChanged;
  final VoidCallback onTripletToggle;
  final VoidCallback onClose;

  const _SnapMenuOverlay({
    required this.position,
    required this.adaptiveGridEnabled,
    required this.gridDivision,
    required this.snapTripletEnabled,
    required this.onDivisionChanged,
    required this.onTripletToggle,
    required this.onClose,
  });

  @override
  State<_SnapMenuOverlay> createState() => _SnapMenuOverlayState();
}

class _SnapMenuOverlayState extends State<_SnapMenuOverlay> {
  late bool _adaptiveEnabled;
  late double _division;
  late bool _tripletEnabled;

  @override
  void initState() {
    super.initState();
    _adaptiveEnabled = widget.adaptiveGridEnabled;
    _division = widget.gridDivision;
    _tripletEnabled = widget.snapTripletEnabled;
  }

  @override
  Widget build(BuildContext context) {
    const divisions = [1.0, 0.5, 0.25, 0.125];

    return Stack(
      children: [
        // Tap outside to close
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.opaque,
            child: Container(color: Colors.transparent),
          ),
        ),
        // Menu popup
        Positioned(
          left: widget.position.dx,
          top: widget.position.dy,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(minWidth: 100),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF404040)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Adaptive option
                  _buildMenuItem(
                    label: 'Adaptive',
                    isSelected: _adaptiveEnabled,
                    onTap: () {
                      setState(() => _adaptiveEnabled = true);
                      widget.onDivisionChanged(null);
                    },
                  ),
                  const Divider(height: 1, color: Color(0xFF404040)),
                  // Division options
                  for (final div in divisions)
                    _buildMenuItem(
                      label: _getGridDivisionLabel(div),
                      isSelected: !_adaptiveEnabled && _division == div,
                      onTap: () {
                        setState(() {
                          _adaptiveEnabled = false;
                          _division = div;
                        });
                        widget.onDivisionChanged(div);
                      },
                    ),
                  const Divider(height: 1, color: Color(0xFF404040)),
                  // Triplet checkbox
                  _buildMenuItem(
                    label: 'Triplet',
                    isSelected: _tripletEnabled,
                    isCheckbox: true,
                    onTap: () {
                      setState(() => _tripletEnabled = !_tripletEnabled);
                      widget.onTripletToggle();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem({
    required String label,
    required bool isSelected,
    bool isCheckbox = false,
    required VoidCallback onTap,
  }) {
    const menuTextColor = Colors.white70;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              child: Icon(
                isCheckbox
                    ? (isSelected ? BI.checkBox : BI.checkBoxBlank)
                    : (isSelected ? BI.check : null),
                size: 14,
                color: menuTextColor,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: menuTextColor,
                fontSize: BT.fontLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _getGridDivisionLabel(double division) {
    if (division >= 4.0) return '1 Bar';
    if (division >= 2.0) return '1/2';
    if (division >= 1.0) return '1/4';
    if (division >= 0.5) return '1/8';
    if (division >= 0.25) return '1/16';
    if (division >= 0.125) return '1/32';
    if (division >= 0.0625) return '1/64';
    return '1/128';
  }
}

/// Overlay menu for Quantize settings - stays open until explicitly closed
class _QuantizeMenuOverlay extends StatefulWidget {
  final Offset position;
  final int quantizeDivision;
  final bool quantizeTripletEnabled;
  final Function(int) onDivisionChanged;
  final VoidCallback onTripletToggle;
  final VoidCallback onClose;

  const _QuantizeMenuOverlay({
    required this.position,
    required this.quantizeDivision,
    required this.quantizeTripletEnabled,
    required this.onDivisionChanged,
    required this.onTripletToggle,
    required this.onClose,
  });

  @override
  State<_QuantizeMenuOverlay> createState() => _QuantizeMenuOverlayState();
}

class _QuantizeMenuOverlayState extends State<_QuantizeMenuOverlay> {
  late int _division;
  late bool _tripletEnabled;

  @override
  void initState() {
    super.initState();
    _division = widget.quantizeDivision;
    _tripletEnabled = widget.quantizeTripletEnabled;
  }

  @override
  Widget build(BuildContext context) {
    const divisions = [4, 8, 16, 32];

    return Stack(
      children: [
        // Tap outside to close
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.opaque,
            child: Container(color: Colors.transparent),
          ),
        ),
        // Menu popup
        Positioned(
          left: widget.position.dx,
          top: widget.position.dy,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(minWidth: 100),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF404040)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Grid option
                  _buildMenuItem(
                    label: 'Grid',
                    isSelected: _division == 0,
                    onTap: () {
                      setState(() => _division = 0);
                      widget.onDivisionChanged(0);
                    },
                  ),
                  const Divider(height: 1, color: Color(0xFF404040)),
                  // Division options
                  for (final div in divisions)
                    _buildMenuItem(
                      label: '1/$div',
                      isSelected: _division == div,
                      onTap: () {
                        setState(() => _division = div);
                        widget.onDivisionChanged(div);
                      },
                    ),
                  // Only show triplet when NOT on Grid
                  if (_division != 0) ...[
                    const Divider(height: 1, color: Color(0xFF404040)),
                    _buildMenuItem(
                      label: 'Triplet',
                      isSelected: _tripletEnabled,
                      isCheckbox: true,
                      onTap: () {
                        setState(() => _tripletEnabled = !_tripletEnabled);
                        widget.onTripletToggle();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem({
    required String label,
    required bool isSelected,
    bool isCheckbox = false,
    required VoidCallback onTap,
  }) {
    const menuTextColor = Colors.white70;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              child: Icon(
                isCheckbox
                    ? (isSelected ? BI.checkBox : BI.checkBoxBlank)
                    : (isSelected ? BI.check : null),
                size: 14,
                color: menuTextColor,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: menuTextColor,
                fontSize: BT.fontLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
