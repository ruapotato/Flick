# Flick HWComposer Shim (hwc-shim)

A thin C library that wraps Android's hwcomposer (via libhybris) for use by
Wayland compositors on Droidian/libhybris devices (e.g., Pixel 3a, FuriLabs phones).

## Architecture

```
┌─────────────────────────────────────────┐
│          Flick Compositor               │
│     (Rust + Smithay + OpenGL ES)        │
└─────────────────────────────────────────┘
                    │
                Rust FFI
                    │
┌─────────────────────────────────────────┐
│          hwc-shim (this library)        │
│    flick_hwc_init / present_callback    │
└─────────────────────────────────────────┘
                    │
       ┌────────────┼────────────┐
       │            │            │
┌──────┴──────┐ ┌───┴───┐ ┌─────┴─────┐
│ libhybris-  │ │libhwc2│ │ libgralloc│
│hwcomposer-  │ │       │ │           │
│   window    │ │       │ │           │
└─────────────┘ └───────┘ └───────────┘
                    │
┌─────────────────────────────────────────┐
│           Android HAL                    │
│  (hwcomposer, gralloc, graphics driver) │
└─────────────────────────────────────────┘
```

## Dependencies

On Droidian, install:
```bash
sudo apt install libhybris-dev libhybris-hwcomposerwindow-dev
```

The libraries needed:
- `libhybris-hwcomposerwindow` - HWCNativeWindow for EGL
- `libhwc2` - HWC2 compatibility layer
- `libgralloc` - Graphics buffer allocation

## Building

```bash
make
```

To install:
```bash
sudo make install PREFIX=/usr
```

## Usage

```c
#include <flick_hwc.h>
#include <EGL/egl.h>

// Initialize hwcomposer
FlickHwcContext* ctx = flick_hwc_init();
if (!ctx) {
    fprintf(stderr, "Failed: %s\n", flick_hwc_get_error());
    return 1;
}

// Get display info
FlickDisplayInfo info;
flick_hwc_get_display_info(ctx, &info);
printf("Display: %dx%d @ %.1fHz\n", info.width, info.height, info.refresh_rate);

// Get native window for EGL
EGLNativeWindowType window = (EGLNativeWindowType)flick_hwc_get_native_window(ctx);

// Create EGL display, surface, context...
EGLDisplay egl_dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
// ... standard EGL setup using 'window' ...

// Render loop
while (running) {
    // Clear and render with OpenGL ES
    glClear(GL_COLOR_BUFFER_BIT);
    // ... render ...

    // Present - this triggers the internal present_callback
    // which handles HWC2 set_client_target, validate, present
    eglSwapBuffers(egl_dpy, egl_surface);
}

// Cleanup - destroy EGL first, then hwc
eglDestroyContext(egl_dpy, egl_ctx);
eglDestroySurface(egl_dpy, egl_surface);
eglTerminate(egl_dpy);
flick_hwc_destroy(ctx);
```

## API Reference

### `FlickHwcContext* flick_hwc_init(void)`
Initialize hwcomposer subsystem. Returns context handle or NULL on failure.

### `int flick_hwc_get_display_info(FlickHwcContext* ctx, FlickDisplayInfo* info)`
Get display information (size, refresh rate, DPI).

### `void* flick_hwc_get_native_window(FlickHwcContext* ctx)`
Get native window pointer for EGL.

### `int flick_hwc_set_power(FlickHwcContext* ctx, bool on)`
Set display power mode (on/off).

### `int flick_hwc_set_vsync_enabled(FlickHwcContext* ctx, bool enabled)`
Enable/disable vsync callbacks.

### `int flick_hwc_set_vsync_callback(FlickHwcContext* ctx, FlickVsyncCallback cb, void* data)`
Set callback for vsync events.

### `void flick_hwc_destroy(FlickHwcContext* ctx)`
Clean up and destroy context.

### `const char* flick_hwc_get_error(void)`
Get last error message.

## Environment Variables

- `EGL_PLATFORM=hwcomposer` - Set automatically by the library
- `FLICK_DISPLAY_WIDTH` / `FLICK_DISPLAY_HEIGHT` - Override display size detection

## How It Works

1. **Initialization**: The library initializes gralloc (for buffer allocation), creates
   an HWC2 device, gets the primary display, creates an HWC2 layer configured for
   client composition, and creates an HWCNativeWindow.

2. **EGL Setup**: The compositor uses the native window to create an EGL surface.
   When `EGL_PLATFORM=hwcomposer`, libhybris routes EGL calls through hwcomposer.

3. **Rendering**: The compositor renders with OpenGL ES to the EGL surface.

4. **Presentation**: When `eglSwapBuffers()` is called, the HWCNativeWindow's present
   callback is invoked with the rendered buffer. The callback:
   - Sets the buffer on the HWC2 layer
   - Sets the buffer as the client target
   - Validates the display composition
   - Accepts any required changes
   - Presents the frame via HWC2

5. **Vsync**: HWC2 can provide vsync callbacks for frame timing (optional).

## License

Apache 2.0 (same as libhybris)
