import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/user_settings.dart';
import '../../services/updater_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extension.dart';
import 'recent_projects_grid.dart';

/// Result returned when the start screen modal is dismissed with an action.
class StartScreenResult {
  final StartScreenAction action;
  final String? projectPath;

  const StartScreenResult(this.action, [this.projectPath]);
}

enum StartScreenAction { newProject, openProject, openRecent, dismissed }

/// Modal overlay start screen shown on app launch and via File menu.
/// Two-column layout: left (branding + action buttons), right (recent projects grid).
class StartScreenModal extends StatefulWidget {
  final UserSettings userSettings;

  const StartScreenModal({super.key, required this.userSettings});

  /// Show the start screen modal and return the user's action.
  static Future<StartScreenResult?> show(BuildContext context, UserSettings userSettings) {
    return showDialog<StartScreenResult>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      barrierDismissible: true,
      builder: (context) => StartScreenModal(userSettings: userSettings),
    );
  }

  @override
  State<StartScreenModal> createState() => _StartScreenModalState();
}

class _StartScreenModalState extends State<StartScreenModal> {
  String _appVersion = '';
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _appVersion = info.version);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Modal sizing: ~70% width, ~75% height with min/max
        final modalWidth = constraints.maxWidth * 0.70;
        final modalHeight = constraints.maxHeight * 0.75;
        final width = modalWidth.clamp(700.0, 1200.0);
        final height = modalHeight.clamp(500.0, 800.0);

        return Center(
          child: Material(
            color: Colors.transparent,
            child: DropTarget(
              onDragEntered: (_) => setState(() => _isDragging = true),
              onDragExited: (_) => setState(() => _isDragging = false),
              onDragDone: (details) {
                setState(() => _isDragging = false);
                if (details.files.isNotEmpty) {
                  final path = details.files.first.path;
                  if (path.endsWith('.audio')) {
                    Navigator.of(context).pop(
                      StartScreenResult(StartScreenAction.openRecent, path),
                    );
                  }
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: colors.darkest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isDragging ? colors.accent : colors.divider,
                    width: _isDragging ? 2.0 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 32,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    children: [
                      // Close button row
                      _buildCloseButton(colors),

                      // Main content
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(32, 0, 32, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Left column: branding + buttons
                              SizedBox(
                                width: 200,
                                child: _buildLeftColumn(colors),
                              ),
                              const SizedBox(width: 32),

                              // Right column: recent projects grid
                              Expanded(
                                child: _buildRightColumn(),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Bottom bar: version + update checker
                      _buildBottomBar(colors),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCloseButton(BoojyColors colors) {
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, right: 8),
        child: IconButton(
          icon: Icon(Icons.close, size: 18, color: colors.textMuted),
          onPressed: () => Navigator.of(context).pop(
            const StartScreenResult(StartScreenAction.dismissed),
          ),
          splashRadius: 16,
          tooltip: 'Close',
        ),
      ),
    );
  }

  Widget _buildLeftColumn(BoojyColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),

        // App logo
        Image.asset(
          'assets/images/boojy-logo.png',
          width: 160,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 4),
        Image.asset(
          'assets/images/boojy_audio_text.png',
          width: 130,
          fit: BoxFit.contain,
        ),

        const SizedBox(height: 40),

        // Action buttons
        _ActionButton(
          icon: Icons.add,
          label: 'New Project',
          onTap: () => Navigator.of(context).pop(
            const StartScreenResult(StartScreenAction.newProject),
          ),
        ),
        const SizedBox(height: 10),
        _ActionButton(
          icon: Icons.folder_open,
          label: 'Open...',
          onTap: () => Navigator.of(context).pop(
            const StartScreenResult(StartScreenAction.openProject),
          ),
        ),
        const SizedBox(height: 10),
        _ActionButton(
          icon: Icons.settings,
          label: 'Settings',
          onTap: () {
            // Close modal first, then settings will be opened by DAW
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  Widget _buildRightColumn() {
    final colors = context.colors;
    final projects = widget.userSettings.recentProjects;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Recent Projects',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: RecentProjectsGrid(
            projects: projects,
            onOpen: (project) {
              Navigator.of(context).pop(
                StartScreenResult(StartScreenAction.openRecent, project.path),
              );
            },
            onRemove: (project) {
              widget.userSettings.removeRecentProject(project.path);
              setState(() {}); // Refresh grid
            },
            onShowInFinder: (project) {
              Process.run('open', ['-R', project.path]);
            },
            onNewProject: () => Navigator.of(context).pop(
              const StartScreenResult(StartScreenAction.newProject),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(BoojyColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 6, 32, 12),
      child: Row(
        children: [
          Text(
            _appVersion.isNotEmpty ? 'v$_appVersion' : '',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 13,
            ),
          ),
          if (UpdaterService.isSupported) ...[
            const SizedBox(width: 12),
            _UpdateButton(onTap: () => UpdaterService.checkForUpdates()),
          ],
        ],
      ),
    );
  }
}

/// Styled action button for the left column.
class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _isHovering ? colors.hover : colors.standard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovering ? colors.divider : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: _isHovering ? colors.textPrimary : colors.textSecondary,
              ),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: TextStyle(
                  color: _isHovering ? colors.textPrimary : colors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small styled button for "Check for updates" in the bottom bar.
class _UpdateButton extends StatefulWidget {
  final VoidCallback onTap;

  const _UpdateButton({required this.onTap});

  @override
  State<_UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<_UpdateButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _isHovering ? colors.hover : colors.standard,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _isHovering ? colors.divider : Colors.transparent,
              width: 1,
            ),
          ),
          child: Text(
            'Check for updates',
            style: TextStyle(
              color: _isHovering ? colors.textPrimary : colors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
