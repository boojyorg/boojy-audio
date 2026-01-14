import 'package:flutter/foundation.dart';

/// Generic multi-selection manager for any item type.
///
/// Provides consistent selection behavior across Piano Roll (notes)
/// and Timeline (clips). Supports:
/// - Single selection (clear others)
/// - Additive selection (add to existing)
/// - Toggle selection (add/remove)
/// - Box selection (select all in range)
class MultiSelectionManager<T> extends ChangeNotifier {
  final Set<T> _selected = {};
  T? _primary;

  /// Unmodifiable view of selected items.
  Set<T> get selected => Set.unmodifiable(_selected);

  /// The primary (most recently selected) item.
  T? get primary => _primary;

  /// Whether selection is empty.
  bool get isEmpty => _selected.isEmpty;

  /// Whether selection is not empty.
  bool get isNotEmpty => _selected.isNotEmpty;

  /// Number of selected items.
  int get count => _selected.length;

  /// Check if an item is selected.
  bool isSelected(T item) => _selected.contains(item);

  /// Select an item with various modes.
  ///
  /// - Default (no flags): Clear selection and select only this item
  /// - [additive]: Add to existing selection
  /// - [toggle]: Toggle this item's selection state
  void select(T item, {bool additive = false, bool toggle = false}) {
    if (toggle) {
      // Toggle mode: add if not selected, remove if selected
      if (_selected.contains(item)) {
        _selected.remove(item);
        if (_primary == item) {
          _primary = _selected.isEmpty ? null : _selected.first;
        }
      } else {
        _selected.add(item);
        _primary = item;
      }
    } else if (additive) {
      // Additive mode: add to existing selection
      _selected.add(item);
      _primary = item;
    } else {
      // Default mode: clear and select only this item
      _selected.clear();
      _selected.add(item);
      _primary = item;
    }
    notifyListeners();
  }

  /// Select multiple items at once (e.g., from box selection).
  ///
  /// If [additive] is false (default), clears existing selection first.
  void selectAll(Iterable<T> items, {bool additive = false}) {
    if (!additive) {
      _selected.clear();
    }
    _selected.addAll(items);
    if (items.isNotEmpty) {
      _primary = items.last;
    }
    notifyListeners();
  }

  /// Clear all selections.
  void clear() {
    if (_selected.isEmpty && _primary == null) return;
    _selected.clear();
    _primary = null;
    notifyListeners();
  }

  /// Remove a specific item from selection.
  void deselect(T item) {
    if (!_selected.contains(item)) return;
    _selected.remove(item);
    if (_primary == item) {
      _primary = _selected.isEmpty ? null : _selected.first;
    }
    notifyListeners();
  }

  /// Replace the entire selection with a new set.
  void replaceSelection(Set<T> newSelection, {T? primary}) {
    _selected.clear();
    _selected.addAll(newSelection);
    _primary = primary ?? (newSelection.isNotEmpty ? newSelection.first : null);
    notifyListeners();
  }
}

/// Extension for int-based selection (clip IDs).
extension ClipSelectionManager on MultiSelectionManager<int> {
  /// Get selected IDs as a list.
  List<int> get selectedIds => _selected.toList();
}

/// Extension for String-based selection (note IDs).
extension NoteSelectionManager on MultiSelectionManager<String> {
  /// Get selected IDs as a list.
  List<String> get selectedIds => _selected.toList();
}
