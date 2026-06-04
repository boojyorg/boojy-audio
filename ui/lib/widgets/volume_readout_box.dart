import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme_extension.dart';
import '../theme/tokens.dart';

/// The little dB number beside a mixer fader, made directly editable:
/// - **drag vertically** to scrub the volume (up = louder), and
/// - **click** to type an exact dB value (Enter / click-away commits, Esc cancels).
///
/// It rides the *same* volume callbacks the fader uses
/// ([onVolumeChanged] / [onVolumeDragStart] / [onVolumeDragEnd]), so the panel's
/// existing `SetVolumeCommand` plumbing makes every change one undo step and
/// keeps the engine in sync — no new command. A typed commit is just
/// snapshot → apply → commit, exactly like a drag.
class VolumeReadoutBox extends StatefulWidget {
  final double volumeDb; // current value, -60..+6 (<= -60 shows as -∞)
  final ValueChanged<double>? onVolumeChanged;
  final VoidCallback? onVolumeDragStart;
  final VoidCallback? onVolumeDragEnd;

  // Styling so this can render both the boxed two-row/master readout and the
  // bare right-aligned one-row readout.
  final double width;
  final double fontSize;
  final Color textColor;
  final TextAlign textAlign;
  final bool showSuffix; // ' dB' suffix
  final bool boxed; // dark rounded background

  const VolumeReadoutBox({
    super.key,
    required this.volumeDb,
    this.onVolumeChanged,
    this.onVolumeDragStart,
    this.onVolumeDragEnd,
    required this.width,
    required this.fontSize,
    required this.textColor,
    this.textAlign = TextAlign.center,
    this.showSuffix = true,
    this.boxed = true,
  });

  /// Volume range (dB). Mirrors the Boojy curve bounds in `capsule_fader.dart`.
  static const double minDb = -60.0;
  static const double maxDb = 6.0;

  /// Drag sensitivity: dB per vertical pixel. Fine by design — the fader is the
  /// coarse control, this is the precise one (~264 px covers the full range).
  static const double dbPerPixel = 0.25;

  /// How far the pointer must move vertically before a press counts as a scrub
  /// rather than a click. The drag recognizer still wins the gesture arena at
  /// ~1px for a mouse (so the parent list can't scroll/reorder the track), but
  /// we hold off changing the volume until this threshold; below it the gesture
  /// ends as a click and opens the editor. Without this, a normal mouse click
  /// (which always drifts a pixel or two) would be swallowed as a tiny scrub.
  static const double tapSlop = 5.0;

  @override
  State<VolumeReadoutBox> createState() => _VolumeReadoutBoxState();
}

class _VolumeReadoutBoxState extends State<VolumeReadoutBox> {
  bool _isEditing = false;
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  // Tap-vs-drag tracking (see [VolumeReadoutBox.tapSlop]). The vertical-drag
  // recognizer claims the gesture arena early (so the parent list can't scroll
  // or reorder the track underneath us), but we only *scrub* once the pointer
  // has actually moved past [tapSlop]; a smaller movement ends as a click.
  bool _scrubbing = false;
  double _dragDy = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    // Blur commits whatever is in the field (mirrors the inline-rename pattern).
    // Esc-cancel clears _isEditing *before* unfocusing, so this is a no-op then.
    if (!_focusNode.hasFocus && _isEditing) {
      _commitTyped();
    }
  }

  String get _displayText {
    final suffix = widget.showSuffix ? ' dB' : '';
    if (widget.volumeDb <= VolumeReadoutBox.minDb) return '-∞$suffix';
    return '${widget.volumeDb.toStringAsFixed(1)}$suffix';
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      // Prefill with the plain number; silence (-∞) starts blank.
      _controller.text = widget.volumeDb <= VolumeReadoutBox.minDb
          ? ''
          : widget.volumeDb.toStringAsFixed(1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  /// Parse a forgiving dB string: strips a ' dB' suffix, accepts -inf/-∞ as
  /// silence, clamps to range. Returns null for unparseable/empty (= cancel).
  double? _parseDb(String raw) {
    var s = raw.trim().toLowerCase();
    s = s.replaceAll(RegExp(r'\s*db\s*$'), '').trim();
    if (s.isEmpty) return null;
    if (s == '-∞' || s == '-inf' || s == '-infinity') {
      return VolumeReadoutBox.minDb;
    }
    final v = double.tryParse(s);
    if (v == null) return null;
    return v.clamp(VolumeReadoutBox.minDb, VolumeReadoutBox.maxDb);
  }

  void _commitTyped() {
    final parsed = _parseDb(_controller.text);
    setState(() => _isEditing = false);
    if (parsed == null) return; // unparseable / empty → no change
    // Same snapshot → apply → commit flow a drag uses, so it's one undo step.
    widget.onVolumeDragStart?.call();
    widget.onVolumeChanged?.call(parsed);
    widget.onVolumeDragEnd?.call();
  }

  void _cancelEditing() {
    setState(() => _isEditing = false);
    _focusNode.unfocus();
  }

  // --- Tap-vs-scrub via the vertical-drag recognizer. The recognizer wins the
  // arena early (blocks parent scroll/reorder), but we defer the actual volume
  // change until the pointer crosses [tapSlop]; a sub-slop drag ends as a click
  // (open the editor), so a normal mouse click reliably types instead of being
  // swallowed as a 1px scrub.
  void _onDragStart(DragStartDetails details) {
    _scrubbing = false;
    _dragDy = 0.0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (widget.onVolumeChanged == null) return;
    _dragDy += details.delta.dy;
    if (!_scrubbing) {
      if (_dragDy.abs() < VolumeReadoutBox.tapSlop) return; // still a click
      _scrubbing = true;
      widget.onVolumeDragStart?.call();
    }
    final newDb =
        (widget.volumeDb - details.delta.dy * VolumeReadoutBox.dbPerPixel)
            .clamp(VolumeReadoutBox.minDb, VolumeReadoutBox.maxDb);
    widget.onVolumeChanged!(newDb);
  }

  void _onDragEnd(DragEndDetails details) {
    if (_scrubbing) {
      widget.onVolumeDragEnd?.call();
    } else {
      _startEditing(); // moved less than tapSlop → it was a click
    }
    _scrubbing = false;
  }

  void _onDragCancel() {
    if (_scrubbing) widget.onVolumeDragEnd?.call();
    _scrubbing = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) return _buildEditor(context);
    return _buildReadout(context);
  }

  Widget _buildReadout(BuildContext context) {
    final text = Text(
      _displayText,
      textAlign: widget.textAlign,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      style: TextStyle(
        color: widget.textColor,
        fontSize: widget.fontSize,
        fontFamily: BT.fontFamilyMono,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _startEditing,
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        onVerticalDragCancel: _onDragCancel,
        child: SizedBox(
          width: widget.width,
          child: widget.boxed
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.darkest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: text,
                )
              : text,
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _cancelEditing();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          textAlign: widget.textAlign,
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
          ],
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: widget.fontSize,
            fontFamily: BT.fontFamilyMono,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 3,
              vertical: 2,
            ),
            // Keep the unit visible while typing, but non-editable — only the
            // number is in the field (the parser also strips a typed ' dB').
            suffixText: widget.showSuffix ? 'dB' : null,
            suffixStyle: TextStyle(
              color: widget.textColor,
              fontSize: widget.fontSize,
              fontFamily: BT.fontFamilyMono,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            filled: true,
            fillColor: context.colors.darkest,
            border: const OutlineInputBorder(borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: context.colors.accent),
            ),
          ),
          onSubmitted: (_) => _commitTyped(),
        ),
      ),
    );
  }
}
