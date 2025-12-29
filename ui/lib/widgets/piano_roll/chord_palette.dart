import 'package:flutter/material.dart';
import '../../models/chord_data.dart';
import '../../theme/theme_extension.dart';

/// Floating chord palette for selecting and stamping chords.
/// Allows root selection, chord type, inversion, and preview.
class ChordPalette extends StatefulWidget {
  /// Currently selected chord configuration
  final ChordConfiguration configuration;

  /// Called when chord configuration changes
  final Function(ChordConfiguration)? onConfigurationChanged;

  /// Called when user wants to preview/audition the chord
  final Function(List<int> midiNotes)? onPreview;

  /// Called to close the palette
  final VoidCallback? onClose;

  /// Whether preview/audition is enabled
  final bool previewEnabled;

  /// Called when preview toggle is changed
  final Function(bool)? onPreviewToggle;

  const ChordPalette({
    super.key,
    required this.configuration,
    this.onConfigurationChanged,
    this.onPreview,
    this.onClose,
    this.previewEnabled = true,
    this.onPreviewToggle,
  });

  @override
  State<ChordPalette> createState() => _ChordPaletteState();
}

class _ChordPaletteState extends State<ChordPalette> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: colors.elevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.surface, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context),
          _buildRootSelector(context),
          _buildChordTypeGrid(context),
          _buildInversionSelector(context),
          _buildPreviewToggle(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.standard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        border: Border(
          bottom: BorderSide(color: colors.surface, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.music_note,
            color: colors.textPrimary,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            'Chord Palette',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Current chord display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              widget.configuration.displayName,
              style: TextStyle(
                color: colors.accent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.onClose,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Icon(
                Icons.close,
                color: colors.textMuted,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRootSelector(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.surface, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              'Root',
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: ChordRoot.values.map((root) {
              final isSelected = root == widget.configuration.root;
              return _buildRootButton(context, root, isSelected);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRootButton(BuildContext context, ChordRoot root, bool isSelected) {
    final colors = context.colors;

    return GestureDetector(
      onTap: () {
        final newConfig = widget.configuration.copyWith(root: root);
        widget.onConfigurationChanged?.call(newConfig);
        if (widget.previewEnabled) {
          widget.onPreview?.call(newConfig.midiNotes);
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 32,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? colors.accent : colors.dark,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? colors.accent : colors.surface,
              width: 1,
            ),
          ),
          child: Text(
            root.displayName,
            style: TextStyle(
              color: isSelected ? colors.elevated : colors.textPrimary,
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChordTypeGrid(BuildContext context) {
    final colors = context.colors;

    // Arrange chord types in rows
    final row1 = [ChordType.major, ChordType.minor, ChordType.dominant7, ChordType.major7];
    final row2 = [ChordType.minor7, ChordType.diminished, ChordType.augmented, ChordType.sus4];
    final row3 = [ChordType.sus2, ChordType.diminished7, ChordType.add9, ChordType.sixth];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.surface, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              'Type',
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          _buildChordTypeRow(context, row1),
          const SizedBox(height: 4),
          _buildChordTypeRow(context, row2),
          const SizedBox(height: 4),
          _buildChordTypeRow(context, row3),
        ],
      ),
    );
  }

  Widget _buildChordTypeRow(BuildContext context, List<ChordType> types) {
    return Row(
      children: types.map((type) {
        final isSelected = type == widget.configuration.type;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _buildChordTypeButton(context, type, isSelected),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildChordTypeButton(BuildContext context, ChordType type, bool isSelected) {
    final colors = context.colors;

    return GestureDetector(
      onTap: () {
        // Reset inversion if it exceeds the new chord's max inversion
        int newInversion = widget.configuration.inversion;
        if (newInversion > type.maxInversion) {
          newInversion = 0;
        }
        final newConfig = widget.configuration.copyWith(
          type: type,
          inversion: newInversion,
        );
        widget.onConfigurationChanged?.call(newConfig);
        if (widget.previewEnabled) {
          widget.onPreview?.call(newConfig.midiNotes);
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? colors.accent : colors.dark,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? colors.accent : colors.surface,
              width: 1,
            ),
          ),
          child: Text(
            type.displayName,
            style: TextStyle(
              color: isSelected ? colors.elevated : colors.textPrimary,
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInversionSelector(BuildContext context) {
    final colors = context.colors;
    final maxInversion = widget.configuration.type.maxInversion;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.surface, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              'Inversion',
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Row(
            children: List.generate(maxInversion + 1, (index) {
              final isSelected = index == widget.configuration.inversion;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _buildInversionButton(context, index, isSelected),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildInversionButton(BuildContext context, int inversion, bool isSelected) {
    final colors = context.colors;
    final label = inversion == 0 ? 'Root' : '$inversion';

    return GestureDetector(
      onTap: () {
        final newConfig = widget.configuration.copyWith(inversion: inversion);
        widget.onConfigurationChanged?.call(newConfig);
        if (widget.previewEnabled) {
          widget.onPreview?.call(newConfig.midiNotes);
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? colors.accent : colors.dark,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? colors.accent : colors.surface,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? colors.elevated : colors.textPrimary,
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewToggle(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => widget.onPreviewToggle?.call(!widget.previewEnabled),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Row(
                children: [
                  Icon(
                    widget.previewEnabled ? Icons.volume_up : Icons.volume_off,
                    color: widget.previewEnabled ? colors.accent : colors.textMuted,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Preview',
                    style: TextStyle(
                      color: widget.previewEnabled ? colors.textPrimary : colors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Manual preview button
          GestureDetector(
            onTap: () => widget.onPreview?.call(widget.configuration.midiNotes),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.play_arrow,
                      color: colors.elevated,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Play',
                      style: TextStyle(
                        color: colors.elevated,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
