/// Mixin providing deferred selection behavior for click vs drag disambiguation.
///
/// When clicking on an already-selected item:
/// - If user drags → keep multi-selection (drag all selected items)
/// - If user just clicks (no drag) → reduce to single selection
///
/// This pattern is used in both Piano Roll and Timeline to enable
/// multi-item drag while still allowing click-to-single-select.
mixin DeferredSelectionMixin<T> {
  /// Item ID that should reduce to single selection on tap-up (if no drag occurred).
  T? pendingTapSelection;

  /// Handle selection on pointer down / tap down.
  ///
  /// Returns true if selection was applied immediately.
  /// Returns false if selection was deferred to tap-up.
  ///
  /// Call this when the user clicks on an item. If the item is already selected
  /// and shift is not pressed, we defer the "reduce to single" selection
  /// until tap-up, allowing the user to drag multiple items.
  bool handleSelectionOnPointerDown({
    required T itemId,
    required bool wasAlreadySelected,
    required bool isShiftPressed,
    required void Function(T itemId, {required bool toggle}) selectItem,
  }) {
    if (isShiftPressed) {
      // Shift+click: toggle selection immediately
      pendingTapSelection = null;
      selectItem(itemId, toggle: true);
      return true;
    }

    if (wasAlreadySelected) {
      // Clicking on already-selected item: defer single-selection to tap-up
      // This allows dragging multiple items if the user drags instead of clicks
      pendingTapSelection = itemId;
      return false;
    }

    // Clicking on unselected item: select immediately
    pendingTapSelection = null;
    selectItem(itemId, toggle: false);
    return true;
  }

  /// Handle selection on tap up.
  ///
  /// Call this when tap ends (no drag occurred). If there's a pending selection,
  /// it will be applied now to reduce to single selection.
  void handleSelectionOnTapUp(void Function(T itemId) selectSingle) {
    if (pendingTapSelection != null) {
      selectSingle(pendingTapSelection as T);
      pendingTapSelection = null;
    }
  }

  /// Clear pending selection (call this when drag starts).
  ///
  /// When the user starts dragging, we want to keep the multi-selection
  /// intact, so we clear the pending single-selection.
  void clearPendingSelection() {
    pendingTapSelection = null;
  }

  /// Check if there's a pending selection for a specific item.
  bool hasPendingSelectionFor(T itemId) {
    return pendingTapSelection == itemId;
  }
}
