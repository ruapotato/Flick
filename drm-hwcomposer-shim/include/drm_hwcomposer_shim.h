/**
 * drm-hwcomposer-shim C API
 *
 * This header provides a C interface to the DRM/GBM shim that wraps Android's
 * hwcomposer. It can be used as a drop-in replacement for libdrm and libgbm
 * on Android-based Linux phones (Droidian, etc.)
 *
 * Usage:
 *   1. Initialize the shim: drm_hwcomposer_shim_init()
 *   2. Use gbm_* functions for buffer management
 *   3. Use drmMode* functions for display control
 *   4. Use EGL with the hwcomposer platform for rendering
 */

#ifndef DRM_HWCOMPOSER_SHIM_H
#define DRM_HWCOMPOSER_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ==========================================================================
 * GBM Types and Constants
 * ========================================================================== */

/* Opaque types */
typedef struct gbm_device gbm_device;
typedef struct gbm_bo gbm_bo;
typedef struct gbm_surface gbm_surface;

/* Buffer object flags */
#define GBM_BO_USE_SCANOUT    (1 << 0)
#define GBM_BO_USE_CURSOR     (1 << 1)
#define GBM_BO_USE_RENDERING  (1 << 2)
#define GBM_BO_USE_WRITE      (1 << 3)
#define GBM_BO_USE_LINEAR     (1 << 4)

/* Buffer formats (DRM fourcc codes) */
#define GBM_FORMAT_XRGB8888   0x34325258  /* 'XR24' */
#define GBM_FORMAT_ARGB8888   0x34325241  /* 'AR24' */
#define GBM_FORMAT_RGB565     0x36314752  /* 'RG16' */
#define GBM_FORMAT_XBGR8888   0x34324258  /* 'XB24' */
#define GBM_FORMAT_ABGR8888   0x34324241  /* 'AB24' */

/* Map transfer flags */
#define GBM_BO_TRANSFER_READ       (1 << 0)
#define GBM_BO_TRANSFER_WRITE      (1 << 1)
#define GBM_BO_TRANSFER_READ_WRITE (GBM_BO_TRANSFER_READ | GBM_BO_TRANSFER_WRITE)

/* Buffer handle union */
union gbm_bo_handle {
    void *ptr;
    int32_t s32;
    uint32_t u32;
    int64_t s64;
    uint64_t u64;
};

/* ==========================================================================
 * GBM Device Functions
 * ========================================================================== */

/**
 * Create a GBM device from a DRM file descriptor.
 * Note: For this shim, the fd parameter is ignored - hwcomposer is used internally.
 */
gbm_device *gbm_create_device(int fd);

/** Destroy a GBM device */
void gbm_device_destroy(gbm_device *device);

/** Get the file descriptor associated with the GBM device */
int gbm_device_get_fd(gbm_device *device);

/** Check if a format/usage combination is supported */
int gbm_device_is_format_supported(gbm_device *device, uint32_t format, uint32_t usage);

/** Get the backend name */
const char *gbm_device_get_backend_name(gbm_device *device);

/* ==========================================================================
 * GBM Buffer Object Functions
 * ========================================================================== */

/** Create a buffer object */
gbm_bo *gbm_bo_create(gbm_device *device, uint32_t width, uint32_t height,
                      uint32_t format, uint32_t flags);

/** Create a buffer object with explicit modifiers */
gbm_bo *gbm_bo_create_with_modifiers(gbm_device *device, uint32_t width, uint32_t height,
                                     uint32_t format, const uint64_t *modifiers, unsigned int count);

/** Create a buffer object with modifiers and flags */
gbm_bo *gbm_bo_create_with_modifiers2(gbm_device *device, uint32_t width, uint32_t height,
                                      uint32_t format, const uint64_t *modifiers, unsigned int count,
                                      uint32_t flags);

/** Destroy a buffer object */
void gbm_bo_destroy(gbm_bo *bo);

/** Get buffer width */
uint32_t gbm_bo_get_width(gbm_bo *bo);

/** Get buffer height */
uint32_t gbm_bo_get_height(gbm_bo *bo);

/** Get buffer stride (pitch) in bytes */
uint32_t gbm_bo_get_stride(gbm_bo *bo);

/** Get stride for a specific plane */
uint32_t gbm_bo_get_stride_for_plane(gbm_bo *bo, int plane);

/** Get buffer format (DRM fourcc) */
uint32_t gbm_bo_get_format(gbm_bo *bo);

/** Get buffer bits per pixel */
uint32_t gbm_bo_get_bpp(gbm_bo *bo);

/** Get offset for a specific plane */
uint32_t gbm_bo_get_offset(gbm_bo *bo, int plane);

/** Get the GBM device this buffer was created from */
gbm_device *gbm_bo_get_device(gbm_bo *bo);

/** Get the native handle */
union gbm_bo_handle gbm_bo_get_handle(gbm_bo *bo);

/** Get handle for a specific plane */
union gbm_bo_handle gbm_bo_get_handle_for_plane(gbm_bo *bo, int plane);

