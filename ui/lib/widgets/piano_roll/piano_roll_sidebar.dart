import 'package:flutter/material.dart';
import '../../models/scale_data.dart';
import '../../theme/theme_extension.dart';
import '../shared/mini_knob.dart';
import '../shared/split_button.dart';
import 'loop_time_display.dart';
import 'time_signature_display.dart';

/// CC type options for MIDI CC lane
enum CCType {
  pitchBend('Pitch Bend'),
  modWheel('Mod Wheel'),
  expression('Expression'),
  sustain('Sustain'),
  volume('Volume');

  final String displayName;
  const CCType(this.displayName);
}

/// View modes for the piano roll sidebar
enum SidebarView {
  pianoRoll,
  effects,
  instrument,
}

/// Comprehensive sidebar for Piano Roll with 7 sections:
/// - Track info (header)
/// - TOOLS: Draw, Select, Eraser, Duplicate, Slice
/// - CLIP: Loop, Start, Length, Time Signature
/// - GRID: Snap, Quantize, Fold, Ghost
/// - SCALE: Root, Type, Highlight, Lock
/// - NOTES: Legato, Stretch, Humanize, Reverse
/// - VELOCITY: Lane toggle, Randomize
/// - MIDI CC: Lane toggle, CC type selector
class PianoRollSidebar extends StatelessWidget {
  // Track info
  final int? trackNumber;
  final String? trackName;
  final String trackEmoji;

  /// Track color for header background (20% opacity)
  final Color? trackColor;

  /// List of clip names for dropdown
  final List<String> clipNames;

  /// Currently selected clip index
  final int selectedClipIndex;

  /// Called when a clip is selected from dropdown
  final Function(int)? onClipSelected;

  /// Whether the sidebar is collapsed
  final bool isCollapsed;

  /// Called when collapse state should toggle
  final VoidCallback? onCollapseToggle;

  /// Current view mode (Piano Roll, Effects, Instrument)
  final SidebarView currentView;

  /// Called when view mode changes
  final Function(SidebarView)? onViewChanged;

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

  // View section
  final bool foldEnabled;
  final bool ghostNotesEnabled;
  final VoidCallback? onFoldToggle;
  final VoidCallback? onGhostNotesToggle;

  // Notes section (transform tools)
  final double stretchAmount;
  final double humanizeAmount;
  final VoidCallback? onLegato;
  final Function(double)? onStretchChanged;
  final VoidCallback? onStretchApply;
  final Function(double)? onHumanizeChanged;
  final VoidCallback? onHumanizeApply;
  final VoidCallback? onReverse;

  // Velocity section
  final bool velocityLaneVisible;
  final VoidCallback? onVelocityLaneToggle;
  final double velocityRandomize;
  final Function(double)? onVelocityRandomizeChanged;
  final VoidCallback? onVelocityRandomizeApply;

  // MIDI CC section
  final bool ccLaneVisible;
  final VoidCallback? onCCLaneToggle;
  final CCType ccType;
  final Function(CCType)? onCCTypeChanged;

  // Resizable width
  final double width;
  final Function(double)? onWidthChanged;

  static const double defaultWidth = 250.0;
  static const double minWidth = 220.0;
  static const double maxWidth = 350.0;

  static const double collapsedWidth = 60.0;

