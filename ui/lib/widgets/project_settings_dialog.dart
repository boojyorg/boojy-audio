import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/project_metadata.dart';

/// Project-specific settings dialog
/// Accessed via File menu → Project Settings
class ProjectSettingsDialog extends StatefulWidget {
  final ProjectMetadata metadata;
  final Function(ProjectMetadata)? onSave;

  const ProjectSettingsDialog({
    super.key,
    required this.metadata,
    this.onSave,
  });

  static Future<ProjectMetadata?> show(
    BuildContext context,
    ProjectMetadata metadata,
  ) {
    return showDialog<ProjectMetadata>(
      context: context,
      builder: (context) => ProjectSettingsDialog(
        metadata: metadata,
        onSave: (updated) => Navigator.of(context).pop(updated),
      ),
    );
  }

  @override
  State<ProjectSettingsDialog> createState() => _ProjectSettingsDialogState();
}

class _ProjectSettingsDialogState extends State<ProjectSettingsDialog> {
  late TextEditingController _nameController;
  late TextEditingController _bpmController;

  String _key = 'C';
  String _scale = 'Major';
  int _timeSignatureNumerator = 4;
  int _timeSignatureDenominator = 4;
  int _sampleRate = 48000;

  @override
  void initState() {
    super.initState();

    // Initialize controllers with current metadata
    _nameController = TextEditingController(text: widget.metadata.name);
    _bpmController = TextEditingController(text: widget.metadata.bpm.toStringAsFixed(0));

    _key = widget.metadata.key;
    _scale = widget.metadata.scale;
    _timeSignatureNumerator = widget.metadata.timeSignatureNumerator;
    _timeSignatureDenominator = widget.metadata.timeSignatureDenominator;
    _sampleRate = widget.metadata.sampleRate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bpmController.dispose();
    super.dispose();
  }

  void _save() {
    // Validate BPM
    final bpm = double.tryParse(_bpmController.text) ?? 120.0;
    final clampedBpm = bpm.clamp(20.0, 300.0);

    final updated = ProjectMetadata(
      name: _nameController.text.trim().isEmpty ? 'Untitled' : _nameController.text.trim(),
      bpm: clampedBpm,
      timeSignatureNumerator: _timeSignatureNumerator,
      timeSignatureDenominator: _timeSignatureDenominator,
      key: _key,
      scale: _scale,
      sampleRate: _sampleRate,
    );

    widget.onSave?.call(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      child: Container(
        width: 500,
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
                  'Project Settings',
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
            const SizedBox(height: 24),

            // Project Name
            _buildSectionHeader('PROJECT'),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _nameController,
              label: 'Project Name',
              hintText: 'My Song',
            ),
            const SizedBox(height: 24),

            // Tempo
            _buildSectionHeader('TEMPO'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
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
                      const Text(
                        'Time Signature',
                        style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDropdown(
                              value: _timeSignatureNumerator,
                              items: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
                              onChanged: (value) {
                                setState(() => _timeSignatureNumerator = value!);
                              },
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '/',
                              style: TextStyle(color: Colors.white, fontSize: 18),
                            ),
                          ),
                          Expanded(
                            child: _buildDropdown(
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

            // Key
            _buildSectionHeader('KEY'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Root Note',
                        style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      _buildDropdown(
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
                      const Text(
                        'Scale',
                        style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      _buildDropdown(
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

            // Sample Rate
            _buildSectionHeader('AUDIO'),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sample Rate',
                  style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
                ),
                const SizedBox(height: 4),
                _buildDropdown(
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
                  onPressed: _save,
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF7FD4A0),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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

  Widget _buildSectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF9E9E9E),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 1,
          color: const Color(0xFF363636),
        ),
      ],
    );
  }

  Widget _buildTextField({
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
          style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hintText,
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
          inputFormatters: inputFormatters,
          keyboardType: keyboardType,
        ),
      ],
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<T> items,
    required Function(T?) onChanged,
    String Function(T)? itemBuilder,
    bool displayString = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF363636)),
      ),
      child: DropdownButton<T>(
        value: value,
        dropdownColor: const Color(0xFF2A2A2A),
        underline: const SizedBox(),
        isExpanded: true,
        style: const TextStyle(color: Colors.white),
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
