import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/boojy_icons.dart';
import '../theme/theme_extension.dart';
import '../theme/tokens.dart';
import '../models/snapshot.dart';

/// Dialog for viewing and managing project snapshots
class SnapshotsListDialog extends StatefulWidget {
  final List<Snapshot> snapshots;
  final Function(Snapshot)? onLoad;
  final Function(Snapshot)? onDelete;

  const SnapshotsListDialog({
    super.key,
    required this.snapshots,
    this.onLoad,
    this.onDelete,
  });

  static Future<void> show(
    BuildContext context, {
    required List<Snapshot> snapshots,
    Function(Snapshot)? onLoad,
    Function(Snapshot)? onDelete,
  }) {
    return showDialog(
      context: context,
      builder: (context) => SnapshotsListDialog(
        snapshots: snapshots,
        onLoad: onLoad,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<SnapshotsListDialog> createState() => _SnapshotsListDialogState();
}

class _SnapshotsListDialogState extends State<SnapshotsListDialog> {
  Snapshot? _selectedSnapshot;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.elevated,
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Snapshots',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: BT.fontHeading,
                    fontWeight: BT.weightSemiBold,
                  ),
                ),
                IconButton(
                  icon: Icon(BI.close, color: colors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.snapshots.length} snapshot${widget.snapshots.length == 1 ? '' : 's'}',
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),

            // Snapshots list
            Expanded(
              child: widget.snapshots.isEmpty
                  ? _buildEmptyState(colors)
                  : _buildSnapshotsList(colors),
            ),

            const SizedBox(height: 16),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Delete button (left side)
                TextButton.icon(
                  onPressed: _selectedSnapshot != null
                      ? () => _confirmDelete(_selectedSnapshot!)
                      : null,
                  style: TextButton.styleFrom(
                    foregroundColor: _selectedSnapshot != null
                        ? colors.error
                        : colors.textMuted,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  icon: Icon(BI.delete, size: 18),
                  label: const Text('Delete'),
                ),

                // Right side buttons
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.textSecondary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: _selectedSnapshot != null
                          ? () => _loadSnapshot(_selectedSnapshot!)
                          : null,
                      style: TextButton.styleFrom(
                        backgroundColor: _selectedSnapshot != null
                            ? colors.accent
                            : colors.divider,
                        foregroundColor: _selectedSnapshot != null
                            ? Colors.black
                            : colors.textMuted,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Load'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BoojyColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            BI.list,
            size: 64,
            color: colors.textPrimary.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 16),
          Text(
            'No snapshots yet',
            style: TextStyle(color: colors.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a snapshot to save the current state of your project',
            style: TextStyle(color: colors.textMuted, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSnapshotsList(BoojyColors colors) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.divider),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListView.separated(
        itemCount: widget.snapshots.length + 1, // +1 for "Current Version"
        separatorBuilder: (context, index) =>
            Divider(height: 1, color: colors.divider),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildCurrentVersionTile(colors);
          }

          final snapshot = widget.snapshots[index - 1];
          final isSelected = _selectedSnapshot?.id == snapshot.id;

          return _buildSnapshotTile(snapshot, isSelected, colors);
        },
      ),
    );
  }

  Widget _buildCurrentVersionTile(BoojyColors colors) {
    final isSelected = _selectedSnapshot == null;

    return InkWell(
      onTap: () => setState(() => _selectedSnapshot = null),
      child: Container(
        padding: const EdgeInsets.all(16),
        color: isSelected ? colors.surface : null,
        child: Row(
          children: [
            Icon(
              isSelected ? BI.radioChecked : BI.circle,
              color: isSelected ? colors.accent : colors.textMuted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Version',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: BT.weightSemiBold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Working state',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: BT.fontBody,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSnapshotTile(
    Snapshot snapshot,
    bool isSelected,
    BoojyColors colors,
  ) {
    return InkWell(
      onTap: () => setState(() => _selectedSnapshot = snapshot),
      child: Container(
        padding: const EdgeInsets.all(16),
        color: isSelected ? colors.surface : null,
        child: Row(
          children: [
            Icon(
              isSelected ? BI.radioChecked : BI.circle,
              color: isSelected ? colors.accent : colors.textMuted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    snapshot.name,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: BT.weightMedium,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    snapshot.formattedDate,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: BT.fontBody,
                    ),
                  ),
                  if (snapshot.note != null && snapshot.note!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      snapshot.note!,
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _loadSnapshot(Snapshot snapshot) {
    widget.onLoad?.call(snapshot);
    Navigator.of(context).pop();
  }

  void _confirmDelete(Snapshot snapshot) {
    showDialog(
      context: context,
      builder: (context) {
        final colors = context.colors;
        return AlertDialog(
          backgroundColor: colors.elevated,
          title: Text(
            'Delete Snapshot?',
            style: TextStyle(color: colors.textPrimary),
          ),
          content: Text(
            'Are you sure you want to delete "${snapshot.name}"?\n\nThis action cannot be undone.',
            style: TextStyle(color: colors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close confirmation dialog
                widget.onDelete?.call(snapshot);
                setState(() => _selectedSnapshot = null);
              },
              style: TextButton.styleFrom(foregroundColor: colors.error),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}
