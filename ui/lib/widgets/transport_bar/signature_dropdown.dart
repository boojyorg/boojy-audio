import 'package:flutter/material.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';

/// Time signature dropdown with optional "Signature" label (matches piano roll style).
/// Only the numerator (beats per bar) is editable — the engine has no
/// beat-unit concept yet, so the denominator is locked to /4 for v0.6
/// (offering 6/8 that plays identically to 6/4 was worse than not offering it).
class SignatureDropdown extends StatefulWidget {
  final int beatsPerBar;
  final Function(int beatsPerBar, int beatUnit)? onChanged;

  /// Fired when the drag-to-change gesture starts/ends, letting the parent
  /// coalesce the whole drag into a single undo step.
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const SignatureDropdown({
    super.key,
    required this.beatsPerBar,
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
  /// and commit (denominator stays locked at 4).
  void _changeNumerator(int delta) {
    final next = (widget.beatsPerBar + delta).clamp(2, 16);
    if (next != widget.beatsPerBar) {
      widget.onChanged?.call(next, 4);
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

    PopupMenuItem<int> sigItem(int num) {
      final isSelected = num == beatsPerBar;
      return PopupMenuItem<int>(
        value: num,
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
              '$num/4',
              style: TextStyle(
                color: isSelected ? accentColor : null,
                fontWeight: isSelected ? BT.weightSemiBold : null,
              ),
            ),
          ],
        ),
      );
    }

    showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        sigItem(2),
        sigItem(3),
        sigItem(4),
        sigItem(5),
        sigItem(6),
        sigItem(7),
      ],
    ).then((value) {
      if (value != null) {
        widget.onChanged?.call(value, 4);
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
                  '${widget.beatsPerBar}/4',
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
