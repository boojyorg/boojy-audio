//-----------------------------------------------------------------------------
// VST3 Host macOS-specific helper functions
// This file provides Objective-C implementations for NSView manipulation
//-----------------------------------------------------------------------------

#import <Cocoa/Cocoa.h>

extern "C" {

/// Resize an NSView to the specified dimensions
/// Also resizes the window if the view is the contentView of a window
void vst3_resize_nsview(void* nsview, int width, int height) {
    if (!nsview) {
        fprintf(stderr, "📐 [ObjC] vst3_resize_nsview: nsview is null\n");
        fflush(stderr);
        return;
    }

    // Dispatch to main thread if not already there
    if (![NSThread isMainThread]) {
        fprintf(stderr, "📐 [ObjC] vst3_resize_nsview: dispatching to main thread\n");
        fflush(stderr);
        dispatch_async(dispatch_get_main_queue(), ^{
            vst3_resize_nsview(nsview, width, height);
        });
        return;
    }

    NSView* view = (__bridge NSView*)nsview;

    fprintf(stderr, "📐 [ObjC] vst3_resize_nsview: view=%p, size=%dx%d\n", nsview, width, height);
    fflush(stderr);

    // Get the window if this view is the contentView
    NSWindow* window = [view window];

    if (window && [window contentView] == view) {
        // This is the contentView of a window - resize the window
        fprintf(stderr, "📐 [ObjC] View is contentView of window, resizing window\n");
        fflush(stderr);

        NSRect windowFrame = [window frame];
        NSRect contentRect = [window contentRectForFrameRect:windowFrame];

        // Calculate the difference in height (for proper origin adjustment)
        CGFloat heightDiff = (CGFloat)height - contentRect.size.height;

        // Update content size
        contentRect.size.width = (CGFloat)width;
        contentRect.size.height = (CGFloat)height;

        // Adjust origin to keep top of window in place
        contentRect.origin.y -= heightDiff;

        NSRect newFrame = [window frameRectForContentRect:contentRect];

        fprintf(stderr, "📐 [ObjC] Setting window frame to (%f, %f, %f, %f)\n",
                newFrame.origin.x, newFrame.origin.y, newFrame.size.width, newFrame.size.height);
        fflush(stderr);

        [window setFrame:newFrame display:YES animate:NO];
    } else {
        // Just resize the view
        fprintf(stderr, "📐 [ObjC] Resizing view only (not contentView)\n");
        fflush(stderr);

        NSRect frame = [view frame];
        frame.size.width = (CGFloat)width;
        frame.size.height = (CGFloat)height;
        [view setFrame:frame];
    }

    fprintf(stderr, "📐 [ObjC] vst3_resize_nsview: done, new frame=(%f, %f, %f, %f)\n",
            view.frame.origin.x, view.frame.origin.y, view.frame.size.width, view.frame.size.height);
    fflush(stderr);
}

/// Set the BOUNDS of an NSView (for visual scaling) without changing its frame.
/// Used in embedded mode: the view frame stays at Flutter's allocated size,
/// bounds are set to the plugin's native size. Cocoa scales content automatically.
void vst3_set_nsview_bounds(void* nsview, int width, int height) {
    if (!nsview) return;

    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            vst3_set_nsview_bounds(nsview, width, height);
        });
        return;
    }

    NSView* view = (__bridge NSView*)nsview;
    [view setBoundsSize:NSMakeSize((CGFloat)width, (CGFloat)height)];
}

} // extern "C"