  const PianoRollSidebar({
    super.key,
    // Track info
    this.trackNumber,
    this.trackName,
    this.trackEmoji = '\u{1F3B9}', // Piano emoji
    this.trackColor,
    this.clipNames = const [],
    this.selectedClipIndex = 0,
    this.onClipSelected,
    this.isCollapsed = false,
    this.onCollapseToggle,
    this.currentView = SidebarView.pianoRoll,
    this.onViewChanged,
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
    // View section
    this.foldEnabled = false,
    this.ghostNotesEnabled = false,
    this.onFoldToggle,
    this.onGhostNotesToggle,
    // Notes section
    this.stretchAmount = 1.0,
    this.humanizeAmount = 0.0,
    this.onLegato,
    this.onStretchChanged,
    this.onStretchApply,
    this.onHumanizeChanged,
    this.onHumanizeApply,
    this.onReverse,
    // Velocity section
    this.velocityLaneVisible = false,
    this.onVelocityLaneToggle,
    this.velocityRandomize = 0.0,
    this.onVelocityRandomizeChanged,
    this.onVelocityRandomizeApply,
    // MIDI CC section
    this.ccLaneVisible = false,
    this.onCCLaneToggle,
    this.ccType = CCType.pitchBend,
    this.onCCTypeChanged,
    // Resizable width
    this.width = defaultWidth,
    this.onWidthChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Return collapsed layout if collapsed
    if (isCollapsed) {
      return _buildCollapsedLayout(context);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main sidebar content
        Container(
          width: width,
          decoration: BoxDecoration(
            color: colors.standard,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // FIXED HEADER (not scrollable)
              _buildTrackInfo(context),
              // TOOLS section removed - now in Piano Roll toolbar

              // SCROLLABLE BODY
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // CLIP section
                      _buildSection(context, 'CLIP', _buildClipContent(context)),
                      // GRID section
                      _buildSection(context, 'GRID', _buildGridContent(context)),
                      // SCALE section
                      _buildSection(context, 'SCALE', _buildScaleContent(context)),
                      // NOTES section
                      _buildSection(context, 'TRANSFORM', _buildNotesContent(context)),
                      // LANES section (combined Velocity + MIDI CC)
                      _buildSection(context, 'LANES', _buildLanesContent(context)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Resize handle on the right edge
        _buildResizeHandle(context),
      ],
    );
  }

  /// Build the collapsed sidebar layout (60px width)
  Widget _buildCollapsedLayout(BuildContext context) {
    final colors = context.colors;
    final headerColor = trackColor ?? colors.accent;

    return Container(
      width: collapsedWidth,
      decoration: BoxDecoration(
        color: colors.standard,
      ),
      child: Column(
        children: [
          // Track color header bar with expand button
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: headerColor.withValues(alpha: 0.2),
              border: Border(
                bottom: BorderSide(color: colors.surface, width: 1),
              ),
            ),
            child: Center(
              child: GestureDetector(
                onTap: onCollapseToggle,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: colors.dark,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Tool icons removed - now in Piano Roll toolbar

          const Spacer(),

          // View switcher icons at bottom
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colors.surface, width: 1),
              ),
            ),
            child: Column(
              children: [
                _buildViewSwitchButton(context, view: SidebarView.pianoRoll, icon: Icons.piano, tooltip: 'Piano Roll'),
                const SizedBox(height: 4),
                _buildViewSwitchButton(context, view: SidebarView.effects, icon: Icons.equalizer, tooltip: 'Effects'),
                const SizedBox(height: 4),
                _buildViewSwitchButton(context, view: SidebarView.instrument, icon: Icons.music_note, tooltip: 'Instrument'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build a view switcher button for collapsed state
  Widget _buildViewSwitchButton(
    BuildContext context, {
    required SidebarView view,
    required IconData icon,
    required String tooltip,
  }) {
    final colors = context.colors;
    final isActive = currentView == view;

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () => onViewChanged?.call(view),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isActive ? colors.accent : colors.dark,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              icon,
              size: 16,
              color: isActive ? colors.elevated : colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  /// Build the draggable resize handle on the right edge
  Widget _buildResizeHandle(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        if (onWidthChanged != null) {
          final newWidth = (width + details.delta.dx).clamp(minWidth, maxWidth);
          onWidthChanged!(newWidth);
        }
      },
      onDoubleTap: () {
        // Reset to default width on double-tap
        onWidthChanged?.call(defaultWidth);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: 4,
          color: colors.surface,
        ),
      ),
    );
  }

  Widget _buildTrackInfo(BuildContext context) {
    final colors = context.colors;
    final displayName = trackName ?? 'MIDI Track';
    final displayNumber = trackNumber ?? 1;
    final headerColor = trackColor ?? colors.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: headerColor.withValues(alpha: 0.2),
        border: Border(
          bottom: BorderSide(color: colors.surface, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Emoji
          Text(
            trackEmoji,
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(width: 4),
          // Track number and name
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    '$displayNumber $displayName',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Clip dropdown (only show if clips available)
                if (clipNames.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _buildClipDropdown(context),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          // Collapse button
          GestureDetector(
            onTap: onCollapseToggle,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: colors.dark,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Icon(
                  Icons.chevron_left,
                  size: 14,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build clip dropdown selector
  Widget _buildClipDropdown(BuildContext context) {
    final colors = context.colors;
    final currentClipName = selectedClipIndex < clipNames.length
        ? clipNames[selectedClipIndex]
        : 'Clip';

    return GestureDetector(
      onTap: () => _showClipDropdownMenu(context),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                currentClipName,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 9,
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 12,
                color: colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showClipDropdownMenu(BuildContext context) {
    if (clipNames.isEmpty) return;

    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);

    showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        buttonPosition.dx,
        buttonPosition.dy + button.size.height,
        overlay.size.width - buttonPosition.dx - button.size.width,
        0,
      ),
      items: List.generate(clipNames.length, (index) {
        return PopupMenuItem<int>(
          value: index,
          height: 32,
          child: Text(
            clipNames[index],
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 11,
              fontWeight: index == selectedClipIndex ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      }),
      elevation: 8,
    ).then((value) {
      if (value != null && onClipSelected != null) {
        onClipSelected!(value);
      }
    });
  }

  Widget _buildSection(BuildContext context, String title, Widget content) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: colors.dark,
          child: Text(
            title,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        // Section content
        Padding(
          padding: const EdgeInsets.all(6),
          child: content,
        ),
      ],
    );
  }

  // ============ CLIP Section ============
  Widget _buildClipContent(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Row 1: Loop toggle + Signature - responsive row
        _buildResponsiveRow([
          // Loop toggle
          _buildToggleRow(
            context,
            icon: Icons.loop,
            label: 'Loop',
            isActive: loopEnabled,
            onTap: onLoopToggle,
          ),
          // Signature label + display
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sig',
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 9,
                ),
              ),
              const SizedBox(width: 4),
              TimeSignatureDisplay(
                beatsPerBar: beatsPerBar,
                beatUnit: beatUnit,
                onBeatsPerBarChanged: onBeatsPerBarChanged,
                onBeatUnitChanged: onBeatUnitChanged,
              ),
            ],
          ),
        ]),
        const SizedBox(height: 6),
        // Row 2: Start + Length with labels inline - responsive row
        _buildResponsiveRow([
          // Start time
          _buildBoxedTimeDisplay(
            context,
            label: 'Start',
            beats: loopStartBeats,
            onChanged: onLoopStartChanged,
          ),
          // Length
          _buildBoxedTimeDisplay(
            context,
            label: 'Length',
            beats: loopLengthBeats,
            onChanged: onLoopLengthChanged,
          ),
        ]),
      ],
    );
  }

  /// Build a bordered box containing a time display with label on the left
  Widget _buildBoxedTimeDisplay(
    BuildContext context, {
    required String label,
    required double beats,
    Function(double)? onChanged,
  }) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 9,
          ),
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
            beats: beats,
            label: '',
            onChanged: onChanged,
            beatsPerBar: beatsPerBar,
          ),
        ),
      ],
    );
  }

