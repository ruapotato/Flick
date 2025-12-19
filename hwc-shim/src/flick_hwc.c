/*
 * Flick HWComposer Shim - Implementation
 *
 * Based on:
 *   - Droidian wlroots hwcomposer backend
 *   - libhybris hwc2_compatibility_layer
 *   - libhybris hwcomposerwindow
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>

#include "flick_hwc.h"

/* libhybris headers - paths may vary by distribution */
#include <hybris/hwcomposerwindow/hwcomposer.h>
#include <hybris/hwc2/hwc2_compatibility_layer.h>

/* Forward declarations for libhybris functions not in headers */
extern void hybris_gralloc_initialize(int framebuffer);

/* Android HAL pixel format */
#define HAL_PIXEL_FORMAT_RGBA_8888 1

/* HWC2 power modes */
#define HWC2_POWER_MODE_OFF 0
#define HWC2_POWER_MODE_ON 2

/* HWC2 composition types */
#define HWC2_COMPOSITION_CLIENT 1

/* HWC2 blend modes */
#define HWC2_BLEND_MODE_NONE 1

/* Error string buffer */
static __thread char g_error_buf[256];

/* Set error message */
static void set_error(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vsnprintf(g_error_buf, sizeof(g_error_buf), fmt, args);
    va_end(args);
    fprintf(stderr, "[flick_hwc] ERROR: %s\n", g_error_buf);
}

/* Log info message */
static void log_info(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    fprintf(stderr, "[flick_hwc] ");
    vfprintf(stderr, fmt, args);
    fprintf(stderr, "\n");
    va_end(args);
}

/*
 * Context structure
 */
struct FlickHwcContext {
    /* HWC2 objects */
    hwc2_compat_device_t* hwc2_device;
    hwc2_compat_display_t* hwc2_display;
    hwc2_compat_layer_t* hwc2_layer;

    /* Native window for EGL */
    struct ANativeWindow* native_window;

    /* Display info */
    FlickDisplayInfo display_info;

    /* HWC2 event listener (must remain allocated) */
    HWC2EventListener* event_listener;

    /* Vsync callback */
    FlickVsyncCallback vsync_callback;
    void* vsync_user_data;

    /* Statistics */
    atomic_uint frame_count;
    atomic_uint error_count;
    atomic_uint buffer_slot;
};

/* Global context pointer for callbacks */
static FlickHwcContext* g_ctx = NULL;

/*
 * Present callback - called by HWCNativeWindow when buffer is ready
 */
static void present_callback(void* user_data, struct ANativeWindow* window __attribute__((unused)),
                             struct ANativeWindowBuffer* buffer) {
    FlickHwcContext* ctx = (FlickHwcContext*)user_data;
    if (!ctx || !ctx->hwc2_display || !buffer) {
        return;
    }

    uint32_t count = atomic_fetch_add(&ctx->frame_count, 1);

    /* Get acquire fence from buffer */
    int32_t acquire_fence = HWCNativeBufferGetFence(buffer);

    /* Get buffer slot (rotate through 3 slots for triple buffering) */
    uint32_t slot = atomic_fetch_add(&ctx->buffer_slot, 1) % 3;

    /* Set buffer on HWC2 layer if we have one */
    if (ctx->hwc2_layer) {
        hwc2_compat_layer_set_buffer(ctx->hwc2_layer, slot, buffer, acquire_fence);
    }

    /* Set client target (the buffer we rendered to) */
    hwc2_error_t err = hwc2_compat_display_set_client_target(
        ctx->hwc2_display, slot, buffer, acquire_fence, 0 /* dataspace */);
    if (err != 0) {
        atomic_fetch_add(&ctx->error_count, 1);
        if (count % 60 == 0) {
            fprintf(stderr, "[flick_hwc] set_client_target error: %d\n", err);
        }
    }

    /* Validate display */
    uint32_t num_types = 0, num_requests = 0;
    err = hwc2_compat_display_validate(ctx->hwc2_display, &num_types, &num_requests);
    if (err != 0 && err != 3 /* HAS_CHANGES */) {
        atomic_fetch_add(&ctx->error_count, 1);
        if (count % 60 == 0) {
            fprintf(stderr, "[flick_hwc] validate error: %d\n", err);
        }
        return;
    }

    /* Accept changes if needed */
    if (num_types > 0 || num_requests > 0) {
        hwc2_compat_display_accept_changes(ctx->hwc2_display);
    }

    /* Present the frame */
    int32_t present_fence = -1;
    err = hwc2_compat_display_present(ctx->hwc2_display, &present_fence);
    if (err != 0) {
        atomic_fetch_add(&ctx->error_count, 1);
        if (count % 60 == 0) {
            fprintf(stderr, "[flick_hwc] present error: %d\n", err);
        }
    }

    /* Set present fence for next frame */
    if (present_fence >= 0) {
        HWCNativeBufferSetFence(buffer, present_fence);
    }

    /* Log progress periodically */
    if (count > 0 && count % 300 == 0) {
        log_info("frame %u, errors: %u", count, atomic_load(&ctx->error_count));
    }
}

