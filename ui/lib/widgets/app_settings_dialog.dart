import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/user_settings.dart';
import '../theme/app_colors.dart';
import '../theme/theme_extension.dart';
import '../theme/theme_provider.dart';

/// Unified app-wide settings dialog
///
/// Opened by clicking the logo "O" or File > Settings
class AppSettingsDialog extends StatefulWidget {
  final UserSettings settings;

  const AppSettingsDialog({
    super.key,
    required this.settings,
  });

  static Future<void> show(BuildContext context, UserSettings settings) {
    return showDialog(
      context: context,
      builder: (context) => AppSettingsDialog(settings: settings),
    );
  }

  @override
  State<AppSettingsDialog> createState() => _AppSettingsDialogState();
}

class _AppSettingsDialogState extends State<AppSettingsDialog> {
  late BoojyTheme _selectedTheme;

  @override
  void initState() {
    super.initState();
    _selectedTheme = BoojyThemeExtension.fromKey(widget.settings.theme);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.colors.darkest,
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Settings',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: context.colors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Settings content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // APPEARANCE section
                    _buildSectionHeader('APPEARANCE'),
                    const SizedBox(height: 12),
                    _buildAppearanceSettings(),
                    const SizedBox(height: 24),

                    // AUDIO section
                    _buildSectionHeader('AUDIO'),
                    const SizedBox(height: 12),
                    _buildAudioSettings(),
                    const SizedBox(height: 24),

                    // MIDI section
                    _buildSectionHeader('MIDI'),
                    const SizedBox(height: 12),
                    _buildMidiSettings(),
                    const SizedBox(height: 24),

                    // SAVING section
                    _buildSectionHeader('SAVING'),
                    const SizedBox(height: 12),
                    _buildSavingSettings(),
                    const SizedBox(height: 24),

                    // PROJECTS section
                    _buildSectionHeader('PROJECTS'),
                    const SizedBox(height: 12),
                    _buildProjectSettings(),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Close button
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  backgroundColor: context.colors.accent,
                  foregroundColor: context.colors.darkest,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: context.colors.accent,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 1,
          color: context.colors.elevated,
        ),
      ],
    );
  }

  Widget _buildAppearanceSettings() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Theme',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.colors.standard,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: context.colors.elevated),
            ),
            child: DropdownButton<BoojyTheme>(
              value: _selectedTheme,
              isExpanded: true,
              underline: Container(),
              dropdownColor: context.colors.standard,
              style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
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
                  // Save to settings
                  widget.settings.theme = value.key;
                  // Apply theme immediately
                  final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
                  themeProvider.setTheme(value);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAudioSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sample Rate
        _buildDropdownSetting(
          label: 'Sample Rate',
          value: widget.settings.sampleRate.toString(),
          items: const ['44100', '48000'],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                widget.settings.sampleRate = int.parse(value);
              });
            }
          },
          formatLabel: (value) => value == '44100' ? '44.1 kHz' : '48 kHz',
        ),
        const SizedBox(height: 12),

        // Buffer Size
        _buildDropdownSetting(
          label: 'Buffer Size',
          value: widget.settings.bufferSize.toString(),
          items: const ['128', '256', '512', '1024'],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                widget.settings.bufferSize = int.parse(value);
              });
            }
          },
          formatLabel: (value) => '$value samples',
        ),
      ],
    );
  }

  Widget _buildMidiSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'MIDI Input',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.colors.standard,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: context.colors.elevated),
                ),
                child: Text(
                  'All Devices',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'MIDI device selection is handled in the transport bar',
          style: TextStyle(
            color: context.colors.textMuted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildSavingSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Auto-save checkbox and interval
        Row(
          children: [
            Checkbox(
              value: widget.settings.autoSaveMinutes > 0,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    widget.settings.autoSaveMinutes = 5; // Default to 5 minutes
                  } else {
                    widget.settings.autoSaveMinutes = 0; // Disable
                  }
                });
              },
              activeColor: context.colors.accent,
            ),
            Text(
              'Auto-save',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 16),
            if (widget.settings.autoSaveMinutes > 0) ...[
              Text(
                'Every',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 80,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.colors.standard,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: context.colors.elevated),
                ),
                child: DropdownButton<int>(
                  value: widget.settings.autoSaveMinutes,
                  isExpanded: true,
                  underline: Container(),
                  dropdownColor: context.colors.standard,
                  style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1')),
                    DropdownMenuItem(value: 2, child: Text('2')),
                    DropdownMenuItem(value: 5, child: Text('5')),
                    DropdownMenuItem(value: 10, child: Text('10')),
                    DropdownMenuItem(value: 15, child: Text('15')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        widget.settings.autoSaveMinutes = value;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'minutes',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildProjectSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Continue where I left off
        _buildCheckboxSetting(
          label: 'Continue where I left off',
          subtitle: 'Restores zoom, scroll, and panel visibility',
          value: widget.settings.continueWhereLeftOff,
          onChanged: (value) {
            setState(() {
              widget.settings.continueWhereLeftOff = value ?? true;
            });
          },
        ),
        const SizedBox(height: 16),

        // Copy samples to project folder
        _buildCheckboxSetting(
          label: 'Copy imported samples to project folder',
          subtitle: 'Prevents missing files if samples are moved or deleted',
          value: widget.settings.copySamplesToProject,
          onChanged: (value) {
            setState(() {
              widget.settings.copySamplesToProject = value ?? true;
            });
          },
        ),
      ],
    );
  }

  Widget _buildDropdownSetting({
    required String label,
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
    String Function(String)? formatLabel,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.colors.standard,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: context.colors.elevated),
            ),
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              underline: Container(),
              dropdownColor: context.colors.standard,
              style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
              items: items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(formatLabel?.call(item) ?? item),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckboxSetting({
    required String label,
    String? subtitle,
    required bool value,
    required void Function(bool?) onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
          activeColor: context.colors.accent,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 14,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
