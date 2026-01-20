import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'instrument_browser.dart';
import 'shared/panel_header.dart';
import 'shared/search_field.dart';
import '../models/library_item.dart';
import '../models/vst3_plugin_data.dart';
import '../services/library_service.dart';
import '../theme/theme_extension.dart';

/// Library panel widget - left sidebar with browsable content categories
class LibraryPanel extends StatefulWidget {
  final bool isCollapsed;
  final VoidCallback? onToggle;
  final List<Map<String, String>> availableVst3Plugins;
  final LibraryService libraryService;
  final void Function(LibraryItem)? onItemDoubleClick;
  final void Function(Vst3Plugin)? onVst3DoubleClick;
  final void Function(LibraryItem)? onOpenInSampler;

  const LibraryPanel({
    super.key,
    this.isCollapsed = false,
    this.onToggle,
    this.availableVst3Plugins = const [],
    required this.libraryService,
    this.onItemDoubleClick,
    this.onVst3DoubleClick,
    this.onOpenInSampler,
  });

  @override
  State<LibraryPanel> createState() => _LibraryPanelState();
}

class _LibraryPanelState extends State<LibraryPanel> {
  // Top-level category IDs for accordion behavior
  static const _topLevelCategories = {'favorites', 'sounds', 'samples', 'instruments', 'effects', 'plugins', 'folders'};

  final Set<String> _expandedCategories = {};
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';

  /// Cache for folder contents to avoid FutureBuilder rebuilds causing scroll jumps
  final Map<String, List<LibraryItem>> _folderContentsCache = {};

  /// Maps folder ID to its parent folder ID (for accordion behavior)
  final Map<String, String> _folderParents = {};

  /// Expand a category with accordion behavior
  /// - For top-level: close other top-level categories but KEEP their children
  ///   (children won't render since parent is collapsed, but will restore when parent reopens)
  /// - For subcategories: close sibling subcategories
  /// - For nested folders (folder_ and nested_folder_): NO accordion - allow multiple open
  void _expandWithAccordion(String categoryId) {
    // Check if this is a top-level category
    if (_topLevelCategories.contains(categoryId)) {
      // Only remove other top-level categories, NOT their children
      // Children stay in set but won't render (parent collapsed)
      // When parent reopens, children are still there → restored position (Ableton-style)
      _expandedCategories.removeWhere((id) {
        return _topLevelCategories.contains(id) && id != categoryId;
      });
      _expandedCategories.add(categoryId);
    } else if (categoryId.startsWith('folder_') || categoryId.startsWith('nested_folder_')) {
      // User folders: Accordion behavior - close siblings, keep children
      // Get this folder's parent (top-level folders have parent 'folders')
      final myParent = _folderParents[categoryId] ?? 'folders';

      // Remove sibling folders (same parent) but NOT their children
      // Children stay in set so they restore when parent is reopened (Ableton-style)
      _expandedCategories.removeWhere((id) {
        if (!id.startsWith('folder_') && !id.startsWith('nested_folder_')) return false;
        if (id == categoryId) return false;

        final theirParent = _folderParents[id] ?? 'folders';
        // Same parent = siblings → close them
        return theirParent == myParent;
      });

      _expandedCategories.add(categoryId);
    } else {
      // This is a subcategory - find its parent and close siblings
      final parentId = _getParentId(categoryId);
      if (parentId != null) {
        // Remove siblings (same parent prefix, different id)
        _expandedCategories.removeWhere((id) {
          return id != categoryId &&
                 id.startsWith('${parentId}_') &&
                 !categoryId.startsWith('${id}_'); // Don't remove ancestors
        });
      }
      _expandedCategories.add(categoryId);
    }
  }

  /// Get parent category ID from a subcategory ID
  /// e.g., "sounds_leads" -> "sounds", "plugins_instruments" -> "plugins"
  String? _getParentId(String categoryId) {
    final lastUnderscore = categoryId.lastIndexOf('_');
    if (lastUnderscore > 0) {
      return categoryId.substring(0, lastUnderscore);
    }
    return null;
  }

