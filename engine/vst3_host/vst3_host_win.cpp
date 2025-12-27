// vst3_host_win.cpp - Windows-specific VST3 GUI helpers
// Windows equivalent of vst3_host_mac.mm for plugin editor window management

#include "vst3_host.h"
#include <windows.h>

extern "C" {

/// Resize a Windows HWND to the specified dimensions
/// This is called when a VST3 plugin requests a resize of its editor window
/// @param hwnd - Window handle (HWND) to resize
/// @param width - New width in pixels
/// @param height - New height in pixels
void vst3_resize_hwnd(void* hwnd, int width, int height) {
    if (!hwnd) {
        return;
    }

    HWND window = static_cast<HWND>(hwnd);

    // Get current window position
    RECT rect;
    if (!GetWindowRect(window, &rect)) {
        return; // Failed to get window rect
    }

    // Calculate new size while maintaining top-left position
    int x = rect.left;
    int y = rect.top;

    // Check if this is a top-level window with decorations
    DWORD style = GetWindowLong(window, GWL_STYLE);
    if (style & WS_CAPTION) {
        // This is a window with decorations (title bar, border, etc.)
        // We need to adjust the requested client size to account for the frame
        RECT client_rect = {0, 0, width, height};

        // AdjustWindowRect calculates the required window size for the desired client area
        if (AdjustWindowRect(&client_rect, style, FALSE)) {
            width = client_rect.right - client_rect.left;
            height = client_rect.bottom - client_rect.top;
        }
    }

    // Resize the window
    // SWP_NOZORDER: Don't change Z-order
    // SWP_NOACTIVATE: Don't activate the window
    SetWindowPos(window, NULL, x, y, width, height,
                 SWP_NOZORDER | SWP_NOACTIVATE);
}

} // extern "C"
