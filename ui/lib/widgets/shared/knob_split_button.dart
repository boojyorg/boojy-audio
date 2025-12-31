import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';
import 'mini_knob.dart';

/// A split button with a knob popup for value adjustment.
///
/// Format: `[Label value][▼]`
/// - Left part: Shows label + current value, tap to **apply** the effect
/// - Right part (▼): Opens popup with MiniKnob to adjust value
///
/// Used for Swing, Humanize, Randomize, and Stretch controls.
class KnobSplitButton extends StatefulWidget {
  /// Label text (e.g., "Swing", "Humanize")
  final String label;

  /// Current value
  final double value;

  /// Minimum value
  final double min;

  /// Maximum value
  final double max;

  /// Format the value for display (e.g., "50%" or "×1.5")
  final String Function(double) valueFormatter;

  /// Called when value changes during knob drag
  final Function(double)? onChanged;

  /// Called when the left part (label) is tapped - applies the effect
  final VoidCallback? onApply;

  /// Optional icon to show before label
  final IconData? icon;

  /// Size of the knob in the popup
  final double knobSize;

  const KnobSplitButton({
    super.key,
    required this.label,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    required this.valueFormatter,
    this.onChanged,
    this.onApply,
    this.icon,
    this.knobSize = 40,
  });

  @override
  State<KnobSplitButton> createState() => _KnobSplitButtonState();
}

class _KnobSplitButtonState extends State<KnobSplitButton> {
  bool _isHoveringLabel = false;
  bool _isHoveringDropdown = false;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showKnobPopup() {
    _removeOverlay();

    _overlayEntry = OverlayEntry(
      builder: (context) => _KnobPopup(
        layerLink: _layerLink,
        value: widget.value,
        min: widget.min,
        max: widget.max,
        valueFormatter: widget.valueFormatter,
        knobSize: widget.knobSize,
        onChanged: widget.onChanged,
        onClose: _removeOverlay,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final displayValue = widget.valueFormatter(widget.value);

    return CompositedTransformTarget(
      link: _layerLink,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.dark,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Left side: Label + Value (clickable for apply action)
            MouseRegion(
              onEnter: (_) => setState(() => _isHoveringLabel = true),
              onExit: (_) => setState(() => _isHoveringLabel = false),
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.onApply,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isHoveringLabel
                        ? colors.textPrimary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(2),
                      bottomLeft: Radius.circular(2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(
                          widget.icon,
                          size: 12,
                          color: colors.textPrimary,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        '${widget.label} $displayValue',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Divider line
            Container(
              width: 1,
              height: 14,
              color: colors.textPrimary.withValues(alpha: 0.2),
            ),

            // Right side: Dropdown arrow (opens knob popup)
            MouseRegion(
              onEnter: (_) => setState(() => _isHoveringDropdown = true),
              onExit: (_) => setState(() => _isHoveringDropdown = false),
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _showKnobPopup,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isHoveringDropdown
                        ? colors.textPrimary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(2),
                      bottomRight: Radius.circular(2),
                    ),
                  ),
                  child: Icon(
                    Icons.arrow_drop_down,
                    size: 14,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The popup overlay containing the knob for value adjustment
class _KnobPopup extends StatefulWidget {
  final LayerLink layerLink;
  final double value;
  final double min;
  final double max;
  final String Function(double) valueFormatter;
  final double knobSize;
  final Function(double)? onChanged;
  final VoidCallback onClose;

  const _KnobPopup({
    required this.layerLink,
    required this.value,
    required this.min,
    required this.max,
    required this.valueFormatter,
    required this.knobSize,
    this.onChanged,
    required this.onClose,
  });

  @override
  State<_KnobPopup> createState() => _KnobPopupState();
}

class _KnobPopupState extends State<_KnobPopup> {
  late double _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Stack(
      children: [
        // Tap outside to close
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.opaque,
            child: Container(color: Colors.transparent),
          ),
        ),

        // The popup itself
        CompositedTransformFollower(
          link: widget.layerLink,
          offset: const Offset(0, 28), // Below the button
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.elevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colors.surface),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MiniKnob(
                    value: _currentValue,
                    min: widget.min,
                    max: widget.max,
                    size: widget.knobSize,
                    valueFormatter: widget.valueFormatter,
                    onChanged: (value) {
                      setState(() => _currentValue = value);
                      widget.onChanged?.call(value);
                    },
                  ),
                  const SizedBox(height: 6),
                  // Apply button
                  GestureDetector(
                    onTap: widget.onClose,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.accent,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'Apply',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
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
