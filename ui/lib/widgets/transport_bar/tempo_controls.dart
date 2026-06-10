import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';

/// Tempo readout + tap-tempo, fused into one split button — `[ 120 │ BPM ]`.
///
/// Wears the **LCD costume** of its readout neighbours (`1.1.1`, `4/4`): black
/// `darkest` fill, divider border, radius 4 — so the three boxes read as one
/// set. Borrows only the *mechanic* of the Loop/Snap split buttons:
///   - **Number zone** (left): drag to nudge, scroll to step, double-tap to type.
///   - **`BPM` zone** (right): tap in rhythm to set tempo; the divider + label
///     flash accent on each tap.
class TempoDisplay extends StatefulWidget {
  final double tempo;
  final Function(double)? onTempoChanged;

  /// Fired when the drag-to-nudge gesture starts/ends, letting the parent
  /// coalesce the whole drag into a single undo step (same pattern as the
  /// signature control — without it every drag tick landed its own BPM on
  /// the undo stack).
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  /// When true the number zone shrinks its min width — used at low
  /// transport-bar density so the readout cluster stays compact.
  final bool compact;

  /// When false the divider + `BPM` tap zone shed entirely ("120 BPM" →
  /// "120"), in step with the tool labels — the density math budgets for the
  /// label being gone at compact width (M22). Tempo stays adjustable via
  /// drag / scroll / double-tap; tap-tempo returns with the labels.
  final bool showLabel;

  const TempoDisplay({
    super.key,
    required this.tempo,
    this.onTempoChanged,
    this.onDragStart,
    this.onDragEnd,
    this.compact = false,
    this.showLabel = true,
  });

  @override
  State<TempoDisplay> createState() => _TempoDisplayState();
}

class _TempoDisplayState extends State<TempoDisplay> {
  bool _isDragging = false;
  double _dragStartY = 0.0;
  double _dragStartTempo = 120.0;

  bool _numHovered = false;
  bool _bpmHovered = false;

  // Tap-tempo state: timestamps of recent taps + a brief accent flash.
  final List<DateTime> _tapTimes = [];
  bool _flash = false;
  int _flashToken = 0;

  /// Register one rhythmic tap; once we have ≥2 taps, average their interval
  /// into a BPM and commit it. Pulses the accent flash on every tap.
  void _onTapTempo() {
    final now = DateTime.now();
    _tapTimes
      ..removeWhere((t) => now.difference(t).inSeconds > 3)
      ..add(now);

    if (_tapTimes.length >= 2) {
      double total = 0.0;
      for (int i = 1; i < _tapTimes.length; i++) {
        total += _tapTimes[i].difference(_tapTimes[i - 1]).inMilliseconds;
      }
      final avg = total / (_tapTimes.length - 1);
      final bpm = (60000.0 / avg).clamp(20.0, 300.0).roundToDouble();
      widget.onTempoChanged?.call(bpm);
    }

    // Brief accent pulse so a tap is felt even before two taps land a tempo.
    final token = ++_flashToken;
    setState(() => _flash = true);
    Future.delayed(const Duration(milliseconds: 320), () {
      if (mounted && token == _flashToken) setState(() => _flash = false);
    });
  }

  /// Format tempo for display: whole numbers as `120`, decimals as `120.50`.
  String _formatTempo(double tempo) {
    if (tempo == tempo.roundToDouble()) return '${tempo.round()}';
    return tempo.toStringAsFixed(2);
  }

