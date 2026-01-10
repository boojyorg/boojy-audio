import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../audio_engine.dart';
import '../models/instrument_data.dart';
import '../models/vst3_plugin_data.dart';
import '../theme/theme_extension.dart';
import '../theme/theme_provider.dart';
import '../utils/track_colors.dart';
import 'pan_knob.dart';
import 'capsule_fader.dart';

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
  final VoidCallback? onArmToggle; // Toggle recording arm
  final VoidCallback? onTap; // Unified track selection callback
  final VoidCallback? onDoubleTap; // Double-click to open editor
  final VoidCallback? onDeletePressed;
  final VoidCallback? onDuplicatePressed;
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
  final VoidCallback? onEditPluginsPressed; // New: Edit active plugins

  // Track height resizing
  final double trackHeight;
  final Function(double)? onHeightChanged;

  // Track color change callback
  final Function(Color)? onColorChanged;

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
    this.onTap,
    this.onDoubleTap,
    this.onDeletePressed,
    this.onDuplicatePressed,
    this.onNameChanged,
    this.isSelected = false,
    this.isArmed = false,
    this.instrumentData,
    this.onInstrumentSelect,
    this.vst3PluginCount = 0,
    this.onFxButtonPressed,
    this.onVst3PluginDropped,
    this.onEditPluginsPressed,
    this.trackHeight = 100.0,
    this.onHeightChanged,
    this.onColorChanged,
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

  /// Calculate scale factor based on track height (0.0 at 40px, 1.0 at 72px+)
  /// Accounts for bottom margin (2px) and potential border (2px)
  double get _scaleFactor {
    const minHeight = 40.0;
    const standardHeight = 76.0; // Adjusted for comfortable 2-row layout
    return ((widget.trackHeight - minHeight) / (standardHeight - minHeight)).clamp(0.0, 1.0);
  }

  /// Lerp helper for scaling values
  double _lerp(double min, double max, double t) => min + (max - min) * t;

  /// Build 2-row layout that scales with track height
  /// Row 1: Icon + Number + Name + MSR + Pan
  /// Row 2: dB + Volume Slider
  Widget _buildStandardLayout(BuildContext context, bool isHovered) {
    final scale = _scaleFactor;

    // Available height for content (subtract margin and potential border)
    final availableHeight = widget.trackHeight - 2; // 2px bottom margin

    // Calculate row height to fit exactly in available space
    // Layout: padding + row1 + spacing + row2 + padding
    // At min (40px): available = 38px, need padding(2*2) + rows(2*14) + spacing(2) = 34px
    // At standard (76px): available = 74px, need padding(2*6) + rows(2*28) + spacing(4) = 72px
    final padding = _lerp(2, 6, scale);
    final rowSpacing = _lerp(2, 4, scale);
    // Calculate row height to fit: (available - 2*padding - spacing) / 2
    final rowHeight = ((availableHeight - 2 * padding - rowSpacing) / 2).clamp(12.0, 28.0);

    final buttonSize = _lerp(14, 22, scale);
    final panSize = _lerp(14, 22, scale);
    final buttonSpacing = _lerp(2, 4, scale);
    final fontSize = _lerp(9, 12, scale);
    final iconSize = _lerp(10, 14, scale);
    final dbFontSize = _lerp(8, 10, scale);

    return Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Icon + Number + Name + MSR + Pan
          // Name area expands to fill available space, truncates with "..." as needed
          SizedBox(
            height: rowHeight,
            child: Row(
              children: [
                // Icon + Number + Name (expands to fill remaining space)
                Expanded(child: _buildTrackInfoRow(fontSize: fontSize, iconSize: iconSize)),
                SizedBox(width: _lerp(3, 5, scale)),
                // M, S, R buttons
                _buildControlButtons(buttonSize: buttonSize, spacing: buttonSpacing, fontSize: _lerp(8, 10, scale)),
                SizedBox(width: _lerp(4, 6, scale)),
                // Pan knob
                PanKnob(
                  pan: widget.pan,
                  onChanged: widget.onPanChanged,
                  size: panSize,
                ),
              ],
            ),
          ),
          SizedBox(height: rowSpacing),
          // Row 2: dB + Volume Slider
          SizedBox(
            height: rowHeight,
            child: Row(
              children: [
                // dB value display
                Container(
                  padding: EdgeInsets.symmetric(horizontal: _lerp(4, 6, scale), vertical: _lerp(1, 2, scale)),
                  decoration: BoxDecoration(
                    color: context.colors.darkest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '${widget.volumeDb.toStringAsFixed(1)} dB',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: dbFontSize,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                SizedBox(width: _lerp(4, 8, scale)),
                // Volume Slider (takes remaining space)
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
    );
  }

  /// Build track info row (Icon + Number + Name)
  Widget _buildTrackInfoRow({double fontSize = 12, double iconSize = 14}) {
    final textColor = _getTextColor();
    final trackColor = widget.trackColor ?? context.colors.textPrimary;
    final scale = _scaleFactor;

    return Row(
      children: [
        // Icon
        Text(_getTrackEmoji(), style: TextStyle(fontSize: iconSize)),
        SizedBox(width: _lerp(4, 6, scale)),
        // Number (sequential display index, not internal ID)
        Text(
          '${widget.displayIndex}',
          style: TextStyle(
            color: textColor,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(width: _lerp(4, 8, scale)),
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
                    contentPadding: EdgeInsets.symmetric(horizontal: _lerp(2, 4, scale), vertical: _lerp(1, 2, scale)),
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


  @override
  Widget build(BuildContext context) {
    return DragTarget<Vst3Plugin>(
      onAcceptWithDetails: (details) {
        widget.onVst3PluginDropped?.call(details.data);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;

        return GestureDetector(
          onTap: widget.onTap, // Track selection on left-click
          onDoubleTap: widget.onDoubleTap, // Double-click to open editor
          onSecondaryTapDown: (TapDownDetails details) {
            _showContextMenu(context, details.globalPosition);
          },
          child: SizedBox(
            width: 380,
            height: widget.trackHeight,
            child: Stack(
              children: [
                // Main content container
                Container(
                  width: 380,
                  height: widget.trackHeight,
                  margin: const EdgeInsets.only(bottom: 2), // Match timeline track spacing
                  decoration: BoxDecoration(
                    // Full track colour background (same as color picker)
                    color: isHovered
                        ? context.colors.accent.withValues(alpha: 0.5)
                        : (widget.trackColor ?? context.colors.standard),
                    // Selection: white border when selected, no border when not
                    border: isHovered
                        ? Border.all(color: context.colors.accent, width: 2)
                        : (widget.isSelected
                            ? Border.all(color: Colors.white, width: 2)
                            : null),
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
                        _resizeStartHeight = widget.trackHeight;
                      },
                      onVerticalDragUpdate: (details) {
                        if (_isResizing) {
                          final delta = details.globalPosition.dy - _resizeStartY;
                          final newHeight = (_resizeStartHeight + delta).clamp(
                            TrackMixerStrip.kMinHeight,
                            TrackMixerStrip.kMaxHeight,
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
          ),
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

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
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
      ],
    ).then((value) {
      if (!mounted) return;
      if (value == 'rename') {
        _startEditing();
      } else if (value == 'color') {
        // Use this.context since we've verified mounted above
        _showColorPicker(this.context, position);
      } else if (value == 'duplicate' && widget.onDuplicatePressed != null) {
        widget.onDuplicatePressed!();
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
        _buildControlButton(
          'R',
          widget.isArmed,
          context.colors.recordActive,
          canArm ? widget.onArmToggle : null,
          buttonSize,
          fontSize,
        ),
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

  /// Get text colour - much darker shade of track colour for readability
  Color _getTextColor() {
    final trackColor = widget.trackColor;
    if (trackColor == null) return context.colors.textPrimary;

    // Darken the track colour significantly for readable text on coloured background
    final hsl = HSLColor.fromColor(trackColor);
    // Use very low lightness for dark text on coloured background
    return hsl.withLightness((hsl.lightness * 0.25).clamp(0.05, 0.25)).toColor();
  }

  String _getTrackEmoji() {
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
}

/// Master track strip - special styling for master track
class MasterTrackMixerStrip extends StatefulWidget {
  final double volumeDb;
  final double pan;
  final double peakLevelLeft;
  final double peakLevelRight;
  final Function(double)? onVolumeChanged;
  final Function(double)? onPanChanged;

  // Track height resizing (top edge for master)
  final double trackHeight;
  final Function(double)? onHeightChanged;

  const MasterTrackMixerStrip({
    super.key,
    required this.volumeDb,
    required this.pan,
    this.peakLevelLeft = 0.0,
    this.peakLevelRight = 0.0,
    this.onVolumeChanged,
    this.onPanChanged,
    this.trackHeight = 60.0,
    this.onHeightChanged,
  });

  @override
  State<MasterTrackMixerStrip> createState() => _MasterTrackMixerStripState();
}

class _MasterTrackMixerStripState extends State<MasterTrackMixerStrip> {
  // Resize state
  bool _isResizing = false;
  double _resizeStartY = 0.0;
  double _resizeStartHeight = 0.0;

  @override
  Widget build(BuildContext context) {
    final masterColor = context.colors.accent;

    return SizedBox(
      width: 380,
      height: widget.trackHeight,
      child: Stack(
        children: [
          // Main content container
          Container(
            width: 380,
            height: widget.trackHeight,
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: context.colors.standard,
              border: Border(
                left: BorderSide(color: masterColor, width: 4),
                top: BorderSide(color: masterColor, width: 2),
                right: BorderSide(color: masterColor, width: 2),
                bottom: BorderSide(color: masterColor, width: 2),
              ),
            ),
            child: Row(
              children: [
                // Left section: Master label
                Container(
                  width: 80,
                  color: masterColor.withValues(alpha: 0.2),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(
                    child: Text(
                      'MASTER',
                      style: TextStyle(
                        color: masterColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),

                // Right section: Controls - single row layout
                Expanded(
                  child: Container(
                    color: context.colors.elevated,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        // dB value display
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.colors.darkest,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '${widget.volumeDb.toStringAsFixed(1)} dB',
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Pan knob
                        PanKnob(
                          pan: widget.pan,
                          onChanged: widget.onPanChanged,
                          size: 22,
                        ),

                        const SizedBox(width: 8),

                        // Capsule fader - takes remaining space
                        Expanded(
                          child: CapsuleFader(
                            leftLevel: widget.peakLevelLeft,
                            rightLevel: widget.peakLevelRight,
                            volumeDb: widget.volumeDb,
                            onVolumeChanged: widget.onVolumeChanged,
                            onDoubleTap: () {
                              // Reset to 0 dB on double-tap
                              widget.onVolumeChanged?.call(0.0);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
                    final newHeight = (_resizeStartHeight + delta).clamp(55.0, 300.0);
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
