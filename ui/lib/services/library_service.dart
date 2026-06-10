import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';
import '../models/library_item.dart';
import 'bundled_content_service.dart';
import '../theme/boojy_icons.dart';
import '../widgets/instrument_browser.dart';
import '../screens/daw_screen_io.dart'
    if (dart.library.js_interop) '../screens/daw_screen_io_web.dart';

/// Service for managing library content, favorites, and user folders
class LibraryService extends ChangeNotifier {
  static const String _favoritesKey = 'library_favorites';
  static const String _userFoldersKey = 'library_user_folders';
  static const String _userContentPathKey = 'library_user_content_path';

  final Set<String> _favoriteIds = {};
  final List<String> _userFolderPaths = [];
  String _userContentPath = '';

  /// Stale favourite IDs from the old `file_<hashCode>` format (pre path-based
  /// `file_<path>` IDs). Those favourites can't be mapped back to a file.
  static final RegExp _legacyFileFavoriteId = RegExp(r'^file_-?\d+$');

  /// Set when [_loadPreferences] pruned old-format favourites; consumed once
  /// by [takeLegacyFavoritesNotice] so the library panel can tell the user
  /// instead of showing a mysteriously empty Favorites view.
  bool _legacyFavoritesPruned = false;

  /// One-shot: true exactly once after a load that pruned legacy favourites.
  bool takeLegacyFavoritesNotice() {
    final flag = _legacyFavoritesPruned;
    _legacyFavoritesPruned = false;
    return flag;
  }

  // Cached folder contents
  final Map<String, List<LibraryItem>> _folderContents = {};

  LibraryService() {
    _loadPreferences();
    _installBundledContent();
    // Schedule a notification after the first frame to ensure widgets are listening
    // This fixes built-in effects not appearing until manual refresh
    Future.microtask(() => notifyListeners());
  }

  /// On-disk root of the bundled drum samples (set once installed).
  String? _bundledDrumsRoot;

  /// Copy the bundled samples out of the asset bundle (no-op when already
  /// installed), then surface them in the Samples category.
  Future<void> _installBundledContent() async {
    final root = await BundledContentService.ensureInstalled();
    if (root != null) {
      _bundledDrumsRoot = root;
      notifyListeners();
    }
  }

  /// Test seam: set the bundled-drums root without a real install.
  @visibleForTesting
  void debugSetBundledDrumsRoot(String? root) {
    _bundledDrumsRoot = root;
    notifyListeners();
  }

  /// Get default user content path based on platform
  static Future<String> getDefaultUserContentPath() async {
    if (kIsWeb || isIOS) {
      // On web/iOS, we can't use HOME environment variable
      // Use the app's documents directory which is sandboxed
      // This will be set during initialization
      return ''; // Will be set by _loadPreferences
    } else {
      final home = getEnv('HOME') ?? '';
      return '$home/Documents/Boojy/Audio';
    }
  }

  /// Load saved preferences
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    // Load favorites, pruning entries in the old `file_<hashCode>` format —
    // they can't be mapped back to a file path, so they would just linger in
    // SharedPreferences forever while the Favorites view ignores them. The
    // pruned flag drives a one-time user-visible notice in the library panel.
    final favorites = prefs.getStringList(_favoritesKey) ?? [];
    final withoutLegacy = favorites
        .where((id) => !_legacyFileFavoriteId.hasMatch(id))
        .toList();
    if (withoutLegacy.length != favorites.length) {
      Log.i(
        'LibraryService: pruned ${favorites.length - withoutLegacy.length} '
        'legacy file_<hashCode> favourites (library index upgraded)',
      );
      await prefs.setStringList(_favoritesKey, withoutLegacy);
      _legacyFavoritesPruned = true;
    }
    _favoriteIds.clear();
    _favoriteIds.addAll(withoutLegacy);

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
          // p.basename handles both / and \ — split('/') broke on Windows.
          final name = p.basename(entity.path);
          final ext = name.split('.').last.toLowerCase();

