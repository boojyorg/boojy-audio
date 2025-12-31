import 'package:flutter/material.dart';

/// Type of library item - determines drag behavior
enum LibraryItemType {
  preset,      // Sounds - creates MIDI track with instrument + preset
  sample,      // Samples - creates Audio track with audio clip
  instrument,  // Instruments - creates MIDI track with blank instrument
  effect,      // Effects - adds to track FX chain
  vst3Instrument, // VST3 Instrument - creates MIDI track with VST3
  vst3Effect,     // VST3 Effect - adds VST3 to track FX chain
  folder,      // User folder - container for files
  audioFile,   // Audio file from user folder - creates Audio track
}

/// Base class for all library items
@immutable
class LibraryItem {
  final String id;
  final String name;
  final LibraryItemType type;
  final String? path;         // File path for samples/VST3
  final String? category;     // Subcategory (e.g., "Leads" under "Sounds")
  final String? parentId;     // Parent category/folder ID
  final IconData icon;
  final bool isPlaceholder;   // If true, shows [WIP] suffix

  const LibraryItem({
    required this.id,
    required this.name,
    required this.type,
    this.path,
    this.category,
    this.parentId,
    this.icon = Icons.music_note,
    this.isPlaceholder = false,
  });

  /// Display name with [WIP] suffix if placeholder
  String get displayName => isPlaceholder ? '$name [WIP]' : name;

  /// Check if item matches search query
  bool matchesSearch(String query) {
    if (query.isEmpty) return true;
    final lowerQuery = query.toLowerCase();
    return name.toLowerCase().contains(lowerQuery) ||
           (category?.toLowerCase().contains(lowerQuery) ?? false);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Preset item (Sounds category) - synth patches that load on instruments
class PresetItem extends LibraryItem {
  final String instrumentId;  // Which instrument this preset is for
  final Map<String, dynamic>? presetData; // Preset parameters

  const PresetItem({
    required super.id,
    required super.name,
    required this.instrumentId,
    super.category,
    super.icon = Icons.queue_music,
    super.isPlaceholder = false,
    this.presetData,
  }) : super(type: LibraryItemType.preset);
}

/// Sample item (Samples category) - audio files
class SampleItem extends LibraryItem {
  final String filePath;
  final Duration? duration;

  const SampleItem({
    required super.id,
    required super.name,
    required this.filePath,
    super.category,
    super.icon = Icons.audio_file,
    super.isPlaceholder = false,
    this.duration,
  }) : super(type: LibraryItemType.sample, path: filePath);
}

/// Folder item for user directories
class FolderItem extends LibraryItem {
  final String folderPath;
  final List<LibraryItem> children;

  const FolderItem({
    required super.id,
    required super.name,
    required this.folderPath,
    this.children = const [],
    super.icon = Icons.folder,
  }) : super(type: LibraryItemType.folder, path: folderPath);

  /// Create copy with updated children
  FolderItem copyWithChildren(List<LibraryItem> newChildren) {
    return FolderItem(
      id: id,
      name: name,
      folderPath: folderPath,
      children: newChildren,
      icon: icon,
    );
  }
}

/// Audio file from user folder
class AudioFileItem extends LibraryItem {
  final String filePath;

  const AudioFileItem({
    required super.id,
    required super.name,
    required this.filePath,
    super.icon = Icons.audio_file,
  }) : super(type: LibraryItemType.audioFile, path: filePath);
}

/// Built-in effect item
class EffectItem extends LibraryItem {
  final String effectType;

  const EffectItem({
    required super.id,
    required super.name,
    required this.effectType,
    super.icon = Icons.tune,
  }) : super(type: LibraryItemType.effect);
}

/// Library category for organizing items
class LibraryCategory {
  final String id;
  final String name;
  final IconData icon;
  final List<LibraryCategory> subcategories;
  final List<LibraryItem> items;
  final bool isExpandable;
  final bool showAddButton; // For Folders category

  const LibraryCategory({
    required this.id,
    required this.name,
    required this.icon,
    this.subcategories = const [],
    this.items = const [],
    this.isExpandable = true,
    this.showAddButton = false,
  });

  /// Check if category has any items matching search
  bool hasMatchingItems(String query) {
    if (query.isEmpty) return true;

    // Check direct items
    if (items.any((item) => item.matchesSearch(query))) return true;

    // Check subcategory items
    for (final sub in subcategories) {
      if (sub.hasMatchingItems(query)) return true;
    }

    return false;
  }

  /// Get all items (including from subcategories) matching search
  List<LibraryItem> getMatchingItems(String query) {
    return [
      // Add matching direct items
      ...items.where((item) => item.matchesSearch(query)),
      // Add matching items from subcategories
      for (final sub in subcategories) ...sub.getMatchingItems(query),
    ];
  }
}
