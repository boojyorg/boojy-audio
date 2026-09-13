import 'package:flutter/material.dart';
import '../../theme/animation_constants.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
import '../shared/boojy_dropdown.dart';
import '../shared/boojy_tooltip.dart';

/// The project name as a plain text button; clicking it opens the project
/// menu (New, Open, Save, Export, Project Settings, Close). No chevron — the
/// hover lift and the tooltip say it's a menu, and it sits beside the equally
/// plain "Audio" app menu.
class FileMenuButton extends StatefulWidget {
  final String projectName;
  final bool hasProject;
  final VoidCallback? onNewProject;
  final VoidCallback? onOpenProject;
  final VoidCallback? onSaveProject;
  final VoidCallback? onSaveProjectAs;
  final VoidCallback? onRenameProject;
  final VoidCallback? onSaveNewVersion;
  final VoidCallback? onExportAudio;
  final VoidCallback? onProjectSettings;
  final VoidCallback? onCloseProject;

  const FileMenuButton({
    super.key,
    required this.projectName,
    this.hasProject = false,
    this.onNewProject,
    this.onOpenProject,
    this.onSaveProject,
    this.onSaveProjectAs,
    this.onRenameProject,
    this.onSaveNewVersion,
    this.onExportAudio,
    this.onProjectSettings,
    this.onCloseProject,
  });

  @override
  State<FileMenuButton> createState() => _FileMenuButtonState();
}

class _FileMenuButtonState extends State<FileMenuButton> {
  bool _isHovered = false;
  final GlobalKey _buttonKey = GlobalKey();

  Future<void> _showMenu(BuildContext context) async {
    final box = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlayBox == null) return;
    // Non-listening read: this runs from a tap handler (flutter-ui rules).
    final colors = context.themeProvider.colors;
    final anchor = Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlayBox),
      box.localToGlobal(
        box.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      ),
    );

    final selected = await showBoojyMenu<String>(
      context: context,
      anchor: anchor,
      items: [
        BoojyMenuItem(value: 'new', icon: BI.fileText, label: 'New Project'),
        BoojyMenuItem(
          value: 'open',
          icon: BI.folderOpen,
          label: 'Open Project…',
        ),
        const BoojyMenuDivider(),
        BoojyMenuItem(value: 'save', icon: BI.save, label: 'Save'),
        BoojyMenuItem(
          value: 'save_as',
          icon: BI.saveAs,
          label: 'Save As…',
          shortcut: '⇧⌘S',
        ),
        if (widget.hasProject) ...[
          const BoojyMenuDivider(),
          BoojyMenuItem(value: 'rename', icon: BI.rename, label: 'Rename…'),
          BoojyMenuItem(
            value: 'save_new_version',
            icon: BI.history,
            label: 'Save New Version…',
          ),
        ],
        const BoojyMenuDivider(),
        BoojyMenuItem(
          value: 'export_audio',
          icon: BI.waveform,
          label: 'Export Audio…',
        ),
        BoojyMenuItem(
          value: 'project_settings',
          icon: BI.settings,
          label: 'Project Settings…',
          shortcut: '⌘,',
        ),
        const BoojyMenuDivider(),
        BoojyMenuItem(value: 'close', icon: BI.close, label: 'Close Project'),
      ],
      selectedValue: null,
      colors: colors,
    );
    switch (selected) {
      case 'new':
        widget.onNewProject?.call();
      case 'open':
        widget.onOpenProject?.call();
      case 'save':
        widget.onSaveProject?.call();
      case 'save_as':
        widget.onSaveProjectAs?.call();
      case 'rename':
        widget.onRenameProject?.call();
      case 'save_new_version':
        widget.onSaveNewVersion?.call();
      case 'export_audio':
        widget.onExportAudio?.call();
      case 'project_settings':
        widget.onProjectSettings?.call();
      case 'close':
        widget.onCloseProject?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return BoojyTooltip(
      // The full name, since the slot truncates long ones.
      title: widget.projectName,
      description: 'Project menu',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (!_isHovered) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isHovered = true);
            });
          }
        },
        onExit: (_) {
          if (_isHovered) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isHovered = false);
            });
          }
        },
        child: GestureDetector(
          onTap: () => _showMenu(context),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            key: _buttonKey,
            duration: AnimationConstants.hoverDuration,
            // 6px, not 8: the only slack left in the 320px rail at 1280px
            // once the traffic-light inset grew to 81, and the difference
            // between "Untitled" and "Untitl…" at the default window.
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: _isHovered ? colors.elevated : Colors.transparent,
              borderRadius: BorderRadius.circular(BT.radiusMd),
            ),
            child: Text(
              widget.projectName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _isHovered ? colors.textPrimary : colors.textSecondary,
                fontSize: 14,
                fontWeight: BT.weightMedium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
