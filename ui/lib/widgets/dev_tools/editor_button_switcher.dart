import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extension.dart';
import '../editor_button_variant.dart';

/// A floating dev tool for A/B/C-ing the editor toolbar's selection-button
/// style live (Instrument/MIDI tabs + the tool palette). Toggle with
/// Cmd+Shift+E in debug builds. Mirrors [UiLabsSwitcher]: a draggable,
/// barrier-less overlay that lifts its selection up to the DAW screen so the
/// editor panel can read it.
class EditorButtonSwitcher extends StatefulWidget {
  final EditorButtonVariant activeVariant;
  final ValueChanged<EditorButtonVariant> onVariantSelected;
  final VoidCallback onClose;

  const EditorButtonSwitcher({
    super.key,
    required this.activeVariant,
    required this.onVariantSelected,
    required this.onClose,
  });

  @override
  State<EditorButtonSwitcher> createState() => _EditorButtonSwitcherState();
}

class _EditorButtonSwitcherState extends State<EditorButtonSwitcher> {
  // Sits below where the top-bar UI Labs panel opens so both can be visible.
  Offset _position = const Offset(20, 320);

  // Ordered A · B · C for the panel, regardless of enum declaration order.
  static const _order = [
    EditorButtonVariant.outline,
    EditorButtonVariant.solidFill,
    EditorButtonVariant.softFill,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _position += d.delta),
        child: Material(
          elevation: 16,
          borderRadius: BorderRadius.circular(8),
          color: colors.elevated,
          child: Container(
            width: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.divider),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(colors),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final variant in _order)
                        _buildVariantRow(colors, variant),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BoojyColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          Icon(Icons.science_outlined, size: 16, color: colors.textSecondary),
          const SizedBox(width: 8),
          Text(
            'UI Labs · Editor Buttons',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: widget.onClose,
            child: Icon(Icons.close, size: 16, color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantRow(BoojyColors colors, EditorButtonVariant variant) {
    final isActive = widget.activeVariant == variant;
    // Preview swatch painted in the variant's own selected style, so the row
    // shows what it does, not just its name.
    final swatch = resolveEditorButtonStyle(
      variant,
      colors,
      selected: true,
      onAccentContent: Colors.white,
      inactiveContent: colors.textSecondary,
      inactiveBackground: colors.surface,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: GestureDetector(
        onTap: () => widget.onVariantSelected(variant),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? colors.selectionFill : colors.dark,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? colors.selectionBorder : colors.divider,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: swatch.background,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: swatch.border),
                ),
                child: Icon(Icons.edit, size: 11, color: swatch.content),
              ),
              const SizedBox(width: 8),
              Text(
                variant.labLabel,
                style: TextStyle(
                  color: isActive ? colors.accent : colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
