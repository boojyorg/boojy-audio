import 'package:flutter/material.dart';
import '../models/project_metadata.dart';
import '../theme/boojy_icons.dart';
import '../theme/theme_extension.dart';
import '../theme/tokens.dart';
import 'shared/boojy_dropdown.dart';

/// Project-specific settings dialog.
/// Returns the updated [ProjectMetadata] on save, or null on cancel.
class ProjectSettingsDialog extends StatefulWidget {
  final ProjectMetadata metadata;
  final Function(ProjectMetadata)? onSave;

  const ProjectSettingsDialog({
    super.key,
    required this.metadata,
    this.onSave,
  });

  static Future<ProjectMetadata?> show(
    BuildContext context, {
    required ProjectMetadata metadata,
  }) {
    return showDialog<ProjectMetadata>(
      context: context,
      barrierColor: BT.dialogBarrierColor,
      builder: (context) => ProjectSettingsDialog(
        metadata: metadata,
        onSave: (result) => Navigator.of(context).pop(result),
      ),
    );
  }

  @override
  State<ProjectSettingsDialog> createState() => _ProjectSettingsDialogState();
}

class _ProjectSettingsDialogState extends State<ProjectSettingsDialog> {
  late TextEditingController _nameController;
  late int _timeSignatureNumerator;
  late int _timeSignatureDenominator;
  late int _sampleRate;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.metadata.name);
    _timeSignatureNumerator = widget.metadata.timeSignatureNumerator;
    _timeSignatureDenominator = widget.metadata.timeSignatureDenominator;
    _sampleRate = widget.metadata.sampleRate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    final updated = widget.metadata.copyWith(
      name: name.isEmpty ? 'Untitled' : name,
      timeSignatureNumerator: _timeSignatureNumerator,
      timeSignatureDenominator: _timeSignatureDenominator,
      sampleRate: _sampleRate,
      lastModified: DateTime.now(),
    );
    widget.onSave?.call(updated);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Dialog(
      backgroundColor: colors.darkest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.divider),
      ),
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      child: Container(
        width: BT.dialogWidthSm,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Project Settings',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: BT.fontHeading,
                    fontWeight: BT.weightSemiBold,
                  ),
                ),
                IconButton(
                  icon: Icon(BI.close, color: colors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Project Name
            _buildLabel(context, 'Project Name'),
            const SizedBox(height: 4),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'My Song',
                hintStyle: TextStyle(color: colors.textMuted),
                filled: true,
                fillColor: colors.standard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: colors.elevated),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: colors.elevated),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: colors.accent),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Time Signature + Sample Rate (side by side)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Time Signature
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel(context, 'Time Signature'),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: BoojyDropdown<int>(
                              value: _timeSignatureNumerator,
                              items: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
                                  .map((n) => BoojyMenuItem(
                                        value: n,
                                        label: '$n',
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _timeSignatureNumerator = v),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              '/',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Expanded(
                            child: BoojyDropdown<int>(
                              value: _timeSignatureDenominator,
                              items: [2, 4, 8, 16]
                                  .map((n) => BoojyMenuItem(
                                        value: n,
                                        label: '$n',
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _timeSignatureDenominator = v),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Sample Rate
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel(context, 'Sample Rate'),
                      const SizedBox(height: 4),
                      BoojyDropdown<int>(
                        value: _sampleRate,
                        items: [44100, 48000]
                            .map((r) => BoojyMenuItem(
                                  value: r,
                                  label: '$r Hz',
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _sampleRate = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Created / Modified (read-only)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel(context, 'Created'),
                      const SizedBox(height: 2),
                      Text(
                        widget.metadata.formattedCreatedDate,
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: BT.fontBody,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel(context, 'Modified'),
                      const SizedBox(height: 2),
                      Text(
                        widget.metadata.formattedLastModified,
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: BT.fontBody,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textSecondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _save,
                  style: TextButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.darkest,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        color: context.colors.textSecondary,
        fontSize: 12,
      ),
    );
  }
}
