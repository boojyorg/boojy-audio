import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';
import '../shared/split_button.dart';
import '../shared/mini_knob.dart';
import 'loop_time_display.dart';

/// Callback definitions for toolbar actions
typedef OnSnapChanged = void Function(bool enabled, double? gridDivision);
typedef OnQuantize = void Function(int division);
typedef OnLoopChanged = void Function(bool enabled, double start, double length);

/// Piano Roll toolbar with two rows:
/// Row 1: Tab buttons and close
/// Row 2: All editing controls
class PianoRollToolbar extends StatelessWidget {
  // Clip info
  final String clipName;

  // Snap settings
  final bool snapEnabled;
  final double gridDivision;
  final VoidCallback? onSnapToggle;
  final Function(double)? onGridDivisionChanged;

  // Slice mode
  final bool sliceModeEnabled;
  final VoidCallback? onSliceToggle;

  // Quantize
  final Function(int)? onQuantize;

  // Audition
  final bool auditionEnabled;
  final VoidCallback? onAuditionToggle;

  // Velocity lane
  final bool velocityLaneExpanded;
  final VoidCallback? onVelocityLaneToggle;

  // CC automation lane
  final bool ccLaneExpanded;
  final VoidCallback? onCCLaneToggle;

  // Zoom
  final double pixelsPerBeat;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;

  // Loop settings
  final bool loopEnabled;
  final double loopStartBeats;
  final double loopLengthBeats;
  final VoidCallback? onLoopToggle;
  final Function(double)? onLoopStartChanged;
  final Function(double)? onLoopLengthChanged;

  // Transform tools
  final double stretchAmount;
  final double humanizeAmount;
  final Function(double)? onStretchChanged;
  final Function(double)? onHumanizeChanged;
  final VoidCallback? onStretchApply;
  final VoidCallback? onHumanizeApply;
  final VoidCallback? onLegato;
  final VoidCallback? onReverse;

  // Close
  final VoidCallback? onClose;

  const PianoRollToolbar({
    super.key,
    required this.clipName,
    this.snapEnabled = true,
    this.gridDivision = 0.25,
    this.onSnapToggle,
    this.onGridDivisionChanged,
    this.sliceModeEnabled = false,
    this.onSliceToggle,
    this.onQuantize,
    this.auditionEnabled = true,
    this.onAuditionToggle,
    this.velocityLaneExpanded = false,
    this.onVelocityLaneToggle,
    this.ccLaneExpanded = false,
    this.onCCLaneToggle,
    this.pixelsPerBeat = 80.0,
    this.onZoomIn,
    this.onZoomOut,
    this.loopEnabled = false,
    this.loopStartBeats = 0.0,
    this.loopLengthBeats = 16.0,
    this.onLoopToggle,
    this.onLoopStartChanged,
    this.onLoopLengthChanged,
    this.stretchAmount = 1.0,
    this.humanizeAmount = 0.0,
    this.onStretchChanged,
    this.onHumanizeChanged,
    this.onStretchApply,
    this.onHumanizeApply,
    this.onLegato,
    this.onReverse,
    this.onClose,
  });

