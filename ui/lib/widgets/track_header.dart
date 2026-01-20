import 'package:flutter/material.dart';
import '../audio_engine.dart';
import '../theme/theme_extension.dart';

/// Track header widget - displays on left side of timeline for each track
/// Supports drag navigation:
/// - Drag up/down = scroll tracks vertically
/// - Drag left/right = zoom track height
class TrackHeader extends StatefulWidget {
  final int trackId;
  final String trackName;
  final String trackType;
  final bool isMuted;
  final bool isSoloed;
  final double peakLevel; // 0.0 to 1.0
  final AudioEngine? audioEngine;
  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;
  final VoidCallback? onDuplicatePressed;
  final VoidCallback? onDeletePressed;
  final VoidCallback? onRenamePressed;
  final VoidCallback? onConvertToSampler; // Convert Audio track to Sampler
  final VoidCallback? onDoubleClick; // Double-click to open editor

  // Drag navigation callbacks
  final void Function(double delta)? onVerticalScroll;
  final void Function(double factor)? onTrackHeightZoom;

  const TrackHeader({
    super.key,
    required this.trackId,
    required this.trackName,
    required this.trackType,
    required this.isMuted,
    required this.isSoloed,
    this.peakLevel = 0.0,
    this.audioEngine,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onDuplicatePressed,
    this.onDeletePressed,
    this.onRenamePressed,
    this.onConvertToSampler,
    this.onDoubleClick,
    this.onVerticalScroll,
    this.onTrackHeightZoom,
  });

  @override
  State<TrackHeader> createState() => _TrackHeaderState();
}

