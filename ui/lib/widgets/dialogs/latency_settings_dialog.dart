import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';

/// Shows a dialog for configuring audio latency/buffer size settings.
///
/// [currentPreset] - Currently selected buffer size preset key
/// [presets] - Map of preset key to display label (e.g. {128: "Low (128 samples)"})
/// [onPresetSelected] - Callback when user selects a preset
void showLatencySettingsDialog({
  required BuildContext context,
  required int currentPreset,
  required Map<int, String> presets,
  required void Function(int preset) onPresetSelected,
}) {
  final colors = context.colors;

  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: colors.dark,
      title: Text(
        'Audio Latency Settings',
        style: TextStyle(color: colors.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Buffer Size',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          ...presets.entries.map((entry) {
            final isSelected = entry.key == currentPreset;
            return InkWell(
              onTap: () {
                onPresetSelected(entry.key);
                Navigator.of(dialogContext).pop();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colors.accent.withValues(alpha: 0.2)
                      : colors.dark,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isSelected ? colors.accent : colors.surface,
                  ),
                ),
                child: Row(
                  children: [
                    if (isSelected)
                      Icon(Icons.check, size: 16, color: colors.accent)
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          color: isSelected ? colors.accent : colors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          Text(
            'Lower latency = more responsive but higher CPU usage.\n'
            'If you hear audio glitches, try a higher buffer size.',
            style: TextStyle(color: colors.textMuted, fontSize: 11),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
