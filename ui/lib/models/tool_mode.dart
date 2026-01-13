/// Tool modes for piano roll and arrangement view toolbar buttons.
/// Shared between both views for consistent tool state.
enum ToolMode {
  draw,      // Default: click to create notes/clips
  select,    // Select and move notes/clips
  eraser,    // Delete notes/clips on click
  duplicate, // Duplicate notes/clips on click/drag
  slice,     // Split notes/clips at click position
}
