import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extension.dart';

/// A clickable time display showing bar.beat.subdivision format.
/// Each segment (bar, beat, sub) is individually clickable to edit.
/// Used for loop start and loop length in the Piano Roll toolbar.
///
/// Two modes:
/// - Position (isPosition=true): 1-indexed, e.g., 1.1.1 = bar 1, beat 1, sub 1
/// - Length (isPosition=false): 0-indexed for beats/subs, e.g., 1.0.0 = 1 bar
///
/// Features:
/// - First keystroke replaces current value, subsequent keystrokes append
/// - Overflow carries to next segment (e.g., typing 5 in sub carries to beat)
/// - Scroll wheel increments/decrements with overflow
class LoopTimeDisplay extends StatefulWidget {
  /// Value in beats (quarter notes)
  final double beats;

  /// Label shown above the display (e.g., "Start", "Length")
  final String label;

  /// Called when value changes
  final Function(double)? onChanged;

  /// Beats per bar (default 4 for 4/4 time)
  final int beatsPerBar;

  /// Subdivisions per beat (default 4 for sixteenth notes)
  final int subsPerBeat;

  /// If true, display as 1-indexed position (1.1.1 = start of bar 1)
  /// If false, display as length (1.0.0 = 1 bar long)
  final bool isPosition;

  /// Maximum bar value (default 100000)
  static const int maxBars = 100000;

  const LoopTimeDisplay({
    super.key,
    required this.beats,
    required this.label,
    this.onChanged,
    this.beatsPerBar = 4,
    this.subsPerBeat = 4, // 4 sixteenths per beat
    this.isPosition = false, // Default to length display
  });

  @override
  State<LoopTimeDisplay> createState() => _LoopTimeDisplayState();
}

