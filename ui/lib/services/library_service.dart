import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/library_item.dart';
import '../widgets/instrument_browser.dart';
import '../screens/daw_screen_io.dart' if (dart.library.js_interop) '../screens/daw_screen_io_web.dart';

/// Service for managing library content, favorites, and user folders
class LibraryService extends ChangeNotifier {
  static const String _favoritesKey = 'library_favorites';
  static const String _userFoldersKey = 'library_user_folders';
  static const String _userContentPathKey = 'library_user_content_path';

  final Set<String> _favoriteIds = {};
  final List<String> _userFolderPaths = [];
  String _userContentPath = '';

  // Cached folder contents
  final Map<String, List<LibraryItem>> _folderContents = {};

  LibraryService() {
    _loadPreferences();
  }

  /// Get default user content path based on platform
  static Future<String> getDefaultUserContentPath() async {
    if (kIsWeb || isIOS) {
      // On web/iOS, we can't use HOME environment variable
      // Use the app's documents directory which is sandboxed
      // This will be set during initialization
      return '';  // Will be set by _loadPreferences
    } else {
      final home = getEnv('HOME') ?? '';
      return '$home/Documents/Boojy/Audio';
    }
  }

  /// Load saved preferences
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    // Load favorites
    final favorites = prefs.getStringList(_favoritesKey) ?? [];
    _favoriteIds.clear();
    _favoriteIds.addAll(favorites);

    // Load user folders
    final folders = prefs.getStringList(_userFoldersKey) ?? [];
    _userFolderPaths.clear();
    _userFolderPaths.addAll(folders);

    // Load user content path - platform specific handling
    final savedPath = prefs.getString(_userContentPathKey);
    if (savedPath != null && savedPath.isNotEmpty) {
      _userContentPath = savedPath;
    } else if (kIsWeb || isIOS) {
      // On web/iOS, skip folder creation - use IndexedDB/sandbox instead
      // User content will be managed differently on web/mobile
      _userContentPath = '';
      notifyListeners();
      return;
    } else {
      final home = getEnv('HOME') ?? '';
      _userContentPath = '$home/Documents/Boojy/Audio';
    }

    // Ensure default folder exists (skip on iOS if path is empty)
    if (_userContentPath.isNotEmpty) {
      await _ensureDefaultFolderExists();
    }