/** Get format modifier (returns DRM_FORMAT_MOD_INVALID for this shim) */
uint64_t gbm_bo_get_modifier(gbm_bo *bo);

/** Get number of planes */
int gbm_bo_get_plane_count(gbm_bo *bo);

/** Get DMA-BUF fd (not yet implemented) */
int gbm_bo_get_fd(gbm_bo *bo);

/** Get DMA-BUF fd for a specific plane */
int gbm_bo_get_fd_for_plane(gbm_bo *bo, int plane);

/** Map buffer for CPU access */
void *gbm_bo_map(gbm_bo *bo, uint32_t x, uint32_t y, uint32_t width, uint32_t height,
                 uint32_t flags, uint32_t *stride, void **map_data);

/** Unmap buffer */
void gbm_bo_unmap(gbm_bo *bo, void *map_data);

/** User data destroy callback type */
typedef void (*gbm_bo_user_data_destroy_func)(gbm_bo *bo, void *data);

/** Set user data on a buffer object */
void gbm_bo_set_user_data(gbm_bo *bo, void *data, gbm_bo_user_data_destroy_func destroy_fn);

/** Get user data from a buffer object */
void *gbm_bo_get_user_data(gbm_bo *bo);

/* ==========================================================================
 * GBM Surface Functions
 * ========================================================================== */

/** Create a GBM surface for rendering */
gbm_surface *gbm_surface_create(gbm_device *device, uint32_t width, uint32_t height,
                                uint32_t format, uint32_t flags);

/** Create a GBM surface with modifiers */
gbm_surface *gbm_surface_create_with_modifiers(gbm_device *device, uint32_t width, uint32_t height,
                                               uint32_t format, const uint64_t *modifiers,
                                               unsigned int count);

/** Create a GBM surface with modifiers and flags */
gbm_surface *gbm_surface_create_with_modifiers2(gbm_device *device, uint32_t width, uint32_t height,
                                                uint32_t format, const uint64_t *modifiers,
                                                unsigned int count, uint32_t flags);

/** Destroy a GBM surface */
void gbm_surface_destroy(gbm_surface *surface);

/** Lock the front buffer for scanout */
gbm_bo *gbm_surface_lock_front_buffer(gbm_surface *surface);

/** Release a locked buffer back to the surface */
void gbm_surface_release_buffer(gbm_surface *surface, gbm_bo *bo);

/** Check if a surface has a free buffer */
int gbm_surface_has_free_buffers(gbm_surface *surface);

/* ==========================================================================
 * DRM Types and Constants
 * ========================================================================== */

/* Mode info structure */
typedef struct _drmModeModeInfo {
    uint32_t clock;
    uint16_t hdisplay;
    uint16_t hsync_start;
    uint16_t hsync_end;
    uint16_t htotal;
    uint16_t hskew;
    uint16_t vdisplay;
    uint16_t vsync_start;
    uint16_t vsync_end;
    uint16_t vtotal;
    uint16_t vscan;
    uint32_t vrefresh;
    uint32_t flags;
    uint32_t type;
    char name[32];
} drmModeModeInfo, *drmModeModeInfoPtr;

/* Resources structure */
typedef struct _drmModeRes {
    int count_fbs;
    uint32_t *fbs;
    int count_crtcs;
    uint32_t *crtcs;
    int count_connectors;
    uint32_t *connectors;
    int count_encoders;
    uint32_t *encoders;
    uint32_t min_width, max_width;
    uint32_t min_height, max_height;
} drmModeRes, *drmModeResPtr;

/* Connector structure */
typedef struct _drmModeConnector {
    uint32_t connector_id;
    uint32_t encoder_id;
    uint32_t connector_type;
    uint32_t connector_type_id;
    uint32_t connection;
    uint32_t mmWidth, mmHeight;
    uint32_t subpixel;
    int count_modes;
    drmModeModeInfoPtr modes;
    int count_props;
    uint32_t *props;
    uint64_t *prop_values;
    int count_encoders;
    uint32_t *encoders;
} drmModeConnector, *drmModeConnectorPtr;

/* CRTC structure */
typedef struct _drmModeCrtc {
    uint32_t crtc_id;
    uint32_t buffer_id;
    uint32_t x, y;
    uint32_t width, height;
    int mode_valid;
    drmModeModeInfo mode;
    int gamma_size;
} drmModeCrtc, *drmModeCrtcPtr;

/* Plane structure */
typedef struct _drmModePlane {
    uint32_t count_formats;
    uint32_t *formats;
    uint32_t plane_id;
    uint32_t crtc_id;
    uint32_t fb_id;
    uint32_t crtc_x, crtc_y;
    uint32_t x, y;
    uint32_t possible_crtcs;
    uint32_t gamma_size;
} drmModePlane, *drmModePlanePtr;

/* Plane resources structure */
typedef struct _drmModePlaneRes {
    uint32_t count_planes;
    uint32_t *planes;
} drmModePlaneRes, *drmModePlaneResPtr;

