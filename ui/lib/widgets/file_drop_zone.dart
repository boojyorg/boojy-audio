import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';

/// File drop zone widget for importing audio files
class FileDropZone extends StatefulWidget {
  final Function(String path) onFileLoaded;
  final bool hasFile;

  const FileDropZone({
    super.key,
    required this.onFileLoaded,
    this.hasFile = false,
  });

  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  bool _isDragging = false;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'flac', 'aif', 'aiff'],
      dialogTitle: 'Select Audio File',
    );

    if (result != null && result.files.single.path != null) {
      widget.onFileLoaded(result.files.single.path!);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hasFile) {
      // Show minimal UI when file is loaded
      return Container(
        padding: const EdgeInsets.all(8),
        child: ElevatedButton.icon(
          onPressed: _pickFile,
          icon: const Icon(Icons.folder_open, size: 16),
          label: const Text('Load Different File'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF404040),
            foregroundColor: const Color(0xFFA0A0A0),
          ),
        ),
      );
    }

    // On iOS/mobile, show file picker button only (no drag-drop support)
    if (Platform.isIOS || Platform.isAndroid) {
      return _buildMobileFilePicker();
    }

    // Show drop zone when no file loaded (desktop only)
    return DropTarget(
      onDragEntered: (details) {
        setState(() {
          _isDragging = true;
        });
      },
      onDragExited: (details) {
        setState(() {
          _isDragging = false;
        });
      },
      onDragDone: (details) {
        setState(() {
          _isDragging = false;
        });

        if (details.files.isNotEmpty) {
          final file = details.files.first;
          widget.onFileLoaded(file.path);
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: _isDragging
              ? const Color(0xFF4CAF50).withValues(alpha: 0.1)
              : const Color(0xFF2B2B2B),
          border: Border.all(
            color: _isDragging
                ? const Color(0xFF4CAF50)
                : const Color(0xFF404040),
            width: 2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isDragging ? Icons.cloud_upload : Icons.audio_file,
              size: 64,
              color: _isDragging
                  ? const Color(0xFF4CAF50)
                  : const Color(0xFF606060),
            ),
            const SizedBox(height: 16),
            Text(
              _isDragging
                  ? 'Drop audio file here'
                  : 'Drag & drop audio file here',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: _isDragging
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFF808080),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Supports: WAV, MP3, FLAC, AIF',
              style: TextStyle(
                fontSize: 14,
                color: const Color(0xFF606060),
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'or',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF606060),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Browse Files'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA0A0A0),
                foregroundColor: const Color(0xFF2B2B2B),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mobile-friendly file picker UI (no drag-drop)
  Widget _buildMobileFilePicker() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2B2B),
        border: Border.all(
          color: const Color(0xFF404040),
          width: 2,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.audio_file,
            size: 64,
            color: Color(0xFF606060),
          ),
          const SizedBox(height: 16),
          const Text(
            'Import Audio File',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Color(0xFF808080),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Supports: WAV, MP3, FLAC, AIF',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF606060),
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.folder_open),
            label: const Text('Browse Files'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFA0A0A0),
              foregroundColor: const Color(0xFF2B2B2B),
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

