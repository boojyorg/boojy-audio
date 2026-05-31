import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../theme/theme_extension.dart';

/// Height of the macOS title strip that sits above the transport bar. Tuned to
/// the native titlebar band so the traffic lights (which `window_manager` can't
/// reposition) land vertically centred within it.
const double kMacTitleStripHeight = 28.0;

/// True when the app draws its own thin title strip in place of the native
/// title bar — macOS only. Windows/web keep their native title bar, so the
/// strip is not drawn and reserves no space.
bool get hasMacTitleStrip =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// A thin, full-window-width strip above the transport bar (macOS). It hosts the
/// native traffic lights on the left and a window-centred project title
/// ("Project — Boojy Audio"). Because the strip spans the whole window (no
/// asymmetric side columns), the title centres against the window — unlike an
/// in-bar centred title wedged between unequal sidebar/mixer widths.
class MacTitleStrip extends StatelessWidget {
  final String projectName;

  const MacTitleStrip({super.key, required this.projectName});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: kMacTitleStripHeight,
      // Solid bar-coloured fill so the strip reads as one connected chrome with
      // the transport bar below — and, painted over the bar (see the Stack order
      // in daw_screen), it masks the bar's upward shadow bleed so there's no
      // seam between the two.
      color: colors.dark,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Whole strip is a window-drag region; the title sits on top but is
          // click-through so dragging works anywhere across the strip.
          const DragToMoveArea(child: SizedBox.expand()),
          Align(
            alignment: Alignment.center,
            // The system font sits ascent-heavy in its line box, which optically
            // pulls the title toward the top of the strip; a 1px downward nudge
            // re-centres it against the traffic lights.
            child: Transform.translate(
              offset: const Offset(0, 1),
              child: IgnorePointer(
                child: Text(
                  '$projectName — Boojy Audio',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    // macOS-only strip → use the native system UI font (San
                    // Francisco) rather than the bundled Inter, so the title
                    // reads like a standard macOS window title.
                    fontFamily: '.AppleSystemUIFont',
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
