import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../audio_engine.dart';
import '../services/updater_service.dart';
import '../services/user_settings.dart';
import '../theme/app_colors.dart';
import '../theme/theme_extension.dart';
import '../theme/theme_provider.dart';

/// Unified app-wide settings dialog
///
/// Opened by clicking the logo "O" or File > Settings
class AppSettingsDialog extends StatefulWidget {
  final UserSettings settings;
  final AudioEngine? audioEngine;

  const AppSettingsDialog({
    super.key,
    required this.settings,
    this.audioEngine,
  });

  static Future<void> show(BuildContext context, UserSettings settings, {AudioEngine? audioEngine}) {
    return showDialog(
      context: context,
      builder: (context) => AppSettingsDialog(settings: settings, audioEngine: audioEngine),
    );
  }

  @override
  State<AppSettingsDialog> createState() => _AppSettingsDialogState();
}

class _AppSettingsDialogState extends State<AppSettingsDialog> {
  late BoojyTheme _selectedTheme;
  List<Map<String, dynamic>> _outputDevices = [];
  List<Map<String, dynamic>> _inputDevices = [];
  String? _selectedOutputDevice;
  String? _selectedInputDevice;
  String _selectedDriver = 'wasapi';
  bool _asioGuideExpanded = false;
  bool _autoCheckUpdates = true;
  String _appVersion = '';
  DateTime? _lastUpdateCheck;

  // Sidebar navigation state
  String _selectedSection = 'appearance';
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _sectionKeys = {
    'appearance': GlobalKey(),
    'audio': GlobalKey(),
    'midi': GlobalKey(),
    'saving': GlobalKey(),
    'projects': GlobalKey(),
    'updates': GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    _selectedTheme = BoojyThemeExtension.fromKey(widget.settings.theme);
    _loadAudioDevices();
    _loadUpdaterSettings();
  }