/*
 * HWC2 vsync callback
 */
static void on_vsync(HWC2EventListener* listener, int32_t sequence_id,
                     hwc2_display_t display, int64_t timestamp) {
    (void)listener;
    (void)sequence_id;
    (void)display;

    if (g_ctx && g_ctx->vsync_callback) {
        g_ctx->vsync_callback(g_ctx->vsync_user_data, timestamp);
    }
}

/*
 * HWC2 hotplug callback
 */
static void on_hotplug(HWC2EventListener* listener, int32_t sequence_id,
                       hwc2_display_t display, bool connected, bool primary) {
    (void)listener;
    (void)sequence_id;

    log_info("hotplug: display=%llu connected=%d primary=%d",
             (unsigned long long)display, connected, primary);

    if (g_ctx && g_ctx->hwc2_device) {
        hwc2_compat_device_on_hotplug(g_ctx->hwc2_device, display, connected);
    }
}

/*
 * HWC2 refresh callback
 */
static void on_refresh(HWC2EventListener* listener, int32_t sequence_id,
                       hwc2_display_t display) {
    (void)listener;
    (void)sequence_id;
    (void)display;
    /* Not used for now */
}

/*
 * Try to unblank display via sysfs
 */
void flick_hwc_unblank_display(void) {
    /* Method 1: backlight bl_power */
    FILE* f = fopen("/sys/class/backlight/panel0-backlight/bl_power", "w");
    if (f) {
        fprintf(f, "0");
        fclose(f);
        log_info("unblanked via backlight bl_power");
    }

    /* Method 2: set brightness if it's 0 */
    f = fopen("/sys/class/backlight/panel0-backlight/brightness", "r");
    if (f) {
        char buf[16];
        if (fgets(buf, sizeof(buf), f) && atoi(buf) == 0) {
            fclose(f);
            f = fopen("/sys/class/backlight/panel0-backlight/brightness", "w");
            if (f) {
                fprintf(f, "255");
                fclose(f);
                log_info("set brightness to max");
            }
        } else {
            fclose(f);
        }
    }

    /* Method 3: fbdev ioctl */
    int fb = open("/dev/fb0", O_RDWR);
    if (fb >= 0) {
        #define FBIOBLANK 0x4611
        #define FB_BLANK_UNBLANK 0
        if (ioctl(fb, FBIOBLANK, FB_BLANK_UNBLANK) == 0) {
            log_info("unblanked via fbdev ioctl");
        }
        close(fb);
    }

    /* Method 4: graphics sysfs */
    f = fopen("/sys/class/graphics/fb0/blank", "w");
    if (f) {
        fprintf(f, "0");
        fclose(f);
        log_info("unblanked via graphics sysfs");
    }
}

/*
 * Get display dimensions from environment or system
 */
static void get_display_dimensions(int32_t* width, int32_t* height) {
    /* Try environment variables first */
    const char* env_w = getenv("FLICK_DISPLAY_WIDTH");
    const char* env_h = getenv("FLICK_DISPLAY_HEIGHT");
    if (env_w && env_h) {
        *width = atoi(env_w);
        *height = atoi(env_h);
        if (*width > 0 && *height > 0) {
            log_info("display size from env: %dx%d", *width, *height);
            return;
        }
    }

    /* Try fb0 virtual_size */
    FILE* f = fopen("/sys/class/graphics/fb0/virtual_size", "r");
    if (f) {
        if (fscanf(f, "%d,%d", width, height) == 2 && *width > 0 && *height > 0) {
            fclose(f);
            log_info("display size from fb0: %dx%d", *width, *height);
            return;
        }
        fclose(f);
    }

    /* Default */
    *width = 1080;
    *height = 2340;
    log_info("using default display size: %dx%d", *width, *height);
}

/*
 * Initialize HWC2 subsystem
 */
