import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'instrument_browser.dart';
import 'library_preview_bar.dart';
import 'resizable_divider.dart';
import 'shared/search_field.dart';
import '../models/library_item.dart';
import '../models/vst3_plugin_data.dart';
import '../services/library_preview_service.dart';
import '../services/library_service.dart';
import '../theme/theme_extension.dart';
import '../utils/text_utils.dart';

/// Library panel widget - two-column layout with categories on left, contents on right
class LibraryPanel extends StatefulWidget {
  final bool isCollapsed;
  final VoidCallback? onToggle;
  final List<Map<String, String>> availableVst3Plugins;
  final LibraryService libraryService;
  final void Function(LibraryItem)? onItemDoubleClick;
  final void Function(Vst3Plugin)? onVst3DoubleClick;
  final void Function(LibraryItem)? onOpenInSampler;

  /// Left column width (managed by parent via UILayoutState)
  final double leftColumnWidth;

  /// Callback when inner divider is dragged
  /// Only affects left column - right column absorbs the difference
  final void Function(double delta)? onLeftColumnResize;

  const LibraryPanel({
    super.key,
    this.isCollapsed = false,
    this.onToggle,
    this.availableVst3Plugins = const [],
    required this.libraryService,
    this.onItemDoubleClick,
    this.onVst3DoubleClick,
    this.onOpenInSampler,
    this.leftColumnWidth = 100.0,
    this.onLeftColumnResize,
  });

  @override
  State<LibraryPanel> createState() => _LibraryPanelState();
}

class _LibraryPanelState extends State<LibraryPanel> {
  // Currently selected category in left column
  String _selectedCategory = 'sounds';

  // Expanded items in right column (subcategories and folders)
  final Set<String> _expandedItems = {};

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _leftScrollController = ScrollController();
  final ScrollController _rightScrollController = ScrollController();
  String _searchQuery = '';

  /// Cache for folder contents to avoid FutureBuilder rebuilds
  final Map<String, List<LibraryItem>> _folderContentsCache = {};

  /// Maps folder ID to its parent folder ID
  final Map<String, String> _folderParents = {};

  @override
  void initState() {
    super.initState();
    widget.libraryService.addListener(_onLibraryChanged);
  }

  @override
  void dispose() {
    widget.libraryService.removeListener(_onLibraryChanged);
    _searchController.dispose();
    _leftScrollController.dispose();
    _rightScrollController.dispose();
    super.dispose();
  }

  void _onLibraryChanged() {
    setState(() {});
  }