  Future<void> _loadUpdaterSettings() async {
    // Load app version
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = packageInfo.version;
      });
    }

    if (!UpdaterService.isSupported) return;
    final autoCheck = await UpdaterService.getAutoCheck();
    final lastCheck = await UpdaterService.getLastCheckDate();
    if (mounted) {
      setState(() {
        _autoCheckUpdates = autoCheck;
        _lastUpdateCheck = lastCheck;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSection(String sectionId) {
    setState(() => _selectedSection = sectionId);

    final key = _sectionKeys[sectionId];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Widget _buildSidebar() {
    final sections = [
      ('appearance', 'Appearance', Icons.palette_outlined),
      ('audio', 'Audio', Icons.volume_up_outlined),
      ('midi', 'MIDI', Icons.piano_outlined),
      ('saving', 'Saving', Icons.save_outlined),
      ('projects', 'Projects', Icons.folder_outlined),
      if (UpdaterService.isSupported)
        ('updates', 'Updates', Icons.system_update_outlined),
    ];

    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: sections.map((section) {
          final (id, label, icon) = section;
          final isSelected = _selectedSection == id;
          return _buildSidebarItem(id, label, icon, isSelected);
        }).toList(),
      ),
    );
  }

  Widget _buildSidebarItem(String id, String label, IconData icon, bool isSelected) {
    return InkWell(
      onTap: () => _scrollToSection(id),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? context.colors.accent.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? Border(left: BorderSide(color: context.colors.accent, width: 3))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? context.colors.accent : context.colors.textSecondary,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? context.colors.accent : context.colors.textPrimary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _loadAudioDevices() {
    // Load driver setting
    _selectedDriver = widget.settings.audioDriver;

    if (widget.audioEngine != null) {
      // Load output devices
      _outputDevices = widget.audioEngine!.getAudioOutputDevices();
      _selectedOutputDevice = widget.settings.preferredOutputDevice;

      // Load input devices
      _inputDevices = widget.audioEngine!.getAudioInputDevices();
      _selectedInputDevice = widget.settings.preferredInputDevice;

      debugPrint('AppSettings: Driver: $_selectedDriver');
      debugPrint('AppSettings: Loaded ${_outputDevices.length} output devices');
      debugPrint('AppSettings: Loaded ${_inputDevices.length} input devices');
      debugPrint('AppSettings: Selected output: $_selectedOutputDevice');
      debugPrint('AppSettings: Selected input: $_selectedInputDevice');
    } else {
      debugPrint('AppSettings: No audio engine provided');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.colors.darkest,
      child: Container(
        width: 850,
        height: 650,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(),
            const SizedBox(height: 24),

            // Main content: Sidebar + Scrollable content
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left sidebar
                  _buildSidebar(),
                  const SizedBox(width: 24),

                  // Right content area
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionWithKey('appearance', 'APPEARANCE', _buildAppearanceSettings()),
                          const SizedBox(height: 24),
                          _buildSectionWithKey('audio', 'AUDIO', _buildAudioSettings()),
                          const SizedBox(height: 24),
                          _buildSectionWithKey('midi', 'MIDI', _buildMidiSettings()),
                          const SizedBox(height: 24),
                          _buildSectionWithKey('saving', 'SAVING', _buildSavingSettings()),
                          const SizedBox(height: 24),
                          _buildSectionWithKey('projects', 'PROJECTS', _buildProjectSettings()),
                          if (UpdaterService.isSupported) ...[
                            const SizedBox(height: 24),
                            _buildSectionWithKey('updates', 'UPDATES', _buildUpdatesSettings()),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
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
    );
  }

  Widget _buildSectionWithKey(String id, String title, Widget content) {
    return Column(
      key: _sectionKeys[id],
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(title),
        const SizedBox(height: 12),
        content,
      ],
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
        // Audio Driver dropdown
        _buildAudioDriverSelector(),
        const SizedBox(height: 6),
        // Driver description
        Text(
          _getDriverDescription(_selectedDriver),
          style: TextStyle(
            color: context.colors.textMuted,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 12),

        // ASIO Guide (expandable)
        if (_selectedDriver == 'wasapi') ...[
          _buildAsioGuideExpander(),
          const SizedBox(height: 16),
        ],

        // Output Device dropdown
        _buildOutputDeviceSelector(),
        const SizedBox(height: 12),

        // Input Device dropdown
        _buildInputDeviceSelector(),
        const SizedBox(height: 12),

        // Buffer Size dropdown
        _buildBufferSizeSelector(),
      ],
    );
  }

  String _getDriverDescription(String driver) {
    switch (driver) {
      case 'wasapi':
        return '15-30ms latency • Works with all devices';
      case 'asio4all':
        return '5-15ms latency • Works with most devices';
      default:
        if (driver.toLowerCase().contains('asio')) {
          return '2-5ms latency • Professional audio interface';
        }
        return '';
    }
  }

  /// Get list of available audio drivers
  List<Map<String, String>> _getAvailableDrivers() {
    final drivers = <Map<String, String>>[
      {'id': 'wasapi', 'name': 'Windows Audio (WASAPI)', 'latency': '15-30ms'},
    ];

    // Check for ASIO devices in the output device list
    // ASIO devices typically have [ASIO] prefix or specific driver names
    final asioDevices = _outputDevices.where((d) {
      final name = (d['name'] as String).toLowerCase();
      return name.contains('asio');
    }).toList();

    // Add ASIO4ALL if any ASIO device is detected (user likely has it installed)
    // In a real implementation, we'd enumerate actual ASIO drivers
    if (asioDevices.isNotEmpty) {
      for (final device in asioDevices) {
        final name = device['name'] as String;
        drivers.add({
          'id': name.toLowerCase().replaceAll(' ', '_'),
          'name': name,
          'latency': '2-10ms',
        });
      }
    }

    return drivers;
  }

  Widget _buildAudioDriverSelector() {
    final drivers = _getAvailableDrivers();
    final currentDriver = drivers.firstWhere(
      (d) => d['id'] == _selectedDriver,
      orElse: () => drivers.first,
    );

    return Row(
      children: [
        Expanded(
          child: Text(
            'Audio Driver',
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
              value: currentDriver['id'],
              isExpanded: true,
              underline: Container(),
              dropdownColor: context.colors.standard,
              style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
              items: drivers.map((driver) {
                return DropdownMenuItem<String>(
                  value: driver['id'],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          driver['name']!,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        driver['latency']!,
                        style: TextStyle(
                          color: context.colors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null && value != _selectedDriver) {
                  setState(() {
                    _selectedDriver = value;
                  });
                  widget.settings.audioDriver = value;
                  // Reload devices for the new driver
                  _loadAudioDevices();
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAsioGuideExpander() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _asioGuideExpanded = !_asioGuideExpanded;
            });
          },
          child: Row(
            children: [
              Icon(
                _asioGuideExpanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: context.colors.accent,
              ),
              const SizedBox(width: 4),
              Text(
                'Want lower latency? Learn about ASIO',
                style: TextStyle(
                  color: context.colors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (_asioGuideExpanded) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colors.standard.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: context.colors.elevated.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ASIO provides 2-10ms latency vs 15-30ms with Windows Audio.\n'
                  'Essential for playing virtual instruments without delay.',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                // Audio interface option
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.colors.darkest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.settings_input_hdmi, size: 18, color: context.colors.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'I have an audio interface',
                              style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '(Focusrite, Universal Audio, PreSonus, etc.)',
                              style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Install the ASIO driver from manufacturer website',
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Built-in audio option
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.colors.darkest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.computer, size: 18, color: context.colors.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'I only have built-in computer audio',
                              style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Download ASIO4ALL (free): asio4all.org',
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'After installing, restart Boojy Audio to see new drivers.',
                  style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInputDeviceSelector() {
    // Build list: "No Input" + all input devices
    final deviceNames = <String>['__no_input__'];  // Special value for no input
    for (final device in _inputDevices) {
      deviceNames.add(device['name'] as String);
    }

    // Current value: null means "No Input"
    final currentValue = _selectedInputDevice ?? '__no_input__';

    return Row(
      children: [
        Expanded(
          child: Text(
            'Input',
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
              value: deviceNames.contains(currentValue) ? currentValue : '__no_input__',
              isExpanded: true,
              underline: Container(),
              dropdownColor: context.colors.standard,
              style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
              items: deviceNames.map((name) {
                String displayName;
                if (name == '__no_input__') {
                  displayName = 'No Input';
                } else {
                  // Check if this is the default device
                  final isDefault = _inputDevices.any((d) =>
                      d['name'] == name && d['isDefault'] == true);
                  displayName = isDefault ? '$name (Default)' : name;
                }

                return DropdownMenuItem<String>(
                  value: name,
                  child: Text(
                    displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedInputDevice = value == '__no_input__' ? null : value;
                  });
                  widget.settings.preferredInputDevice =
                      value == '__no_input__' ? null : value;
                  // TODO: Apply to audio engine when input device switching is implemented
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBufferSizeSelector() {
    // Buffer size options with calculated latency at 48kHz
    final bufferOptions = [
      {'samples': 64, 'ms': '1.3ms'},
      {'samples': 128, 'ms': '2.7ms'},
      {'samples': 256, 'ms': '5.3ms'},
      {'samples': 512, 'ms': '10.7ms'},
      {'samples': 1024, 'ms': '21.3ms'},
    ];

    final currentBufferSize = widget.settings.bufferSize;

    return Row(
      children: [
        Expanded(
          child: Text(
            'Buffer Size',
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
            child: DropdownButton<int>(
              value: currentBufferSize,
              isExpanded: true,
              underline: Container(),
              dropdownColor: context.colors.standard,
              style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
              items: bufferOptions.map((option) {
                final samples = option['samples'] as int;
                final ms = option['ms'] as String;
                return DropdownMenuItem<int>(
                  value: samples,
                  child: Text('$samples samples ($ms)'),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    widget.settings.bufferSize = value;
                  });
                  // TODO: Apply buffer size to audio engine
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Check if a device name suggests high latency (Bluetooth, wireless)
  bool _isHighLatencyDevice(String? deviceName) {
    if (deviceName == null || deviceName.isEmpty) return false;
    final lower = deviceName.toLowerCase();
    return lower.contains('bluetooth') ||
        lower.contains('airpods') ||
        lower.contains('wireless') ||
        lower.contains('bt ') ||
        lower.contains('arctis') ||  // SteelSeries Arctis (often wireless/BT)
        lower.contains('nova');       // Arctis Nova series
  }

  Widget _buildOutputDeviceSelector() {
    // Build list: "No Output" + all output devices
    final deviceNames = <String>['__no_output__'];  // Special value for no output
    for (final device in _outputDevices) {
      deviceNames.add(device['name'] as String);
    }

    // Current value: null means use system default, but we show first real device
    // Use special __no_output__ for explicit no output
    final currentValue = _selectedOutputDevice ?? '';
    final showWarning = _isHighLatencyDevice(_selectedOutputDevice);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Output',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: context.colors.standard,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: context.colors.elevated),
                      ),
                      child: DropdownButton<String>(
                        value: deviceNames.contains(currentValue) ? currentValue : (deviceNames.length > 1 ? deviceNames[1] : '__no_output__'),
                        isExpanded: true,
                        underline: Container(),
                        dropdownColor: context.colors.standard,
                        style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
                        items: deviceNames.map((name) {
                          String displayName;
                          if (name == '__no_output__') {
                            displayName = 'No Output';
                          } else {
                            // Check if this is the default device
                            final isDefault = _outputDevices.any((d) =>
                                d['name'] == name && d['isDefault'] == true);
                            displayName = isDefault ? '$name (Default)' : name;
                          }

                          return DropdownMenuItem<String>(
                            value: name,
                            child: Text(
                              displayName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedOutputDevice = value == '__no_output__' ? '__no_output__' : value;
                            });
                            // Save to settings
                            widget.settings.preferredOutputDevice =
                                value == '__no_output__' ? null : value;
                            // Apply to audio engine
                            if (widget.audioEngine != null && value != '__no_output__') {
                              widget.audioEngine!.setAudioOutputDevice(value);
                            }
                          }
                        },
                      ),
                    ),
                  ),
                  if (showWarning) ...[
                    const SizedBox(width: 8),
                    const Tooltip(
                      message: 'Bluetooth/wireless devices have high latency.\nUse a wired connection for recording.',
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.amber,
                        size: 20,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (showWarning) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 100),
            child: Text(
              'Bluetooth has 100-200ms latency. Use wired for recording.',
              style: TextStyle(
                color: Colors.amber.shade700,
                fontSize: 10,
              ),
            ),
          ),
        ],
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

  Widget _buildUpdatesSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Auto-check for updates
        _buildCheckboxSetting(
          label: 'Check for updates automatically',
          subtitle: 'Checks for new versions when the app starts',
          value: _autoCheckUpdates,
          onChanged: (value) async {
            final enabled = value ?? true;
            setState(() {
              _autoCheckUpdates = enabled;
            });
            await UpdaterService.setAutoCheck(enabled: enabled);
          },
        ),
        const SizedBox(height: 16),

        // Divider
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Divider(color: context.colors.divider, height: 1),
        ),
        const SizedBox(height: 16),

        // Version info
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  'Current version',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                _appVersion.isNotEmpty ? _appVersion : '...',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Last checked info
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  'Last checked',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                _formatLastCheckDate(_lastUpdateCheck),
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Manual check button
        Row(
          children: [
            const SizedBox(width: 32), // Align with checkbox labels
            TextButton.icon(
              onPressed: () async {
                await UpdaterService.checkForUpdates();
                // Refresh last check date after checking
                final lastCheck = await UpdaterService.getLastCheckDate();
                if (mounted) {
                  setState(() {
                    _lastUpdateCheck = lastCheck;
                  });
                }
              },
              icon: Icon(
                Icons.refresh,
                size: 16,
                color: context.colors.accent,
              ),
              label: Text(
                'Check for Updates Now',
                style: TextStyle(
                  color: context.colors.accent,
                  fontSize: 14,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Format the last update check date for display
  String _formatLastCheckDate(DateTime? date) {
    if (date == null) return 'Never';

    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      // Today
      final hour = date.hour;
      final minute = date.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return 'Today at $hour12:$minute $period';
    } else if (difference.inDays == 1) {
      // Yesterday
      final hour = date.hour;
      final minute = date.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return 'Yesterday at $hour12:$minute $period';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      // More than a week ago - show date
      return '${date.month}/${date.day}/${date.year}';
    }
  }

  Widget _buildCheckboxSetting({
    required String label,
    String? subtitle,
    required bool value,
    required ValueChanged<bool?> onChanged,
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
