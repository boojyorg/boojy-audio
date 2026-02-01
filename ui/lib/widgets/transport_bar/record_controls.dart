import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';

/// Recording indicator with pulsing REC label and duration
class RecordingIndicator extends StatefulWidget {
  final bool isRecording;
  final bool isCountingIn;
  final double playheadPosition;

  const RecordingIndicator({
    super.key,
    required this.isRecording,
    required this.isCountingIn,
    required this.playheadPosition,
  });

  @override
  State<RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<RecordingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    final ms = ((seconds % 1) * 100).floor();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: context.colors.standard,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: widget.isRecording
                ? context.colors.recordActive
                : context.colors.warning,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing REC indicator
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isRecording
                        ? Color.fromRGBO(255, 0, 0, _pulseAnimation.value)
                        : Color.fromRGBO(255, 152, 0, _pulseAnimation.value),
                  ),
                );
              },
            ),
            const SizedBox(width: 6),
            Text(
              widget.isCountingIn ? 'COUNT-IN' : 'REC',
              style: TextStyle(
                color: widget.isRecording
                    ? context.colors.recordActive
                    : context.colors.warning,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            if (widget.isRecording) ...[
              const SizedBox(width: 8),
              Text(
                _formatDuration(widget.playheadPosition),
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Record button with right-click context menu for count-in settings
class RecordButton extends StatefulWidget {
  final bool isRecording;
  final bool isCountingIn;
  final int countInBars;
  final VoidCallback? onPressed;
  final Function(int)? onCountInChanged;
  final double size;

  const RecordButton({
    super.key,
    required this.isRecording,
    required this.isCountingIn,
    required this.countInBars,
    required this.onPressed,
    required this.onCountInChanged,
    this.size = 40,
  });

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    // Blink animation for count-in state (500ms on/off cycle)
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // Start blinking if already counting in
    if (widget.isCountingIn) {
      _blinkController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(RecordButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Start/stop blink animation based on count-in state
    if (widget.isCountingIn && !oldWidget.isCountingIn) {
      _blinkController.repeat(reverse: true);
    } else if (!widget.isCountingIn && oldWidget.isCountingIn) {
      _blinkController.stop();
      _blinkController.reset();
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  void _showCountInMenu(BuildContext context, Offset position) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem<int>(
          value: 0,
          child: Row(
            children: [
              Icon(Icons.close, size: 16),
              SizedBox(width: 8),
              Text('Count-in: Off'),
            ],
          ),
        ),
        const PopupMenuItem<int>(
          value: 1,
          child: Row(
            children: [
              Icon(Icons.looks_one, size: 16),
              SizedBox(width: 8),
              Text('Count-in: 1 Bar'),
            ],
          ),
        ),
        const PopupMenuItem<int>(
          value: 2,
          child: Row(
            children: [
              Icon(Icons.looks_two, size: 16),
              SizedBox(width: 8),
              Text('Count-in: 2 Bars'),
            ],
          ),
        ),
        const PopupMenuItem<int>(
          value: 4,
          child: Row(
            children: [
              Icon(Icons.looks_4, size: 16),
              SizedBox(width: 8),
              Text('Count-in: 4 Bars'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        widget.onCountInChanged?.call(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null;
    final scale = _isPressed ? 0.95 : (_isHovered ? 1.05 : 1.0);

    // Record button color: Bright red (same intensity as play/stop)
    const recordColor = Color(0xFFFF4444);

    String tooltip = widget.isRecording
        ? 'Stop Recording (R)'
        : (widget.isCountingIn ? 'Counting In...' : 'Record (R)');

    // Add count-in info to tooltip
    if (!widget.isRecording && !widget.isCountingIn) {
      final countInText = widget.countInBars == 0
          ? 'Off'
          : widget.countInBars == 1
              ? '1 Bar'
              : widget.countInBars == 2
                  ? '2 Bars'
                  : '4 Bars';
      tooltip += ' | Right-click: Count-in ($countInText)';
    }

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) {
            setState(() => _isPressed = false);
            widget.onPressed?.call();
          },
          onTapCancel: () => setState(() => _isPressed = false),
          onSecondaryTapDown: (details) {
            // Right-click: show count-in menu
            _showCountInMenu(context, details.globalPosition);
          },
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: AnimatedBuilder(
              animation: _blinkController,
              builder: (context, child) {
                // Traffic Light System:
                // - Idle: Grey/red fill with small red circle in center
                // - Count-In: Blinking red (animated)
                // - Recording: Solid red fill with glow

                final bool isCountingIn = widget.isCountingIn;
                final bool isRecording = widget.isRecording;

                // Match CircularToggleButton pattern exactly
                // Fill: dim red when idle, brighter when recording
                Color fillColor;
                if (isRecording) {
                  fillColor = recordColor.withValues(alpha: _isHovered ? 0.95 : 0.85);
                } else if (isCountingIn) {
                  final blinkValue = _blinkController.value;
                  fillColor = recordColor.withValues(alpha: 0.3 + (blinkValue * 0.55));
                } else if (isEnabled) {
                  fillColor = recordColor.withValues(alpha: _isHovered ? 0.3 : 0.2);
                } else {
                  // Disabled: same as CircularToggleButton disabled
                  fillColor = context.colors.elevated.withValues(alpha: _isHovered ? 1.0 : 0.8);
                }

                // Border always visible (matches CircularToggleButton)
                final border = Border.all(
                  color: isEnabled ? recordColor : context.colors.elevated,
                  width: 2,
                );

                // Glow effect when hovering or recording
                final List<BoxShadow>? shadows = (_isHovered || isRecording) && isEnabled
                    ? [
                        BoxShadow(
                          color: recordColor.withValues(alpha: isRecording ? 0.5 : 0.3),
                          blurRadius: isRecording ? 12 : 8,
                          spreadRadius: isRecording ? 3 : 2,
                        ),
                      ]
                    : null;

                return Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: fillColor,
                    shape: BoxShape.circle,
                    border: border,
                    boxShadow: shadows,
                  ),
                  child: Icon(
                    Icons.fiber_manual_record,
                    size: widget.size * 0.5,
                    color: isEnabled
                        ? (isCountingIn
                            ? recordColor.withValues(alpha: 0.5 + (_blinkController.value * 0.5))
                            : recordColor)
                        : context.colors.textMuted,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
