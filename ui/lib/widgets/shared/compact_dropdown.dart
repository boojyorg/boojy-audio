import 'package:flutter/material.dart';
import 'boojy_dropdown.dart';

/// A compact dropdown widget for selecting from a list of items.
///
/// Thin wrapper over [BoojyDropdown] kept for its existing call-site API; the
/// chrome (filled chip + themed menu, both A/C variants) lives in the shared
/// widget. Generic over the item type [T].
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
    return BoojyDropdown<T>(
      value: value,
      items: items
          .map(
            (item) => BoojyMenuItem<T>(
              value: item,
              label: itemLabel != null ? itemLabel!(item) : item.toString(),
            ),
          )
          .toList(),
      onChanged: onChanged ?? (_) {},
      width: width,
      enabled: enabled,
    );
  }
}
