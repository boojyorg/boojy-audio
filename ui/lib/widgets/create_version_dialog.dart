import 'package:flutter/material.dart';
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
    if (widget.existingNames.any((n) => n.toLowerCase() == name.toLowerCase())) {
      setState(() => _errorMessage = 'A version with this name already exists');
      return;
    }

    final note = _noteController.text.trim();

    Navigator.of(context).pop((
      name: name,
      note: note.isEmpty ? null : note,
      type: _selectedType,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
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
                const Text(
                  'New Version',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF9E9E9E)),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Save a version of your current project',
              style: TextStyle(
                color: Color(0xFF9E9E9E),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),

            // Version type selector
            const Text(
              'Type',
              style: TextStyle(
                color: Color(0xFF9E9E9E),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _buildVersionTypeSelector(),
            const SizedBox(height: 16),

            // Name field
            const Text(
              'Name',
              style: TextStyle(
                color: Color(0xFF9E9E9E),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: _getSuggestedName(),
                hintStyle: const TextStyle(color: Color(0xFF616161)),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Color(0xFF363636)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Color(0xFF363636)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Color(0xFF7FD4A0)),
                ),
                errorText: _errorMessage,
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Color(0xFFF44336)),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Color(0xFFF44336)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
            const Text(
              'Note (optional)',
              style: TextStyle(
                color: Color(0xFF9E9E9E),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g., Trying different arrangement for the chorus',
                hintStyle: const TextStyle(color: Color(0xFF616161)),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Color(0xFF363636)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Color(0xFF363636)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Color(0xFF7FD4A0)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                    foregroundColor: const Color(0xFF9E9E9E),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _create,
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF7FD4A0),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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

  Widget _buildVersionTypeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF363636)),
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
                      color: isSelected ? Colors.black : const Color(0xFF9E9E9E),
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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
