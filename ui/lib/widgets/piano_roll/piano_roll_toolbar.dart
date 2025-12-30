import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';
import '../shared/split_button.dart';

/// Piano Roll toolbar - simplified to zoom controls and close button
/// Tool mode buttons and lane toggles have moved to the sidebar
class PianoRollToolbar extends StatelessWidget {
  // Zoom
  final double pixelsPerBeat;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;

  // Close
  final VoidCallback? onClose;

  const PianoRollToolbar({
    super.key,
    this.pixelsPerBeat = 80.0,
    this.onZoomIn,
    this.onZoomOut,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colors.standard,
        border: Border(
          bottom: BorderSide(color: colors.surface, width: 1),
        ),
      ),
      child: Row(
        children: [
          const Spacer(),
          // Zoom controls and close button
          _buildViewControls(context),
        ],
      ),
    );
  }

  Widget _buildViewControls(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Zoom controls
        ToolbarButton(
          icon: Icons.remove,
          label: '',
          onTap: onZoomOut,
          tooltip: 'Zoom out',
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '${pixelsPerBeat.toInt()}px',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 10,
            ),
          ),
        ),
        const SizedBox(width: 4),
        ToolbarButton(
          icon: Icons.add,
          label: '',
          onTap: onZoomIn,
          tooltip: 'Zoom in',
        ),
        const SizedBox(width: 12),
        // Close button
        ToolbarButton(
          icon: Icons.close,
          label: '',
          onTap: onClose,
          tooltip: 'Close Piano Roll',
        ),
      ],
    );
  }
}
