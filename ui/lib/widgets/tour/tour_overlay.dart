import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/animation_constants.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
import 'tour_controller.dart';
import 'tour_step.dart';
import 'tour_scrim_painter.dart';

/// Full-screen overlay that displays the guided tour.
/// Shows a scrim with spotlight cutout + tooltip card for each step.
class TourOverlay extends StatefulWidget {
  final TourController controller;
  final VoidCallback onComplete;
  final VoidCallback onSkip;

  const TourOverlay({
    super.key,
    required this.controller,
    required this.onComplete,
    required this.onSkip,
  });

  @override
  State<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<TourOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: AnimationConstants.panelDuration,
      vsync: this,
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: AnimationConstants.standardCurve,
    );
    _animController.forward();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _animController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!widget.controller.isActive) {
      // Tour ended
      _animController.reverse().then((_) {
        widget.onComplete();
      });
    } else {
      // Step changed — fade transition
      _animController.forward(from: 0.0);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.controller.currentStep;
    final spotlightRect = _getSpotlightRect(step);
    final colors = context.colors;

    return FadeTransition(
      opacity: _fadeAnim,
      child: KeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            widget.controller.skip();
            widget.onSkip();
          }
        },
        child: Stack(
          children: [
            // Scrim with spotlight cutout — absorbs all taps
            Positioned.fill(
              child: GestureDetector(
                onTap: () {}, // absorb taps
                behavior: HitTestBehavior.opaque,
                child: CustomPaint(
                  painter: TourScrimPainter(
                    spotlightRect: spotlightRect,
                    borderColor: colors.accent.withValues(
                      alpha: BT.opacityStrong,
                    ),
                  ),
                ),
              ),
            ),
            // Tooltip card
            _buildTooltipCard(step, spotlightRect, colors),
          ],
        ),
      ),
    );
  }

  Rect? _getSpotlightRect(TourStep step) {
    if (step.targetKey == null) return null;

    final renderBox =
        step.targetKey!.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return null;

    final position = renderBox.localToGlobal(Offset.zero);
    const padding = 8.0;
    return Rect.fromLTWH(
      position.dx - padding,
      position.dy - padding,
      renderBox.size.width + padding * 2,
      renderBox.size.height + padding * 2,
    );
  }

  Widget _buildTooltipCard(TourStep step, Rect? spotlightRect, dynamic colors) {
    final screenSize = MediaQuery.of(context).size;

    // Position the tooltip relative to spotlight, or center on screen
    double left;
    double top;

    if (spotlightRect != null) {
      switch (step.placement) {
        case TourPlacement.below:
          left = spotlightRect.left;
          top = spotlightRect.bottom + 12;
        case TourPlacement.above:
          left = spotlightRect.left;
          top = spotlightRect.top - 12 - 180; // approximate card height
        case TourPlacement.left:
          left = spotlightRect.left - 12 - 320;
          top = spotlightRect.top;
        case TourPlacement.right:
          left = spotlightRect.right + 12;
          top = spotlightRect.top;
      }
      // Clamp to screen bounds
      left = left.clamp(16.0, screenSize.width - 336.0);
      top = top.clamp(16.0, screenSize.height - 200.0);
    } else {
      // Centered on screen
      left = (screenSize.width - 320) / 2;
      top = (screenSize.height - 180) / 2;
    }

    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(BT.lg),
        decoration: BoxDecoration(
          color: context.colors.elevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.divider),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            Text(
              step.title,
              style: TextStyle(
                color: context.colors.accent,
                fontSize: BT.fontBody + 1,
                fontWeight: BT.weightSemiBold,
              ),
            ),
            const SizedBox(height: BT.sm),
            // Description
            Text(
              step.description,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: BT.fontBody,
                height: 1.5,
              ),
            ),
            const SizedBox(height: BT.lg),
            // Footer: step indicator + buttons
            Row(
              children: [
                Text(
                  '${widget.controller.currentIndex + 1} of ${widget.controller.totalSteps}',
                  style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: BT.fontLabel,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    widget.controller.skip();
                    widget.onSkip();
                  },
                  child: Text(
                    'Skip Tour',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: BT.fontLabel,
                    ),
                  ),
                ),
                const SizedBox(width: BT.sm),
                ElevatedButton(
                  onPressed: widget.controller.next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: BT.lg,
                      vertical: BT.sm,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: Text(
                    widget.controller.isLastStep ? 'Done' : 'Next',
                    style: const TextStyle(
                      fontSize: BT.fontLabel,
                      fontWeight: BT.weightSemiBold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
