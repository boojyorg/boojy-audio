import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../audio_engine.dart';
import '../models/instrument_data.dart';
import '../models/track_automation_data.dart';
import '../models/vst3_plugin_data.dart';
import '../services/tool_mode_resolver.dart';
import '../theme/theme_extension.dart';
import '../theme/theme_provider.dart';
import '../utils/track_colors.dart';
import 'instrument_browser.dart';
import 'pan_knob.dart';
import 'capsule_fader.dart';
import 'input_selector_dropdown.dart';

/// Unified track strip combining track info and mixer controls
/// Displayed on the right side of timeline, aligned with each track row
class TrackMixerStrip extends StatefulWidget {
  // Height constraints
  static const double kMinHeight = 40.0;
  static const double kMaxHeight = 400.0;
  final int trackId;
  final int displayIndex; // Sequential display number (1, 2, 3...) - NOT internal track ID
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
  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;
  final VoidCallback? onArmToggle; // Toggle recording arm (exclusive)
  final VoidCallback? onArmShiftClick; // Shift+click for multi-arm mode
  final VoidCallback? onAutomationToggle; // Toggle automation lane visibility
  final bool showAutomation; // Whether automation lane is visible

  // Automation parameter controls
  final AutomationParameter selectedParameter; // Currently selected parameter
  final Function(AutomationParameter)? onParameterChanged; // Parameter dropdown changed
  final VoidCallback? onResetParameter; // Reset parameter to default
  final VoidCallback? onAddParameter; // Add another parameter lane

  // Automation lane data (for inline lane in mixer)
  final TrackAutomationLane? automationLane;
  final double pixelsPerBeat;
  final double totalBeats;
  final Function(AutomationPoint)? onAutomationPointAdded;
  final Function(String pointId, AutomationPoint)? onAutomationPointUpdated;
  final Function(String pointId)? onAutomationPointDeleted;
  final Function(double? value)? onPreviewValue; // Callback for live value display during drag
  final double? previewParameterValue; // Live preview value during drag

  final Function(bool isShiftHeld)? onTap; // Unified track selection callback (with shift state for multi-select)
  final VoidCallback? onDoubleTap; // Double-click to open editor
  final VoidCallback? onDeletePressed;
  final VoidCallback? onDuplicatePressed;
  final VoidCallback? onConvertToSampler; // Convert Audio track to Sampler
  final Function(String)? onNameChanged; // Inline rename callback
  final bool isSelected; // Track selection state
  final bool isArmed; // Recording arm state

  // MIDI instrument selection
  final InstrumentData? instrumentData;
  final Function(String)? onInstrumentSelect; // Callback with instrument ID

  // M10: VST3 Plugin support
  final int vst3PluginCount;
  final VoidCallback? onFxButtonPressed;
  final Function(Vst3Plugin)? onVst3PluginDropped;
  final Function(Vst3Plugin)? onVst3InstrumentDropped; // VST3 instrument swap
  final Function(Instrument)? onInstrumentDropped; // Built-in instrument swap
  final VoidCallback? onEditPluginsPressed; // New: Edit active plugins

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
  final double? inputLevel; // 0.0 to 1.0, input level overlay on fader when armed

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
    this.onMuteToggle,
    this.onSoloToggle,
    this.onArmToggle,
    this.onArmShiftClick,
    this.onAutomationToggle,
    this.showAutomation = false,
    this.selectedParameter = AutomationParameter.volume,
    this.onParameterChanged,
    this.onResetParameter,
    this.onAddParameter,
    this.automationLane,
    this.pixelsPerBeat = 20.0,
    this.totalBeats = 256.0,
    this.onAutomationPointAdded,
    this.onAutomationPointUpdated,
    this.onAutomationPointDeleted,
    this.onPreviewValue,
    this.previewParameterValue,
    this.onTap,
    this.onDoubleTap,
    this.onDeletePressed,
    this.onDuplicatePressed,
    this.onConvertToSampler,
    this.onNameChanged,
    this.isSelected = false,
    this.isArmed = false,
    this.instrumentData,
    this.onInstrumentSelect,
    this.vst3PluginCount = 0,
    this.onFxButtonPressed,
    this.onVst3PluginDropped,
    this.onVst3InstrumentDropped,
    this.onInstrumentDropped,
    this.onEditPluginsPressed,
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
  late TextEditingController _nameController;
  late FocusNode _focusNode;

