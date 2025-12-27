import 'package:flutter/material.dart';
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
    final preview = widget.captureBuffer.getPreview(_selectedDuration);
    final hasEvents = widget.captureBuffer.hasEvents;

    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
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
                const Row(
                  children: [
                    Icon(Icons.history, color: Color(0xFF7FD4A0), size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Capture MIDI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF9E9E9E)),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Description
            const Text(
              'Capture MIDI events from the recent past and create a clip on the selected track.',
              style: TextStyle(
                color: Color(0xFF9E9E9E),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),

            // Duration selector
            Row(
              children: [
                const Text(
                  'Capture last',
                  style: TextStyle(
                    color: Color(0xFFE0E0E0),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF363636)),
                  ),
                  child: DropdownButton<int>(
                    value: _selectedDuration,
                    isExpanded: false,
                    underline: Container(),
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 14),
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
                const Text(
                  'seconds',
                  style: TextStyle(
                    color: Color(0xFFE0E0E0),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Preview
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF363636)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.preview, color: Color(0xFF7FD4A0), size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Preview',
                        style: TextStyle(
                          color: Color(0xFF7FD4A0),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    preview,
                    style: const TextStyle(
                      color: Color(0xFFE0E0E0),
                      fontSize: 14,
                    ),
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
                    foregroundColor: const Color(0xFF9E9E9E),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: hasEvents ? _captureEvents : null,
                  style: TextButton.styleFrom(
                    backgroundColor: hasEvents ? const Color(0xFF7FD4A0) : const Color(0xFF363636),
                    foregroundColor: hasEvents ? Colors.black : const Color(0xFF616161),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
