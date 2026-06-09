import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/animation_constants.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';

/// A styled search field — a slim rectangle with hard-square corners that
/// runs the full width of its host panel (edge-to-edge, no side margins).
///
/// Features:
/// - Fills [expandedWidth] (the host panel is fixed-width)
/// - Dark filled background with a thin square-cornered border
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
  // One step up from BT.iconMd/BT.fontLabel — the field is the panel's primary
  // entry point, so its glyph and hint sit slightly above the chrome around it.
  static const double _iconSize = 15;
  static const double _fontSize = 12;

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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AnimationConstants.panelDuration,
        curve: Curves.easeInOut,
        // Always fill the available width (the panel is fixed-width) — the old
        // 105px idle pill was what clipped the placeholder to "Searc…". Hard
        // square corners: the field runs edge-to-edge of the host panel, so
        // rounding would read as a floating pill rather than a built-in band.
        width: widget.expandedWidth,
        height: BT.controlHeight,
        decoration: BoxDecoration(
          color: colors.darkest,
          border: Border.all(
            color: _isFocused
                ? colors.accent.withValues(alpha: 0.37)
                : colors.divider,
          ),
        ),
        clipBehavior: Clip.hardEdge,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Row(
          children: [
            Icon(BI.search, size: _iconSize, color: colors.textMuted),
            const SizedBox(width: 6),
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
                    fontSize: _fontSize,
                    fontWeight: BT.weightMedium,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: TextStyle(
                      color: colors.textMuted,
                      fontSize: _fontSize,
                      fontWeight: BT.weightMedium,
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
                onEnter: (_) {
                  if (!_clearHovered) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _clearHovered = true);
                    });
                  }
                },
                onExit: (_) {
                  if (_clearHovered) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _clearHovered = false);
                    });
                  }
                },
                child: GestureDetector(
                  onTap: _clear,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      '\u2715',
                      style: TextStyle(
                        fontSize: BT.fontBody,
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
        border: Border(bottom: BorderSide(color: colors.elevated)),
      ),
      child: SearchField(
        controller: controller,
        onChanged: onChanged,
        hintText: hintText,
      ),
    );
  }
}
