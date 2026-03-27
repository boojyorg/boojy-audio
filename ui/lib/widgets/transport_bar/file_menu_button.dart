import 'package:flutter/material.dart';
import '../../theme/animation_constants.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
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
    final displayName = widget.projectName;

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
        PopupMenuItem<String>(
          value: 'new',
          child: Row(
            children: [
              Icon(BI.fileText, size: BT.iconLg),
              const SizedBox(width: 8),
              const Text('New Project'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'open',
          child: Row(
            children: [
              Icon(BI.folderOpen, size: BT.iconLg),
              const SizedBox(width: 8),
              const Text('Open Project...'),
            ],
          ),
        ),
        // Future: Open Recent submenu (v0.6.0)
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'save',
          child: Row(
            children: [
              Icon(BI.save, size: BT.iconLg),
              const SizedBox(width: 8),
              const Text('Save'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'save_as',
          child: Row(
            children: [
              Icon(BI.saveAs, size: BT.iconLg),
              const SizedBox(width: 8),
              const Text('Save As...'),
              const Spacer(),
              Text(
                '⇧⌘S',
                style: TextStyle(fontSize: 12, color: context.colors.textMuted),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        // Only show Rename and Save New Version when project has been saved
        if (widget.hasProject)
          PopupMenuItem<String>(
            value: 'rename',
            child: Row(
              children: [
                Icon(BI.rename, size: BT.iconLg),
                const SizedBox(width: 8),
                const Text('Rename...'),
              ],
            ),
          ),
        if (widget.hasProject)
          PopupMenuItem<String>(
            value: 'save_new_version',
            child: Row(
              children: [
                Icon(BI.history, size: BT.iconLg),
                const SizedBox(width: 8),
                const Text('Save New Version...'),
              ],
            ),
          ),
        if (widget.hasProject) const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'export_mp3',
          child: Row(
            children: [
              Icon(BI.musicNote, size: BT.iconLg),
              const SizedBox(width: 8),
              const Text('Export MP3'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'export_wav',
          child: Row(
            children: [
              Icon(BI.audioFile, size: BT.iconLg),
              const SizedBox(width: 8),
              const Text('Export WAV'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'export_audio',
          child: Row(
            children: [
              Icon(BI.settings, size: BT.iconLg),
              const SizedBox(width: 8),
              const Text('Export Audio...'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'export_midi',
          child: Row(
            children: [
              Icon(BI.piano, size: BT.iconLg),
              const SizedBox(width: 8),
              const Text('Export MIDI...'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'close',
          child: Row(
            children: [
              Icon(BI.close, size: BT.iconLg),
              const SizedBox(width: 8),
              const Text('Close Project'),
            ],
          ),
        ),
      ],
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: AnimationConstants.hoverDuration,
          padding: EdgeInsets.symmetric(
            horizontal: widget.mode == ButtonDisplayMode.narrow ? 8 : 12,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: _isHovered ? context.colors.elevated : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _isHovered
                  ? context.colors.textPrimary
                  : context.colors.textSecondary,
              fontSize: 14,
              fontWeight: BT.weightMedium,
            ),
          ),
        ),
      ),
    );
  }
}
