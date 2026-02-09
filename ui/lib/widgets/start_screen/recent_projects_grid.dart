import 'package:flutter/material.dart';
import '../../services/user_settings.dart';
import '../../theme/theme_extension.dart';
import 'project_card.dart';

/// Responsive grid of recent project cards.
/// 2 columns on narrow widths, 3 on wider.
/// Includes header, empty state, and optional faint "+" card.
class RecentProjectsGrid extends StatelessWidget {
  final List<RecentProject> projects;
  final void Function(RecentProject project) onOpen;
  final void Function(RecentProject project) onRemove;
  final void Function(RecentProject project) onShowInFinder;
  final VoidCallback onNewProject;

  const RecentProjectsGrid({
    super.key,
    required this.projects,
    required this.onOpen,
    required this.onRemove,
    required this.onShowInFinder,
    required this.onNewProject,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.dark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.divider, width: 1),
      ),
      child: projects.isEmpty ? _buildEmptyState(context) : _buildGrid(context),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No recent projects',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a new project or open\nan existing one to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final colors = context.colors;
        // 3 columns when wider than 500px, otherwise 2
        final crossAxisCount = constraints.maxWidth > 500 ? 3 : 2;

        // Determine if we should show a faint "+" card
        final showPlusCard = projects.length.isOdd && projects.length < crossAxisCount * 4;
        final itemCount = projects.length + (showPlusCard ? 1 : 0);

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.4,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index < projects.length) {
              final project = projects[index];
              return ProjectCard(
                project: project,
                onTap: () => onOpen(project),
                onRemove: () => onRemove(project),
                onShowInFinder: () => onShowInFinder(project),
              );
            }

            // Faint "+" card
            return GestureDetector(
              onTap: onNewProject,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colors.divider.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.add,
                      size: 32,
                      color: colors.textMuted.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
