import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extension.dart';
import '../transport_bar/transport_bar_models.dart';

/// A floating dev tool for A/B-ing the top-bar layout variants live.
/// Toggle with Cmd+Shift+L in debug builds. Mirrors [PaletteEditor]: a
/// draggable, barrier-less overlay that lifts its selection up to the DAW
/// screen so the transport bar can read it.
class UiLabsSwitcher extends StatefulWidget {
  final TopBarVariant activeVariant;
  final bool showCenteredTitle;
  final ValueChanged<TopBarVariant> onVariantSelected;
  final ValueChanged<bool> onCenteredTitleChanged;
  final VoidCallback onClose;

  const UiLabsSwitcher({
    super.key,
    required this.activeVariant,
    required this.showCenteredTitle,
    required this.onVariantSelected,
    required this.onCenteredTitleChanged,
    required this.onClose,
  });

  @override
  State<UiLabsSwitcher> createState() => _UiLabsSwitcherState();
}

class _UiLabsSwitcherState extends State<UiLabsSwitcher> {
  Offset _position = const Offset(20, 64);

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
                      for (final variant in TopBarVariant.values)
                        _buildVariantRow(colors, variant),
                      const SizedBox(height: 6),
                      _buildCenteredTitleToggle(colors),
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
            'UI Labs · Top Bar',
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

  Widget _buildVariantRow(BoojyColors colors, TopBarVariant variant) {
    final isActive = widget.activeVariant == variant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: GestureDetector(
        onTap: () => widget.onVariantSelected(variant),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? colors.accent : colors.dark,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? colors.accent : colors.divider,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isActive ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 15,
                color: isActive ? Colors.white : colors.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                variant.labLabel,
                style: TextStyle(
                  color: isActive ? Colors.white : colors.textSecondary,
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

  Widget _buildCenteredTitleToggle(BoojyColors colors) {
    final on = widget.showCenteredTitle;
    return GestureDetector(
      onTap: () => widget.onCenteredTitleChanged(!on),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colors.dark,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Icon(
              on ? Icons.check_box : Icons.check_box_outline_blank,
              size: 15,
              color: on ? colors.accent : colors.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              'Centered title',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
