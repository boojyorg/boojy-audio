import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';

/// Status pill showing engine state with color-coded background.
///
/// States:
///   Ready (green) — engine initialized
///   Initializing (gray) — engine starting up
///
/// Hover tooltip shows engine stats (sample rate, latency, output device).
class StatusPill extends StatelessWidget {
  final bool isReady;
  final int? sampleRate;
  final double? latencyMs;
  final String? audioOutputDevice;

  const StatusPill({
    super.key,
    required this.isReady,
    this.sampleRate,
    this.latencyMs,
    this.audioOutputDevice,
  });

  String _buildTooltip() {
    if (!isReady) return 'Engine initializing...';

    final parts = <String>['Engine ready'];
    if (sampleRate != null) {
      final rateKhz = sampleRate! / 1000.0;
      parts.add('Sample Rate  ${rateKhz.toStringAsFixed(1)} kHz');
    }
    if (latencyMs != null) {
      parts.add('Latency      ${latencyMs!.toStringAsFixed(1)} ms');
    }
    if (audioOutputDevice != null && audioOutputDevice!.isNotEmpty) {
      parts.add('Audio Out    $audioOutputDevice');
    }
    return parts.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final Color bgColor;
    final Color iconColor;
    final IconData icon;
    final String label;

    if (isReady) {
      bgColor = colors.success.withValues(alpha: 0.2);
      iconColor = colors.success;
      icon = Icons.check;
      label = 'Ready';
    } else {
      bgColor = colors.surface;
      iconColor = colors.textMuted;
      icon = Icons.hourglass_empty;
      label = 'Init...';
    }

    return Tooltip(
      message: _buildTooltip(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colors.divider, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: iconColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isReady ? colors.textPrimary : colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