static int init_hwc2(FlickHwcContext* ctx) {
    log_info("initializing gralloc...");
    hybris_gralloc_initialize(0);

    log_info("initializing hwc2...");
    /* Note: hybris_hwc2_initialize() may not exist in all versions */

    log_info("creating hwc2 device...");
    ctx->hwc2_device = hwc2_compat_device_new(false /* useVrComposer */);
    if (!ctx->hwc2_device) {
        set_error("failed to create hwc2 device");
        return -1;
    }

    /* Create event listener */
    ctx->event_listener = calloc(1, sizeof(HWC2EventListener));
    if (!ctx->event_listener) {
        set_error("failed to allocate event listener");
        return -1;
    }
    ctx->event_listener->on_vsync_received = on_vsync;
    ctx->event_listener->on_hotplug_received = on_hotplug;
    ctx->event_listener->on_refresh_received = on_refresh;

    /* Register callbacks */
    log_info("registering hwc2 callbacks...");
    hwc2_compat_device_register_callback(ctx->hwc2_device, ctx->event_listener, 0);

    /* Trigger hotplug for primary display */
    hwc2_compat_device_on_hotplug(ctx->hwc2_device, 0, true);
    usleep(100000); /* 100ms delay for hotplug processing */

    /* Get primary display */
    log_info("getting primary display...");
    ctx->hwc2_display = hwc2_compat_device_get_display_by_id(ctx->hwc2_device, 0);
    if (!ctx->hwc2_display) {
        set_error("failed to get hwc2 primary display");
        return -1;
    }

    /* Get display config */
    HWC2DisplayConfig* config = hwc2_compat_display_get_active_config(ctx->hwc2_display);
    if (config) {
        ctx->display_info.width = config->width;
        ctx->display_info.height = config->height;
        ctx->display_info.vsync_period_ns = config->vsyncPeriod;
        ctx->display_info.refresh_rate = 1000000000.0f / (float)config->vsyncPeriod;
        ctx->display_info.dpi_x = config->dpiX;
        ctx->display_info.dpi_y = config->dpiY;

        /* Calculate physical size from DPI if available */
        if (config->dpiX > 0) {
            ctx->display_info.physical_width = (int32_t)(config->width / config->dpiX * 25.4f);
        }
        if (config->dpiY > 0) {
            ctx->display_info.physical_height = (int32_t)(config->height / config->dpiY * 25.4f);
        }

        log_info("hwc2 config: %dx%d @ %.1fHz, DPI: %.1fx%.1f",
                 config->width, config->height, ctx->display_info.refresh_rate,
                 config->dpiX, config->dpiY);
    } else {
        /* Fall back to detection */
        log_info("hwc2 config unavailable, using fallback");
        get_display_dimensions(&ctx->display_info.width, &ctx->display_info.height);
        ctx->display_info.vsync_period_ns = 16666666; /* 60Hz */
        ctx->display_info.refresh_rate = 60.0f;
    }

    /* Power on display */
    log_info("powering on display...");
    hwc2_error_t err = hwc2_compat_display_set_power_mode(ctx->hwc2_display, HWC2_POWER_MODE_ON);
    if (err != 0) {
        log_info("warning: set_power_mode returned %d", err);
    }

    /* Create layer for client composition */
    log_info("creating hwc2 layer...");
    ctx->hwc2_layer = hwc2_compat_display_create_layer(ctx->hwc2_display);
    if (!ctx->hwc2_layer) {
        log_info("warning: failed to create hwc2 layer (may not be required)");
    } else {
        /* Configure layer */
        int32_t w = ctx->display_info.width;
        int32_t h = ctx->display_info.height;

        hwc2_compat_layer_set_composition_type(ctx->hwc2_layer, HWC2_COMPOSITION_CLIENT);
        hwc2_compat_layer_set_blend_mode(ctx->hwc2_layer, HWC2_BLEND_MODE_NONE);
        hwc2_compat_layer_set_display_frame(ctx->hwc2_layer, 0, 0, w, h);
        hwc2_compat_layer_set_source_crop(ctx->hwc2_layer, 0.0f, 0.0f, (float)w, (float)h);
        hwc2_compat_layer_set_visible_region(ctx->hwc2_layer, 0, 0, w, h);
        hwc2_compat_layer_set_plane_alpha(ctx->hwc2_layer, 1.0f);
        log_info("hwc2 layer configured");
    }

    return 0;
}

/*
 * Initialize native window for EGL
 */
static int init_native_window(FlickHwcContext* ctx) {
    log_info("creating native window %dx%d...",
             ctx->display_info.width, ctx->display_info.height);

    ctx->native_window = HWCNativeWindowCreate(
        ctx->display_info.width,
        ctx->display_info.height,
        HAL_PIXEL_FORMAT_RGBA_8888,
        present_callback,
        ctx);

    if (!ctx->native_window) {
        set_error("failed to create native window");
        return -1;
    }

    /* Set triple buffering */
    HWCNativeWindowSetBufferCount(ctx->native_window, 3);

    log_info("native window created");
    return 0;
}

/*
 * Public API
 */