  // Resize state
  bool _isResizing = false;
  double _resizeStartY = 0.0;
  double _resizeStartHeight = 0.0;


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

  /// Calculate scale factor based on track height (0.0 at 40px, 1.0 at 76px+)
  double get _scaleFactor {
    const minHeight = 40.0;
    const standardHeight = 76.0;
    return ((widget.clipHeight - minHeight) / (standardHeight - minHeight)).clamp(0.0, 1.0);
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
    final scale = _scaleFactor;

    // Available height for content
    // Border: 4px left, 2px top/right/bottom - vertical offset is top + bottom = 4px
    const double borderOffset = 4.0;
    final availableHeight = widget.clipHeight - borderOffset;

    // Calculate layout dimensions
    // Top padding: 0 at compact for row 1 at very top, 6 at standard
    final topPadding = _lerp(-1, 6, scale).clamp(0.0, 6.0);
    // Bottom padding: 2 at compact, 6 at standard
    final bottomPadding = _lerp(2, 6, scale);
    // Fixed horizontal padding so dB x-position is consistent
    const double horizontalPadding = 6.0;
    // Row 2 height - slightly smaller at compact to prevent overflow
    final rowHeight = ((availableHeight - topPadding - bottomPadding) / 2).clamp(11.0, 28.0);

    // MSR buttons and Pan scale with height
    final buttonSize = _lerp(14, 22, scale);
    final panSize = _lerp(14, 22, scale);
    final buttonSpacing = _lerp(2, 4, scale);
    final buttonFontSize = _lerp(8, 10, scale);

    // Fixed sizes - consistent across all heights
    const double fontSize = 12.0;
    const double iconSize = 14.0;
    const double dbFontSize = 10.0;
    const double dbContainerWidth = 56.0; // Fixed width so slider aligns

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
              Expanded(child: _buildTrackInfoRow(fontSize: fontSize, iconSize: iconSize)),
              const SizedBox(width: 4),
              // Input selector (Audio/Sampler tracks only)
              if (_showInputSelector)
                _buildInputSelector(buttonSize: buttonSize, fontSize: buttonFontSize),
              if (_showInputSelector)
                const SizedBox(width: 4),
              // M, S, R buttons (scale with height)
              _buildControlButtons(buttonSize: buttonSize, spacing: buttonSpacing, fontSize: buttonFontSize),
              const SizedBox(width: 6),
              // Pan knob (scales with height)
              PanKnob(
                pan: widget.pan,
                onChanged: widget.onPanChanged,
                size: panSize,
              ),
            ],
          ),
          // Row 2: Automation SplitButton + dB + Volume Slider
          // Check for volume preview during automation drag
          Builder(
            builder: (context) {
              // Use preview value if dragging volume automation
              final hasVolumePreview = widget.previewParameterValue != null &&
                  widget.selectedParameter == AutomationParameter.volume;
              final displayVolumeDb = hasVolumePreview
                  ? VolumeConversion.normalizedToDb(widget.previewParameterValue!)
                  : widget.volumeDb;

              return SizedBox(
                height: rowHeight,
                child: Row(
                  children: [
                    // Automation SplitButton (Icon+Auto | dropdown)
                    _buildAutomationButton(context, rowHeight),
                    const SizedBox(width: 4),
                    // dB value display (fixed size and width)
                    SizedBox(
                      width: dbContainerWidth,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.colors.darkest,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          displayVolumeDb <= -60.0 ? '-∞ dB' : '${displayVolumeDb.toStringAsFixed(1)} dB',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: hasVolumePreview ? context.colors.textPrimary : context.colors.textSecondary,
                            fontSize: dbFontSize,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Volume Slider (height scales, X position fixed)
                    Expanded(
                      child: CapsuleFader(
                        leftLevel: widget.peakLevelLeft,
                        rightLevel: widget.peakLevelRight,
                        volumeDb: displayVolumeDb,
                        onVolumeChanged: widget.onVolumeChanged,
                        onDoubleTap: () => widget.onVolumeChanged?.call(0.0),
                        inputLevel: widget.isArmed ? widget.inputLevel : null,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // Row 3-4: Automation Controls (only when visible)
          if (widget.showAutomation)
            _buildAutomationControlsSection(context),
        ],
      ),
    );
  }

  /// Build automation controls section (parameter row)
  /// Row 3: [ + ] + [Volume ▼] dropdown + [value] + [↺] reset
  Widget _buildAutomationControlsSection(BuildContext context) {
    final scale = _scaleFactor;
    final rowHeight = _lerp(20, 24, scale);
    final fontSize = _lerp(9, 10, scale);
    final param = widget.selectedParameter;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SizedBox(
        height: rowHeight,
        child: Row(
          children: [
            // [ + ] add parameter button (shorter, wider)
            _buildAddParameterButton(context, fontSize, rowHeight),
            const SizedBox(width: 4),
            // [Volume ▼] dropdown
            _buildParameterDropdown(context, fontSize, rowHeight),
            const SizedBox(width: 4),
            // [value] display
            _buildParameterValueDisplay(context, param, fontSize),
            const SizedBox(width: 4),
            // [↺] reset button
            _buildResetButton(context, rowHeight),
          ],
        ),
      ),
    );
  }

  /// Build parameter dropdown (Volume, Pan, etc.)
  Widget _buildParameterDropdown(BuildContext context, double fontSize, double rowHeight) {
    final colors = context.colors;
    final param = widget.selectedParameter;

    return Container(
      height: rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colors.dark,
        borderRadius: BorderRadius.circular(2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AutomationParameter>(
          value: param,
          isDense: true,
          dropdownColor: colors.elevated,
          icon: Icon(Icons.arrow_drop_down, size: 14, color: colors.textSecondary),
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: fontSize,
          ),
          items: AutomationParameter.values.map((p) {
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

  /// Build parameter value display (matches volume display style above)
  Widget _buildParameterValueDisplay(BuildContext context, AutomationParameter param, double fontSize) {
    final colors = context.colors;
    final hasPreview = widget.previewParameterValue != null;
    const double dbFontSize = 10.0; // Match volume display
    const double containerWidth = 56.0; // Match volume display width

    // Get current value based on parameter type
    // Use preview value during drag if available
    final String valueText;
    if (param == AutomationParameter.volume) {
      if (hasPreview) {
        // Preview value is normalized (0-1), convert to dB
        valueText = VolumeConversion.normalizedToDisplayString(widget.previewParameterValue!);
      } else {
        valueText = widget.volumeDb <= -60.0 ? '-∞ dB' : '${widget.volumeDb.toStringAsFixed(1)} dB';
      }
    } else if (param == AutomationParameter.pan) {
      final panValue = hasPreview ? widget.previewParameterValue! : widget.pan;
      if (panValue == 0) {
        valueText = 'C';
      } else if (panValue < 0) {
        valueText = '${(panValue * 100).abs().toInt()}L';
      } else {
        valueText = '${(panValue * 100).toInt()}R';
      }
    } else {
      valueText = '0';
    }

    return Container(
      width: containerWidth,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: colors.darkest,
        borderRadius: BorderRadius.circular(3), // Match volume display
      ),
      child: Text(
        valueText,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: hasPreview ? colors.textPrimary : colors.textSecondary, // Highlight during drag
          fontSize: dbFontSize, // Match volume display
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  /// Build reset button
  Widget _buildResetButton(BuildContext context, double rowHeight) {
    final colors = context.colors;

    return GestureDetector(
      onTap: widget.onResetParameter,
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
            Icons.refresh,
            size: rowHeight * 0.6,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// Build add parameter button (shorter and wider)
  Widget _buildAddParameterButton(BuildContext context, double fontSize, double rowHeight) {
    final colors = context.colors;
    final buttonHeight = rowHeight * 0.75; // Shorter than row height

    return GestureDetector(
      onTap: widget.onAddParameter,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: buttonHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10), // Wider padding
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Icon(
            Icons.add,
            size: fontSize + 2,
            color: colors.textSecondary,
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
          onTap: widget.onIconChanged != null ? () => _showIconPopup(context) : null,
          child: MouseRegion(
            cursor: widget.onIconChanged != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: Text(_getTrackEmoji(), style: TextStyle(fontSize: iconSize)),
          ),
        ),
        const SizedBox(width: 6),
        // Number (sequential display index, not internal ID) - fixed size
        Text(
          '${widget.displayIndex}',
          style: TextStyle(
            color: textColor,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        // Name (editable) - expanded to fill remaining space
        Expanded(
          child: _isEditing
              ? TextField(
                  controller: _nameController,
                  focusNode: _focusNode,
                  style: TextStyle(
                    color: textColor,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
        ),
      ],
    );
  }

  /// Get display name for standard layout
  String _getStandardDisplayName() {
    // Show track name (which may be auto-populated from instrument)
    return widget.trackName;
  }

  /// Whether to show the input selector (Audio and Sampler tracks only)
  bool get _showInputSelector {
    final type = widget.trackType.toLowerCase();
    return type == 'audio' || type == 'sampler';
  }

  /// Get short label for current input assignment
  String _getInputLabel() {
    if (widget.inputDeviceIndex < 0) return 'No In';

    // If we have device info, use device name + channel
    if (widget.inputDevices.isNotEmpty && widget.inputDeviceIndex < widget.inputDevices.length) {
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
        cursor: isLocked ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
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
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (!isLocked) ...[
                const SizedBox(width: 1),
                Icon(
                  Icons.arrow_drop_down,
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

    // Nested DragTargets: VST3 (instruments + effects) -> Built-in Instruments
    return DragTarget<Vst3Plugin>(
      onWillAcceptWithDetails: (details) {
        // Accept VST3 instruments only on MIDI tracks, effects on any track
        if (details.data.isInstrument) {
          return isMidiTrack;
        }
        return true; // Effects accepted on any track
      },
      onAcceptWithDetails: (details) {
        if (details.data.isInstrument) {
          widget.onVst3InstrumentDropped?.call(details.data);
        } else {
          widget.onVst3PluginDropped?.call(details.data);
        }
      },
      builder: (context, candidateVst3, rejectedVst3) {
        return DragTarget<Instrument>(
          onWillAcceptWithDetails: (_) => isMidiTrack,
          onAcceptWithDetails: (details) {
            widget.onInstrumentDropped?.call(details.data);
          },
          builder: (context, candidateInstrument, rejectedInstrument) {
            final isHovered = candidateVst3.isNotEmpty || candidateInstrument.isNotEmpty;

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
                                  : (widget.trackColor ?? context.colors.textSecondary),
                              width: 4,
                            ),
                            top: BorderSide(
                              color: widget.isSelected
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : (widget.trackColor ?? context.colors.textSecondary),
                              width: 2,
                            ),
                            right: BorderSide(
                              color: widget.isSelected
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : (widget.trackColor ?? context.colors.textSecondary),
                              width: 2,
                            ),
                            bottom: BorderSide(
                              color: widget.isSelected
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : (widget.trackColor ?? context.colors.textSecondary),
                              width: 2,
                            ),
                          ),
                  ),
                  child: _buildStandardLayout(context, isHovered),
                ),
                // Bottom resize handle
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 6,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeRow,
                    child: GestureDetector(
                      onVerticalDragStart: (details) {
                        _isResizing = true;
                        _resizeStartY = details.globalPosition.dy;
                        _resizeStartHeight = widget.clipHeight;
                      },
                      onVerticalDragUpdate: (details) {
                        if (_isResizing) {
                          final delta = details.globalPosition.dy - _resizeStartY;
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
                      child: Container(
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
          },
        );
      },
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    // Don't show context menu for master track
    if (widget.trackType.toLowerCase() == 'master') {
      debugPrint('TrackMixerStrip: Skipping context menu for master track');
      return;
    }

    debugPrint('TrackMixerStrip: Showing context menu at position $position for track ${widget.trackName}');

    // Use listen: false to avoid provider error in callback context
    final colors = Provider.of<ThemeProvider>(context, listen: false).colors;
    final trackColor = widget.trackColor;
    final isAudioTrack = widget.trackType.toLowerCase() == 'audio';

    final menuItems = <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: 'rename',
        child: Row(
          children: [
            Icon(Icons.edit, size: 16, color: colors.textPrimary),
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
        child: Row(
          children: [
            Icon(Icons.content_copy, size: 16, color: colors.textPrimary),
            const SizedBox(width: 8),
            Text('Duplicate', style: TextStyle(color: colors.textPrimary)),
          ],
        ),
      ),
      // Show "Convert to Sampler" only for Audio tracks
      if (isAudioTrack && widget.onConvertToSampler != null)
        PopupMenuItem<String>(
          value: 'convert_to_sampler',
          child: Row(
            children: [
              Icon(Icons.music_note, size: 16, color: colors.textPrimary),
              const SizedBox(width: 8),
              Text('Convert to Sampler', style: TextStyle(color: colors.textPrimary)),
            ],
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'delete',
        child: Row(
          children: [
            Icon(Icons.delete, size: 16, color: colors.error),
            const SizedBox(width: 8),
            Text('Delete', style: TextStyle(color: colors.error)),
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
      } else if (value == 'convert_to_sampler' && widget.onConvertToSampler != null) {
        widget.onConvertToSampler!();
      } else if (value == 'delete' && widget.onDeletePressed != null) {
        widget.onDeletePressed!();
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
                  fontWeight: FontWeight.w600,
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
                                      )
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
                                      )
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

  Widget _buildControlButtons({double buttonSize = 22, double spacing = 4, double fontSize = 10}) {
    // Show arm button only for Audio and MIDI tracks (not master, return, group)
    final canArm = widget.trackType.toLowerCase() == 'audio' || widget.trackType.toLowerCase() == 'midi';

    return Row(
      children: [
        // Mute button - Yellow/Amber when active
        _buildControlButton('M', widget.isMuted, context.colors.muteActive, widget.onMuteToggle, buttonSize, fontSize),
        SizedBox(width: spacing),
        // Solo button - Blue when active
        _buildControlButton('S', widget.isSoloed, context.colors.soloActive, widget.onSoloToggle, buttonSize, fontSize),
        SizedBox(width: spacing),
        // Record arm button - Red when active
        // Supports Shift+click for multi-arm mode
        _buildArmButton(canArm, buttonSize, fontSize),
      ],
    );
  }

  Widget _buildControlButton(String label, bool isActive, Color activeColor, VoidCallback? onPressed, double size, double fontSize) {
    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isActive ? activeColor : context.colors.surface,
          // All active buttons use dark text for better contrast
          foregroundColor: isActive
              ? context.colors.darkest
              : context.colors.textSecondary,
          padding: EdgeInsets.zero,
          minimumSize: Size(size, size),
          textStyle: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        child: Text(label),
      ),
    );
  }

  /// Build arm button with Shift+click support for multi-arm mode
  Widget _buildArmButton(bool canArm, double size, double fontSize) {
    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: canArm
            ? () {
                // Check if Shift is held for multi-arm mode
                final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
                if (shiftPressed && widget.onArmShiftClick != null) {
                  widget.onArmShiftClick!();
                } else {
                  widget.onArmToggle?.call();
                }
              }
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.isArmed ? context.colors.recordActive : context.colors.surface,
          foregroundColor: widget.isArmed ? context.colors.darkest : context.colors.textSecondary,
          padding: EdgeInsets.zero,
          minimumSize: Size(size, size),
          textStyle: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        child: const Text('R'),
      ),
    );
  }

  /// Build automation toggle button (grey when off, blue when on)
  /// Shows text only if volume slider would still be >= 80px wide
  Widget _buildAutomationButton(BuildContext context, double rowHeight) {
    final colors = context.colors;
    final isActive = widget.showAutomation;
    final buttonHeight = (rowHeight * 0.85).clamp(16.0, 22.0);
    final fontSize = (rowHeight * 0.4).clamp(8.0, 10.0);
    final iconSize = (rowHeight * 0.5).clamp(10.0, 14.0);

    // Calculate if showing text would leave enough room for volume slider
    // Strip width - horizontal padding (12) - dB container (56) - gaps (12) = available
    // Button with text: ~80px, icon only: ~28px
    // Show text if slider would be >= 80px
    final availableForButtonAndSlider = widget.stripWidth - 12 - 56 - 12;
    const buttonWithTextWidth = 80.0;
    const minSliderWidth = 80.0;
    final showText = (availableForButtonAndSlider - buttonWithTextWidth) >= minSliderWidth;

    return GestureDetector(
      onTap: widget.onAutomationToggle,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: buttonHeight,
          padding: EdgeInsets.symmetric(horizontal: showText ? 6 : 4),
          decoration: BoxDecoration(
            // Same style as piano roll toggle buttons (Legato, Reverse, etc.)
            color: isActive ? colors.accent : colors.dark,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timeline,
                size: iconSize,
                color: isActive ? colors.elevated : colors.textPrimary,
              ),
              if (showText) ...[
                const SizedBox(width: 4),
                Text(
                  'Automation',
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                    color: isActive ? colors.elevated : colors.textPrimary,
                  ),
                ),
              ],
            ],
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
    '🎤', '🎸', '🎹', '🥁', '🎺', '🎷', '🎻', '🎧',
    '🎵', '🎶', '🔊', '🎼', '🪗', '🪘', '🪕', '🎙️',
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
                    border: Border.all(color: dialogContext.colors.hover, width: 0.5),
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
                          fontWeight: FontWeight.w600,
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
                                padding: EdgeInsets.only(right: col < 7 ? 4 : 0),
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
                                    child: Text(emoji, style: const TextStyle(fontSize: 16)),
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
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...List.generate(2, (row) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: row == 0 ? 4 : 0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(8, (col) {
                              final color = TrackColors.manualPalette[row * 8 + col];
                              final isSelected = widget.trackColor == color;
                              return Padding(
                                padding: EdgeInsets.only(right: col < 7 ? 4 : 0),
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
  static const double kMinHeight = 40.0;
  static const double kMaxHeight = 400.0;
  static const double kDefaultHeight = 50.0;

  final double volumeDb;
  final double pan;
  final double peakLevelLeft;
  final double peakLevelRight;
  final Function(double)? onVolumeChanged;
  final Function(double)? onPanChanged;

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
    const standardHeight = 76.0;
    return ((widget.trackHeight - minHeight) / (standardHeight - minHeight)).clamp(0.0, 1.0);
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
    final scale = _scaleFactor;

    // Layout dimensions (same logic as regular tracks)
    const double borderOffset = 4.0;
    final availableHeight = widget.trackHeight - borderOffset;
    final topPadding = _lerp(-1, 6, scale).clamp(0.0, 6.0);
    final bottomPadding = _lerp(2, 6, scale);
    const double horizontalPadding = 6.0;
    final rowHeight = ((availableHeight - topPadding - bottomPadding) / 2).clamp(11.0, 28.0);

    // Pan knob scales with height
    final panSize = _lerp(14, 22, scale);

    // Fixed sizes
    const double fontSize = 12.0;
    const double iconSize = 14.0;
    const double dbFontSize = 10.0;
    const double dbContainerWidth = 56.0;

    return SizedBox(
      width: widget.stripWidth,
      height: widget.trackHeight,
      child: Stack(
        children: [
          // Main content container
          Container(
            width: widget.stripWidth,
            height: widget.trackHeight,
            decoration: BoxDecoration(
              color: _getTintedBackgroundColor(context),
              border: Border(
                left: BorderSide(color: masterColor, width: 4),
                top: BorderSide(color: masterColor, width: 2),
                right: BorderSide(color: masterColor, width: 2),
                bottom: BorderSide(color: masterColor, width: 2),
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
                  Row(
                    children: [
                      // Icon (headphones)
                      Text('🎧', style: TextStyle(fontSize: iconSize)),
                      const SizedBox(width: 6),
                      // "Master" text
                      Expanded(
                        child: Text(
                          'Master',
                          style: TextStyle(
                            color: masterColor,
                            fontSize: fontSize,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Pan knob (aligned right)
                      PanKnob(
                        pan: widget.pan,
                        onChanged: widget.onPanChanged,
                        size: panSize,
                      ),
                    ],
                  ),
                  // Row 2: dB + Volume Slider (same as regular tracks)
                  SizedBox(
                    height: rowHeight,
                    child: Row(
                      children: [
                        // dB value display
                        SizedBox(
                          width: dbContainerWidth,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.colors.darkest,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              widget.volumeDb <= -60.0 ? '-∞ dB' : '${widget.volumeDb.toStringAsFixed(1)} dB',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: dbFontSize,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Volume Slider
                        Expanded(
                          child: CapsuleFader(
                            leftLevel: widget.peakLevelLeft,
                            rightLevel: widget.peakLevelRight,
                            volumeDb: widget.volumeDb,
                            onVolumeChanged: widget.onVolumeChanged,
                            onDoubleTap: () => widget.onVolumeChanged?.call(0.0),
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
            height: 6,
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
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
