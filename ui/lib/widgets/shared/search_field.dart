import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';

/// A styled search field with consistent appearance.
///
/// Features:
/// - Search icon prefix
/// - Clear button suffix when text is present
/// - Consistent styling across the app
/// - Optional onSubmitted callback
class SearchField extends StatefulWidget {
  /// Controller for the text field
  final TextEditingController? controller;

  /// Called when the text changes
  final ValueChanged<String>? onChanged;

  /// Called when the user submits (presses enter)
  final ValueChanged<String>? onSubmitted;

  /// Placeholder text
  final String hintText;

  /// Whether the field should autofocus
  final bool autofocus;

  /// Whether to show the clear button
  final bool showClearButton;

  const SearchField({
    super.key,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.hintText = 'Search...',
    this.autofocus = false,
    this.showClearButton = true,
  });

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late TextEditingController _controller;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    } else {
      _controller.removeListener(_onTextChanged);
    }
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: TextStyle(
        color: colors.textPrimary,
        fontSize: 12,
      ),
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: TextStyle(
          color: colors.textMuted,
          fontSize: 12,
        ),
        prefixIcon: Icon(
          Icons.search,
          color: colors.textMuted,
          size: 16,
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 28,
          minHeight: 28,
        ),
        suffixIcon: widget.showClearButton && _hasText
            ? GestureDetector(
                onTap: _clear,
                child: Icon(
                  Icons.close,
                  color: colors.textMuted,
                  size: 14,
                ),
              )
            : null,
        suffixIconConstraints: const BoxConstraints(
          minWidth: 28,
          minHeight: 28,
        ),
        filled: true,
        fillColor: colors.darkest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
        isDense: true,
      ),
    );
  }
}

/// A search field wrapped in a container with consistent panel styling.
class SearchFieldPanel extends StatelessWidget {
  /// Controller for the text field
  final TextEditingController? controller;

  /// Called when the text changes
  final ValueChanged<String>? onChanged;

  /// Placeholder text
  final String hintText;

  const SearchFieldPanel({
    super.key,
    this.controller,
    this.onChanged,
    this.hintText = 'Search...',
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colors.standard,
        border: Border(
          bottom: BorderSide(color: colors.elevated),
        ),
      ),
      child: SearchField(
        controller: controller,
        onChanged: onChanged,
        hintText: hintText,
      ),
    );
  }
}