  // ============ GRID Section ============
  Widget _buildGridContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Snap and Quantize - responsive row
        _buildResponsiveRow([
          SplitButton<double>(
            icon: null,  // No checkmark, color indicates state
            label: 'Snap ${_getGridDivisionLabel(gridDivision)}',
            isActive: snapEnabled,
            onLabelTap: onSnapToggle,
            dropdownItems: const [1.0, 0.5, 0.25, 0.125, 0.0625]
                .map((v) => PopupMenuItem<double>(
                      value: v,
                      height: 32,
                      child: Text(_getGridDivisionLabel(v)),
                    ))
                .toList(),
            onItemSelected: onGridDivisionChanged,
          ),
          SplitButton<int>(
            label: 'Quantize ${_getQuantizeLabel(_quantizeValue)}',
            isActive: false,
            onLabelTap: () => onQuantize?.call(_quantizeValue),
            dropdownItems: const [4, 8, 16, 32]
                .map((v) => PopupMenuItem<int>(
                      value: v,
                      height: 32,
                      child: Text(_getQuantizeLabel(v)),
                    ))
                .toList(),
            onItemSelected: (v) {
              onQuantize?.call(v);
            },
          ),
        ]),
        const SizedBox(height: 4),
        // Fold and Ghost toggles - responsive row
        _buildResponsiveRow([
          _buildToggleRow(
            context,
            icon: Icons.unfold_less,
            label: 'Fold',
            isActive: foldEnabled,
            onTap: onFoldToggle,
          ),
          _buildToggleRow(
            context,
            icon: Icons.layers,
            label: 'Ghost',
            isActive: ghostNotesEnabled,
            onTap: onGhostNotesToggle,
          ),
        ]),
        const SizedBox(height: 4),
        // Swing knob with apply button
        _buildKnobRow(
          context,
          icon: Icons.sync_alt,
          label: 'Swing',
          value: swingAmount,
          min: 0.0,
          max: 1.0,
          onChanged: onSwingChanged,
          onApply: onSwingApply,
          valueFormatter: (v) => '${(v * 100).round()}%',
        ),
      ],
    );
  }

  /// Default quantize value (1/16)
  int get _quantizeValue => 16;

  String _getQuantizeLabel(int division) {
    return '1/$division';
  }

  String _getGridDivisionLabel(double division) {
    if (division == 1.0) return '1/4';
    if (division == 0.5) return '1/8';
    if (division == 0.25) return '1/16';
    if (division == 0.125) return '1/32';
    if (division == 0.0625) return '1/64';
    return '1/${(4 / division).round()}';
  }

  /// Format stretch value: ÷2 to ×2 centered at ×1
  static String _stretchFormatter(double v) {
    if (v < 1.0) {
      final divisor = 1 / v;
      return '÷${divisor.toStringAsFixed(divisor >= 1.5 ? 0 : 1)}';
    }
    if (v == 1.0) return '×1';
    return '×${v.toStringAsFixed(v >= 1.5 ? 0 : 1)}';
  }

  // ============ SCALE Section ============
  // Mint green color for Chords button
  static const Color _chordsGreen = Color(0xFF10B981);

  Widget _buildScaleContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Key row with Chords button
        Row(
          children: [
            // Key label + dropdowns
            Expanded(
              child: _buildLabeledValue(
                context,
                label: 'Key',
                child: Row(
                  children: [
                    Expanded(
                      child: _buildCompactDropdown<String>(
                        context,
                        value: scaleRoot,
                        items: ScaleRoot.noteNames,
                        onChanged: onRootChanged,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      flex: 2,
                      child: _buildCompactDropdown<ScaleType>(
                        context,
                        value: scaleType,
                        items: ScaleType.values,
                        itemLabel: (t) => t.displayName,
                        onChanged: onTypeChanged,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Chords button (green outlined style)
            _buildChordsButton(context),
          ],
        ),
        const SizedBox(height: 4),
        // Highlight and Lock toggles - responsive row
        _buildResponsiveRow([
          _buildToggleRow(
            context,
            icon: Icons.visibility,
            label: 'Highlight',
            isActive: highlightEnabled,
            onTap: onHighlightToggle,
          ),
          _buildToggleRow(
            context,
            icon: Icons.lock,
            label: 'Lock',
            isActive: lockEnabled,
            onTap: onLockToggle,
          ),
        ]),
      ],
    );
  }

  // ============ NOTES Section ============
  Widget _buildNotesContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Legato + Reverse - responsive row
        _buildResponsiveRow([
          _buildActionButton(
            context,
            icon: Icons.linear_scale,
            label: 'Legato',
            onTap: onLegato,
          ),
          _buildActionButton(
            context,
            icon: Icons.swap_horiz,
            label: 'Reverse',
            onTap: onReverse,
          ),
        ]),
        const SizedBox(height: 4),
        // Stretch + Humanize - responsive row
        _buildResponsiveRow([
          _buildKnobRow(
            context,
            icon: Icons.expand,
            label: 'Stretch',
            value: stretchAmount,
            min: 0.5,
            max: 2.0,
            onChanged: onStretchChanged,
            onApply: onStretchApply,
            valueFormatter: _stretchFormatter,
          ),
          _buildKnobRow(
            context,
            icon: Icons.gesture,
            label: 'Humanize',
            value: humanizeAmount,
            min: 0.0,
            max: 1.0,
            onChanged: onHumanizeChanged,
            onApply: onHumanizeApply,
            valueFormatter: (v) => '${(v * 100).round()}%',
          ),
        ]),
      ],
    );
  }

  // ============ LANES Section (combined Velocity + MIDI CC) ============
  Widget _buildLanesContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Row 1: [👁 Velocity] + (0%) [Randomize] - responsive row
        _buildResponsiveRow([
          _buildToggleRow(
            context,
            icon: Icons.visibility,
            label: 'Velocity',
            isActive: velocityLaneVisible,
            onTap: onVelocityLaneToggle,
          ),
          _buildKnobRow(
            context,
            icon: Icons.casino,
            label: 'Randomize',
            value: velocityRandomize,
            min: 0.0,
            max: 1.0,
            onChanged: onVelocityRandomizeChanged,
            onApply: onVelocityRandomizeApply,
            valueFormatter: (v) => '${(v * 100).round()}%',
          ),
        ]),
        const SizedBox(height: 4),
        // Row 2: [👁 MIDI CC] + [Mod Wheel ▾] - responsive row
        _buildResponsiveRow([
          _buildToggleRow(
            context,
            icon: Icons.visibility,
            label: 'MIDI CC',
            isActive: ccLaneVisible,
            onTap: onCCLaneToggle,
          ),
          _buildCompactDropdown<CCType>(
            context,
            value: ccType,
            items: CCType.values,
            itemLabel: (t) => t.displayName,
            onChanged: onCCTypeChanged,
          ),
        ]),
      ],
    );
  }

  // ============ Helper Widgets ============

  /// Responsive row that stacks to column when sidebar width < 250px
  Widget _buildResponsiveRow(List<Widget> children) {
    if (width < 250) {
      // Stack vertically when narrow
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children.map((c) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: c,
        )).toList(),
      );
    }
    // Side by side when wide
    return Row(
      children: [
        for (int i = 0; i < children.length; i++) ...[
          Expanded(child: children[i]),
          if (i < children.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }

  Widget _buildLabeledValue(
    BuildContext context, {
    required String label,
    required Widget child,
  }) {
    final colors = context.colors;

    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            label,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 9,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildToggleRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isActive,
    VoidCallback? onTap,
    bool compact = false,
  }) {
    final colors = context.colors;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 120),
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 4 : 6,
              vertical: compact ? 2 : 4,
            ),
            decoration: BoxDecoration(
              color: isActive ? colors.accent : colors.dark,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: compact ? 10 : 12,
                  color: isActive ? colors.elevated : colors.textPrimary,
                ),
                if (label.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isActive ? colors.elevated : colors.textPrimary,
                        fontSize: compact ? 8 : 9,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
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

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 120),
      child: GestureDetector(
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 12,
                  color: colors.textPrimary,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build the Chords button with green outlined style
  Widget _buildChordsButton(BuildContext context) {
    final isActive = chordsEnabled;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 120),
      child: GestureDetector(
        onTap: onChordsToggle,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? _chordsGreen : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: _chordsGreen,
                width: 1,
              ),
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
      ),
    );
  }

  Widget _buildKnobRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    Function(double)? onChanged,
    VoidCallback? onApply,
    String Function(double)? valueFormatter,
  }) {
    return Row(
      children: [
        // Action button first (icon + label, matching Legato/Reverse style)
        Expanded(
          child: _buildActionButton(
            context,
            icon: icon,
            label: label,
            onTap: onApply,
          ),
        ),
        const SizedBox(width: 8),
        // Knob second with value displayed inside
        MiniKnob(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
          size: 28,
          valueFormatter: valueFormatter,
        ),
      ],
    );
  }

  Widget _buildCompactDropdown<T>(
    BuildContext context, {
    required T value,
    required List<T> items,
    String Function(T)? itemLabel,
    Function(T)? onChanged,
  }) {
    final colors = context.colors;
    final label = itemLabel != null ? itemLabel(value) : value.toString();

    return GestureDetector(
      onTap: () => _showDropdownMenu<T>(
        context,
        items: items,
        currentValue: value,
        itemLabel: itemLabel,
        onSelected: onChanged,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 9,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 12,
                color: colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDropdownMenu<T>(
    BuildContext context, {
    required List<T> items,
    required T currentValue,
    String Function(T)? itemLabel,
    Function(T)? onSelected,
  }) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);

    showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(
        buttonPosition.dx,
        buttonPosition.dy,
        overlay.size.width - buttonPosition.dx - button.size.width,
        0,
      ),
      items: items.map((item) {
        final label = itemLabel != null ? itemLabel(item) : item.toString();
        return PopupMenuItem<T>(
          value: item,
          height: 32,
          child: Text(
            label,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 11,
              fontWeight: item == currentValue ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
      elevation: 8,
    ).then((value) {
      if (value != null && onSelected != null) {
        onSelected(value);
      }
    });
  }
}
