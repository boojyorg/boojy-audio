import 'package:flutter/material.dart';
import '../theme/boojy_icons.dart';
import '../theme/theme_extension.dart';
import '../theme/tokens.dart';
import '../services/midi_capture_buffer.dart';
import '../models/midi_event.dart';

/// Dialog for capturing MIDI from the circular buffer
///
/// Allows user to select duration and preview captured events
class CaptureMidiDialog extends StatefulWidget {
  final MidiCaptureBuffer captureBuffer;
  final Function(List<MidiEvent>)? onCapture;

  const CaptureMidiDialog({
    super.key,
    required this.captureBuffer,
    this.onCapture,
  });

  static Future<List<MidiEvent>?> show(
    BuildContext context,
    MidiCaptureBuffer captureBuffer,
  ) {
    return showDialog<List<MidiEvent>>(
      context: context,
      builder: (context) => CaptureMidiDialog(
        captureBuffer: captureBuffer,
        onCapture: (events) => Navigator.of(context).pop(events),
      ),
    );
  }

  @override
  State<CaptureMidiDialog> createState() => _CaptureMidiDialogState();
}

class _CaptureMidiDialogState extends State<CaptureMidiDialog> {
  int _selectedDuration = 30; // seconds
  final List<int> _durationOptions = [5, 10, 15, 20, 30];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final preview = widget.captureBuffer.getPreview(_selectedDuration);
    final hasEvents = widget.captureBuffer.hasEvents;

    return Dialog(
      backgroundColor: colors.elevated,
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(BI.history, color: colors.accent, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Capture MIDI',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: BT.fontHeading,
                        fontWeight: BT.weightSemiBold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(BI.close, color: colors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Description
            Text(
              'Capture MIDI events from the recent past and create a clip on the selected track.',
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),

            // Duration selector
            Row(
              children: [
                Text(
                  'Capture last',
                  style: TextStyle(color: colors.textPrimary, fontSize: 14),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colors.divider),
                  ),
                  child: DropdownButton<int>(
                    value: _selectedDuration,
                    isExpanded: false,
                    underline: Container(),
                    dropdownColor: colors.surface,
                    style: TextStyle(color: colors.textPrimary, fontSize: 14),
                    items: _durationOptions.map((duration) {
                      return DropdownMenuItem(
                        value: duration,
                        child: Text('$duration'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedDuration = value;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'seconds',
                  style: TextStyle(color: colors.textPrimary, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Preview
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(BI.eye, color: colors.accent, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Preview',
                        style: TextStyle(
                          color: colors.accent,
                          fontSize: 12,
                          fontWeight: BT.weightSemiBold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    preview,
                    style: TextStyle(color: colors.textPrimary, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textSecondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: hasEvents ? _captureEvents : null,
                  style: TextButton.styleFrom(
                    backgroundColor: hasEvents ? colors.accent : colors.divider,
                    foregroundColor: hasEvents
                        ? Colors.black
                        : colors.textMuted,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Capture'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _captureEvents() {
    final events = widget.captureBuffer.getRecentEvents(_selectedDuration);
    widget.onCapture?.call(events);
  }
}
