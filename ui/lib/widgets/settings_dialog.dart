import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/user_settings.dart';
import '../services/auto_save_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_extension.dart';
import '../theme/theme_provider.dart';

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
  late BoojyTheme _selectedTheme;
  final _undoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _undoLimit = _settings.undoLimit;
    _autoSaveMinutes = _settings.autoSaveMinutes;
    _undoController.text = _undoLimit.toString();
    // Get current theme from provider
    _selectedTheme = BoojyThemeExtension.fromKey(_settings.theme);
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
    _settings.theme = _selectedTheme.key;

    // Apply theme to provider
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    themeProvider.setTheme(_selectedTheme);

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
          color: context.colors.standard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.divider),
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
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.colors.divider),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.settings,
                    color: context.colors.accent,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Settings',
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: context.colors.textSecondary),
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
                  // Appearance Section
                  _buildSectionHeader('Appearance'),
                  const SizedBox(height: 12),
                  _buildThemeDropdown(),

                  const SizedBox(height: 24),

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
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: context.colors.divider),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: context.colors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _saveSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.accent,
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
      style: TextStyle(
        color: context.colors.accent,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildUndoLimitField() {
    return Row(
      children: [
        Text(
          'Maximum undo steps:',
          style: TextStyle(
            color: context.colors.textPrimary,
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
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              filled: true,
              fillColor: context.colors.elevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: context.colors.hover),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: context.colors.hover),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: context.colors.accent),
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
        Text(
          '(10-500)',
          style: TextStyle(
            color: context.colors.textMuted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildThemeDropdown() {
    return Row(
      children: [
        Text(
          'Theme:',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: context.colors.elevated,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: context.colors.hover),
          ),
          child: DropdownButton<BoojyTheme>(
            value: _selectedTheme,
            dropdownColor: context.colors.elevated,
            underline: const SizedBox(),
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 14,
            ),
            items: BoojyTheme.values.map((theme) {
              return DropdownMenuItem<BoojyTheme>(
                value: theme,
                child: Text(theme.displayName),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedTheme = value;
                });
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAutoSaveDropdown() {
    return Row(
      children: [
        Text(
          'Save every:',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: context.colors.elevated,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: context.colors.hover),
          ),
          child: DropdownButton<int>(
            value: _autoSaveMinutes,
            dropdownColor: context.colors.elevated,
            underline: const SizedBox(),
            style: TextStyle(
              color: context.colors.textPrimary,
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
          color: context.colors.standard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.divider),
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
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.restore,
                    color: context.colors.warning,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Recover Unsaved Work?',
                    style: TextStyle(
                      color: context.colors.textPrimary,
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
                  Text(
                    'It looks like the app closed unexpectedly. A backup of your work was found:',
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.colors.elevated,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: context.colors.hover),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          color: context.colors.textSecondary,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Saved at: $_formattedDate',
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Would you like to recover this backup?',
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: context.colors.divider),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      'Start Fresh',
                      style: TextStyle(color: context.colors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.warning,
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
