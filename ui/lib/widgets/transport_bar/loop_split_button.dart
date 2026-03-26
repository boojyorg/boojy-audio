import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';

/// Loop split button with value-text design:
///   Left zone: icon + "Loop" label — toggles loop on/off
///   Right zone: punch status text — opens punch dropdown (stays open for multi-select)
class LoopSplitButton extends StatefulWidget {
  final bool loopEnabled;
  final bool punchInEnabled;
  final bool punchOutEnabled;
  final bool showLabel;
  final VoidCallback? onLoopToggle;
  final VoidCallback? onPunchInToggle;
  final VoidCallback? onPunchOutToggle;

  const LoopSplitButton({
    super.key,
    required this.loopEnabled,
    this.punchInEnabled = false,
    this.punchOutEnabled = false,
    this.showLabel = true,
    this.onLoopToggle,
    this.onPunchInToggle,
    this.onPunchOutToggle,
  });

  @override
  State<LoopSplitButton> createState() => _LoopSplitButtonState();
}

class _LoopSplitButtonState extends State<LoopSplitButton> {
  bool _isLeftHovered = false;
  bool _isRightHovered = false;
  OverlayEntry? _overlayEntry;
  final GlobalKey _buttonKey = GlobalKey();
  final LayerLink _layerLink = LayerLink();

  /// Punch status text for the right zone
  String get _punchText {
    if (widget.punchInEnabled && widget.punchOutEnabled) return '→|→';
    if (widget.punchInEnabled) return '→|';
    if (widget.punchOutEnabled) return '|→';
    return '|';
  }

  void _toggleOverlay() {
    if (_overlayEntry != null) {
      _dismissOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    _overlayEntry = OverlayEntry(
      builder: (context) => _PunchOverlay(
        link: _layerLink,
        punchInEnabled: widget.punchInEnabled,
        punchOutEnabled: widget.punchOutEnabled,
        onPunchInToggle: () {
          widget.onPunchInToggle?.call();
        },
        onPunchOutToggle: () {
          widget.onPunchOutToggle?.call();
        },
        onDismiss: _dismissOverlay,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _dismissOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void didUpdateWidget(LoopSplitButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rebuild overlay when punch state changes (so checkboxes update)
    if (_overlayEntry != null &&
        (oldWidget.punchInEnabled != widget.punchInEnabled ||
            oldWidget.punchOutEnabled != widget.punchOutEnabled)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _overlayEntry?.markNeedsBuild();
      });
    }
  }

  @override
  void dispose() {
    _dismissOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isActive = widget.loopEnabled;
    final leftBg = isActive
        ? colors.accent.withValues(alpha: 0.3)
        : Colors.transparent;
    final iconColor = isActive ? colors.accent : colors.textSecondary;
    final textColor = isActive ? colors.textPrimary : colors.textSecondary;

    final tooltip = isActive
        ? 'Loop On (L) · Click right for punch options'
        : 'Loop Off (L)';

    return CompositedTransformTarget(
      link: _layerLink,
      child: Tooltip(
        message: tooltip,
        child: DecoratedBox(
          key: _buttonKey,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: colors.divider, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Left zone: icon + label (toggle loop)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _isLeftHovered = true),
                onExit: (_) => setState(() => _isLeftHovered = false),
                child: GestureDetector(
                  onTap: widget.onLoopToggle,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _isLeftHovered
                          ? (isActive
                                ? colors.accent.withValues(alpha: 0.4)
                                : colors.textPrimary.withValues(alpha: 0.1))
                          : leftBg,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(2),
                        bottomLeft: Radius.circular(2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.loop, size: 16, color: iconColor),
                        if (widget.showLabel) ...[
                          const SizedBox(width: 5),
                          Text(
                            'Loop',
                            style: TextStyle(color: textColor, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // Divider
              Container(
                width: 1,
                height: 19,
                color: colors.textPrimary.withValues(alpha: 0.2),
              ),
              // Right zone: punch status text (opens dropdown)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _isRightHovered = true),
                onExit: (_) => setState(() => _isRightHovered = false),
                child: GestureDetector(
                  onTap: _toggleOverlay,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 33),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _isRightHovered
                          ? (isActive
                                ? colors.accent.withValues(alpha: 0.4)
                                : colors.textPrimary.withValues(alpha: 0.1))
                          : leftBg,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(2),
                        bottomRight: Radius.circular(2),
                      ),
                    ),
                    child: Text(
                      _punchText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isActive ? colors.accent : colors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Overlay popup for punch in/out — stays open for multi-select.
class _PunchOverlay extends StatelessWidget {
  final LayerLink link;
  final bool punchInEnabled;
  final bool punchOutEnabled;
  final VoidCallback? onPunchInToggle;
  final VoidCallback? onPunchOutToggle;
  final VoidCallback onDismiss;

  const _PunchOverlay({
    required this.link,
    required this.punchInEnabled,
    required this.punchOutEnabled,
    this.onPunchInToggle,
    this.onPunchOutToggle,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Stack(
      children: [
        // Dismiss on outside tap
        GestureDetector(
          onTap: onDismiss,
          behavior: HitTestBehavior.translucent,
          child: const SizedBox.expand(),
        ),
        // Popup positioned below the button
        CompositedTransformFollower(
          link: link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 4),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            color: colors.elevated,
            child: Container(
              constraints: const BoxConstraints(minWidth: 160),
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: colors.divider),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PunchOptionTile(
                    label: 'Punch In',
                    symbol: '→|',
                    isEnabled: punchInEnabled,
                    accentColor: colors.accent,
                    onTap: onPunchInToggle,
                  ),
                  _PunchOptionTile(
                    label: 'Punch Out',
                    symbol: '|→',
                    isEnabled: punchOutEnabled,
                    accentColor: colors.accent,
                    onTap: onPunchOutToggle,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PunchOptionTile extends StatefulWidget {
  final String label;
  final String symbol;
  final bool isEnabled;
  final Color accentColor;
  final VoidCallback? onTap;

  const _PunchOptionTile({
    required this.label,
    required this.symbol,
    required this.isEnabled,
    required this.accentColor,
    this.onTap,
  });

  @override
  State<_PunchOptionTile> createState() => _PunchOptionTileState();
}

class _PunchOptionTileState extends State<_PunchOptionTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: _isHovered ? colors.surface : Colors.transparent,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.isEnabled
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                size: 16,
                color: widget.isEnabled ? widget.accentColor : null,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.isEnabled ? widget.accentColor : null,
                  fontWeight: widget.isEnabled ? FontWeight.w600 : null,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                widget.symbol,
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