/* Framebuffer structure */
typedef struct _drmModeFB {
    uint32_t fb_id;
    uint32_t width, height;
    uint32_t pitch;
    uint32_t bpp;
    uint32_t depth;
    uint32_t handle;
} drmModeFB, *drmModeFBPtr;

/* Version structure */
typedef struct _drmVersion {
    int version_major;
    int version_minor;
    int version_patchlevel;
    int name_len;
    char *name;
    int date_len;
    char *date;
    int desc_len;
    char *desc;
} drmVersion, *drmVersionPtr;

/* Connection status */
#define DRM_MODE_CONNECTED         1
#define DRM_MODE_DISCONNECTED      2
#define DRM_MODE_UNKNOWNCONNECTION 3

/* Connector types */
#define DRM_MODE_CONNECTOR_DSI     16
#define DRM_MODE_CONNECTOR_VIRTUAL 15

/* Page flip flags */
#define DRM_MODE_PAGE_FLIP_EVENT   0x01
#define DRM_MODE_PAGE_FLIP_ASYNC   0x02

/* ==========================================================================
 * DRM Functions
 * ========================================================================== */

/** Get DRM resources */
drmModeResPtr drmModeGetResources(int fd);

/** Free DRM resources */
void drmModeFreeResources(drmModeResPtr res);

/** Get connector info */
drmModeConnectorPtr drmModeGetConnector(int fd, uint32_t connector_id);

/** Free connector */
void drmModeFreeConnector(drmModeConnectorPtr connector);

/** Get CRTC info */
drmModeCrtcPtr drmModeGetCrtc(int fd, uint32_t crtc_id);

/** Free CRTC */
void drmModeFreeCrtc(drmModeCrtcPtr crtc);

/** Get plane resources */
drmModePlaneResPtr drmModeGetPlaneResources(int fd);

/** Free plane resources */
void drmModeFreePlaneResources(drmModePlaneResPtr res);

/** Get plane info */
drmModePlanePtr drmModeGetPlane(int fd, uint32_t plane_id);

/** Free plane */
void drmModeFreePlane(drmModePlanePtr plane);

/** Add a framebuffer */
int drmModeAddFB(int fd, uint32_t width, uint32_t height, uint8_t depth,
                 uint8_t bpp, uint32_t pitch, uint32_t bo_handle, uint32_t *buf_id);

/** Add a framebuffer with format */
int drmModeAddFB2(int fd, uint32_t width, uint32_t height, uint32_t pixel_format,
                  const uint32_t *bo_handles, const uint32_t *pitches,
                  const uint32_t *offsets, uint32_t *buf_id, uint32_t flags);

/** Remove a framebuffer */
int drmModeRmFB(int fd, uint32_t fb_id);

/** Get framebuffer info */
drmModeFBPtr drmModeGetFB(int fd, uint32_t fb_id);

/** Free framebuffer info */
void drmModeFreeFB(drmModeFBPtr fb);

/** Set plane */
int drmModeSetPlane(int fd, uint32_t plane_id, uint32_t crtc_id, uint32_t fb_id,
                    uint32_t flags, int32_t crtc_x, int32_t crtc_y,
                    uint32_t crtc_w, uint32_t crtc_h,
                    uint32_t src_x, uint32_t src_y, uint32_t src_w, uint32_t src_h);

/** Page flip */
int drmModePageFlip(int fd, uint32_t crtc_id, uint32_t fb_id, uint32_t flags, void *user_data);

/** Set CRTC mode */
int drmModeSetCrtc(int fd, uint32_t crtc_id, uint32_t fb_id, uint32_t x, uint32_t y,
                   const uint32_t *connectors, int count, drmModeModeInfoPtr mode);

/** Set client capability */
int drmSetClientCap(int fd, uint64_t capability, uint64_t value);

/** Get device capability */
int drmGetCap(int fd, uint64_t capability, uint64_t *value);

/** Get DRM version */
drmVersionPtr drmGetVersion(int fd);

/** Free DRM version */
void drmFreeVersion(drmVersionPtr version);

/* ==========================================================================
 * Shim-specific Functions
 * ========================================================================== */

/**
 * Initialize the hwcomposer shim.
 * Call this before using any other functions.
 * Returns 0 on success, -1 on failure.
 */
int drm_hwcomposer_shim_init(void);

/**
 * Get the EGL display from the shim.
 * Use this for EGL integration instead of eglGetDisplay().
 */
void *drm_hwcomposer_shim_get_egl_display(void);

/**
 * Initialize EGL on the shim device.
 * Returns 0 on success, -1 on failure.
 */
int drm_hwcomposer_shim_init_egl(void);

/**
 * Swap buffers (present to display).
 * Returns 0 on success, -1 on failure.
 */
int drm_hwcomposer_shim_swap_buffers(void);

#ifdef __cplusplus
}
#endif

#endif /* DRM_HWCOMPOSER_SHIM_H */
