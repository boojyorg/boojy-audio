import 'package:flutter/material.dart';
import '../theme/boojy_icons.dart';
import '../theme/theme_extension.dart';
import '../theme/tokens.dart';

/// Modal overlay displaying all keyboard shortcuts organized by category
class KeyboardShortcutsOverlay extends StatelessWidget {
  const KeyboardShortcutsOverlay({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (context) => const KeyboardShortcutsOverlay(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 600),
        decoration: BoxDecoration(
          color: context.colors.dark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.surface),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.colors.surface),
                ),
              ),
              child: Row(
                children: [
                  Icon(BI.keyboard, color: context.colors.accent, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'Keyboard Shortcuts',
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 18,
                      fontWeight: BT.weightSemiBold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(BI.close, color: context.colors.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close (Esc)',
                  ),
                ],
              ),
            ),

            // Scrollable content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSection(context, 'Transport', [
                      _Shortcut('Space', 'Play / Pause'),
                      _Shortcut('R', 'Start / Stop Recording'),
                      _Shortcut('.', 'Stop'),
                      _Shortcut('L', 'Toggle Loop'),
                      _Shortcut('M', 'Toggle Metronome'),
                    ]),
                    const SizedBox(height: 20),
                    _buildSection(context, 'File', [
                      _Shortcut('\u2318 N', 'New Project'),
                      _Shortcut('\u2318 O', 'Open Project'),
                      _Shortcut('\u2318 S', 'Save Project'),
                      _Shortcut('\u21E7 \u2318 S', 'Save As'),
                      _Shortcut('\u2318 W', 'Close Project'),
                    ]),
                    const SizedBox(height: 20),
                    _buildSection(context, 'Edit', [
                      _Shortcut('\u2318 Z', 'Undo'),
                      _Shortcut('\u21E7 \u2318 Z', 'Redo'),
                      _Shortcut('\u2318 C', 'Copy'),
                      _Shortcut('\u2318 V', 'Paste'),
                      _Shortcut('\u2318 A', 'Select All'),
                      _Shortcut('Delete', 'Delete Selected'),
                    ]),
                    const SizedBox(height: 20),
                    _buildSection(context, 'View', [
                      _Shortcut('\u2318 L', 'Toggle Library Panel'),
                      _Shortcut('\u2318 M', 'Toggle Mixer Panel'),
                      _Shortcut('\u2318 E', 'Toggle Editor Panel'),
                      _Shortcut('\u2318 P', 'Toggle Virtual Piano'),
                      _Shortcut('\u2318 ,', 'Project Settings'),
                    ]),
                    const SizedBox(height: 20),
                    _buildSection(context, 'Piano Roll Tools', [
                      _Shortcut('Z', 'Draw Tool'),
                      _Shortcut('X', 'Select Tool'),
                      _Shortcut('C', 'Erase Tool'),
                      _Shortcut('V', 'Duplicate Tool'),
                      _Shortcut('B', 'Slice Tool'),
                      _Shortcut('Esc', 'Deselect All'),
                    ]),
                    const SizedBox(height: 20),
                    _buildSection(context, 'Piano Roll Modifiers', [
                      _Shortcut('Alt + Click', 'Delete Note'),
                      _Shortcut('\u2318 + Drag', 'Duplicate Note'),
                      _Shortcut('\u2318 + Click', 'Slice at Cursor'),
                      _Shortcut('Shift + Click', 'Add to Selection'),
                      _Shortcut('Delete', 'Delete Selected'),
                    ]),
                    const SizedBox(height: 20),
                    _buildSection(context, 'Piano Roll Actions', [
                      _Shortcut('Click', 'Add Note'),
                      _Shortcut('Drag', 'Move Note'),
                      _Shortcut('Edge Drag', 'Resize Note'),
                      _Shortcut('\u2318 D', 'Duplicate Selected'),
                      _Shortcut('\u2318 X', 'Cut Selected'),
                      _Shortcut('Q', 'Quantize Selected'),
                    ]),
                    const SizedBox(height: 20),
                    _buildSection(context, 'Virtual Piano', [
                      _Shortcut('A S D F G H J K L', 'White Keys'),
                      _Shortcut('W E  T Y U  O P', 'Black Keys'),
                    ]),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.colors.surface)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Press ',
                    style: TextStyle(
                      color: context.colors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  _buildKeyBadge(context, '?'),
                  Text(
                    ' anytime to show this overlay',
                    style: TextStyle(
                      color: context.colors.textMuted,
                      fontSize: 12,
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

  Widget _buildSection(
    BuildContext context,
    String title,
    List<_Shortcut> shortcuts,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: context.colors.accent,
            fontSize: 14,
            fontWeight: BT.weightSemiBold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        ...shortcuts.map((s) => _buildShortcutRow(context, s)),
      ],
    );
  }

  Widget _buildShortcutRow(BuildContext context, _Shortcut shortcut) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 150, child: _buildKeyCombo(context, shortcut.keys)),
          Expanded(
            child: Text(
              shortcut.description,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: BT.fontBody,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyCombo(BuildContext context, String keys) {
    // Split by spaces to handle multi-key combos
    final parts = keys.split(' ');
    return Wrap(
      spacing: 4,
      children: parts.map((key) => _buildKeyBadge(context, key)).toList(),
    );
  }

  Widget _buildKeyBadge(BuildContext context, String key) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: context.colors.divider),
      ),
      child: Text(
        key,
        style: TextStyle(
          color: context.colors.textPrimary,
          fontSize: 12,
          fontFamily: 'SF Mono',
          fontFamilyFallback: const ['Menlo', 'Consolas', 'monospace'],
          fontWeight: BT.weightMedium,
        ),
      ),
    );
  }
}

class _Shortcut {
  final String keys;
  final String description;

  _Shortcut(this.keys, this.description);
}
