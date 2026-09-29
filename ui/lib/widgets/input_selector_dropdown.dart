import 'dart:async';
import 'package:flutter/material.dart';
import '../audio_engine.dart';
import '../models/audio_input_status.dart';
import '../theme/boojy_icons.dart';
import '../theme/theme_extension.dart';
import '../theme/tokens.dart';

/// Shows a live input selector dropdown with animated level meters per channel.
/// Replaces static PopupMenu with a custom overlay that polls input levels.
Future<void> showInputSelectorDropdown({
  required BuildContext context,
  required Offset position,
  required AudioInputStatus status,
  required int currentChannel,
  required AudioEngine? audioEngine,
  required void Function(int channel) onSelected,
}) async {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) => _InputSelectorOverlay(
      position: position,
      status: status,
      currentChannel: currentChannel,
      audioEngine: audioEngine,
      onSelected: (channel) {
        entry.remove();
        onSelected(channel);
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
  final AudioInputStatus status;
  final int currentChannel;
  final AudioEngine? audioEngine;
  final void Function(int channel) onSelected;
  final VoidCallback onDismiss;

  const _InputSelectorOverlay({
    required this.position,
    required this.status,
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

  // The engine meters and records the first two channels (L/R) only.
  int get _channelCount => widget.status.channelCount.clamp(0, 2);

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
    for (int ch = 0; ch < _channelCount; ch++) {
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
    final status = widget.status;
    final items = <Widget>[];

    Widget note(String text) => Container(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: TextStyle(
          color: colors.textMuted,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      ),
    );

    if (status.isOff) {
      return [note('Audio input is off. Turn it on in Settings → Audio.')];
    }
    if (status.deviceName.isEmpty) return [note('No audio input connected.')];

    // Device header: the one input Boojy records from (chosen in Settings)
    items.add(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          status.deviceName,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: BT.fontLabel,
            fontWeight: BT.weightSemiBold,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );

    for (int ch = 0; ch < _channelCount; ch++) {
      items.add(
        _buildChannelItem(
          channel: ch,
          isSelected: widget.currentChannel == ch,
          level: _channelLevels[ch] ?? 0.0,
          onTap: () => widget.onSelected(ch),
        ),
      );
    }
    return items;
  }

  Widget _buildChannelItem({
    required int channel,
    required bool isSelected,
    required double level,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    // Numbered like the sockets on an interface.
    final channelLabel = 'Input ${channel + 1}';

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(left: 24, right: 12, top: 6, bottom: 6),
        child: Row(
          children: [
            Icon(
              isSelected ? BI.radioChecked : BI.circle,
              size: 14,
              color: isSelected ? colors.accent : colors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              channelLabel,
              style: TextStyle(
                color: isSelected ? colors.accent : colors.textPrimary,
                fontSize: 12,
                fontWeight: isSelected ? BT.weightSemiBold : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 8),
            // Live level meter
            Expanded(child: _LiveMeterBar(level: level)),
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
                        context.colors.success, // Green
                        if (level > 0.8)
                          context
                              .colors
                              .warning // Yellow at high levels
                        else
                          context.colors.success,
                        if (level > 0.9)
                          context.colors.error, // Red at clipping
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
