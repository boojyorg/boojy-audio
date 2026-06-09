import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Visual language for the editor toolbar's *selection* controls — the
/// Instrument/MIDI tabs and the draw/select/erase/duplicate/slice tool palette.
/// These are one-of-N selections (not on/off toggles), so the question is how
/// the *selected* one should read against the rest of the app. Explored live
/// via the dev "UI Labs · Editor Buttons" switcher (Cmd+Shift+E).
enum EditorButtonVariant {
  /// B — baseline (today): selected = full solid accent fill, light icon.
  /// Boldest / most GarageBand-like; can feel more saturated than the top bar.
  solidFill,

  /// A — system match: selected = accent outline + a faint tint, accent icon.
  /// Mirrors the top bar's engaged-toggle language. Most consistent, but a
  /// ring-only selection is less glanceable for a tool palette.
  outline,

  /// C — soft fill: selected = a low-opacity accent wash + accent border +
  /// accent icon. Keeps "filled = selected" clarity at the top bar's restrained
  /// saturation, so both toolbars read as one system.
  softFill,
}

extension EditorButtonVariantInfo on EditorButtonVariant {
  /// Letter + name shown on the switcher chip.
  String get labLabel {
    switch (this) {
      case EditorButtonVariant.solidFill:
        return 'B · Solid Fill';
      case EditorButtonVariant.outline:
        return 'A · Outline';
      case EditorButtonVariant.softFill:
        return 'C · Soft Fill';
    }
  }

  /// Persisted token (matches the enum identifier).
  String get token => name;
}

/// Parse a persisted token back to a variant, defaulting to [outline] — the
/// chosen design — so a fresh install (or an unknown/removed token) lands on
/// the system-matching look rather than crashing startup.
EditorButtonVariant editorButtonVariantFromName(String? s) {
  switch (s) {
    case 'solidFill':
      return EditorButtonVariant.solidFill;
    case 'softFill':
      return EditorButtonVariant.softFill;
    default:
      return EditorButtonVariant.outline;
  }
}

/// Resolved background / border / content colours for one editor-button state.
class EditorButtonStyle {
  final Color background;
  final Color border;
  final Color content;

  const EditorButtonStyle({
    required this.background,
    required this.border,
    required this.content,
  });
}

/// Single source of truth for how a selection control paints under each
/// variant, so the tabs and the tool palette stay in lock-step.
///
/// [onAccentContent] is the icon/text colour used only by [solidFill]'s
/// selected state (white for tabs, [BoojyColors.elevated] for the small tool
/// icons); the outline/soft variants always tint their content with the accent.
EditorButtonStyle resolveEditorButtonStyle(
  EditorButtonVariant variant,
  BoojyColors colors, {
  required bool selected,
  required Color onAccentContent,
  required Color inactiveContent,
  required Color inactiveBackground,
  Color? inactiveBorder,
}) {
  if (!selected) {
    return EditorButtonStyle(
      background: inactiveBackground,
      border: inactiveBorder ?? colors.divider,
      content: inactiveContent,
    );
  }
  switch (variant) {
    case EditorButtonVariant.solidFill:
      return EditorButtonStyle(
        background: colors.accent,
        border: colors.accent,
        content: onAccentContent,
      );
    case EditorButtonVariant.outline:
      // The chosen design rides the shared selection tokens so the editor
      // tabs/tools match BoojyButton and the transport split buttons exactly.
      return EditorButtonStyle(
        background: colors.selectionFill,
        border: colors.selectionBorder,
        content: colors.accent,
      );
    case EditorButtonVariant.softFill:
      return EditorButtonStyle(
        background: colors.accent.withValues(alpha: 0.24),
        border: colors.accent.withValues(alpha: 0.85),
        content: colors.accent,
      );
  }
}
