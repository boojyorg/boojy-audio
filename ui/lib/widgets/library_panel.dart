import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'instrument_browser.dart';
import '../models/library_item.dart';
import '../models/vst3_plugin_data.dart';
import '../services/library_service.dart';

/// Library panel widget - left sidebar with browsable content categories
class LibraryPanel extends StatefulWidget {
  final bool isCollapsed;
  final VoidCallback? onToggle;
  final List<Map<String, String>> availableVst3Plugins;
  final LibraryService libraryService;
  final void Function(LibraryItem)? onItemDoubleClick;
  final void Function(Vst3Plugin)? onVst3DoubleClick;

  const LibraryPanel({
    super.key,
    this.isCollapsed = false,
    this.onToggle,
    this.availableVst3Plugins = const [],
    required this.libraryService,
    this.onItemDoubleClick,
    this.onVst3DoubleClick,
  });

  @override
  State<LibraryPanel> createState() => _LibraryPanelState();
}

class _LibraryPanelState extends State<LibraryPanel> {
  // Top-level category IDs for accordion behavior
  static const _topLevelCategories = {'favorites', 'sounds', 'samples', 'instruments', 'effects', 'plugins', 'folders'};

  final Set<String> _expandedCategories = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  /// Expand a category with accordion behavior
  /// - For top-level: close other top-level categories but KEEP their children
  ///   (children won't render since parent is collapsed, but will restore when parent reopens)
  /// - For subcategories: close sibling subcategories
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

  @override
  void initState() {
    super.initState();
    widget.libraryService.addListener(_onLibraryChanged);
  }

