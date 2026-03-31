import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
import 'device_strip.dart';

/// The type of device in the chain.
enum DeviceType { instrument, effect }

/// Whether the device is a built-in Boojy device or a third-party plugin.
enum DeviceKind { builtIn, vst3Plugin }

/// Controls which header variant a device box shows.
enum HeaderMode {
  /// Standard 24px header (icon + name). Used for effects.
  full24,

  /// Compact 16px header (icon + name). Used for built-in instruments.
  mini16,

  /// No header at all. Used for VST3 plugin instruments.
  none,
}

/// A single device box in the combined instrument + effects chain.
///
/// Displays an optional header (icon + name) on the left,
/// a content area, and a 24px right strip with on/off, float, and meter.
class DeviceBox extends StatefulWidget {
  final DeviceType deviceType;
  final DeviceKind deviceKind;
  final HeaderMode headerMode;
  final String name;
  final IconData icon;
  final bool isEnabled;
  final bool isSelected;
  final bool isFloated;
  final double width;
  final bool expandContent;
  final double leftLevel;
  final double rightLevel;
  final bool showVolumeThumb;
  final double volumeDb;
  final VoidCallback? onToggleEnabled;
  final VoidCallback? onFloat;
  final VoidCallback? onEmbed;
  final VoidCallback? onNameTap;
  final ValueChanged<double>? onVolumeChanged;
  final Widget child;

  const DeviceBox({
    super.key,
    required this.deviceType,
    required this.deviceKind,
    this.headerMode = HeaderMode.full24,
    required this.name,
    required this.icon,
    this.isEnabled = true,
    this.isSelected = false,
    this.isFloated = false,
    required this.width,
    this.expandContent = true,
    this.leftLevel = 0.0,
    this.rightLevel = 0.0,
    this.showVolumeThumb = false,
    this.volumeDb = 0.0,
    this.onToggleEnabled,
    this.onFloat,
    this.onEmbed,
    this.onNameTap,
    this.onVolumeChanged,
    required this.child,
  });

  @override
  State<DeviceBox> createState() => _DeviceBoxState();
}

class _DeviceBoxState extends State<DeviceBox> {
  bool _isHovered = false;

  bool get _hasHeader => widget.headerMode != HeaderMode.none;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDisabled = !widget.isEnabled;

    return MouseRegion(
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
      child: Opacity(
        opacity: isDisabled ? 0.5 : 1.0,
        child: Container(
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.isSelected
                  ? const Color(0xFFE8EAF0)
                  : _isHovered
                  ? colors.hover
                  : colors.divider,
              width: widget.isSelected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildBody(colors),
        ),
      ),
    );
  }

  Widget _buildBody(BoojyColors colors) {
    final strip = DeviceStrip(
      isEnabled: widget.isEnabled,
      isFloated: widget.isFloated,
      showFloat: widget.deviceKind == DeviceKind.vst3Plugin,
      showVolumeThumb: widget.showVolumeThumb,
      leftLevel: widget.leftLevel,
      rightLevel: widget.rightLevel,
      volumeDb: widget.volumeDb,
      onToggleEnabled: widget.onToggleEnabled,
      onFloat: widget.onFloat,
      onEmbed: widget.onEmbed,
      onVolumeChanged: widget.onVolumeChanged,
    );

    final content = Column(
      mainAxisSize: widget.expandContent ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (_hasHeader) _buildHeader(colors),
        if (_hasHeader) Container(height: 1, color: colors.divider),
        if (widget.expandContent)
          Expanded(child: widget.child)
        else
          widget.child,
      ],
    );

    final row = Row(
      children: [
        Expanded(child: content),
        strip,
      ],
    );

    // For content-height devices (effects), use IntrinsicHeight so the
    // strip matches the content Column's height instead of stretching.
    if (!widget.expandContent) {
      return IntrinsicHeight(child: row);
    }
    return row;
  }

  Widget _buildHeader(BoojyColors colors) {
    final isMini = widget.headerMode == HeaderMode.mini16;
    final height = isMini ? 16.0 : 24.0;
    final iconSize = isMini ? 12.0 : 14.0;
    final fontSize = isMini ? 11.0 : 12.0;
    final hPad = isMini ? 6.0 : 8.0;

    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: hPad),
      color: colors.dark,
      child: Row(
        children: [
          // Icon
          Icon(widget.icon, size: iconSize, color: colors.textMuted),
          SizedBox(width: isMini ? 4 : 6),
          // Name (tappable for dropdown)
          Expanded(
            child: GestureDetector(
              onTap: widget.onNameTap,
              child: MouseRegion(
                cursor: widget.onNameTap != null
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: Text(
                  widget.name,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: fontSize,
                    fontWeight: BT.weightMedium,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
