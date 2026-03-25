import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../theme/app_colors.dart';
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
  final VoidCallback? onLeftColumnDragStart;
  final VoidCallback? onLeftColumnDragEnd;

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
    this.onLeftColumnDragStart,
    this.onLeftColumnDragEnd,
  });

  @override
  State<LibraryPanel> createState() => _LibraryPanelState();
}

class _LibraryPanelState extends State<LibraryPanel> {
  // Currently selected category in left column (null = no selection)
  String? _selectedCategory;

  // Currently selected item in right column (for blue pill highlight)
  String? _selectedItemId;

  // Per-category memory (saved state for each category)
  final Map<String, _CategoryState> _categoryStates = {};

  // Keyboard navigation
  final FocusNode _libraryFocusNode = FocusNode();
  bool _focusOnRightPanel = false; // false = left panel, true = right panel

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
    _libraryFocusNode.dispose();
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
    final colors = context.colors;

    return GestureDetector(
        onTap: () => _libraryFocusNode.requestFocus(),
        behavior: HitTestBehavior.translucent,
        child: Focus(
          focusNode: _libraryFocusNode,
          onKeyEvent: _handleKeyEvent,
          child: ColoredBox(
          color: colors.dark,
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
                          // Right column - Contents only (preview bar moved to full width)
                          Expanded(
                            child: _buildContentsView(),
                          ),
                        ],
                      ),
              ),
              // Preview bar — full width below both columns
              const LibraryPreviewBar(),
            ],
          ),
        ),
        ),
        );
  }

  /// Get ordered list of category IDs for keyboard navigation
  List<String> _getCategoryIds() {
    final ids = <String>['favorites', 'sounds', 'samples', 'instruments', 'effects', 'plugins'];
    for (final path in widget.libraryService.userFolderPaths) {
      ids.add('folder_${path.hashCode}');
    }
    return ids;
  }

  /// Get ordered list of item IDs in the current right panel view
  List<String> _getRightPanelItemIds() {
    if (_selectedCategory == null) return [];
    final ids = <String>[];
    final builtInCategories = widget.libraryService.getBuiltInCategories();
    for (final cat in builtInCategories) {
      if (cat.id != _selectedCategory) continue;
      for (final sub in cat.subcategories) {
        for (final item in sub.items) {
          ids.add(item.id);
        }
      }
      for (final item in cat.items) {
        ids.add(item.id);
      }
    }
    // Add VST3 plugin IDs for plugins category
    if (_selectedCategory == 'plugins') {
      for (final plugin in widget.availableVst3Plugins) {
        ids.add('vst3_${plugin['path']}');
      }
    }
    // Add user folder contents (recursively include nested folder contents)
    if (_selectedCategory?.startsWith('folder_') ?? false) {
      _collectFolderItemIds(_selectedCategory!, ids);
    }
    return ids;
  }

  /// Recursively collect non-folder item IDs from cached folder contents
  void _collectFolderItemIds(String folderId, List<String> ids) {
    final contents = _folderContentsCache[folderId];
    if (contents == null) return;
    for (final item in contents) {
      if (item is FolderItem) {
        final nestedId = 'nested_folder_${item.folderPath.hashCode}';
        _collectFolderItemIds(nestedId, ids);
      } else {
        ids.add(item.id);
      }
    }
  }

  /// Handle keyboard events for arrow navigation
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (_focusOnRightPanel) {
      // Right panel navigation
      final itemIds = _getRightPanelItemIds();
      if (itemIds.isEmpty) return KeyEventResult.ignored;

      final currentIndex = _selectedItemId != null ? itemIds.indexOf(_selectedItemId!) : -1;

      if (key == LogicalKeyboardKey.arrowDown) {
        final next = (currentIndex + 1).clamp(0, itemIds.length - 1);
        setState(() => _selectedItemId = itemIds[next]);
        print('[LIBRARY-NAV] Arrow down → selected: ${itemIds[next]}, previewing...');
        _previewSelectedItem();
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowUp) {
        final prev = (currentIndex - 1).clamp(0, itemIds.length - 1);
        setState(() => _selectedItemId = itemIds[prev]);
        print('[LIBRARY-NAV] Arrow up → selected: ${itemIds[prev]}, previewing...');
        _previewSelectedItem();
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        // Return focus to left panel
        setState(() => _focusOnRightPanel = false);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.enter) {
        // Load the item (same as double-click)
        if (_selectedItemId != null) {
          _loadSelectedItem();
        }
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.space) {
        // Preview the item (same as single-click)
        if (_selectedItemId != null) {
          _previewSelectedItem();
        }
        return KeyEventResult.handled;
      }
    } else {
      // Left panel navigation
      final categoryIds = _getCategoryIds();
      final currentIndex = _selectedCategory != null ? categoryIds.indexOf(_selectedCategory!) : -1;

      if (key == LogicalKeyboardKey.arrowDown) {
        final next = (currentIndex + 1).clamp(0, categoryIds.length - 1);
        _switchToCategory(categoryIds[next]);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowUp) {
        final prev = (currentIndex - 1).clamp(0, categoryIds.length - 1);
        _switchToCategory(categoryIds[prev]);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.enter) {
        // Move focus to right panel
        if (_selectedCategory != null) {
          setState(() {
            _focusOnRightPanel = true;
            // Select first item if nothing selected
            if (_selectedItemId == null) {
              final itemIds = _getRightPanelItemIds();
              if (itemIds.isNotEmpty) {
                _selectedItemId = itemIds.first;
              }
            }
          });
        }
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _switchToCategory(String categoryId) {
    setState(() {
      _saveCurrentCategoryState();
      _selectedCategory = categoryId;
      _restoreCategoryState(categoryId);
    });
    // Load user folder contents if not cached
    if (categoryId.startsWith('folder_') && !_folderContentsCache.containsKey(categoryId)) {
      final userFolders = widget.libraryService.userFolderPaths;
      for (final path in userFolders) {
        if ('folder_${path.hashCode}' == categoryId) {
          widget.libraryService.scanFolder(path).then((contents) {
            if (mounted) {
              setState(() {
                _folderContentsCache[categoryId] = contents;
              });
            }
          });
          break;
        }
      }
    }
  }

  void _loadSelectedItem() {
    final itemId = _selectedItemId;
    if (itemId == null) return;

    // Find the item and trigger double-click
    final builtInCategories = widget.libraryService.getBuiltInCategories();
    for (final cat in builtInCategories) {
      for (final sub in cat.subcategories) {
        for (final item in sub.items) {
          if (item.id == itemId) {
            widget.onItemDoubleClick?.call(item);
            return;
          }
        }
      }
      for (final item in cat.items) {
        if (item.id == itemId) {
          widget.onItemDoubleClick?.call(item);
          return;
        }
      }
    }

    // Check VST3 plugins
    if (itemId.startsWith('vst3_')) {
      for (final plugin in widget.availableVst3Plugins) {
        if ('vst3_${plugin['path']}' == itemId) {
          widget.onVst3DoubleClick?.call(Vst3Plugin.fromMap(plugin));
          return;
        }
      }
    }

    // Check user folder contents
    for (final contents in _folderContentsCache.values) {
      final item = _findItemInContents(contents, itemId);
      if (item != null) {
        widget.onItemDoubleClick?.call(item);
        return;
      }
    }
  }

  void _previewSelectedItem() {
    final itemId = _selectedItemId;
    if (itemId == null) return;

    // Search built-in categories
    final builtInCategories = widget.libraryService.getBuiltInCategories();
    for (final cat in builtInCategories) {
      for (final sub in cat.subcategories) {
        for (final item in sub.items) {
          if (item.id == itemId) {
            _handleItemClick(item);
            return;
          }
        }
      }
      for (final item in cat.items) {
        if (item.id == itemId) {
          _handleItemClick(item);
          return;
        }
      }
    }

    // Search user folder contents
    for (final contents in _folderContentsCache.values) {
      final item = _findItemInContents(contents, itemId);
      if (item != null) {
        _handleItemClick(item);
        return;
      }
    }
  }

  /// Recursively find an item by ID in folder contents
  LibraryItem? _findItemInContents(List<LibraryItem> contents, String itemId) {
    for (final item in contents) {
      if (item.id == itemId) return item;
      if (item is FolderItem) {
        final nestedId = 'nested_folder_${item.folderPath.hashCode}';
        final nestedContents = _folderContentsCache[nestedId];
        if (nestedContents != null) {
          final found = _findItemInContents(nestedContents, itemId);
          if (found != null) return found;
        }
      }
    }
    return null;
  }

  /// Save the current category's state (selected item, scroll, expanded folders)
  void _saveCurrentCategoryState() {
    final cat = _selectedCategory;
    if (cat == null) return;
    _categoryStates[cat] = _CategoryState(
      selectedItemId: _selectedItemId,
      scrollOffset: _rightScrollController.hasClients ? _rightScrollController.offset : 0.0,
      expandedFolders: Set.of(_expandedItems),
    );
  }

  /// Restore a category's saved state
  void _restoreCategoryState(String categoryId) {
    final saved = _categoryStates[categoryId];
    if (saved != null) {
      _selectedItemId = saved.selectedItemId;
      _expandedItems
        ..clear()
        ..addAll(saved.expandedFolders);
      // Restore scroll position after the frame builds
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_rightScrollController.hasClients && saved.scrollOffset > 0) {
          _rightScrollController.jumpTo(
            saved.scrollOffset.clamp(0.0, _rightScrollController.position.maxScrollExtent),
          );
        }
      });
    } else {
      _selectedItemId = null;
    }
  }

  /// Returns (icon, label) for a category ID, or null for user folders
  (IconData, String)? _categoryMeta(String? id) {
    return switch (id) {
      'favorites'   => (Icons.star, 'Favorites'),
      'sounds'      => (Icons.music_note, 'Sounds'),
      'samples'     => (Icons.graphic_eq, 'Samples'),
      'instruments' => (Icons.piano, 'Instruments'),
      'effects'     => (Icons.bolt, 'Effects'),
      'plugins'     => (Icons.extension, 'Plugins'),
      _ => null,
    };
  }

  /// Returns the display name for a category (including user folders)
  String _categoryLabel(String id) {
    final meta = _categoryMeta(id);
    if (meta != null) return meta.$2;
    // User folder — extract folder name from path
    final userFolders = widget.libraryService.userFolderPaths;
    for (final path in userFolders) {
      if ('folder_${path.hashCode}' == id) {
        return path.split('/').last;
      }
    }
    return 'Library';
  }

  Widget _buildCombinedHeader() {
    final colors = context.colors;
    final showChip = _searchQuery.isNotEmpty && _selectedCategory != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.dark,
        border: Border(
          bottom: BorderSide(color: colors.divider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final placeholder = _selectedCategory != null
                  ? 'Search ${_categoryLabel(_selectedCategory!).toLowerCase()}...'
                  : 'Search all...';
              return Align(
                alignment: Alignment.centerLeft,
                child: SearchField(
                  controller: _searchController,
                  expandedWidth: constraints.maxWidth,
                  hintText: placeholder,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              );
            },
          ),
          // Scoped search chip
          if (showChip) ...[
            const SizedBox(height: 6),
            _buildSearchScopeChip(colors),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchScopeChip(BoojyColors colors) {
    final meta = _categoryMeta(_selectedCategory);
    final icon = meta?.$1 ?? Icons.folder;
    final label = _selectedCategory != null
        ? _categoryLabel(_selectedCategory!)
        : 'All';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.elevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colors.textMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategory = null;
              });
            },
            child: Icon(Icons.close, size: 12, color: colors.textMuted),
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
      onDragStart: widget.onLeftColumnDragStart,
      onDragEnd: widget.onLeftColumnDragEnd,
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

    return ColoredBox(
      color: colors.dark,
      child: ListView(
        controller: _leftScrollController,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          // System categories
          _buildCategoryItem('favorites', Icons.star, 'Favorites'),
          _buildCategoryItem('sounds', Icons.music_note, 'Sounds'),
          _buildCategoryItem('samples', Icons.graphic_eq, 'Samples'),
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
    final hasChildSelected = isSelected && _selectedItemId != null;

    return _CategoryItemWidget(
      icon: icon,
      label: label,
      isSelected: isSelected,
      hasChildSelected: hasChildSelected,
      onTap: () {
        setState(() {
          if (_selectedCategory == id) {
            // Deselect — save state first
            _saveCurrentCategoryState();
            _selectedCategory = null;
            _selectedItemId = null;
          } else {
            // Save outgoing category state
            _saveCurrentCategoryState();
            // Switch to new category
            _selectedCategory = id;
            // Restore incoming category state
            _restoreCategoryState(id);
          }
        });
        if (_selectedCategory == id && isUserFolder && folderPath != null && !_folderContentsCache.containsKey(id)) {
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
    );
  }

  Widget _buildAddFolderButton() {
    final colors = context.colors;
    return GestureDetector(
      onTap: _addUserFolder,
      child: Container(
        margin: const EdgeInsets.only(left: 5, right: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          children: [
            Icon(Icons.add, size: 16, color: colors.textMuted),
            const SizedBox(width: 8),
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
              Icon(Icons.folder_open, size: 16),
              SizedBox(width: 8),
              Text('Show in Finder'),
            ],
          ),
          onTap: () => Process.run('open', ['-R', path]),
        ),
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

  Widget _buildContentsView() {
    final colors = context.colors;

    if (_selectedCategory == null) {
      return ColoredBox(
        color: colors.darkest,
        child: Center(
          child: Text(
            'Select a category\nor search to browse.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: colors.textMuted,
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: colors.darkest,
      child: ListView(
        controller: _rightScrollController,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: _buildContentsForCategory(_selectedCategory!),
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
      return [_buildEmptyState('No favorites yet.', subtitle: 'Right-click any item to add it here.')];
    }

    return favoriteItems.map((item) => _buildLibraryItem(item)).toList();
  }

  List<Widget> _buildNestedCategoryContents(LibraryCategory category) {
    if (category.subcategories.isEmpty) {
      return [_buildEmptyState('No ${category.name.toLowerCase()} yet.')];
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
      return [_buildEmptyState('No plugins found.', subtitle: 'Install VST3 plugins to see them here.')];
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
    return _ExpandableHeaderWidget(
      icon: icon,
      title: title,
      isExpanded: isExpanded,
      onTap: onTap,
    );
  }

  Widget _buildEmptyState(String message, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textMuted,
                fontSize: 13,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ],
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
    final query = _searchQuery.toLowerCase();
    final scope = _selectedCategory;

    // Determine which categories to search
    bool shouldSearchCategory(String categoryId) {
      if (scope == null) return true; // search everything
      if (scope.startsWith('folder_')) return false; // user folder scope — handled below
      return scope == categoryId;
    }

    // Search built-in categories
    for (final category in builtInCategories) {
      if (!shouldSearchCategory(category.id)) continue;
      for (final sub in category.subcategories) {
        for (final item in sub.items) {
          if (item.matchesSearch(_searchQuery)) {
            results.add(_SearchResult(item: item));
          }
        }
      }
      for (final item in category.items) {
        if (item.matchesSearch(_searchQuery)) {
          results.add(_SearchResult(item: item));
        }
      }
    }

    // Search VST3 plugins
    if (shouldSearchCategory('plugins')) {
      for (final plugin in widget.availableVst3Plugins) {
        final name = plugin['name']?.toLowerCase() ?? '';
        if (name.contains(query)) {
          results.add(_SearchResult(vst3Plugin: plugin));
        }
      }
    }

    // Search user folder contents
    if (scope == null || scope.startsWith('folder_')) {
      for (final entry in _folderContentsCache.entries) {
        // If scoped to a specific folder, only search that folder
        if (scope != null && entry.key != scope) continue;
        for (final item in entry.value) {
          if (item.matchesSearch(_searchQuery)) {
            results.add(_SearchResult(item: item));
          }
        }
      }
    }

    if (results.isEmpty) {
      return _buildEmptyState('No results for "$_searchQuery"');
    }

    // Sort A-Z by display name
    results.sort((a, b) {
      final nameA = a.displayName.toLowerCase();
      final nameB = b.displayName.toLowerCase();
      return nameA.compareTo(nameB);
    });

    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Result count header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
          child: Text(
            '${results.length} result${results.length == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 11, color: colors.textMuted),
          ),
        ),
        // Flat A-Z list with type icons
        Expanded(
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final result = results[index];
              if (result.item != null) {
                return _buildLibraryItem(result.item!);
              } else if (result.vst3Plugin != null) {
                final isInstrument = result.vst3Plugin!['is_instrument'] == '1';
                return _buildVst3PluginItem(result.vst3Plugin!, isInstrument);
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
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
      onTap: () {
        _libraryFocusNode.requestFocus();
        setState(() {
          _selectedItemId = item.id;
          _focusOnRightPanel = true;
        });
        _handleItemClick(item);
      },
      onDoubleTap: () => widget.onItemDoubleClick?.call(item),
      onSecondaryTapUp: (details) => _showItemContextMenu(details, item),
      child: _LibraryItemWidget(
        key: ValueKey(item.id),
        name: item.displayName,
        indent: indent,
        isFavorite: widget.libraryService.isFavorite(item.id),
        isPreviewing: isCurrentlyPreviewing,
        isSelected: _selectedItemId == item.id,
        typeIcon: _typeIconFor(item),
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
        feedback: _buildDragFeedback(item.displayName, Icons.graphic_eq),
        childWhenDragging: Opacity(opacity: 0.5, child: child),
        onDragStarted: _handleDragStarted,
        child: child,
      );
    } else if (item.type == LibraryItemType.midiFile && item is MidiFileItem) {
      child = Draggable<MidiFileItem>(
        data: item,
        feedback: _buildDragFeedback(item.displayName, Icons.music_note),
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
        child: _LibraryItemWidget(name: name, indent: indent, typeIcon: isInstrument ? Icons.piano : Icons.graphic_eq),
      ),
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedItemId = 'vst3_${plugin.path}';
          _focusOnRightPanel = true;
        }),
        onDoubleTap: () => widget.onVst3DoubleClick?.call(plugin),
        onSecondaryTapUp: (details) => _showVst3ContextMenu(details, plugin),
        child: _LibraryItemWidget(
          key: ValueKey('vst3_${plugin.path}'),
          name: name,
          indent: indent,
          isFavorite: widget.libraryService.isFavorite('vst3_${plugin.path}'),
          isSelected: _selectedItemId == 'vst3_${plugin.path}',
          typeIcon: isInstrument ? Icons.piano : Icons.graphic_eq,
        ),
      ),
    );
  }

  Widget _buildDragFeedback(String name, IconData icon) {
    final colors = context.colors;
    return Material(
      color: Colors.transparent,
      child: Opacity(
        opacity: 0.75,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: colors.elevated,
            border: Border.all(color: colors.divider),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                offset: Offset(0, 4),
                blurRadius: 16,
                color: Color.fromRGBO(0, 0, 0, 0.4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: colors.textMuted, size: 14),
              const SizedBox(width: 6),
              Text(
                name,
                style: TextStyle(
                  color: colors.textPrimary,
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

  void _showItemContextMenu(TapUpDetails details, LibraryItem item) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final isFavorite = widget.libraryService.isFavorite(item.id);
    final isAudioFile = item.type == LibraryItemType.audioFile || item.type == LibraryItemType.sample;
    final isInstrument = item.type == LibraryItemType.instrument;
    final isEffect = item.type == LibraryItemType.effect;
    final hasFilePath = item is AudioFileItem || item is SampleItem;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry>[
        // Load actions for instruments
        if (isInstrument)
          PopupMenuItem(
            child: const Row(
              children: [
                Icon(Icons.play_arrow, size: 16),
                SizedBox(width: 8),
                Text('Load on Selected Track'),
              ],
            ),
            onTap: () => widget.onItemDoubleClick?.call(item),
          ),
        // Add action for effects
        if (isEffect)
          PopupMenuItem(
            child: const Row(
              children: [
                Icon(Icons.add, size: 16),
                SizedBox(width: 8),
                Text('Add to Selected Track'),
              ],
            ),
            onTap: () => widget.onItemDoubleClick?.call(item),
          ),
        // Open in Sampler for audio files
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
        // Favorites toggle
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
        // File actions
        if (hasFilePath) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            child: const Row(
              children: [
                Icon(Icons.folder_open, size: 16),
                SizedBox(width: 8),
                Text('Show in Finder'),
              ],
            ),
            onTap: () {
              final path = item is AudioFileItem ? item.filePath : (item as SampleItem).filePath;
              Process.run('open', ['-R', path]);
            },
          ),
          PopupMenuItem(
            child: const Row(
              children: [
                Icon(Icons.copy, size: 16),
                SizedBox(width: 8),
                Text('Copy Path'),
              ],
            ),
            onTap: () {
              final path = item is AudioFileItem ? item.filePath : (item as SampleItem).filePath;
              Clipboard.setData(ClipboardData(text: path));
            },
          ),
        ],
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
          child: const Row(
            children: [
              Icon(Icons.play_arrow, size: 16),
              SizedBox(width: 8),
              Text('Load on Selected Track'),
            ],
          ),
          onTap: () => widget.onVst3DoubleClick?.call(plugin),
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
          onTap: () => widget.libraryService.toggleFavorite(itemId),
        ),
      ],
    );
  }

  /// Returns the type icon for a library item
  IconData _typeIconFor(LibraryItem item) {
    switch (item.type) {
      case LibraryItemType.preset:
        return Icons.music_note;
      case LibraryItemType.sample:
      case LibraryItemType.audioFile:
        return Icons.graphic_eq;
      case LibraryItemType.instrument:
        return Icons.piano;
      case LibraryItemType.effect:
        return Icons.bolt;
      case LibraryItemType.vst3Instrument:
      case LibraryItemType.vst3Effect:
        return Icons.extension;
      case LibraryItemType.folder:
        return Icons.folder;
      case LibraryItemType.midiFile:
        return Icons.music_note;
    }
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

/// Category item widget with hover and selection pill
class _CategoryItemWidget extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool hasChildSelected;
  final VoidCallback onTap;
  final void Function(TapUpDetails)? onSecondaryTapUp;

  const _CategoryItemWidget({
    required this.icon,
    required this.label,
    required this.isSelected,
    this.hasChildSelected = false,
    required this.onTap,
    this.onSecondaryTapUp,
  });

  @override
  State<_CategoryItemWidget> createState() => _CategoryItemWidgetState();
}

class _CategoryItemWidgetState extends State<_CategoryItemWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isSelected = widget.isSelected;

    final faded = widget.hasChildSelected;
    final isActive = isSelected && !faded;
    final isInactive = isSelected && faded;

    // Pill states: active > inactive > hover > default
    Color bgColor;
    List<BoxShadow>? shadow;
    if (isActive) {
      bgColor = colors.accent.withValues(alpha: 0.4);
      shadow = [BoxShadow(color: colors.accent.withValues(alpha: 0.1), blurRadius: 8)];
    } else if (isInactive) {
      bgColor = colors.accent.withValues(alpha: 0.15);
    } else if (_isHovered) {
      bgColor = colors.accent.withValues(alpha: 0.12);
    } else {
      bgColor = Colors.transparent;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapUp: widget.onSecondaryTapUp,
        child: Container(
          margin: const EdgeInsets.only(left: 5, right: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
            boxShadow: shadow,
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: isActive ? colors.accent : colors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 14,
                    color: isActive || _isHovered ? colors.textPrimary : colors.textSecondary,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Expandable header widget with hover pill
class _ExpandableHeaderWidget extends StatefulWidget {
  final IconData icon;
  final String title;
  final bool isExpanded;
  final VoidCallback onTap;

  const _ExpandableHeaderWidget({
    required this.icon,
    required this.title,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  State<_ExpandableHeaderWidget> createState() => _ExpandableHeaderWidgetState();
}

class _ExpandableHeaderWidgetState extends State<_ExpandableHeaderWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(left: 5, right: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _isHovered ? colors.accent.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(
                widget.isExpanded ? Icons.expand_more : Icons.chevron_right,
                size: 14,
                color: colors.textMuted,
              ),
              const SizedBox(width: 4),
              Icon(widget.icon, size: 14, color: colors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 14,
                    color: _isHovered ? colors.textPrimary : colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Saved state for a category (for per-category memory)
class _CategoryState {
  String? selectedItemId;
  double scrollOffset;
  Set<String> expandedFolders;

  _CategoryState({
    this.selectedItemId,
    this.scrollOffset = 0.0,
    Set<String>? expandedFolders,
  }) : expandedFolders = expandedFolders ?? {};
}

/// Search result wrapper
class _SearchResult {
  final LibraryItem? item;
  final Map<String, String>? vst3Plugin;

  _SearchResult({
    this.item,
    this.vst3Plugin,
  });

  String get displayName =>
      item?.displayName ?? vst3Plugin?['name'] ?? 'Unknown';
}

/// Library item widget with hover and indentation
class _LibraryItemWidget extends StatefulWidget {
  final String name;
  final int indent;
  final bool isFavorite;
  final bool isPreviewing;
  final bool isSelected;
  final IconData? typeIcon;

  const _LibraryItemWidget({
    super.key,
    required this.name,
    this.indent = 0,
    this.isFavorite = false,
    this.isPreviewing = false,
    this.isSelected = false,
    this.typeIcon,
  });

  @override
  State<_LibraryItemWidget> createState() => _LibraryItemWidgetState();
}

class _LibraryItemWidgetState extends State<_LibraryItemWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final isActive = widget.isSelected;

    // Pill states: active > hover > default (same as category widget)
    Color bgColor;
    List<BoxShadow>? shadow;
    if (isActive) {
      bgColor = colors.accent.withValues(alpha: 0.4);
      shadow = [BoxShadow(color: colors.accent.withValues(alpha: 0.1), blurRadius: 8)];
    } else if (_isHovered) {
      bgColor = colors.accent.withValues(alpha: 0.12);
    } else {
      bgColor = Colors.transparent;
    }

    // Icon color: active = accent, previewing = accent, default = muted
    final iconColor = isActive || widget.isPreviewing ? colors.accent : colors.textMuted;

    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        margin: EdgeInsets.only(left: 5.0 + (widget.indent * 16.0), right: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          boxShadow: shadow,
        ),
        child: Row(
          children: [
            if (widget.isPreviewing) ...[
              Icon(Icons.volume_up, size: 14, color: iconColor),
              const SizedBox(width: 6),
            ] else if (widget.typeIcon != null) ...[
              Icon(widget.typeIcon, size: 14, color: iconColor),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textStyle = TextStyle(
                    color: isActive || widget.isPreviewing
                        ? colors.textPrimary
                        : (_isHovered ? colors.textPrimary : colors.textSecondary),
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
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
