import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/user_settings.dart';
import '../../theme/animation_constants.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
import '../../utils/native_dialogs.dart';

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
    final borderWidth = _isHovering ? 1.5 : 1.0;

    return GestureDetector(
      onTap: widget.onTap,
      onSecondaryTapUp: (details) => _showContextMenu(context, details),
      child: MouseRegion(
        onEnter: (_) {
          if (!_isHovering) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isHovering = true);
            });
          }
        },
        onExit: (_) {
          if (_isHovering) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isHovering = false);
            });
          }
        },
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          scale: _isHovering ? 1.02 : 1.0,
          duration: AnimationConstants.hoverDuration,
          child: AnimatedContainer(
            duration: AnimationConstants.hoverDuration,
            decoration: BoxDecoration(
              color: colors.darkest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isHovering
                    ? colors.accent.withValues(alpha: 0.6)
                    : colors.divider,
                width: borderWidth,
              ),
            ),
            // No clipBehavior on the bordered container (ragged-corner artifact;
            // see .claude/rules/flutter-ui.md) — clip the content at the inner
            // radius instead.
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8 - borderWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Thumbnail area
                  Expanded(
                    child: hasThumbnail
                        // cover (not contain) so the preview bleeds to the card
                        // edges; anchor top-centre so overflow crops the empty
                        // bottom of the arrangement, not the tracks.
                        ? Image.memory(
                            thumbnailFile.readAsBytesSync(),
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            errorBuilder: (_, __, ___) =>
                                _buildPlaceholder(context),
                          )
                        : _buildPlaceholder(context),
                  ),

                  // Name + metadata area — slightly lighter than thumbnail
                  ColoredBox(
                    color: colors.dark,
                    child: Padding(
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
                  ),

                  // Track count + BPM row
                  ColoredBox(
                    color: colors.dark,
                    child: Padding(
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
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
                  ),

                  // (The hover path row was cut — the path lives behind
                  // right-click → Reveal; hover feedback is border + scale.)
                ],
              ),
            ),
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
    // listen:false — a listening read inside a tap handler asserts in debug.
    final colors = context.themeProvider.colors;
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
            revealInFinderLabel,
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
}