  /// Toggle a category expanded/collapsed while preserving scroll position.
  /// This prevents the scroll from jumping when the list changes size.
  Future<void> _toggleCategory(String categoryId, {Future<List<LibraryItem>>? loadContents}) async {
    final isExpanded = _expandedCategories.contains(categoryId);

    // Save current scroll position before state change
    final savedOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;

    // If expanding a folder, load contents first and cache them
    if (!isExpanded && loadContents != null) {
      final contents = await loadContents;
      _folderContentsCache[categoryId] = contents;

      // Record parent relationships for nested folders (for accordion behavior)
      for (final item in contents) {
        if (item is FolderItem) {
          final childId = 'nested_folder_${item.folderPath.hashCode}';
          _folderParents[childId] = categoryId;
        }
      }
    }

    if (!mounted) return;

    setState(() {
      if (isExpanded) {
        _expandedCategories.remove(categoryId);
      } else {
        _expandWithAccordion(categoryId);
      }
    });

    // Restore scroll position after the frame rebuilds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && mounted) {
        // Clamp to valid range in case content is now shorter
        final maxScroll = _scrollController.position.maxScrollExtent;
        final targetOffset = savedOffset.clamp(0.0, maxScroll);
        _scrollController.jumpTo(targetOffset);
      }
    });
  }

  /// Build folder contents from cache (avoids FutureBuilder rebuild issues)
  Widget _buildFolderContents(String folderId) {
    final items = _folderContentsCache[folderId];

    if (items == null) {
      // Still loading - show spinner
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
        child: Text(
          'Empty folder',
          style: TextStyle(
            color: context.colors.textMuted,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items.map((item) => _buildLibraryItem(item)).toList(),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    widget.libraryService.addListener(_onLibraryChanged);
  }

  @override
  void dispose() {
    widget.libraryService.removeListener(_onLibraryChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onLibraryChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isCollapsed) {
      return _buildCollapsedPanel();
    }

    final colors = context.colors;
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: colors.standard,
        border: Border(
          right: BorderSide(color: colors.elevated),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildSearchBar(),
          Expanded(
            child: ListView(
              key: const ValueKey('library_list'),
              controller: _scrollController,
              padding: EdgeInsets.zero,
              children: _buildCategoryList(),
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

  Widget _buildHeader() {
    return PanelHeader(
      title: 'Library',
      icon: Icons.library_music,
      actions: widget.onToggle != null
          ? [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                color: context.colors.textSecondary,
                iconSize: 18,
                onPressed: widget.onToggle,
                tooltip: 'Hide Library (B)',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]
          : null,
    );
  }

  Widget _buildSearchBar() {
    return SearchFieldPanel(
      controller: _searchController,
      onChanged: (value) {
        setState(() {
          _searchQuery = value;
        });
      },
    );
  }

  List<Widget> _buildCategoryList() {
    final categories = <Widget>[];

    // Get built-in categories
    final builtInCategories = widget.libraryService.getBuiltInCategories();

    // Favorites
    final favoriteItems = widget.libraryService.getFavoriteItems(builtInCategories);
    if (favoriteItems.isNotEmpty || _searchQuery.isEmpty) {
      final filteredFavorites = favoriteItems
          .where((item) => item.matchesSearch(_searchQuery))
          .toList();

      if (filteredFavorites.isNotEmpty || _searchQuery.isEmpty) {
        categories.add(_buildCategorySection(
          id: 'favorites',
          icon: Icons.star,
          title: 'Favorites',
          items: filteredFavorites,
        ));
      }
    }

    // Sounds (with subcategories)
    final soundsCategory = builtInCategories.firstWhere((c) => c.id == 'sounds');
    if (soundsCategory.hasMatchingItems(_searchQuery) || _searchQuery.isEmpty) {
      categories.add(_buildNestedCategorySection(soundsCategory));
    }

    // Samples (with subcategories)
    final samplesCategory = builtInCategories.firstWhere((c) => c.id == 'samples');
    if (samplesCategory.hasMatchingItems(_searchQuery) || _searchQuery.isEmpty) {
      categories.add(_buildNestedCategorySection(samplesCategory));
    }

    // Instruments
    final instrumentsCategory = builtInCategories.firstWhere((c) => c.id == 'instruments');
    if (instrumentsCategory.hasMatchingItems(_searchQuery) || _searchQuery.isEmpty) {
      categories.add(_buildCategorySection(
        id: instrumentsCategory.id,
        icon: instrumentsCategory.icon,
        title: instrumentsCategory.name,
        items: instrumentsCategory.getMatchingItems(_searchQuery),
        isInstrumentCategory: true,
      ));
    }

    // Effects
    final effectsCategory = builtInCategories.firstWhere((c) => c.id == 'effects');
    if (effectsCategory.hasMatchingItems(_searchQuery) || _searchQuery.isEmpty) {
      categories.add(_buildCategorySection(
        id: effectsCategory.id,
        icon: effectsCategory.icon,
        title: effectsCategory.name,
        items: effectsCategory.getMatchingItems(_searchQuery),
      ));
    }

    // Plugins (VST3)
    categories.add(_buildPluginsCategory());

    // Folders (user directories)
    categories.add(_buildFoldersCategory());

    return categories;
  }

  Widget _buildCategorySection({
    required String id,
    required IconData icon,
    required String title,
    required List<LibraryItem> items,
    bool isInstrumentCategory = false,
    bool showAddButton = false,
    VoidCallback? onAddPressed,
  }) {
    final isExpanded = _expandedCategories.contains(id);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.colors.elevated),
        ),
      ),
      child: Column(
        children: [
          _CategoryHeader(
            icon: icon,
            title: title,
            isExpanded: isExpanded,
            showAddButton: showAddButton,
            onTap: () => _toggleCategory(id),
            onAddPressed: onAddPressed,
          ),
          if (isExpanded)
            Container(
              padding: const EdgeInsets.only(left: 20, bottom: 8),
              color: context.colors.dark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: items.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                          child: Text(
                            'No items',
                            style: TextStyle(
                              color: context.colors.textMuted,
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ]
                    : items.map((item) => _buildLibraryItem(item, isInstrumentCategory: isInstrumentCategory)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNestedCategorySection(LibraryCategory category) {
    final isExpanded = _expandedCategories.contains(category.id);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.colors.elevated),
        ),
      ),
      child: Column(
        children: [
          _CategoryHeader(
            icon: category.icon,
            title: category.name,
            isExpanded: isExpanded,
            onTap: () => _toggleCategory(category.id),
          ),
          if (isExpanded)
            ColoredBox(
              color: context.colors.dark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: category.subcategories.map((sub) {
                  final subId = '${category.id}_${sub.id}';
                  final isSubExpanded = _expandedCategories.contains(subId);
                  final filteredItems = sub.getMatchingItems(_searchQuery);

                  // Skip subcategory if no matching items during search
                  if (_searchQuery.isNotEmpty && filteredItems.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return Column(
                    children: [
                      _SubcategoryHeader(
                        icon: sub.icon,
                        title: sub.name,
                        isExpanded: isSubExpanded,
                        onTap: () => _toggleCategory(subId),
                      ),
                      if (isSubExpanded)
                        Container(
                          padding: const EdgeInsets.only(left: 32, bottom: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: filteredItems
                                .map((item) => _buildLibraryItem(item))
                                .toList(),
                          ),
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPluginsCategory() {
    final isExpanded = _expandedCategories.contains('plugins');

    // Split into instruments and effects
    final vst3Instruments = widget.availableVst3Plugins
        .where((p) => p['is_instrument'] == '1')
        .toList();
    final vst3Effects = widget.availableVst3Plugins
        .where((p) => p['is_effect'] == '1')
        .toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.colors.elevated),
        ),
      ),
      child: Column(
        children: [
          _CategoryHeader(
            icon: Icons.extension,
            title: 'Plugins',
            isExpanded: isExpanded,
            onTap: () => _toggleCategory('plugins'),
          ),
          if (isExpanded)
            ColoredBox(
              color: context.colors.dark,
              child: Column(
                children: [
                  // VST3 Instruments
                  _buildVst3Subcategory(
                    id: 'plugins_instruments',
                    title: 'Instruments',
                    icon: Icons.piano,
                    plugins: vst3Instruments,
                    isInstrument: true,
                  ),
                  // VST3 Effects
                  _buildVst3Subcategory(
                    id: 'plugins_effects',
                    title: 'Effects',
                    icon: Icons.graphic_eq,
                    plugins: vst3Effects,
                    isInstrument: false,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVst3Subcategory({
    required String id,
    required String title,
    required IconData icon,
    required List<Map<String, String>> plugins,
    required bool isInstrument,
  }) {
    final isExpanded = _expandedCategories.contains(id);

    // Filter by search
    final filteredPlugins = _searchQuery.isEmpty
        ? plugins
        : plugins.where((p) {
            final name = p['name']?.toLowerCase() ?? '';
            return name.contains(_searchQuery.toLowerCase());
          }).toList();

    if (_searchQuery.isNotEmpty && filteredPlugins.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        _SubcategoryHeader(
          icon: icon,
          title: title,
          isExpanded: isExpanded,
          onTap: () => _toggleCategory(id),
        ),
        if (isExpanded)
          Container(
            padding: const EdgeInsets.only(left: 32, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: filteredPlugins.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                        child: Text(
                          isInstrument ? 'No VST3 instruments found' : 'No VST3 effects found',
                          style: TextStyle(
                            color: context.colors.textMuted,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ]
                  : filteredPlugins.map((p) => _buildVst3PluginItem(p, isInstrument)).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildFoldersCategory() {
    final isExpanded = _expandedCategories.contains('folders');
    final folderPaths = widget.libraryService.userFolderPaths;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.colors.elevated),
        ),
      ),
      child: Column(
        children: [
          _CategoryHeader(
            icon: Icons.folder,
            title: 'Folders',
            isExpanded: isExpanded,
            showAddButton: true,
            onTap: () => _toggleCategory('folders'),
            onAddPressed: _addUserFolder,
          ),
          if (isExpanded)
            Container(
              padding: const EdgeInsets.only(left: 20, bottom: 8),
              color: context.colors.dark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: folderPaths.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                          child: Text(
                            'Click + to add folders',
                            style: TextStyle(
                              color: context.colors.textMuted,
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ]
                    : folderPaths.map((path) => _buildUserFolderItem(path)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUserFolderItem(String path) {
    final folderName = path.split('/').last;
    final folderId = 'folder_${path.hashCode}';
    final isExpanded = _expandedCategories.contains(folderId);

    return Column(
      children: [
        GestureDetector(
          onSecondaryTapUp: (details) => _showFolderContextMenu(details, path),
          child: _SubcategoryHeader(
            icon: Icons.folder,
            title: folderName,
            isExpanded: isExpanded,
            onTap: () => _toggleCategory(
              folderId,
              loadContents: widget.libraryService.scanFolder(path),
            ),
          ),
        ),
        if (isExpanded)
          _buildFolderContents(folderId),
      ],
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

  Widget _buildLibraryItem(LibraryItem item, {bool isInstrumentCategory = false}) {
    Widget child = GestureDetector(
      onDoubleTap: () => widget.onItemDoubleClick?.call(item),
      onSecondaryTapUp: (details) => _showItemContextMenu(details, item),
      child: _LibraryItemWidget(
        name: item.displayName,
        isFavorite: widget.libraryService.isFavorite(item.id),
      ),
    );

    // Make draggable based on type
    if (item.type == LibraryItemType.instrument || isInstrumentCategory) {
      // Find matching instrument from availableInstruments
      final instrument = _findInstrumentByName(item.name);
      if (instrument != null) {
        child = Draggable<Instrument>(
          data: instrument,
          feedback: _buildDragFeedback(item.name, item.icon),
          childWhenDragging: Opacity(opacity: 0.5, child: child),
          child: child,
        );
      }
    } else if (item.type == LibraryItemType.preset && item is PresetItem) {
      child = Draggable<PresetItem>(
        data: item,
        feedback: _buildDragFeedback(item.displayName, item.icon),
        childWhenDragging: Opacity(opacity: 0.5, child: child),
        child: child,
      );
    } else if (item.type == LibraryItemType.audioFile && item is AudioFileItem) {
      child = Draggable<AudioFileItem>(
        data: item,
        feedback: _buildDragFeedback(item.name, item.icon),
        childWhenDragging: Opacity(opacity: 0.5, child: child),
        child: child,
      );
    } else if (item.type == LibraryItemType.folder && item is FolderItem) {
      // Folders are expandable, not draggable
      return _buildNestedFolderItem(item);
    }

    return child;
  }

  Widget _buildNestedFolderItem(FolderItem folder) {
    final folderId = 'nested_folder_${folder.folderPath.hashCode}';
    final isExpanded = _expandedCategories.contains(folderId);

    return Column(
      children: [
        _SubcategoryHeader(
          icon: Icons.folder,
          title: folder.name,
          isExpanded: isExpanded,
          onTap: () => _toggleCategory(
            folderId,
            loadContents: widget.libraryService.scanFolder(folder.folderPath),
          ),
        ),
        if (isExpanded)
          _buildFolderContents(folderId),
      ],
    );
  }

  Widget _buildVst3PluginItem(Map<String, String> pluginData, bool isInstrument) {
    final plugin = Vst3Plugin.fromMap(pluginData);
    final name = plugin.name;

    return Draggable<Vst3Plugin>(
      data: plugin,
      feedback: _buildDragFeedback(name, isInstrument ? Icons.piano : Icons.graphic_eq),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _LibraryItemWidget(name: name),
      ),
      child: GestureDetector(
        onDoubleTap: () => widget.onVst3DoubleClick?.call(plugin),
        onSecondaryTapUp: (details) => _showVst3ContextMenu(details, plugin),
        child: _LibraryItemWidget(
          name: name,
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

    // Check if this is an audio file (for "Open in Sampler" option)
    final isAudioFile = item.type == LibraryItemType.audioFile ||
        item.type == LibraryItemType.sample;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        // Open in Sampler - only for audio files
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

/// Category header with hover animation
class _CategoryHeader extends StatefulWidget {
  final IconData icon;
  final String title;
  final bool isExpanded;
  final VoidCallback onTap;
  final bool showAddButton;
  final VoidCallback? onAddPressed;

  const _CategoryHeader({
    required this.icon,
    required this.title,
    required this.isExpanded,
    required this.onTap,
    this.showAddButton = false,
    this.onAddPressed,
  });

  @override
  State<_CategoryHeader> createState() => _CategoryHeaderState();
}

class _CategoryHeaderState extends State<_CategoryHeader> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: _isHovered ? context.colors.elevated : Colors.transparent,
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: _isHovered ? context.colors.accent : context.colors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    color: _isHovered ? context.colors.textPrimary : context.colors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (widget.showAddButton)
                GestureDetector(
                  onTap: widget.onAddPressed,
                  child: Icon(
                    Icons.add,
                    size: 16,
                    color: _isHovered ? context.colors.accent : context.colors.textMuted,
                  ),
                ),
              if (widget.showAddButton) const SizedBox(width: 8),
              Icon(
                widget.isExpanded ? Icons.expand_more : Icons.chevron_right,
                size: 18,
                color: _isHovered ? context.colors.accent : context.colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Subcategory header (indented, smaller)
class _SubcategoryHeader extends StatefulWidget {
  final IconData icon;
  final String title;
  final bool isExpanded;
  final VoidCallback onTap;

  const _SubcategoryHeader({
    required this.icon,
    required this.title,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  State<_SubcategoryHeader> createState() => _SubcategoryHeaderState();
}

class _SubcategoryHeaderState extends State<_SubcategoryHeader> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.only(left: 28, right: 12, top: 6, bottom: 6),
          color: _isHovered ? context.colors.elevated : Colors.transparent,
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: _isHovered ? context.colors.accent : context.colors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    color: _isHovered ? context.colors.textPrimary : context.colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              Icon(
                widget.isExpanded ? Icons.expand_more : Icons.chevron_right,
                size: 14,
                color: _isHovered ? context.colors.accent : context.colors.divider,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Library item with hover animation
class _LibraryItemWidget extends StatefulWidget {
  final String name;
  final bool isFavorite;

  const _LibraryItemWidget({
    required this.name,
    this.isFavorite = false,
  });

  @override
  State<_LibraryItemWidget> createState() => _LibraryItemWidgetState();
}

class _LibraryItemWidgetState extends State<_LibraryItemWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.only(left: 14, right: 18, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: _isHovered ? context.colors.elevated : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: _isHovered ? context.colors.accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.name,
                style: TextStyle(
                  color: _isHovered ? context.colors.textPrimary : context.colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            if (widget.isFavorite)
              const Icon(
                Icons.star,
                size: 12,
                color: Colors.amber,
              ),
          ],
        ),
      ),
    );
  }
}
