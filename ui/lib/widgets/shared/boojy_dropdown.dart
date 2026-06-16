import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';

// ── Entry types ───────────────────────────────────────────────────────────────

/// Base type for all items that can appear in a [showBoojyMenu] surface.
/// Subtypes: [BoojyMenuItem] (action row), [BoojyMenuDivider] (separator),
/// [BoojyMenuSection] (non-interactive group header).
sealed class BoojyMenuEntry<T> {
  const BoojyMenuEntry();
}

/// One action row in a Boojy menu. Value dropdowns use [value]/[label]/[enabled];
/// context menus also carry [icon], [shortcut], and [destructive].
class BoojyMenuItem<T> extends BoojyMenuEntry<T> {
  const BoojyMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.shortcut,
    this.enabled = true,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// Keyboard shortcut shown right-aligned (e.g. '⌘D', '⌫').
  final String? shortcut;
  final bool enabled;

  /// Colours the icon and label [BoojyColors.error] — used for Delete actions.
  final bool destructive;
}

/// A thin horizontal rule separating groups of menu items.
class BoojyMenuDivider<T> extends BoojyMenuEntry<T> {
  const BoojyMenuDivider();
}

/// A non-interactive section header (e.g. 'BUILT-IN', 'PLUGINS').
class BoojyMenuSection<T> extends BoojyMenuEntry<T> {
  const BoojyMenuSection({required this.label});
  final String label;
}

// ── Trigger chip ──────────────────────────────────────────────────────────────

/// Unified value dropdown (v0.7 Slice 3). A compact "quiet pill" trigger —
/// fill + subtle border + muted caret, hugging its content — that opens a
/// rounded menu with per-row hover and a trailing check on the current value
/// (Notion-style). Replaces the scattered "dark box + caret → default Material
/// menu" dropdowns so every value picker reads as one control.
///
/// The menu is a custom overlay rather than Flutter's `showMenu`, because the
/// inset rounded hover highlight (matching the Library list) isn't reachable
/// with the stock `PopupMenuItem`.
class BoojyDropdown<T> extends StatelessWidget {
  const BoojyDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.triggerBuilder,
    this.leadingIcon,
    this.width,
    this.enabled = true,
  });

  final T value;
  final List<BoojyMenuItem<T>> items;
  final ValueChanged<T> onChanged;

  /// Override the chip's value content (e.g. a mono LCD readout). Receives the
  /// resolved label of the current value.
  final Widget Function(BuildContext context, String label)? triggerBuilder;

  /// Optional glyph shown at the chip's leading edge.
  final IconData? leadingIcon;

  /// Fixed chip width for sites that need column alignment; null = hug content.
  final double? width;

  final bool enabled;

  BoojyMenuItem<T>? get _selected {
    for (final item in items) {
      if (item.value == value) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = _selected?.label ?? '$value';

    final Widget valueContent =
        triggerBuilder?.call(context, label) ??
        Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: enabled ? colors.textPrimary : colors.textMuted,
            fontSize: BT.fontLabel,
          ),
        );

    return GestureDetector(
      onTap: enabled ? () => _open(context, colors) : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, size: 13, color: colors.textSecondary),
                const SizedBox(width: 5),
              ],
              Flexible(child: valueContent),
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(BI.caretDown, size: 14, color: colors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, BoojyColors colors) {
    final button = context.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (button == null || overlayBox == null) return;

    final anchor = Rect.fromPoints(
      button.localToGlobal(Offset.zero, ancestor: overlayBox),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      ),
    );

    showBoojyMenu<T>(
      context: context,
      anchor: anchor,
      items: items,
      selectedValue: value,
      colors: colors,
    ).then((picked) {
      if (picked != null) onChanged(picked);
    });
  }
}

// ── Surface ───────────────────────────────────────────────────────────────────

/// Opens the shared rounded menu surface under [anchor]. Exposed so bespoke
/// triggers (and context menus) reuse the exact same surface, hover and
/// selected-row treatment.
///
/// For **value dropdowns**, pass the current value as [selectedValue] — the
/// matching row shows a trailing check.
///
/// For **context menus**, pass `selectedValue: null` (suppresses the check) and
/// put icons/shortcuts/destructive flags on the [BoojyMenuItem]s.
///
/// [colors] must be resolved by the caller in a build context — never read
/// `context.colors` inside the tap handler that calls this (it asserts "listen
/// outside build" in debug; the recurring v0.5.1 footgun).
Future<T?> showBoojyMenu<T>({
  required BuildContext context,
  required Rect anchor,
  required List<BoojyMenuEntry<T>> items,
  required T? selectedValue,
  required BoojyColors colors,
}) {
  return Navigator.of(context).push<T>(
    _BoojyMenuRoute<T>(
      anchor: anchor,
      items: items,
      selectedValue: selectedValue,
      colors: colors,
    ),
  );
}

