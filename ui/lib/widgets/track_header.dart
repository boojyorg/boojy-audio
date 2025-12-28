import 'package:flutter/material.dart';
import '../audio_engine.dart';
import '../theme/theme_extension.dart';

/// Track header widget - displays on left side of timeline for each track
class TrackHeader extends StatelessWidget {
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
  final VoidCallback? onDoubleClick; // Double-click to open editor

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
    this.onDoubleClick,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: onDoubleClick,
      onSecondaryTapDown: (TapDownDetails details) {
        _showContextMenu(context, details.globalPosition);
      },
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
                    trackName,
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
                      onPressed: onSoloToggle,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSoloed
                            ? context.colors.soloActive
                            : context.colors.buttonInactive,
                        foregroundColor: isSoloed
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
                      onPressed: onMuteToggle,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isMuted
                            ? context.colors.muteActive
                            : context.colors.buttonInactive,
                        foregroundColor: isMuted
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
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    // Don't show context menu for master track
    if (trackType.toLowerCase() == 'master') {
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
      ],
    ).then((value) {
      if (value == 'rename' && onRenamePressed != null) {
        onRenamePressed!();
      } else if (value == 'duplicate' && onDuplicatePressed != null) {
        onDuplicatePressed!();
      } else if (value == 'delete' && onDeletePressed != null) {
        onDeletePressed!();
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
              final isLit = peakLevel > threshold;

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
    final lowerName = trackName.toLowerCase();
    final lowerType = trackType.toLowerCase();

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