  /// Toggle an item expanded/collapsed in the right column
  Future<void> _toggleItem(String itemId, {Future<List<LibraryItem>>? loadContents}) async {
    final isExpanded = _expandedItems.contains(itemId);

    // If expanding a folder, load contents first
    if (!isExpanded && loadContents != null) {
      final contents = await loadContents;
      _folderContentsCache[itemId] = contents;

      // Record parent relationships for nested folders
      for (final item in contents) {
        if (item is FolderItem) {
          final childId = 'nested_folder_${item.folderPath.hashCode}';
          _folderParents[childId] = itemId;
        }
      }
    }

    if (!mounted) return;

    setState(() {
      if (isExpanded) {
        _expandedItems.remove(itemId);
      } else {
        _expandedItems.add(itemId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isCollapsed) {
      return _buildCollapsedPanel();
    }

    final colors = context.colors;

    return Container(
          decoration: BoxDecoration(
            color: colors.standard,
            border: Border(
              right: BorderSide(color: colors.elevated),
            ),
          ),
          child: Column(
            children: [
              _buildCombinedHeader(),
              Expanded(
                child: _searchQuery.isNotEmpty
                    ? _buildSearchResults()
                    : Row(
                        children: [
                          // Left column - Categories
                          SizedBox(
                            width: widget.leftColumnWidth,
                            child: _buildCategoryList(),
                          ),
                          // Draggable divider
                          _buildDivider(),
                          // Right column - Contents + Preview
                          Expanded(
                            child: _buildContentsColumn(),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
  }

  Widget _buildCollapsedPanel() {
    final colors = context.colors;
    return Container(
      width: 40,
      decoration: BoxDecoration(
        color: colors.standard,
        border: Border(
          right: BorderSide(color: colors.elevated),
        ),
      ),
      child: Column(
        children: [
          IconButton(
            icon: const Icon(Icons.library_music),
            color: colors.textSecondary,
            onPressed: widget.onToggle,
            tooltip: 'Show Library (B)',
          ),
        ],
      ),
    );
  }

  Widget _buildCombinedHeader() {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.elevated,
        border: Border(
          bottom: BorderSide(color: colors.elevated),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.library_music,
            color: colors.textPrimary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            'LIBRARY',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 26,
              child: SearchField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (widget.onToggle != null)
            IconButton(
              icon: const Icon(Icons.chevron_left),
              color: colors.textSecondary,
              iconSize: 18,
              onPressed: widget.onToggle,
              tooltip: 'Hide Library (B)',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return ResizableDivider(
      orientation: DividerOrientation.vertical,
      onDrag: (delta) {
        // Middle divider only affects left column
        // Right column absorbs the difference (via Expanded widget)
        widget.onLeftColumnResize?.call(delta);
      },
      onDoubleClick: () {
        // Toggle between compact (100px) and comfortable (150px)
        final target = widget.leftColumnWidth > 125.0 ? 100.0 : 150.0;
        widget.onLeftColumnResize?.call(target - widget.leftColumnWidth);
      },
    );
  }

  // ==========================================================================
  // LEFT COLUMN - Category List
  // ==========================================================================

  Widget _buildCategoryList() {
    final colors = context.colors;
    final userFolders = widget.libraryService.userFolderPaths;

    return Container(
      color: colors.dark,
      child: ListView(
        controller: _leftScrollController,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          // System categories
          _buildCategoryItem('favorites', Icons.star, 'Favorites'),
          _buildCategoryItem('sounds', Icons.music_note, 'Sounds'),
          _buildCategoryItem('samples', Icons.grid_view, 'Samples'),
          _buildCategoryItem('instruments', Icons.piano, 'Instruments'),
          _buildCategoryItem('effects', Icons.bolt, 'Effects'),
          _buildCategoryItem('plugins', Icons.extension, 'Plugins'),

          // Divider before user folders
          if (userFolders.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Divider(color: colors.elevated, height: 1),
            ),
          ],

          // User folders
          ...userFolders.map((path) {
            final name = path.split('/').last;
            final folderId = 'folder_${path.hashCode}';
            return _buildCategoryItem(folderId, Icons.folder, name, isUserFolder: true, folderPath: path);
          }),

          // Add folder button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Divider(color: colors.elevated, height: 1),
          ),
          _buildAddFolderButton(),
        ],
      ),
    );
  }

  Widget _buildCategoryItem(String id, IconData icon, String label, {bool isUserFolder = false, String? folderPath}) {
    final isSelected = _selectedCategory == id;
    final colors = context.colors;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCategory = id;
        });
        // If it's a user folder, load contents
        if (isUserFolder && folderPath != null && !_folderContentsCache.containsKey(id)) {
          widget.libraryService.scanFolder(folderPath).then((contents) {
            if (mounted) {
              setState(() {
                _folderContentsCache[id] = contents;
              });
            }
          });
        }
      },
      onSecondaryTapUp: isUserFolder && folderPath != null
          ? (details) => _showFolderContextMenu(details, folderPath)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colors.elevated : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? colors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? colors.accent : colors.textMuted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected ? colors.textPrimary : colors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddFolderButton() {
    final colors = context.colors;
    return GestureDetector(
      onTap: _addUserFolder,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.add, size: 14, color: colors.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Add Folder',
                style: TextStyle(fontSize: 12, color: colors.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addUserFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select folder to add to library',
    );

    if (result != null) {
      await widget.libraryService.addUserFolder(result);
    }
  }

  void _showFolderContextMenu(TapUpDetails details, String path) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.delete, size: 16),
              SizedBox(width: 8),
              Text('Remove from Library'),
            ],
          ),
          onTap: () => widget.libraryService.removeUserFolder(path),
        ),
      ],
    );
  }

  // ==========================================================================
  // RIGHT COLUMN - Contents View
  // ==========================================================================

  Widget _buildContentsColumn() {
    return Column(
      children: [
        Expanded(
          child: _buildContentsView(),
        ),
        // Preview bar at bottom of right column
        const LibraryPreviewBar(),
      ],
    );
  }

  Widget _buildContentsView() {
    final colors = context.colors;

    return Container(
      color: colors.standard,
      child: ListView(
        controller: _rightScrollController,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: _buildContentsForCategory(_selectedCategory),
      ),
    );
  }

  List<Widget> _buildContentsForCategory(String categoryId) {
    final builtInCategories = widget.libraryService.getBuiltInCategories();

    switch (categoryId) {
      case 'favorites':
        return _buildFavoritesContents(builtInCategories);
      case 'sounds':
        final soundsCategory = builtInCategories.firstWhere((c) => c.id == 'sounds');
        return _buildNestedCategoryContents(soundsCategory);
      case 'samples':
        final samplesCategory = builtInCategories.firstWhere((c) => c.id == 'samples');
        return _buildNestedCategoryContents(samplesCategory);
      case 'instruments':
        final instrumentsCategory = builtInCategories.firstWhere((c) => c.id == 'instruments');
        return _buildFlatCategoryContents(instrumentsCategory, isInstrumentCategory: true);
      case 'effects':
        final effectsCategory = builtInCategories.firstWhere((c) => c.id == 'effects');
        return _buildFlatCategoryContents(effectsCategory);
      case 'plugins':
        return _buildPluginsContents();
      default:
        // User folder
        if (categoryId.startsWith('folder_')) {
          return _buildUserFolderContents(categoryId);
        }
        return [_buildEmptyState('Select a category')];
    }
  }

  List<Widget> _buildFavoritesContents(List<LibraryCategory> builtInCategories) {
    final favoriteItems = widget.libraryService.getFavoriteItems(builtInCategories);

    if (favoriteItems.isEmpty) {
      return [_buildEmptyState('No favorites yet')];
    }

    return favoriteItems.map((item) => _buildLibraryItem(item)).toList();
  }

  List<Widget> _buildNestedCategoryContents(LibraryCategory category) {
    if (category.subcategories.isEmpty) {
      return [_buildEmptyState('No ${category.name.toLowerCase()} yet')];
    }

    final widgets = <Widget>[];
    for (final sub in category.subcategories) {
      final subId = '${category.id}_${sub.id}';
      final isExpanded = _expandedItems.contains(subId);
      final items = sub.items;

      widgets.add(_buildExpandableHeader(
        icon: sub.icon,
        title: sub.name,
        isExpanded: isExpanded,
        onTap: () => _toggleItem(subId),
      ));

      if (isExpanded) {
        if (items.isEmpty) {
          widgets.add(_buildIndentedEmpty('No items'));
        } else {
          widgets.addAll(items.map((item) => _buildLibraryItem(item, indent: 1)));
        }
      }
    }
    return widgets;
  }

  List<Widget> _buildFlatCategoryContents(LibraryCategory category, {bool isInstrumentCategory = false}) {
    if (category.items.isEmpty) {
      return [_buildEmptyState('No ${category.name.toLowerCase()}')];
    }

    return category.items.map((item) => _buildLibraryItem(item, isInstrumentCategory: isInstrumentCategory)).toList();
  }

  List<Widget> _buildPluginsContents() {
    final vst3Instruments = widget.availableVst3Plugins
        .where((p) => p['is_instrument'] == '1')
        .toList();
    final vst3Effects = widget.availableVst3Plugins
        .where((p) => p['is_effect'] == '1')
        .toList();

    if (vst3Instruments.isEmpty && vst3Effects.isEmpty) {
      return [_buildEmptyState('No plugins found')];
    }

    final widgets = <Widget>[];

    // Instruments subcategory
    final instrumentsExpanded = _expandedItems.contains('plugins_instruments');
    widgets.add(_buildExpandableHeader(
      icon: Icons.piano,
      title: 'Instruments',
      isExpanded: instrumentsExpanded,
      onTap: () => _toggleItem('plugins_instruments'),
    ));
    if (instrumentsExpanded) {
      if (vst3Instruments.isEmpty) {
        widgets.add(_buildIndentedEmpty('No VST3 instruments'));
      } else {
        widgets.addAll(vst3Instruments.map((p) => _buildVst3PluginItem(p, true, indent: 1)));
      }
    }

    // Effects subcategory
    final effectsExpanded = _expandedItems.contains('plugins_effects');
    widgets.add(_buildExpandableHeader(
      icon: Icons.graphic_eq,
      title: 'Effects',
      isExpanded: effectsExpanded,
      onTap: () => _toggleItem('plugins_effects'),
    ));
    if (effectsExpanded) {
      if (vst3Effects.isEmpty) {
        widgets.add(_buildIndentedEmpty('No VST3 effects'));
      } else {
        widgets.addAll(vst3Effects.map((p) => _buildVst3PluginItem(p, false, indent: 1)));
      }
    }

    return widgets;
  }

  List<Widget> _buildUserFolderContents(String folderId) {
    final items = _folderContentsCache[folderId];

    if (items == null) {
      // Still loading
      return [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ];
    }

    if (items.isEmpty) {
      return [_buildEmptyState('Empty folder')];
    }

    return items.map((item) => _buildLibraryItemOrFolder(item)).toList();
  }

  Widget _buildLibraryItemOrFolder(LibraryItem item) {
    if (item is FolderItem) {
      return _buildNestedFolderItem(item);
    }
    return _buildLibraryItem(item);
  }

  Widget _buildNestedFolderItem(FolderItem folder) {
    final folderId = 'nested_folder_${folder.folderPath.hashCode}';
    final isExpanded = _expandedItems.contains(folderId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildExpandableHeader(
          icon: Icons.folder,
          title: folder.name,
          isExpanded: isExpanded,
          onTap: () => _toggleItem(
            folderId,
            loadContents: widget.libraryService.scanFolder(folder.folderPath),
          ),
        ),
        if (isExpanded) _buildNestedFolderContents(folderId),
      ],
    );
  }

