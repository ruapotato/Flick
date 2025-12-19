/*
 * Flick HWComposer Shim
 *
 * A thin C library that wraps Android's hwcomposer (via libhybris) and presents
 * a simple API for Wayland compositors on Droidian/libhybris devices.
 *
 * Architecture:
 *   Compositor (Flick) -> flick_hwc shim -> libhybris -> Android HAL
 *
 * The shim handles:
 *   - gralloc initialization
 *   - HWC2 device/display/layer setup
 *   - EGL-compatible native window creation
 *   - Frame presentation via hwcomposer
 *   - Vsync handling
 *
 * Usage:
 *   1. Call flick_hwc_init() to initialize
 *   2. Get display info with flick_hwc_get_display_info()
 *   3. Get native window with flick_hwc_get_native_window()
 *   4. Create EGL display/surface/context using the native window
 *   5. Render with OpenGL
 *   6. Call eglSwapBuffers - the shim handles HWC2 presentation internally
 *   7. Call flick_hwc_destroy() on shutdown
 */

#ifndef FLICK_HWC_H
#define FLICK_HWC_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque context handle */
typedef struct FlickHwcContext FlickHwcContext;

/* Display information */
typedef struct {
    int32_t width;           /* Display width in pixels */
    int32_t height;          /* Display height in pixels */
    int32_t physical_width;  /* Physical width in mm (may be 0 if unknown) */
    int32_t physical_height; /* Physical height in mm (may be 0 if unknown) */
    int64_t vsync_period_ns; /* Vsync period in nanoseconds */
    float refresh_rate;      /* Refresh rate in Hz */
    float dpi_x;             /* Horizontal DPI */
    float dpi_y;             /* Vertical DPI */
} FlickDisplayInfo;

/* Vsync callback function type */
typedef void (*FlickVsyncCallback)(void* user_data, int64_t timestamp_ns);

/*
 * Initialize the hwcomposer subsystem.
 *
 * This will:
 *   - Initialize gralloc
 *   - Initialize HWC2
 *   - Create HWC2 device and get primary display
 *   - Create HWC2 layer for client composition
 *   - Power on the display
 *   - Create HWCNativeWindow for EGL
 *
 * Returns: Context handle on success, NULL on failure.
 */
FlickHwcContext* flick_hwc_init(void);

/*
 * Get display information.
 *
 * Parameters:
 *   ctx  - Context from flick_hwc_init()
 *   info - Output struct to fill with display info
 *
 * Returns: 0 on success, negative error code on failure.
 */
int flick_hwc_get_display_info(FlickHwcContext* ctx, FlickDisplayInfo* info);

/*
 * Get the native window pointer for use with EGL.
 *
 * This returns a pointer that can be cast to EGLNativeWindowType and
 * passed to eglCreateWindowSurface().
 *
 * Parameters:
 *   ctx - Context from flick_hwc_init()
 *
 * Returns: Native window pointer, or NULL if not initialized.
 */
void* flick_hwc_get_native_window(FlickHwcContext* ctx);

/*
 * Set display power mode.
 *
 * Parameters:
 *   ctx - Context from flick_hwc_init()
 *   on  - true to power on, false to power off
 *
 * Returns: 0 on success, negative error code on failure.
 */
int flick_hwc_set_power(FlickHwcContext* ctx, bool on);

/*
 * Enable or disable vsync events.
 *
 * When enabled, the vsync callback (if set) will be called on each vsync.
 *
 * Parameters:
 *   ctx     - Context from flick_hwc_init()
 *   enabled - true to enable vsync events, false to disable
 *
 * Returns: 0 on success, negative error code on failure.
 */
int flick_hwc_set_vsync_enabled(FlickHwcContext* ctx, bool enabled);

/*
 * Set vsync callback.
 *
 * The callback will be invoked from the HWC2 vsync thread when vsync occurs.
 * Make sure the callback is thread-safe.
 *
 * Parameters:
 *   ctx       - Context from flick_hwc_init()
 *   callback  - Function to call on vsync (or NULL to clear)
 *   user_data - User data to pass to callback
 *
 * Returns: 0 on success, negative error code on failure.
 */
int flick_hwc_set_vsync_callback(FlickHwcContext* ctx, FlickVsyncCallback callback, void* user_data);

/*
 * Get statistics about frame presentation.
 *
 * Parameters:
 *   ctx              - Context from flick_hwc_init()
 *   out_frame_count  - Output: total frames presented
 *   out_error_count  - Output: frames with presentation errors
 *
 * Returns: 0 on success, negative error code on failure.
 */
int flick_hwc_get_stats(FlickHwcContext* ctx, uint32_t* out_frame_count, uint32_t* out_error_count);

/*
 * Try to unblank/wake the display via sysfs.
 *
 * This is useful if the display is blanked by the system before we start.
 * Called automatically by flick_hwc_init(), but can be called again if needed.
 */
void flick_hwc_unblank_display(void);

/*
 * Destroy the hwcomposer context and clean up resources.
 *
 * This will:
 *   - Power off the display
 *   - Destroy HWC2 layer, display, device
 *   - Destroy native window
 *   - Free context memory
 *
 * Note: Destroy your EGL context/surface BEFORE calling this.
 *
 * Parameters:
 *   ctx - Context from flick_hwc_init()
 */
void flick_hwc_destroy(FlickHwcContext* ctx);

/*
 * Get the last error message.
 *
 * Returns: Error message string, or NULL if no error.
 *          The string is valid until the next API call.
 */
const char* flick_hwc_get_error(void);

#ifdef __cplusplus
}
#endif

#endif /* FLICK_HWC_H */
