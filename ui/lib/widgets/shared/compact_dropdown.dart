import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';

/// A compact dropdown widget for selecting from a list of items.
///
/// This provides a consistent, space-efficient dropdown UI that matches
/// the DAW's visual style. It's generic over the item type [T].
///
/// Example usage:
/// ```dart
/// CompactDropdown<String>(
///   value: 'C',
///   items: ['C', 'D', 'E', 'F', 'G', 'A', 'B'],
///   onChanged: (value) => setState(() => selectedNote = value),
/// )
/// ```
class CompactDropdown<T> extends StatelessWidget {
  /// The currently selected value.
  final T value;

  /// List of items to display in the dropdown.
  final List<T> items;

  /// Called when the user selects an item.
  final ValueChanged<T>? onChanged;

  /// Optional function to convert item to display label.
  /// If not provided, uses item.toString().
  final String Function(T)? itemLabel;

  /// Width of the dropdown button.
  final double width;

  /// Font size for the label text.
  final double fontSize;

  /// Whether the dropdown is enabled.
  final bool enabled;

  const CompactDropdown({
    super.key,
    required this.value,
    required this.items,
    this.onChanged,
    this.itemLabel,
    this.width = 52,
    this.fontSize = 9,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = itemLabel != null ? itemLabel!(value) : value.toString();

    return GestureDetector(
      onTap: enabled ? () => _showDropdownMenu(context) : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: enabled ? colors.textPrimary : colors.textMuted,
                    fontSize: fontSize,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 12,
                color: colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDropdownMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);

    showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(
        buttonPosition.dx,
        buttonPosition.dy,
        overlay.size.width - buttonPosition.dx - button.size.width,
        0,
      ),
      items: items.map((item) {
        final label = itemLabel != null ? itemLabel!(item) : item.toString();
        return PopupMenuItem<T>(
          value: item,
          height: 32,
          child: Text(
            label,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 11,
              fontWeight: item == value ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
      elevation: 8,
    ).then((selectedValue) {
      if (selectedValue != null && onChanged != null) {
        onChanged!(selectedValue);
      }
    });
  }
}
