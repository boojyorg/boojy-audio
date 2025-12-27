import 'package:flutter/material.dart';
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
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
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
                const Text(
                  'Snapshots',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF9E9E9E)),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.snapshots.length} snapshot${widget.snapshots.length == 1 ? '' : 's'}',
              style: const TextStyle(
                color: Color(0xFF9E9E9E),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),

            // Snapshots list
            Expanded(
              child: widget.snapshots.isEmpty
                  ? _buildEmptyState()
                  : _buildSnapshotsList(),
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
                        ? const Color(0xFFF44336)
                        : const Color(0xFF616161),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('Delete'),
                ),

                // Right side buttons
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF9E9E9E),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                            ? const Color(0xFF7FD4A0)
                            : const Color(0xFF363636),
                        foregroundColor: _selectedSnapshot != null
                            ? Colors.black
                            : const Color(0xFF616161),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 64,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 16),
          const Text(
            'No snapshots yet',
            style: TextStyle(
              color: Color(0xFF9E9E9E),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create a snapshot to save the current state of your project',
            style: TextStyle(
              color: Color(0xFF616161),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSnapshotsList() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF363636)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListView.separated(
        itemCount: widget.snapshots.length + 1, // +1 for "Current Version"
        separatorBuilder: (context, index) => const Divider(
          height: 1,
          color: Color(0xFF363636),
        ),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildCurrentVersionTile();
          }

          final snapshot = widget.snapshots[index - 1];
          final isSelected = _selectedSnapshot?.id == snapshot.id;

          return _buildSnapshotTile(snapshot, isSelected);
        },
      ),
    );
  }

  Widget _buildCurrentVersionTile() {
    final isSelected = _selectedSnapshot == null;

    return InkWell(
      onTap: () => setState(() => _selectedSnapshot = null),
      child: Container(
        padding: const EdgeInsets.all(16),
        color: isSelected ? const Color(0xFF2A2A2A) : null,
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? const Color(0xFF7FD4A0) : const Color(0xFF616161),
              size: 20,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Version',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Working state',
                    style: TextStyle(
                      color: Color(0xFF9E9E9E),
                      fontSize: 13,
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

  Widget _buildSnapshotTile(Snapshot snapshot, bool isSelected) {
    return InkWell(
      onTap: () => setState(() => _selectedSnapshot = snapshot),
      child: Container(
        padding: const EdgeInsets.all(16),
        color: isSelected ? const Color(0xFF2A2A2A) : null,
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? const Color(0xFF7FD4A0) : const Color(0xFF616161),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    snapshot.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    snapshot.formattedDate,
                    style: const TextStyle(
                      color: Color(0xFF9E9E9E),
                      fontSize: 13,
                    ),
                  ),
                  if (snapshot.note != null && snapshot.note!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      snapshot.note!,
                      style: const TextStyle(
                        color: Color(0xFF757575),
                        fontSize: 12,
                      ),
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
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Delete Snapshot?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete "${snapshot.name}"?\n\nThis action cannot be undone.',
          style: const TextStyle(color: Color(0xFF9E9E9E)),
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
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFF44336),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
