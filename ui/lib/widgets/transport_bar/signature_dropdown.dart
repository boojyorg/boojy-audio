import 'package:flutter/material.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';

/// Time signature dropdown with optional "Signature" label (matches piano roll style)
class SignatureDropdown extends StatefulWidget {
  final int beatsPerBar;
  final int beatUnit;
  final Function(int beatsPerBar, int beatUnit)? onChanged;

  /// Fired when the drag-to-change gesture starts/ends, letting the parent
  /// coalesce the whole drag into a single undo step.
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const SignatureDropdown({
    super.key,
    required this.beatsPerBar,
    required this.beatUnit,
    this.onChanged,
    this.onDragStart,
    this.onDragEnd,
  });

  @override
  State<SignatureDropdown> createState() => _SignatureDropdownState();
}

class _SignatureDropdownState extends State<SignatureDropdown> {
  bool _isHovered = false;
  bool _isDragging = false;
  double _dragAccumulator = 0;

  /// Step the numerator (beats per bar) by [delta], clamped to a sane range,
  /// and commit. Keeps the current denominator (beat unit).
  void _changeNumerator(int delta) {
    final next = (widget.beatsPerBar + delta).clamp(2, 16);
    if (next != widget.beatsPerBar) {
      widget.onChanged?.call(next, widget.beatUnit);
    }
  }

  void _showSignatureMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(
      Offset(0, button.size.height),
      ancestor: overlay,
    );

    // Capture colors before showing menu (to avoid provider access in overlay)
    final accentColor = context.colors.accent;
    final beatsPerBar = widget.beatsPerBar;
    final beatUnit = widget.beatUnit;

    PopupMenuItem<(int, int)> sigItem(int num, int den, String label) {
      final isSelected = num == beatsPerBar && den == beatUnit;
      return PopupMenuItem<(int, int)>(
        value: (num, den),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: isSelected
                  ? Icon(BI.radioChecked, size: 16, color: accentColor)
                  : Icon(BI.circle, size: 16),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? accentColor : null,
                fontWeight: isSelected ? BT.weightSemiBold : null,
              ),
            ),
          ],
        ),
      );
    }

    showMenu<(int, int)>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        // Simple
        const PopupMenuItem<(int, int)>(
          enabled: false,
          height: 28,
          child: Text(
            'SIMPLE',
            style: TextStyle(
              fontSize: BT.fontLabel,
              fontWeight: BT.weightSemiBold,
              letterSpacing: 1.0,
            ),
          ),
        ),
        sigItem(4, 4, '4/4'),
        sigItem(3, 4, '3/4'),
        sigItem(2, 4, '2/4'),
        const PopupMenuDivider(),
        // Compound
        const PopupMenuItem<(int, int)>(
          enabled: false,
          height: 28,
          child: Text(
            'COMPOUND',
            style: TextStyle(
              fontSize: BT.fontLabel,
              fontWeight: BT.weightSemiBold,
              letterSpacing: 1.0,
            ),
          ),
        ),
        sigItem(6, 8, '6/8'),
        sigItem(9, 8, '9/8'),
        sigItem(12, 8, '12/8'),
        const PopupMenuDivider(),
        // Odd
        const PopupMenuItem<(int, int)>(
          enabled: false,
          height: 28,
          child: Text(
            'ODD',
            style: TextStyle(
              fontSize: BT.fontLabel,
              fontWeight: BT.weightSemiBold,
              letterSpacing: 1.0,
            ),
          ),
        ),
        sigItem(5, 4, '5/4'),
        sigItem(7, 8, '7/8'),
        sigItem(7, 4, '7/4'),
      ],
    ).then((value) {
      if (value != null) {
        widget.onChanged?.call(value.$1, value.$2);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Time Signature',
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        onEnter: (_) {
          if (!_isHovered) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isHovered = true);
            });
          }
        },
        onExit: (_) {
          if (_isHovered) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isHovered = false);
            });
          }
        },
        child: GestureDetector(
          onTap: () => _showSignatureMenu(context),
          onVerticalDragStart: (_) {
            widget.onDragStart?.call();
            setState(() {
              _isDragging = true;
              _dragAccumulator = 0;
            });
          },
          onVerticalDragUpdate: (details) {
            _dragAccumulator += details.delta.dy;
            const pxPerStep = 6.0;
            if (_dragAccumulator.abs() >= pxPerStep) {
              final steps = (_dragAccumulator / pxPerStep).truncate();
              _dragAccumulator -= steps * pxPerStep;
              _changeNumerator(-steps); // drag up = increase
            }
          },
          onVerticalDragEnd: (_) {
            widget.onDragEnd?.call();
            setState(() => _isDragging = false);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // [4/4] box - LCD readout style (h-padding matches the tempo box
              // so the readout row reads as uniform boxes).
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.colors.darkest,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: (_isHovered || _isDragging)
                        ? context.colors.accent
                        : context.colors.divider,
                    width: 1,
                  ),
                ),
                child: Text(
                  '${widget.beatsPerBar}/${widget.beatUnit}',
                  style: BT.display(context.colors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
