import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/project_metadata.dart';
import '../models/project_version.dart';
import '../models/version_type.dart';
import '../theme/theme_extension.dart';

/// Result type for project settings dialog
typedef ProjectSettingsResult = ({
  ProjectMetadata metadata,
  String? versionAction, // 'create' or 'restore'
  ProjectVersion? selectedVersion,
  ({String name, String? note, VersionType type})? newVersionData,
});

/// Project-specific settings dialog
/// Accessed via clicking on the project/song name in the transport bar
class ProjectSettingsDialog extends StatefulWidget {
  final ProjectMetadata metadata;
  final List<ProjectVersion> versions;
  final int? currentVersionNumber;
  final int nextVersionNumber;
  final Function(ProjectSettingsResult)? onSave;

  const ProjectSettingsDialog({
    super.key,
    required this.metadata,
    this.versions = const [],
    this.currentVersionNumber,
    this.nextVersionNumber = 1,
    this.onSave,
  });

  static Future<ProjectSettingsResult?> show(
    BuildContext context, {
    required ProjectMetadata metadata,
    List<ProjectVersion> versions = const [],
    int? currentVersionNumber,
    int nextVersionNumber = 1,
  }) {
    return showDialog<ProjectSettingsResult>(
      context: context,
      builder: (context) => ProjectSettingsDialog(
        metadata: metadata,
        versions: versions,
        currentVersionNumber: currentVersionNumber,
        nextVersionNumber: nextVersionNumber,
        onSave: (result) => Navigator.of(context).pop(result),
      ),
    );
  }

  @override
  State<ProjectSettingsDialog> createState() => _ProjectSettingsDialogState();
}

class _ProjectSettingsDialogState extends State<ProjectSettingsDialog> {
  late TextEditingController _nameController;
  late TextEditingController _styleController;
  late TextEditingController _bpmController;

  String _key = 'C';
  String _scale = 'Major';
  int _timeSignatureNumerator = 4;
  int _timeSignatureDenominator = 4;
  int _sampleRate = 48000;

  // Version selection
  ProjectVersion? _selectedVersion;

