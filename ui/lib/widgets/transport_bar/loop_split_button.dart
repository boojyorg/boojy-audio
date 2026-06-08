import 'package:flutter/material.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';

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

  /// Whether any punch marker is set (drives the status text vs the chevron).
  bool get _hasPunch => widget.punchInEnabled || widget.punchOutEnabled;

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
    final leftBg = isActive ? colors.selectionFill : colors.surface;
    final iconColor = isActive ? colors.accent : colors.textSecondary;
    final textColor = isActive ? colors.textPrimary : colors.textSecondary;

    final tooltip = isActive
        ? 'Loop On (L) · Click right for punch options'
        : 'Loop Off (L)';

    return CompositedTransformTarget(
      link: _layerLink,
      child: Tooltip(
        message: tooltip,
        child: Container(
          key: _buttonKey,
          // Clip so the rounded corners never show a grey sliver of the bar
          // behind the zone fills. The outline turns a soft accent when engaged.
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BT.borderSm,
            border: Border.all(
              // Off-state outline reads with the same weight as the active
              // accent one (textMuted, not the near-invisible divider) — just
              // grey instead of blue.
              color: isActive ? colors.selectionBorder : colors.textMuted,
              width: 1,
            ),
          ),
          // Pinned to a shared height (not IntrinsicHeight) so Loop · Snap ·
          // Metronome align despite differing zone content; stretch then makes
          // the inter-zone divider span that full height (not the bar).
          child: SizedBox(
            height: BT.splitButtonHeight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left zone: icon + label (toggle loop)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) {
                    if (!_isLeftHovered) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _isLeftHovered = true);
                      });
                    }
                  },
                  onExit: (_) {
                    if (_isLeftHovered) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _isLeftHovered = false);
                      });
                    }
                  },
                  child: GestureDetector(
                    onTap: widget.onLoopToggle,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: BT.splitLeftPadding,
                      decoration: BoxDecoration(
                        color: _isLeftHovered
                            ? (isActive
                                  ? colors.accent.withValues(
                                      alpha: BT.opacityMedium,
                                    )
                                  : colors.textPrimary.withValues(
                                      alpha: BT.opacitySubtle,
                                    ))
                            : leftBg,
                        // When loop is off the button is a single plain pill
                        // (rounds all corners); when on, only the left corners
                        // round so the punch zone joins seamlessly on the right.
                        borderRadius: isActive
                            ? const BorderRadius.only(
                                topLeft: Radius.circular(BT.radiusSm),
                                bottomLeft: Radius.circular(BT.radiusSm),
                              )
                            : BT.borderSm,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(BI.loop, size: BT.iconMd, color: iconColor),
                          if (widget.showLabel) ...[
                            const SizedBox(width: BT.xs),
                            Text(
                              'Loop',
                              style: TextStyle(
                                color: textColor,
                                fontSize: BT.fontLabel,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                // Divider + punch zone only exist while looping — punch in/out is
                // meaningless when loop is off, so the resting button is a single
                // plain pill (no stray divider, no bare "|").
                if (isActive) ...[
                  Container(width: 1, color: colors.accent),
                  // Right zone: punch status (opens dropdown)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) {
                      if (!_isRightHovered) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _isRightHovered = true);
                        });
                      }
                    },
                    onExit: (_) {
                      if (_isRightHovered) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _isRightHovered = false);
                        });
                      }
                    },
                    child: GestureDetector(
                      onTap: _toggleOverlay,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        alignment: Alignment.center,
                        constraints: const BoxConstraints(minWidth: 33),
                        padding: BT.splitRightPadding,
                        decoration: BoxDecoration(
                          color: _isRightHovered
                              ? (isActive
                                    ? colors.accent.withValues(
                                        alpha: BT.opacityMedium,
                                      )
                                    : colors.textPrimary.withValues(
                                        alpha: BT.opacitySubtle,
                                      ))
                              : leftBg,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(BT.radiusSm),
                            bottomRight: Radius.circular(BT.radiusSm),
                          ),
                        ),
                        child: _hasPunch
                            // Punch markers set → show the →| / |→ / →|→ status.
                            ? Text(
                                _punchText,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.accent,
                                  fontSize: BT.fontLabel,
                                  fontWeight: BT.weightSemiBold,
                                ),
                              )
                            // No punch yet → an accent chevron that reads as
                            // "options", not a stray pipe.
                            : Icon(
                                BI.expandMore,
                                size: BT.iconMd,
                                color: colors.accent,
                              ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
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
      onEnter: (_) {
        if (!_isHovered) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _isHovered = true);
          });
        }
      },
      onExit: (_) {
        if (_isHovered) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _isHovered = false);
          });
        }
      },
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
                widget.isEnabled ? BI.checkBox : BI.checkBoxBlank,
                size: BT.iconMd,
                color: widget.isEnabled ? widget.accentColor : null,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.isEnabled ? widget.accentColor : null,
                  fontWeight: widget.isEnabled ? BT.weightSemiBold : null,
                  fontSize: BT.fontBody,
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
