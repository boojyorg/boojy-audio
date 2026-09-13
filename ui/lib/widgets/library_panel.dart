import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'instrument_browser.dart';
import 'library_preview_bar.dart';
import 'shared/boojy_tooltip.dart';
import 'shared/search_field.dart';
import '../models/library_item.dart';
import '../models/vst3_plugin_data.dart';
import '../services/library_preview_service.dart';
import '../services/library_service.dart';
import '../theme/app_colors.dart';
import '../theme/boojy_icons.dart';
import '../theme/theme_extension.dart';
import '../theme/tokens.dart';
import '../utils/native_dialogs.dart';
import 'shared/boojy_dropdown.dart';

/// Library panel — one full-width expandable tree.
///
/// Root rows (Favorites, Sounds, Samples, Instruments, Effects, Plugins and
/// each user folder) carry an icon and a label but no chevron: clicking the
/// row toggles it. Subfolders below a root use a chevron in place of a folder
/// icon, so every level indents by the same [_indentUnit]. Several roots can
/// be open at once; opening one never closes another.
///
/// Three kinds of feedback stay distinct: hover (faint pill), selection (the
/// accent pill, items only — expanding a root or folder never selects it) and
/// keyboard focus (a thin ring, shown only after keyboard use).
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

/// Horizontal step per tree level. Also the width of the glyph slot (root
/// icon, subfolder chevron, file-type icon) so labels at one depth line up
/// whether the row is a folder or a file.
const double _indentUnit = 14.0;

/// Gap between the glyph slot and the label.
const double _glyphGap = 6.0;

enum _RowKind { root, folder, item, plugin, action, message, loading, divider }

/// One visible row of the tree. Built fresh on every frame from the
/// expansion set and the folder cache; keyboard navigation walks this list.
class _TreeRow {
  const _TreeRow({
    required this.key,
    required this.kind,
    this.id = '',
    this.parentKey,
    this.rootId,
    this.depth = 0,
    this.label = '',
    this.subtitle,
    this.icon,
    this.isExpanded = false,
    this.item,
    this.plugin,
    this.pluginIsInstrument = false,
    this.folderPath,
    this.isUserFolderRoot = false,
  });

  /// Unique within one build: the parent's key plus this row's [id]. The same
  /// file can appear under Favorites and under its own folder at the same
  /// time, so widget keys and the focus cursor use this, not [id].
  final String key;
  final _RowKind kind;

  /// Semantic id: root/folder ids drive the expansion set, item/plugin ids
  /// drive selection and favourites.
  final String id;
  final String? parentKey;

  /// The root this row lives under (null for search results).
  final String? rootId;
  final int depth;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final bool isExpanded;
  final LibraryItem? item;
  final Map<String, String>? plugin;
  final bool pluginIsInstrument;

  /// Set on rows that scan a folder from disk when expanded.
  final String? folderPath;
  final bool isUserFolderRoot;

  bool get isExpandable => kind == _RowKind.root || kind == _RowKind.folder;

  bool get isFocusable => switch (kind) {
    _RowKind.root ||
    _RowKind.folder ||
    _RowKind.item ||
    _RowKind.plugin ||
    _RowKind.action => true,
    _RowKind.message || _RowKind.loading || _RowKind.divider => false,
  };

  bool get isSelectable => kind == _RowKind.item || kind == _RowKind.plugin;
}

class _LibraryPanelState extends State<LibraryPanel> {
  /// Selected item (accent pill). Only items and plugins are selectable.
  String? _selectedItemId;

  /// Keyboard cursor: the [_TreeRow.key] of the focused row.
  String? _focusedRowKey;

  /// True after keyboard navigation, false after any pointer tap — the focus
  /// ring only shows for keyboard users, like `:focus-visible`.
  bool _keyboardFocusVisible = false;

  final FocusNode _libraryFocusNode = FocusNode();

  /// Expanded roots, subcategories and folders, keyed by [_TreeRow.id].
  final Set<String> _expandedIds = {};

  /// Root id that scopes search (the last root opened or browsed into), or
  /// null to search everything. Shown in the placeholder and as a chip.
  String? _searchScope;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';

  /// Folder contents by folder id, filled by [_scanFolder].
  final Map<String, List<LibraryItem>> _folderContentsCache = {};

  /// One GlobalKey per row key so keyboard navigation can scroll the focused
  /// row into view.
  final Map<String, GlobalKey> _rowKeys = {};

  /// Rows as of the last build — the list keyboard handlers navigate.
  List<_TreeRow> _visibleRows = const [];

