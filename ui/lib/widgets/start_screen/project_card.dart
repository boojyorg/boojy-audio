import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/user_settings.dart';
import '../../theme/animation_constants.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';

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
          duration: AnimationConstants.hoverDuration,
          decoration: BoxDecoration(
            color: _isHovering ? colors.hover : colors.standard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovering
                  ? colors.accent.withValues(alpha: 0.6)
                  : colors.divider,
              width: _isHovering ? 1.5 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Colour bar at top (4px, derived from project name hash)
              Container(height: 4, color: _projectColor(widget.project.name)),

              // Thumbnail area
              Expanded(
                child: hasThumbnail
                    ? Image.file(
                        thumbnailFile,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _buildPlaceholder(context),
                      )
                    : _buildPlaceholder(context),
              ),

              // Name + relative time row
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.project.name,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: BT.fontBody,
                          fontWeight: BT.weightSemiBold,
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
                        fontSize: BT.fontLabel,
                      ),
                    ),
                  ],
                ),
              ),

              // Track count + BPM row
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: Row(
                  children: [
                    if (widget.project.trackCount != null)
                      Text(
                        '${widget.project.trackCount} tracks',
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: BT.fontLabel,
                        ),
                      ),
                    if (widget.project.trackCount != null &&
                        widget.project.bpm != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '·',
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: BT.fontLabel,
                          ),
                        ),
                      ),
                    if (widget.project.bpm != null)
                      Text(
                        '${widget.project.bpm!.round()} BPM',
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: BT.fontLabel,
                        ),
                      ),
                  ],
                ),
              ),

              // Path row (visible on hover)
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: colors.divider, width: 0.5),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    _shortenPath(widget.project.path),
                    style: TextStyle(color: colors.textMuted, fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                crossFadeState: _isHovering
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: AnimationConstants.hoverDuration,
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
          BI.musicNote,
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
          child: Text(
            'Open',
            style: TextStyle(color: colors.textPrimary, fontSize: BT.fontBody),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'finder',
          child: Text(
            'Show in Finder',
            style: TextStyle(color: colors.textPrimary, fontSize: BT.fontBody),
          ),
        ),
        PopupMenuItem<String>(
          value: 'remove',
          child: Text(
            'Remove from Recent',
            style: TextStyle(color: colors.textPrimary, fontSize: BT.fontBody),
          ),
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

  /// Generate a colour from the project name hash for the card accent bar.
  static Color _projectColor(String name) {
    const palette = [
      Color(0xFFEF4444), // red
      Color(0xFFF97316), // orange
      Color(0xFF22C55E), // green
      Color(0xFF3B82F6), // blue
      Color(0xFF9775FA), // purple
      Color(0xFFEC4899), // pink
      Color(0xFF40B3E8), // cyan
      Color(0xFFFACC15), // yellow
    ];
    return palette[name.hashCode.abs() % palette.length];
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