  @override
  void initState() {
    super.initState();

    // Initialize controllers with current metadata
    _nameController = TextEditingController(text: widget.metadata.name);
    _styleController = TextEditingController(text: widget.metadata.style ?? '');
    _bpmController = TextEditingController(text: widget.metadata.bpm.toStringAsFixed(0));

    _key = widget.metadata.key;
    _scale = widget.metadata.scale;
    _timeSignatureNumerator = widget.metadata.timeSignatureNumerator;
    _timeSignatureDenominator = widget.metadata.timeSignatureDenominator;
    _sampleRate = widget.metadata.sampleRate;

    // Select current version if any
    if (widget.currentVersionNumber != null && widget.currentVersionNumber! > 0) {
      _selectedVersion = widget.versions.where(
        (v) => v.versionNumber == widget.currentVersionNumber
      ).firstOrNull;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _styleController.dispose();
    _bpmController.dispose();
    super.dispose();
  }

  ProjectMetadata _buildUpdatedMetadata() {
    final bpm = double.tryParse(_bpmController.text) ?? 120.0;
    final clampedBpm = bpm.clamp(20.0, 300.0);
    final styleText = _styleController.text.trim();

    return widget.metadata.copyWith(
      name: _nameController.text.trim().isEmpty ? 'Untitled' : _nameController.text.trim(),
      style: styleText.isEmpty ? null : styleText,
      clearStyle: styleText.isEmpty,
      bpm: clampedBpm,
      timeSignatureNumerator: _timeSignatureNumerator,
      timeSignatureDenominator: _timeSignatureDenominator,
      key: _key,
      scale: _scale,
      sampleRate: _sampleRate,
      lastModified: DateTime.now(),
    );
  }

  void _save() {
    widget.onSave?.call((
      metadata: _buildUpdatedMetadata(),
      versionAction: null,
      selectedVersion: null,
      newVersionData: null,
    ));
  }

  void _restoreSelectedVersion() {
    if (_selectedVersion == null) return;

    widget.onSave?.call((
      metadata: _buildUpdatedMetadata(),
      versionAction: 'restore',
      selectedVersion: _selectedVersion,
      newVersionData: null,
    ));
  }

  void _createNewVersion() async {
    final result = await _showNewVersionDialog();
    if (result == null) return;

    widget.onSave?.call((
      metadata: _buildUpdatedMetadata(),
      versionAction: 'create',
      selectedVersion: null,
      newVersionData: result,
    ));
  }

  Future<({String name, String? note, VersionType type})?> _showNewVersionDialog() async {
    VersionType selectedType = VersionType.demo;
    final nameController = TextEditingController(
      text: selectedType.displayLabel(widget.nextVersionNumber),
    );
    final noteController = TextEditingController();
    String? errorMessage;

    return showDialog<({String name, String? note, VersionType type})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void updateSuggestedName(VersionType type) {
            final currentName = nameController.text.trim();
            final oldSuggested = selectedType.displayLabel(widget.nextVersionNumber);
            if (currentName == oldSuggested || currentName.isEmpty) {
              nameController.text = type.displayLabel(widget.nextVersionNumber);
            }
            setDialogState(() => selectedType = type);
          }

          return Dialog(
            backgroundColor: context.colors.darkest,
            child: Container(
              width: 400,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'New Version',
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: context.colors.textSecondary, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Type selector
                  Text(
                    'Type',
                    style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: context.colors.standard,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: context.colors.elevated),
                    ),
                    child: Row(
                      children: VersionType.values.map((type) {
                        final isSelected = type == selectedType;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => updateSuggestedName(type),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? type.color : Colors.transparent,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Center(
                                child: Text(
                                  type.displayName,
                                  style: TextStyle(
                                    color: isSelected ? Colors.black : context.colors.textSecondary,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Name field
                  Text(
                    'Name',
                    style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    style: TextStyle(color: context.colors.textPrimary),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: context.colors.standard,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: context.colors.elevated),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: context.colors.elevated),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: context.colors.accent),
                      ),
                      errorText: errorMessage,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (_) {
                      if (errorMessage != null) {
                        setDialogState(() => errorMessage = null);
                      }
                    },
                  ),
                  const SizedBox(height: 12),

                  // Note field
                  Text(
                    'Note (optional)',
                    style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    style: TextStyle(color: context.colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'e.g., Trying different arrangement',
                      hintStyle: TextStyle(color: context.colors.textMuted),
                      filled: true,
                      fillColor: context.colors.standard,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: context.colors.elevated),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: context.colors.elevated),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: context.colors.accent),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: context.colors.textSecondary,
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          final name = nameController.text.trim();
                          if (name.isEmpty) {
                            setDialogState(() => errorMessage = 'Please enter a name');
                            return;
                          }
                          if (widget.versions.any((v) => v.name.toLowerCase() == name.toLowerCase())) {
                            setDialogState(() => errorMessage = 'Name already exists');
                            return;
                          }
                          final note = noteController.text.trim();
                          Navigator.of(context).pop((
                            name: name,
                            note: note.isEmpty ? null : note,
                            type: selectedType,
                          ));
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: context.colors.accent,
                          foregroundColor: context.colors.darkest,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                        child: const Text('Create'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.colors.darkest,
      child: Container(
        width: 520,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header (fixed)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Project Settings',
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
            ),
            const SizedBox(height: 16),

            // Scrollable content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Project section
                    _buildSectionHeader(context, 'PROJECT'),
                    const SizedBox(height: 12),
                    _buildTextField(
                      context,
                      controller: _nameController,
                      label: 'Project Name',
                      hintText: 'My Song',
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      context,
                      controller: _styleController,
                      label: 'Style (optional)',
                      hintText: 'e.g., Travis Scott Type Beat',
                    ),
                    const SizedBox(height: 12),

                    // Created / Modified dates (read-only)
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Created',
                                style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.metadata.formattedCreatedDate,
                                style: TextStyle(color: context.colors.textMuted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Modified',
                                style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.metadata.formattedLastModified,
                                style: TextStyle(color: context.colors.textMuted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Tempo section
                    _buildSectionHeader(context, 'TEMPO'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            context,
                            controller: _bpmController,
                            label: 'BPM',
                            hintText: '120',
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                            ],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Time Signature',
                                style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildDropdown(
                                      context,
                                      value: _timeSignatureNumerator,
                                      items: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
                                      onChanged: (value) {
                                        setState(() => _timeSignatureNumerator = value!);
                                      },
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: Text(
                                      '/',
                                      style: TextStyle(color: context.colors.textPrimary, fontSize: 18),
                                    ),
                                  ),
                                  Expanded(
                                    child: _buildDropdown(
                                      context,
                                      value: _timeSignatureDenominator,
                                      items: [2, 4, 8, 16],
                                      onChanged: (value) {
                                        setState(() => _timeSignatureDenominator = value!);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Key section
                    _buildSectionHeader(context, 'KEY'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Root Note',
                                style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              _buildDropdown(
                                context,
                                value: _key,
                                items: ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'],
                                onChanged: (value) {
                                  setState(() => _key = value!);
                                },
                                displayString: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Scale',
                                style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              _buildDropdown(
                                context,
                                value: _scale,
                                items: ['Major', 'Minor'],
                                onChanged: (value) {
                                  setState(() => _scale = value!);
                                },
                                displayString: true,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Audio section
                    _buildSectionHeader(context, 'AUDIO'),
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sample Rate',
                          style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        _buildDropdown(
                          context,
                          value: _sampleRate,
                          items: [44100, 48000],
                          onChanged: (value) {
                            setState(() => _sampleRate = value!);
                          },
                          itemBuilder: (value) => '$value Hz',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Versions section
                    _buildSectionHeader(context, 'VERSIONS'),
                    const SizedBox(height: 12),
                    _buildVersionsList(context),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Action buttons (fixed at bottom)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: context.colors.textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _save,
                    style: TextButton.styleFrom(
                      backgroundColor: context.colors.accent,
                      foregroundColor: context.colors.darkest,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionsList(BuildContext context) {
    final hasVersions = widget.versions.isNotEmpty;
    final canRestore = _selectedVersion != null &&
        _selectedVersion!.versionNumber != widget.currentVersionNumber;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.standard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.colors.elevated),
      ),
      child: Column(
        children: [
          // Version list
          if (hasVersions)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.versions.length,
                itemBuilder: (context, index) {
                  final version = widget.versions[index];
                  final isCurrent = version.versionNumber == widget.currentVersionNumber;
                  final isSelected = version == _selectedVersion;

                  return InkWell(
                    onTap: () => setState(() => _selectedVersion = version),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? context.colors.accent.withOpacity(0.15)
                            : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: context.colors.elevated.withOpacity(0.5),
                            width: index < widget.versions.length - 1 ? 1 : 0,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Version type indicator
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: version.versionType.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          // Name and current indicator
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  version.name,
                                  style: TextStyle(
                                    color: context.colors.textPrimary,
                                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                                if (isCurrent) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: context.colors.accent.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'current',
                                      style: TextStyle(
                                        color: context.colors.accent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Date
                          Text(
                            version.formattedDateTime,
                            style: TextStyle(
                              color: context.colors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No versions saved yet',
                style: TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 13,
                ),
              ),
            ),

          // Action buttons
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: context.colors.elevated),
              ),
            ),
            child: Row(
              children: [
                // New Version button
                Expanded(
                  child: TextButton.icon(
                    onPressed: _createNewVersion,
                    icon: Icon(Icons.add, size: 18, color: context.colors.accent),
                    label: Text(
                      'New Version',
                      style: TextStyle(color: context.colors.accent),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Restore button
                Expanded(
                  child: TextButton.icon(
                    onPressed: canRestore ? _restoreSelectedVersion : null,
                    icon: Icon(
                      Icons.restore,
                      size: 18,
                      color: canRestore ? context.colors.textPrimary : context.colors.textMuted,
                    ),
                    label: Text(
                      'Restore',
                      style: TextStyle(
                        color: canRestore ? context.colors.textPrimary : context.colors.textMuted,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
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

  Widget _buildTextField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    String? hintText,
    List<TextInputFormatter>? inputFormatters,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: TextStyle(color: context.colors.textPrimary),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(color: context.colors.textMuted),
            filled: true,
            fillColor: context.colors.standard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: context.colors.elevated),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: context.colors.elevated),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: context.colors.accent),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          inputFormatters: inputFormatters,
          keyboardType: keyboardType,
        ),
      ],
    );
  }

  Widget _buildDropdown<T>(
    BuildContext context, {
    required T value,
    required List<T> items,
    required Function(T?) onChanged,
    String Function(T)? itemBuilder,
    bool displayString = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.colors.standard,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: context.colors.elevated),
      ),
      child: DropdownButton<T>(
        value: value,
        dropdownColor: context.colors.standard,
        underline: const SizedBox(),
        isExpanded: true,
        style: TextStyle(color: context.colors.textPrimary),
        items: items.map((item) {
          return DropdownMenuItem(
            value: item,
            child: Text(
              itemBuilder != null
                  ? itemBuilder(item)
                  : (displayString ? item.toString() : item.toString()),
            ),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }
}
