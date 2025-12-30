import 'package:flutter/material.dart';
import '../../models/scale_data.dart';
import '../../theme/theme_extension.dart';
import '../shared/split_button.dart';
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
  final VoidCallback? onSnapToggle;
  final Function(double)? onGridDivisionChanged;
  final Function(int)? onQuantize;
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

  // Default quantize value
  final int quantizeValue;

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
    this.onSnapToggle,
    this.onGridDivisionChanged,
    this.onQuantize,
    this.swingAmount = 0.0,
    this.onSwingChanged,
    this.onSwingApply,
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
    // Quantize
    this.quantizeValue = 16,
  });

  @override
  State<PianoRollControlsBar> createState() => _PianoRollControlsBarState();
}

class _PianoRollControlsBarState extends State<PianoRollControlsBar> {
  _ButtonDisplayMode _displayMode = _ButtonDisplayMode.wide;
  final GlobalKey _wrapKey = GlobalKey();
  double _lastWidth = 0;

  @override
  void initState() {
    super.initState();
    // Check layout after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkIfFitsOnOneLine());
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Snap split button
        SplitButton<double>(
          label: 'Snap ${_getGridDivisionLabel(widget.gridDivision)}',
          isActive: widget.snapEnabled,
          onLabelTap: widget.onSnapToggle,
          dropdownItems: const [1.0, 0.5, 0.25, 0.125, 0.0625]
              .map((v) => PopupMenuItem<double>(
                    value: v,
                    height: 32,
                    child: Text(_getGridDivisionLabel(v)),
                  ))
              .toList(),
          onItemSelected: widget.onGridDivisionChanged,
        ),
        const SizedBox(width: 4),
        // Quantize split button
        SplitButton<int>(
          label: 'Quantize ${_getQuantizeLabel(widget.quantizeValue)}',
          isActive: false,
          onLabelTap: () => widget.onQuantize?.call(widget.quantizeValue),
          dropdownItems: const [4, 8, 16, 32]
              .map((v) => PopupMenuItem<int>(
                    value: v,
                    height: 32,
                    child: Text(_getQuantizeLabel(v)),
                  ))
              .toList(),
          onItemSelected: (v) => widget.onQuantize?.call(v),
        ),
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

  String _getGridDivisionLabel(double division) {
    if (division == 1.0) return '1/4';
    if (division == 0.5) return '1/8';
    if (division == 0.25) return '1/16';
    if (division == 0.125) return '1/32';
    if (division == 0.0625) return '1/64';
    return '1/${(4 / division).round()}';
  }

  String _getQuantizeLabel(int division) {
    return '1/$division';
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