FlickHwcContext* flick_hwc_init(void) {
    log_info("initializing...");

    /* Set EGL platform */
    setenv("EGL_PLATFORM", "hwcomposer", 1);

    /* Unblank display first */
    flick_hwc_unblank_display();

    /* Allocate context */
    FlickHwcContext* ctx = calloc(1, sizeof(FlickHwcContext));
    if (!ctx) {
        set_error("failed to allocate context");
        return NULL;
    }

    /* Initialize atomics */
    atomic_init(&ctx->frame_count, 0);
    atomic_init(&ctx->error_count, 0);
    atomic_init(&ctx->buffer_slot, 0);

    /* Set global context for callbacks */
    g_ctx = ctx;

    /* Initialize HWC2 */
    if (init_hwc2(ctx) != 0) {
        flick_hwc_destroy(ctx);
        return NULL;
    }

    /* Initialize native window */
    if (init_native_window(ctx) != 0) {
        flick_hwc_destroy(ctx);
        return NULL;
    }

    /* Try to unblank again after init */
    flick_hwc_unblank_display();

    log_info("initialization complete");
    return ctx;
}

int flick_hwc_get_display_info(FlickHwcContext* ctx, FlickDisplayInfo* info) {
    if (!ctx || !info) {
        set_error("invalid parameters");
        return -1;
    }
    *info = ctx->display_info;
    return 0;
}

void* flick_hwc_get_native_window(FlickHwcContext* ctx) {
    if (!ctx) {
        return NULL;
    }
    return ctx->native_window;
}

int flick_hwc_set_power(FlickHwcContext* ctx, bool on) {
    if (!ctx || !ctx->hwc2_display) {
        set_error("invalid context or display");
        return -1;
    }

    int mode = on ? HWC2_POWER_MODE_ON : HWC2_POWER_MODE_OFF;
    hwc2_error_t err = hwc2_compat_display_set_power_mode(ctx->hwc2_display, mode);
    if (err != 0) {
        set_error("set_power_mode failed: %d", err);
        return -1;
    }

    if (on) {
        flick_hwc_unblank_display();
    }

    return 0;
}

int flick_hwc_set_vsync_enabled(FlickHwcContext* ctx, bool enabled) {
    if (!ctx || !ctx->hwc2_display) {
        set_error("invalid context or display");
        return -1;
    }

    hwc2_error_t err = hwc2_compat_display_set_vsync_enabled(ctx->hwc2_display, enabled ? 1 : 0);
    if (err != 0) {
        set_error("set_vsync_enabled failed: %d", err);
        return -1;
    }

    return 0;
}

int flick_hwc_set_vsync_callback(FlickHwcContext* ctx, FlickVsyncCallback callback, void* user_data) {
    if (!ctx) {
        set_error("invalid context");
        return -1;
    }

    ctx->vsync_callback = callback;
    ctx->vsync_user_data = user_data;
    return 0;
}

int flick_hwc_get_stats(FlickHwcContext* ctx, uint32_t* out_frame_count, uint32_t* out_error_count) {
    if (!ctx) {
        set_error("invalid context");
        return -1;
    }

    if (out_frame_count) {
        *out_frame_count = atomic_load(&ctx->frame_count);
    }
    if (out_error_count) {
        *out_error_count = atomic_load(&ctx->error_count);
    }
    return 0;
}

void flick_hwc_destroy(FlickHwcContext* ctx) {
    if (!ctx) {
        return;
    }

    log_info("shutting down...");

    /* Clear global context */
    if (g_ctx == ctx) {
        g_ctx = NULL;
    }

    /* Power off display */
    if (ctx->hwc2_display) {
        hwc2_compat_display_set_power_mode(ctx->hwc2_display, HWC2_POWER_MODE_OFF);
    }

    /* Destroy layer */
    if (ctx->hwc2_layer && ctx->hwc2_display) {
        hwc2_compat_display_destroy_layer(ctx->hwc2_display, ctx->hwc2_layer);
        ctx->hwc2_layer = NULL;
    }

    /* Destroy display */
    if (ctx->hwc2_display && ctx->hwc2_device) {
        hwc2_compat_device_destroy_display(ctx->hwc2_device, ctx->hwc2_display);
        ctx->hwc2_display = NULL;
    }

    /* Native window - usually destroyed by EGL */
    if (ctx->native_window) {
        HWCNativeWindowDestroy(ctx->native_window);
        ctx->native_window = NULL;
    }

    /* Free event listener */
    if (ctx->event_listener) {
        free(ctx->event_listener);
        ctx->event_listener = NULL;
    }

    /* Note: hwc2_device doesn't have a destroy function in libhybris */
    ctx->hwc2_device = NULL;

    free(ctx);
    log_info("shutdown complete");
}

const char* flick_hwc_get_error(void) {
    return g_error_buf[0] ? g_error_buf : NULL;
}
