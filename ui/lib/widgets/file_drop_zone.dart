import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/boojy_icons.dart';
import '../theme/theme_extension.dart';
import '../theme/tokens.dart';
import 'shared/boojy_button.dart';
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

    if (result != null &&
        result.files.isNotEmpty &&
        result.files.first.path != null) {
      widget.onFileLoaded(result.files.first.path!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (widget.hasFile) {
      // Show minimal UI when file is loaded
      return Container(
        padding: const EdgeInsets.all(BT.sm),
        child: BoojyButton(
          icon: BI.folderOpen,
          label: 'Load Different File',
          onTap: _pickFile,
        ),
      );
    }

    // On iOS/mobile, show file picker button only (no drag-drop support)
    if (Platform.isIOS || Platform.isAndroid) {
      return _buildMobileFilePicker(colors);
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
              ? colors.success.withValues(alpha: 0.1)
              : colors.dark,
          border: Border.all(
            color: _isDragging ? colors.success : colors.divider,
            width: 2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
          borderRadius: BT.borderLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isDragging ? BI.upload : BI.audioFile,
              size: 64,
              color: _isDragging ? colors.success : colors.textMuted,
            ),
            const SizedBox(height: BT.lg),
            Text(
              _isDragging
                  ? 'Drop audio file here'
                  : 'Drag & drop audio file here',
              style: TextStyle(
                fontSize: BT.fontDisplay,
                fontWeight: BT.weightMedium,
                color: _isDragging ? colors.success : colors.textSecondary,
              ),
            ),
            const SizedBox(height: BT.sm),
            Text(
              'Supports: WAV, MP3, FLAC, AIF',
              style: TextStyle(
                fontSize: BT.fontBody,
                color: colors.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: BT.xl),
            Text(
              'or',
              style: TextStyle(fontSize: BT.fontBody, color: colors.textMuted),
            ),
            const SizedBox(height: BT.lg),
            BoojyButton(
              icon: BI.folderOpen,
              label: 'Browse Files',
              onTap: _pickFile,
            ),
          ],
        ),
      ),
    );
  }

  /// Mobile-friendly file picker UI (no drag-drop)
  Widget _buildMobileFilePicker(BoojyColors colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: colors.dark,
        border: Border.all(
          color: colors.divider,
          width: 2,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
        borderRadius: BT.borderLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(BI.audioFile, size: 64, color: colors.textMuted),
          const SizedBox(height: BT.lg),
          Text(
            'Import Audio File',
            style: TextStyle(
              fontSize: BT.fontDisplay,
              fontWeight: BT.weightMedium,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: BT.sm),
          Text(
            'Supports: WAV, MP3, FLAC, AIF',
            style: TextStyle(
              fontSize: BT.fontBody,
              color: colors.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: BT.xl),
          BoojyButton(
            icon: BI.folderOpen,
            label: 'Browse Files',
            onTap: _pickFile,
          ),
        ],
      ),
    );
  }
}
