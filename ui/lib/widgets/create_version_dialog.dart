import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/boojy_icons.dart';
import '../theme/theme_extension.dart';
import '../theme/tokens.dart';
import '../models/version_type.dart';

/// Dialog for creating a new project version
class CreateVersionDialog extends StatefulWidget {
  final List<String> existingNames;
  final int nextVersionNumber;
  final VersionType? initialType;

  const CreateVersionDialog({
    super.key,
    this.existingNames = const [],
    required this.nextVersionNumber,
    this.initialType,
  });

  static Future<({String name, String? note, VersionType type})?> show(
    BuildContext context, {
    List<String> existingNames = const [],
    required int nextVersionNumber,
    VersionType? initialType,
  }) {
    return showDialog<({String name, String? note, VersionType type})>(
      context: context,
      builder: (context) => CreateVersionDialog(
        existingNames: existingNames,
        nextVersionNumber: nextVersionNumber,
        initialType: initialType,
      ),
    );
  }

  @override
  State<CreateVersionDialog> createState() => _CreateVersionDialogState();
}

class _CreateVersionDialogState extends State<CreateVersionDialog> {
  late final TextEditingController _nameController;
  final _noteController = TextEditingController();
  late VersionType _selectedType;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType ?? VersionType.demo;
    _nameController = TextEditingController(text: _getSuggestedName());
  }

  String _getSuggestedName() {
    return _selectedType.displayLabel(widget.nextVersionNumber);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onTypeChanged(VersionType type) {
    final currentName = _nameController.text.trim();
    final oldSuggested = _getSuggestedName();

    setState(() {
      _selectedType = type;
    });

    // Update name if it was the suggested name
    if (currentName == oldSuggested || currentName.isEmpty) {
      _nameController.text = _getSuggestedName();
    }
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
      setState(() => _errorMessage = 'A version with this name already exists');
      return;
    }

    final note = _noteController.text.trim();

    Navigator.of(
      context,
    ).pop((name: name, note: note.isEmpty ? null : note, type: _selectedType));
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
                  'New Version',
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
              'Save a version of your current project',
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),

            // Version type selector
            Text(
              'Type',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: BT.weightSemiBold,
              ),
            ),
            const SizedBox(height: 8),
            _buildVersionTypeSelector(colors),
            const SizedBox(height: 16),

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
                hintText: _getSuggestedName(),
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
                  child: const Text('Create Version'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionTypeSelector(BoojyColors colors) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: VersionType.values.map((type) {
          final isSelected = type == _selectedType;
          return Expanded(
            child: GestureDetector(
              onTap: () => _onTypeChanged(type),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? type.color : Colors.transparent,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Center(
                  child: Text(
                    type.displayName,
                    style: TextStyle(
                      color: isSelected ? Colors.black : colors.textSecondary,
                      fontWeight: isSelected
                          ? BT.weightSemiBold
                          : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
