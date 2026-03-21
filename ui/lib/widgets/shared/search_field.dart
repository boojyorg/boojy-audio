import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/theme_extension.dart';

/// A styled search field matching the Boojy Notes pill-shaped design.
///
/// Features:
/// - Compact 95px pill when idle (icon + "Search" hint)
/// - Expands to [expandedWidth] when focused or has text
/// - Dark filled background with pill border
/// - Clear button (✕) when text is present
/// - Escape key clears text and blurs
class SearchField extends StatefulWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String hintText;
  final bool autofocus;
  final bool showClearButton;
  final double expandedWidth;

  const SearchField({
    super.key,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.hintText = 'Search',
    this.autofocus = false,
    this.showClearButton = true,
    this.expandedWidth = 300,
  });

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _hasText = false;
  bool _isFocused = false;
  bool _clearHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_onTextChanged);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
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

  void _onFocusChanged() {
    setState(() => _isFocused = _focusNode.hasFocus);
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    _focusNode.unfocus();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _clear();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool get _isExpanded => _isFocused || _hasText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: _isExpanded ? widget.expandedWidth : 95,
        height: 28,
        decoration: BoxDecoration(
          color: colors.darkest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _isFocused
                ? colors.accent.withValues(alpha: 0.37)
                : colors.divider,
          ),
        ),
        clipBehavior: Clip.hardEdge,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            const Icon(
              Icons.search,
              size: 15.4,
              color: Color(0xFF646880),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Focus(
                onKeyEvent: _handleKeyEvent,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: widget.autofocus,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: TextStyle(
                      color: colors.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                ),
              ),
            ),
            if (widget.showClearButton && _hasText) ...[
              const SizedBox(width: 4),
              MouseRegion(
                onEnter: (_) => setState(() => _clearHovered = true),
                onExit: (_) => setState(() => _clearHovered = false),
                child: GestureDetector(
                  onTap: _clear,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      '\u2715',
                      style: TextStyle(
                        fontSize: 13,
                        color: _clearHovered
                            ? colors.textPrimary
                            : colors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A search field wrapped in a container with consistent panel styling.
class SearchFieldPanel extends StatelessWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String hintText;

  const SearchFieldPanel({
    super.key,
    this.controller,
    this.onChanged,
    this.hintText = 'Search',
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
