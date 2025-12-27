import 'package:flutter/material.dart';
import '../audio_engine.dart';
import 'instrument_browser.dart';
import '../models/instrument_data.dart';
import '../models/vst3_plugin_data.dart';
import '../utils/track_colors.dart';
import 'pan_knob.dart';
import 'capsule_fader.dart';

/// Unified track strip combining track info and mixer controls
/// Displayed on the right side of timeline, aligned with each track row
class TrackMixerStrip extends StatefulWidget {
  final int trackId;
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

  /// Get background color for right box - matches MIDI notes/audio clips
  Color _getTintedBackground(Color? trackColor) {
    if (trackColor == null) return const Color(0xFF2D2D2D);
    return TrackColors.getLighterShade(trackColor, 0.3);
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
                  margin: const EdgeInsets.only(bottom: 4), // Match timeline track spacing
                  decoration: BoxDecoration(
                    // Ableton-style selection: brighter background and thicker border when selected
                    // M10: Highlight when VST3 plugin is being dragged over
                    color: isHovered
                        ? const Color(0xFF00BCD4).withValues(alpha: 0.2)
                        : (widget.isSelected ? const Color(0xFF363636) : const Color(0xFF242424)),
                    border: Border.all(
                      color: isHovered
                          ? const Color(0xFF00BCD4)
                          : (widget.isSelected ? (widget.trackColor ?? const Color(0xFF00BCD4)) : const Color(0xFF363636)),
                      width: isHovered ? 2 : (widget.isSelected ? 3 : 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Left section: Colored track name area (Ableton style)
                      Container(
                        width: 120,
                        color: widget.trackColor ?? const Color(0xFF363636),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: _buildTrackNameSection(),
                      ),

                      // Right section: Controls area (tinted with track color)
                      Expanded(
                        child: Container(
                          color: _getTintedBackground(widget.trackColor),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Column(
                            children: [
                              // Top row: dB → M S R → Pan (new order per spec)
                              Row(
                                children: [
                                  // dB value display (moved to left)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1A1A1A),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      '${widget.volumeDb.toStringAsFixed(1)} dB',
                                      style: const TextStyle(
                                        color: Color(0xFF9E9E9E),
                                        fontSize: 10,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),

                                  const SizedBox(width: 8),

                                  // M, S, R buttons
                                  _buildControlButtons(),

                                  const SizedBox(width: 8),

                                  // Pan knob (right next to MSR, same size as buttons)
                                  PanKnob(
                                    pan: widget.pan,
                                    onChanged: widget.onPanChanged,
                                    size: 22,
                                  ),
                                ],
                              ),

                              const SizedBox(height: 4),

                              // Bottom row: Capsule fader with integrated level meters
                              SizedBox(
                                height: 32,
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
                          final newHeight = (_resizeStartHeight + delta).clamp(50.0, 300.0);
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
      return;
    }

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit, size: 16, color: Color(0xFFE0E0E0)),
              SizedBox(width: 8),
              Text('Rename', style: TextStyle(color: Color(0xFFE0E0E0))),
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
                  color: widget.trackColor ?? const Color(0xFF90A4AE),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: const Color(0xFF505050)),
                ),
              ),
              const SizedBox(width: 8),
              const Text('Change Color', style: TextStyle(color: Color(0xFFE0E0E0))),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(Icons.content_copy, size: 16, color: Color(0xFFE0E0E0)),
              SizedBox(width: 8),
              Text('Duplicate', style: TextStyle(color: Color(0xFFE0E0E0))),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 16, color: Color(0xFFFF5722)),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Color(0xFFFF5722))),
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
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF2A2A2A),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Track Color',
                style: TextStyle(
                  color: Color(0xFFE0E0E0),
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
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF505050),
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
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF505050),
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

  Widget _buildTrackNameSection() {
    final isMidiTrack = widget.trackType.toLowerCase() == 'midi';
    final trackNumber = widget.trackId; // 1-indexed track number

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Track number + emoji + type row (consistent sizing)
        Row(
          children: [
            // Track number
            Text(
              '$trackNumber',
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            // Track emoji
            Text(
              _getTrackEmoji(),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(width: 4),
            // Track type
            Text(
              widget.trackType.toUpperCase(),
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),

        // Track name / Instrument name row - only show if different from type
        if (_getDisplayName().isNotEmpty || _isEditing) ...[
          const SizedBox(height: 2),
          _isEditing
              ? TextField(
                  controller: _nameController,
                  focusNode: _focusNode,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.black),
                    ),
                  ),
                  onSubmitted: (_) => _submitName(),
                )
              : GestureDetector(
                  onDoubleTap: _startEditing,
                  child: Text(
                    _getDisplayName(),
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
        ],

        // Instrument selector for MIDI tracks (only if no instrument assigned)
        if (isMidiTrack && widget.instrumentData == null) ...[
          const SizedBox(height: 4),
          _buildInstrumentSelector(),
        ],
      ],
    );
  }

  /// Get display name - show instrument name if available, otherwise track name
  /// Returns empty string if track name matches type (to avoid "MIDI" appearing twice)
  String _getDisplayName() {
    if (widget.instrumentData != null) {
      return widget.instrumentData!.type;
    }
    // Don't show track name if it matches the type (avoids "MIDI" appearing twice)
    if (widget.trackName.toLowerCase() == widget.trackType.toLowerCase()) {
      return '';
    }
    return widget.trackName;
  }

  Widget _buildInstrumentSelector() {
    final hasInstrument = widget.instrumentData != null;
    return Builder(
      builder: (context) => GestureDetector(
        onTap: widget.onInstrumentSelect != null
            ? () async {
                final selectedInstrument = await showInstrumentBrowser(context);
                if (selectedInstrument != null) {
                  widget.onInstrumentSelect?.call(selectedInstrument.id);
                }
              }
            : null,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: hasInstrument ? 8 : 6,
            vertical: hasInstrument ? 4 : 3,
          ),
          decoration: BoxDecoration(
            color: hasInstrument
                ? const Color(0xFF00BCD4).withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: hasInstrument
                ? Border.all(color: const Color(0xFF00BCD4).withValues(alpha: 0.5))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasInstrument) ...[
                Text(
                  widget.instrumentData!.type,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ] else ...[
                Icon(
                  Icons.add,
                  size: 10,
                  color: Colors.black.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 2),
                Text(
                  'Instrument',
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.4),
                    fontSize: 8,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFxButton() {
    final hasPlugins = widget.vst3PluginCount > 0;
    return GestureDetector(
      onLongPress: hasPlugins ? widget.onEditPluginsPressed : null,
      onTap: widget.onFxButtonPressed,
      child: Tooltip(
        message: hasPlugins
            ? 'Click to browse plugins, long-press to edit'
            : 'Click to add plugins',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: hasPlugins
                ? Colors.black.withValues(alpha: 0.25)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasPlugins) ...[
                Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'FX ×${widget.vst3PluginCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ] else ...[
                Icon(
                  Icons.add,
                  size: 10,
                  color: Colors.black.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 2),
                Text(
                  'FX',
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.4),
                    fontSize: 8,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    // Show arm button only for Audio and MIDI tracks (not master, return, group)
    final canArm = widget.trackType.toLowerCase() == 'audio' || widget.trackType.toLowerCase() == 'midi';

    return Row(
      children: [
        // Mute button
        _buildControlButton('M', widget.isMuted, const Color(0xFFFF5722), widget.onMuteToggle),
        const SizedBox(width: 4),
        // Solo button
        _buildControlButton('S', widget.isSoloed, const Color(0xFFFFC107), widget.onSoloToggle),
        const SizedBox(width: 4),
        // Record arm button (only for audio/midi tracks)
        _buildControlButton(
          'R',
          widget.isArmed,
          const Color(0xFFFF0000), // Bright red when armed
          canArm ? widget.onArmToggle : null,
        ),
      ],
    );
  }

  Widget _buildControlButton(String label, bool isActive, Color activeColor, VoidCallback? onPressed) {
    return SizedBox(
      width: 22,
      height: 22,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isActive ? activeColor : const Color(0xFF3a3a3a), // Dark grey when inactive
          foregroundColor: isActive
              ? (label == 'S' ? Colors.black : Colors.white)
              : const Color(0xFF9E9E9E), // Grey text when inactive
          padding: EdgeInsets.zero,
          minimumSize: const Size(22, 22),
          textStyle: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        child: Text(label),
      ),
    );
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
    return SizedBox(
      width: 380,
      height: widget.trackHeight,
      child: Stack(
        children: [
          // Main content container
          Container(
            width: 380,
            height: widget.trackHeight,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: const BoxDecoration(
              color: Color(0xFF242424),
              border: Border(
                left: BorderSide(color: Color(0xFF4CAF50), width: 4),
                top: BorderSide(color: Color(0xFF4CAF50), width: 2),
                right: BorderSide(color: Color(0xFF4CAF50), width: 2),
                bottom: BorderSide(color: Color(0xFF4CAF50), width: 2),
              ),
            ),
            child: Row(
              children: [
                // Left section: Master label
                Container(
                  width: 120,
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Row(
                        children: [
                          Text('🎚️', style: TextStyle(fontSize: 16)),
                          SizedBox(width: 6),
                          Text(
                            'MASTER',
                            style: TextStyle(
                              color: Color(0xFFE0E0E0),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Limiter indicator chip
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF363636),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF4CAF50)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.security, size: 10, color: Color(0xFF4CAF50)),
                            SizedBox(width: 4),
                            Text(
                              'LIMITER',
                              style: TextStyle(
                                color: Color(0xFF4CAF50),
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Right section: Controls
                Expanded(
                  child: Container(
                    color: const Color(0xFF2D2D2D),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Column(
                      children: [
                        // Top row: dB display + Pan knob (next to each other)
                        Row(
                          children: [
                            // dB value display
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A1A),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                '${widget.volumeDb.toStringAsFixed(1)} dB',
                                style: const TextStyle(
                                  color: Color(0xFF9E9E9E),
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),

                            const SizedBox(width: 8),

                            // Pan knob (right next to dB, same size as track buttons)
                            PanKnob(
                              pan: widget.pan,
                              onChanged: widget.onPanChanged,
                              size: 22,
                            ),
                          ],
                        ),

                        const SizedBox(height: 4),

                        // Bottom row: Capsule fader with integrated level meters
                        SizedBox(
                          height: 32,
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
                    final newHeight = (_resizeStartHeight + delta).clamp(50.0, 300.0);
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