  @override
  void dispose() {
    widget.libraryService.removeListener(_onLibraryChanged);
    _searchController.dispose();
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

    return Container(
      width: 200,
      decoration: const BoxDecoration(
        color: Color(0xFF242424),
        border: Border(
          right: BorderSide(color: Color(0xFF363636)),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildSearchBar(),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: _buildCategoryList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedPanel() {
    return Container(
      width: 40,
      decoration: const BoxDecoration(
        color: Color(0xFF242424),
        border: Border(
          right: BorderSide(color: Color(0xFF363636)),
        ),
      ),
      child: Column(
        children: [
          IconButton(
            icon: const Icon(Icons.menu),
            color: const Color(0xFF9E9E9E),
            onPressed: widget.onToggle,
            tooltip: 'Show Library (B)',
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF363636),
        border: Border(
          bottom: BorderSide(color: Color(0xFF363636)),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.library_music,
            color: Color(0xFFE0E0E0),
            size: 18,
          ),
          const SizedBox(width: 8),
          const Text(
            'LIBRARY',
            style: TextStyle(
              color: Color(0xFFE0E0E0),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (widget.onToggle != null)
            IconButton(
              icon: const Icon(Icons.chevron_left),
              color: const Color(0xFF9E9E9E),
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

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF2A2A2A),
        border: Border(
          bottom: BorderSide(color: Color(0xFF363636)),
        ),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        style: const TextStyle(
          color: Color(0xFFE0E0E0),
          fontSize: 12,
        ),
        decoration: InputDecoration(
          hintText: 'Search...',
          hintStyle: const TextStyle(
            color: Color(0xFF707070),
            fontSize: 12,
          ),
          prefixIcon: const Icon(
            Icons.search,
            color: Color(0xFF707070),
            size: 16,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 28,
            minHeight: 28,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                  child: const Icon(
                    Icons.close,
                    color: Color(0xFF707070),
                    size: 14,
                  ),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 28,
            minHeight: 28,
          ),
          filled: true,
          fillColor: const Color(0xFF1E1E1E),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide.none,
          ),
          isDense: true,
        ),
      ),
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

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF363636)),
        ),
      ),
      child: Column(
        children: [
          _CategoryHeader(
            icon: icon,
            title: title,
            isExpanded: isExpanded,
            showAddButton: showAddButton,
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCategories.remove(id);
                } else {
                  _expandWithAccordion(id);
                }
              });
            },
            onAddPressed: onAddPressed,
          ),
          if (isExpanded)
            Container(
              padding: const EdgeInsets.only(left: 20, bottom: 8),
              color: const Color(0xFF242424),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: items.isEmpty
                    ? [
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                          child: Text(
                            'No items',
                            style: TextStyle(
                              color: Color(0xFF707070),
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

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF363636)),
        ),
      ),
      child: Column(
        children: [
          _CategoryHeader(
            icon: category.icon,
            title: category.name,
            isExpanded: isExpanded,
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCategories.remove(category.id);
                } else {
                  _expandWithAccordion(category.id);
                }
              });
            },
          ),
          if (isExpanded)
            Container(
              color: const Color(0xFF242424),
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
                        onTap: () {
                          setState(() {
                            if (isSubExpanded) {
                              _expandedCategories.remove(subId);
                            } else {
                              _expandWithAccordion(subId);
                            }
                          });
                        },
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

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF363636)),
        ),
      ),
      child: Column(
        children: [
          _CategoryHeader(
            icon: Icons.extension,
            title: 'Plugins',
            isExpanded: isExpanded,
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCategories.remove('plugins');
                } else {
                  _expandWithAccordion('plugins');
                }
              });
            },
          ),
          if (isExpanded)
            Container(
              color: const Color(0xFF242424),
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
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedCategories.remove(id);
              } else {
                _expandWithAccordion(id);
              }
            });
          },
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
                          style: const TextStyle(
                            color: Color(0xFF707070),
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

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF363636)),
        ),
      ),
      child: Column(
        children: [
          _CategoryHeader(
            icon: Icons.folder,
            title: 'Folders',
            isExpanded: isExpanded,
            showAddButton: true,
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCategories.remove('folders');
                } else {
                  _expandWithAccordion('folders');
                }
              });
            },
            onAddPressed: _addUserFolder,
          ),
          if (isExpanded)
            Container(
              padding: const EdgeInsets.only(left: 20, bottom: 8),
              color: const Color(0xFF242424),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: folderPaths.isEmpty
                    ? [
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                          child: Text(
                            'Click + to add folders',
                            style: TextStyle(
                              color: Color(0xFF707070),
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
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCategories.remove(folderId);
                } else {
                  _expandWithAccordion(folderId);
                  // Scan folder when expanded
                  widget.libraryService.scanFolder(path);
                }
              });
            },
          ),
        ),
        if (isExpanded)
          FutureBuilder<List<LibraryItem>>(
            future: widget.libraryService.scanFolder(path),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
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

              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 6),
                  child: Text(
                    'Empty folder',
                    style: TextStyle(
                      color: Color(0xFF707070),
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
            },
          ),
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
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedCategories.remove(folderId);
              } else {
                _expandWithAccordion(folderId);
              }
            });
          },
        ),
        if (isExpanded)
          FutureBuilder<List<LibraryItem>>(
            future: widget.libraryService.scanFolder(folder.folderPath),
            builder: (context, snapshot) {
              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 6),
                  child: Text(
                    'Empty',
                    style: TextStyle(
                      color: Color(0xFF707070),
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
            },
          ),
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
          color: const Color(0xFF00BCD4),
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
          color: _isHovered ? const Color(0xFF363636) : Colors.transparent,
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: _isHovered ? const Color(0xFF00BCD4) : const Color(0xFF9E9E9E),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    color: _isHovered ? const Color(0xFFE0E0E0) : const Color(0xFFBDBDBD),
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
                    color: _isHovered ? const Color(0xFF00BCD4) : const Color(0xFF616161),
                  ),
                ),
              if (widget.showAddButton) const SizedBox(width: 8),
              Icon(
                widget.isExpanded ? Icons.expand_more : Icons.chevron_right,
                size: 18,
                color: _isHovered ? const Color(0xFF00BCD4) : const Color(0xFF616161),
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
          color: _isHovered ? const Color(0xFF333333) : Colors.transparent,
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: _isHovered ? const Color(0xFF00BCD4) : const Color(0xFF808080),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    color: _isHovered ? const Color(0xFFE0E0E0) : const Color(0xFFA0A0A0),
                    fontSize: 12,
                  ),
                ),
              ),
              Icon(
                widget.isExpanded ? Icons.expand_more : Icons.chevron_right,
                size: 14,
                color: _isHovered ? const Color(0xFF00BCD4) : const Color(0xFF606060),
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
          color: _isHovered ? const Color(0xFF363636) : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: _isHovered ? const Color(0xFF00BCD4) : Colors.transparent,
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
                  color: _isHovered ? const Color(0xFFE0E0E0) : const Color(0xFF9E9E9E),
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