  Widget _buildNestedFolderContents(String folderId) {
    final items = _folderContentsCache[folderId];

    if (items == null) {
      return const Padding(
        padding: EdgeInsets.only(left: 24, top: 4, bottom: 4),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (items.isEmpty) {
      return _buildIndentedEmpty('Empty folder');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items.map((item) {
        if (item is FolderItem) {
          return Padding(
            padding: const EdgeInsets.only(left: 12),
            child: _buildNestedFolderItem(item),
          );
        }
        return _buildLibraryItem(item, indent: 1);
      }).toList(),
    );
  }

  Widget _buildExpandableHeader({
    required IconData icon,
    required String title,
    required bool isExpanded,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(
              isExpanded ? Icons.expand_more : Icons.chevron_right,
              size: 14,
              color: colors.textMuted,
            ),
            const SizedBox(width: 4),
            Icon(icon, size: 14, color: colors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            color: context.colors.textMuted,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  Widget _buildIndentedEmpty(String message) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, top: 4, bottom: 4),
      child: Text(
        message,
        style: TextStyle(
          color: context.colors.textMuted,
          fontSize: 11,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  // ==========================================================================
  // SEARCH RESULTS
  // ==========================================================================

  Widget _buildSearchResults() {
    final builtInCategories = widget.libraryService.getBuiltInCategories();
    final results = <_SearchResult>[];

    // Search through all categories
    for (final category in builtInCategories) {
      for (final sub in category.subcategories) {
        for (final item in sub.items) {
          if (item.matchesSearch(_searchQuery)) {
            results.add(_SearchResult(
              item: item,
              categoryPath: '${category.name} > ${sub.name}',
            ));
          }
        }
      }
      for (final item in category.items) {
        if (item.matchesSearch(_searchQuery)) {
          results.add(_SearchResult(
            item: item,
            categoryPath: category.name,
          ));
        }
      }
    }

    // Search VST3 plugins
    for (final plugin in widget.availableVst3Plugins) {
      final name = plugin['name']?.toLowerCase() ?? '';
      if (name.contains(_searchQuery.toLowerCase())) {
        final isInstrument = plugin['is_instrument'] == '1';
        results.add(_SearchResult(
          vst3Plugin: plugin,
          categoryPath: 'Plugins > ${isInstrument ? 'Instruments' : 'Effects'}',
        ));
      }
    }

    // Search user folder contents
    for (final entry in _folderContentsCache.entries) {
      for (final item in entry.value) {
        if (item.matchesSearch(_searchQuery)) {
          results.add(_SearchResult(
            item: item,
            categoryPath: 'Folders',
          ));
        }
      }
    }

    if (results.isEmpty) {
      return Column(
        children: [
          Expanded(child: _buildEmptyState('No results for "$_searchQuery"')),
          const LibraryPreviewBar(),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final result = results[index];
              if (result.item != null) {
                return _buildSearchResultItem(result.item!, result.categoryPath);
              } else if (result.vst3Plugin != null) {
                return _buildSearchResultVst3(result.vst3Plugin!, result.categoryPath);
              }
              return const SizedBox.shrink();
            },
          ),
        ),
        const LibraryPreviewBar(),
      ],
    );
  }

  Widget _buildSearchResultItem(LibraryItem item, String categoryPath) {
    final colors = context.colors;
    final previewService = _tryGetPreviewService(listen: true);
    final isCurrentlyPreviewing = previewService != null &&
        item is AudioFileItem &&
        previewService.currentFilePath == item.filePath &&
        previewService.isPlaying;

    return GestureDetector(
      onTap: () => _handleItemClick(item),
      onDoubleTap: () => widget.onItemDoubleClick?.call(item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            if (isCurrentlyPreviewing) ...[
              Icon(Icons.volume_up, size: 12, color: colors.accent),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textStyle = TextStyle(
                    fontSize: 12,
                    color: isCurrentlyPreviewing ? colors.accent : colors.textPrimary,
                  );
                  return Text(
                    TextUtils.truncateMiddleToFit(
                      filename: item.displayName,
                      maxWidth: constraints.maxWidth,
                      style: textStyle,
                    ),
                    style: textStyle,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Text(
              categoryPath,
              style: TextStyle(
                fontSize: 10,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultVst3(Map<String, String> plugin, String categoryPath) {
    final colors = context.colors;
    final name = plugin['name'] ?? 'Unknown';

    return GestureDetector(
      onDoubleTap: () => widget.onVst3DoubleClick?.call(Vst3Plugin.fromMap(plugin)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textStyle = TextStyle(fontSize: 12, color: colors.textPrimary);
                  return Text(
                    TextUtils.truncateMiddleToFit(
                      filename: name,
                      maxWidth: constraints.maxWidth,
                      style: textStyle,
                    ),
                    style: textStyle,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Text(
              categoryPath,
              style: TextStyle(fontSize: 10, color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // LIBRARY ITEMS
  // ==========================================================================

  /// Safely get the preview service
  LibraryPreviewService? _tryGetPreviewService({bool listen = false}) {
    try {
      return Provider.of<LibraryPreviewService>(context, listen: listen);
    } catch (e) {
      return null;
    }
  }

  void _handleItemClick(LibraryItem item) {
    final previewService = _tryGetPreviewService();
    if (previewService == null) return;

    if (item is AudioFileItem) {
      previewService.loadAndPreviewAudio(item.filePath, item.name);
    } else if (item is PresetItem) {
      previewService.previewSynthPreset(item);
    }
  }

  void _handleDragStarted() {
    _tryGetPreviewService()?.onDragStarted();
  }

  Widget _buildLibraryItem(LibraryItem item, {int indent = 0, bool isInstrumentCategory = false}) {
    final previewService = _tryGetPreviewService(listen: true);
    final isCurrentlyPreviewing = previewService != null &&
        item is AudioFileItem &&
        previewService.currentFilePath == item.filePath &&
        previewService.isPlaying;

    Widget child = GestureDetector(
      onTap: () => _handleItemClick(item),
      onDoubleTap: () => widget.onItemDoubleClick?.call(item),
      onSecondaryTapUp: (details) => _showItemContextMenu(details, item),
      child: _LibraryItemWidget(
        name: item.displayName,
        indent: indent,
        isFavorite: widget.libraryService.isFavorite(item.id),
        isPreviewing: isCurrentlyPreviewing,
      ),
    );

    // Make draggable based on type
    if (item.type == LibraryItemType.instrument || isInstrumentCategory) {
      final instrument = _findInstrumentByName(item.name);
      if (instrument != null) {
        child = Draggable<Instrument>(
          data: instrument,
          feedback: _buildDragFeedback(item.name, item.icon),
          childWhenDragging: Opacity(opacity: 0.5, child: child),
          onDragStarted: _handleDragStarted,
          child: child,
        );
      }
    } else if (item.type == LibraryItemType.preset && item is PresetItem) {
      child = Draggable<PresetItem>(
        data: item,
        feedback: _buildDragFeedback(item.displayName, item.icon),
        childWhenDragging: Opacity(opacity: 0.5, child: child),
        onDragStarted: _handleDragStarted,
        child: child,
      );
    } else if (item.type == LibraryItemType.audioFile && item is AudioFileItem) {
      child = Draggable<AudioFileItem>(
        data: item,
        // Use invisible feedback - the preview clip in timeline view provides visual feedback
        feedback: const SizedBox.shrink(),
        childWhenDragging: Opacity(opacity: 0.5, child: child),
        onDragStarted: _handleDragStarted,
        child: child,
      );
    } else if (item.type == LibraryItemType.midiFile && item is MidiFileItem) {
      child = Draggable<MidiFileItem>(
        data: item,
        feedback: const SizedBox.shrink(),
        childWhenDragging: Opacity(opacity: 0.5, child: child),
        onDragStarted: _handleDragStarted,
        child: child,
      );
    }

    return child;
  }

  Widget _buildVst3PluginItem(Map<String, String> pluginData, bool isInstrument, {int indent = 0}) {
    final plugin = Vst3Plugin.fromMap(pluginData);
    final name = plugin.name;

    return Draggable<Vst3Plugin>(
      data: plugin,
      feedback: _buildDragFeedback(name, isInstrument ? Icons.piano : Icons.graphic_eq),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _LibraryItemWidget(name: name, indent: indent),
      ),
      child: GestureDetector(
        onDoubleTap: () => widget.onVst3DoubleClick?.call(plugin),
        onSecondaryTapUp: (details) => _showVst3ContextMenu(details, plugin),
        child: _LibraryItemWidget(
          name: name,
          indent: indent,
          isFavorite: widget.libraryService.isFavorite('vst3_${plugin.path}'),
        ),
      ),
    );
  }

  Widget _buildDragFeedback(String name, IconData icon) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.colors.accent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showItemContextMenu(TapUpDetails details, LibraryItem item) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final isFavorite = widget.libraryService.isFavorite(item.id);
    final isAudioFile = item.type == LibraryItemType.audioFile || item.type == LibraryItemType.sample;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        if (isAudioFile && widget.onOpenInSampler != null)
          PopupMenuItem(
            child: const Row(
              children: [
                Icon(Icons.music_note, size: 16),
                SizedBox(width: 8),
                Text('Open in Sampler'),
              ],
            ),
            onTap: () => widget.onOpenInSampler?.call(item),
          ),
        PopupMenuItem(
          child: Row(
            children: [
              Icon(
                isFavorite ? Icons.star : Icons.star_border,
                size: 16,
                color: isFavorite ? Colors.amber : null,
              ),
              const SizedBox(width: 8),
              Text(isFavorite ? 'Remove from Favorites' : 'Add to Favorites'),
            ],
          ),
          onTap: () => widget.libraryService.toggleFavorite(item.id),
        ),
      ],
    );
  }

  void _showVst3ContextMenu(TapUpDetails details, Vst3Plugin plugin) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final itemId = 'vst3_${plugin.path}';
    final isFavorite = widget.libraryService.isFavorite(itemId);

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          child: Row(
            children: [
              Icon(
                isFavorite ? Icons.star : Icons.star_border,
                size: 16,
                color: isFavorite ? Colors.amber : null,
              ),
              const SizedBox(width: 8),
              Text(isFavorite ? 'Remove from Favorites' : 'Add to Favorites'),
            ],
          ),
          onTap: () => widget.libraryService.toggleFavorite(itemId),
        ),
      ],
    );
  }

  Instrument? _findInstrumentByName(String name) {
    try {
      return availableInstruments.firstWhere(
        (inst) => inst.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (e) {
      return null;
    }
  }
}

/// Search result wrapper
class _SearchResult {
  final LibraryItem? item;
  final Map<String, String>? vst3Plugin;
  final String categoryPath;

  _SearchResult({
    this.item,
    this.vst3Plugin,
    required this.categoryPath,
  });
}

/// Library item widget with hover and indentation
class _LibraryItemWidget extends StatefulWidget {
  final String name;
  final int indent;
  final bool isFavorite;
  final bool isPreviewing;

  const _LibraryItemWidget({
    required this.name,
    this.indent = 0,
    this.isFavorite = false,
    this.isPreviewing = false,
  });

  @override
  State<_LibraryItemWidget> createState() => _LibraryItemWidgetState();
}

class _LibraryItemWidgetState extends State<_LibraryItemWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final leftPadding = 8.0 + (widget.indent * 12.0);

    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(left: leftPadding, right: 8, top: 5, bottom: 5),
        decoration: BoxDecoration(
          color: _isHovered ? colors.elevated : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: _isHovered ? colors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            if (widget.isPreviewing) ...[
              Icon(Icons.volume_up, size: 12, color: colors.accent),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textStyle = TextStyle(
                    color: widget.isPreviewing
                        ? colors.accent
                        : (_isHovered ? colors.textPrimary : colors.textSecondary),
                    fontSize: 12,
                  );
                  return Text(
                    TextUtils.truncateMiddleToFit(
                      filename: widget.name,
                      maxWidth: constraints.maxWidth,
                      style: textStyle,
                    ),
                    style: textStyle,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                  );
                },
              ),
            ),
            if (widget.isFavorite)
              const Icon(Icons.star, size: 12, color: Colors.amber),
          ],
        ),
      ),
    );
  }
}
