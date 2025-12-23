import 'package:flutter/material.dart';

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
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF404040)),
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
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFF404040)),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.keyboard,
                    color: Color(0xFF00BCD4),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Keyboard Shortcuts',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF9E9E9E)),
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
                    _buildSection('Transport', [
                      _Shortcut('Space', 'Play / Pause'),
                      _Shortcut('R', 'Start / Stop Recording'),
                      _Shortcut('.', 'Stop'),
                    ]),
                    const SizedBox(height: 20),
                    _buildSection('File', [
                      _Shortcut('\u2318 N', 'New Project'),
                      _Shortcut('\u2318 O', 'Open Project'),
                      _Shortcut('\u2318 S', 'Save Project'),
                      _Shortcut('\u21E7 \u2318 S', 'Save As'),
                      _Shortcut('\u2318 W', 'Close Project'),
                    ]),
                    const SizedBox(height: 20),
                    _buildSection('Edit', [
                      _Shortcut('\u2318 Z', 'Undo'),
                      _Shortcut('\u21E7 \u2318 Z', 'Redo'),
                      _Shortcut('\u2318 C', 'Copy'),
                      _Shortcut('\u2318 V', 'Paste'),
                      _Shortcut('\u2318 A', 'Select All'),
                      _Shortcut('Delete', 'Delete Selected'),
                    ]),
                    const SizedBox(height: 20),
                    _buildSection('View', [
                      _Shortcut('\u2318 L', 'Toggle Library Panel'),
                      _Shortcut('\u2318 M', 'Toggle Mixer Panel'),
                      _Shortcut('\u2318 E', 'Toggle Editor Panel'),
                      _Shortcut('\u2318 P', 'Toggle Virtual Piano'),
                      _Shortcut('\u2318 ,', 'Project Settings'),
                    ]),
                    const SizedBox(height: 20),
                    _buildSection('Piano Roll', [
                      _Shortcut('Click', 'Add Note'),
                      _Shortcut('Drag', 'Move Note'),
                      _Shortcut('Right Edge', 'Resize Note'),
                      _Shortcut('Right-Click', 'Delete Note'),
                      _Shortcut('Delete', 'Delete Selected Notes'),
                    ]),
                    const SizedBox(height: 20),
                    _buildSection('Virtual Piano', [
                      _Shortcut('Z X C V B', 'White Keys (C to G)'),
                      _Shortcut('S D  G H J', 'Black Keys'),
                      _Shortcut('Q W E R T', 'Higher Octave White Keys'),
                      _Shortcut('2 3  5 6 7', 'Higher Octave Black Keys'),
                    ]),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFF404040)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Press ',
                    style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
                  ),
                  _buildKeyBadge('?'),
                  const Text(
                    ' anytime to show this overlay',
                    style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<_Shortcut> shortcuts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF00BCD4),
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        ...shortcuts.map((s) => _buildShortcutRow(s)),
      ],
    );
  }

  Widget _buildShortcutRow(_Shortcut shortcut) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: _buildKeyCombo(shortcut.keys),
          ),
          Expanded(
            child: Text(
              shortcut.description,
              style: const TextStyle(
                color: Color(0xFFE0E0E0),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyCombo(String keys) {
    // Split by spaces to handle multi-key combos
    final parts = keys.split(' ');
    return Wrap(
      spacing: 4,
      children: parts.map((key) => _buildKeyBadge(key)).toList(),
    );
  }

  Widget _buildKeyBadge(String key) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF363636),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF505050)),
      ),
      child: Text(
        key,
        style: const TextStyle(
          color: Color(0xFFE0E0E0),
          fontSize: 12,
          fontFamily: 'SF Mono',
          fontFamilyFallback: ['Menlo', 'Consolas', 'monospace'],
          fontWeight: FontWeight.w500,
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