          // Check if audio or MIDI file
          // IDs embed the full path (not path.hashCode — collisions made
          // two files share favourite/selection state) and double as the
          // persisted favourite key, so favourites can be reconstructed
          // without re-scanning the folder.
          if (_isAudioFile(ext)) {
            items.add(
              AudioFileItem(
                id: 'file_${entity.path}',
                name: name,
                filePath: entity.path,
                icon: BI.audioFile,
              ),
            );
          } else if (_isMidiFile(ext)) {
            items.add(
              MidiFileItem(
                id: 'file_${entity.path}',
                name: name,
                filePath: entity.path,
              ),
            );
          }
        } else if (entity is Directory) {
          final folderName = p.basename(entity.path);
          // Add subfolder
          items.add(
            FolderItem(
              id: 'folder_${entity.path}',
              name: folderName,
              folderPath: entity.path,
              icon: BI.folder,
            ),
          );
        }
      }
    } catch (e) {
      Log.e('LibraryService: Error loading folder contents: $e');
    }

    // Sort: folders first, then files alphabetically
    items.sort((a, b) {
      if (a.type == LibraryItemType.folder &&
          b.type != LibraryItemType.folder) {
        return -1;
      } else if (a.type != LibraryItemType.folder &&
          b.type == LibraryItemType.folder) {
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

  /// Check if extension is MIDI file
  bool _isMidiFile(String ext) {
    const midiExtensions = ['mid', 'midi'];
    return midiExtensions.contains(ext);
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
    return LibraryCategory(
      id: 'sounds',
      name: 'Sounds',
      icon: BI.queue,
      subcategories: [],
      items: [],
    );
  }

  /// Build Samples category — bundled content, copied out to disk on first
  /// launch and browsed with the same folder scanning as user folders.
  LibraryCategory _buildSamplesCategory() {
    final drumsRoot = _bundledDrumsRoot;
    return LibraryCategory(
      id: 'samples',
      name: 'Samples',
      icon: BI.audioFile,
      subcategories: [],
      items: [
        if (drumsRoot != null)
          FolderItem(
            id: 'builtin_samples_drums',
            name: 'Drums',
            folderPath: drumsRoot,
          ),
      ],
    );
  }

  /// Build Instruments category (blank engines)
  LibraryCategory _buildInstrumentsCategory() {
    // Map from availableInstruments
    final items = availableInstruments
        .where(
          (i) => [
            'Piano',
            'Synthesizer',
            'Drums',
            'Sampler',
            'Drum Kit',
          ].contains(i.name),
        )
        .map(
          (i) => LibraryItem(
            id: 'instrument_${i.id}',
            name: i.name,
            type: LibraryItemType.instrument,
            icon: i.icon,
          ),
        )
        .toList();

    return LibraryCategory(
      id: 'instruments',
      name: 'Instruments',
      icon: BI.piano,
      items: items,
    );
  }

  /// Build Effects category
  LibraryCategory _buildEffectsCategory() {
    return LibraryCategory(
      id: 'effects',
      name: 'Effects',
      icon: BI.equalizer,
      items: [
        EffectItem(
          id: 'effect_eq',
          name: 'EQ',
          effectType: 'eq',
          icon: BI.equalizer,
        ),
        EffectItem(
          id: 'effect_compressor',
          name: 'Compressor',
          effectType: 'compressor',
          icon: BI.compress,
        ),
        EffectItem(
          id: 'effect_reverb',
          name: 'Reverb',
          effectType: 'reverb',
          icon: BI.waveSine,
        ),
        EffectItem(
          id: 'effect_delay',
          name: 'Delay',
          effectType: 'delay',
          icon: BI.metronome,
        ),
        EffectItem(
          id: 'effect_chorus',
          name: 'Chorus',
          effectType: 'chorus',
          icon: BI.waveform,
        ),
        EffectItem(
          id: 'effect_limiter',
          name: 'Limiter',
          effectType: 'limiter',
          icon: BI.arrowsHorizontal,
        ),
      ],
    );
  }

  /// Get favorite items from all categories, plus favourited files from
  /// user folders / bundled-sample folders (reconstructed from their
  /// path-based `file_<path>` IDs, so they show up without re-scanning
  /// every folder first). VST3 plugin favourites (`vst3_<path>`) live in
  /// the panel's plugin list, not here — the panel appends those itself.
  List<LibraryItem> getFavoriteItems(List<LibraryCategory> categories) {
    final favorites = <LibraryItem>[];
    final seen = <String>{};

    void collectFavorites(List<LibraryCategory> cats) {
      for (final cat in cats) {
        for (final item in cat.items) {
          if (_favoriteIds.contains(item.id) && seen.add(item.id)) {
            favorites.add(item);
          }
        }
        collectFavorites(cat.subcategories);
      }
    }

    collectFavorites(categories);

    // File favourites not found in the category tree. Stale entries from
    // the old `file_<hashCode>` format are pruned at load (with a one-time
    // notice — see _loadPreferences); _fileItemFromPath still returns null
    // for anything unrecognisable rather than showing garbage rows.
    final fileFavorites = <LibraryItem>[];
    for (final id in _favoriteIds) {
      if (seen.contains(id) || !id.startsWith('file_')) continue;
      final item = _fileItemFromPath(id.substring('file_'.length));
      if (item != null && seen.add(item.id)) {
        fileFavorites.add(item);
      }
    }
    fileFavorites.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    favorites.addAll(fileFavorites);

    return favorites;
  }

  /// Rebuild a library item from a favourited file path. Returns null for
  /// anything that isn't a recognised audio/MIDI file path (e.g. legacy
  /// hash-based favourite IDs).
  LibraryItem? _fileItemFromPath(String path) {
    final name = p.basename(path);
    if (!name.contains('.')) return null;
    final ext = name.split('.').last.toLowerCase();
    if (_isAudioFile(ext)) {
      return AudioFileItem(
        id: 'file_$path',
        name: name,
        filePath: path,
        icon: BI.audioFile,
      );
    }
    if (_isMidiFile(ext)) {
      return MidiFileItem(id: 'file_$path', name: name, filePath: path);
    }
    return null;
  }
}