class _LoopTimeDisplayState extends State<LoopTimeDisplay> {
  bool _isEditing = false;
  int _editingSegment = -1; // 0=bar, 1=beat, 2=sub
  bool _isFirstKeystroke = true; // Track if first keystroke should replace
  late TextEditingController _editController;
  late FocusNode _editFocusNode;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController();
    _editFocusNode = FocusNode();
    _editFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _editController.dispose();
    _editFocusNode.removeListener(_onFocusChange);
    _editFocusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_editFocusNode.hasFocus && _isEditing) {
      _commitEdit();
    }
  }

  /// Convert beats to bar.beat.sub tuple
  /// For POSITION (isPosition=true): 1-indexed, 0 beats = 1.1.1
  /// For LENGTH (isPosition=false): 0-indexed for beat/sub, 4 beats = 1.0.0
  (int bar, int beat, int sub) _beatsToBarBeatSub(double beats) {
    final totalSubs = (beats * widget.subsPerBeat).round();
    final subsPerBar = widget.beatsPerBar * widget.subsPerBeat;

    final barValue = totalSubs ~/ subsPerBar;
    final remainingSubs = totalSubs % subsPerBar;
    final beatValue = remainingSubs ~/ widget.subsPerBeat;
    final subValue = remainingSubs % widget.subsPerBeat;

    if (widget.isPosition) {
      // Position: 1-indexed (0 beats = bar 1, beat 1, sub 1)
      return (barValue + 1, beatValue + 1, subValue + 1);
    } else {
      // Length: 0-indexed for beat/sub (4 beats = 1 bar, 0 extra beats, 0 subs)
      return (barValue, beatValue, subValue);
    }
  }

  /// Convert total subs to beats, with proper normalization
  /// This handles overflow automatically by working in total subs
  double _totalSubsToBeats(int totalSubs) {
    // Clamp to valid range
    // Position: min 0 internal = 1.1.1, Length: min 1 internal = 0.0.1
    final minSubs = widget.isPosition ? 0 : 1;
    final maxSubs = LoopTimeDisplay.maxBars * widget.beatsPerBar * widget.subsPerBeat;
    totalSubs = totalSubs.clamp(minSubs, maxSubs);
    return totalSubs / widget.subsPerBeat;
  }

  /// Convert bar.beat.sub to total subs (0-indexed internally)
  int _barBeatSubToTotalSubs(int bar, int beat, int sub) {
    final subsPerBar = widget.beatsPerBar * widget.subsPerBeat;

    int adjustedBar = bar;
    int adjustedBeat = beat;
    int adjustedSub = sub;

    if (widget.isPosition) {
      // Position: convert from 1-indexed to 0-indexed
      adjustedBar = bar - 1;
      adjustedBeat = beat - 1;
      adjustedSub = sub - 1;
    }

    return (adjustedBar * subsPerBar) +
        (adjustedBeat * widget.subsPerBeat) +
        adjustedSub;
  }

  void _startEditing(int segment) {
    final (bar, beat, sub) = _beatsToBarBeatSub(widget.beats);
    String initialValue;
    switch (segment) {
      case 0:
        initialValue = bar.toString();
        break;
      case 1:
        initialValue = beat.toString();
        break;
      case 2:
        initialValue = sub.toString();
        break;
      default:
        return;
    }

    setState(() {
      _isEditing = true;
      _editingSegment = segment;
      _isFirstKeystroke = true;
      _editController.text = initialValue; // Show current value
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editFocusNode.requestFocus();
      // Select all text so first keystroke replaces it
      _editController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editController.text.length,
      );
    });
  }

  void _commitEdit() {
    if (!_isEditing) return;

    final text = _editController.text;
    if (text.isNotEmpty && widget.onChanged != null) {
      final newValue = int.tryParse(text);
      if (newValue != null) {
        _applyValueWithOverflow(newValue);
      }
    }

    setState(() {
      _isEditing = false;
      _editingSegment = -1;
      _isFirstKeystroke = true;
    });
  }

  /// Apply a new value to the current segment, handling overflow
  void _applyValueWithOverflow(int newValue) {
    final (bar, beat, sub) = _beatsToBarBeatSub(widget.beats);

    // Get current total subs
    int totalSubs = _barBeatSubToTotalSubs(bar, beat, sub);

    // Calculate segment sizes for overflow
    final subsPerBeat = widget.subsPerBeat;
    final subsPerBar = widget.beatsPerBar * subsPerBeat;

    if (widget.isPosition) {
      // Position mode: 1-indexed
      switch (_editingSegment) {
        case 0: // Bar
          // Just set the bar value (no overflow from bar)
          final clampedBar = newValue.clamp(1, LoopTimeDisplay.maxBars);
          totalSubs = ((clampedBar - 1) * subsPerBar) +
              ((beat - 1) * subsPerBeat) +
              (sub - 1);
          break;
        case 1: // Beat
          // Calculate overflow: newValue could be > beatsPerBar
          final extraBars = (newValue - 1) ~/ widget.beatsPerBar;
          final remainingBeat = ((newValue - 1) % widget.beatsPerBar) + 1;
          final newBar = (bar + extraBars).clamp(1, LoopTimeDisplay.maxBars);
          totalSubs = ((newBar - 1) * subsPerBar) +
              ((remainingBeat - 1) * subsPerBeat) +
              (sub - 1);
          break;
        case 2: // Sub
          // Calculate overflow: newValue could be > subsPerBeat
          final extraBeats = (newValue - 1) ~/ subsPerBeat;
          final remainingSub = ((newValue - 1) % subsPerBeat) + 1;
          // First apply beat overflow
          final tempBeat = beat + extraBeats;
          final extraBars = (tempBeat - 1) ~/ widget.beatsPerBar;
          final remainingBeat = ((tempBeat - 1) % widget.beatsPerBar) + 1;
          final newBar = (bar + extraBars).clamp(1, LoopTimeDisplay.maxBars);
          totalSubs = ((newBar - 1) * subsPerBar) +
              ((remainingBeat - 1) * subsPerBeat) +
              (remainingSub - 1);
          break;
      }
    } else {
      // Length mode: 0-indexed for beat/sub
      switch (_editingSegment) {
        case 0: // Bar
          final clampedBar = newValue.clamp(0, LoopTimeDisplay.maxBars);
          totalSubs = (clampedBar * subsPerBar) +
              (beat * subsPerBeat) +
              sub;
          break;
        case 1: // Beat
          final extraBars = newValue ~/ widget.beatsPerBar;
          final remainingBeat = newValue % widget.beatsPerBar;
          final newBar = (bar + extraBars).clamp(0, LoopTimeDisplay.maxBars);
          totalSubs = (newBar * subsPerBar) +
              (remainingBeat * subsPerBeat) +
              sub;
          break;
        case 2: // Sub
          final extraBeats = newValue ~/ subsPerBeat;
          final remainingSub = newValue % subsPerBeat;
          final tempBeat = beat + extraBeats;
          final extraBars = tempBeat ~/ widget.beatsPerBar;
          final remainingBeat = tempBeat % widget.beatsPerBar;
          final newBar = (bar + extraBars).clamp(0, LoopTimeDisplay.maxBars);
          totalSubs = (newBar * subsPerBar) +
              (remainingBeat * subsPerBeat) +
              remainingSub;
          break;
      }
    }

    final newBeats = _totalSubsToBeats(totalSubs);
    widget.onChanged!(newBeats);
  }

  /// Increment/decrement segment with scroll, with overflow
  void _handleScroll(int segment, double delta) {
    final (bar, beat, sub) = _beatsToBarBeatSub(widget.beats);
    final direction = delta > 0 ? -1 : 1; // Scroll up = increase

    // Get current total subs
    int totalSubs = _barBeatSubToTotalSubs(bar, beat, sub);

    // Calculate increment based on segment
    final subsPerBeat = widget.subsPerBeat;
    final subsPerBar = widget.beatsPerBar * subsPerBeat;

    switch (segment) {
      case 0: // Bar - increment by full bar
        totalSubs += direction * subsPerBar;
        break;
      case 1: // Beat - increment by full beat
        totalSubs += direction * subsPerBeat;
        break;
      case 2: // Sub - increment by 1 sub
        totalSubs += direction;
        break;
    }

    // Clamp to valid range
    // Position: min 0 internal = 1.1.1, Length: min 1 internal = 0.0.1
    final minSubs = widget.isPosition ? 0 : 1;
    final maxSubs = LoopTimeDisplay.maxBars * subsPerBar - 1;
    totalSubs = totalSubs.clamp(minSubs, maxSubs);

    final newBeats = _totalSubsToBeats(totalSubs);
    widget.onChanged?.call(newBeats);
  }

  // Accumulated drag delta for smooth dragging
  double _dragAccumulator = 0.0;

  /// Handle vertical drag to increment/decrement values
  void _handleDrag(int segment, double deltaY) {
    // Accumulate drag delta - need ~3 pixels to trigger one increment
    _dragAccumulator += deltaY;

    const pixelsPerIncrement = 3.0;
    if (_dragAccumulator.abs() >= pixelsPerIncrement) {
      final increments = (_dragAccumulator / pixelsPerIncrement).truncate();
      _dragAccumulator -= increments * pixelsPerIncrement;

      // Dragging up (negative) = increase, dragging down (positive) = decrease
      final direction = -increments;

      final (bar, beat, sub) = _beatsToBarBeatSub(widget.beats);
      int totalSubs = _barBeatSubToTotalSubs(bar, beat, sub);

      final subsPerBeat = widget.subsPerBeat;
      final subsPerBar = widget.beatsPerBar * subsPerBeat;

      switch (segment) {
        case 0: // Bar
          totalSubs += direction * subsPerBar;
          break;
        case 1: // Beat
          totalSubs += direction * subsPerBeat;
          break;
        case 2: // Sub
          totalSubs += direction;
          break;
      }

      // Clamp to valid range
      // Position: min 0 internal = 1.1.1, Length: min 1 internal = 0.0.1
      final minSubs = widget.isPosition ? 0 : 1;
      final maxSubs = LoopTimeDisplay.maxBars * subsPerBar - 1;
      totalSubs = totalSubs.clamp(minSubs, maxSubs);

      final newBeats = _totalSubsToBeats(totalSubs);
      widget.onChanged?.call(newBeats);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (bar, beat, sub) = _beatsToBarBeatSub(widget.beats);

    // Single row with 3 clickable/editable segments
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSegment(0, bar.toString(), colors),
        _buildDot(colors),
        _buildSegment(1, beat.toString(), colors),
        _buildDot(colors),
        _buildSegment(2, sub.toString(), colors),
      ],
    );
  }

  Widget _buildSegment(int segment, String value, BoojyColors colors) {
    final isEditing = _isEditing && _editingSegment == segment;

    // Calculate max digits for this segment
    final maxDigits = segment == 0 ? 6 : 2; // bar up to 100000, beat/sub up to 16

    if (isEditing) {
      return SizedBox(
        width: segment == 0 ? 40 : 24, // Wider for bar, enough for beat/sub
        height: 18,
        child: TextField(
          controller: _editController,
          focusNode: _editFocusNode,
          autofocus: true,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 10,
            fontFamily: 'monospace',
          ),
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            isDense: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(maxDigits),
            _FirstKeystrokeReplacer(this),
          ],
          onSubmitted: (_) => _commitEdit(),
        ),
      );
    }

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _handleScroll(segment, event.scrollDelta.dy);
        }
      },
      child: GestureDetector(
        onTap: () => _startEditing(segment),
        onVerticalDragUpdate: (details) {
          // Dragging up (negative dy) = increase value
          // Scale: ~3 pixels per increment
          _handleDrag(segment, details.delta.dy);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              value,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDot(BoojyColors colors) {
    return Text(
      '.',
      style: TextStyle(
        color: colors.textMuted,
        fontSize: 10,
        fontFamily: 'monospace',
      ),
    );
  }
}

/// Input formatter that replaces text on first keystroke, then appends
class _FirstKeystrokeReplacer extends TextInputFormatter {
  final _LoopTimeDisplayState state;

  _FirstKeystrokeReplacer(this.state);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // If this is the first keystroke, the text was selected, so Flutter
    // already replaced it. Just mark that we're past the first keystroke.
    if (state._isFirstKeystroke && newValue.text != oldValue.text) {
      state._isFirstKeystroke = false;
    }
    return newValue;
  }
}
