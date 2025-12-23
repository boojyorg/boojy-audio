import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/user_settings.dart';
import '../services/auto_save_service.dart';

/// Settings dialog for configuring user preferences
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (context) => const SettingsDialog(),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final _settings = UserSettings();
  late int _undoLimit;
  late int _autoSaveMinutes;
  final _undoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _undoLimit = _settings.undoLimit;
    _autoSaveMinutes = _settings.autoSaveMinutes;
    _undoController.text = _undoLimit.toString();
  }

  @override
  void dispose() {
    _undoController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    // Parse undo limit from text field
    final parsed = int.tryParse(_undoController.text);
    if (parsed != null) {
      _undoLimit = parsed.clamp(10, 500);
    }

    // Apply settings
    _settings.undoLimit = _undoLimit;
    _settings.autoSaveMinutes = _autoSaveMinutes;

    // Restart auto-save with new settings
    AutoSaveService().restart();

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 400,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF404040)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFF404040)),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.settings,
                    color: Color(0xFF00BCD4),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Settings',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF9E9E9E)),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close (Esc)',
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Undo History Section
                  _buildSectionHeader('Undo History'),
                  const SizedBox(height: 12),
                  _buildUndoLimitField(),

                  const SizedBox(height: 24),

                  // Auto-Save Section
                  _buildSectionHeader('Auto-Save'),
                  const SizedBox(height: 12),
                  _buildAutoSaveDropdown(),
                ],
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFF404040)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Color(0xFF9E9E9E)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _saveSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00BCD4),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Save Settings'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF00BCD4),
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildUndoLimitField() {
    return Row(
      children: [
        const Text(
          'Maximum undo steps:',
          style: TextStyle(
            color: Color(0xFFE0E0E0),
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 80,
          child: TextField(
            controller: _undoController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              filled: true,
              fillColor: const Color(0xFF363636),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF505050)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF505050)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF00BCD4)),
              ),
            ),
            onChanged: (value) {
              final parsed = int.tryParse(value);
              if (parsed != null) {
                setState(() {
                  _undoLimit = parsed.clamp(10, 500);
                });
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          '(10-500)',
          style: TextStyle(
            color: Color(0xFF808080),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildAutoSaveDropdown() {
    return Row(
      children: [
        const Text(
          'Save every:',
          style: TextStyle(
            color: Color(0xFFE0E0E0),
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF363636),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF505050)),
          ),
          child: DropdownButton<int>(
            value: _autoSaveMinutes,
            dropdownColor: const Color(0xFF363636),
            underline: const SizedBox(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
            items: UserSettings.autoSaveOptions.map((option) {
              return DropdownMenuItem<int>(
                value: option.minutes,
                child: Text(option.label),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _autoSaveMinutes = value;
                });
              }
            },
          ),
        ),
      ],
    );
  }
}

/// Recovery dialog shown when a crash recovery backup is found
class RecoveryDialog extends StatelessWidget {
  final String backupPath;
  final DateTime backupDate;

  const RecoveryDialog({
    super.key,
    required this.backupPath,
    required this.backupDate,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String backupPath,
    required DateTime backupDate,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (context) => RecoveryDialog(
        backupPath: backupPath,
        backupDate: backupDate,
      ),
    );
  }

  String get _formattedDate {
    return '${backupDate.year}-${backupDate.month.toString().padLeft(2, '0')}-${backupDate.day.toString().padLeft(2, '0')} '
        '${backupDate.hour.toString().padLeft(2, '0')}:${backupDate.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 400,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF404040)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                color: Color(0xFF3A3A3A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.restore,
                    color: Color(0xFFFF9800),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Recover Unsaved Work?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'It looks like the app closed unexpectedly. A backup of your work was found:',
                    style: TextStyle(
                      color: Color(0xFFE0E0E0),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF363636),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF505050)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          color: Color(0xFF9E9E9E),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Saved at: $_formattedDate',
                          style: const TextStyle(
                            color: Color(0xFFE0E0E0),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Would you like to recover this backup?',
                    style: TextStyle(
                      color: Color(0xFFE0E0E0),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFF404040)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text(
                      'Start Fresh',
                      style: TextStyle(color: Color(0xFF9E9E9E)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF9800),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Recover Backup'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