/// A lightweight popup route for the dropdown menu: transparent barrier (tap
/// outside to dismiss), positioned under the trigger, flips above when there
/// isn't room below.
class _BoojyMenuRoute<T> extends PopupRoute<T> {
  _BoojyMenuRoute({
    required this.anchor,
    required this.items,
    required this.selectedValue,
    required this.colors,
  });

  final Rect anchor;
  final List<BoojyMenuEntry<T>> items;
  final T? selectedValue;
  final BoojyColors colors;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'Dismiss menu';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 120);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final menu = _BoojyMenuSurface<T>(
      items: items,
      selectedValue: selectedValue,
      colors: colors,
      onPick: (value) => Navigator.of(context).pop(value),
    );

    return CustomSingleChildLayout(
      delegate: _BoojyMenuLayout(anchor: anchor),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: menu,
      ),
    );
  }
}

/// Positions the menu directly under the trigger, clamped to the screen, and
/// flips it above the trigger when there isn't room below.
class _BoojyMenuLayout extends SingleChildLayoutDelegate {
  _BoojyMenuLayout({required this.anchor});

  final Rect anchor;

  static const double _gap = 4;
  static const double _margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(
      Size(
        constraints.maxWidth - _margin * 2,
        constraints.maxHeight - _margin * 2,
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double dx = anchor.left;
    dx = dx.clamp(_margin, size.width - childSize.width - _margin);

    final belowTop = anchor.bottom + _gap;
    final fitsBelow = belowTop + childSize.height <= size.height - _margin;
    final double dy = fitsBelow
        ? belowTop
        : (anchor.top - _gap - childSize.height).clamp(
            _margin,
            size.height - childSize.height - _margin,
          );

    return Offset(dx, dy);
  }

  @override
  bool shouldRelayout(_BoojyMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor;
}

/// The rounded card + rows. Sizes to its content.
class _BoojyMenuSurface<T> extends StatelessWidget {
  const _BoojyMenuSurface({
    required this.items,
    required this.selectedValue,
    required this.colors,
    required this.onPick,
  });

  final List<BoojyMenuEntry<T>> items;
  final T? selectedValue;
  final BoojyColors colors;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        constraints: const BoxConstraints(minWidth: 160),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colors.elevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.divider),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: IntrinsicWidth(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final entry in items) _buildEntry(entry)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(height: 1, color: colors.divider),
    );
  }

  Widget _buildSection(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: colors.textMuted,
          fontSize: 10,
          fontWeight: BT.weightSemiBold,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildEntry(BoojyMenuEntry<T> entry) {
    if (entry is BoojyMenuItem<T>) {
      return _BoojyMenuRow<T>(
        item: entry,
        isSelected: entry.value == selectedValue,
        colors: colors,
        onTap: () => onPick(entry.value),
      );
    }
    if (entry is BoojyMenuDivider<T>) return _buildDivider();
    if (entry is BoojyMenuSection<T>) return _buildSection(entry.label);
    return const SizedBox.shrink();
  }
}

/// A single menu row: inset rounded hover fill + optional leading icon +
/// optional trailing shortcut or check on the current value.
class _BoojyMenuRow<T> extends StatefulWidget {
  const _BoojyMenuRow({
    required this.item,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  final BoojyMenuItem<T> item;
  final bool isSelected;
  final BoojyColors colors;
  final VoidCallback onTap;

  @override
  State<_BoojyMenuRow<T>> createState() => _BoojyMenuRowState<T>();
}

class _BoojyMenuRowState<T> extends State<_BoojyMenuRow<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final item = widget.item;
    final enabled = item.enabled;
    final Color labelColor;
    final Color iconColor;
    if (!enabled) {
      labelColor = colors.textMuted;
      iconColor = colors.textMuted;
    } else if (item.destructive) {
      labelColor = colors.error;
      iconColor = colors.error;
    } else {
      labelColor = colors.textPrimary;
      iconColor = colors.textSecondary;
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        onTap: enabled ? widget.onTap : null,
        child: Container(
          decoration: BoxDecoration(
            color: _hovered && enabled ? colors.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(item.icon, size: 16, color: iconColor),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  item.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: BT.fontLabel,
                    fontWeight: widget.isSelected
                        ? BT.weightSemiBold
                        : BT.weightRegular,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (widget.isSelected)
                Icon(BI.check, size: 14, color: colors.textPrimary)
              else if (item.shortcut != null)
                Text(
                  item.shortcut!,
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                )
              else
                const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}
