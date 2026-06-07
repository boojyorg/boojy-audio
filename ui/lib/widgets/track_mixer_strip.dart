// ignore_for_file: avoid_positional_boolean_parameters

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../audio_engine.dart';
import '../constants/ui_constants.dart';
import '../models/instrument_data.dart';
import '../models/track_automation_data.dart';
import '../models/library_item.dart';
import '../models/vst3_plugin_data.dart';
import '../services/tool_mode_resolver.dart';
import '../theme/app_colors.dart';
import '../theme/boojy_icons.dart';
import '../theme/theme_extension.dart';
import '../theme/theme_provider.dart';
import '../theme/tokens.dart';
import '../utils/track_colors.dart';
import 'instrument_browser.dart';
import 'pan_knob.dart';
import 'capsule_fader.dart';
import 'volume_readout_box.dart';
import 'input_selector_dropdown.dart';
import '../models/track_send_data.dart';
import '../utils/logger.dart';

/// Unified track strip combining track info and mixer controls
/// Displayed on the right side of timeline, aligned with each track row
class TrackMixerStrip extends StatefulWidget {
  // Height constraints
  static const double kMinHeight = UIConstants.trackMinHeight;
  static const double kMaxHeight = UIConstants.trackMaxHeight;
  final int trackId;
  final int
  displayIndex; // Sequential display number (1, 2, 3...) - NOT internal track ID
  final String trackName;
  final String trackType;
  final double volumeDb;
  final double pan;
  final bool isMuted;
  final bool isSoloed;
  final double peakLevelLeft; // 0.0 to 1.0
  final double peakLevelRight; // 0.0 to 1.0
  final Color? trackColor; // Optional track color for left border
  final AudioEngine? audioEngine;

  // Callbacks
  final Function(double)? onVolumeChanged;
  final Function(double)? onPanChanged;
  final VoidCallback? onVolumeDragStart;
  final VoidCallback? onVolumeDragEnd;
  final VoidCallback? onPanDragStart;
  final VoidCallback? onPanDragEnd;
  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;
  final VoidCallback? onArmToggle; // Toggle recording arm (exclusive)
  final VoidCallback? onArmShiftClick; // Shift+click for multi-arm mode
  final VoidCallback? onMonitorToggle; // Toggle input monitoring (audio tracks)
  final bool showAutomation; // Whether automation lane is visible
  final AutomationParameter selectedParameter; // Lane parameter (dropdown)
  final Function(AutomationParameter)? onParameterChanged;
  final VoidCallback? onResetAutomation; // Clear all points on the lane

  final double? previewParameterValue; // Live preview value during drag

  final Function(bool isShiftHeld)?
  onTap; // Unified track selection callback (with shift state for multi-select)
  final VoidCallback? onDoubleTap; // Double-click to open editor
  final VoidCallback? onDeletePressed;
  final VoidCallback? onDuplicatePressed;
  final VoidCallback? onConvertToSampler; // Convert Audio track to Sampler
  final Function(String)? onNameChanged; // Inline rename callback
  final bool isSelected; // Track selection state
  final bool isArmed; // Recording arm state
  final bool inputMonitoring; // Hear live input while armed (audio tracks)

  // MIDI instrument selection
  final InstrumentData? instrumentData;
  final Function(String)? onInstrumentSelect; // Callback with instrument ID

  // M10: VST3 Plugin support
  final int vst3PluginCount;
  final VoidCallback? onFxButtonPressed;
  final Function(Vst3Plugin)? onVst3PluginDropped;
  final Function(Vst3Plugin)? onVst3InstrumentDropped; // VST3 instrument swap
  final Function(Instrument)? onInstrumentDropped; // Built-in instrument swap
  final Function(EffectItem)? onBuiltInEffectDropped; // Built-in effect drop
  final VoidCallback? onEditPluginsPressed; // New: Edit active plugins

  // Send/return routing (v0.3)
  final bool isReturnTrack;
  final List<TrackSendData> sends;
  final List<ReturnTrackData> existingReturns;
  final Function(int returnTrackId, double amountDb)? onSendAmountChanged;
  final Function(int returnTrackId)? onSendAmountDragStart;
  final Function(int returnTrackId)? onSendAmountDragEnd;
  final Function(int returnTrackId)? onRemoveSend;
  final Function(ReturnTrackData returnTrack)? onSendToReturn;
  final VoidCallback? onDeleteReturn;

  // Track height management (synced with timeline)
  final double clipHeight; // Clip area height
  final double automationHeight; // Automation lane height (when visible)
  final Function(double)? onClipHeightChanged;
  final Function(double)? onAutomationHeightChanged;

  // Strip width (for responsive layout)
  final double stripWidth;

  // Track color change callback
  final Function(Color)? onColorChanged;

  // Input routing
  final int inputDeviceIndex; // -1 = no input, 0+ = device index
  final int inputChannel; // 0-based channel within device
  final List<Map<String, dynamic>> inputDevices; // Available input devices
  final Function(int deviceIndex, int channel)? onInputChanged;
  final bool isRecording; // Lock input selector during recording
  final double?
  inputLevel; // 0.0 to 1.0, input level overlay on fader when armed

  // Custom icon (emoji override from user)
  final String? customIcon;
  final Function(String)? onIconChanged;

  const TrackMixerStrip({
    super.key,
    required this.trackId,
    required this.displayIndex,
    required this.trackName,
    required this.trackType,
    required this.volumeDb,
    required this.pan,
    required this.isMuted,
    required this.isSoloed,
    this.peakLevelLeft = 0.0,
    this.peakLevelRight = 0.0,
    this.trackColor,
    this.audioEngine,
    this.onVolumeChanged,
    this.onPanChanged,
    this.onVolumeDragStart,
    this.onVolumeDragEnd,
    this.onPanDragStart,
    this.onPanDragEnd,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onArmToggle,
    this.onArmShiftClick,
    this.onMonitorToggle,
    this.showAutomation = false,
    this.selectedParameter = AutomationParameter.volume,
    this.onParameterChanged,
    this.onResetAutomation,
    this.previewParameterValue,
    this.onTap,
    this.onDoubleTap,
    this.onDeletePressed,
    this.onDuplicatePressed,
    this.onConvertToSampler,
    this.onNameChanged,
    this.isSelected = false,
    this.isArmed = false,
    this.inputMonitoring = true,
    this.instrumentData,
    this.onInstrumentSelect,
    this.vst3PluginCount = 0,
    this.onFxButtonPressed,
    this.onVst3PluginDropped,
    this.onVst3InstrumentDropped,
    this.onInstrumentDropped,
    this.onBuiltInEffectDropped,
    this.onEditPluginsPressed,
    this.isReturnTrack = false,
    this.sends = const [],
    this.existingReturns = const [],
    this.onSendAmountChanged,
    this.onSendAmountDragStart,
    this.onSendAmountDragEnd,
    this.onRemoveSend,
    this.onSendToReturn,
    this.onDeleteReturn,
    this.clipHeight = 100.0,
    this.automationHeight = 60.0,
    this.onClipHeightChanged,
    this.onAutomationHeightChanged,
    this.stripWidth = 380.0,
    this.onColorChanged,
    this.inputDeviceIndex = -1,
    this.inputChannel = 0,
    this.inputDevices = const [],
    this.onInputChanged,
    this.isRecording = false,
    this.inputLevel,
    this.customIcon,
    this.onIconChanged,
  });