class _TrackHeaderState extends State<TrackHeader> {
  // Drag state
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: widget.onDoubleClick,
      onSecondaryTapDown: (TapDownDetails details) {
        _showContextMenu(context, details.globalPosition);
      },
      onPanStart: _handlePanStart,
      onPanUpdate: _handlePanUpdate,
      onPanEnd: _handlePanEnd,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: Container(
          width: 120,
          height: 100, // Height of track row in timeline
          decoration: BoxDecoration(
            color: context.colors.textMuted,
            border: Border(
              right: BorderSide(color: context.colors.buttonInactive),
              bottom: BorderSide(color: context.colors.buttonInactive),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Track name and icon
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Text(
                      _getTrackEmoji(),
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.trackName,
                        style: TextStyle(
                          color: context.colors.darkest,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // Mute/Solo buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  children: [
                    // Solo button
                    Expanded(
                      child: SizedBox(
                        height: 24,
                        child: ElevatedButton(
                          onPressed: widget.onSoloToggle,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.isSoloed
                                ? context.colors.soloActive
                                : context.colors.buttonInactive,
                            foregroundColor: widget.isSoloed
                                ? Colors.black
                                : context.colors.textMuted,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 24),
                            textStyle: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          child: const Text('S'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),

                    // Mute button
                    Expanded(
                      child: SizedBox(
                        height: 24,
                        child: ElevatedButton(
                          onPressed: widget.onMuteToggle,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.isMuted
                                ? context.colors.muteActive
                                : context.colors.buttonInactive,
                            foregroundColor: widget.isMuted
                                ? Colors.white
                                : context.colors.textMuted,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 24),
                            textStyle: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          child: const Text('M'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Level meter
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: _buildLevelMeter(context),
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================
  // PAN HANDLING (Drag for scroll/zoom)
  // ============================================

  void _handlePanStart(DragStartDetails details) {
    _isDragging = true;
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    final deltaX = details.delta.dx;
    final deltaY = details.delta.dy;

    // Vertical drag = scroll tracks (drag up = scroll up)
    if (deltaY.abs() > 0.5) {
      widget.onVerticalScroll?.call(deltaY);
    }

    // Horizontal drag = zoom track height
    // Drag right = zoom in (tracks get taller)
    // Drag left = zoom out (tracks get shorter)
    if (deltaX.abs() > 0.5) {
      // Sensitivity: 100px drag = ~1.5x zoom change
      final factor = 1.0 + (deltaX / 200.0);
      widget.onTrackHeightZoom?.call(factor);
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    _isDragging = false;
  }

  void _showContextMenu(BuildContext context, Offset position) {
    // Don't show context menu for master track
    if (widget.trackType.toLowerCase() == 'master') {
      return;
    }

    final isAudioTrack = widget.trackType.toLowerCase() == 'audio';

    final menuItems = <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: 'rename',
        child: Row(
          children: [
            Icon(Icons.edit, size: 16, color: context.colors.darkest),
            const SizedBox(width: 8),
            Text('Rename', style: TextStyle(color: context.colors.darkest)),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'duplicate',
        child: Row(
          children: [
            Icon(Icons.content_copy, size: 16, color: context.colors.darkest),
            const SizedBox(width: 8),
            Text('Duplicate', style: TextStyle(color: context.colors.darkest)),
          ],
        ),
      ),
      // Show "Convert to Sampler" only for Audio tracks
      if (isAudioTrack && widget.onConvertToSampler != null)
        PopupMenuItem<String>(
          value: 'convert_to_sampler',
          child: Row(
            children: [
              Icon(Icons.music_note, size: 16, color: context.colors.darkest),
              const SizedBox(width: 8),
              Text('Convert to Sampler', style: TextStyle(color: context.colors.darkest)),
            ],
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'delete',
        child: Row(
          children: [
            Icon(Icons.delete, size: 16, color: context.colors.error),
            const SizedBox(width: 8),
            Text('Delete', style: TextStyle(color: context.colors.error)),
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
      if (value == 'rename' && widget.onRenamePressed != null) {
        widget.onRenamePressed!();
      } else if (value == 'duplicate' && widget.onDuplicatePressed != null) {
        widget.onDuplicatePressed!();
      } else if (value == 'convert_to_sampler' && widget.onConvertToSampler != null) {
        widget.onConvertToSampler!();
      } else if (value == 'delete' && widget.onDeletePressed != null) {
        widget.onDeletePressed!();
      }
    });
  }

  Widget _buildLevelMeter(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Meter label
        Text(
          'LEVEL',
          style: TextStyle(
            color: context.colors.hover,
            fontSize: 8,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),

        // Meter bars
        Expanded(
          child: Row(
            children: List.generate(10, (index) {
              final threshold = index / 10.0;
              final isLit = widget.peakLevel > threshold;

              // Color gradient: green → yellow → red
              Color barColor;
              if (index < 6) {
                barColor = context.colors.meterGreen;
              } else if (index < 8) {
                barColor = context.colors.meterYellow;
              } else {
                barColor = context.colors.meterRed;
              }

              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: isLit ? barColor : context.colors.textMuted,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: context.colors.buttonInactive,
                      width: 0.5,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  String _getTrackEmoji() {
    // Map track type or name to emoji
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

/// Master track header - special styling for master track
class MasterTrackHeader extends StatelessWidget {
  final double peakLevel;

  const MasterTrackHeader({
    super.key,
    this.peakLevel = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 80, // Slightly shorter than regular tracks
      decoration: BoxDecoration(
        color: context.colors.hover,
        border: Border.all(color: context.colors.success, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Master label
          const Text(
            '🎚️',
            style: TextStyle(fontSize: 20),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'MASTER',
            style: TextStyle(
              color: context.colors.success,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // Level meter (simplified)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: SizedBox(
              height: 20,
              child: Row(
                children: List.generate(10, (index) {
                  final threshold = index / 10.0;
                  final isLit = peakLevel > threshold;

                  Color barColor;
                  if (index < 6) {
                    barColor = context.colors.meterGreen;
                  } else if (index < 8) {
                    barColor = context.colors.meterYellow;
                  } else {
                    barColor = context.colors.meterRed;
                  }

                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: isLit ? barColor : context.colors.textMuted,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: context.colors.buttonInactive,
                          width: 0.5,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