  @override
  void initState() {
    super.initState();
    widget.libraryService.addListener(_onLibraryChanged);
    // The service may have finished loading (and pruning legacy favourites)
    // before this panel attached its listener — check once after mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowLegacyFavoritesNotice();
    });
  }

  @override
  void dispose() {
    widget.libraryService.removeListener(_onLibraryChanged);
    _searchController.dispose();
    _scrollController.dispose();
    _libraryFocusNode.dispose();
    super.dispose();
  }

  void _onLibraryChanged() {
    setState(() {});
    _maybeShowLegacyFavoritesNotice();
  }

  /// One-time upgrade notice: favourites saved before the path-based ID
  /// format can't be restored (the service prunes them on load), so tell the
  /// user instead of presenting a mysteriously empty Favorites view.
  void _maybeShowLegacyFavoritesNotice() {
    if (!widget.libraryService.takeLegacyFavoritesNotice()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your favourites were reset — the library index was upgraded',
          ),
        ),
      );
    });
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final searching = _searchQuery.isNotEmpty;
    final rows = searching ? _buildSearchRows() : _buildTreeRows();
    _visibleRows = rows;

    return GestureDetector(
      onTap: _libraryFocusNode.requestFocus,
      behavior: HitTestBehavior.translucent,
      child: Focus(
        focusNode: _libraryFocusNode,
        onKeyEvent: _handleKeyEvent,
        onFocusChange: (_) => setState(() {}),
        child: ColoredBox(
          color: colors.dark,
          child: Column(
            children: [
              _buildCombinedHeader(),
              Expanded(
                child: searching ? _buildSearchResults(rows) : _buildTree(rows),
              ),
              // Preview bar — full width below the tree
              const LibraryPreviewBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTree(List<_TreeRow> rows) {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: rows.map(_buildRowWidget).toList(),
    );
  }

  Widget _buildRowWidget(_TreeRow row) {
    final key = _rowKeys.putIfAbsent(row.key, GlobalKey.new);
    final isFocused =
        _keyboardFocusVisible &&
        _libraryFocusNode.hasFocus &&
        _focusedRowKey == row.key;

    final Widget child = switch (row.kind) {
      _RowKind.root => _RootRowWidget(
        icon: row.icon!,
        label: row.label,
        isExpanded: row.isExpanded,
        isFocused: isFocused,
        onTap: () => _onExpandableTap(row),
        onSecondaryTapUp: row.isUserFolderRoot && row.folderPath != null
            ? (details) => _showFolderContextMenu(details, row.folderPath!)
            : null,
      ),
      _RowKind.folder => _FolderRowWidget(
        label: row.label,
        depth: row.depth,
        isExpanded: row.isExpanded,
        isFocused: isFocused,
        onTap: () => _onExpandableTap(row),
      ),
      _RowKind.item => _buildLibraryItem(row, isFocused: isFocused),
      _RowKind.plugin => _buildVst3PluginItem(row, isFocused: isFocused),
      _RowKind.action => _AddFolderButton(
        isFocused: isFocused,
        onTap: () => _onActionTap(row),
      ),
      _RowKind.message => _buildMessageRow(row),
      _RowKind.loading => _buildLoadingRow(row),
      _RowKind.divider => _buildDividerRow(),
    };

    return KeyedSubtree(key: key, child: child);
  }

  // ==========================================================================
  // TREE MODEL
  // ==========================================================================

  /// Built-in roots in display order: (id, icon, label).
  List<(String, IconData, String)> get _builtInRoots => [
    ('favorites', BI.starFilled, 'Favorites'),
    ('sounds', BI.musicNote, 'Sounds'),
    ('samples', BI.equalizer, 'Samples'),
    ('instruments', BI.piano, 'Instruments'),
    ('effects', BI.lightning, 'Effects'),
    ('plugins', BI.plugin, 'Plugins'),
  ];

  List<_TreeRow> _buildTreeRows() {
    final rows = <_TreeRow>[];
    final categories = widget.libraryService.getBuiltInCategories();

    for (final (id, icon, label) in _builtInRoots) {
      final isExpanded = _expandedIds.contains(id);
      rows.add(
        _TreeRow(
          key: id,
          kind: _RowKind.root,
          id: id,
          rootId: id,
          label: label,
          icon: icon,
          isExpanded: isExpanded,
        ),
      );
      if (isExpanded) rows.addAll(_builtInChildren(id, categories));
    }

    final userFolders = widget.libraryService.userFolderPaths;
    if (userFolders.isNotEmpty) {
      rows.add(const _TreeRow(key: 'divider_user', kind: _RowKind.divider));
    }
    for (final path in userFolders) {
      final id = 'folder_$path';
      final isExpanded = _expandedIds.contains(id);
      rows.add(
        _TreeRow(
          key: id,
          kind: _RowKind.root,
          id: id,
          rootId: id,
          label: path.split('/').last,
          icon: BI.folder,
          isExpanded: isExpanded,
          folderPath: path,
          isUserFolderRoot: true,
        ),
      );
      if (isExpanded) {
        rows.addAll(
          _folderChildren(cacheId: id, parentKey: id, rootId: id, depth: 1),
        );
      }
    }

    rows.add(const _TreeRow(key: 'divider_add', kind: _RowKind.divider));
    rows.add(
      const _TreeRow(
        key: 'add_folder',
        kind: _RowKind.action,
        id: 'add_folder',
        label: 'Add Folder',
      ),
    );
    return rows;
  }

  List<_TreeRow> _builtInChildren(
    String rootId,
    List<LibraryCategory> categories,
  ) {
    switch (rootId) {
      case 'favorites':
        return _favoritesChildren(categories);
      case 'plugins':
        return _pluginChildren();
      default:
        final category = categories.firstWhere((c) => c.id == rootId);
        return _categoryChildren(category);
    }
  }

  List<_TreeRow> _favoritesChildren(List<LibraryCategory> categories) {
    final items = widget.libraryService.getFavoriteItems(categories);
    final plugins = _favoriteVst3Plugins();
    if (items.isEmpty && plugins.isEmpty) {
      return [
        _messageRow(
          parentKey: 'favorites',
          depth: 1,
          'No favorites yet.',
          subtitle: 'Right-click any item to add it here.',
        ),
      ];
    }
    return [
      for (final item in items)
        _itemRow(item, parentKey: 'favorites', rootId: 'favorites', depth: 1),
      for (final plugin in plugins)
        _pluginRow(
          plugin,
          isInstrument: plugin['is_instrument'] == '1',
          parentKey: 'favorites',
          rootId: 'favorites',
          depth: 1,
        ),
    ];
  }

  /// VST3 plugins whose `vst3_<path>` ID is favourited — the plugin list
  /// lives on this widget, not in LibraryService, so favourites for them
  /// are resolved here.
  List<Map<String, String>> _favoriteVst3Plugins() {
    return widget.availableVst3Plugins
        .where((p) => widget.libraryService.isFavorite('vst3_${p['path']}'))
        .toList();
  }

  /// Sounds, Samples, Instruments and Effects: top-level items (which may be
  /// lazily scanned folders, like the bundled Drums folder) then any
  /// subcategories as chevron rows.
  List<_TreeRow> _categoryChildren(LibraryCategory category) {
    final rootId = category.id;
    if (category.subcategories.isEmpty && category.items.isEmpty) {
      return [
        _messageRow(
          parentKey: rootId,
          depth: 1,
          'No ${category.name.toLowerCase()} yet.',
        ),
      ];
    }

    final rows = <_TreeRow>[
      ..._itemOrFolderRows(
        category.items,
        parentKey: rootId,
        rootId: rootId,
        depth: 1,
      ),
    ];
    for (final sub in category.subcategories) {
      final subId = '${rootId}_${sub.id}';
      final key = '$rootId/$subId';
      final isExpanded = _expandedIds.contains(subId);
      rows.add(
        _TreeRow(
          key: key,
          kind: _RowKind.folder,
          id: subId,
          parentKey: rootId,
          rootId: rootId,
          depth: 1,
          label: sub.name,
          isExpanded: isExpanded,
        ),
      );
      if (isExpanded) {
        if (sub.items.isEmpty) {
          rows.add(_messageRow(parentKey: key, depth: 2, 'No items'));
        } else {
          rows.addAll(
            sub.items.map(
              (item) =>
                  _itemRow(item, parentKey: key, rootId: rootId, depth: 2),
            ),
          );
        }
      }
    }
    return rows;
  }

  List<_TreeRow> _pluginChildren() {
    final instruments = widget.availableVst3Plugins
        .where((p) => p['is_instrument'] == '1')
        .toList();
    final effects = widget.availableVst3Plugins
        .where((p) => p['is_effect'] == '1')
        .toList();

    if (instruments.isEmpty && effects.isEmpty) {
      return [
        _messageRow(
          parentKey: 'plugins',
          depth: 1,
          'No plugins found.',
          subtitle: 'Install VST3 plugins to see them here.',
        ),
      ];
    }

    final rows = <_TreeRow>[];
    void addGroup(
      String id,
      String label,
      List<Map<String, String>> plugins, {
      required bool isInstrument,
    }) {
      final key = 'plugins/$id';
      final isExpanded = _expandedIds.contains(id);
      rows.add(
        _TreeRow(
          key: key,
          kind: _RowKind.folder,
          id: id,
          parentKey: 'plugins',
          rootId: 'plugins',
          depth: 1,
          label: label,
          isExpanded: isExpanded,
        ),
      );
      if (!isExpanded) return;
      if (plugins.isEmpty) {
        rows.add(
          _messageRow(
            parentKey: key,
            depth: 2,
            'No VST3 ${label.toLowerCase()}',
          ),
        );
      } else {
        rows.addAll(
          plugins.map(
            (p) => _pluginRow(
              p,
              isInstrument: isInstrument,
              parentKey: key,
              rootId: 'plugins',
              depth: 2,
            ),
          ),
        );
      }
    }

    addGroup(
      'plugins_instruments',
      'Instruments',
      instruments,
      isInstrument: true,
    );
    addGroup('plugins_effects', 'Effects', effects, isInstrument: false);
    return rows;
  }

  /// Contents of a scanned folder (user root or nested), or a loading /
  /// empty row.
  List<_TreeRow> _folderChildren({
    required String cacheId,
    required String parentKey,
    required String rootId,
    required int depth,
  }) {
    final items = _folderContentsCache[cacheId];
    if (items == null) {
      return [
        _TreeRow(
          key: '$parentKey/loading',
          kind: _RowKind.loading,
          parentKey: parentKey,
          depth: depth,
        ),
      ];
    }
    if (items.isEmpty) {
      return [_messageRow(parentKey: parentKey, depth: depth, 'Empty folder')];
    }
    return _itemOrFolderRows(
      items,
      parentKey: parentKey,
      rootId: rootId,
      depth: depth,
    );
  }

  List<_TreeRow> _itemOrFolderRows(
    List<LibraryItem> items, {
    required String parentKey,
    required String rootId,
    required int depth,
  }) {
    final rows = <_TreeRow>[];
    for (final item in items) {
      if (item is FolderItem) {
        final folderId = 'nested_folder_${item.folderPath}';
        final key = '$parentKey/$folderId';
        final isExpanded = _expandedIds.contains(folderId);
        rows.add(
          _TreeRow(
            key: key,
            kind: _RowKind.folder,
            id: folderId,
            parentKey: parentKey,
            rootId: rootId,
            depth: depth,
            label: item.name,
            isExpanded: isExpanded,
            folderPath: item.folderPath,
          ),
        );
        if (isExpanded) {
          rows.addAll(
            _folderChildren(
              cacheId: folderId,
              parentKey: key,
              rootId: rootId,
              depth: depth + 1,
            ),
          );
        }
      } else {
        rows.add(
          _itemRow(item, parentKey: parentKey, rootId: rootId, depth: depth),
        );
      }
    }
    return rows;
  }

  _TreeRow _itemRow(
    LibraryItem item, {
    required String parentKey,
    required String? rootId,
    required int depth,
  }) {
    return _TreeRow(
      key: '$parentKey/${item.id}',
      kind: _RowKind.item,
      id: item.id,
      parentKey: parentKey,
      rootId: rootId,
      depth: depth,
      label: item.displayName,
      icon: _typeIconFor(item),
      item: item,
    );
  }

  _TreeRow _pluginRow(
    Map<String, String> plugin, {
    required bool isInstrument,
    required String parentKey,
    required String? rootId,
    required int depth,
  }) {
    final id = 'vst3_${plugin['path']}';
    return _TreeRow(
      key: '$parentKey/$id',
      kind: _RowKind.plugin,
      id: id,
      parentKey: parentKey,
      rootId: rootId,
      depth: depth,
      label: plugin['name'] ?? 'Unknown',
      icon: isInstrument ? BI.piano : BI.equalizer,
      plugin: plugin,
      pluginIsInstrument: isInstrument,
    );
  }

  _TreeRow _messageRow(
    String message, {
    required String parentKey,
    required int depth,
    String? subtitle,
  }) {
    return _TreeRow(
      key: '$parentKey/message',
      kind: _RowKind.message,
      parentKey: parentKey,
      depth: depth,
      label: message,
      subtitle: subtitle,
    );
  }

  // ==========================================================================
  // EXPANSION, SELECTION, FOCUS
  // ==========================================================================

  void _onExpandableTap(_TreeRow row) {
    _libraryFocusNode.requestFocus();
    _focusedRowKey = row.key;
    _keyboardFocusVisible = false;
    _toggleExpanded(row);
  }

  /// Expand or collapse a root, subcategory or folder. Opening a root makes
  /// it the search scope; closing the scoped root returns search to "all".
  void _toggleExpanded(_TreeRow row) {
    final id = row.id;
    final wasExpanded = _expandedIds.contains(id);
    setState(() {
      if (wasExpanded) {
        _expandedIds.remove(id);
        if (row.kind == _RowKind.root && _searchScope == id) {
          _searchScope = null;
        }
      } else {
        _expandedIds.add(id);
        if (row.kind == _RowKind.root) _searchScope = id;
      }
    });
    // Rescan on every open so files added since last time show up; the
    // cached contents stay on screen until the fresh scan lands.
    if (!wasExpanded && row.folderPath != null) {
      _scanFolder(id, row.folderPath!);
    }
  }

  Future<void> _scanFolder(String cacheId, String path) async {
    final contents = await widget.libraryService.scanFolder(path);
    if (!mounted) return;
    setState(() => _folderContentsCache[cacheId] = contents);
  }

  /// Synchronous on purpose: a post-frame deferral here never ran when the
  /// pointer was still (nothing scheduled the frame), leaving the click with
  /// no selection. Root and folder taps already setState on this same path.
  void _onItemTap(_TreeRow row) {
    _libraryFocusNode.requestFocus();
    setState(() {
      _selectedItemId = row.id;
      _focusedRowKey = row.key;
      _keyboardFocusVisible = false;
      if (row.rootId != null) _searchScope = row.rootId;
    });
    _previewRow(row);
  }

  void _onActionTap(_TreeRow row) {
    _libraryFocusNode.requestFocus();
    _focusedRowKey = row.key;
    _keyboardFocusVisible = false;
    if (row.id == 'add_folder') _addUserFolder();
  }

  /// Single click / Space: audition audio files and presets.
  void _previewRow(_TreeRow row) {
    final item = row.item;
    if (item == null) return;
    _handleItemClick(item);
  }

  /// Double click / Enter: load onto a track.
  void _loadRow(_TreeRow row) {
    if (row.item != null) {
      widget.onItemDoubleClick?.call(row.item!);
    } else if (row.plugin != null) {
      widget.onVst3DoubleClick?.call(Vst3Plugin.fromMap(row.plugin!));
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

  // ==========================================================================
  // KEYBOARD NAVIGATION
  // ==========================================================================

  /// Up/Down walk the visible rows; landing on an item selects and previews
  /// it. Right opens a closed folder or steps into an open one, Left closes
  /// an open folder or steps up to the parent. Enter opens/closes a folder or
  /// loads an item; Space previews.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final rows = _visibleRows.where((r) => r.isFocusable).toList();
    if (rows.isEmpty) return KeyEventResult.ignored;

    final index = rows.indexWhere((r) => r.key == _focusedRowKey);

    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      final down = key == LogicalKeyboardKey.arrowDown;
      final int next;
      if (index == -1) {
        next = down ? 0 : rows.length - 1;
      } else {
        next = (index + (down ? 1 : -1)).clamp(0, rows.length - 1);
      }
      _focusRow(rows[next], towardsEnd: down);
      return KeyEventResult.handled;
    }

    if (index == -1) {
      if (key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.enter) {
        _focusRow(rows.first, towardsEnd: true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final row = rows[index];

    if (key == LogicalKeyboardKey.arrowRight) {
      if (row.isExpandable) {
        if (!row.isExpanded) {
          _keyboardFocusVisible = true;
          _toggleExpanded(row);
        } else {
          final child = rows
              .skip(index + 1)
              .firstWhere((r) => r.parentKey == row.key, orElse: () => row);
          if (child != row) _focusRow(child, towardsEnd: true);
        }
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (row.isExpandable && row.isExpanded) {
        _keyboardFocusVisible = true;
        _toggleExpanded(row);
      } else if (row.parentKey != null) {
        final parent = rows.firstWhere(
          (r) => r.key == row.parentKey,
          orElse: () => row,
        );
        if (parent != row) _focusRow(parent, towardsEnd: false);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter) {
      if (row.isExpandable) {
        _keyboardFocusVisible = true;
        _toggleExpanded(row);
      } else if (row.kind == _RowKind.action) {
        _onActionTap(row);
      } else {
        _loadRow(row);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.space) {
      _previewRow(row);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _focusRow(_TreeRow row, {required bool towardsEnd}) {
    setState(() {
      _keyboardFocusVisible = true;
      _focusedRowKey = row.key;
      if (row.isSelectable) {
        _selectedItemId = row.id;
        if (row.rootId != null) _searchScope = row.rootId;
      }
    });
    _previewRow(row);
    _ensureRowVisible(row.key, towardsEnd: towardsEnd);
  }

  void _ensureRowVisible(String rowKey, {required bool towardsEnd}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rowContext = _rowKeys[rowKey]?.currentContext;
      if (rowContext == null) return;
      Scrollable.ensureVisible(
        rowContext,
        alignmentPolicy: towardsEnd
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        duration: const Duration(milliseconds: 80),
      );
    });
  }

  // ==========================================================================
  // HEADER: search field + scope chip
  // ==========================================================================

  /// Returns (icon, label) for a built-in root ID, or null for user folders
  (IconData, String)? _categoryMeta(String? id) {
    return switch (id) {
      'favorites' => (BI.starFilled, 'Favorites'),
      'sounds' => (BI.musicNote, 'Sounds'),
      'samples' => (BI.equalizer, 'Samples'),
      'instruments' => (BI.piano, 'Instruments'),
      'effects' => (BI.lightning, 'Effects'),
      'plugins' => (BI.plugin, 'Plugins'),
      _ => null,
    };
  }

  /// Returns the display name for a root (including user folders)
  String _categoryLabel(String id) {
    final meta = _categoryMeta(id);
    if (meta != null) return meta.$2;
    // User folder — extract folder name from path
    for (final path in widget.libraryService.userFolderPaths) {
      if ('folder_$path' == id) {
        return path.split('/').last;
      }
    }
    return 'Library';
  }

  Widget _buildCombinedHeader() {
    final colors = context.colors;
    final scope = _searchScope;
    final showChip = _searchQuery.isNotEmpty && scope != null;

    return DecoratedBox(
      // No bottom divider: the search field is the single box here. Drawing a
      // divider under it fenced the field inside a second "band", which read as
      // a box-in-a-box. Whitespace separates it from the tree instead.
      // No padding at all: the square-cornered field runs edge-to-edge and its
      // top edge sits flush with the timeline loop bar (both BT.controlHeight).
      decoration: BoxDecoration(color: colors.dark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final placeholder = scope != null
                  ? 'Search ${_categoryLabel(scope).toLowerCase()}…'
                  : 'Search all…';
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
          // Scoped search chip (keeps the side inset the full-bleed field shed)
          if (showChip) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _buildSearchScopeChip(colors, scope),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchScopeChip(BoojyColors colors, String scope) {
    final meta = _categoryMeta(scope);
    final icon = meta?.$1 ?? BI.folder;
    final label = _categoryLabel(scope);

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
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: BT.fontLabel,
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () {
              setState(() {
                _searchScope = null;
              });
            },
            child: Icon(BI.close, size: 12, color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // FOLDER MANAGEMENT
  // ==========================================================================

  Future<void> _addUserFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select folder to add to library',
    );

    if (result != null) {
      await widget.libraryService.addUserFolder(result);
    }
  }

  Future<void> _showFolderContextMenu(TapUpDetails details, String path) async {
    // listen:false — a listening read inside a tap handler asserts in debug.
    final colors = context.themeProvider.colors;
    final action = await showBoojyMenu<String>(
      context: context,
      anchor: Rect.fromLTWH(
        details.globalPosition.dx,
        details.globalPosition.dy,
        0,
        0,
      ),
      items: [
        BoojyMenuItem(
          value: 'reveal',
          icon: BI.folderOpen,
          label: revealInFinderLabel,
        ),
        BoojyMenuItem(
          value: 'remove',
          icon: BI.delete,
          label: 'Remove from Library',
          destructive: true,
        ),
      ],
      selectedValue: null,
      colors: colors,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'reveal':
        revealInFinder(path);
      case 'remove':
        widget.libraryService.removeUserFolder(path);
    }
  }

  // ==========================================================================
  // NON-INTERACTIVE ROWS
  // ==========================================================================

  double _rowInset(int depth) => 5.0 + 8.0 + depth * _indentUnit;

  Widget _buildMessageRow(_TreeRow row) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.only(
        left: _rowInset(row.depth),
        right: 11,
        top: 4,
        bottom: 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.label,
            style: TextStyle(color: colors.textMuted, fontSize: BT.fontLabel),
          ),
          if (row.subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              row.subtitle!,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: BT.fontCaption,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingRow(_TreeRow row) {
    return Padding(
      padding: EdgeInsets.only(left: _rowInset(row.depth), top: 4, bottom: 4),
      child: const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _buildDividerRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Divider(color: context.colors.elevated, height: 1),
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
                fontSize: BT.fontBody,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.colors.textMuted,
                  fontSize: BT.fontLabel,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // SEARCH RESULTS
  // ==========================================================================

  /// Flat A–Z rows matching the query within [_searchScope] (all when null).
  List<_TreeRow> _buildSearchRows() {
    final builtInCategories = widget.libraryService.getBuiltInCategories();
    final results = <_SearchResult>[];
    final query = _searchQuery.toLowerCase();
    final scope = _searchScope;

    // Determine which categories to search
    bool shouldSearchCategory(String categoryId) {
      if (scope == null) return true; // search everything
      if (scope.startsWith('folder_')) {
        return false; // user folder scope — handled below
      }
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

    // Search user folder contents. A folder scope covers the folder and
    // every subfolder already opened beneath it (their caches are keyed
    // `nested_folder_<path>`), matching what the tree shows under that root.
    final scopePath = scope != null && scope.startsWith('folder_')
        ? scope.substring('folder_'.length)
        : null;
    if (scope == null || scopePath != null) {
      for (final entry in _folderContentsCache.entries) {
        if (scopePath != null &&
            entry.key != scope &&
            !entry.key.startsWith('nested_folder_$scopePath/')) {
          continue;
        }
        for (final item in entry.value) {
          if (item.matchesSearch(_searchQuery)) {
            results.add(_SearchResult(item: item));
          }
        }
      }
    }

    // Sort A-Z by display name
    results.sort((a, b) {
      final nameA = a.displayName.toLowerCase();
      final nameB = b.displayName.toLowerCase();
      return nameA.compareTo(nameB);
    });

    return [
      for (final result in results)
        if (result.item != null)
          _itemRow(result.item!, parentKey: 'search', rootId: null, depth: 0)
        else if (result.vst3Plugin != null)
          _pluginRow(
            result.vst3Plugin!,
            isInstrument: result.vst3Plugin!['is_instrument'] == '1',
            parentKey: 'search',
            rootId: null,
            depth: 0,
          ),
    ];
  }

  Widget _buildSearchResults(List<_TreeRow> rows) {
    if (rows.isEmpty) {
      return _buildEmptyState('No results for "$_searchQuery"');
    }

    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Result count header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
          child: Text(
            '${rows.length} result${rows.length == 1 ? '' : 's'}',
            style: TextStyle(fontSize: BT.fontLabel, color: colors.textMuted),
          ),
        ),
        // Flat A-Z list with type icons
        Expanded(
          child: ListView(
            controller: _scrollController,
            children: rows.map(_buildRowWidget).toList(),
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

  void _handleDragStarted() {
    _tryGetPreviewService()?.onDragStarted();
  }

  Widget _buildLibraryItem(_TreeRow row, {required bool isFocused}) {
    final item = row.item!;
    final previewService = _tryGetPreviewService(listen: true);
    final isCurrentlyPreviewing =
        previewService != null &&
        item is AudioFileItem &&
        previewService.currentFilePath == item.filePath &&
        previewService.isPlaying;

    Widget child = GestureDetector(
      onTap: () => _onItemTap(row),
      onDoubleTap: () => widget.onItemDoubleClick?.call(item),
      onSecondaryTapUp: (details) => _showItemContextMenu(details, item),
      child: _LibraryItemWidget(
        name: item.displayName,
        depth: row.depth,
        isFavorite: widget.libraryService.isFavorite(item.id),
        isPreviewing: isCurrentlyPreviewing,
        isSelected: _selectedItemId == item.id,
        isFocused: isFocused,
        typeIcon: row.icon,
        onTap: () => _onItemTap(row),
      ),
    );

    // Make draggable based on type
    if (item.type == LibraryItemType.instrument) {
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
    } else if (item.type == LibraryItemType.audioFile &&
        item is AudioFileItem) {
      child = Draggable<AudioFileItem>(
        data: item,
        feedback: _buildDragFeedback(item.displayName, BI.equalizer),
        childWhenDragging: Opacity(opacity: 0.5, child: child),
        onDragStarted: _handleDragStarted,
        child: child,
      );
    } else if (item.type == LibraryItemType.midiFile && item is MidiFileItem) {
      child = Draggable<MidiFileItem>(
        data: item,
        feedback: _buildDragFeedback(item.displayName, BI.musicNote),
        childWhenDragging: Opacity(opacity: 0.5, child: child),
        onDragStarted: _handleDragStarted,
        child: child,
      );
    } else if (item.type == LibraryItemType.effect && item is EffectItem) {
      child = Draggable<EffectItem>(
        data: item,
        feedback: _buildDragFeedback(item.displayName, item.icon),
        childWhenDragging: Opacity(opacity: 0.5, child: child),
        onDragStarted: _handleDragStarted,
        child: child,
      );
    }

    return child;
  }

  Widget _buildVst3PluginItem(_TreeRow row, {required bool isFocused}) {
    final plugin = Vst3Plugin.fromMap(row.plugin!);
    final name = plugin.name;
    final typeIcon = row.pluginIsInstrument ? BI.piano : BI.equalizer;

    return Draggable<Vst3Plugin>(
      data: plugin,
      feedback: _buildDragFeedback(name, typeIcon),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _LibraryItemWidget(
          name: name,
          depth: row.depth,
          typeIcon: typeIcon,
        ),
      ),
      child: GestureDetector(
        onTap: () => _onItemTap(row),
        onDoubleTap: () => widget.onVst3DoubleClick?.call(plugin),
        onSecondaryTapUp: (details) => _showVst3ContextMenu(details, plugin),
        child: _LibraryItemWidget(
          name: name,
          depth: row.depth,
          isFavorite: widget.libraryService.isFavorite(row.id),
          isSelected: _selectedItemId == row.id,
          isFocused: isFocused,
          typeIcon: typeIcon,
          onTap: () => _onItemTap(row),
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
                  fontWeight: BT.weightMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showItemContextMenu(
    TapUpDetails details,
    LibraryItem item,
  ) async {
    // listen:false — a listening read inside a tap handler asserts in debug.
    final colors = context.themeProvider.colors;
    final isFavorite = widget.libraryService.isFavorite(item.id);
    final isAudioFile =
        item.type == LibraryItemType.audioFile ||
        item.type == LibraryItemType.sample;
    final isInstrument = item.type == LibraryItemType.instrument;
    final isEffect = item.type == LibraryItemType.effect;
    final hasFilePath = item is AudioFileItem || item is SampleItem;

    final action = await showBoojyMenu<String>(
      context: context,
      anchor: Rect.fromLTWH(
        details.globalPosition.dx,
        details.globalPosition.dy,
        0,
        0,
      ),
      items: <BoojyMenuEntry<String>>[
        if (isInstrument)
          BoojyMenuItem(
            value: 'load',
            icon: BI.play,
            label: 'Load on Selected Track',
          ),
        if (isEffect)
          BoojyMenuItem(
            value: 'load',
            icon: BI.add,
            label: 'Add to Selected Track',
          ),
        if (isAudioFile && widget.onOpenInSampler != null)
          BoojyMenuItem(
            value: 'open_sampler',
            icon: BI.musicNote,
            label: 'Open in Sampler',
          ),
        BoojyMenuItem(
          value: 'favorite',
          icon: isFavorite ? BI.starFilled : BI.star,
          label: isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
        ),
        if (hasFilePath) ...[
          const BoojyMenuDivider<String>(),
          BoojyMenuItem(
            value: 'reveal',
            icon: BI.folderOpen,
            label: revealInFinderLabel,
          ),
          BoojyMenuItem(value: 'copy_path', icon: BI.copy, label: 'Copy Path'),
        ],
      ],
      selectedValue: null,
      colors: colors,
    );
    if (action == null || !mounted) return;
    final filePath = hasFilePath
        ? (item is AudioFileItem
              ? item.filePath
              : (item as SampleItem).filePath)
        : null;
    switch (action) {
      case 'load':
        widget.onItemDoubleClick?.call(item);
      case 'open_sampler':
        widget.onOpenInSampler?.call(item);
      case 'favorite':
        widget.libraryService.toggleFavorite(item.id);
      case 'reveal':
        if (filePath != null) revealInFinder(filePath);
      case 'copy_path':
        if (filePath != null) {
          await Clipboard.setData(ClipboardData(text: filePath));
        }
    }
  }

  Future<void> _showVst3ContextMenu(
    TapUpDetails details,
    Vst3Plugin plugin,
  ) async {
    // listen:false — a listening read inside a tap handler asserts in debug.
    final colors = context.themeProvider.colors;
    final itemId = 'vst3_${plugin.path}';
    final isFavorite = widget.libraryService.isFavorite(itemId);

    final action = await showBoojyMenu<String>(
      context: context,
      anchor: Rect.fromLTWH(
        details.globalPosition.dx,
        details.globalPosition.dy,
        0,
        0,
      ),
      items: [
        BoojyMenuItem(
          value: 'load',
          icon: BI.play,
          label: 'Load on Selected Track',
        ),
        BoojyMenuItem(
          value: 'favorite',
          icon: isFavorite ? BI.starFilled : BI.star,
          label: isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
        ),
      ],
      selectedValue: null,
      colors: colors,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'load':
        widget.onVst3DoubleClick?.call(plugin);
      case 'favorite':
        widget.libraryService.toggleFavorite(itemId);
    }
  }

  /// Returns the type icon for a library item
  IconData _typeIconFor(LibraryItem item) {
    switch (item.type) {
      case LibraryItemType.preset:
        return BI.musicNote;
      case LibraryItemType.sample:
      case LibraryItemType.audioFile:
        return BI.equalizer;
      case LibraryItemType.instrument:
        return BI.piano;
      case LibraryItemType.effect:
        return item.icon;
      case LibraryItemType.vst3Instrument:
      case LibraryItemType.vst3Effect:
        return BI.plugin;
      case LibraryItemType.folder:
        return BI.folder;
      case LibraryItemType.midiFile:
        return BI.musicNote;
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

/// Search result wrapper
class _SearchResult {
  final LibraryItem? item;
  final Map<String, String>? vst3Plugin;

  _SearchResult({this.item, this.vst3Plugin});

  String get displayName =>
      item?.displayName ?? vst3Plugin?['name'] ?? 'Unknown';
}

// ============================================================================
// ROW WIDGETS
// ============================================================================

/// The pill every row shares: hover tint, optional selection tint, and a thin
/// ring for keyboard focus. The ring is always laid out (transparent when
/// unfocused) so focusing never shifts the row.
class _RowPill extends StatelessWidget {
  final int depth;
  final bool isHovered;
  final bool isSelected;
  final bool isFocused;
  final Widget child;

  const _RowPill({
    required this.depth,
    required this.isHovered,
    required this.isFocused,
    required this.child,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Pill states: selected > hover > default
    Color bgColor;
    List<BoxShadow>? shadow;
    if (isSelected) {
      bgColor = colors.accent.withValues(alpha: 0.4);
      shadow = [
        BoxShadow(color: colors.accent.withValues(alpha: 0.1), blurRadius: 8),
      ];
    } else if (isHovered) {
      bgColor = colors.accent.withValues(alpha: 0.12);
    } else {
      bgColor = Colors.transparent;
    }

    return Container(
      margin: EdgeInsets.only(left: 5.0 + depth * _indentUnit, right: 3),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        boxShadow: shadow,
        border: Border.all(
          color: isFocused
              ? colors.accent.withValues(alpha: 0.7)
              : Colors.transparent,
        ),
      ),
      child: child,
    );
  }
}

/// One-line label that ellipsises when the row is too narrow and, only then,
/// shows the full text in a tooltip on hover.
class _TruncatingLabel extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _TruncatingLabel({required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final overflows = painter.width > constraints.maxWidth;
        painter.dispose();

        final label = Text(
          text,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
        if (!overflows) return label;
        return BoojyTooltip(
          title: text,
          waitDuration: const Duration(milliseconds: 600),
          child: label,
        );
      },
    );
  }
}

/// Shared hover tracking for row widgets. Hover changes are deferred a frame
/// to avoid setState inside MouseTracker's device update phase.
mixin _HoverState<T extends StatefulWidget> on State<T> {
  bool isHovered = false;

  void onHoverEnter(PointerEnterEvent _) {
    if (isHovered) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => isHovered = true);
    });
  }

  void onHoverExit(PointerExitEvent _) {
    if (!isHovered) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => isHovered = false);
    });
  }
}

/// Root row: icon + label, no chevron. The whole row toggles; the open state
/// is expressed only by the children below it (and to assistive tech).
class _RootRowWidget extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isExpanded;
  final bool isFocused;
  final VoidCallback onTap;
  final void Function(TapUpDetails)? onSecondaryTapUp;

  const _RootRowWidget({
    required this.icon,
    required this.label,
    required this.isExpanded,
    required this.isFocused,
    required this.onTap,
    this.onSecondaryTapUp,
  });

  @override
  State<_RootRowWidget> createState() => _RootRowWidgetState();
}

class _RootRowWidgetState extends State<_RootRowWidget>
    with _HoverState<_RootRowWidget> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: true,
      expanded: widget.isExpanded,
      label: widget.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: onHoverEnter,
        onExit: onHoverExit,
        child: GestureDetector(
          onTap: widget.onTap,
          onSecondaryTapUp: widget.onSecondaryTapUp,
          child: _RowPill(
            depth: 0,
            isHovered: isHovered,
            isFocused: widget.isFocused,
            child: Row(
              children: [
                SizedBox(
                  width: _indentUnit,
                  child: Icon(widget.icon, size: 14, color: colors.textMuted),
                ),
                const SizedBox(width: _glyphGap),
                Expanded(
                  child: _TruncatingLabel(
                    text: widget.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: isHovered
                          ? colors.textPrimary
                          : colors.textSecondary,
                      fontWeight: BT.weightMedium,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Subfolder / subcategory row: a chevron stands in for the folder icon.
class _FolderRowWidget extends StatefulWidget {
  final String label;
  final int depth;
  final bool isExpanded;
  final bool isFocused;
  final VoidCallback onTap;

  const _FolderRowWidget({
    required this.label,
    required this.depth,
    required this.isExpanded,
    required this.isFocused,
    required this.onTap,
  });

  @override
  State<_FolderRowWidget> createState() => _FolderRowWidgetState();
}

class _FolderRowWidgetState extends State<_FolderRowWidget>
    with _HoverState<_FolderRowWidget> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: true,
      expanded: widget.isExpanded,
      label: widget.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: onHoverEnter,
        onExit: onHoverExit,
        child: GestureDetector(
          onTap: widget.onTap,
          child: _RowPill(
            depth: widget.depth,
            isHovered: isHovered,
            isFocused: widget.isFocused,
            child: Row(
              children: [
                SizedBox(
                  width: _indentUnit,
                  child: Icon(
                    widget.isExpanded ? BI.expandMore : BI.caretRight,
                    size: 12,
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(width: _glyphGap),
                Expanded(
                  child: _TruncatingLabel(
                    text: widget.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: isHovered
                          ? colors.textPrimary
                          : colors.textSecondary,
                      fontWeight: BT.weightMedium,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "+ Add Folder" action row — same hover pill as the rows above it, with a
/// press state so the click visibly lands (v0.6 dogfood A10).
class _AddFolderButton extends StatefulWidget {
  final bool isFocused;
  final VoidCallback onTap;

  const _AddFolderButton({required this.isFocused, required this.onTap});

  @override
  State<_AddFolderButton> createState() => _AddFolderButtonState();
}

class _AddFolderButtonState extends State<_AddFolderButton>
    with _HoverState<_AddFolderButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fgColor = isHovered || _isPressed
        ? colors.textPrimary
        : colors.textMuted;

    return Semantics(
      button: true,
      label: 'Add Folder',
      onTap: widget.onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: onHoverEnter,
        onExit: (event) {
          onHoverExit(event);
          if (_isPressed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isPressed = false);
            });
          }
        },
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          child: _RowPill(
            depth: 0,
            isHovered: isHovered || _isPressed,
            isFocused: widget.isFocused,
            child: Row(
              children: [
                SizedBox(
                  width: _indentUnit,
                  child: Icon(BI.add, size: 14, color: fgColor),
                ),
                const SizedBox(width: _glyphGap),
                Expanded(
                  child: Text(
                    'Add Folder',
                    style: TextStyle(fontSize: 12, color: fgColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Library item row (audio file, MIDI file, preset, instrument, effect,
/// plugin): file-type glyph, label, favourite marker.
class _LibraryItemWidget extends StatefulWidget {
  final String name;
  final int depth;
  final bool isFavorite;
  final bool isPreviewing;
  final bool isSelected;
  final bool isFocused;
  final IconData? typeIcon;

  /// Exposed as the row's semantic tap action; pointer taps are handled by
  /// the enclosing GestureDetector.
  final VoidCallback? onTap;

  const _LibraryItemWidget({
    required this.name,
    this.depth = 0,
    this.isFavorite = false,
    this.isPreviewing = false,
    this.isSelected = false,
    this.isFocused = false,
    this.typeIcon,
    this.onTap,
  });

  @override
  State<_LibraryItemWidget> createState() => _LibraryItemWidgetState();
}

class _LibraryItemWidgetState extends State<_LibraryItemWidget>
    with _HoverState<_LibraryItemWidget> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isActive = widget.isSelected;

    // Icon color: active = accent, previewing = accent, default = muted
    final iconColor = isActive || widget.isPreviewing
        ? colors.accent
        : colors.textMuted;

    final glyph = widget.isPreviewing ? BI.speakerHigh : widget.typeIcon;

    return Semantics(
      button: true,
      selected: isActive,
      label: widget.name,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        onEnter: onHoverEnter,
        onExit: onHoverExit,
        child: _RowPill(
          depth: widget.depth,
          isHovered: isHovered,
          isSelected: isActive,
          isFocused: widget.isFocused,
          child: Row(
            children: [
              if (glyph != null) ...[
                SizedBox(
                  width: _indentUnit,
                  child: Icon(glyph, size: 12, color: iconColor),
                ),
                const SizedBox(width: _glyphGap),
              ],
              Expanded(
                child: _TruncatingLabel(
                  text: widget.name,
                  style: TextStyle(
                    color: isActive || widget.isPreviewing || isHovered
                        ? colors.textPrimary
                        : colors.textSecondary,
                    fontSize: 12,
                    fontWeight: isActive ? BT.weightSemiBold : BT.weightMedium,
                  ),
                ),
              ),
              if (widget.isFavorite)
                // Quiet grey marker — the favourite star shouldn't be the
                // brightest thing in the panel (was the shared gold `warning`).
                // Filled (like the Favorites category icon): "this IS a
                // favourite"; the outline star means "not yet favourited".
                Icon(BI.starFilled, size: 12, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
