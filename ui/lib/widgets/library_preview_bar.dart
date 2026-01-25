import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/library_preview_service.dart';
import '../theme/theme_extension.dart';
import 'library_preview_waveform.dart';

/// Preview bar widget displayed at the bottom of the library panel.
/// Shows audition toggle, play/stop button, and waveform visualization.
class LibraryPreviewBar extends StatelessWidget {
  const LibraryPreviewBar({super.key});

  @override
  Widget build(BuildContext context) {
    // Safely check if the preview service is available
    LibraryPreviewService? previewService;
    try {
      previewService = Provider.of<LibraryPreviewService>(context);
    } catch (e) {
      // Provider not available, don't show preview bar
      return const SizedBox.shrink();
    }

    // Only show when a file is loaded
    if (!previewService.hasLoadedFile) {
      return const SizedBox.shrink();
    }

    // Capture non-null reference for closures
    final service = previewService;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: context.colors.elevated,
        border: Border(
          top: BorderSide(color: context.colors.divider),
        ),
      ),
      child: Row(
        children: [
          // Audition toggle button
          _AuditionToggleButton(
            isEnabled: previewService.auditionEnabled,
            onTap: previewService.toggleAudition,
          ),
          // Play/Stop button
          _PlayStopButton(
            isPlaying: service.isPlaying,
            onTap: () {
              if (service.isPlaying) {
                service.stop();
              } else {
                service.play();
              }
            },
          ),
          // Waveform display
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: LibraryPreviewWaveform(
                peaks: previewService.waveformPeaks,
                position: previewService.position,
                duration: previewService.duration,
                isAuditionEnabled: previewService.auditionEnabled,
                onSeek: previewService.seek,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Audition toggle button (speaker icon)
class _AuditionToggleButton extends StatefulWidget {
  final bool isEnabled;
  final VoidCallback onTap;

  const _AuditionToggleButton({
    required this.isEnabled,
    required this.onTap,
  });

  @override
  State<_AuditionToggleButton> createState() => _AuditionToggleButtonState();
}

class _AuditionToggleButtonState extends State<_AuditionToggleButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isActive = widget.isEnabled;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: 'Preview sounds on click',
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 48,
            color: _isHovered ? colors.hover : Colors.transparent,
            child: Center(
              child: Icon(
                isActive ? Icons.volume_up : Icons.volume_off,
                size: 18,
                color: isActive ? colors.accent : colors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Play/Stop button
class _PlayStopButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onTap;

  const _PlayStopButton({
    required this.isPlaying,
    required this.onTap,
  });

  @override
  State<_PlayStopButton> createState() => _PlayStopButtonState();
}

class _PlayStopButtonState extends State<_PlayStopButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: widget.isPlaying ? 'Stop preview' : 'Play preview',
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 48,
            color: _isHovered ? colors.hover : Colors.transparent,
            child: Center(
              child: Icon(
                widget.isPlaying ? Icons.stop : Icons.play_arrow,
                size: 20,
                color: _isHovered ? colors.accent : colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
