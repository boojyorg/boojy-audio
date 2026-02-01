import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';
import '../shared/pill_toggle_button.dart' show ButtonDisplayMode;

/// File menu button showing project name with dropdown menu
class FileMenuButton extends StatefulWidget {
  final String projectName;
  final bool hasProject;
  final ButtonDisplayMode mode;
  final VoidCallback? onNewProject;
  final VoidCallback? onOpenProject;
  final VoidCallback? onSaveProject;
  final VoidCallback? onSaveProjectAs;
  final VoidCallback? onRenameProject;
  final VoidCallback? onSaveNewVersion;
  final VoidCallback? onExportAudio;
  final VoidCallback? onExportMp3;
  final VoidCallback? onExportWav;
  final VoidCallback? onExportMidi;
  final VoidCallback? onCloseProject;

  const FileMenuButton({
    super.key,
    required this.projectName,
    this.hasProject = false,
    required this.mode,
    this.onNewProject,
    this.onOpenProject,
    this.onSaveProject,
    this.onSaveProjectAs,
    this.onRenameProject,
    this.onSaveNewVersion,
    this.onExportAudio,
    this.onExportMp3,
    this.onExportWav,
    this.onExportMidi,
    this.onCloseProject,
  });

  @override
  State<FileMenuButton> createState() => _FileMenuButtonState();
}

class _FileMenuButtonState extends State<FileMenuButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    // Truncate based on mode: narrow = shorter truncation
    final maxLength = widget.mode == ButtonDisplayMode.narrow ? 8 : 20;
    final displayName = widget.projectName.length > maxLength
        ? '${widget.projectName.substring(0, maxLength - 2)}...'
        : widget.projectName;

    return PopupMenuButton<String>(
      tooltip: 'File Menu',
      offset: const Offset(0, 40),
      onSelected: (String value) {
        switch (value) {
          case 'new':
            widget.onNewProject?.call();
            break;
          case 'open':
            widget.onOpenProject?.call();
            break;
          case 'save':
            widget.onSaveProject?.call();
            break;
          case 'save_as':
            widget.onSaveProjectAs?.call();
            break;
          case 'rename':
            widget.onRenameProject?.call();
            break;
          case 'save_new_version':
            widget.onSaveNewVersion?.call();
            break;
          case 'export_audio':
            widget.onExportAudio?.call();
            break;
          case 'export_mp3':
            widget.onExportMp3?.call();
            break;
          case 'export_wav':
            widget.onExportWav?.call();
            break;
          case 'export_midi':
            widget.onExportMidi?.call();
            break;
          case 'close':
            widget.onCloseProject?.call();
            break;
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'new',
          child: Row(
            children: [
              Icon(Icons.description, size: 18),
              SizedBox(width: 8),
              Text('New Project'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'open',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 18),
              SizedBox(width: 8),
              Text('Open Project...'),
            ],
          ),
        ),
        // TODO: Open Recent submenu would go here
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'save',
          child: Row(
            children: [
              Icon(Icons.save, size: 18),
              SizedBox(width: 8),
              Text('Save'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'save_as',
          child: Row(
            children: [
              Icon(Icons.save_as, size: 18),
              SizedBox(width: 8),
              Text('Save As...'),
              Spacer(),
              Text('⇧⌘S', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        // Only show Rename and Save New Version when project has been saved
        if (widget.hasProject)
          const PopupMenuItem<String>(
            value: 'rename',
            child: Row(
              children: [
                Icon(Icons.drive_file_rename_outline, size: 18),
                SizedBox(width: 8),
                Text('Rename...'),
              ],
            ),
          ),
        if (widget.hasProject)
          const PopupMenuItem<String>(
            value: 'save_new_version',
            child: Row(
              children: [
                Icon(Icons.history, size: 18),
                SizedBox(width: 8),
                Text('Save New Version...'),
              ],
            ),
          ),
        if (widget.hasProject)
          const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'export_mp3',
          child: Row(
            children: [
              Icon(Icons.music_note, size: 18),
              SizedBox(width: 8),
              Text('Export MP3'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'export_wav',
          child: Row(
            children: [
              Icon(Icons.audio_file, size: 18),
              SizedBox(width: 8),
              Text('Export WAV'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'export_audio',
          child: Row(
            children: [
              Icon(Icons.settings, size: 18),
              SizedBox(width: 8),
              Text('Export Audio...'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'export_midi',
          child: Row(
            children: [
              Icon(Icons.piano, size: 18),
              SizedBox(width: 8),
              Text('Export MIDI...'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'close',
          child: Row(
            children: [
              Icon(Icons.close, size: 18),
              SizedBox(width: 8),
              Text('Close Project'),
            ],
          ),
        ),
      ],
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: widget.mode == ButtonDisplayMode.narrow ? 8 : 12,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: _isHovered
                ? context.colors.elevated
                : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            displayName,
            style: TextStyle(
              color: _isHovered
                  ? context.colors.textPrimary
                  : context.colors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
