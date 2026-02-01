import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';

/// Time signature dropdown with optional "Signature" label (matches piano roll style)
class SignatureDropdown extends StatefulWidget {
  final int beatsPerBar;
  final int beatUnit;
  final Function(int beatsPerBar, int beatUnit)? onChanged;
  final bool isLabelHidden;

  const SignatureDropdown({
    super.key,
    required this.beatsPerBar,
    required this.beatUnit,
    this.onChanged,
    this.isLabelHidden = false,
  });

  @override
  State<SignatureDropdown> createState() => _SignatureDropdownState();
}

class _SignatureDropdownState extends State<SignatureDropdown> {
  bool _isHovered = false;

  void _showSignatureMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(Offset(0, button.size.height), ancestor: overlay);

    // Capture colors before showing menu (to avoid provider access in overlay)
    final accentColor = context.colors.accent;
    final beatsPerBar = widget.beatsPerBar;
    final beatUnit = widget.beatUnit;

    final signatures = [
      (4, 4, '4/4'),
      (3, 4, '3/4'),
      (6, 8, '6/8'),
      (2, 4, '2/4'),
    ];

    showMenu<(int, int)>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: signatures.map((sig) {
        final isSelected = sig.$1 == beatsPerBar && sig.$2 == beatUnit;
        return PopupMenuItem<(int, int)>(
          value: (sig.$1, sig.$2),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check : Icons.music_note,
                size: 16,
                color: isSelected ? accentColor : null,
              ),
              const SizedBox(width: 8),
              Text(
                sig.$3,
                style: TextStyle(
                  color: isSelected ? accentColor : null,
                  fontWeight: isSelected ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        );
      }).toList(),
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
              // "Signature" label - hidden when space is tight
              if (!widget.isLabelHidden) ...[
                Text(
                  'Signature',
                  style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              // [4/4] box - always shown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: _isHovered ? context.colors.surface : context.colors.dark,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: context.colors.surface, width: 1.5),
                ),
                child: Text(
                  '${widget.beatsPerBar}/${widget.beatUnit}',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
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
