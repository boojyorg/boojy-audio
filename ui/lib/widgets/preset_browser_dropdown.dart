import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/animation_constants.dart';
import '../theme/boojy_icons.dart';
import '../theme/theme_extension.dart';
import '../theme/tokens.dart';

/// Data model for a preset program list (folder)
class PresetFolder {
  final int listId;
  final String name;
  final int programCount;
  final List<String> presets;

  const PresetFolder({
    required this.listId,
    required this.name,
    required this.programCount,
    required this.presets,
  });
}

/// Floating dropdown for browsing and selecting presets.
/// Anchored below the preset name button in Row 1.
class PresetBrowserDropdown extends StatefulWidget {
  final List<PresetFolder> folders;
  final int? currentListId;
  final int? currentPresetIndex;
  final Function(int listId, int presetIndex) onPresetSelected;
  final VoidCallback onResetToDefault;
  final VoidCallback onDismiss;

  const PresetBrowserDropdown({
    super.key,
    required this.folders,
    this.currentListId,
    this.currentPresetIndex,
    required this.onPresetSelected,
    required this.onResetToDefault,
    required this.onDismiss,
  });

  @override
  State<PresetBrowserDropdown> createState() => _PresetBrowserDropdownState();
}

class _PresetBrowserDropdownState extends State<PresetBrowserDropdown>
    with SingleTickerProviderStateMixin {
  String _searchQuery = '';
  final Set<int> _expandedListIds = {};
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: AnimationConstants.hoverDuration,
      vsync: this,
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -0.02),
      end: Offset.zero,
    ).animate(_fadeAnim);
    _animController.forward();

    // Auto-expand the folder containing the current preset
    if (widget.currentListId != null) {
      _expandedListIds.add(widget.currentListId!);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Material(
          elevation: 0,
          color: Colors.transparent,
          child: Container(
            width: 280,
            constraints: const BoxConstraints(maxHeight: 400),
            decoration: BoxDecoration(
              color: colors.elevated,
              borderRadius: BorderRadius.circular(BT.radiusLg),
              border: Border.all(color: colors.divider),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(BT.radiusLg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSearchBar(colors),
                  Divider(height: 1, color: colors.divider),
                  _buildResetRow(colors),
                  Divider(height: 1, color: colors.divider),
                  Flexible(child: _buildPresetList(colors)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(BoojyColors colors) {
    return Container(
      padding: const EdgeInsets.all(BT.sm),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Search presets...',
          hintStyle: TextStyle(color: colors.textMuted, fontSize: BT.fontBody),
          prefixIcon: Icon(BI.search, color: colors.textMuted, size: 16),
          filled: true,
          fillColor: colors.darkest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: colors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: colors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: colors.accent),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          isDense: true,
        ),
        style: TextStyle(color: colors.textPrimary, fontSize: BT.fontBody),
      ),
    );
  }

  Widget _buildResetRow(BoojyColors colors) {
    return InkWell(
      onTap: () {
        widget.onResetToDefault();
        widget.onDismiss();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(BI.refresh, size: 14, color: colors.textMuted),
            const SizedBox(width: 8),
            Text(
              'Reset to Default',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: BT.fontBody,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetList(BoojyColors colors) {
    final query = _searchQuery.toLowerCase();
    final hasSearch = query.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: BT.xs),
      shrinkWrap: true,
      children: [
        for (final folder in widget.folders) ...[
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              folder.name.toUpperCase(),
              style: TextStyle(
                color: colors.textMuted,
                fontSize: BT.fontCaption,
                fontWeight: BT.weightSemiBold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          // When searching, show matching presets flat. Otherwise show expandable folder.
          if (hasSearch)
            ..._buildFilteredPresets(folder, query, colors)
          else
            _buildExpandableFolder(folder, colors),
        ],
        // Empty search results
        if (hasSearch && !_hasAnyMatch(query))
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                'No presets matching "$_searchQuery"',
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: BT.fontBody,
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _hasAnyMatch(String query) {
    for (final folder in widget.folders) {
      for (final preset in folder.presets) {
        if (preset.toLowerCase().contains(query)) return true;
      }
    }
    return false;
  }

  List<Widget> _buildFilteredPresets(
    PresetFolder folder,
    String query,
    BoojyColors colors,
  ) {
    final widgets = <Widget>[];
    for (int i = 0; i < folder.presets.length; i++) {
      if (folder.presets[i].toLowerCase().contains(query)) {
        widgets.add(_buildPresetRow(folder, i, colors));
      }
    }
    return widgets;
  }

  Widget _buildExpandableFolder(PresetFolder folder, BoojyColors colors) {
    final isExpanded = _expandedListIds.contains(folder.listId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Folder row
        InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedListIds.remove(folder.listId);
              } else {
                _expandedListIds.add(folder.listId);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  isExpanded ? BI.caretDown : BI.caretRight,
                  size: 12,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    folder.name,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: BT.fontBody,
                    ),
                  ),
                ),
                Text(
                  '(${folder.programCount})',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: BT.fontLabel,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Expanded preset rows
        if (isExpanded)
          for (int i = 0; i < folder.presets.length; i++)
            _buildPresetRow(folder, i, colors),
      ],
    );
  }

  Widget _buildPresetRow(PresetFolder folder, int index, BoojyColors colors) {
    final isCurrent =
        folder.listId == widget.currentListId &&
        index == widget.currentPresetIndex;

    return InkWell(
      onTap: () {
        widget.onPresetSelected(folder.listId, index);
        widget.onDismiss();
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 28, right: 12, top: 4, bottom: 4),
        child: Row(
          children: [
            if (isCurrent)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accent,
                ),
              )
            else
              const SizedBox(width: 14),
            Expanded(
              child: Text(
                folder.presets[index],
                style: TextStyle(
                  color: isCurrent ? colors.textPrimary : colors.textSecondary,
                  fontSize: BT.fontBody,
                  fontWeight: isCurrent ? BT.weightMedium : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