  void _showTempoDialog(BuildContext context) {
    final initialText = widget.tempo == widget.tempo.roundToDouble()
        ? widget.tempo.round().toString()
        : widget.tempo.toStringAsFixed(2);
    final controller = TextEditingController(text: initialText);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Project Tempo'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'BPM (20 - 300)'),
          autofocus: true,
          onSubmitted: (_) {
            final value = double.tryParse(controller.text) ?? 120.0;
            widget.onTempoChanged?.call(value.clamp(20, 300));
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = double.tryParse(controller.text) ?? 120.0;
              widget.onTempoChanged?.call(value.clamp(20, 300));
              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _onScroll(PointerScrollEvent event) {
    if (widget.onTempoChanged == null) return;
    final direction = event.scrollDelta.dy < 0 ? 1.0 : -1.0;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final delta = isShift ? 0.1 : 1.0;
    final newTempo = (widget.tempo + direction * delta).clamp(20.0, 300.0);
    widget.onTempoChanged!(newTempo);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tempoText = _formatTempo(widget.tempo);

    // BPM label: dim unit at rest, brightens on hover, accent on tap-flash.
    final bpmColor = _flash
        ? colors.accent
        : (_bpmHovered ? colors.textPrimary : colors.textSecondary);

    return Container(
      // Black LCD shell — matches 1.1.1 / 4/4. clip so the divider + zone
      // fills never leak a grey sliver past the rounded corners.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.darkest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _isDragging ? colors.accent : colors.divider,
          width: 1,
        ),
      ),
      // IntrinsicHeight + stretch so the divider spans the box's content
      // height (set by the big number) — same trick as the split buttons.
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Number zone: drag / scroll / double-tap to edit ──
            Tooltip(
              message: 'Drag to adjust · Scroll to step · Double-click to type',
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                onEnter: (_) {
                  if (!_numHovered) setState(() => _numHovered = true);
                },
                onExit: (_) {
                  if (_numHovered) setState(() => _numHovered = false);
                },
                child: Listener(
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) _onScroll(event);
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (details) {
                      widget.onDragStart?.call();
                      setState(() {
                        _isDragging = true;
                        _dragStartY = details.globalPosition.dy;
                        _dragStartTempo = widget.tempo.roundToDouble();
                      });
                    },
                    onVerticalDragUpdate: (details) {
                      if (widget.onTempoChanged != null) {
                        final deltaY = _dragStartY - details.globalPosition.dy;
                        final deltaTempo = (deltaY * 0.5).roundToDouble();
                        final newTempo = (_dragStartTempo + deltaTempo).clamp(
                          20.0,
                          300.0,
                        );
                        widget.onTempoChanged!(newTempo);
                      }
                    },
                    onVerticalDragEnd: (_) {
                      widget.onDragEnd?.call();
                      setState(() => _isDragging = false);
                    },
                    // A cancelled drag must still close the coalescing
                    // window, or the parent would treat every later edit
                    // as mid-drag and skip the undo step entirely.
                    onVerticalDragCancel: () {
                      widget.onDragEnd?.call();
                      setState(() => _isDragging = false);
                    },
                    onDoubleTap: () => _showTempoDialog(context),
                    child: Container(
                      // v:2 (not the split buttons' v:4) so the box height
                      // matches the 1.1.1 / 4/4 readouts exactly.
                      padding: const EdgeInsets.fromLTRB(8, 2, 7, 2),
                      alignment: Alignment.center,
                      // Fixed width (sized for 3 digits) so the box is identical
                      // for "80" vs "120" — no jitter — and softWrap:false stops
                      // a 3-digit tempo (153) from wrapping onto two lines.
                      child: SizedBox(
                        width: widget.compact ? 30 : 34,
                        child: Text(
                          tempoText,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          textAlign: TextAlign.center,
                          style: BT.display(colors.textPrimary),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // ── Divider — always neutral grey (only the BPM label flashes) ──
            if (widget.showLabel) Container(width: 1, color: colors.divider),
            // ── BPM zone: tap in rhythm to set tempo ──
            if (widget.showLabel)
              Tooltip(
                message: 'Tap in time to set tempo',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) {
                    if (!_bpmHovered) setState(() => _bpmHovered = true);
                  },
                  onExit: (_) {
                    if (_bpmHovered) setState(() => _bpmHovered = false);
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _onTapTempo,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.fromLTRB(7, 2, 8, 2),
                      alignment: Alignment.center,
                      color: _flash
                          ? colors.accent.withValues(alpha: 0.18)
                          : (_bpmHovered
                                ? colors.textPrimary.withValues(alpha: 0.06)
                                : Colors.transparent),
                      child: Text(
                        'BPM',
                        style: TextStyle(
                          color: bpmColor,
                          fontSize: BT.fontLabel,
                          fontWeight: BT.weightSemiBold,
                          letterSpacing: 0.5,
                        ),
                      ),
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
