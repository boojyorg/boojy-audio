import 'package:flutter/material.dart';

/// Dialog for creating a new project snapshot
class CreateSnapshotDialog extends StatefulWidget {
  final List<String> existingNames;

  const CreateSnapshotDialog({
    super.key,
    this.existingNames = const [],
  });

  static Future<({String name, String? note})?> show(
    BuildContext context, {
    List<String> existingNames = const [],
  }) {
    return showDialog<({String name, String? note})>(
      context: context,
      builder: (context) => CreateSnapshotDialog(
        existingNames: existingNames,
      ),
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
    if (widget.existingNames.any((n) => n.toLowerCase() == name.toLowerCase())) {
      setState(() => _errorMessage = 'A snapshot with this name already exists');
      return;
    }

    final note = _noteController.text.trim();

    Navigator.of(context).pop((
      name: name,
      note: note.isEmpty ? null : note,
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
                  'New Snapshot',
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
              'Save a snapshot of your current project',
              style: TextStyle(
                color: Color(0xFF9E9E9E),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),

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
                hintText: 'e.g., Chorus Idea 1',
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
