import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';

/// Time signature dropdown with optional "Signature" label (matches piano roll style)
class SignatureDropdown extends StatefulWidget {
  final int beatsPerBar;
  final int beatUnit;
  final Function(int beatsPerBar, int beatUnit)? onChanged;

  const SignatureDropdown({
    super.key,
    required this.beatsPerBar,
    required this.beatUnit,
    this.onChanged,
  });

  @override
  State<SignatureDropdown> createState() => _SignatureDropdownState();
}

class _SignatureDropdownState extends State<SignatureDropdown> {
  bool _isHovered = false;

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
                  ? Icon(
                      Icons.radio_button_checked,
                      size: 16,
                      color: accentColor,
                    )
                  : const Icon(Icons.radio_button_unchecked, size: 16),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? accentColor : null,
                fontWeight: isSelected ? FontWeight.w600 : null,
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
              fontSize: 11,
              fontWeight: FontWeight.w600,
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
              fontSize: 11,
              fontWeight: FontWeight.w600,
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
              fontSize: 11,
              fontWeight: FontWeight.w600,
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
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: () => _showSignatureMenu(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // [4/4] box - LCD readout style
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: context.colors.darkest,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _isHovered
                        ? context.colors.accent
                        : context.colors.divider,
                    width: 1,
                  ),
                ),
                child: Text(
                  '${widget.beatsPerBar}/${widget.beatUnit}',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
