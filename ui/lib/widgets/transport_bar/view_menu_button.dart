import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';

/// View menu button that shows panel visibility toggles
class ViewMenuButton extends StatefulWidget {
  final bool libraryVisible;
  final bool mixerVisible;
  final bool editorVisible;
  final bool pianoVisible;
  final VoidCallback? onToggleLibrary;
  final VoidCallback? onToggleMixer;
  final VoidCallback? onToggleEditor;
  final VoidCallback? onTogglePiano;
  final VoidCallback? onResetPanelLayout;

  const ViewMenuButton({
    super.key,
    required this.libraryVisible,
    required this.mixerVisible,
    required this.editorVisible,
    required this.pianoVisible,
    this.onToggleLibrary,
    this.onToggleMixer,
    this.onToggleEditor,
    this.onTogglePiano,
    this.onResetPanelLayout,
  });

  @override
  State<ViewMenuButton> createState() => _ViewMenuButtonState();
}

class _ViewMenuButtonState extends State<ViewMenuButton> {
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  void _showMenu() {
    if (_isOpen) {
      _hideMenu();
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => _ViewMenuOverlay(
        layerLink: _layerLink,
        libraryVisible: widget.libraryVisible,
        mixerVisible: widget.mixerVisible,
        editorVisible: widget.editorVisible,
        pianoVisible: widget.pianoVisible,
        onToggleLibrary: () {
          widget.onToggleLibrary?.call();
          _rebuildOverlay();
        },
        onToggleMixer: () {
          widget.onToggleMixer?.call();
          _rebuildOverlay();
        },
        onToggleEditor: () {
          widget.onToggleEditor?.call();
          _rebuildOverlay();
        },
        onTogglePiano: () {
          widget.onTogglePiano?.call();
          _rebuildOverlay();
        },
        onResetPanelLayout: () {
          widget.onResetPanelLayout?.call();
          _hideMenu();
        },
        onDismiss: _hideMenu,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _rebuildOverlay() {
    // Rebuild the overlay with updated state
    _overlayEntry?.markNeedsBuild();
  }

  void _hideMenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) {
      setState(() => _isOpen = false);
    }
  }

  @override
  void didUpdateWidget(ViewMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If any visibility changed while menu is open, rebuild it after frame
    if (_isOpen && _overlayEntry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _overlayEntry != null) {
          _overlayEntry!.markNeedsBuild();
        }
      });
    }
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: IconButton(
        icon: Icon(
          Icons.visibility,
          color: _isOpen ? context.colors.accent : context.colors.textSecondary,
          size: 20,
        ),
        onPressed: _showMenu,
        tooltip: 'View',
      ),
    );
  }
}

/// Overlay content for the View menu
class _ViewMenuOverlay extends StatelessWidget {
  final LayerLink layerLink;
  final bool libraryVisible;
  final bool mixerVisible;
  final bool editorVisible;
  final bool pianoVisible;
  final VoidCallback? onToggleLibrary;
  final VoidCallback? onToggleMixer;
  final VoidCallback? onToggleEditor;
  final VoidCallback? onTogglePiano;
  final VoidCallback? onResetPanelLayout;
  final VoidCallback onDismiss;

  const _ViewMenuOverlay({
    required this.layerLink,
    required this.libraryVisible,
    required this.mixerVisible,
    required this.editorVisible,
    required this.pianoVisible,
    this.onToggleLibrary,
    this.onToggleMixer,
    this.onToggleEditor,
    this.onTogglePiano,
    this.onResetPanelLayout,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Dismiss layer - tapping outside closes the menu
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        // Menu positioned below the button
        CompositedTransformFollower(
          link: layerLink,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 4),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            color: context.colors.elevated,
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  _ViewMenuItem(
                    icon: Icons.library_music,
                    label: 'Show Library',
                    isChecked: libraryVisible,
                    onTap: onToggleLibrary,
                  ),
                  _ViewMenuItem(
                    icon: Icons.tune,
                    label: 'Show Mixer',
                    isChecked: mixerVisible,
                    onTap: onToggleMixer,
                  ),
                  _ViewMenuItem(
                    icon: Icons.piano,
                    label: 'Show Editor',
                    isChecked: editorVisible,
                    onTap: onToggleEditor,
                  ),
                  _ViewMenuItem(
                    icon: Icons.keyboard,
                    label: 'Show Virtual Piano',
                    isChecked: pianoVisible,
                    onTap: onTogglePiano,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Divider(height: 1, color: context.colors.surface),
                  ),
                  _ViewMenuItem(
                    icon: Icons.refresh,
                    label: 'Reset Panel Layout',
                    isChecked: false,
                    showCheckbox: false,
                    onTap: onResetPanelLayout,
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Individual menu item in View menu
class _ViewMenuItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isChecked;
  final bool showCheckbox;
  final VoidCallback? onTap;

  const _ViewMenuItem({
    required this.icon,
    required this.label,
    required this.isChecked,
    this.showCheckbox = true,
    this.onTap,
  });

  @override
  State<_ViewMenuItem> createState() => _ViewMenuItemState();
}

class _ViewMenuItemState extends State<_ViewMenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: _isHovered ? context.colors.surface : Colors.transparent,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showCheckbox) ...[
                SizedBox(
                  width: 20,
                  child: widget.isChecked
                      ? Icon(Icons.check, size: 16, color: context.colors.accent)
                      : null,
                ),
                const SizedBox(width: 8),
              ],
              Icon(widget.icon, size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 24),
            ],
          ),
        ),
      ),
    );
  }
}