  @override
  State<TrackMixerStrip> createState() => _TrackMixerStripState();
}

class _TrackMixerStripState extends State<TrackMixerStrip> {
  bool _isEditing = false;
  bool _fxHovered = false;
  late TextEditingController _nameController;
  late FocusNode _focusNode;

  // Resize state
  bool _isResizing = false;
  double _resizeStartY = 0.0;
  double _resizeStartHeight = 0.0;

  /// Stored height before collapse, for restoring on double-click expand
  double? _preCollapseHeight;

  void _toggleCollapse() {
    if (widget.clipHeight <= UIConstants.trackMinHeight + 1) {
      // Currently collapsed — restore previous height
      final restoreTo = _preCollapseHeight ?? UIConstants.trackStandardHeight;
      _preCollapseHeight = null;
      widget.onClipHeightChanged?.call(restoreTo);
    } else {
      // Collapse to minimum
      _preCollapseHeight = widget.clipHeight;
      widget.onClipHeightChanged?.call(UIConstants.trackMinHeight);
    }
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.trackName);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(TrackMixerStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackName != widget.trackName && !_isEditing) {
      _nameController.text = widget.trackName;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _isEditing) {
      _submitName();
    }
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _nameController.text = widget.trackName;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _nameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _nameController.text.length,
      );
    });
  }

  void _submitName() {
    final newName = _nameController.text.trim();
    setState(() {
      _isEditing = false;
    });
    if (newName.isNotEmpty && newName != widget.trackName) {
      widget.onNameChanged?.call(newName);
    }
  }

  /// Clip area height excluding send rows (send padding lives in clipHeight).
  double get _baseClipHeight {
    final sendPadding = widget.sends.length * UIConstants.sendRowHeight;
    return (widget.clipHeight - sendPadding).clamp(
      UIConstants.trackMinHeight,
      UIConstants.trackMaxHeight,
    );
  }

  /// Calculate scale factor based on track height (0.0 at 50px, 1.0 at 76px+)
  /// Only used by the 2-row layout (heights >= 50px).
  double get _scaleFactor {
    const minHeight = UIConstants.trackOneRowThreshold;
    const standardHeight = UIConstants.trackStandardHeight;
    return ((_baseClipHeight - minHeight) / (standardHeight - minHeight)).clamp(
      0.0,
      1.0,
    );
  }

  /// Lerp helper for scaling values
  double _lerp(double min, double max, double t) => min + (max - min) * t;

  /// Build 2-row layout that scales with track height
  /// Row 1: Icon + Number + Name + MSR + Pan
  /// Row 2: dB + Volume Slider
  ///
  /// Fixed sizes (consistent across all heights):
  /// - Icon, Number, Name text: always 14px icon, 12px font
  /// - dB display: always 10px font
  /// - dB container width: fixed so volume slider aligns
  ///
  /// Scaled with height:
  /// - Row heights, padding, spacing
  /// - MSR button size, Pan knob size
  /// - Volume slider height (thinner when compact)
  Widget _buildStandardLayout(BuildContext context, bool isHovered) {
    // Route to 1-row layout when height is below threshold
    if (_baseClipHeight < UIConstants.trackOneRowThreshold) {
      return _buildOneRowLayout(context);
    }

    final baseHeight = _baseClipHeight;

    final scale = _scaleFactor;

    // Available height for content
    // Border: 4px left, 2px top/right/bottom - vertical offset is top + bottom = 4px
    const double borderOffset = 4.0;
    final availableHeight = baseHeight - borderOffset;

    // Calculate layout dimensions
    // Top padding: 0 at compact for row 1 at very top, 6 at standard
    final topPadding = _lerp(-1, 6, scale).clamp(0.0, 6.0);
    // Bottom padding: 2 at compact, 6 at standard
    final bottomPadding = _lerp(2, 6, scale);
    // Fixed horizontal padding so dB x-position is consistent
    const double horizontalPadding = 6.0;
    // Row 2 height - slightly smaller at compact to prevent overflow
    final rowHeight = ((availableHeight - topPadding - bottomPadding) / 2)
        .clamp(11.0, 28.0);

    // MSR buttons and Pan scale with height
    final buttonSize = _lerp(14, 22, scale);
    final panSize = _lerp(14, 22, scale);
    final buttonSpacing = _lerp(2, 4, scale);
    final buttonFontSize = _lerp(8, 10, scale);

    // Fixed sizes - consistent across all heights
    const double fontSize = 12.0;
    const double iconSize = 14.0;
    const double dbFontSize = UIConstants.dbFontSize;
    const double dbContainerWidth =
        UIConstants.dbContainerWidth; // Fixed width so slider aligns

    return Padding(
      padding: EdgeInsets.only(
        left: horizontalPadding,
        right: horizontalPadding,
        top: topPadding,
        bottom: bottomPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Row 1: Icon + Number + Name + [Input] + MSR + Pan
          // No fixed height - let it size to content and sit at top
          Row(
            children: [
              // Icon + Number + Name (fixed font sizes, expands to fill space)
              Expanded(
                child: _buildTrackInfoRow(
                  fontSize: fontSize,
                  iconSize: iconSize,
                ),
              ),
              const SizedBox(width: 4),
              // Input selector (Audio/Sampler tracks only)
              if (_showInputSelector)
                _buildInputSelector(
                  buttonSize: buttonSize,
                  fontSize: buttonFontSize,
                ),
              if (_showInputSelector) const SizedBox(width: 4),
              // M, S, R buttons (scale with height)
              _buildControlButtons(
                buttonSize: buttonSize,
                spacing: buttonSpacing,
                fontSize: buttonFontSize,
              ),
              if (widget.onFxButtonPressed != null) ...[
                const SizedBox(width: 4),
                _buildFxButton(buttonSize: buttonSize),
              ],
              const SizedBox(width: 6),
              // Pan knob (scales with height)
              PanKnob(
                pan: widget.pan,
                onChanged: widget.onPanChanged,
                onDragStart: widget.onPanDragStart,
                onDragEnd: widget.onPanDragEnd,
                size: panSize,
              ),
            ],
          ),
          // Row 2: dB + Volume Slider
          SizedBox(
            height: rowHeight,
            child: Row(
              children: [
                // dB value display — drag vertically to scrub, click to type.
                VolumeReadoutBox(
                  volumeDb: widget.volumeDb,
                  onVolumeChanged: widget.onVolumeChanged,
                  onVolumeDragStart: widget.onVolumeDragStart,
                  onVolumeDragEnd: widget.onVolumeDragEnd,
                  width: dbContainerWidth,
                  fontSize: dbFontSize,
                  textColor: context.colors.textSecondary,
                ),
                const SizedBox(width: 8),
                // Volume Slider (height scales, X position fixed)
                Expanded(
                  child: CapsuleFader(
                    leftLevel: widget.peakLevelLeft,
                    rightLevel: widget.peakLevelRight,
                    volumeDb: widget.volumeDb,
                    onVolumeChanged: widget.onVolumeChanged,
                    onDragStart: widget.onVolumeDragStart,
                    onDragEnd: widget.onVolumeDragEnd,
                    onDoubleTap: () => widget.onVolumeChanged?.call(0.0),
                    inputLevel: widget.isArmed ? widget.inputLevel : null,
                  ),
                ),
              ],
            ),
          ),
          // Send rows (when sends exist)
          if (widget.sends.isNotEmpty) _buildSendRows(context),
        ],
      ),
    );
  }

  /// Automation controls in the lane-aligned space below the normal strip
  /// rows: [Volume ▾] parameter dropdown + value readout + clear-lane reset.
  Widget _buildAutomationSection(BuildContext context) {
    final colors = context.colors;
    const double rowHeight = 20.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.divider, width: 0.5)),
      ),
      child: ClipRect(
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildParameterDropdown(context, rowHeight),
                const SizedBox(width: 4),
                _buildParameterValueDisplay(context, rowHeight),
                const SizedBox(width: 4),
                _buildResetButton(context, rowHeight),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Parameter dropdown ([Volume ▾]; gains entries as the engine grows)
  Widget _buildParameterDropdown(BuildContext context, double rowHeight) {
    final colors = context.colors;

    return Container(
      height: rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colors.dark,
        borderRadius: BorderRadius.circular(2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AutomationParameter>(
          value: widget.selectedParameter,
          isDense: true,
          dropdownColor: colors.elevated,
          icon: Icon(BI.caretDown, size: 14, color: colors.textSecondary),
          style: TextStyle(color: colors.textPrimary, fontSize: 10),
          // Only engine-backed parameters — pan automation is UI-only today.
          items: AutomationParameter.engineBacked.map((p) {
            return DropdownMenuItem<AutomationParameter>(
              value: p,
              child: Text(p.displayName),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              widget.onParameterChanged?.call(value);
            }
          },
        ),
      ),
    );
  }

  /// Automation value readout — live point value during a drag, otherwise
  /// the track's current volume.
  Widget _buildParameterValueDisplay(BuildContext context, double rowHeight) {
    final colors = context.colors;
    final hasPreview = widget.previewParameterValue != null;

    final String valueText;
    if (hasPreview) {
      // Preview value is normalized (0-1), convert to dB
      valueText = VolumeConversion.normalizedToDisplayString(
        widget.previewParameterValue!,
      );
    } else {
      valueText = widget.volumeDb <= -60.0
          ? '-∞ dB'
          : '${widget.volumeDb.toStringAsFixed(1)} dB';
    }

    return Container(
      width: UIConstants.dbContainerWidth,
      height: rowHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.darkest,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        valueText,
        maxLines: 1,
        style: TextStyle(
          color: hasPreview ? colors.textPrimary : colors.textSecondary,
          fontSize: UIConstants.dbFontSize,
        ),
      ),
    );
  }

  /// Reset button — clears every point on the lane (undoable)
  Widget _buildResetButton(BuildContext context, double rowHeight) {
    final colors = context.colors;

    return Tooltip(
      message: 'Clear automation points',
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        onTap: widget.onResetAutomation,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: rowHeight,
            height: rowHeight,
            decoration: BoxDecoration(
              color: colors.dark,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Icon(
              BI.refresh,
              size: rowHeight * 0.6,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFxButton({double buttonSize = 22}) {
    return MouseRegion(
      onEnter: (_) => setState(() => _fxHovered = true),
      onExit: (_) => setState(() => _fxHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onFxButtonPressed,
        child: SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                BI.lightning,
                size: buttonSize * 0.8,
                color: _fxHovered
                    ? context.colors.accent
                    : context.colors.textSecondary,
              ),
              if (_fxHovered)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Text(
                    '+',
                    style: TextStyle(
                      color: context.colors.accent,
                      fontSize: buttonSize * 0.45,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSendRows(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: widget.sends.map((send) {
        return SizedBox(
          height: UIConstants.sendRowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    send.label,
                    style: TextStyle(color: colors.textSecondary, fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                _SendAmountKnob(
                  amountLinear: send.amountLinear,
                  size: 16,
                  onChanged: (linear) {
                    final db = TrackSendData.linearToDb(linear);
                    widget.onSendAmountChanged?.call(send.returnId, db);
                  },
                  onDragStart: () =>
                      widget.onSendAmountDragStart?.call(send.returnId),
                  onDragEnd: () =>
                      widget.onSendAmountDragEnd?.call(send.returnId),
                ),
                const SizedBox(width: 4),
                Text(
                  send.amountPercentLabel,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 9,
                    fontFamily: BT.fontFamilyMono,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => widget.onRemoveSend?.call(send.returnId),
                  child: Icon(BI.close, size: 12, color: colors.textMuted),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 1-row layout for heights below 50px.
  /// Width-responsive: controls drop off progressively to protect fader width.
  /// Drop order: dB → pan → R → M/S → (name + fader always visible)
  Widget _buildOneRowLayout(BuildContext context) {
    final colors = context.colors;
    final width = widget.stripWidth;

    // Width breakpoints — controls drop to give fader more space
    final showDb = width >= 350;
    final showPan = width >= 280;
    final showRecord = width >= 220;
    final showMsr = width >= 160;

    // Collapsed mode (< 24px): thin fader, no thumb, minimal text
    final isCollapsed = widget.clipHeight < 24;
    final fontSize = isCollapsed ? BT.fontCaption : BT.fontLabel;
    final buttonSize = isCollapsed ? 12.0 : 16.0;

    // Volume display
    final displayVolumeDb = widget.volumeDb;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isCollapsed ? BT.xs : 6.0,
        vertical: isCollapsed ? 1.0 : BT.xxs,
      ),
      child: Row(
        children: [
          // Track number + name (always visible)
          Text(
            '${widget.displayIndex}',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: fontSize,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: BT.xs),
          Expanded(
            flex: 2,
            child: Text(
              widget.trackName,
              style: TextStyle(color: colors.textSecondary, fontSize: fontSize),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: BT.xs),

          // M/S/R buttons (drop R first, then M/S)
          if (showMsr) ...[
            _buildMiniMsrButtons(
              colors: colors,
              size: buttonSize,
              showRecord: showRecord,
              isCollapsed: isCollapsed,
            ),
            const SizedBox(width: BT.xs),
          ],

          // Pan knob
          if (showPan) ...[
            PanKnob(
              pan: widget.pan,
              onChanged: widget.onPanChanged,
              onDragStart: widget.onPanDragStart,
              onDragEnd: widget.onPanDragEnd,
              size: buttonSize,
            ),
            const SizedBox(width: BT.xs),
          ],

          // Volume fader (always visible, gets wider as controls drop)
          Expanded(
            flex: 3,
            child: CapsuleFader(
              leftLevel: widget.peakLevelLeft,
              rightLevel: widget.peakLevelRight,
              volumeDb: displayVolumeDb,
              onVolumeChanged: widget.onVolumeChanged,
              onDragStart: widget.onVolumeDragStart,
              onDragEnd: widget.onVolumeDragEnd,
              onDoubleTap: () => widget.onVolumeChanged?.call(0.0),
              inputLevel: widget.isArmed ? widget.inputLevel : null,
            ),
          ),

          // dB text (drops before pan) — drag vertically to scrub, click to type.
          if (showDb) ...[
            const SizedBox(width: BT.xs),
            VolumeReadoutBox(
              volumeDb: displayVolumeDb,
              onVolumeChanged: widget.onVolumeChanged,
              onVolumeDragStart: widget.onVolumeDragStart,
              onVolumeDragEnd: widget.onVolumeDragEnd,
              width: 44,
              fontSize: BT.fontCaption,
              textColor: colors.textMuted,
              textAlign: TextAlign.right,
              showSuffix: false,
              boxed: false,
            ),
          ],
        ],
      ),
    );
  }

  /// Compact M/S/R buttons for 1-row layout.
  Widget _buildMiniMsrButtons({
    required BoojyColors colors,
    required double size,
    required bool showRecord,
    required bool isCollapsed,
  }) {
    if (isCollapsed) {
      // Dots only — 6px colored circles
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.isMuted
                  ? colors.muteActive
                  : colors.textMuted.withValues(alpha: BT.opacityMedium),
            ),
          ),
          const SizedBox(width: 2),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.isSoloed
                  ? colors.soloActive
                  : colors.textMuted.withValues(alpha: BT.opacityMedium),
            ),
          ),
        ],
      );
    }

    // Small text buttons
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _miniButton(
          'M',
          widget.isMuted,
          colors.muteActive,
          widget.onMuteToggle,
          size,
        ),
        const SizedBox(width: 2),
        _miniButton(
          'S',
          widget.isSoloed,
          colors.soloActive,
          widget.onSoloToggle,
          size,
        ),
        if (showRecord) ...[
          const SizedBox(width: 2),
          _miniButton(
            'R',
            widget.isArmed,
            colors.recordActive,
            widget.onArmToggle,
            size,
          ),
        ],
      ],
    );
  }

  Widget _miniButton(
    String label,
    bool active,
    Color activeColor,
    VoidCallback? onTap,
    double size,
  ) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? activeColor : colors.dark,
          borderRadius: BT.borderSm,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? colors.darkest : colors.textMuted,
            fontSize: size * 0.55,
            fontWeight: BT.weightSemiBold,
          ),
        ),
      ),
    );
  }

  /// Build track info row (Icon + Number + Name)
  /// All elements use fixed sizes for consistent alignment across all track heights
  Widget _buildTrackInfoRow({double fontSize = 12, double iconSize = 14}) {
    final textColor = _getTextColor();
    final trackColor = widget.trackColor ?? context.colors.textPrimary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Icon (fixed size, clickable to change)
        GestureDetector(
          onTap: widget.onIconChanged != null
              ? () => _showIconPopup(context)
              : null,
          child: MouseRegion(
            cursor: widget.onIconChanged != null
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: Text(_getTrackEmoji(), style: TextStyle(fontSize: iconSize)),
          ),
        ),
        const SizedBox(width: 6),
        // Number (sequential display index, not internal ID) - fixed size
        if (!widget.isReturnTrack)
          Text(
            '${widget.displayIndex}',
            style: TextStyle(
              color: textColor,
              fontSize: fontSize,
              fontWeight: BT.weightSemiBold,
            ),
          ),
        if (!widget.isReturnTrack) const SizedBox(width: 8),
        // Name (editable) - expanded to fill remaining space
        Expanded(
          child: _isEditing
              ? TextField(
                  controller: _nameController,
                  focusNode: _focusNode,
                  style: TextStyle(
                    color: textColor,
                    fontSize: fontSize,
                    fontWeight: BT.weightMedium,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    border: const OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: trackColor),
                    ),
                  ),
                  onSubmitted: (_) => _submitName(),
                )
              : GestureDetector(
                  onDoubleTap: _startEditing,
                  child: Text(
                    _getStandardDisplayName(),
                    style: TextStyle(
                      color: textColor,
                      fontSize: fontSize,
                      fontWeight: BT.weightMedium,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
        ),
        if (widget.isReturnTrack) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: context.colors.dark,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              'RETURN',
              style: TextStyle(
                color: context.colors.textMuted,
                fontSize: 8,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Get display name for standard layout
  String _getStandardDisplayName() {
    // Show track name (which may be auto-populated from instrument)
    return widget.trackName;
  }

  /// Whether to show the input selector (Audio tracks only, not returns)
  bool get _showInputSelector {
    if (widget.isReturnTrack) return false;
    final type = widget.trackType.toLowerCase();
    return type == 'audio';
  }

  /// Get short label for current input assignment
  String _getInputLabel() {
    if (widget.inputDeviceIndex < 0) return 'No In';

    // If we have device info, use device name + channel
    if (widget.inputDevices.isNotEmpty &&
        widget.inputDeviceIndex < widget.inputDevices.length) {
      final device = widget.inputDevices[widget.inputDeviceIndex];
      final deviceName = device['name'] as String? ?? 'Input';
      // Shorten common names
      String shortName = deviceName
          .replaceAll('Built-in Microphone', 'Mic')
          .replaceAll('Built-in', 'Built')
          .replaceAll('Microphone', 'Mic');
      // Truncate long names
      if (shortName.length > 8) {
        shortName = '${shortName.substring(0, 7)}…';
      }
      return 'In ${widget.inputChannel + 1}';
    }

    return 'In ${widget.inputChannel + 1}';
  }

  /// Build input selector dropdown button
  Widget _buildInputSelector({double buttonSize = 22, double fontSize = 10}) {
    final colors = context.colors;
    final isLocked = widget.isRecording;
    final hasInput = widget.inputDeviceIndex >= 0;
    final label = _getInputLabel();
    final height = buttonSize;

    return GestureDetector(
      onTap: isLocked ? null : () => _showInputDropdown(context),
      child: MouseRegion(
        cursor: isLocked
            ? SystemMouseCursors.forbidden
            : SystemMouseCursors.click,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isLocked
                ? colors.surface.withValues(alpha: 0.5)
                : hasInput
                ? colors.dark
                : colors.surface,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: isLocked
                  ? colors.hover.withValues(alpha: 0.3)
                  : colors.hover,
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isLocked
                      ? colors.textMuted
                      : hasInput
                      ? colors.textPrimary
                      : colors.textSecondary,
                  fontSize: fontSize,
                  fontWeight: BT.weightMedium,
                ),
              ),
              if (!isLocked) ...[
                const SizedBox(width: 1),
                Icon(
                  BI.caretDown,
                  size: fontSize + 4,
                  color: colors.textSecondary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Show input device/channel dropdown with live level meters
  void _showInputDropdown(BuildContext context) {
    final RenderBox button = this.context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(Offset.zero);

    showInputSelectorDropdown(
      context: context,
      position: Offset(position.dx, position.dy + button.size.height),
      inputDevices: widget.inputDevices,
      currentDeviceIndex: widget.inputDeviceIndex,
      currentChannel: widget.inputChannel,
      audioEngine: widget.audioEngine,
      onSelected: (deviceIndex, channel) {
        widget.onInputChanged?.call(deviceIndex, channel);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Note: trackType from engine is 'MIDI', 'Audio', 'Master' (uppercase)
    final isMidiTrack = widget.trackType.toLowerCase() == 'midi';

    // Calculate total height: clipHeight + automationHeight when automation is visible
    final totalHeight = widget.showAutomation
        ? widget.clipHeight + widget.automationHeight
        : widget.clipHeight;

    // Unified DragTarget: accepts effects (built-in + VST3), instruments (built-in + VST3)
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        if (data is EffectItem) return true; // Built-in effects on any track
        if (data is Vst3Plugin) {
          return !data.isInstrument || isMidiTrack;
        }
        if (data is Instrument) return isMidiTrack;
        return false;
      },
      onAcceptWithDetails: (details) {
        final data = details.data;
        if (data is EffectItem) {
          widget.onBuiltInEffectDropped?.call(data);
        } else if (data is Vst3Plugin && data.isInstrument) {
          widget.onVst3InstrumentDropped?.call(data);
        } else if (data is Vst3Plugin) {
          widget.onVst3PluginDropped?.call(data);
        } else if (data is Instrument) {
          widget.onInstrumentDropped?.call(data);
        }
      },
      builder: (context, candidates, rejected) {
        final isHovered = candidates.isNotEmpty;

        return GestureDetector(
          onTap: () {
            final isShiftHeld = ModifierKeyState.current().isShiftPressed;
            widget.onTap?.call(isShiftHeld);
          },
          onDoubleTap: widget.onDoubleTap,
          onSecondaryTapDown: (TapDownDetails details) {
            _showContextMenu(context, details.globalPosition);
          },
          child: SizedBox(
            width: widget.stripWidth,
            height: totalHeight,
            child: Stack(
              children: [
                // Main content container
                Container(
                  width: widget.stripWidth,
                  height: totalHeight,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    // Track color at 20% opacity (like Master track left section)
                    color: isHovered
                        ? context.colors.accent.withValues(alpha: 0.3)
                        : _getTintedBackgroundColor(),
                    // Asymmetric border: 4px left, 2px top/right/bottom (like Master track)
                    // When selected, border changes to white
                    border: isHovered
                        ? Border.all(color: context.colors.accent, width: 2)
                        : Border(
                            left: BorderSide(
                              color: widget.isSelected
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : (widget.trackColor ??
                                        context.colors.textSecondary),
                              width: 4,
                            ),
                            top: BorderSide(
                              color: widget.isSelected
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : (widget.trackColor ??
                                        context.colors.textSecondary),
                              width: 2,
                            ),
                            right: BorderSide(
                              color: widget.isSelected
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : (widget.trackColor ??
                                        context.colors.textSecondary),
                              width: 2,
                            ),
                            bottom: BorderSide(
                              color: widget.isSelected
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : (widget.trackColor ??
                                        context.colors.textSecondary),
                              width: 2,
                            ),
                          ),
                  ),
                  // When the automation lane is visible, the strip grows by
                  // automationHeight — but the normal controls stay pinned in
                  // the clipHeight area so the fader doesn't move. The extra
                  // space hosts the lane-aligned automation controls.
                  child: widget.showAutomation
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: widget.clipHeight,
                              child: _buildStandardLayout(context, isHovered),
                            ),
                            Expanded(child: _buildAutomationSection(context)),
                          ],
                        )
                      : _buildStandardLayout(context, isHovered),
                ),
                // Resize handle: bottom edge on regular tracks, top edge on
                // return tracks (returns are pinned at the bottom of the mixer,
                // so dragging the top edge grows the strip upward, like Master).
                Positioned(
                  left: 0,
                  right: 0,
                  top: widget.isReturnTrack ? 0 : null,
                  bottom: widget.isReturnTrack ? null : 0,
                  height: UIConstants.trackResizeHandleHeight,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeRow,
                    child: GestureDetector(
                      onDoubleTap: _toggleCollapse,
                      onVerticalDragStart: (details) {
                        _isResizing = true;
                        _resizeStartY = details.globalPosition.dy;
                        _resizeStartHeight = widget.clipHeight;
                      },
                      onVerticalDragUpdate: (details) {
                        if (_isResizing) {
                          // Inverse sign for returns: dragging UP increases height
                          // (the strip's bottom edge is anchored).
                          final delta = widget.isReturnTrack
                              ? _resizeStartY - details.globalPosition.dy
                              : details.globalPosition.dy - _resizeStartY;
                          final newHeight = (_resizeStartHeight + delta).clamp(
                            TrackMixerStrip.kMinHeight,
                            TrackMixerStrip.kMaxHeight,
                          );
                          widget.onClipHeightChanged?.call(newHeight);
                        }
                      },
                      onVerticalDragEnd: (details) {
                        _isResizing = false;
                      },
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    // Don't show context menu for master track
    if (widget.trackType.toLowerCase() == 'master') {
      Log.d('TrackMixerStrip: Skipping context menu for master track');
      return;
    }

    final isReturn = widget.isReturnTrack;

    Log.d(
      'TrackMixerStrip: Showing context menu at position $position for track ${widget.trackName}',
    );

    // Use listen: false to avoid provider error in callback context
    final colors = Provider.of<ThemeProvider>(context, listen: false).colors;
    final trackColor = widget.trackColor;
    final isAudioTrack = widget.trackType.toLowerCase() == 'audio';

    final menuItems = <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: 'rename',
        child: Row(
          children: [
            Icon(BI.pencil, size: 16, color: colors.textPrimary),
            const SizedBox(width: 8),
            Text('Rename', style: TextStyle(color: colors.textPrimary)),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'color',
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: trackColor ?? colors.textSecondary,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: colors.hover),
              ),
            ),
            const SizedBox(width: 8),
            Text('Change Color', style: TextStyle(color: colors.textPrimary)),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'duplicate',
        enabled: !isReturn,
        child: Row(
          children: [
            Icon(BI.copy, size: 16, color: colors.textPrimary),
            const SizedBox(width: 8),
            Text('Duplicate', style: TextStyle(color: colors.textPrimary)),
          ],
        ),
      ),
      // Show "Convert to Sampler" only for Audio tracks
      if (!isReturn && isAudioTrack && widget.onConvertToSampler != null)
        PopupMenuItem<String>(
          value: 'convert_to_sampler',
          child: Row(
            children: [
              Icon(BI.musicNote, size: 16, color: colors.textPrimary),
              const SizedBox(width: 8),
              Text(
                'Convert to Sampler',
                style: TextStyle(color: colors.textPrimary),
              ),
            ],
          ),
        ),
      if (!isReturn && widget.existingReturns.isNotEmpty) ...[
        const PopupMenuDivider(),
        ...widget.existingReturns.map((ret) {
          final alreadySent = widget.sends.any((s) => s.returnId == ret.id);
          return PopupMenuItem<String>(
            value: 'send_${ret.id}',
            enabled: !alreadySent,
            child: Text(
              'Send to ${ret.name}',
              style: TextStyle(color: colors.textPrimary),
            ),
          );
        }),
      ],
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'delete',
        child: Row(
          children: [
            Icon(BI.delete, size: 16, color: colors.error),
            const SizedBox(width: 8),
            Text(
              isReturn ? 'Delete Return' : 'Delete',
              style: TextStyle(color: colors.error),
            ),
          ],
        ),
      ),
    ];

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: menuItems,
    ).then((value) {
      if (!mounted) return;
      if (value == 'rename') {
        _startEditing();
      } else if (value == 'color') {
        // Use this.context since we've verified mounted above
        _showColorPicker(this.context, position);
      } else if (value == 'duplicate' && widget.onDuplicatePressed != null) {
        widget.onDuplicatePressed!();
      } else if (value == 'convert_to_sampler' &&
          widget.onConvertToSampler != null) {
        widget.onConvertToSampler!();
      } else if (value != null && value.startsWith('send_')) {
        final returnId = int.tryParse(value.substring(5));
        if (returnId != null) {
          final ret = widget.existingReturns
              .where((r) => r.id == returnId)
              .firstOrNull;
          if (ret != null) widget.onSendToReturn?.call(ret);
        }
      } else if (value == 'delete') {
        if (isReturn) {
          widget.onDeleteReturn?.call();
        } else {
          widget.onDeletePressed?.call();
        }
      }
    });
  }

  void _showColorPicker(BuildContext context, Offset position) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: dialogContext.colors.standard,
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Track Color',
                style: TextStyle(
                  color: dialogContext.colors.textPrimary,
                  fontSize: 14,
                  fontWeight: BT.weightSemiBold,
                ),
              ),
              const SizedBox(height: 12),
              // 16 color grid (2 rows × 8 columns)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1: Vibrant colors (first 8)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(8, (index) {
                      final color = TrackColors.manualPalette[index];
                      final isSelected = widget.trackColor == color;
                      return Padding(
                        padding: EdgeInsets.only(right: index < 7 ? 6 : 0),
                        child: GestureDetector(
                          onTap: () {
                            widget.onColorChanged?.call(color);
                            Navigator.of(dialogContext).pop();
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelected
                                    ? dialogContext.colors.textPrimary
                                    : dialogContext.colors.hover,
                                width: isSelected ? 2 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: color.withValues(alpha: 0.5),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 6),
                  // Row 2: Softer variants (last 8)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(8, (index) {
                      final color = TrackColors.manualPalette[index + 8];
                      final isSelected = widget.trackColor == color;
                      return Padding(
                        padding: EdgeInsets.only(right: index < 7 ? 6 : 0),
                        child: GestureDetector(
                          onTap: () {
                            widget.onColorChanged?.call(color);
                            Navigator.of(dialogContext).pop();
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelected
                                    ? dialogContext.colors.textPrimary
                                    : dialogContext.colors.hover,
                                width: isSelected ? 2 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: color.withValues(alpha: 0.5),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButtons({
    double buttonSize = 22,
    double spacing = 4,
    double fontSize = 10,
  }) {
    // Show arm button only for Audio and MIDI tracks (not master, return, group)
    final canArm =
        !widget.isReturnTrack &&
        (widget.trackType.toLowerCase() == 'audio' ||
            widget.trackType.toLowerCase() == 'midi');

    return Row(
      children: [
        // Mute button - Yellow/Amber when active
        _buildControlButton(
          'M',
          widget.isMuted,
          context.colors.muteActive,
          widget.onMuteToggle,
          buttonSize,
          fontSize,
        ),
        SizedBox(width: spacing),
        // Solo button - Blue when active
        _buildControlButton(
          'S',
          widget.isSoloed,
          context.colors.soloActive,
          widget.onSoloToggle,
          buttonSize,
          fontSize,
        ),
        if (!widget.isReturnTrack) ...[
          SizedBox(width: spacing),
          // Record arm button - Red when active
          _buildArmButton(canArm, buttonSize, fontSize),
        ],
        // Input monitoring button - audio tracks only (the engine only
        // monitors audio input; MIDI tracks have nothing to pass through).
        // Only shown while armed: monitoring is irrelevant otherwise, and
        // this is when the feedback escape hatch matters.
        if (!widget.isReturnTrack &&
            widget.isArmed &&
            widget.trackType.toLowerCase() == 'audio' &&
            widget.onMonitorToggle != null) ...[
          SizedBox(width: spacing),
          _buildControlButton(
            'I',
            widget.inputMonitoring,
            context.colors.success,
            widget.onMonitorToggle,
            buttonSize,
            fontSize,
          ),
        ],
      ],
    );
  }

  Widget _buildControlButton(
    String label,
    bool isActive,
    Color activeColor,
    VoidCallback? onPressed,
    double size,
    double fontSize,
  ) {
    return GestureDetector(
      onTap: onPressed,
      child: MouseRegion(
        cursor: onPressed != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isActive ? activeColor : context.colors.surface,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isActive
                  ? context.colors.darkest
                  : context.colors.textSecondary,
              fontSize: fontSize,
              fontWeight: BT.weightSemiBold,
            ),
          ),
        ),
      ),
    );
  }

  /// Build arm button with Shift+click support for multi-arm mode
  /// Matches M/S button style but uses red when armed
  Widget _buildArmButton(bool canArm, double size, double fontSize) {
    return GestureDetector(
      onTap: canArm
          ? () {
              final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
              if (shiftPressed && widget.onArmShiftClick != null) {
                widget.onArmShiftClick!();
              } else {
                widget.onArmToggle?.call();
              }
            }
          : null,
      child: MouseRegion(
        cursor: canArm ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: widget.isArmed
                ? context.colors.recordActive
                : context.colors.surface,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            'R',
            style: TextStyle(
              color: widget.isArmed
                  ? context.colors.darkest
                  : context.colors.textSecondary,
              fontSize: fontSize,
              fontWeight: BT.weightSemiBold,
            ),
          ),
        ),
      ),
    );
  }

  /// Get tinted background color (track color at 30% opacity over standard background)
  Color _getTintedBackgroundColor() {
    final trackColor = widget.trackColor;
    if (trackColor == null) return context.colors.standard;

    // Blend track color at 30% opacity with the standard background
    return Color.alphaBlend(
      trackColor.withValues(alpha: 0.2),
      context.colors.standard,
    );
  }

  /// Get text colour - use the regular track color for text
  Color _getTextColor() {
    final trackColor = widget.trackColor;
    if (trackColor == null) return context.colors.textPrimary;

    // Use the track color directly for text (like Master track uses accent color)
    return trackColor;
  }

  String _getTrackEmoji() {
    // Use custom icon if set
    if (widget.customIcon != null) return widget.customIcon!;

    final lowerName = widget.trackName.toLowerCase();
    final lowerType = widget.trackType.toLowerCase();

    if (lowerType == 'master') return '🎚️';
    if (lowerName.contains('guitar')) return '🎸';
    if (lowerName.contains('piano') || lowerName.contains('keys')) return '🎹';
    if (lowerName.contains('drum')) return '🥁';
    if (lowerName.contains('vocal') || lowerName.contains('voice')) return '🎤';
    if (lowerName.contains('bass')) return '🎸';
    if (lowerName.contains('synth')) return '🎹';
    if (lowerType == 'midi') return '🎼';
    if (lowerType == 'audio') return '🔊';

    return '🎵'; // Default
  }

  /// Emoji grid for track icon picker
  static const List<String> _iconEmojis = [
    '🎤',
    '🎸',
    '🎹',
    '🥁',
    '🎺',
    '🎷',
    '🎻',
    '🎧',
    '🎵',
    '🎶',
    '🔊',
    '🎼',
    '🪗',
    '🪘',
    '🪕',
    '🎙️',
  ];

  /// Show icon picker popup
  void _showIconPopup(BuildContext context) {
    final RenderBox box = this.context.findRenderObject() as RenderBox;
    final Offset position = box.localToGlobal(Offset.zero);

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        return Stack(
          children: [
            // Dismiss on tap outside
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(dialogContext).pop(),
                behavior: HitTestBehavior.opaque,
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            // Popup positioned near the icon
            Positioned(
              left: position.dx,
              top: position.dy + box.size.height,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                color: dialogContext.colors.elevated,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: dialogContext.colors.hover,
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Track Icon',
                        style: TextStyle(
                          color: dialogContext.colors.textPrimary,
                          fontSize: 12,
                          fontWeight: BT.weightSemiBold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Emoji grid (2 rows x 8 cols)
                      ...List.generate(2, (row) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: row == 0 ? 4 : 0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(8, (col) {
                              final idx = row * 8 + col;
                              final emoji = _iconEmojis[idx];
                              final isSelected = _getTrackEmoji() == emoji;
                              return Padding(
                                padding: EdgeInsets.only(
                                  right: col < 7 ? 4 : 0,
                                ),
                                child: GestureDetector(
                                  onTap: () {
                                    widget.onIconChanged?.call(emoji);
                                    Navigator.of(dialogContext).pop();
                                  },
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: isSelected
                                            ? dialogContext.colors.textPrimary
                                            : dialogContext.colors.hover,
                                        width: isSelected ? 2 : 1,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      emoji,
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      // Color grid below
                      Text(
                        'Track Color',
                        style: TextStyle(
                          color: dialogContext.colors.textPrimary,
                          fontSize: 12,
                          fontWeight: BT.weightSemiBold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...List.generate(2, (row) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: row == 0 ? 4 : 0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(8, (col) {
                              final color =
                                  TrackColors.manualPalette[row * 8 + col];
                              final isSelected = widget.trackColor == color;
                              return Padding(
                                padding: EdgeInsets.only(
                                  right: col < 7 ? 4 : 0,
                                ),
                                child: GestureDetector(
                                  onTap: () {
                                    widget.onColorChanged?.call(color);
                                    Navigator.of(dialogContext).pop();
                                  },
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: isSelected
                                            ? dialogContext.colors.textPrimary
                                            : dialogContext.colors.hover,
                                        width: isSelected ? 2 : 1,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Master track strip - special styling for master track
/// Layout matches regular tracks with 2-row design:
/// Row 1: Icon + "Master" text + Pan knob
/// Row 2: dB display + Volume slider
class MasterTrackMixerStrip extends StatefulWidget {
  // Height constraints
  static const double kMinHeight = UIConstants.trackMinHeight;
  static const double kMaxHeight = UIConstants.trackMaxHeight;
  static const double kDefaultHeight = 50.0;

  final double volumeDb;
  final double pan;
  final double peakLevelLeft;
  final double peakLevelRight;
  final Function(double)? onVolumeChanged;
  final Function(double)? onPanChanged;
  final VoidCallback? onVolumeDragStart;
  final VoidCallback? onVolumeDragEnd;
  final VoidCallback? onPanDragStart;
  final VoidCallback? onPanDragEnd;
  final VoidCallback? onFxButtonPressed;

  // Selection (tap the strip to edit Master's effects chain in the editor)
  final bool isSelected;
  final VoidCallback? onTap;

  // Track height resizing (top edge for master)
  final double trackHeight;
  final Function(double)? onHeightChanged;

  // Strip width (for responsive layout)
  final double stripWidth;

  const MasterTrackMixerStrip({
    super.key,
    required this.volumeDb,
    required this.pan,
    this.peakLevelLeft = 0.0,
    this.peakLevelRight = 0.0,
    this.onVolumeChanged,
    this.onPanChanged,
    this.onVolumeDragStart,
    this.onVolumeDragEnd,
    this.onPanDragStart,
    this.onPanDragEnd,
    this.onFxButtonPressed,
    this.isSelected = false,
    this.onTap,
    this.trackHeight = kDefaultHeight,
    this.onHeightChanged,
    this.stripWidth = 380.0,
  });

  @override
  State<MasterTrackMixerStrip> createState() => _MasterTrackMixerStripState();
}

class _MasterTrackMixerStripState extends State<MasterTrackMixerStrip> {
  // Resize state
  bool _isResizing = false;
  double _resizeStartY = 0.0;
  double _resizeStartHeight = 0.0;

  /// Calculate scale factor based on track height (0.0 at 40px, 1.0 at 76px+)
  double get _scaleFactor {
    const minHeight = MasterTrackMixerStrip.kMinHeight;
    const standardHeight = UIConstants.trackStandardHeight;
    return ((widget.trackHeight - minHeight) / (standardHeight - minHeight))
        .clamp(0.0, 1.0);
  }

  /// Lerp helper for scaling values
  double _lerp(double min, double max, double t) => min + (max - min) * t;

  /// Get tinted background color (accent color at 20% opacity)
  Color _getTintedBackgroundColor(BuildContext context) {
    final masterColor = context.colors.accent;
    return Color.alphaBlend(
      masterColor.withValues(alpha: 0.2),
      context.colors.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final masterColor = context.colors.accent;
    // When selected, the border goes white to match the regular track strips.
    final borderColor = widget.isSelected
        ? Colors.white.withValues(alpha: 0.9)
        : masterColor;
    final scale = _scaleFactor;

    // Layout dimensions (same logic as regular tracks)
    const double borderOffset = 4.0;
    final availableHeight = widget.trackHeight - borderOffset;
    final topPadding = _lerp(-1, 6, scale).clamp(0.0, 6.0);
    final bottomPadding = _lerp(2, 6, scale);
    const double horizontalPadding = 6.0;
    final rowHeight = ((availableHeight - topPadding - bottomPadding) / 2)
        .clamp(11.0, 28.0);

    // Pan knob scales with height
    final panSize = _lerp(14, 22, scale);

    // Fixed sizes
    const double fontSize = 12.0;
    const double dbFontSize = UIConstants.dbFontSize;
    const double dbContainerWidth = UIConstants.dbContainerWidth;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: widget.stripWidth,
        height: widget.trackHeight,
        child: Stack(
          children: [
            // Main content container
            Container(
              width: widget.stripWidth,
              height: widget.trackHeight,
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: _getTintedBackgroundColor(context),
                border: Border(
                  left: BorderSide(color: borderColor, width: 4),
                  top: BorderSide(color: borderColor, width: 2),
                  right: BorderSide(color: borderColor, width: 2),
                  bottom: BorderSide(color: borderColor, width: 2),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  left: horizontalPadding,
                  right: horizontalPadding,
                  top: topPadding,
                  bottom: bottomPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Row 1: Icon + "Master" text + Pan knob
                    SizedBox(
                      height: rowHeight,
                      child: Row(
                        children: [
                          // Icon (headphones)
                          const Text('🎧', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          // "Master" text
                          Expanded(
                            child: Text(
                              'Master',
                              style: TextStyle(
                                color: masterColor,
                                fontSize: fontSize,
                                fontWeight: BT.weightSemiBold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (widget.onFxButtonPressed != null)
                            GestureDetector(
                              onTap: widget.onFxButtonPressed,
                              child: Icon(
                                BI.lightning,
                                size: 16,
                                color: context.colors.textSecondary,
                              ),
                            ),
                          if (widget.onFxButtonPressed != null)
                            const SizedBox(width: 4),
                          // Pan knob (aligned right)
                          PanKnob(
                            pan: widget.pan,
                            onChanged: widget.onPanChanged,
                            onDragStart: widget.onPanDragStart,
                            onDragEnd: widget.onPanDragEnd,
                            size: panSize,
                          ),
                        ],
                      ),
                    ),
                    // Row 2: dB + Volume Slider (same as regular tracks)
                    SizedBox(
                      height: rowHeight,
                      child: Row(
                        children: [
                          // dB value display — drag vertically to scrub, click to type.
                          VolumeReadoutBox(
                            volumeDb: widget.volumeDb,
                            onVolumeChanged: widget.onVolumeChanged,
                            onVolumeDragStart: widget.onVolumeDragStart,
                            onVolumeDragEnd: widget.onVolumeDragEnd,
                            width: dbContainerWidth,
                            fontSize: dbFontSize,
                            textColor: context.colors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          // Volume Slider
                          Expanded(
                            child: CapsuleFader(
                              leftLevel: widget.peakLevelLeft,
                              rightLevel: widget.peakLevelRight,
                              volumeDb: widget.volumeDb,
                              onVolumeChanged: widget.onVolumeChanged,
                              onDragStart: widget.onVolumeDragStart,
                              onDragEnd: widget.onVolumeDragEnd,
                              onDoubleTap: () =>
                                  widget.onVolumeChanged?.call(0.0),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Top resize handle (master uses top edge, opposite of regular tracks)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: UIConstants.trackResizeHandleHeight,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeRow,
                child: GestureDetector(
                  onVerticalDragStart: (details) {
                    _isResizing = true;
                    _resizeStartY = details.globalPosition.dy;
                    _resizeStartHeight = widget.trackHeight;
                  },
                  onVerticalDragUpdate: (details) {
                    if (_isResizing) {
                      // Note: negative delta because dragging UP should increase height
                      final delta = _resizeStartY - details.globalPosition.dy;
                      final newHeight = (_resizeStartHeight + delta).clamp(
                        MasterTrackMixerStrip.kMinHeight,
                        MasterTrackMixerStrip.kMaxHeight,
                      );
                      widget.onHeightChanged?.call(newHeight);
                    }
                  },
                  onVerticalDragEnd: (details) {
                    _isResizing = false;
                  },
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact knob for send amount (0.0–1.0 linear).
class _SendAmountKnob extends StatelessWidget {
  final double amountLinear;
  final double size;
  final ValueChanged<double>? onChanged;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const _SendAmountKnob({
    required this.amountLinear,
    required this.size,
    this.onChanged,
    this.onDragStart,
    this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: GestureDetector(
        onVerticalDragStart: (_) => onDragStart?.call(),
        onVerticalDragUpdate: (details) {
          if (onChanged == null) return;
          final delta = -details.delta.dy / 120.0;
          onChanged!((amountLinear + delta).clamp(0.0, 1.0));
        },
        onVerticalDragEnd: (_) => onDragEnd?.call(),
        onVerticalDragCancel: () => onDragEnd?.call(),
        onDoubleTap: () {
          onDragStart?.call();
          onChanged?.call(0.0);
          onDragEnd?.call();
        },
        child: CustomPaint(
          size: Size(size, size),
          painter: _SendKnobPainter(
            amount: amountLinear,
            colors: context.colors,
          ),
        ),
      ),
    );
  }
}

class _SendKnobPainter extends CustomPainter {
  final double amount;
  final BoojyColors colors;

  _SendKnobPainter({required this.amount, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;
    final trackPaint = Paint()
      ..color = colors.divider
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, trackPaint);

    if (amount > 0.001) {
      final activePaint = Paint()
        ..color = colors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      const startAngle = 135 * 3.14159265 / 180;
      final sweep = 270 * 3.14159265 / 180 * amount;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        activePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SendKnobPainter oldDelegate) =>
      oldDelegate.amount != amount || oldDelegate.colors != colors;
}