    notifyListeners();
  }

  /// Ensure default user content folder exists
  Future<void> _ensureDefaultFolderExists() async {
    // Skip folder creation on web/iOS - use IndexedDB/sandbox instead
    if (kIsWeb || isIOS || _userContentPath.isEmpty) {
      return;
    }

    try {
      final dir = Directory(_userContentPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        // Create subfolders
        await Directory('$_userContentPath/Samples').create(recursive: true);
        await Directory('$_userContentPath/Presets').create(recursive: true);
        await Directory('$_userContentPath/Projects').create(recursive: true);
      }
    } catch (e) {
      // Don't throw - just log the error and continue
    }
  }

  /// Check if item is favorited
  bool isFavorite(String itemId) => _favoriteIds.contains(itemId);

  /// Get all favorite IDs
  Set<String> get favoriteIds => Set.unmodifiable(_favoriteIds);

  /// Add item to favorites
  Future<void> addFavorite(String itemId) async {
    _favoriteIds.add(itemId);
    await _saveFavorites();
    notifyListeners();
  }

  /// Remove item from favorites
  Future<void> removeFavorite(String itemId) async {
    _favoriteIds.remove(itemId);
    await _saveFavorites();
    notifyListeners();
  }

  /// Toggle favorite status
  Future<void> toggleFavorite(String itemId) async {
    if (_favoriteIds.contains(itemId)) {
      await removeFavorite(itemId);
    } else {
      await addFavorite(itemId);
    }
  }

  /// Save favorites to preferences
  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, _favoriteIds.toList());
  }

  /// Get user folder paths
  List<String> get userFolderPaths => List.unmodifiable(_userFolderPaths);

  /// Add user folder
  Future<void> addUserFolder(String path) async {
    if (!_userFolderPaths.contains(path)) {
      _userFolderPaths.add(path);
      await _saveUserFolders();
      notifyListeners();
    }
  }

  /// Remove user folder
  Future<void> removeUserFolder(String path) async {
    _userFolderPaths.remove(path);
    _folderContents.remove(path);
    await _saveUserFolders();
    notifyListeners();
  }

  /// Save user folders to preferences
  Future<void> _saveUserFolders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_userFoldersKey, _userFolderPaths);
  }

  /// Scan folder for audio files
  Future<List<LibraryItem>> scanFolder(String path) async {
    // Check cache first
    if (_folderContents.containsKey(path)) {
      return _folderContents[path]!;
    }

    final items = <LibraryItem>[];
    final dir = Directory(path);

    if (!await dir.exists()) {
      return items;
    }

    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.path.split('/').last;
          final ext = name.split('.').last.toLowerCase();

          // Check if audio file
          if (_isAudioFile(ext)) {
            items.add(AudioFileItem(
              id: 'file_${entity.path.hashCode}',
              name: name,
              filePath: entity.path,
              icon: Icons.audio_file,
            ));
          }
        } else if (entity is Directory) {
          final folderName = entity.path.split('/').last;
          // Add subfolder
          items.add(FolderItem(
            id: 'folder_${entity.path.hashCode}',
            name: folderName,
            folderPath: entity.path,
            icon: Icons.folder,
          ));
        }
      }
    } catch (e) {
      debugPrint('LibraryService: Error loading folder contents: $e');
    }

    // Sort: folders first, then files alphabetically
    items.sort((a, b) {
      if (a.type == LibraryItemType.folder && b.type != LibraryItemType.folder) {
        return -1;
      } else if (a.type != LibraryItemType.folder && b.type == LibraryItemType.folder) {
        return 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    // Cache results
    _folderContents[path] = items;

    return items;
  }

  /// Check if extension is audio file
  bool _isAudioFile(String ext) {
    const audioExtensions = ['wav', 'mp3', 'aiff', 'aif', 'flac', 'ogg', 'm4a'];
    return audioExtensions.contains(ext);
  }

  /// Clear folder cache (for refresh)
  void clearFolderCache() {
    _folderContents.clear();
    notifyListeners();
  }

  /// Get all built-in categories with content
  List<LibraryCategory> getBuiltInCategories() {
    return [
      _buildSoundsCategory(),
      _buildSamplesCategory(),
      _buildInstrumentsCategory(),
      _buildEffectsCategory(),
    ];
  }

  /// Build Sounds category (empty - not yet implemented)
  LibraryCategory _buildSoundsCategory() {
    return const LibraryCategory(
      id: 'sounds',
      name: 'Sounds',
      icon: Icons.queue_music,
      subcategories: [],
      items: [],
    );
  }

  /// Build Samples category (empty - not yet implemented)
  LibraryCategory _buildSamplesCategory() {
    return const LibraryCategory(
      id: 'samples',
      name: 'Samples',
      icon: Icons.audio_file,
      subcategories: [],
      items: [],
    );
  }

  /// Build Instruments category (blank engines)
  LibraryCategory _buildInstrumentsCategory() {
    // Map from availableInstruments
    final items = availableInstruments
        .where((i) => ['Piano', 'Synthesizer', 'Drums', 'Sampler'].contains(i.name))
        .map((i) => LibraryItem(
              id: 'instrument_${i.id}',
              name: i.name,
              type: LibraryItemType.instrument,
              icon: i.icon,
            ))
        .toList();

    return LibraryCategory(
      id: 'instruments',
      name: 'Instruments',
      icon: Icons.piano,
      items: items,
    );
  }

  /// Build Effects category
  LibraryCategory _buildEffectsCategory() {
    return const LibraryCategory(
      id: 'effects',
      name: 'Effects',
      icon: Icons.graphic_eq,
      items: [
        EffectItem(id: 'effect_eq', name: 'EQ', effectType: 'eq', icon: Icons.equalizer),
        EffectItem(id: 'effect_compressor', name: 'Compressor', effectType: 'compressor', icon: Icons.compress),
        EffectItem(id: 'effect_reverb', name: 'Reverb', effectType: 'reverb', icon: Icons.blur_on),
        EffectItem(id: 'effect_delay', name: 'Delay', effectType: 'delay', icon: Icons.timer),
        EffectItem(id: 'effect_chorus', name: 'Chorus', effectType: 'chorus', icon: Icons.waves),
        EffectItem(id: 'effect_limiter', name: 'Limiter', effectType: 'limiter', icon: Icons.vertical_align_center),
      ],
    );
  }

  /// Get favorite items from all categories
  List<LibraryItem> getFavoriteItems(List<LibraryCategory> categories) {
    final favorites = <LibraryItem>[];

    void collectFavorites(List<LibraryCategory> cats) {
      for (final cat in cats) {
        for (final item in cat.items) {
          if (_favoriteIds.contains(item.id)) {
            favorites.add(item);
          }
        }
        collectFavorites(cat.subcategories);
      }
    }

    collectFavorites(categories);
    return favorites;
  }
}
