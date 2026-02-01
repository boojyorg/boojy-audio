import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';
import '../shared/pill_toggle_button.dart' show ButtonDisplayMode;

/// Metronome split button: icon toggles metronome, chevron opens count-in menu
class MetronomeSplitButton extends StatefulWidget {
  final bool isActive;
  final int countInBars;
  final VoidCallback? onToggle;
  final Function(int)? onCountInChanged;
  final ButtonDisplayMode mode;

  const MetronomeSplitButton({
    super.key,
    required this.isActive,
    required this.countInBars,
    this.onToggle,
    this.onCountInChanged,
    required this.mode,
  });

  @override
  State<MetronomeSplitButton> createState() => _MetronomeSplitButtonState();
}

class _MetronomeSplitButtonState extends State<MetronomeSplitButton> {
  bool _isIconHovered = false;
  bool _isChevronHovered = false;
  final GlobalKey _buttonKey = GlobalKey();

  void _showCountInMenu(BuildContext context, Color accentColor) {
    final RenderBox button = _buttonKey.currentContext!.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(Offset(0, button.size.height), ancestor: overlay);

    final countInBars = widget.countInBars;

    showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<int>(
          value: 0,
          child: Row(
            children: [
              Icon(
                countInBars == 0 ? Icons.check : Icons.close,
                size: 16,
                color: countInBars == 0 ? accentColor : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Count-in: Off',
                style: TextStyle(
                  color: countInBars == 0 ? accentColor : null,
                  fontWeight: countInBars == 0 ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: 1,
          child: Row(
            children: [
              Icon(
                countInBars == 1 ? Icons.check : Icons.looks_one,
                size: 16,
                color: countInBars == 1 ? accentColor : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Count-in: 1 Bar',
                style: TextStyle(
                  color: countInBars == 1 ? accentColor : null,
                  fontWeight: countInBars == 1 ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: 2,
          child: Row(
            children: [
              Icon(
                countInBars == 2 ? Icons.check : Icons.looks_two,
                size: 16,
                color: countInBars == 2 ? accentColor : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Count-in: 2 Bars',
                style: TextStyle(
                  color: countInBars == 2 ? accentColor : null,
                  fontWeight: countInBars == 2 ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: 4,
          child: Row(
            children: [
              Icon(
                countInBars == 4 ? Icons.check : Icons.looks_4,
                size: 16,
                color: countInBars == 4 ? accentColor : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Count-in: 4 Bars',
                style: TextStyle(
                  color: countInBars == 4 ? accentColor : null,
                  fontWeight: countInBars == 4 ? FontWeight.w600 : null,
                ),
              ),
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
    final colors = context.colors;
    final bgColor = widget.isActive ? colors.accent : colors.dark;
    final textColor = widget.isActive ? colors.elevated : colors.textPrimary;

    // Build tooltip with count-in info
    final countInText = widget.countInBars == 0
        ? 'Off'
        : widget.countInBars == 1
            ? '1 Bar'
            : '2 Bars';
    final tooltip = widget.isActive
        ? 'Metronome On | Count-in: $countInText'
        : 'Metronome Off | Count-in: $countInText';

    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        key: _buttonKey,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Left side: Icon (clickable for toggle)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isIconHovered = true),
              onExit: (_) => setState(() => _isIconHovered = false),
              child: GestureDetector(
                onTap: widget.onToggle,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isIconHovered
                        ? colors.textPrimary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(2),
                      bottomLeft: Radius.circular(2),
                    ),
                  ),
                  child: Image.asset(
                    'assets/images/metronome.png',
                    width: 14,
                    height: 14,
                    color: textColor,
                  ),
                ),
              ),
            ),
            // Divider line
            Container(
              width: 1,
              height: 17,
              color: colors.textPrimary.withValues(alpha: 0.2),
            ),
            // Right side: Dropdown arrow
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isChevronHovered = true),
              onExit: (_) => setState(() => _isChevronHovered = false),
              child: GestureDetector(
                onTap: () => _showCountInMenu(context, colors.accent),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isChevronHovered
                        ? colors.textPrimary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(2),
                      bottomRight: Radius.circular(2),
                    ),
                  ),
                  child: Icon(
                    Icons.arrow_drop_down,
                    size: 17,
                    color: textColor,
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
