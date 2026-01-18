import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../audio_engine.dart';
import '../models/instrument_data.dart';
import '../models/vst3_plugin_data.dart';
import '../theme/theme_extension.dart';
import '../theme/theme_provider.dart';
import '../utils/track_colors.dart';
import 'instrument_browser.dart';
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
  final VoidCallback? onArmToggle; // Toggle recording arm (exclusive)
  final VoidCallback? onArmShiftClick; // Shift+click for multi-arm mode
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
  final Function(Vst3Plugin)? onVst3InstrumentDropped; // VST3 instrument swap
  final Function(Instrument)? onInstrumentDropped; // Built-in instrument swap
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
    this.onArmShiftClick,
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
    this.onVst3InstrumentDropped,
    this.onInstrumentDropped,
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

  /// Calculate scale factor based on track height (0.0 at 40px, 1.0 at 76px+)
  double get _scaleFactor {
    const minHeight = 40.0;
    const standardHeight = 76.0;
    return ((widget.trackHeight - minHeight) / (standardHeight - minHeight)).clamp(0.0, 1.0);
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
    final availableHeight = widget.trackHeight - borderOffset;

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
          // Row 1: Icon + Number + Name + MSR + Pan
          // No fixed height - let it size to content and sit at top
          Row(
            children: [
              // Icon + Number + Name (fixed font sizes, expands to fill space)
              Expanded(child: _buildTrackInfoRow(fontSize: fontSize, iconSize: iconSize)),
              const SizedBox(width: 5),
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
          // Row 2: dB + Volume Slider
          SizedBox(
            height: rowHeight,
            child: Row(
              children: [
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
                // Volume Slider (height scales, X position fixed)
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
  /// All elements use fixed sizes for consistent alignment across all track heights
  Widget _buildTrackInfoRow({double fontSize = 12, double iconSize = 14}) {
    final textColor = _getTextColor();
    final trackColor = widget.trackColor ?? context.colors.textPrimary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Icon (fixed size)
        Text(_getTrackEmoji(), style: TextStyle(fontSize: iconSize)),
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


  @override
  Widget build(BuildContext context) {
    // Note: trackType from engine is 'MIDI', 'Audio', 'Master' (uppercase)
    final isMidiTrack = widget.trackType.toLowerCase() == 'midi';

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
          onTap: widget.onTap,
          onDoubleTap: widget.onDoubleTap,
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
      width: 380,
      height: widget.trackHeight,
      child: Stack(
        children: [
          // Main content container
          Container(
            width: 380,
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