  String _getGridDivisionLabel() {
    if (gridDivision == 1.0) return '1/4';
    if (gridDivision == 0.5) return '1/8';
    if (gridDivision == 0.25) return '1/16';
    if (gridDivision == 0.125) return '1/32';
    if (gridDivision == 0.0625) return '1/64';
    return '1/${(4 / gridDivision).round()}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.elevated,
        border: Border(
          bottom: BorderSide(color: colors.surface, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Title and close button (40px)
          _buildRow1(context),
          // Row 2: All controls (36px)
          _buildRow2(context),
        ],
      ),
    );
  }

  Widget _buildRow1(BuildContext context) {
    final colors = context.colors;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.piano_outlined,
            color: colors.textPrimary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Piano Roll - $clipName',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Close button
          IconButton(
            icon: const Icon(Icons.close),
            color: colors.textPrimary,
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: onClose,
            tooltip: 'Close Piano Roll',
          ),
        ],
      ),
    );
  }

  Widget _buildRow2(BuildContext context) {
    final colors = context.colors;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colors.standard,
        border: Border(
          top: BorderSide(color: colors.surface, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Snap split button
          _buildSnapButton(context),
          const SizedBox(width: 8),

          // Quantize split button
          _buildQuantizeButton(context),

          // Separator
          _buildSeparator(context),

          // Loop controls
          _buildLoopControls(context),

          // Separator
          _buildSeparator(context),

          // Transform tools
          _buildTransformTools(context),

          const Spacer(),

          // View controls (velocity, zoom)
          _buildViewControls(context),
        ],
      ),
    );
  }

  Widget _buildSnapButton(BuildContext context) {
    return SplitButton<double>(
      icon: Icons.grid_on,
      label: snapEnabled ? 'Snap ${_getGridDivisionLabel()}' : 'Snap OFF',
      isActive: snapEnabled,
      onLabelTap: onSnapToggle,
      dropdownItems: [
        PopupMenuItem<double>(
          value: 1.0,
          child: Text('1/4 Note (Quarter)',
            style: TextStyle(color: context.colors.textPrimary)),
        ),
        PopupMenuItem<double>(
          value: 0.5,
          child: Text('1/8 Note (Eighth)',
            style: TextStyle(color: context.colors.textPrimary)),
        ),
        PopupMenuItem<double>(
          value: 0.25,
          child: Text('1/16 Note (Sixteenth)',
            style: TextStyle(color: context.colors.textPrimary)),
        ),
        PopupMenuItem<double>(
          value: 0.125,
          child: Text('1/32 Note (Thirty-second)',
            style: TextStyle(color: context.colors.textPrimary)),
        ),
        PopupMenuItem<double>(
          value: 0.0625,
          child: Text('1/64 Note',
            style: TextStyle(color: context.colors.textPrimary)),
        ),
      ],
      onItemSelected: onGridDivisionChanged,
    );
  }

  Widget _buildQuantizeButton(BuildContext context) {
    return SplitButton<int>(
      icon: Icons.align_horizontal_left,
      label: 'Quantize',
      onLabelTap: () => onQuantize?.call(16), // Default to 1/16
      dropdownItems: [
        PopupMenuItem<int>(
          value: 4,
          child: Text('1/4 Note (Quarter)',
            style: TextStyle(color: context.colors.textPrimary)),
        ),
        PopupMenuItem<int>(
          value: 8,
          child: Text('1/8 Note (Eighth)',
            style: TextStyle(color: context.colors.textPrimary)),
        ),
        PopupMenuItem<int>(
          value: 16,
          child: Text('1/16 Note (Sixteenth)',
            style: TextStyle(color: context.colors.textPrimary)),
        ),
        PopupMenuItem<int>(
          value: 32,
          child: Text('1/32 Note (Thirty-second)',
            style: TextStyle(color: context.colors.textPrimary)),
        ),
      ],
      onItemSelected: onQuantize,
    );
  }

  Widget _buildSeparator(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        width: 1,
        height: 20,
        color: context.colors.textMuted.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _buildLoopControls(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Loop toggle
        ToolbarButton(
          icon: Icons.loop,
          label: '',
          isActive: loopEnabled,
          onTap: onLoopToggle,
          tooltip: loopEnabled ? 'Disable loop' : 'Enable loop',
        ),
        const SizedBox(width: 8),
        // Loop start (editable bar.beat.tick format)
        LoopTimeDisplay(
          beats: loopStartBeats,
          label: 'Start',
          onChanged: onLoopStartChanged,
        ),
        const SizedBox(width: 8),
        // Loop length (editable bar.beat.tick format)
        LoopTimeDisplay(
          beats: loopLengthBeats,
          label: 'Length',
          onChanged: onLoopLengthChanged,
        ),
      ],
    );
  }

  Widget _buildTransformTools(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Legato button
        ToolbarButton(
          icon: Icons.linear_scale,
          label: 'Legato',
          onTap: onLegato,
          tooltip: 'Extend notes to touch next note',
        ),
        const SizedBox(width: 4),

        // Slice toggle
        ToolbarButton(
          icon: Icons.content_cut,
          label: 'Slice',
          isActive: sliceModeEnabled,
          onTap: onSliceToggle,
          tooltip: sliceModeEnabled ? 'Exit slice mode' : 'Enter slice mode',
        ),
        const SizedBox(width: 8),

        // Stretch knob with apply
        KnobWithApply(
          value: stretchAmount,
          min: 0.5,
          max: 2.0,
          label: 'Str',
          onChanged: onStretchChanged,
          onApply: onStretchApply,
          valueFormatter: (v) => '${v.toStringAsFixed(1)}x',
        ),
        const SizedBox(width: 8),

        // Humanize knob with apply
        KnobWithApply(
          value: humanizeAmount,
          min: 0.0,
          max: 1.0,
          label: 'Hum',
          onChanged: onHumanizeChanged,
          onApply: onHumanizeApply,
          valueFormatter: (v) => '${(v * 100).round()}%',
        ),
        const SizedBox(width: 8),

        // Reverse button
        ToolbarButton(
          icon: Icons.swap_horiz,
          label: 'Rev',
          onTap: onReverse,
          tooltip: 'Reverse selected notes in time',
        ),
      ],
    );
  }

  Widget _buildViewControls(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Audition toggle
        ToolbarButton(
          icon: auditionEnabled ? Icons.volume_up : Icons.volume_off,
          label: '',
          isActive: auditionEnabled,
          onTap: onAuditionToggle,
          tooltip: auditionEnabled ? 'Disable audition' : 'Enable audition',
        ),
        const SizedBox(width: 4),

        // Velocity lane toggle
        ToolbarButton(
          icon: Icons.equalizer,
          label: '',
          isActive: velocityLaneExpanded,
          onTap: onVelocityLaneToggle,
          tooltip: velocityLaneExpanded ? 'Hide velocity lane' : 'Show velocity lane',
        ),
        const SizedBox(width: 4),

        // CC automation lane toggle
        ToolbarButton(
          icon: Icons.show_chart,
          label: '',
          isActive: ccLaneExpanded,
          onTap: onCCLaneToggle,
          tooltip: ccLaneExpanded ? 'Hide CC lane' : 'Show CC lane',
        ),
        const SizedBox(width: 8),

        // Zoom controls
        ToolbarButton(
          icon: Icons.remove,
          label: '',
          onTap: onZoomOut,
          tooltip: 'Zoom out',
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '${pixelsPerBeat.toInt()}px',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 10,
            ),
          ),
        ),
        const SizedBox(width: 4),
        ToolbarButton(
          icon: Icons.add,
          label: '',
          onTap: onZoomIn,
          tooltip: 'Zoom in',
        ),
      ],
    );
  }
}
