import 'package:flutter/material.dart';
import '../../models/scale_data.dart';
import '../../theme/theme_extension.dart';
import '../shared/knob_split_button.dart';
import 'loop_time_display.dart';
import 'time_signature_display.dart';

/// Display mode for responsive icon/label buttons
enum _ButtonDisplayMode {
  wide,   // Icon + Label
  medium, // Label only
  narrow, // Icon only
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
  final Function(int)? onBeatUnitChanged;

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
  final double swingAmount;
  final Function(double)? onSwingChanged;
  final VoidCallback? onSwingApply;

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
  final bool chordsEnabled;
  final Function(String)? onRootChanged;
  final Function(ScaleType)? onTypeChanged;
  final VoidCallback? onHighlightToggle;
  final VoidCallback? onLockToggle;
  final VoidCallback? onChordsToggle;

  // Transform section
  final double stretchAmount;
  final double humanizeAmount;
  final VoidCallback? onLegato;
  final Function(double)? onStretchChanged;
  final VoidCallback? onStretchApply;
  final Function(double)? onHumanizeChanged;
  final VoidCallback? onHumanizeApply;
  final VoidCallback? onReverse;

  // Lane visibility toggles (Randomize/CC type moved to lane headers)
  final bool velocityLaneVisible;
  final VoidCallback? onVelocityLaneToggle;
  final bool ccLaneVisible;
  final VoidCallback? onCCLaneToggle;

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
    this.onBeatUnitChanged,
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
    this.swingAmount = 0.0,
    this.onSwingChanged,
    this.onSwingApply,
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
    this.chordsEnabled = false,
    this.onRootChanged,
    this.onTypeChanged,
    this.onHighlightToggle,
    this.onLockToggle,
    this.onChordsToggle,
    // Transform section
    this.stretchAmount = 1.0,
    this.humanizeAmount = 0.0,
    this.onLegato,
    this.onStretchChanged,
    this.onStretchApply,
    this.onHumanizeChanged,
    this.onHumanizeApply,
    this.onReverse,
    // Lane visibility toggles
    this.velocityLaneVisible = false,
    this.onVelocityLaneToggle,
    this.ccLaneVisible = false,
    this.onCCLaneToggle,
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

  // Keys and overlays for dropdown menus
  final GlobalKey _snapButtonKey = GlobalKey();
  final GlobalKey _quantizeButtonKey = GlobalKey();
  OverlayEntry? _snapOverlay;
  OverlayEntry? _quantizeOverlay;

