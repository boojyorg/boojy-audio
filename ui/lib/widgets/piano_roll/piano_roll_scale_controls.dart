import 'package:flutter/material.dart';
import '../../models/scale_data.dart';
import '../../theme/theme_extension.dart';

/// Scale controls widget for the Piano Roll left side area.
/// Provides scale root, type selection, and highlight/lock/fold toggles.
class PianoRollScaleControls extends StatelessWidget {
  /// Current scale root (e.g., 'C', 'D#')
  final String scaleRoot;

  /// Current scale type
  final ScaleType scaleType;

  /// Whether scale highlighting is enabled
  final bool highlightEnabled;

  /// Whether scale lock is enabled (snap notes to scale)
  final bool lockEnabled;

  /// Whether fold view is enabled (hide out-of-scale keys)
  final bool foldEnabled;

  /// Whether ghost notes are enabled
  final bool ghostNotesEnabled;

  /// Whether audition is enabled
  final bool auditionEnabled;

  /// Callbacks
  final Function(String)? onRootChanged;
  final Function(ScaleType)? onTypeChanged;
  final VoidCallback? onHighlightToggle;
  final VoidCallback? onLockToggle;
  final VoidCallback? onFoldToggle;
  final VoidCallback? onGhostNotesToggle;
  final VoidCallback? onAuditionToggle;

  const PianoRollScaleControls({
    super.key,
    required this.scaleRoot,
    required this.scaleType,
    this.highlightEnabled = false,
    this.lockEnabled = false,
    this.foldEnabled = false,
    this.ghostNotesEnabled = false,
    this.auditionEnabled = true,
    this.onRootChanged,
    this.onTypeChanged,
    this.onHighlightToggle,
    this.onLockToggle,
    this.onFoldToggle,
    this.onGhostNotesToggle,
    this.onAuditionToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 60,
      decoration: BoxDecoration(
        color: colors.standard,
        border: Border(
          right: BorderSide(color: colors.surface, width: 1),
          bottom: BorderSide(color: colors.surface, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Scale root and type dropdowns
          _buildScaleSelectors(context),
          const SizedBox(height: 4),
          // Row 2: Highlight, Lock, Fold toggles
          _buildToggles(context),
          const SizedBox(height: 8),
          // Audition button (moved from header)
          _buildAuditionButton(context),
        ],
      ),
    );
  }

  Widget _buildScaleSelectors(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        children: [
          // Scale root dropdown
          _buildCompactDropdown<String>(
            context,
            value: scaleRoot,
            items: ScaleRoot.noteNames,
            onChanged: onRootChanged,
            width: 52,
          ),
          const SizedBox(height: 2),
          // Scale type dropdown
          _buildCompactDropdown<ScaleType>(
            context,
            value: scaleType,
            items: ScaleType.values,
            itemLabel: (t) => t.displayName,
            onChanged: onTypeChanged,
            width: 52,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactDropdown<T>(
    BuildContext context, {
    required T value,
    required List<T> items,
    String Function(T)? itemLabel,
    Function(T)? onChanged,
    double width = 52,
  }) {
    final colors = context.colors;
    final label = itemLabel != null ? itemLabel(value) : value.toString();

    return GestureDetector(
      onTap: () => _showDropdownMenu<T>(
        context,
        items: items,
        currentValue: value,
        itemLabel: itemLabel,
        onSelected: onChanged,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 9,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 12,
                color: colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDropdownMenu<T>(
    BuildContext context, {
    required List<T> items,
    required T currentValue,
    String Function(T)? itemLabel,
    Function(T)? onSelected,
  }) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);

    showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(
        buttonPosition.dx,
        buttonPosition.dy,
        overlay.size.width - buttonPosition.dx - button.size.width,
        0,
      ),
      items: items.map((item) {
        final label = itemLabel != null ? itemLabel(item) : item.toString();
        return PopupMenuItem<T>(
          value: item,
          height: 32,
          child: Text(
            label,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 11,
              fontWeight: item == currentValue ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
      elevation: 8,
    ).then((value) {
      if (value != null && onSelected != null) {
        onSelected(value);
      }
    });
  }

  Widget _buildToggles(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          // Row 1: Highlight toggle
          _buildToggleButton(
            context,
            icon: Icons.visibility,
            label: 'Hi',
            isActive: highlightEnabled,
            onTap: onHighlightToggle,
            tooltip: 'Highlight scale notes',
          ),
          const SizedBox(height: 2),
          // Row 2: Lock and Fold
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildToggleButton(
                context,
                icon: Icons.lock,
                label: '',
                isActive: lockEnabled,
                onTap: onLockToggle,
                tooltip: 'Lock to scale',
                size: 24,
              ),
              const SizedBox(width: 2),
              _buildToggleButton(
                context,
                icon: Icons.unfold_less,
                label: '',
                isActive: foldEnabled,
                onTap: onFoldToggle,
                tooltip: 'Fold view',
                size: 24,
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Ghost notes toggle
          _buildToggleButton(
            context,
            icon: Icons.layers,
            label: 'Gh',
            isActive: ghostNotesEnabled,
            onTap: onGhostNotesToggle,
            tooltip: 'Show ghost notes',
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isActive,
    VoidCallback? onTap,
    String? tooltip,
    double size = 52,
  }) {
    final colors = context.colors;

    Widget button = GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: size,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: isActive ? colors.accent : colors.dark,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 12,
                color: colors.textPrimary,
              ),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 9,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(
        message: tooltip,
        child: button,
      );
    }

    return button;
  }

  Widget _buildAuditionButton(BuildContext context) {
    final colors = context.colors;

    return Tooltip(
      message: auditionEnabled ? 'Disable audition' : 'Enable audition',
      child: GestureDetector(
        onTap: onAuditionToggle,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 4),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: auditionEnabled ? colors.accent : colors.dark,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Icon(
              auditionEnabled ? Icons.volume_up : Icons.volume_off,
              size: 16,
              color: colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
