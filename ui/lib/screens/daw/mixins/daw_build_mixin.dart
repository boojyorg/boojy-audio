import 'package:flutter/material.dart';
import '../../../audio_engine.dart';
import '../../../theme/theme_extension.dart';
import '../../../widgets/dialogs/latency_settings_dialog.dart';
import '../../daw_screen.dart';
import 'daw_screen_state.dart';
import 'daw_playback_mixin.dart';
import 'daw_recording_mixin.dart';
import 'daw_ui_mixin.dart';
import 'daw_track_mixin.dart';
import 'daw_clip_mixin.dart';
import 'daw_vst3_mixin.dart';
import 'daw_library_mixin.dart';
import 'daw_project_mixin.dart';

/// Mixin containing widget builder methods for DAWScreen.
/// Handles building status bar, collapsed mixer bar, and latency display.
mixin DAWBuildMixin on State<DAWScreen>, DAWScreenStateMixin, DAWPlaybackMixin, DAWRecordingMixin, DAWUIMixin, DAWTrackMixin, DAWClipMixin, DAWVst3Mixin, DAWLibraryMixin, DAWProjectMixin {
  // ============================================
  // COLLAPSED MIXER BAR
  // ============================================

  /// Build collapsed mixer bar when mixer is hidden
  Widget buildCollapsedMixerBar() {
    final colors = context.colors;
    return Container(
      width: 30,
      decoration: BoxDecoration(
        color: colors.elevated,
        border: Border(
          left: BorderSide(color: colors.divider),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          // Mixer icon to expand
          Tooltip(
            message: 'Show Mixer',
            child: Material(
              color: colors.standard,
              child: InkWell(
                onTap: toggleMixer,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.tune,
                    color: colors.textPrimary,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // LATENCY DISPLAY
  // ============================================

  /// Build latency display widget
  Widget buildLatencyDisplay() {
    final colors = context.colors;
    if (audioEngine == null || !isAudioGraphInitialized) {
      return Text(
        '--ms',
        style: TextStyle(
          color: colors.textMuted,
          fontSize: 10,
          fontFamily: 'monospace',
        ),
      );
    }

    final latencyInfo = audioEngine!.getLatencyInfo();
    final roundtripMs = latencyInfo['roundtripMs'] ?? 0.0;

    // Color based on latency quality (semantic colors stay consistent)
    Color latencyColor;
    if (roundtripMs < 10) {
      latencyColor = colors.success; // Green - excellent
    } else if (roundtripMs < 20) {
      latencyColor = colors.success.withValues(alpha: 0.7); // Light green - good
    } else if (roundtripMs < 30) {
      latencyColor = colors.warning; // Yellow - acceptable
    } else {
      latencyColor = colors.warning.withValues(alpha: 0.8); // Orange - high
    }

    return GestureDetector(
      onTap: showLatencySettings,
      child: Text(
        '${roundtripMs.toStringAsFixed(1)}ms',
        style: TextStyle(
          color: latencyColor,
          fontSize: 10,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  /// Show latency settings dialog
  void showLatencySettings() {
    if (audioEngine == null) return;

    showLatencySettingsDialog(
      context: context,
      currentPreset: audioEngine!.getBufferSizePreset(),
      presets: AudioEngine.bufferSizePresets,
      onPresetSelected: (preset) {
        audioEngine!.setBufferSize(preset);
        setState(() {}); // Refresh display
      },
    );
  }

  // ============================================
  // STATUS BAR
  // ============================================

  /// Build status bar widget
  Widget buildStatusBar() {
    final colors = context.colors;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.darkest,
        border: Border(
          top: BorderSide(color: colors.standard),
        ),
      ),
      child: Row(
        children: [
          // Engine status with icon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isAudioGraphInitialized
                  ? colors.accent.withValues(alpha: 0.15)
                  : colors.textMuted.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isAudioGraphInitialized ? Icons.check_circle : Icons.hourglass_empty,
                  size: 12,
                  color: isAudioGraphInitialized
                      ? colors.accent
                      : colors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  isAudioGraphInitialized ? 'Ready' : 'Initializing...',
                  style: TextStyle(
                    color: isAudioGraphInitialized
                        ? colors.accent
                        : colors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Duration (if clip selected)
          if (clipDuration != null) ...[
            Icon(Icons.timelapse, size: 11, color: colors.textMuted),
            const SizedBox(width: 4),
            Text(
              '${clipDuration!.toStringAsFixed(2)}s',
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 16),
          ],
          // Sample rate with icon
          Icon(Icons.graphic_eq, size: 11, color: colors.textMuted),
          const SizedBox(width: 4),
          Text(
            '48kHz',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 16),
          // Latency display with icon
          Icon(Icons.speed, size: 11, color: colors.textMuted),
          const SizedBox(width: 4),
          buildLatencyDisplay(),
          const SizedBox(width: 16),
          // CPU with icon
          Icon(Icons.memory, size: 11, color: colors.textMuted),
          const SizedBox(width: 4),
          Text(
            '0%',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