  @override
  void initState() {
    super.initState();
    // Check layout after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkIfFitsOnOneLine());
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
      // Content wrapped - try a more compact mode
      if (_displayMode == _ButtonDisplayMode.wide) {
        setState(() => _displayMode = _ButtonDisplayMode.medium);
        WidgetsBinding.instance.addPostFrameCallback((_) => _checkIfFitsOnOneLine());
      } else if (_displayMode == _ButtonDisplayMode.medium) {
        setState(() => _displayMode = _ButtonDisplayMode.narrow);
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
                WidgetsBinding.instance.addPostFrameCallback((_) => _checkIfFitsOnOneLine());
              }
            });
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) => _checkIfFitsOnOneLine());
          }
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.standard,
            border: Border(
              bottom: BorderSide(color: colors.surface, width: 1),
            ),
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

                    // === TRANSFORM GROUP ===
                    _buildTransformGroup(context),
                    _buildSeparator(context),

                    // === LANES GROUP (visibility toggles only) ===
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
    return Container(
      width: 1,
      height: 20,
      color: context.colors.surface,
    );
  }

  // ============ CLIP GROUP ============
  Widget _buildClipGroup(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Loop toggle
        _buildToggleButton(
          context,
          icon: Icons.loop,
          label: 'Loop',
          isActive: widget.loopEnabled,
          onTap: widget.onLoopToggle,
        ),
        const SizedBox(width: 8),
        // Start label + input
        Text('Start', style: TextStyle(color: colors.textMuted, fontSize: 9)),
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
        Text('Length', style: TextStyle(color: colors.textMuted, fontSize: 9)),
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
        Text('Signature', style: TextStyle(color: colors.textMuted, fontSize: 9)),
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
            onBeatUnitChanged: widget.onBeatUnitChanged,
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
      snapLabel = 'Snap ${_getGridDivisionLabel(widget.gridDivision, triplet: widget.snapTripletEnabled)}';
    }

    // Quantize label: "Quantize" when grid, "Quantize (T)" with triplet, "Quantize 1/16T" when fixed
    String quantizeLabel;
    if (widget.quantizeDivision == 0) {
      quantizeLabel = widget.quantizeTripletEnabled ? 'Quantize (T)' : 'Quantize';
    } else {
      quantizeLabel = 'Quantize ${_getQuantizeDivisionLabel(widget.quantizeDivision, triplet: widget.quantizeTripletEnabled)}';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Snap split button with adaptive + triplet
        _buildSnapDropdown(context, snapLabel),
        const SizedBox(width: 4),
        // Quantize split button with grid + triplet
        _buildQuantizeDropdown(context, quantizeLabel),
        const SizedBox(width: 4),
        // Fold toggle
        _buildToggleButton(
          context,
          icon: Icons.unfold_less,
          label: 'Fold',
          isActive: widget.foldEnabled,
          onTap: widget.onFoldToggle,
        ),
        const SizedBox(width: 4),
        // Ghost toggle
        _buildToggleButton(
          context,
          icon: Icons.layers,
          label: 'Ghost',
          isActive: widget.ghostNotesEnabled,
          onTap: widget.onGhostNotesToggle,
        ),
        const SizedBox(width: 4),
        // Swing knob split button
        KnobSplitButton(
          label: 'Swing',
          value: widget.swingAmount,
          min: 0.0,
          max: 1.0,
          valueFormatter: (v) => '${(v * 100).round()}%',
          onChanged: widget.onSwingChanged,
          onApply: widget.onSwingApply,
        ),
      ],
    );
  }

  Widget _buildSnapDropdown(BuildContext context, String label) {
    final colors = context.colors;
    final bgColor = widget.snapEnabled ? colors.accent : colors.dark;
    final textColor = widget.snapEnabled ? colors.elevated : colors.textPrimary;

    return DecoratedBox(
      key: _snapButtonKey,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Left side: Label (clickable for toggle)
          MouseRegion(
            onEnter: (_) => setState(() => _isHoveringSnapLabel = true),
            onExit: (_) => setState(() => _isHoveringSnapLabel = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onSnapToggle,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: _isHoveringSnapLabel
                      ? colors.textPrimary.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(2),
                    bottomLeft: Radius.circular(2),
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 9,
                  ),
                ),
              ),
            ),
          ),

          // Divider line
          Container(
            width: 1,
            height: 14,
            color: colors.textPrimary.withValues(alpha: 0.2),
          ),

          // Right side: Dropdown arrow
          MouseRegion(
            onEnter: (_) => setState(() => _isHoveringSnapDropdown = true),
            onExit: (_) => setState(() => _isHoveringSnapDropdown = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _showSnapMenu(context),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: _isHoveringSnapDropdown
                      ? colors.textPrimary.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(2),
                    bottomRight: Radius.circular(2),
                  ),
                ),
                child: Icon(
                  Icons.arrow_drop_down,
                  size: 14,
                  color: textColor,
                ),
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
        position: Offset(buttonPosition.dx, buttonPosition.dy + buttonSize.height + 2),
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
    final textColor = colors.textPrimary;

    return DecoratedBox(
      key: _quantizeButtonKey,
      decoration: BoxDecoration(
        color: colors.dark,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Left side: Label (clickable for quantize action)
          MouseRegion(
            onEnter: (_) => setState(() => _isHoveringQuantizeLabel = true),
            onExit: (_) => setState(() => _isHoveringQuantizeLabel = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onQuantize,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: _isHoveringQuantizeLabel
                      ? colors.textPrimary.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(2),
                    bottomLeft: Radius.circular(2),
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 9,
                  ),
                ),
              ),
            ),
          ),

          // Divider line
          Container(
            width: 1,
            height: 14,
            color: colors.textPrimary.withValues(alpha: 0.2),
          ),

          // Right side: Dropdown arrow
          MouseRegion(
            onEnter: (_) => setState(() => _isHoveringQuantizeDropdown = true),
            onExit: (_) => setState(() => _isHoveringQuantizeDropdown = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _showQuantizeMenu(context),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: _isHoveringQuantizeDropdown
                      ? colors.textPrimary.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(2),
                    bottomRight: Radius.circular(2),
                  ),
                ),
                child: Icon(
                  Icons.arrow_drop_down,
                  size: 14,
                  color: textColor,
                ),
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
        position: Offset(buttonPosition.dx, buttonPosition.dy + buttonSize.height + 2),
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

  // ============ SCALE GROUP ============
  Widget _buildScaleGroup(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Scale dropdown (combined root + type)
        _buildScaleDropdown(context),
        const SizedBox(width: 4),
        // Chords toggle (green outlined style)
        _buildChordsButton(context),
        const SizedBox(width: 4),
        // Highlight toggle
        _buildToggleButton(
          context,
          icon: Icons.visibility,
          label: 'Highlight',
          isActive: widget.highlightEnabled,
          onTap: widget.onHighlightToggle,
        ),
        const SizedBox(width: 4),
        // Lock toggle
        _buildToggleButton(
          context,
          icon: Icons.lock,
          label: 'Lock',
          isActive: widget.lockEnabled,
          onTap: widget.onLockToggle,
        ),
      ],
    );
  }

  // ============ TRANSFORM GROUP ============
  Widget _buildTransformGroup(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Legato button
        _buildActionButton(
          context,
          icon: Icons.linear_scale,
          label: 'Legato',
          onTap: widget.onLegato,
        ),
        const SizedBox(width: 4),
        // Reverse button
        _buildActionButton(
          context,
          icon: Icons.swap_horiz,
          label: 'Reverse',
          onTap: widget.onReverse,
        ),
        const SizedBox(width: 4),
        // Stretch knob split button
        KnobSplitButton(
          label: 'Stretch',
          value: widget.stretchAmount,
          min: 0.5,
          max: 2.0,
          valueFormatter: _stretchFormatter,
          onChanged: widget.onStretchChanged,
          onApply: widget.onStretchApply,
        ),
        const SizedBox(width: 4),
        // Humanize knob split button
        KnobSplitButton(
          label: 'Humanize',
          value: widget.humanizeAmount,
          min: 0.0,
          max: 1.0,
          valueFormatter: (v) => '${(v * 100).round()}%',
          onChanged: widget.onHumanizeChanged,
          onApply: widget.onHumanizeApply,
        ),
      ],
    );
  }

  // ============ LANES GROUP (visibility toggles only) ============
  Widget _buildLanesGroup(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Velocity lane visibility toggle
        _buildToggleButton(
          context,
          icon: Icons.visibility,
          label: 'Velocity',
          isActive: widget.velocityLaneVisible,
          onTap: widget.onVelocityLaneToggle,
        ),
        const SizedBox(width: 4),
        // CC lane visibility toggle
        _buildToggleButton(
          context,
          icon: Icons.visibility,
          label: 'MIDI CC',
          isActive: widget.ccLaneVisible,
          onTap: widget.onCCLaneToggle,
        ),
        const SizedBox(width: 4),
        // Virtual Piano visibility toggle (computer keyboard icon)
        _buildToggleButton(
          context,
          icon: Icons.keyboard,
          label: 'Piano',
          isActive: widget.virtualPianoVisible,
          onTap: widget.onVirtualPianoToggle,
        ),
      ],
    );
  }

  // ============ HELPER WIDGETS ============

  Widget _buildToggleButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isActive,
    VoidCallback? onTap,
  }) {
    final colors = context.colors;
    final mode = _displayMode;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? colors.accent : colors.dark,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Show icon in wide and narrow modes
              if (mode == _ButtonDisplayMode.wide || mode == _ButtonDisplayMode.narrow)
                Icon(
                  icon,
                  size: 12,
                  color: isActive ? colors.elevated : colors.textPrimary,
                ),
              // Show spacing between icon and label in wide mode only
              if (mode == _ButtonDisplayMode.wide)
                const SizedBox(width: 4),
              // Show label in wide and medium modes
              if (mode == _ButtonDisplayMode.wide || mode == _ButtonDisplayMode.medium)
                Text(
                  label,
                  style: TextStyle(
                    color: isActive ? colors.elevated : colors.textPrimary,
                    fontSize: 9,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    final colors = context.colors;
    final mode = _displayMode;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Show icon in wide and narrow modes
              if (mode == _ButtonDisplayMode.wide || mode == _ButtonDisplayMode.narrow)
                Icon(icon, size: 12, color: colors.textPrimary),
              // Show spacing between icon and label in wide mode only
              if (mode == _ButtonDisplayMode.wide)
                const SizedBox(width: 4),
              // Show label in wide and medium modes
              if (mode == _ButtonDisplayMode.wide || mode == _ButtonDisplayMode.medium)
                Text(
                  label,
                  style: TextStyle(color: colors.textPrimary, fontSize: 9),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScaleDropdown(BuildContext context) {
    final colors = context.colors;
    final displayLabel = '${widget.scaleRoot} ${widget.scaleType.displayName}';

    return GestureDetector(
      onTap: () => _showScaleMenu(context),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayLabel,
                style: TextStyle(color: colors.textPrimary, fontSize: 9),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 14, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  void _showScaleMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);

    // Build menu items: first root notes, then scale types
    final items = <PopupMenuEntry<dynamic>>[];

    // Root note selection
    for (final root in ScaleRoot.noteNames) {
      items.add(PopupMenuItem<String>(
        value: root,
        height: 28,
        child: Text(
          root,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 11,
            fontWeight: root == widget.scaleRoot ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ));
    }

    items.add(const PopupMenuDivider());

    // Scale type selection
    for (final type in ScaleType.values) {
      items.add(PopupMenuItem<ScaleType>(
        value: type,
        height: 28,
        child: Text(
          type.displayName,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 11,
            fontWeight: type == widget.scaleType ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ));
    }

    showMenu<dynamic>(
      context: context,
      position: RelativeRect.fromLTRB(
        buttonPosition.dx,
        buttonPosition.dy + button.size.height,
        overlay.size.width - buttonPosition.dx - button.size.width,
        0,
      ),
      items: items,
      elevation: 8,
    ).then((value) {
      if (value is String) {
        widget.onRootChanged?.call(value);
      } else if (value is ScaleType) {
        widget.onTypeChanged?.call(value);
      }
    });
  }

  // Mint green color for Chords button
  static const Color _chordsGreen = Color(0xFF10B981);

  Widget _buildChordsButton(BuildContext context) {
    final isActive = widget.chordsEnabled;

    return GestureDetector(
      onTap: widget.onChordsToggle,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? _chordsGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: _chordsGreen, width: 1),
          ),
          child: Text(
            'Chords',
            style: TextStyle(
              color: isActive ? Colors.white : _chordsGreen,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
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

  static String _stretchFormatter(double v) {
    if (v < 1.0) {
      final divisor = 1 / v;
      return '÷${divisor.toStringAsFixed(divisor >= 1.5 ? 0 : 1)}';
    }
    if (v == 1.0) return '×1';
    return '×${v.toStringAsFixed(v >= 1.5 ? 0 : 1)}';
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
                    ? (isSelected ? Icons.check_box : Icons.check_box_outline_blank)
                    : (isSelected ? Icons.check : null),
                size: 14,
                color: menuTextColor,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(color: menuTextColor, fontSize: 11),
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
                    ? (isSelected ? Icons.check_box : Icons.check_box_outline_blank)
                    : (isSelected ? Icons.check : null),
                size: 14,
                color: menuTextColor,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(color: menuTextColor, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
