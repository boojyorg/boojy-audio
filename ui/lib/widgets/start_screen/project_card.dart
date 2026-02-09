import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/user_settings.dart';
import '../../theme/theme_extension.dart';

/// A card displaying a recent project with thumbnail, name, and relative time.
/// Hover shows metadata row. Right-click shows context menu.
class ProjectCard extends StatefulWidget {
  final RecentProject project;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback onShowInFinder;

  const ProjectCard({
    super.key,
    required this.project,
    required this.onTap,
    required this.onRemove,
    required this.onShowInFinder,
  });

  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final thumbnailPath = '${widget.project.path}/thumbnail.png';
    final thumbnailFile = File(thumbnailPath);
    final hasThumbnail = thumbnailFile.existsSync();

    return GestureDetector(
      onTap: widget.onTap,
      onSecondaryTapUp: (details) => _showContextMenu(context, details),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _isHovering ? colors.hover : colors.standard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovering ? colors.accent.withValues(alpha: 0.6) : colors.divider,
              width: _isHovering ? 1.5 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Thumbnail area
              Expanded(
                child: hasThumbnail
                    ? Image.file(
                        thumbnailFile,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildPlaceholder(context),
                      )
                    : _buildPlaceholder(context),
              ),

              // Name + relative time row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.project.name,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _relativeTime(widget.project.openedAt),
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // Metadata row (visible on hover)
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: colors.divider, width: 0.5),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    _shortenPath(widget.project.path),
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 10,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                crossFadeState: _isHovering
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 150),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.darkest,
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 32,
          color: colors.textMuted.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, TapUpDetails details) {
    final colors = context.colors;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      color: colors.elevated,
      items: [
        PopupMenuItem<String>(
          value: 'open',
          child: Text('Open', style: TextStyle(color: colors.textPrimary, fontSize: 13)),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'finder',
          child: Text('Show in Finder', style: TextStyle(color: colors.textPrimary, fontSize: 13)),
        ),
        PopupMenuItem<String>(
          value: 'remove',
          child: Text('Remove from Recent', style: TextStyle(color: colors.textPrimary, fontSize: 13)),
        ),
      ],
    ).then((value) {
      if (value == 'open') {
        widget.onTap();
      } else if (value == 'finder') {
        widget.onShowInFinder();
      } else if (value == 'remove') {
        widget.onRemove();
      }
    });
  }

  /// Format a DateTime as a relative time string (e.g. "1d", "2w", "3m")
  static String _relativeTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo';
    return '${(diff.inDays / 365).floor()}y';
  }

  /// Shorten a path for display (replace home dir with ~)
  static String _shortenPath(String path) {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty && path.startsWith(home)) {
      return '~${path.substring(home.length)}';
    }
    return path;
  }
}
