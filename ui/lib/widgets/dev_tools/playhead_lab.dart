import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extension.dart';

/// Border treatment for the playhead grabber.
enum PlayheadBorder {
  none('None'),
  white('White'),
  darkGrey('Dark grey'),
  blue('Blue (accent)');

  const PlayheadBorder(this.label);
  final String label;
}

/// Fill treatment for the playhead grabber.
enum PlayheadFill {
  stateColor('State (white/grey)'),
  buttonBlue('Button grey-blue');

  const PlayheadFill(this.label);
  final String label;
}

/// Where the grabber triangle sits within the loop/ruler band.
enum PlayheadAnchor {
  top('Top of bar'),
  bottom('Bottom of bar');

  const PlayheadAnchor(this.label);
  final String label;
}

/// Live, debug-only styling choices for the timeline playhead grabber.
/// Mutated by [PlayheadLabSwitcher] (Cmd+Shift+H) and read directly by
/// [UnifiedNavBarPainter], which repaints via `super(repaint: PlayheadLab.notifier)`.
/// Once a combination is chosen, bake it in as the defaults and the lab can go.
class PlayheadLabConfig {
  final PlayheadBorder border;
  final PlayheadFill fill;
  final PlayheadAnchor anchor;

  const PlayheadLabConfig({
    this.border = PlayheadBorder.darkGrey,
    this.fill = PlayheadFill.stateColor,
    this.anchor = PlayheadAnchor.top,
  });

  PlayheadLabConfig copyWith({
    PlayheadBorder? border,
    PlayheadFill? fill,
    PlayheadAnchor? anchor,
  }) => PlayheadLabConfig(
    border: border ?? this.border,
    fill: fill ?? this.fill,
    anchor: anchor ?? this.anchor,
  );
}

/// Global holder so the painter can read the current choice without threading
/// a parameter through every nav-bar call site (debug tooling only).
class PlayheadLab {
  PlayheadLab._();
  static final ValueNotifier<PlayheadLabConfig> notifier =
      ValueNotifier<PlayheadLabConfig>(const PlayheadLabConfig());
}

/// Draggable, barrier-less overlay for A/B-ing the playhead grabber's border
/// and vertical position live. Mirrors [UiLabsSwitcher].
class PlayheadLabSwitcher extends StatefulWidget {
  final VoidCallback onClose;

  const PlayheadLabSwitcher({super.key, required this.onClose});

  @override
  State<PlayheadLabSwitcher> createState() => _PlayheadLabSwitcherState();
}

class _PlayheadLabSwitcherState extends State<PlayheadLabSwitcher> {
  Offset _position = const Offset(20, 64);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _position += d.delta),
        child: Material(
          elevation: 16,
          borderRadius: BorderRadius.circular(8),
          color: colors.elevated,
          child: Container(
            width: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.divider),
            ),
            child: ValueListenableBuilder<PlayheadLabConfig>(
              valueListenable: PlayheadLab.notifier,
              builder: (context, config, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(colors),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildGroupLabel(colors, 'Fill'),
                          for (final f in PlayheadFill.values)
                            _buildRow(
                              colors,
                              label: f.label,
                              isActive: config.fill == f,
                              onTap: () => PlayheadLab.notifier.value = config
                                  .copyWith(fill: f),
                            ),
                          const SizedBox(height: 8),
                          _buildGroupLabel(colors, 'Border'),
                          for (final b in PlayheadBorder.values)
                            _buildRow(
                              colors,
                              label: b.label,
                              isActive: config.border == b,
                              onTap: () => PlayheadLab.notifier.value = config
                                  .copyWith(border: b),
                            ),
                          const SizedBox(height: 8),
                          _buildGroupLabel(colors, 'Position'),
                          for (final a in PlayheadAnchor.values)
                            _buildRow(
                              colors,
                              label: a.label,
                              isActive: config.anchor == a,
                              onTap: () => PlayheadLab.notifier.value = config
                                  .copyWith(anchor: a),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BoojyColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          Icon(Icons.science_outlined, size: 16, color: colors.textSecondary),
          const SizedBox(width: 8),
          Text(
            'Playhead Lab',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: widget.onClose,
            child: Icon(Icons.close, size: 16, color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupLabel(BoojyColors colors, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4, top: 2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: colors.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildRow(
    BoojyColors colors, {
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? colors.selectionFill : colors.dark,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? colors.selectionBorder : colors.divider,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isActive ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 15,
                color: isActive ? colors.accent : colors.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? colors.accent : colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
