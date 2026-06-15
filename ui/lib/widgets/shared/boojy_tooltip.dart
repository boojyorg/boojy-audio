import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';

/// Affinity-style tooltip: a small card with a bold **title**, an optional
/// one-line **description**, and an optional **shortcut** hint — instead of the
/// flat grey single line a bare [Tooltip] shows.
///
/// Wraps Flutter's [Tooltip] via `richMessage` + a themed `decoration` rather
/// than a hand-rolled overlay: we get the three-region anatomy for free and
/// inherit Tooltip's hover/dismiss/edge-clamping behaviour.
///
/// ```dart
/// BoojyTooltip(
///   title: 'Record',
///   description: 'Capture to the armed track',
///   shortcut: 'R',
///   child: myButton,
/// )
/// ```
class BoojyTooltip extends StatelessWidget {
  /// Bold first line — the control's name. Required.
  final String title;

  /// Optional one-line description under the title.
  final String? description;

  /// Optional keyboard shortcut hint, shown muted on its own line (e.g. `'R'`,
  /// `'⌘Z'`). Pass the display form; this widget does no key formatting.
  final String? shortcut;

  /// The control the tooltip describes.
  final Widget child;

  /// Hover dwell before the card appears. The richer card earns a slightly
  /// longer beat than a bare label so it doesn't flash on every pass-over.
  final Duration waitDuration;

  /// Prefer showing below the child (true) — correct for the top transport bar.
  final bool preferBelow;

  const BoojyTooltip({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.shortcut,
    this.waitDuration = const Duration(milliseconds: 400),
    this.preferBelow = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final spans = <InlineSpan>[
      TextSpan(
        text: title,
        style: BT.label(colors.textPrimary, weight: BT.weightSemiBold),
      ),
      if (description != null && description!.isNotEmpty)
        TextSpan(
          text: '\n$description',
          style: BT.label(colors.textSecondary, weight: BT.weightRegular),
        ),
      if (shortcut != null && shortcut!.isNotEmpty)
        TextSpan(
          text: '\n$shortcut',
          style: BT.caption(colors.textMuted, weight: BT.weightMedium),
        ),
    ];

    return Tooltip(
      richMessage: TextSpan(
        children: spans,
        // Loosen line spacing so the three regions read as stacked rows, not a
        // cramped paragraph.
        style: const TextStyle(height: 1.4),
      ),
      waitDuration: waitDuration,
      preferBelow: preferBelow,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      margin: const EdgeInsets.symmetric(horizontal: BT.sm),
      decoration: BoxDecoration(
        color: colors.elevated,
        borderRadius: BT.borderMd,
        border: Border.all(color: colors.divider, width: 1),
        boxShadow: BT.shadowMd,
      ),
      child: child,
    );
  }
}
