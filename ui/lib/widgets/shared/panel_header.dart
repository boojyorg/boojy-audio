import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';

/// A consistent panel header used across the application.
///
/// Features:
/// - Icon + title layout
/// - Optional actions on the right side
/// - Consistent styling (color, padding, border)
/// - Uppercase title with letter spacing
class PanelHeader extends StatelessWidget {
  /// Title text (will be uppercased)
  final String title;

  /// Icon displayed before the title
  final IconData icon;

  /// Optional list of action widgets on the right side
  final List<Widget>? actions;

  /// Background color (defaults to elevated)
  final Color? backgroundColor;

  /// Padding around the content
  final EdgeInsets padding;

  /// Whether to show bottom border
  final bool showBorder;

  /// Font size for title
  final double fontSize;

  /// Whether to uppercase the title
  final bool uppercase;

  const PanelHeader({
    super.key,
    required this.title,
    required this.icon,
    this.actions,
    this.backgroundColor,
    this.padding = const EdgeInsets.all(12),
    this.showBorder = true,
    this.fontSize = 12,
    this.uppercase = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.elevated,
        border: showBorder
            ? Border(
                bottom: BorderSide(color: colors.elevated),
              )
            : null,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: colors.textPrimary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            uppercase ? title.toUpperCase() : title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              letterSpacing: uppercase ? 1.2 : 0,
            ),
          ),
          const Spacer(),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}

/// A collapsible panel header that can toggle visibility.
///
/// Includes a chevron icon that rotates based on expanded state.
class CollapsiblePanelHeader extends StatelessWidget {
  /// Title text
  final String title;

  /// Icon displayed before the title
  final IconData icon;

  /// Whether the panel is currently expanded
  final bool isExpanded;

  /// Called when the header is tapped to toggle expansion
  final VoidCallback? onToggle;

  /// Tooltip for the toggle button
  final String? toggleTooltip;

  /// Background color
  final Color? backgroundColor;

  /// Additional actions before the toggle button
  final List<Widget>? actions;

  const CollapsiblePanelHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.isExpanded,
    this.onToggle,
    this.toggleTooltip,
    this.backgroundColor,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.elevated,
        border: Border(
          bottom: BorderSide(color: colors.elevated),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: colors.textPrimary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (actions != null) ...actions!,
          if (onToggle != null)
            IconButton(
              icon: AnimatedRotation(
                turns: isExpanded ? 0 : 0.5,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.chevron_left),
              ),
              color: colors.textSecondary,
              iconSize: 18,
              onPressed: onToggle,
              tooltip: toggleTooltip,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}

/// A simple section header for use within panels.
///
/// Lighter weight than PanelHeader, used for subsections.
class SectionHeader extends StatelessWidget {
  /// Title text
  final String title;

  /// Optional icon
  final IconData? icon;

  /// Optional trailing widget
  final Widget? trailing;

  /// Padding
  final EdgeInsets padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: padding,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              color: colors.textMuted,
              size: 14,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            title,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}
