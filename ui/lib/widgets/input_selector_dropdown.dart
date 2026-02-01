import 'dart:async';
import 'package:flutter/material.dart';
import '../audio_engine.dart';
import '../theme/theme_extension.dart';

/// Shows a live input selector dropdown with animated level meters per channel.
/// Replaces static PopupMenu with a custom overlay that polls input levels.
Future<void> showInputSelectorDropdown({
  required BuildContext context,
  required Offset position,
  required List<Map<String, dynamic>> inputDevices,
  required int currentDeviceIndex,
  required int currentChannel,
  required AudioEngine? audioEngine,
  required Function(int deviceIndex, int channel) onSelected,
}) async {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) => _InputSelectorOverlay(
      position: position,
      inputDevices: inputDevices,
      currentDeviceIndex: currentDeviceIndex,
      currentChannel: currentChannel,
      audioEngine: audioEngine,
      onSelected: (deviceIndex, channel) {
        entry.remove();
        onSelected(deviceIndex, channel);
      },
      onDismiss: () {
        entry.remove();
      },
    ),
  );

  overlay.insert(entry);
}

class _InputSelectorOverlay extends StatefulWidget {
  final Offset position;
  final List<Map<String, dynamic>> inputDevices;
  final int currentDeviceIndex;
  final int currentChannel;
  final AudioEngine? audioEngine;
  final Function(int deviceIndex, int channel) onSelected;
  final VoidCallback onDismiss;

  const _InputSelectorOverlay({
    required this.position,
    required this.inputDevices,
    required this.currentDeviceIndex,
    required this.currentChannel,
    required this.audioEngine,
    required this.onSelected,
    required this.onDismiss,
  });

  @override
  State<_InputSelectorOverlay> createState() => _InputSelectorOverlayState();
}

class _InputSelectorOverlayState extends State<_InputSelectorOverlay> {
  Timer? _levelTimer;
  // channel index -> peak level (0.0 to 1.0)
  Map<int, double> _channelLevels = {};

  @override
  void initState() {
    super.initState();
    // Poll input levels at ~50ms for smooth meters
    _levelTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _pollLevels();
    });
    _pollLevels(); // Initial poll
  }

  @override
  void dispose() {
    _levelTimer?.cancel();
    super.dispose();
  }

  void _pollLevels() {
    if (widget.audioEngine == null || !mounted) return;

    final newLevels = <int, double>{};
    // Poll levels for channels 0 and 1 (stereo)
    for (int ch = 0; ch < 2; ch++) {
      try {
        final raw = widget.audioEngine!.getInputChannelLevel(ch);
        newLevels[ch] = raw.clamp(0.0, 1.0);
      } catch (_) {
        newLevels[ch] = 0.0;
      }
    }

    if (mounted) {
      setState(() {
        _channelLevels = newLevels;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Dismiss backdrop
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        // Dropdown card
        Positioned(
          left: widget.position.dx,
          top: widget.position.dy,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(6),
            color: context.colors.elevated,
            child: Container(
              width: 220,
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.colors.hover, width: 0.5),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildMenuItems(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildMenuItems(BuildContext context) {
    final colors = context.colors;
    final items = <Widget>[];

    // "No Input" option
    final noInputSelected = widget.currentDeviceIndex < 0;
    items.add(_buildMenuItem(
      icon: Icons.block,
      label: 'No Input',
      isSelected: noInputSelected,
      onTap: () => widget.onSelected(-1, 0),
    ));

    items.add(Divider(height: 1, color: colors.hover));

    // Devices and channels
    for (int deviceIdx = 0; deviceIdx < widget.inputDevices.length; deviceIdx++) {
      final device = widget.inputDevices[deviceIdx];
      final deviceName = device['name'] as String? ?? 'Input Device $deviceIdx';
      final isDefault = device['isDefault'] as bool? ?? false;

      // Device header
      items.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          '${isDefault ? "★ " : ""}$deviceName',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ));

      // Channel options with live meters
      const channelCount = 2;
      for (int ch = 0; ch < channelCount; ch++) {
        final isSelected = widget.currentDeviceIndex == deviceIdx && widget.currentChannel == ch;
        final level = _channelLevels[ch] ?? 0.0;

        items.add(_buildChannelItem(
          channel: ch,
          isSelected: isSelected,
          level: level,
          onTap: () => widget.onSelected(deviceIdx, ch),
        ));
      }
    }

    // No devices message
    if (widget.inputDevices.isEmpty) {
      items.add(Container(
        padding: const EdgeInsets.all(12),
        child: Text(
          'No audio input devices found',
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      ));
    }

    return items;
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? colors.accent : colors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? colors.accent : colors.textPrimary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelItem({
    required int channel,
    required bool isSelected,
    required double level,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    final channelLabel = 'Input ${channel + 1} (${channel == 0 ? "L" : "R"})';

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(left: 24, right: 12, top: 6, bottom: 6),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 14,
              color: isSelected ? colors.accent : colors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              channelLabel,
              style: TextStyle(
                color: isSelected ? colors.accent : colors.textPrimary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 8),
            // Live level meter
            Expanded(
              child: _LiveMeterBar(level: level),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animated level meter bar for input channel
class _LiveMeterBar extends StatelessWidget {
  final double level;

  const _LiveMeterBar({required this.level});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Stack(
          children: [
            // Background
            Container(
              decoration: BoxDecoration(
                color: context.colors.darkest,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            // Level fill
            if (level > 0.01)
              FractionallySizedBox(
                widthFactor: level.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF22c55e), // Green
                        if (level > 0.8)
                          const Color(0xFFeab308) // Yellow at high levels
                        else
                          const Color(0xFF22c55e),
                        if (level > 0.9) const Color(0xFFef4444), // Red at clipping
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
