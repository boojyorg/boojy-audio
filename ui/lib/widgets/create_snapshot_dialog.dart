import 'package:flutter/material.dart';
import '../theme/boojy_icons.dart';
import '../theme/theme_extension.dart';
import '../theme/tokens.dart';

/// Dialog for creating a new project snapshot
class CreateSnapshotDialog extends StatefulWidget {
  final List<String> existingNames;

  const CreateSnapshotDialog({super.key, this.existingNames = const []});

  static Future<({String name, String? note})?> show(
    BuildContext context, {
    List<String> existingNames = const [],
  }) {
    return showDialog<({String name, String? note})>(
      context: context,
      builder: (context) => CreateSnapshotDialog(existingNames: existingNames),
    );
  }

  @override
  State<CreateSnapshotDialog> createState() => _CreateSnapshotDialogState();
}

class _CreateSnapshotDialogState extends State<CreateSnapshotDialog> {
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _create() {
    final name = _nameController.text.trim();

    // Validate name
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter a name');
      return;
    }

    // Check if name already exists
    if (widget.existingNames.any(
      (n) => n.toLowerCase() == name.toLowerCase(),
    )) {
      setState(
        () => _errorMessage = 'A snapshot with this name already exists',
      );
      return;
    }

    final note = _noteController.text.trim();

    Navigator.of(context).pop((name: name, note: note.isEmpty ? null : note));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.elevated,
      child: Container(
        width: 450,
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
                  'New Snapshot',
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
            const SizedBox(height: 8),
            Text(
              'Save a snapshot of your current project',
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),

            // Name field
            Text(
              'Name',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: BT.weightSemiBold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'e.g., Chorus Idea 1',
                hintStyle: TextStyle(color: colors.textMuted),
                filled: true,
                fillColor: colors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.accent),
                ),
                errorText: _errorMessage,
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.error),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.error),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() => _errorMessage = null);
                }
              },
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 16),

            // Note field (optional)
            Text(
              'Note (optional)',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: BT.weightSemiBold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              maxLines: 3,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'e.g., Trying different arrangement for the chorus',
                hintStyle: TextStyle(color: colors.textMuted),
                filled: true,
                fillColor: colors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.accent),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textSecondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _create,
                  style: TextButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Create Snapshot'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
