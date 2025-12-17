//! C API for libgbm/libdrm compatibility
//!
//! This module provides C-compatible functions that match the libgbm and libdrm APIs,
//! allowing existing applications to use this shim as a drop-in replacement.

use crate::drm_device::{HwcDrmDevice, drm_fourcc, PlaneType};
use crate::gbm_device::{GbmFormat, HwcGbmBo, HwcGbmDevice, HwcGbmSurface, gbm_usage};
use std::ffi::{c_char, c_int, c_uint, c_void, CStr};
use std::ptr;
use std::sync::{Arc, Mutex, Once};
use tracing::{debug, error, info, warn};

// RTLD_NEXT for getting the next symbol in the lookup chain (for LD_PRELOAD)
const RTLD_NEXT: *mut c_void = -1isize as *mut c_void;

// Cached function pointers for real libc functions
static mut REAL_IOCTL: Option<unsafe extern "C" fn(c_int, libc::c_ulong, ...) -> c_int> = None;
static mut REAL_OPEN_FN: Option<unsafe extern "C" fn(*const c_char, c_int, libc::mode_t) -> c_int> = None;
static INIT_REAL_FUNCS: Once = Once::new();

/// Library constructor - runs when the library is loaded via LD_PRELOAD
#[no_mangle]
#[used]
#[link_section = ".init_array"]
static LIBRARY_INIT: unsafe extern "C" fn() = library_init;

unsafe extern "C" fn library_init() {
    // Initialize tracing early (simple init)
    let _ = tracing_subscriber::fmt().try_init();

    eprintln!("=== drm-hwcomposer-shim LOADED via LD_PRELOAD ===");
    info!("drm-hwcomposer-shim: Library loaded, intercepting DRM/GBM calls");
}

// =============================================================================
// GBM Types (matching libgbm)
// =============================================================================

/// Opaque GBM device handle
pub struct gbm_device {
    inner: Arc<HwcGbmDevice>,
    drm: Arc<HwcDrmDevice>,
}

/// Opaque GBM buffer object handle
pub struct gbm_bo {
    inner: Option<HwcGbmBo>,
    device: *mut gbm_device,
    user_data: *mut c_void,
    destroy_fn: Option<extern "C" fn(*mut gbm_bo, *mut c_void)>,
}

/// Opaque GBM surface handle
pub struct gbm_surface {
    inner: Option<HwcGbmSurface>,
    device: *mut gbm_device,
}

/// GBM buffer object flags
pub const GBM_BO_USE_SCANOUT: u32 = gbm_usage::GBM_BO_USE_SCANOUT;
pub const GBM_BO_USE_CURSOR: u32 = gbm_usage::GBM_BO_USE_CURSOR;
pub const GBM_BO_USE_RENDERING: u32 = gbm_usage::GBM_BO_USE_RENDERING;
pub const GBM_BO_USE_WRITE: u32 = gbm_usage::GBM_BO_USE_WRITE;
pub const GBM_BO_USE_LINEAR: u32 = gbm_usage::GBM_BO_USE_LINEAR;

/// GBM buffer formats (DRM fourcc)
pub const GBM_FORMAT_XRGB8888: u32 = drm_fourcc::DRM_FORMAT_XRGB8888;
pub const GBM_FORMAT_ARGB8888: u32 = drm_fourcc::DRM_FORMAT_ARGB8888;
pub const GBM_FORMAT_RGB565: u32 = drm_fourcc::DRM_FORMAT_RGB565;
pub const GBM_FORMAT_XBGR8888: u32 = drm_fourcc::DRM_FORMAT_XBGR8888;
pub const GBM_FORMAT_ABGR8888: u32 = drm_fourcc::DRM_FORMAT_ABGR8888;

/// GBM map transfer flags
pub const GBM_BO_TRANSFER_READ: u32 = 1 << 0;
pub const GBM_BO_TRANSFER_WRITE: u32 = 1 << 1;
pub const GBM_BO_TRANSFER_READ_WRITE: u32 = GBM_BO_TRANSFER_READ | GBM_BO_TRANSFER_WRITE;

// Global device storage (since we have a single hwcomposer instance)
static GLOBAL_DRM: Mutex<Option<Arc<HwcDrmDevice>>> = Mutex::new(None);

fn format_to_gbm(format: u32) -> Option<GbmFormat> {
    match format {
        GBM_FORMAT_XRGB8888 => Some(GbmFormat::Xrgb8888),
        GBM_FORMAT_ARGB8888 => Some(GbmFormat::Argb8888),
        GBM_FORMAT_RGB565 => Some(GbmFormat::Rgb565),
        GBM_FORMAT_XBGR8888 => Some(GbmFormat::Xbgr8888),
        GBM_FORMAT_ABGR8888 => Some(GbmFormat::Abgr8888),
        _ => None,
    }
}

// =============================================================================
// GBM Device Functions
// =============================================================================

/// Create a GBM device from a DRM file descriptor
/// For this shim, the fd is ignored - we use hwcomposer internally
#[no_mangle]
pub unsafe extern "C" fn gbm_create_device(fd: c_int) -> *mut gbm_device {
    info!("gbm_create_device(fd={})", fd);

    // Try to initialize - this determines if we're the main process
    let init_result = drm_hwcomposer_shim_init();

    // If we're not the main shim process, return null (let real libgbm handle it)
    if !is_main_shim_process() {
        debug!("gbm_create_device: not main shim process, returning null");
        return ptr::null_mut();
    }

    if init_result != 0 {
        error!("Failed to initialize shim for GBM device");
        return ptr::null_mut();
    }

    // Get global DRM device (should be initialized now)
    let drm = {
        let global = GLOBAL_DRM.lock().unwrap();
        match global.clone() {
            Some(d) => d,
            None => {
                error!("GLOBAL_DRM not set after init");
                return ptr::null_mut();
            }
        }
    };

    // Create GBM device
    let gbm = match HwcGbmDevice::new(drm.clone()) {
        Ok(g) => Arc::new(g),
        Err(e) => {
            error!("Failed to create GBM device: {}", e);
            return ptr::null_mut();
        }
    };

    let device = Box::new(gbm_device {
        inner: gbm,
        drm,
    });

    Box::into_raw(device)
}

/// Destroy a GBM device
#[no_mangle]
pub unsafe extern "C" fn gbm_device_destroy(device: *mut gbm_device) {
    if device.is_null() {
        return;
    }
    debug!("gbm_device_destroy");
    let _ = Box::from_raw(device);
}

/// Get the file descriptor associated with the GBM device
#[no_mangle]
pub unsafe extern "C" fn gbm_device_get_fd(device: *mut gbm_device) -> c_int {
    if device.is_null() {
        return -1;
    }
    // Return a placeholder - we don't have a real DRM fd
    -1
}

/// Check if a format/usage combination is supported
#[no_mangle]
pub unsafe extern "C" fn gbm_device_is_format_supported(
    device: *mut gbm_device,
    format: u32,
    usage: u32,
) -> c_int {
    if device.is_null() {
        return 0;
    }

    // We support common formats
    let supported = matches!(
        format,
        GBM_FORMAT_XRGB8888
            | GBM_FORMAT_ARGB8888
            | GBM_FORMAT_RGB565
            | GBM_FORMAT_XBGR8888
            | GBM_FORMAT_ABGR8888
    );

    if supported { 1 } else { 0 }
}

/// Get the backend name
#[no_mangle]
pub unsafe extern "C" fn gbm_device_get_backend_name(device: *mut gbm_device) -> *const c_char {
    static NAME: &[u8] = b"hwcomposer\0";
    NAME.as_ptr() as *const c_char
}

// =============================================================================
// GBM Buffer Object Functions
// =============================================================================

/// Create a buffer object
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_create(
    device: *mut gbm_device,
    width: u32,
    height: u32,
    format: u32,
    flags: u32,
) -> *mut gbm_bo {
    if device.is_null() {
        return ptr::null_mut();
    }

    debug!("gbm_bo_create({}x{}, format=0x{:08x}, flags=0x{:x})", width, height, format, flags);

    let gbm_format = match format_to_gbm(format) {
        Some(f) => f,
        None => {
            error!("Unsupported format: 0x{:08x}", format);
            return ptr::null_mut();
        }
    };

    let dev = &*device;
    match dev.inner.create_bo(width, height, gbm_format, flags) {
        Ok(bo) => {
            let bo_ptr = Box::new(gbm_bo {
                inner: Some(bo),
                device,
                user_data: ptr::null_mut(),
                destroy_fn: None,
            });
            Box::into_raw(bo_ptr)
        }
        Err(e) => {
            error!("Failed to create buffer: {}", e);
            ptr::null_mut()
        }
    }
}

/// Create a buffer object with explicit modifiers
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_create_with_modifiers(
    device: *mut gbm_device,
    width: u32,
    height: u32,
    format: u32,
    modifiers: *const u64,
    count: c_uint,
) -> *mut gbm_bo {
    // We don't support modifiers, fall back to regular creation
    gbm_bo_create(device, width, height, format, GBM_BO_USE_RENDERING | GBM_BO_USE_SCANOUT)
}

/// Create a buffer object with explicit modifiers and usage flags
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_create_with_modifiers2(
    device: *mut gbm_device,
    width: u32,
    height: u32,
    format: u32,
    modifiers: *const u64,
    count: c_uint,
    flags: u32,
) -> *mut gbm_bo {
    // We don't support modifiers, fall back to regular creation
    gbm_bo_create(device, width, height, format, flags)
}

/// Destroy a buffer object
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_destroy(bo: *mut gbm_bo) {
    if bo.is_null() {
        return;
    }

    let bo_box = Box::from_raw(bo);

    // Call user destroy callback if set
    if let Some(destroy_fn) = bo_box.destroy_fn {
        if !bo_box.user_data.is_null() {
            destroy_fn(bo, bo_box.user_data);
        }
    }

    debug!("gbm_bo_destroy");
    // bo_box drops here, freeing the gralloc buffer
}

/// Get buffer width
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_get_width(bo: *mut gbm_bo) -> u32 {
    if bo.is_null() {
        return 0;
    }
    (*bo).inner.as_ref().map(|b| b.width()).unwrap_or(0)
}

/// Get buffer height
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_get_height(bo: *mut gbm_bo) -> u32 {
    if bo.is_null() {
        return 0;
    }
    (*bo).inner.as_ref().map(|b| b.height()).unwrap_or(0)
}

/// Get buffer stride
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_get_stride(bo: *mut gbm_bo) -> u32 {
    if bo.is_null() {
        return 0;
    }
    (*bo).inner.as_ref().map(|b| b.stride()).unwrap_or(0)
}

/// Get stride for a specific plane
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_get_stride_for_plane(bo: *mut gbm_bo, plane: c_int) -> u32 {
    if plane == 0 {
        gbm_bo_get_stride(bo)
    } else {
        0 // We only support single-plane formats for now
    }
}

/// Get buffer format
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_get_format(bo: *mut gbm_bo) -> u32 {
    if bo.is_null() {
        return 0;
    }
    (*bo).inner.as_ref().map(|b| b.format() as u32).unwrap_or(0)
}

/// Get buffer bits per pixel
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_get_bpp(bo: *mut gbm_bo) -> u32 {
    if bo.is_null() {
        return 0;
    }
    (*bo).inner.as_ref().map(|b| b.format().bpp() * 8).unwrap_or(0)
}

/// Get offset for a specific plane
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_get_offset(bo: *mut gbm_bo, plane: c_int) -> u32 {
    0 // We only support single-plane formats
}

/// Get the GBM device this buffer was created from
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_get_device(bo: *mut gbm_bo) -> *mut gbm_device {
    if bo.is_null() {
        return ptr::null_mut();
    }
    (*bo).device
}

/// Get the native handle (gralloc handle)
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_get_handle(bo: *mut gbm_bo) -> GbmBoHandle {
    if bo.is_null() {
        return GbmBoHandle { ptr: ptr::null_mut() };
    }
    let handle = (*bo).inner.as_ref().map(|b| b.handle()).unwrap_or(ptr::null_mut());
    GbmBoHandle { ptr: handle as *mut c_void }
}

/// Get handle for a specific plane
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_get_handle_for_plane(bo: *mut gbm_bo, plane: c_int) -> GbmBoHandle {
    if plane == 0 {
        gbm_bo_get_handle(bo)
    } else {
        GbmBoHandle { ptr: ptr::null_mut() }
    }
}

/// Union for various handle types
#[repr(C)]
pub union GbmBoHandle {
    pub ptr: *mut c_void,
    pub s32: i32,
    pub u32_: u32,
    pub s64: i64,
    pub u64_: u64,
}

/// Get modifier (we don't support modifiers)
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_get_modifier(bo: *mut gbm_bo) -> u64 {
    // DRM_FORMAT_MOD_INVALID
    0x00ffffffffffffff
}

/// Get number of planes
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_get_plane_count(bo: *mut gbm_bo) -> c_int {
    if bo.is_null() {
        return 0;
    }
    1 // We only support single-plane formats
}

/// Get DMA-BUF fd for this buffer
/// Returns a duplicated fd - caller is responsible for closing it
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_get_fd(bo: *mut gbm_bo) -> c_int {
    if bo.is_null() {
        return -1;
    }

    let bo_ref = &*bo;
    if let Some(ref inner) = bo_ref.inner {
        match inner.get_dmabuf_fd() {
            Ok(fd) => fd,
            Err(e) => {
                debug!("gbm_bo_get_fd failed: {}", e);
                -1
            }
        }
    } else {
        -1
    }
}

/// Get DMA-BUF fd for a specific plane
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_get_fd_for_plane(bo: *mut gbm_bo, plane: c_int) -> c_int {
    if plane == 0 {
        gbm_bo_get_fd(bo)
    } else {
        -1
    }
}

/// Import a DMA-BUF as a buffer object
/// This creates a gbm_bo that references the imported buffer
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_import(
    device: *mut gbm_device,
    type_: u32,
    buffer: *mut c_void,
    usage: u32,
) -> *mut gbm_bo {
    if device.is_null() || buffer.is_null() {
        return ptr::null_mut();
    }

    // GBM_BO_IMPORT_FD = 0x5504
    // GBM_BO_IMPORT_FD_MODIFIER = 0x5505
    const GBM_BO_IMPORT_FD: u32 = 0x5504;
    const GBM_BO_IMPORT_FD_MODIFIER: u32 = 0x5505;

    match type_ {
        GBM_BO_IMPORT_FD | GBM_BO_IMPORT_FD_MODIFIER => {
            // For now, we don't fully support import - would need gralloc import
            warn!("gbm_bo_import: DMA-BUF import not fully implemented");
            ptr::null_mut()
        }
        _ => {
            error!("gbm_bo_import: Unknown import type {}", type_);
            ptr::null_mut()
        }
    }
}

/// Map buffer for CPU access
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_map(
    bo: *mut gbm_bo,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    flags: u32,
    stride: *mut u32,
    map_data: *mut *mut c_void,
) -> *mut c_void {
    if bo.is_null() {
        return ptr::null_mut();
    }

    let bo_ref = &*bo;
    if let Some(ref inner) = bo_ref.inner {
        match inner.map() {
            Ok(ptr) => {
                if !stride.is_null() {
                    *stride = inner.stride();
                }
                if !map_data.is_null() {
                    // Store the mapped pointer for unmap
                    *map_data = ptr;
                }
                ptr
            }
            Err(e) => {
                error!("gbm_bo_map failed: {}", e);
                ptr::null_mut()
            }
        }
    } else {
        ptr::null_mut()
    }
}

/// Unmap buffer
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_unmap(bo: *mut gbm_bo, map_data: *mut c_void) {
    if bo.is_null() {
        return;
    }

    let bo_ref = &*bo;
    if let Some(ref inner) = bo_ref.inner {
        if let Err(e) = inner.unmap() {
            error!("gbm_bo_unmap failed: {}", e);
        }
    }
}

/// Set user data on a buffer object
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_set_user_data(
    bo: *mut gbm_bo,
    data: *mut c_void,
    destroy_fn: Option<extern "C" fn(*mut gbm_bo, *mut c_void)>,
) {
    if bo.is_null() {
        return;
    }
    (*bo).user_data = data;
    (*bo).destroy_fn = destroy_fn;
}

/// Get user data from a buffer object
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_get_user_data(bo: *mut gbm_bo) -> *mut c_void {
    if bo.is_null() {
        return ptr::null_mut();
    }
    (*bo).user_data
}

// =============================================================================
// GBM Surface Functions
// =============================================================================

/// Create a GBM surface for rendering
#[no_mangle]
pub unsafe extern "C" fn gbm_surface_create(
    device: *mut gbm_device,
    width: u32,
    height: u32,
    format: u32,
    flags: u32,
) -> *mut gbm_surface {
    if device.is_null() {
        return ptr::null_mut();
    }

    debug!("gbm_surface_create({}x{}, format=0x{:08x}, flags=0x{:x})", width, height, format, flags);

    let gbm_format = match format_to_gbm(format) {
        Some(f) => f,
        None => {
            error!("Unsupported format: 0x{:08x}", format);
            return ptr::null_mut();
        }
    };

    let dev = &*device;
    match dev.inner.create_surface(width, height, gbm_format, flags) {
        Ok(surface) => {
            let surface_ptr = Box::new(gbm_surface {
                inner: Some(surface),
                device,
            });
            Box::into_raw(surface_ptr)
        }
        Err(e) => {
            error!("Failed to create surface: {}", e);
            ptr::null_mut()
        }
    }
}

/// Create a GBM surface with modifiers
#[no_mangle]
pub unsafe extern "C" fn gbm_surface_create_with_modifiers(
    device: *mut gbm_device,
    width: u32,
    height: u32,
    format: u32,
    modifiers: *const u64,
    count: c_uint,
) -> *mut gbm_surface {
    // We don't support modifiers, fall back to regular creation
    gbm_surface_create(device, width, height, format, GBM_BO_USE_RENDERING | GBM_BO_USE_SCANOUT)
}

/// Create a GBM surface with modifiers and flags
#[no_mangle]
pub unsafe extern "C" fn gbm_surface_create_with_modifiers2(
    device: *mut gbm_device,
    width: u32,
    height: u32,
    format: u32,
    modifiers: *const u64,
    count: c_uint,
    flags: u32,
) -> *mut gbm_surface {
    // We don't support modifiers, fall back to regular creation
    gbm_surface_create(device, width, height, format, flags)
}

/// Destroy a GBM surface
#[no_mangle]
pub unsafe extern "C" fn gbm_surface_destroy(surface: *mut gbm_surface) {
    if surface.is_null() {
        return;
    }
    debug!("gbm_surface_destroy");
    let _ = Box::from_raw(surface);
}

/// Lock the front buffer for scanout
/// Returns a borrowed reference - caller must NOT destroy it
#[no_mangle]
pub unsafe extern "C" fn gbm_surface_lock_front_buffer(surface: *mut gbm_surface) -> *mut gbm_bo {
    if surface.is_null() {
        return ptr::null_mut();
    }

    let surface_ref = &mut *surface;
    if let Some(ref mut inner) = surface_ref.inner {
        match inner.lock_front_buffer() {
            Ok(bo) => {
                // Create a wrapper that doesn't own the buffer
                // Note: This is a simplification - proper impl would manage buffer lifecycle
                let bo_ptr = Box::new(gbm_bo {
                    inner: None, // Don't transfer ownership
                    device: surface_ref.device,
                    user_data: ptr::null_mut(),
                    destroy_fn: None,
                });
                Box::into_raw(bo_ptr)
            }
            Err(e) => {
                error!("Failed to lock front buffer: {}", e);
                ptr::null_mut()
            }
        }
    } else {
        ptr::null_mut()
    }
}

/// Release a locked buffer back to the surface
#[no_mangle]
pub unsafe extern "C" fn gbm_surface_release_buffer(surface: *mut gbm_surface, bo: *mut gbm_bo) {
    if bo.is_null() {
        return;
    }
    // Free the wrapper (doesn't free the actual buffer since inner is None)
    let _ = Box::from_raw(bo);
}

/// Check if a surface has a free buffer
#[no_mangle]
pub unsafe extern "C" fn gbm_surface_has_free_buffers(surface: *mut gbm_surface) -> c_int {
    // With triple buffering, we usually have free buffers
    1
}

// =============================================================================
// DRM Types (matching libdrm)
// =============================================================================

/// DRM mode info structure
#[repr(C)]
pub struct drmModeModeInfo {
    pub clock: u32,
    pub hdisplay: u16,
    pub hsync_start: u16,
    pub hsync_end: u16,
    pub htotal: u16,
    pub hskew: u16,
    pub vdisplay: u16,
    pub vsync_start: u16,
    pub vsync_end: u16,
    pub vtotal: u16,
    pub vscan: u16,
    pub vrefresh: u32,
    pub flags: u32,
    pub type_: u32,
    pub name: [c_char; 32],
}

/// DRM resources structure
#[repr(C)]
pub struct drmModeRes {
    pub count_fbs: c_int,
    pub fbs: *mut u32,
    pub count_crtcs: c_int,
    pub crtcs: *mut u32,
    pub count_connectors: c_int,
    pub connectors: *mut u32,
    pub count_encoders: c_int,
    pub encoders: *mut u32,
    pub min_width: u32,
    pub max_width: u32,
    pub min_height: u32,
    pub max_height: u32,
}

/// DRM connector structure
#[repr(C)]
pub struct drmModeConnector {
    pub connector_id: u32,
    pub encoder_id: u32,
    pub connector_type: u32,
    pub connector_type_id: u32,
    pub connection: u32,
    pub mmWidth: u32,
    pub mmHeight: u32,
    pub subpixel: u32,
    pub count_modes: c_int,
    pub modes: *mut drmModeModeInfo,
    pub count_props: c_int,
    pub props: *mut u32,
    pub prop_values: *mut u64,
    pub count_encoders: c_int,
    pub encoders: *mut u32,
}

/// DRM CRTC structure
#[repr(C)]
pub struct drmModeCrtc {
    pub crtc_id: u32,
    pub buffer_id: u32,
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
    pub mode_valid: c_int,
    pub mode: drmModeModeInfo,
    pub gamma_size: c_int,
}

/// DRM plane structure
#[repr(C)]
pub struct drmModePlane {
    pub count_formats: u32,
    pub formats: *mut u32,
    pub plane_id: u32,
    pub crtc_id: u32,
    pub fb_id: u32,
    pub crtc_x: u32,
    pub crtc_y: u32,
    pub x: u32,
    pub y: u32,
    pub possible_crtcs: u32,
    pub gamma_size: u32,
}

/// DRM plane resources
#[repr(C)]
pub struct drmModePlaneRes {
    pub count_planes: u32,
    pub planes: *mut u32,
}

/// DRM framebuffer structure
#[repr(C)]
pub struct drmModeFB {
    pub fb_id: u32,
    pub width: u32,
    pub height: u32,
    pub pitch: u32,
    pub bpp: u32,
    pub depth: u32,
    pub handle: u32,
}

/// Connection status
pub const DRM_MODE_CONNECTED: u32 = 1;
pub const DRM_MODE_DISCONNECTED: u32 = 2;
pub const DRM_MODE_UNKNOWNCONNECTION: u32 = 3;

/// Connector types
pub const DRM_MODE_CONNECTOR_DSI: u32 = 16;
pub const DRM_MODE_CONNECTOR_VIRTUAL: u32 = 15;

/// Plane types (for properties)
pub const DRM_PLANE_TYPE_OVERLAY: u64 = 0;
pub const DRM_PLANE_TYPE_PRIMARY: u64 = 1;
pub const DRM_PLANE_TYPE_CURSOR: u64 = 2;

// =============================================================================
// DRM Device Functions
// =============================================================================

/// Get DRM resources
#[no_mangle]
pub unsafe extern "C" fn drmModeGetResources(fd: c_int) -> *mut drmModeRes {
    debug!("drmModeGetResources(fd={})", fd);

    // Try to initialize - this determines if we're the main process
    let init_result = drm_hwcomposer_shim_init();

    // If we're not the main shim process, return null
    if !is_main_shim_process() {
        debug!("drmModeGetResources: not main shim process, returning null");
        return ptr::null_mut();
    }

    if init_result != 0 {
        error!("Failed to initialize shim for drmModeGetResources");
        return ptr::null_mut();
    }

    // Get global DRM device
    let drm = {
        let global = GLOBAL_DRM.lock().unwrap();
        match global.clone() {
            Some(d) => d,
            None => {
                error!("GLOBAL_DRM not set");
                return ptr::null_mut();
            }
        }
    };

    let resources = drm.get_resources();

    // Allocate arrays
    let fbs = if resources.fbs.is_empty() {
        ptr::null_mut()
    } else {
        let fbs_arr = resources.fbs.clone().into_boxed_slice();
        Box::into_raw(fbs_arr) as *mut u32
    };

    let crtcs = Box::into_raw(vec![10u32].into_boxed_slice()) as *mut u32;
    let connectors = Box::into_raw(vec![1u32].into_boxed_slice()) as *mut u32;
    let encoders = Box::into_raw(vec![5u32].into_boxed_slice()) as *mut u32;

    let res = Box::new(drmModeRes {
        count_fbs: resources.fbs.len() as c_int,
        fbs,
        count_crtcs: 1,
        crtcs,
        count_connectors: 1,
        connectors,
        count_encoders: 1,
        encoders,
        min_width: resources.min_width,
        max_width: resources.max_width,
        min_height: resources.min_height,
        max_height: resources.max_height,
    });

    Box::into_raw(res)
}

/// Free DRM resources
#[no_mangle]
pub unsafe extern "C" fn drmModeFreeResources(res: *mut drmModeRes) {
    if res.is_null() {
        return;
    }

    let res_box = Box::from_raw(res);

    // Free arrays
    if !res_box.fbs.is_null() && res_box.count_fbs > 0 {
        let _ = Vec::from_raw_parts(res_box.fbs, res_box.count_fbs as usize, res_box.count_fbs as usize);
    }
    if !res_box.crtcs.is_null() && res_box.count_crtcs > 0 {
        let _ = Vec::from_raw_parts(res_box.crtcs, res_box.count_crtcs as usize, res_box.count_crtcs as usize);
    }
    if !res_box.connectors.is_null() && res_box.count_connectors > 0 {
        let _ = Vec::from_raw_parts(res_box.connectors, res_box.count_connectors as usize, res_box.count_connectors as usize);
    }
    if !res_box.encoders.is_null() && res_box.count_encoders > 0 {
        let _ = Vec::from_raw_parts(res_box.encoders, res_box.count_encoders as usize, res_box.count_encoders as usize);
    }
}

/// Get connector info
#[no_mangle]
pub unsafe extern "C" fn drmModeGetConnector(fd: c_int, connector_id: u32) -> *mut drmModeConnector {
    debug!("drmModeGetConnector(fd={}, id={})", fd, connector_id);

    let drm = match GLOBAL_DRM.lock().unwrap().clone() {
        Some(d) => d,
        None => return ptr::null_mut(),
    };

    let connector = drm.get_connector();
    let mode = drm.get_mode_info();

    // Create mode info
    let mut mode_info = drmModeModeInfo {
        clock: mode.clock,
        hdisplay: mode.hdisplay,
        hsync_start: mode.hsync_start,
        hsync_end: mode.hsync_end,
        htotal: mode.htotal,
        hskew: 0,
        vdisplay: mode.vdisplay,
        vsync_start: mode.vsync_start,
        vsync_end: mode.vsync_end,
        vtotal: mode.vtotal,
        vscan: 0,
        vrefresh: mode.vrefresh,
        flags: mode.flags,
        type_: 0,
        name: [0; 32],
    };

    // Copy mode name
    let name_bytes = mode.name.as_bytes();
    for (i, &b) in name_bytes.iter().take(31).enumerate() {
        mode_info.name[i] = b as c_char;
    }

    let modes = Box::into_raw(vec![mode_info].into_boxed_slice()) as *mut drmModeModeInfo;
    let encoders = Box::into_raw(vec![5u32].into_boxed_slice()) as *mut u32;

    let conn = Box::new(drmModeConnector {
        connector_id: connector.id,
        encoder_id: 5, // ENCODER_ID
        connector_type: DRM_MODE_CONNECTOR_DSI,
        connector_type_id: 1,
        connection: if connector.connected { DRM_MODE_CONNECTED } else { DRM_MODE_DISCONNECTED },
        mmWidth: connector.width_mm,
        mmHeight: connector.height_mm,
        subpixel: 0, // DRM_MODE_SUBPIXEL_UNKNOWN
        count_modes: 1,
        modes,
        count_props: 0,
        props: ptr::null_mut(),
        prop_values: ptr::null_mut(),
        count_encoders: 1,
        encoders,
    });

    Box::into_raw(conn)
}

/// Free connector
#[no_mangle]
pub unsafe extern "C" fn drmModeFreeConnector(connector: *mut drmModeConnector) {
    if connector.is_null() {
        return;
    }

    let conn = Box::from_raw(connector);

    if !conn.modes.is_null() && conn.count_modes > 0 {
        let _ = Vec::from_raw_parts(conn.modes, conn.count_modes as usize, conn.count_modes as usize);
    }
    if !conn.encoders.is_null() && conn.count_encoders > 0 {
        let _ = Vec::from_raw_parts(conn.encoders, conn.count_encoders as usize, conn.count_encoders as usize);
    }
}

/// Get CRTC info
#[no_mangle]
pub unsafe extern "C" fn drmModeGetCrtc(fd: c_int, crtc_id: u32) -> *mut drmModeCrtc {
    debug!("drmModeGetCrtc(fd={}, id={})", fd, crtc_id);

    let drm = match GLOBAL_DRM.lock().unwrap().clone() {
        Some(d) => d,
        None => return ptr::null_mut(),
    };

    let crtc = drm.get_crtc();
    let mode = drm.get_mode_info();

    let mut mode_info = drmModeModeInfo {
        clock: mode.clock,
        hdisplay: mode.hdisplay,
        hsync_start: mode.hsync_start,
        hsync_end: mode.hsync_end,
        htotal: mode.htotal,
        hskew: 0,
        vdisplay: mode.vdisplay,
        vsync_start: mode.vsync_start,
        vsync_end: mode.vsync_end,
        vtotal: mode.vtotal,
        vscan: 0,
        vrefresh: mode.vrefresh,
        flags: mode.flags,
        type_: 0,
        name: [0; 32],
    };

    let name_bytes = mode.name.as_bytes();
    for (i, &b) in name_bytes.iter().take(31).enumerate() {
        mode_info.name[i] = b as c_char;
    }

    let crtc_info = Box::new(drmModeCrtc {
        crtc_id: crtc.id,
        buffer_id: 0,
        x: crtc.x,
        y: crtc.y,
        width: crtc.width,
        height: crtc.height,
        mode_valid: if crtc.mode_valid { 1 } else { 0 },
        mode: mode_info,
        gamma_size: 256,
    });

    Box::into_raw(crtc_info)
}

/// Free CRTC
#[no_mangle]
pub unsafe extern "C" fn drmModeFreeCrtc(crtc: *mut drmModeCrtc) {
    if crtc.is_null() {
        return;
    }
    let _ = Box::from_raw(crtc);
}

/// Get plane resources
#[no_mangle]
pub unsafe extern "C" fn drmModeGetPlaneResources(fd: c_int) -> *mut drmModePlaneRes {
    debug!("drmModeGetPlaneResources(fd={})", fd);

    let drm = match GLOBAL_DRM.lock().unwrap().clone() {
        Some(d) => d,
        None => return ptr::null_mut(),
    };

    let planes = drm.get_plane_resources();
    let planes_arr = planes.into_boxed_slice();
    let count = planes_arr.len() as u32;
    let planes_ptr = Box::into_raw(planes_arr) as *mut u32;

    let res = Box::new(drmModePlaneRes {
        count_planes: count,
        planes: planes_ptr,
    });

    Box::into_raw(res)
}

/// Free plane resources
#[no_mangle]
pub unsafe extern "C" fn drmModeFreePlaneResources(res: *mut drmModePlaneRes) {
    if res.is_null() {
        return;
    }

    let res_box = Box::from_raw(res);
    if !res_box.planes.is_null() && res_box.count_planes > 0 {
        let _ = Vec::from_raw_parts(res_box.planes, res_box.count_planes as usize, res_box.count_planes as usize);
    }
}

/// Get plane info
#[no_mangle]
pub unsafe extern "C" fn drmModeGetPlane(fd: c_int, plane_id: u32) -> *mut drmModePlane {
    debug!("drmModeGetPlane(fd={}, id={})", fd, plane_id);

    let drm = match GLOBAL_DRM.lock().unwrap().clone() {
        Some(d) => d,
        None => return ptr::null_mut(),
    };

    let plane = match drm.get_plane(plane_id) {
        Some(p) => p,
        None => return ptr::null_mut(),
    };

    let formats_arr = plane.formats.into_boxed_slice();
    let count = formats_arr.len() as u32;
    let formats_ptr = Box::into_raw(formats_arr) as *mut u32;

    let plane_info = Box::new(drmModePlane {
        count_formats: count,
        formats: formats_ptr,
        plane_id: plane.id,
        crtc_id: plane.crtc_id,
        fb_id: plane.fb_id,
        crtc_x: plane.crtc_x as u32,
        crtc_y: plane.crtc_y as u32,
        x: plane.src_x,
        y: plane.src_y,
        possible_crtcs: plane.possible_crtcs,
        gamma_size: 0,
    });

    Box::into_raw(plane_info)
}

/// Free plane
#[no_mangle]
pub unsafe extern "C" fn drmModeFreePlane(plane: *mut drmModePlane) {
    if plane.is_null() {
        return;
    }

    let plane_box = Box::from_raw(plane);
    if !plane_box.formats.is_null() && plane_box.count_formats > 0 {
        let _ = Vec::from_raw_parts(plane_box.formats, plane_box.count_formats as usize, plane_box.count_formats as usize);
    }
}

/// Add a framebuffer
#[no_mangle]
pub unsafe extern "C" fn drmModeAddFB(
    fd: c_int,
    width: u32,
    height: u32,
    depth: u8,
    bpp: u8,
    pitch: u32,
    bo_handle: u32,
    buf_id: *mut u32,
) -> c_int {
    debug!("drmModeAddFB({}x{}, depth={}, bpp={}, pitch={})", width, height, depth, bpp, pitch);

    let drm = match GLOBAL_DRM.lock().unwrap().clone() {
        Some(d) => d,
        None => return -1,
    };

    // Determine format from bpp/depth
    let format = match (bpp, depth) {
        (32, 24) => drm_fourcc::DRM_FORMAT_XRGB8888,
        (32, 32) => drm_fourcc::DRM_FORMAT_ARGB8888,
        (16, 16) => drm_fourcc::DRM_FORMAT_RGB565,
        _ => drm_fourcc::DRM_FORMAT_XRGB8888,
    };

    match drm.add_framebuffer(width, height, pitch, bpp as u32, depth as u32, format, bo_handle) {
        Ok(fb_id) => {
            if !buf_id.is_null() {
                *buf_id = fb_id;
            }
            0
        }
        Err(e) => {
            error!("drmModeAddFB failed: {}", e);
            -1
        }
    }
}

/// Add a framebuffer with format
#[no_mangle]
pub unsafe extern "C" fn drmModeAddFB2(
    fd: c_int,
    width: u32,
    height: u32,
    pixel_format: u32,
    bo_handles: *const u32,
    pitches: *const u32,
    offsets: *const u32,
    buf_id: *mut u32,
    flags: u32,
) -> c_int {
    debug!("drmModeAddFB2({}x{}, format=0x{:08x})", width, height, pixel_format);

    let drm = match GLOBAL_DRM.lock().unwrap().clone() {
        Some(d) => d,
        None => return -1,
    };

    let handle = if bo_handles.is_null() { 0 } else { *bo_handles };
    let pitch = if pitches.is_null() { width * 4 } else { *pitches };
    let bpp = match pixel_format {
        drm_fourcc::DRM_FORMAT_RGB565 => 16,
        _ => 32,
    };
    let depth = match pixel_format {
        drm_fourcc::DRM_FORMAT_XRGB8888 | drm_fourcc::DRM_FORMAT_XBGR8888 => 24,
        _ => 32,
    };

    match drm.add_framebuffer(width, height, pitch, bpp, depth, pixel_format, handle) {
        Ok(fb_id) => {
            if !buf_id.is_null() {
                *buf_id = fb_id;
            }
            0
        }
        Err(e) => {
            error!("drmModeAddFB2 failed: {}", e);
            -1
        }
    }
}

/// Remove a framebuffer
#[no_mangle]
pub unsafe extern "C" fn drmModeRmFB(fd: c_int, fb_id: u32) -> c_int {
    debug!("drmModeRmFB(fb={})", fb_id);

    let drm = match GLOBAL_DRM.lock().unwrap().clone() {
        Some(d) => d,
        None => return -1,
    };

    match drm.remove_framebuffer(fb_id) {
        Ok(()) => 0,
        Err(e) => {
            error!("drmModeRmFB failed: {}", e);
            -1
        }
    }
}

/// Get framebuffer info
#[no_mangle]
pub unsafe extern "C" fn drmModeGetFB(fd: c_int, fb_id: u32) -> *mut drmModeFB {
    debug!("drmModeGetFB(fb={})", fb_id);

    let drm = match GLOBAL_DRM.lock().unwrap().clone() {
        Some(d) => d,
        None => return ptr::null_mut(),
    };

    match drm.get_framebuffer(fb_id) {
        Some(fb) => {
            let fb_info = Box::new(drmModeFB {
                fb_id: fb.id,
                width: fb.width,
                height: fb.height,
                pitch: fb.pitch,
                bpp: fb.bpp,
                depth: fb.depth,
                handle: fb.handle,
            });
            Box::into_raw(fb_info)
        }
        None => ptr::null_mut(),
    }
}

/// Free framebuffer info
#[no_mangle]
pub unsafe extern "C" fn drmModeFreeFB(fb: *mut drmModeFB) {
    if fb.is_null() {
        return;
    }
    let _ = Box::from_raw(fb);
}

/// Set plane
#[no_mangle]
pub unsafe extern "C" fn drmModeSetPlane(
    fd: c_int,
    plane_id: u32,
    crtc_id: u32,
    fb_id: u32,
    flags: u32,
    crtc_x: i32,
    crtc_y: i32,
    crtc_w: u32,
    crtc_h: u32,
    src_x: u32,
    src_y: u32,
    src_w: u32,
    src_h: u32,
) -> c_int {
    debug!("drmModeSetPlane(plane={}, crtc={}, fb={})", plane_id, crtc_id, fb_id);

    let drm = match GLOBAL_DRM.lock().unwrap().clone() {
        Some(d) => d,
        None => return -1,
    };

    match drm.set_plane(plane_id, crtc_id, fb_id, crtc_x, crtc_y, crtc_w, crtc_h) {
        Ok(()) => 0,
        Err(e) => {
            error!("drmModeSetPlane failed: {}", e);
            -1
        }
    }
}

/// Page flip
#[no_mangle]
pub unsafe extern "C" fn drmModePageFlip(
    fd: c_int,
    crtc_id: u32,
    fb_id: u32,
    flags: u32,
    user_data: *mut c_void,
) -> c_int {
    debug!("drmModePageFlip(crtc={}, fb={})", crtc_id, fb_id);

    let drm = match GLOBAL_DRM.lock().unwrap().clone() {
        Some(d) => d,
        None => return -1,
    };

    match drm.page_flip(crtc_id, fb_id) {
        Ok(()) => 0,
        Err(e) => {
            error!("drmModePageFlip failed: {}", e);
            -1
        }
    }
}

/// Set CRTC mode
#[no_mangle]
pub unsafe extern "C" fn drmModeSetCrtc(
    fd: c_int,
    crtc_id: u32,
    fb_id: u32,
    x: u32,
    y: u32,
    connectors: *const u32,
    count: c_int,
    mode: *mut drmModeModeInfo,
) -> c_int {
    debug!("drmModeSetCrtc(crtc={}, fb={})", crtc_id, fb_id);
    // In our shim, the mode is fixed by hwcomposer
    0
}

/// Set client capability
#[no_mangle]
pub unsafe extern "C" fn drmSetClientCap(fd: c_int, capability: u64, value: u64) -> c_int {
    debug!("drmSetClientCap(cap={}, value={})", capability, value);
    // Accept all capabilities
    0
}

/// Get device capability
#[no_mangle]
pub unsafe extern "C" fn drmGetCap(fd: c_int, capability: u64, value: *mut u64) -> c_int {
    debug!("drmGetCap(cap={})", capability);

    if value.is_null() {
        return -1;
    }

    // Common capabilities
    const DRM_CAP_DUMB_BUFFER: u64 = 0x1;
    const DRM_CAP_PRIME: u64 = 0x5;
    const DRM_CAP_TIMESTAMP_MONOTONIC: u64 = 0x6;

    match capability {
        DRM_CAP_DUMB_BUFFER => *value = 1,
        DRM_CAP_PRIME => *value = 3, // IMPORT | EXPORT
        DRM_CAP_TIMESTAMP_MONOTONIC => *value = 1,
        _ => *value = 0,
    }

    0
}

/// Check DRM version
#[no_mangle]
pub unsafe extern "C" fn drmGetVersion(fd: c_int) -> *mut DrmVersion {
    let version = Box::new(DrmVersion {
        version_major: 1,
        version_minor: 0,
        version_patchlevel: 0,
        name_len: 11,
        name: b"hwcomposer\0".as_ptr() as *mut c_char,
        date_len: 10,
        date: b"2024-01-01".as_ptr() as *mut c_char,
        desc_len: 35,
        desc: b"DRM shim over Android hwcomposer\0".as_ptr() as *mut c_char,
    });
    Box::into_raw(version)
}

#[repr(C)]
pub struct DrmVersion {
    pub version_major: c_int,
    pub version_minor: c_int,
    pub version_patchlevel: c_int,
    pub name_len: c_int,
    pub name: *mut c_char,
    pub date_len: c_int,
    pub date: *mut c_char,
    pub desc_len: c_int,
    pub desc: *mut c_char,
}

#[no_mangle]
pub unsafe extern "C" fn drmFreeVersion(version: *mut DrmVersion) {
    if version.is_null() {
        return;
    }
    let _ = Box::from_raw(version);
}

// =============================================================================
// DRM Device Open/Close Functions
// =============================================================================

/// Real file descriptor used as our DRM "device"
/// We use memfd_create to get a real fd that can be dup'd
static SHIM_DRM_FD: Mutex<Option<c_int>> = Mutex::new(None);

/// Get or create the shim DRM fd
fn get_or_create_shim_fd() -> c_int {
    let mut fd_guard = SHIM_DRM_FD.lock().unwrap();
    if let Some(fd) = *fd_guard {
        return fd;
    }

    // Create a real fd using memfd_create (anonymous file in memory)
    let fd = unsafe {
        libc::memfd_create(
            b"drm-hwcomposer-shim\0".as_ptr() as *const c_char,
            0, // No special flags
        )
    };

    if fd >= 0 {
        info!("Created shim DRM fd: {}", fd);
        *fd_guard = Some(fd);
        fd
    } else {
        // Fallback: open /dev/null
        let fd = unsafe {
            libc::open(b"/dev/null\0".as_ptr() as *const c_char, libc::O_RDWR)
        };
        if fd >= 0 {
            info!("Created shim DRM fd from /dev/null: {}", fd);
            *fd_guard = Some(fd);
            fd
        } else {
            error!("Failed to create shim DRM fd");
            -1
        }
    }
}

/// Check if an fd is our shim fd
fn is_shim_fd(fd: c_int) -> bool {
    if fd < 0 {
        return false;
    }
    if let Ok(guard) = SHIM_DRM_FD.lock() {
        if let Some(shim_fd) = *guard {
            return fd == shim_fd;
        }
    }
    false
}

/// Open a DRM device by name
#[no_mangle]
pub unsafe extern "C" fn drmOpen(name: *const c_char, busid: *const c_char) -> c_int {
    let name_str = if name.is_null() {
        "null"
    } else {
        CStr::from_ptr(name).to_str().unwrap_or("invalid")
    };
    info!("drmOpen(name={}, busid=...)", name_str);

    // Initialize shim and return real fd
    if drm_hwcomposer_shim_init() == 0 {
        get_or_create_shim_fd()
    } else {
        -1
    }
}

/// Open a DRM device with type
#[no_mangle]
pub unsafe extern "C" fn drmOpenWithType(
    name: *const c_char,
    busid: *const c_char,
    type_: c_int,
) -> c_int {
    drmOpen(name, busid)
}

/// Open the DRM control device
#[no_mangle]
pub unsafe extern "C" fn drmOpenControl(minor: c_int) -> c_int {
    info!("drmOpenControl(minor={})", minor);
    if drm_hwcomposer_shim_init() == 0 {
        get_or_create_shim_fd()
    } else {
        -1
    }
}

/// Open a DRM render node
#[no_mangle]
pub unsafe extern "C" fn drmOpenRender(minor: c_int) -> c_int {
    info!("drmOpenRender(minor={})", minor);
    if drm_hwcomposer_shim_init() == 0 {
        get_or_create_shim_fd()
    } else {
        -1
    }
}

/// Close a DRM device
#[no_mangle]
pub unsafe extern "C" fn drmClose(fd: c_int) -> c_int {
    debug!("drmClose(fd={})", fd);
    // Don't actually close anything - our device is managed internally
    0
}

/// Check if fd is a DRM device (ours is always valid)
#[no_mangle]
pub unsafe extern "C" fn drmAvailable() -> c_int {
    debug!("drmAvailable()");
    1
}

/// Get the bus ID
#[no_mangle]
pub unsafe extern "C" fn drmGetBusid(fd: c_int) -> *mut c_char {
    static BUSID: &[u8] = b"hwcomposer:0\0";
    // Return a static string - caller should use drmFreeBusid
    BUSID.as_ptr() as *mut c_char
}

/// Free bus ID (no-op for our static string)
#[no_mangle]
pub unsafe extern "C" fn drmFreeBusid(busid: *const c_char) {
    // No-op - we return a static string
}

/// Get magic token for authentication
#[no_mangle]
pub unsafe extern "C" fn drmGetMagic(fd: c_int, magic: *mut u32) -> c_int {
    if !magic.is_null() {
        *magic = 0x12345678;
    }
    0
}

/// Authenticate with magic token
#[no_mangle]
pub unsafe extern "C" fn drmAuthMagic(fd: c_int, magic: u32) -> c_int {
    0 // Always succeed
}

/// Get device node name
#[no_mangle]
pub unsafe extern "C" fn drmGetDeviceNameFromFd(fd: c_int) -> *mut c_char {
    static NAME: &[u8] = b"/dev/dri/card0\0";
    NAME.as_ptr() as *mut c_char
}

/// Get device node name (version 2)
#[no_mangle]
pub unsafe extern "C" fn drmGetDeviceNameFromFd2(fd: c_int) -> *mut c_char {
    drmGetDeviceNameFromFd(fd)
}

/// Get render device node name
#[no_mangle]
pub unsafe extern "C" fn drmGetRenderDeviceNameFromFd(fd: c_int) -> *mut c_char {
    static NAME: &[u8] = b"/dev/dri/renderD128\0";
    NAME.as_ptr() as *mut c_char
}

/// Drop master
#[no_mangle]
pub unsafe extern "C" fn drmDropMaster(fd: c_int) -> c_int {
    debug!("drmDropMaster(fd={})", fd);
    0
}

/// Set master
#[no_mangle]
pub unsafe extern "C" fn drmSetMaster(fd: c_int) -> c_int {
    debug!("drmSetMaster(fd={})", fd);
    0
}

/// Check if we're the master
#[no_mangle]
pub unsafe extern "C" fn drmIsMaster(fd: c_int) -> c_int {
    1 // Always master
}

// =============================================================================
// DRM ioctl definitions and interceptor
// =============================================================================

// DRM ioctl command numbers (from drm.h and drm_mode.h)
const DRM_IOCTL_BASE: libc::c_ulong = 0x64; // 'd'

// Helper to build DRM ioctl numbers
const fn drm_iowr(nr: libc::c_ulong, size: libc::c_ulong) -> libc::c_ulong {
    // _IOWR('d', nr, size) = _IOC(_IOC_READ|_IOC_WRITE, 'd', nr, size)
    // On Linux: (3 << 30) | ('d' << 8) | nr | (size << 16)
    (3 << 30) | (DRM_IOCTL_BASE << 8) | nr | (size << 16)
}

const fn drm_ior(nr: libc::c_ulong, size: libc::c_ulong) -> libc::c_ulong {
    // _IOR('d', nr, size) = _IOC(_IOC_READ, 'd', nr, size)
    (2 << 30) | (DRM_IOCTL_BASE << 8) | nr | (size << 16)
}

const fn drm_iow(nr: libc::c_ulong, size: libc::c_ulong) -> libc::c_ulong {
    // _IOW('d', nr, size) = _IOC(_IOC_WRITE, 'd', nr, size)
    (1 << 30) | (DRM_IOCTL_BASE << 8) | nr | (size << 16)
}

const fn drm_io(nr: libc::c_ulong) -> libc::c_ulong {
    // _IO('d', nr) = _IOC(_IOC_NONE, 'd', nr, 0)
    (DRM_IOCTL_BASE << 8) | nr
}

// DRM ioctl numbers
const DRM_IOCTL_VERSION: libc::c_ulong = drm_iowr(0x00, 36); // struct drm_version
const DRM_IOCTL_GET_CAP: libc::c_ulong = drm_iowr(0x0c, 16);
const DRM_IOCTL_SET_CLIENT_CAP: libc::c_ulong = drm_iow(0x0d, 16);
const DRM_IOCTL_SET_MASTER: libc::c_ulong = drm_io(0x1e);
const DRM_IOCTL_DROP_MASTER: libc::c_ulong = drm_io(0x1f);

// Mode setting ioctls (0xA0+)
const DRM_IOCTL_MODE_GETRESOURCES: libc::c_ulong = drm_iowr(0xa0, 64);
const DRM_IOCTL_MODE_GETCRTC: libc::c_ulong = drm_iowr(0xa1, 80);
const DRM_IOCTL_MODE_SETCRTC: libc::c_ulong = drm_iowr(0xa2, 80);
const DRM_IOCTL_MODE_CURSOR: libc::c_ulong = drm_iowr(0xa3, 24);
const DRM_IOCTL_MODE_GETGAMMA: libc::c_ulong = drm_iowr(0xa4, 32);
const DRM_IOCTL_MODE_SETGAMMA: libc::c_ulong = drm_iowr(0xa5, 32);
const DRM_IOCTL_MODE_GETENCODER: libc::c_ulong = drm_iowr(0xa6, 20);
const DRM_IOCTL_MODE_GETCONNECTOR: libc::c_ulong = drm_iowr(0xa7, 80);
const DRM_IOCTL_MODE_ADDFB: libc::c_ulong = drm_iowr(0xae, 28);
const DRM_IOCTL_MODE_RMFB: libc::c_ulong = drm_iowr(0xaf, 4);
const DRM_IOCTL_MODE_PAGE_FLIP: libc::c_ulong = drm_iowr(0xb0, 20);
const DRM_IOCTL_MODE_ADDFB2: libc::c_ulong = drm_iowr(0xb8, 72);
const DRM_IOCTL_MODE_OBJ_GETPROPERTIES: libc::c_ulong = drm_iowr(0xb9, 24);
const DRM_IOCTL_MODE_OBJ_SETPROPERTY: libc::c_ulong = drm_iowr(0xba, 16);
const DRM_IOCTL_MODE_CURSOR2: libc::c_ulong = drm_iowr(0xbb, 32);
const DRM_IOCTL_MODE_ATOMIC: libc::c_ulong = drm_iowr(0xbc, 56);
const DRM_IOCTL_MODE_GETPLANE: libc::c_ulong = drm_iowr(0xb6, 40);
const DRM_IOCTL_MODE_GETPLANERESOURCES: libc::c_ulong = drm_iowr(0xb5, 16);

// drm_version struct (for DRM_IOCTL_VERSION)
#[repr(C)]
struct DrmVersionIoctl {
    version_major: c_int,
    version_minor: c_int,
    version_patchlevel: c_int,
    name_len: libc::size_t,
    name: *mut c_char,
    date_len: libc::size_t,
    date: *mut c_char,
    desc_len: libc::size_t,
    desc: *mut c_char,
}

// drm_get_cap struct
#[repr(C)]
struct DrmGetCap {
    capability: u64,
    value: u64,
}

// drm_set_client_cap struct
#[repr(C)]
struct DrmSetClientCap {
    capability: u64,
    value: u64,
}

// drm_mode_card_res struct (for DRM_IOCTL_MODE_GETRESOURCES)
#[repr(C)]
struct DrmModeCardRes {
    fb_id_ptr: u64,
    crtc_id_ptr: u64,
    connector_id_ptr: u64,
    encoder_id_ptr: u64,
    count_fbs: u32,
    count_crtcs: u32,
    count_connectors: u32,
    count_encoders: u32,
    min_width: u32,
    max_width: u32,
    min_height: u32,
    max_height: u32,
}

// drm_mode_get_connector struct
#[repr(C)]
struct DrmModeGetConnector {
    encoders_ptr: u64,
    modes_ptr: u64,
    props_ptr: u64,
    prop_values_ptr: u64,
    count_modes: u32,
    count_props: u32,
    count_encoders: u32,
    encoder_id: u32,
    connector_id: u32,
    connector_type: u32,
    connector_type_id: u32,
    connection: u32,
    mm_width: u32,
    mm_height: u32,
    subpixel: u32,
    pad: u32,
}

// drm_mode_crtc struct
#[repr(C)]
struct DrmModeCrtc {
    set_connectors_ptr: u64,
    count_connectors: u32,
    crtc_id: u32,
    fb_id: u32,
    x: u32,
    y: u32,
    gamma_size: u32,
    mode_valid: u32,
    mode: DrmModeModeinfo,
}

// drm_mode_modeinfo struct
#[repr(C)]
#[derive(Clone, Copy, Default)]
struct DrmModeModeinfo {
    clock: u32,
    hdisplay: u16,
    hsync_start: u16,
    hsync_end: u16,
    htotal: u16,
    hskew: u16,
    vdisplay: u16,
    vsync_start: u16,
    vsync_end: u16,
    vtotal: u16,
    vscan: u16,
    vrefresh: u32,
    flags: u32,
    type_: u32,
    name: [c_char; 32],
}

// drm_mode_get_encoder struct
#[repr(C)]
struct DrmModeGetEncoder {
    encoder_id: u32,
    encoder_type: u32,
    crtc_id: u32,
    possible_crtcs: u32,
    possible_clones: u32,
}

// drm_mode_get_plane_res struct
#[repr(C)]
struct DrmModeGetPlaneRes {
    plane_id_ptr: u64,
    count_planes: u32,
}

// drm_mode_get_plane struct
#[repr(C)]
struct DrmModeGetPlane {
    plane_id: u32,
    crtc_id: u32,
    fb_id: u32,
    possible_crtcs: u32,
    gamma_size: u32,
    count_format_types: u32,
    format_type_ptr: u64,
}

// drm_mode_fb_cmd2 struct (for ADDFB2)
#[repr(C)]
struct DrmModeFbCmd2 {
    fb_id: u32,
    width: u32,
    height: u32,
    pixel_format: u32,
    flags: u32,
    handles: [u32; 4],
    pitches: [u32; 4],
    offsets: [u32; 4],
    modifier: [u64; 4],
}

// drm_mode_obj_get_properties struct
#[repr(C)]
struct DrmModeObjGetProperties {
    props_ptr: u64,
    prop_values_ptr: u64,
    count_props: u32,
    obj_id: u32,
    obj_type: u32,
}

// drm_mode_atomic struct
#[repr(C)]
struct DrmModeAtomic {
    flags: u32,
    count_objs: u32,
    objs_ptr: u64,
    count_props_ptr: u64,
    props_ptr: u64,
    prop_values_ptr: u64,
    reserved: u64,
    user_data: u64,
}

/// Handle DRM ioctls - wraps libdrm's drmIoctl
#[no_mangle]
pub unsafe extern "C" fn drmIoctl(fd: c_int, request: libc::c_ulong, arg: *mut c_void) -> c_int {
    // Log but delegate to our ioctl handler
    debug!("drmIoctl(fd={}, request=0x{:x})", fd, request);
    handle_drm_ioctl(fd, request, arg)
}

/// Check if an ioctl request is a DRM ioctl (magic 'd' = 0x64)
fn is_drm_ioctl(request: libc::c_ulong) -> bool {
    // DRM ioctls have magic number 'd' (0x64) in bits 8-15
    let magic = (request >> 8) & 0xFF;
    magic == DRM_IOCTL_BASE
}

/// Initialize real libc function pointers using RTLD_NEXT
unsafe fn init_real_funcs() {
    INIT_REAL_FUNCS.call_once(|| {
        // Get the real ioctl from libc using RTLD_NEXT
        let ioctl_ptr = libc::dlsym(RTLD_NEXT, b"ioctl\0".as_ptr() as *const c_char);
        if !ioctl_ptr.is_null() {
            REAL_IOCTL = Some(std::mem::transmute(ioctl_ptr));
        }

        // Get the real open from libc
        let open_ptr = libc::dlsym(RTLD_NEXT, b"open\0".as_ptr() as *const c_char);
        if !open_ptr.is_null() {
            REAL_OPEN_FN = Some(std::mem::transmute(open_ptr));
        }

        info!("drm-hwcomposer-shim: Real function pointers initialized (ioctl={}, open={})",
              !ioctl_ptr.is_null(), !open_ptr.is_null());
    });
}

/// Intercept ioctl() syscall for DRM operations
#[no_mangle]
pub unsafe extern "C" fn ioctl(fd: c_int, request: libc::c_ulong, arg: *mut c_void) -> c_int {
    // Initialize real function pointers on first call
    init_real_funcs();

    // Check if this is a DRM ioctl - intercept ALL DRM ioctls regardless of fd
    // This is critical because compositors may open the real /dev/dri/card0
    // but we want to handle all DRM operations through hwcomposer
    if is_drm_ioctl(request) {
        debug!("ioctl: intercepted DRM ioctl 0x{:x} on fd {}", request, fd);
        // Initialize our shim if not already done
        let _ = drm_hwcomposer_shim_init();
        return handle_drm_ioctl(fd, request, arg);
    }

    // For non-DRM ioctls, call the real ioctl
    if let Some(real_ioctl) = REAL_IOCTL {
        real_ioctl(fd, request, arg)
    } else {
        error!("Real ioctl function not available!");
        *libc::__errno_location() = libc::ENOSYS;
        -1
    }
}

/// Handle DRM-specific ioctls
unsafe fn handle_drm_ioctl(fd: c_int, request: libc::c_ulong, arg: *mut c_void) -> c_int {
    // Extract the ioctl number for matching (mask out size/direction bits for easier matching)
    let nr = (request >> 8) & 0xFF;

    match request {
        DRM_IOCTL_VERSION => {
            debug!("ioctl: DRM_IOCTL_VERSION");
            let ver = arg as *mut DrmVersionIoctl;
            if !ver.is_null() {
                (*ver).version_major = 1;
                (*ver).version_minor = 0;
                (*ver).version_patchlevel = 0;

                // Copy name if buffer provided
                if !(*ver).name.is_null() && (*ver).name_len > 0 {
                    let name = b"hwcomposer\0";
                    let copy_len = std::cmp::min((*ver).name_len, name.len());
                    std::ptr::copy_nonoverlapping(name.as_ptr(), (*ver).name as *mut u8, copy_len);
                }
                (*ver).name_len = 10;

                if !(*ver).date.is_null() && (*ver).date_len > 0 {
                    let date = b"20250101\0";
                    let copy_len = std::cmp::min((*ver).date_len, date.len());
                    std::ptr::copy_nonoverlapping(date.as_ptr(), (*ver).date as *mut u8, copy_len);
                }
                (*ver).date_len = 8;

                if !(*ver).desc.is_null() && (*ver).desc_len > 0 {
                    let desc = b"DRM shim over hwcomposer\0";
                    let copy_len = std::cmp::min((*ver).desc_len, desc.len());
                    std::ptr::copy_nonoverlapping(desc.as_ptr(), (*ver).desc as *mut u8, copy_len);
                }
                (*ver).desc_len = 24;
            }
            0
        }

        DRM_IOCTL_GET_CAP => {
            let cap = arg as *mut DrmGetCap;
            if !cap.is_null() {
                debug!("ioctl: DRM_IOCTL_GET_CAP capability={}", (*cap).capability);
                // Common capabilities
                const DRM_CAP_DUMB_BUFFER: u64 = 0x1;
                const DRM_CAP_VBLANK_HIGH_CRTC: u64 = 0x2;
                const DRM_CAP_DUMB_PREFERRED_DEPTH: u64 = 0x3;
                const DRM_CAP_DUMB_PREFER_SHADOW: u64 = 0x4;
                const DRM_CAP_PRIME: u64 = 0x5;
                const DRM_CAP_TIMESTAMP_MONOTONIC: u64 = 0x6;
                const DRM_CAP_ASYNC_PAGE_FLIP: u64 = 0x7;
                const DRM_CAP_CURSOR_WIDTH: u64 = 0x8;
                const DRM_CAP_CURSOR_HEIGHT: u64 = 0x9;
                const DRM_CAP_ADDFB2_MODIFIERS: u64 = 0x10;
                const DRM_CAP_CRTC_IN_VBLANK_EVENT: u64 = 0x12;

                (*cap).value = match (*cap).capability {
                    DRM_CAP_DUMB_BUFFER => 1,
                    DRM_CAP_VBLANK_HIGH_CRTC => 1,
                    DRM_CAP_DUMB_PREFERRED_DEPTH => 24,
                    DRM_CAP_DUMB_PREFER_SHADOW => 0,
                    DRM_CAP_PRIME => 3, // IMPORT | EXPORT
                    DRM_CAP_TIMESTAMP_MONOTONIC => 1,
                    DRM_CAP_ASYNC_PAGE_FLIP => 0, // Don't support async flip
                    DRM_CAP_CURSOR_WIDTH => 64,
                    DRM_CAP_CURSOR_HEIGHT => 64,
                    DRM_CAP_ADDFB2_MODIFIERS => 0, // No modifier support
                    DRM_CAP_CRTC_IN_VBLANK_EVENT => 1,
                    _ => 0,
                };
            }
            0
        }

        DRM_IOCTL_SET_CLIENT_CAP => {
            let cap = arg as *mut DrmSetClientCap;
            if !cap.is_null() {
                debug!("ioctl: DRM_IOCTL_SET_CLIENT_CAP capability={} value={}",
                       (*cap).capability, (*cap).value);
                // Accept all client capabilities
                // DRM_CLIENT_CAP_STEREO_3D = 1
                // DRM_CLIENT_CAP_UNIVERSAL_PLANES = 2
                // DRM_CLIENT_CAP_ATOMIC = 3
                // DRM_CLIENT_CAP_ASPECT_RATIO = 4
                // DRM_CLIENT_CAP_WRITEBACK_CONNECTORS = 5
            }
            0
        }

        DRM_IOCTL_SET_MASTER => {
            debug!("ioctl: DRM_IOCTL_SET_MASTER");
            0 // Always succeed - we don't need real DRM master
        }

        DRM_IOCTL_DROP_MASTER => {
            debug!("ioctl: DRM_IOCTL_DROP_MASTER");
            0
        }

        DRM_IOCTL_MODE_GETRESOURCES => {
            debug!("ioctl: DRM_IOCTL_MODE_GETRESOURCES");
            let res = arg as *mut DrmModeCardRes;
            if !res.is_null() {
                let drm = match GLOBAL_DRM.lock().unwrap().clone() {
                    Some(d) => d,
                    None => return -1,
                };

                let resources = drm.get_resources();

                // First call: return counts
                // Second call: fill arrays
                if (*res).count_crtcs == 0 && (*res).count_connectors == 0 {
                    // First call - return counts
                    (*res).count_fbs = resources.fbs.len() as u32;
                    (*res).count_crtcs = 1;
                    (*res).count_connectors = 1;
                    (*res).count_encoders = 1;
                } else {
                    // Second call - fill arrays if provided
                    if (*res).crtc_id_ptr != 0 && (*res).count_crtcs >= 1 {
                        let crtcs = (*res).crtc_id_ptr as *mut u32;
                        *crtcs = 10; // CRTC_ID
                    }
                    if (*res).connector_id_ptr != 0 && (*res).count_connectors >= 1 {
                        let connectors = (*res).connector_id_ptr as *mut u32;
                        *connectors = 1; // CONNECTOR_ID
                    }
                    if (*res).encoder_id_ptr != 0 && (*res).count_encoders >= 1 {
                        let encoders = (*res).encoder_id_ptr as *mut u32;
                        *encoders = 5; // ENCODER_ID
                    }
                }

                (*res).min_width = resources.min_width;
                (*res).max_width = resources.max_width;
                (*res).min_height = resources.min_height;
                (*res).max_height = resources.max_height;
            }
            0
        }

        DRM_IOCTL_MODE_GETCONNECTOR => {
            debug!("ioctl: DRM_IOCTL_MODE_GETCONNECTOR");
            let conn = arg as *mut DrmModeGetConnector;
            if !conn.is_null() {
                let drm = match GLOBAL_DRM.lock().unwrap().clone() {
                    Some(d) => d,
                    None => return -1,
                };

                let connector = drm.get_connector();
                let mode_info = drm.get_mode_info();

                (*conn).connector_id = connector.id;
                (*conn).connector_type = DRM_MODE_CONNECTOR_DSI;
                (*conn).connector_type_id = 1;
                (*conn).connection = if connector.connected { DRM_MODE_CONNECTED } else { DRM_MODE_DISCONNECTED };
                (*conn).mm_width = connector.width_mm;
                (*conn).mm_height = connector.height_mm;
                (*conn).encoder_id = 5; // ENCODER_ID
                (*conn).subpixel = 0;

                // First call returns counts, second fills arrays
                if (*conn).count_modes == 0 {
                    (*conn).count_modes = 1;
                    (*conn).count_encoders = 1;
                    (*conn).count_props = 0;
                } else {
                    // Fill mode info
                    if (*conn).modes_ptr != 0 && (*conn).count_modes >= 1 {
                        let modes = (*conn).modes_ptr as *mut DrmModeModeinfo;
                        let mut m = DrmModeModeinfo::default();
                        m.clock = mode_info.clock;
                        m.hdisplay = mode_info.hdisplay;
                        m.hsync_start = mode_info.hsync_start;
                        m.hsync_end = mode_info.hsync_end;
                        m.htotal = mode_info.htotal;
                        m.vdisplay = mode_info.vdisplay;
                        m.vsync_start = mode_info.vsync_start;
                        m.vsync_end = mode_info.vsync_end;
                        m.vtotal = mode_info.vtotal;
                        m.vrefresh = mode_info.vrefresh;
                        m.flags = mode_info.flags;

                        // Copy mode name
                        let name_bytes = mode_info.name.as_bytes();
                        for (i, &b) in name_bytes.iter().take(31).enumerate() {
                            m.name[i] = b as c_char;
                        }

                        *modes = m;
                    }

                    // Fill encoder
                    if (*conn).encoders_ptr != 0 && (*conn).count_encoders >= 1 {
                        let encoders = (*conn).encoders_ptr as *mut u32;
                        *encoders = 5; // ENCODER_ID
                    }
                }
            }
            0
        }

        DRM_IOCTL_MODE_GETCRTC => {
            debug!("ioctl: DRM_IOCTL_MODE_GETCRTC");
            let crtc = arg as *mut DrmModeCrtc;
            if !crtc.is_null() {
                let drm = match GLOBAL_DRM.lock().unwrap().clone() {
                    Some(d) => d,
                    None => return -1,
                };

                let crtc_info = drm.get_crtc();
                let mode_info = drm.get_mode_info();

                (*crtc).crtc_id = crtc_info.id;
                (*crtc).fb_id = 0;
                (*crtc).x = crtc_info.x;
                (*crtc).y = crtc_info.y;
                (*crtc).gamma_size = 256;
                (*crtc).mode_valid = if crtc_info.mode_valid { 1 } else { 0 };

                // Fill mode
                (*crtc).mode.clock = mode_info.clock;
                (*crtc).mode.hdisplay = mode_info.hdisplay;
                (*crtc).mode.hsync_start = mode_info.hsync_start;
                (*crtc).mode.hsync_end = mode_info.hsync_end;
                (*crtc).mode.htotal = mode_info.htotal;
                (*crtc).mode.vdisplay = mode_info.vdisplay;
                (*crtc).mode.vsync_start = mode_info.vsync_start;
                (*crtc).mode.vsync_end = mode_info.vsync_end;
                (*crtc).mode.vtotal = mode_info.vtotal;
                (*crtc).mode.vrefresh = mode_info.vrefresh;
                (*crtc).mode.flags = mode_info.flags;

                let name_bytes = mode_info.name.as_bytes();
                for (i, &b) in name_bytes.iter().take(31).enumerate() {
                    (*crtc).mode.name[i] = b as c_char;
                }
            }
            0
        }

        DRM_IOCTL_MODE_GETENCODER => {
            debug!("ioctl: DRM_IOCTL_MODE_GETENCODER");
            let enc = arg as *mut DrmModeGetEncoder;
            if !enc.is_null() {
                (*enc).encoder_type = 0; // DSI
                (*enc).crtc_id = 10; // CRTC_ID
                (*enc).possible_crtcs = 1;
                (*enc).possible_clones = 0;
            }
            0
        }

        DRM_IOCTL_MODE_GETPLANERESOURCES => {
            debug!("ioctl: DRM_IOCTL_MODE_GETPLANERESOURCES");
            let res = arg as *mut DrmModeGetPlaneRes;
            if !res.is_null() {
                if (*res).count_planes == 0 {
                    (*res).count_planes = 2; // Primary + cursor
                } else if (*res).plane_id_ptr != 0 {
                    let planes = (*res).plane_id_ptr as *mut u32;
                    *planes = 20; // PRIMARY_PLANE_ID
                    *planes.add(1) = 21; // CURSOR_PLANE_ID
                }
            }
            0
        }

        DRM_IOCTL_MODE_GETPLANE => {
            debug!("ioctl: DRM_IOCTL_MODE_GETPLANE");
            let plane = arg as *mut DrmModeGetPlane;
            if !plane.is_null() {
                let drm = match GLOBAL_DRM.lock().unwrap().clone() {
                    Some(d) => d,
                    None => return -1,
                };

                if let Some(plane_info) = drm.get_plane((*plane).plane_id) {
                    (*plane).crtc_id = plane_info.crtc_id;
                    (*plane).fb_id = plane_info.fb_id;
                    (*plane).possible_crtcs = plane_info.possible_crtcs;
                    (*plane).gamma_size = 0;

                    if (*plane).count_format_types == 0 {
                        (*plane).count_format_types = plane_info.formats.len() as u32;
                    } else if (*plane).format_type_ptr != 0 {
                        let fmts = (*plane).format_type_ptr as *mut u32;
                        for (i, &fmt) in plane_info.formats.iter().enumerate() {
                            *fmts.add(i) = fmt;
                        }
                    }
                } else {
                    return -1;
                }
            }
            0
        }

        DRM_IOCTL_MODE_OBJ_GETPROPERTIES => {
            debug!("ioctl: DRM_IOCTL_MODE_OBJ_GETPROPERTIES");
            let props = arg as *mut DrmModeObjGetProperties;
            if !props.is_null() {
                // Return minimal properties for now
                if (*props).count_props == 0 {
                    (*props).count_props = 1; // Just "type" property for planes
                } else if (*props).props_ptr != 0 && (*props).prop_values_ptr != 0 {
                    let prop_ids = (*props).props_ptr as *mut u32;
                    let prop_vals = (*props).prop_values_ptr as *mut u64;
                    *prop_ids = 1; // Property ID for "type"
                    *prop_vals = DRM_PLANE_TYPE_PRIMARY;
                }
            }
            0
        }

        DRM_IOCTL_MODE_ATOMIC => {
            debug!("ioctl: DRM_IOCTL_MODE_ATOMIC (accepting)");
            // Accept atomic commits - our display is managed by hwcomposer
            // We don't actually do anything here since hwcomposer manages the display
            0
        }

        DRM_IOCTL_MODE_ADDFB2 => {
            debug!("ioctl: DRM_IOCTL_MODE_ADDFB2");
            let fb = arg as *mut DrmModeFbCmd2;
            if !fb.is_null() {
                let drm = match GLOBAL_DRM.lock().unwrap().clone() {
                    Some(d) => d,
                    None => return -1,
                };

                let bpp = match (*fb).pixel_format {
                    GBM_FORMAT_RGB565 => 16,
                    _ => 32,
                };
                let depth = match (*fb).pixel_format {
                    GBM_FORMAT_XRGB8888 | GBM_FORMAT_XBGR8888 => 24,
                    _ => 32,
                };

                match drm.add_framebuffer(
                    (*fb).width,
                    (*fb).height,
                    (*fb).pitches[0],
                    bpp,
                    depth,
                    (*fb).pixel_format,
                    (*fb).handles[0],
                ) {
                    Ok(fb_id) => {
                        (*fb).fb_id = fb_id;
                        0
                    }
                    Err(_) => -1,
                }
            } else {
                -1
            }
        }

        DRM_IOCTL_MODE_RMFB => {
            debug!("ioctl: DRM_IOCTL_MODE_RMFB");
            let fb_id = arg as *mut u32;
            if !fb_id.is_null() {
                let drm = match GLOBAL_DRM.lock().unwrap().clone() {
                    Some(d) => d,
                    None => return -1,
                };

                match drm.remove_framebuffer(*fb_id) {
                    Ok(()) => 0,
                    Err(_) => -1,
                }
            } else {
                -1
            }
        }

        DRM_IOCTL_MODE_PAGE_FLIP => {
            debug!("ioctl: DRM_IOCTL_MODE_PAGE_FLIP");
            // Accept page flip requests
            0
        }

        DRM_IOCTL_MODE_SETCRTC => {
            debug!("ioctl: DRM_IOCTL_MODE_SETCRTC");
            // Accept CRTC configuration (mode is fixed by hwcomposer)
            0
        }

        DRM_IOCTL_MODE_CURSOR | DRM_IOCTL_MODE_CURSOR2 => {
            debug!("ioctl: DRM_IOCTL_MODE_CURSOR");
            // Accept cursor operations (no-op for mobile)
            0
        }

        _ => {
            // Log unknown ioctls but return success to avoid breaking things
            warn!("ioctl: Unknown DRM ioctl 0x{:x} (nr=0x{:x})", request, nr);
            0
        }
    }
}

// =============================================================================
// open() intercept for /dev/dri/*
// =============================================================================

/// Intercept open() calls to /dev/dri/*
/// Note: We use the 2-argument form. For O_CREAT, the mode is passed as 0 (DRM opens don't create files)
#[no_mangle]
pub unsafe extern "C" fn open(path: *const c_char, flags: c_int) -> c_int {
    // Initialize real function pointers
    init_real_funcs();

    if !path.is_null() {
        let path_str = CStr::from_ptr(path).to_str().unwrap_or("");

        // Intercept DRM device opens
        if path_str.starts_with("/dev/dri/") {
            // Try init first to determine if we're the main process
            let init_result = drm_hwcomposer_shim_init();

            // If we're not the main shim process, pass through to real open
            if !is_main_shim_process() {
                debug!("open(): not main shim process, passing through");
                if let Some(real_open) = REAL_OPEN_FN {
                    return real_open(path, flags, 0);
                }
            }

            if init_result == 0 {
                info!("open() intercepted: {} -> returning shim DRM fd", path_str);
                return get_or_create_shim_fd();
            } else {
                return -1;
            }
        }
    }

    // For all other files, call the real open
    if let Some(real_open) = REAL_OPEN_FN {
        real_open(path, flags, 0)
    } else {
        error!("Real open function not available!");
        *libc::__errno_location() = libc::ENOSYS;
        -1
    }
}

/// Intercept open64() as well (same as open on 64-bit systems)
#[no_mangle]
pub unsafe extern "C" fn open64(path: *const c_char, flags: c_int) -> c_int {
    // Initialize real function pointers
    init_real_funcs();

    if !path.is_null() {
        let path_str = CStr::from_ptr(path).to_str().unwrap_or("");
        if path_str.starts_with("/dev/dri/") {
            // Try init first to determine if we're the main process
            let init_result = drm_hwcomposer_shim_init();

            // If we're not the main shim process, pass through to real open
            if !is_main_shim_process() {
                debug!("open64(): not main shim process, passing through");
                if let Some(real_open) = REAL_OPEN_FN {
                    return real_open(path, flags, 0);
                }
            }

            if init_result == 0 {
                info!("open64() intercepted: {} -> returning shim DRM fd", path_str);
                return get_or_create_shim_fd();
            }
            return -1;
        }
    }

    if let Some(real_open) = REAL_OPEN_FN {
        real_open(path, flags, 0)
    } else {
        *libc::__errno_location() = libc::ENOSYS;
        -1
    }
}

/// Intercept openat() for /dev/dri/*
#[no_mangle]
pub unsafe extern "C" fn openat(dirfd: c_int, path: *const c_char, flags: c_int) -> c_int {
    // Initialize real function pointers
    init_real_funcs();

    if !path.is_null() {
        let path_str = CStr::from_ptr(path).to_str().unwrap_or("");

        // Intercept DRM device opens
        if path_str.starts_with("/dev/dri/") || path_str.contains("dri/card") {
            // Try init first to determine if we're the main process
            let init_result = drm_hwcomposer_shim_init();

            // If we're not the main shim process, pass through to real openat
            if !is_main_shim_process() {
                debug!("openat(): not main shim process, passing through");
                return libc::openat(dirfd, path, flags);
            }

            if init_result == 0 {
                info!("openat() intercepted: {} -> returning shim DRM fd", path_str);
                return get_or_create_shim_fd();
            } else {
                return -1;
            }
        }
    }

    // Call real openat using libc
    libc::openat(dirfd, path, flags)
}

// =============================================================================
// Cursor functions
// =============================================================================

/// Set cursor (no-op for now - mobile doesn't use cursors)
#[no_mangle]
pub unsafe extern "C" fn drmModeSetCursor(
    fd: c_int,
    crtc_id: u32,
    bo_handle: u32,
    width: u32,
    height: u32,
) -> c_int {
    debug!("drmModeSetCursor(crtc={}, handle={})", crtc_id, bo_handle);
    0 // Success, but we don't display a cursor
}

/// Set cursor with hotspot
#[no_mangle]
pub unsafe extern "C" fn drmModeSetCursor2(
    fd: c_int,
    crtc_id: u32,
    bo_handle: u32,
    width: u32,
    height: u32,
    hot_x: i32,
    hot_y: i32,
) -> c_int {
    debug!("drmModeSetCursor2(crtc={}, handle={})", crtc_id, bo_handle);
    0
}

/// Move cursor
#[no_mangle]
pub unsafe extern "C" fn drmModeMoveCursor(fd: c_int, crtc_id: u32, x: c_int, y: c_int) -> c_int {
    0
}

// =============================================================================
// Encoder functions
// =============================================================================

/// DRM encoder structure
#[repr(C)]
pub struct drmModeEncoder {
    pub encoder_id: u32,
    pub encoder_type: u32,
    pub crtc_id: u32,
    pub possible_crtcs: u32,
    pub possible_clones: u32,
}

/// Get encoder info
#[no_mangle]
pub unsafe extern "C" fn drmModeGetEncoder(fd: c_int, encoder_id: u32) -> *mut drmModeEncoder {
    debug!("drmModeGetEncoder(fd={}, id={})", fd, encoder_id);

    let encoder = Box::new(drmModeEncoder {
        encoder_id,
        encoder_type: 0, // DRM_MODE_ENCODER_DSI
        crtc_id: 10, // CRTC_ID
        possible_crtcs: 1,
        possible_clones: 0,
    });

    Box::into_raw(encoder)
}

/// Free encoder
#[no_mangle]
pub unsafe extern "C" fn drmModeFreeEncoder(encoder: *mut drmModeEncoder) {
    if encoder.is_null() {
        return;
    }
    let _ = Box::from_raw(encoder);
}

// =============================================================================
// Property functions
// =============================================================================

/// DRM property structure
#[repr(C)]
pub struct drmModePropertyRes {
    pub prop_id: u32,
    pub flags: u32,
    pub name: [c_char; 32],
    pub count_values: c_int,
    pub values: *mut u64,
    pub count_enums: c_int,
    pub enums: *mut drmModePropertyEnum,
    pub count_blobs: c_int,
    pub blob_ids: *mut u32,
}

#[repr(C)]
pub struct drmModePropertyEnum {
    pub value: u64,
    pub name: [c_char; 32],
}

/// Get property
#[no_mangle]
pub unsafe extern "C" fn drmModeGetProperty(fd: c_int, prop_id: u32) -> *mut drmModePropertyRes {
    debug!("drmModeGetProperty(fd={}, id={})", fd, prop_id);

    // Return a basic property for "type" (used for plane type)
    let mut prop = Box::new(drmModePropertyRes {
        prop_id,
        flags: 0,
        name: [0; 32],
        count_values: 0,
        values: ptr::null_mut(),
        count_enums: 3,
        enums: ptr::null_mut(),
        count_blobs: 0,
        blob_ids: ptr::null_mut(),
    });

    // Set name based on prop_id
    let name: &[u8] = match prop_id {
        1 => b"type\0",
        _ => b"unknown\0",
    };
    for (i, &b) in name.iter().take(31).enumerate() {
        prop.name[i] = b as c_char;
    }

    Box::into_raw(prop)
}

/// Free property
#[no_mangle]
pub unsafe extern "C" fn drmModeFreeProperty(prop: *mut drmModePropertyRes) {
    if prop.is_null() {
        return;
    }
    let _ = Box::from_raw(prop);
}

/// Get object properties
#[repr(C)]
pub struct drmModeObjectProperties {
    pub count_props: u32,
    pub props: *mut u32,
    pub prop_values: *mut u64,
}

#[no_mangle]
pub unsafe extern "C" fn drmModeObjectGetProperties(
    fd: c_int,
    object_id: u32,
    object_type: u32,
) -> *mut drmModeObjectProperties {
    debug!("drmModeObjectGetProperties(fd={}, obj={}, type={})", fd, object_id, object_type);

    // For planes, return the type property
    let props = Box::new(drmModeObjectProperties {
        count_props: 1,
        props: Box::into_raw(vec![1u32].into_boxed_slice()) as *mut u32, // prop_id 1 = "type"
        prop_values: Box::into_raw(vec![DRM_PLANE_TYPE_PRIMARY].into_boxed_slice()) as *mut u64,
    });

    Box::into_raw(props)
}

/// Free object properties
#[no_mangle]
pub unsafe extern "C" fn drmModeFreeObjectProperties(props: *mut drmModeObjectProperties) {
    if props.is_null() {
        return;
    }
    let p = Box::from_raw(props);
    if !p.props.is_null() {
        let _ = Vec::from_raw_parts(p.props, p.count_props as usize, p.count_props as usize);
    }
    if !p.prop_values.is_null() {
        let _ = Vec::from_raw_parts(p.prop_values, p.count_props as usize, p.count_props as usize);
    }
}

// =============================================================================
// Initialization
// =============================================================================

// Static initialization result
static INIT_RESULT: Mutex<Option<c_int>> = Mutex::new(None);
static SHIM_INIT_ONCE: Once = Once::new();

// System-wide lock file to prevent multiple processes from initializing hwcomposer
const LOCK_FILE: &str = "/tmp/drm-hwcomposer-shim.lock";

// Track if this process is the main shim process (holds the lock)
static IS_MAIN_SHIM_PROCESS: Mutex<Option<bool>> = Mutex::new(None);

fn is_main_shim_process() -> bool {
    if let Ok(guard) = IS_MAIN_SHIM_PROCESS.lock() {
        guard.unwrap_or(false)
    } else {
        false
    }
}

fn try_acquire_system_lock() -> Option<std::fs::File> {
    use std::fs::OpenOptions;
    use std::os::unix::fs::OpenOptionsExt;

    match OpenOptions::new()
        .write(true)
        .create(true)
        .mode(0o666)
        .open(LOCK_FILE)
    {
        Ok(file) => {
            // Try to get exclusive lock (non-blocking)
            let fd = std::os::unix::io::AsRawFd::as_raw_fd(&file);
            let result = unsafe { libc::flock(fd, libc::LOCK_EX | libc::LOCK_NB) };
            if result == 0 {
                Some(file)
            } else {
                // Another process has the lock
                None
            }
        }
        Err(_) => None,
    }
}

/// Initialize the shim (call this before using any other functions)
#[no_mangle]
pub extern "C" fn drm_hwcomposer_shim_init() -> c_int {
    // Check if already initialized in this process
    if let Ok(guard) = INIT_RESULT.lock() {
        if let Some(result) = *guard {
            return result;
        }
    }

    let mut result = -1;

    SHIM_INIT_ONCE.call_once(|| {
        // Initialize tracing
        let _ = tracing_subscriber::fmt()
            .with_max_level(tracing::Level::INFO)
            .try_init();

        // Try to acquire system-wide lock
        let lock_file = try_acquire_system_lock();
        if lock_file.is_none() {
            // Another process is initializing hwcomposer, we're probably a child process
            // Mark ourselves as NOT the main shim process
            if let Ok(mut guard) = IS_MAIN_SHIM_PROCESS.lock() {
                *guard = Some(false);
            }
            warn!("drm_hwcomposer_shim_init: Another process has hwcomposer lock, passing through");
            result = 0;
            return;
        }

        // Mark ourselves as the main shim process
        if let Ok(mut guard) = IS_MAIN_SHIM_PROCESS.lock() {
            *guard = Some(true);
        }

        info!("drm_hwcomposer_shim_init: first-time initialization (holding lock)");

        // Create global DRM device
        let mut global = GLOBAL_DRM.lock().unwrap();
        if global.is_none() {
            match HwcDrmDevice::new() {
                Ok(d) => {
                    info!("HwcDrmDevice created successfully");
                    *global = Some(Arc::new(d));
                    result = 0;
                }
                Err(e) => {
                    error!("Failed to initialize: {}", e);
                    result = -1;
                }
            }
        } else {
            info!("GLOBAL_DRM already set");
            result = 0;
        }

        // Keep lock file open (will be released when process exits)
        std::mem::forget(lock_file);
    });

    // Store result for subsequent calls
    if let Ok(mut guard) = INIT_RESULT.lock() {
        *guard = Some(result);
    }

    result
}

/// Get the EGL display from the shim (for EGL integration)
#[no_mangle]
pub unsafe extern "C" fn drm_hwcomposer_shim_get_egl_display() -> *mut c_void {
    let global = GLOBAL_DRM.lock().unwrap();
    if let Some(ref drm) = *global {
        drm.egl_display().unwrap_or(ptr::null_mut())
    } else {
        ptr::null_mut()
    }
}

/// Initialize EGL on the shim device
#[no_mangle]
pub unsafe extern "C" fn drm_hwcomposer_shim_init_egl() -> c_int {
    let global = GLOBAL_DRM.lock().unwrap();
    if let Some(ref drm) = *global {
        match drm.init_egl() {
            Ok(()) => 0,
            Err(e) => {
                error!("Failed to init EGL: {}", e);
                -1
            }
        }
    } else {
        -1
    }
}

/// Swap buffers (present to display)
#[no_mangle]
pub unsafe extern "C" fn drm_hwcomposer_shim_swap_buffers() -> c_int {
    let global = GLOBAL_DRM.lock().unwrap();
    if let Some(ref drm) = *global {
        match drm.swap_buffers() {
            Ok(()) => 0,
            Err(e) => {
                error!("Failed to swap buffers: {}", e);
                -1
            }
        }
    } else {
        -1
    }
}

// =============================================================================
// EGL Interception for Universal Compositor Support
// =============================================================================
//
// When compositors like Weston use GBM + EGL, they expect Mesa's EGL to work
// with GBM devices. On hwcomposer systems, we need to intercept EGL calls
// and redirect them to hwcomposer's EGL implementation.

// EGL types
type EGLDisplay = *mut c_void;
type EGLSurface = *mut c_void;
type EGLConfig = *mut c_void;
type EGLNativeDisplayType = *mut c_void;
type EGLNativeWindowType = *mut c_void;
type EGLint = i32;

const EGL_NO_DISPLAY: EGLDisplay = std::ptr::null_mut();
const EGL_NO_SURFACE: EGLSurface = std::ptr::null_mut();
const EGL_FALSE: u32 = 0;
const EGL_TRUE: u32 = 1;
const EGL_PLATFORM_GBM_KHR: u32 = 0x31D7;
const EGL_PLATFORM_GBM_MESA: u32 = 0x31D7;

// Cached real EGL function pointers
static mut REAL_EGL_GET_DISPLAY: Option<unsafe extern "C" fn(EGLNativeDisplayType) -> EGLDisplay> = None;
static mut REAL_EGL_GET_PLATFORM_DISPLAY: Option<unsafe extern "C" fn(u32, *mut c_void, *const EGLint) -> EGLDisplay> = None;
static mut REAL_EGL_INITIALIZE: Option<unsafe extern "C" fn(EGLDisplay, *mut EGLint, *mut EGLint) -> u32> = None;
static mut REAL_EGL_CREATE_WINDOW_SURFACE: Option<unsafe extern "C" fn(EGLDisplay, EGLConfig, EGLNativeWindowType, *const EGLint) -> EGLSurface> = None;
static mut REAL_EGL_SWAP_BUFFERS: Option<unsafe extern "C" fn(EGLDisplay, EGLSurface) -> u32> = None;
static EGL_INIT: Once = Once::new();

// Track if we've initialized hwcomposer EGL
static EGL_INITIALIZED: Mutex<bool> = Mutex::new(false);

// Thread-local recursion guard to prevent infinite loops
std::thread_local! {
    static IN_EGL_INTERCEPT: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

unsafe fn init_egl_funcs() {
    EGL_INIT.call_once(|| {
        // Load real EGL functions via RTLD_NEXT
        let get_display = libc::dlsym(RTLD_NEXT, b"eglGetDisplay\0".as_ptr() as *const c_char);
        if !get_display.is_null() {
            REAL_EGL_GET_DISPLAY = Some(std::mem::transmute(get_display));
        }

        let get_platform_display = libc::dlsym(RTLD_NEXT, b"eglGetPlatformDisplay\0".as_ptr() as *const c_char);
        if !get_platform_display.is_null() {
            REAL_EGL_GET_PLATFORM_DISPLAY = Some(std::mem::transmute(get_platform_display));
        }

        let initialize = libc::dlsym(RTLD_NEXT, b"eglInitialize\0".as_ptr() as *const c_char);
        if !initialize.is_null() {
            REAL_EGL_INITIALIZE = Some(std::mem::transmute(initialize));
        }

        let create_window_surface = libc::dlsym(RTLD_NEXT, b"eglCreateWindowSurface\0".as_ptr() as *const c_char);
        if !create_window_surface.is_null() {
            REAL_EGL_CREATE_WINDOW_SURFACE = Some(std::mem::transmute(create_window_surface));
        }

        let swap_buffers = libc::dlsym(RTLD_NEXT, b"eglSwapBuffers\0".as_ptr() as *const c_char);
        if !swap_buffers.is_null() {
            REAL_EGL_SWAP_BUFFERS = Some(std::mem::transmute(swap_buffers));
        }

        info!("EGL function pointers initialized for interception");
    });
}

/// Intercept eglGetDisplay - return hwcomposer's EGL display
#[no_mangle]
pub unsafe extern "C" fn eglGetDisplay(display_id: EGLNativeDisplayType) -> EGLDisplay {
    // Check for recursion - if we're already in an intercept, pass through to real function
    let in_intercept = IN_EGL_INTERCEPT.with(|flag| flag.get());
    if in_intercept {
        // Recursion detected - call real function
        init_egl_funcs();
        if let Some(real_fn) = REAL_EGL_GET_DISPLAY {
            return real_fn(display_id);
        }
        return EGL_NO_DISPLAY;
    }

    // Set recursion guard
    IN_EGL_INTERCEPT.with(|flag| flag.set(true));

    init_egl_funcs();
    info!("eglGetDisplay intercepted (display_id={:?})", display_id);

    // Initialize the shim and its EGL
    if drm_hwcomposer_shim_init() != 0 {
        error!("Failed to initialize shim for EGL");
        IN_EGL_INTERCEPT.with(|flag| flag.set(false));
        return EGL_NO_DISPLAY;
    }

    if drm_hwcomposer_shim_init_egl() != 0 {
        error!("Failed to initialize hwcomposer EGL");
        IN_EGL_INTERCEPT.with(|flag| flag.set(false));
        return EGL_NO_DISPLAY;
    }

    *EGL_INITIALIZED.lock().unwrap() = true;

    // Clear recursion guard
    IN_EGL_INTERCEPT.with(|flag| flag.set(false));

    // Return our hwcomposer EGL display
    drm_hwcomposer_shim_get_egl_display()
}

/// Intercept eglGetPlatformDisplay - handle GBM platform requests
#[no_mangle]
pub unsafe extern "C" fn eglGetPlatformDisplay(
    platform: u32,
    native_display: *mut c_void,
    attrib_list: *const EGLint,
) -> EGLDisplay {
    // Check for recursion
    let in_intercept = IN_EGL_INTERCEPT.with(|flag| flag.get());
    if in_intercept {
        init_egl_funcs();
        if let Some(real_fn) = REAL_EGL_GET_PLATFORM_DISPLAY {
            return real_fn(platform, native_display, attrib_list);
        }
        return EGL_NO_DISPLAY;
    }

    // Set recursion guard
    IN_EGL_INTERCEPT.with(|flag| flag.set(true));

    init_egl_funcs();
    info!("eglGetPlatformDisplay intercepted (platform=0x{:x}, native_display={:?})", platform, native_display);

    // Intercept GBM platform requests
    if platform == EGL_PLATFORM_GBM_KHR || platform == EGL_PLATFORM_GBM_MESA {
        info!("GBM platform requested - redirecting to hwcomposer EGL");

        // Initialize the shim and its EGL
        if drm_hwcomposer_shim_init() != 0 {
            error!("Failed to initialize shim for EGL");
            IN_EGL_INTERCEPT.with(|flag| flag.set(false));
            return EGL_NO_DISPLAY;
        }

        if drm_hwcomposer_shim_init_egl() != 0 {
            error!("Failed to initialize hwcomposer EGL");
            IN_EGL_INTERCEPT.with(|flag| flag.set(false));
            return EGL_NO_DISPLAY;
        }

        *EGL_INITIALIZED.lock().unwrap() = true;
        IN_EGL_INTERCEPT.with(|flag| flag.set(false));

        // Return our hwcomposer EGL display
        return drm_hwcomposer_shim_get_egl_display();
    }

    IN_EGL_INTERCEPT.with(|flag| flag.set(false));

    // For other platforms, use the real function
    if let Some(real_fn) = REAL_EGL_GET_PLATFORM_DISPLAY {
        real_fn(platform, native_display, attrib_list)
    } else {
        error!("Real eglGetPlatformDisplay not available");
        EGL_NO_DISPLAY
    }
}

/// Intercept eglInitialize - we may have already initialized
#[no_mangle]
pub unsafe extern "C" fn eglInitialize(dpy: EGLDisplay, major: *mut EGLint, minor: *mut EGLint) -> u32 {
    // Check for recursion - if we're already in an EGL intercept (e.g., during init_egl),
    // pass through to real function to avoid deadlock on GLOBAL_DRM mutex
    let in_intercept = IN_EGL_INTERCEPT.with(|flag| flag.get());
    if in_intercept {
        init_egl_funcs();
        if let Some(real_fn) = REAL_EGL_INITIALIZE {
            return real_fn(dpy, major, minor);
        }
        return EGL_FALSE;
    }

    init_egl_funcs();
    debug!("eglInitialize intercepted (dpy={:?})", dpy);

    // Check if this is our hwcomposer display (already initialized)
    let our_display = drm_hwcomposer_shim_get_egl_display();
    if dpy == our_display && *EGL_INITIALIZED.lock().unwrap() {
        // Already initialized - just return version
        if !major.is_null() {
            *major = 1;
        }
        if !minor.is_null() {
            *minor = 4;
        }
        info!("eglInitialize: hwcomposer EGL already initialized, returning 1.4");
        return EGL_TRUE;
    }

    // Otherwise use real function
    if let Some(real_fn) = REAL_EGL_INITIALIZE {
        real_fn(dpy, major, minor)
    } else {
        error!("Real eglInitialize not available");
        EGL_FALSE
    }
}

/// Intercept eglCreateWindowSurface - use our native window
#[no_mangle]
pub unsafe extern "C" fn eglCreateWindowSurface(
    dpy: EGLDisplay,
    config: EGLConfig,
    win: EGLNativeWindowType,
    attrib_list: *const EGLint,
) -> EGLSurface {
    // Check for recursion to avoid deadlock
    let in_intercept = IN_EGL_INTERCEPT.with(|flag| flag.get());
    if in_intercept {
        init_egl_funcs();
        if let Some(real_fn) = REAL_EGL_CREATE_WINDOW_SURFACE {
            return real_fn(dpy, config, win, attrib_list);
        }
        return EGL_NO_SURFACE;
    }

    init_egl_funcs();
    debug!("eglCreateWindowSurface intercepted (dpy={:?}, win={:?})", dpy, win);

    // Check if this is our hwcomposer display
    let our_display = drm_hwcomposer_shim_get_egl_display();
    if dpy == our_display {
        // The surface was already created during init_egl
        // Return our existing surface
        let global = GLOBAL_DRM.lock().unwrap();
        if let Some(ref drm) = *global {
            let surface = drm.egl_surface().unwrap_or(EGL_NO_SURFACE);
            info!("eglCreateWindowSurface: returning hwcomposer EGL surface {:?}", surface);
            return surface;
        }
    }

    // Otherwise use real function
    if let Some(real_fn) = REAL_EGL_CREATE_WINDOW_SURFACE {
        real_fn(dpy, config, win, attrib_list)
    } else {
        error!("Real eglCreateWindowSurface not available");
        EGL_NO_SURFACE
    }
}

/// Intercept eglSwapBuffers - present via hwcomposer
#[no_mangle]
pub unsafe extern "C" fn eglSwapBuffers(dpy: EGLDisplay, surface: EGLSurface) -> u32 {
    // Check for recursion to avoid deadlock
    let in_intercept = IN_EGL_INTERCEPT.with(|flag| flag.get());
    if in_intercept {
        init_egl_funcs();
        if let Some(real_fn) = REAL_EGL_SWAP_BUFFERS {
            return real_fn(dpy, surface);
        }
        return EGL_FALSE;
    }

    // Check if this is our hwcomposer display
    let our_display = drm_hwcomposer_shim_get_egl_display();
    if dpy == our_display {
        if drm_hwcomposer_shim_swap_buffers() == 0 {
            return EGL_TRUE;
        } else {
            return EGL_FALSE;
        }
    }

    // Otherwise use real function
    init_egl_funcs();
    if let Some(real_fn) = REAL_EGL_SWAP_BUFFERS {
        real_fn(dpy, surface)
    } else {
        error!("Real eglSwapBuffers not available");
        EGL_FALSE
    }
}

// Real EGL function pointer for GetProcAddress
static mut REAL_EGL_GET_PROC_ADDRESS: Option<unsafe extern "C" fn(*const c_char) -> *mut c_void> = None;
static EGL_PROC_INIT: Once = Once::new();

unsafe fn init_egl_proc_funcs() {
    EGL_PROC_INIT.call_once(|| {
        let get_proc = libc::dlsym(RTLD_NEXT, b"eglGetProcAddress\0".as_ptr() as *const c_char);
        if !get_proc.is_null() {
            REAL_EGL_GET_PROC_ADDRESS = Some(std::mem::transmute(get_proc));
        }
    });
}

/// Intercept eglGetProcAddress - return our intercepted functions
#[no_mangle]
pub unsafe extern "C" fn eglGetProcAddress(procname: *const c_char) -> *mut c_void {
    init_egl_funcs();
    init_egl_proc_funcs();

    if procname.is_null() {
        return ptr::null_mut();
    }

    let name = CStr::from_ptr(procname).to_str().unwrap_or("");
    debug!("eglGetProcAddress(\"{}\")", name);

    // Return our intercepted functions for key EGL calls
    match name {
        "eglGetDisplay" => eglGetDisplay as *mut c_void,
        "eglGetPlatformDisplay" => eglGetPlatformDisplay as *mut c_void,
        "eglGetPlatformDisplayEXT" => eglGetPlatformDisplay as *mut c_void,
        "eglInitialize" => eglInitialize as *mut c_void,
        "eglCreateWindowSurface" => eglCreateWindowSurface as *mut c_void,
        "eglSwapBuffers" => eglSwapBuffers as *mut c_void,
        _ => {
            // For other functions, use real eglGetProcAddress
            if let Some(real_fn) = REAL_EGL_GET_PROC_ADDRESS {
                real_fn(procname)
            } else {
                ptr::null_mut()
            }
        }
    }
}

/// Intercept eglChooseConfig - use hwcomposer's config
#[no_mangle]
pub unsafe extern "C" fn eglChooseConfig(
    dpy: EGLDisplay,
    attrib_list: *const EGLint,
    configs: *mut EGLConfig,
    config_size: EGLint,
    num_config: *mut EGLint,
) -> u32 {
    // Check for recursion to avoid deadlock
    let in_intercept = IN_EGL_INTERCEPT.with(|flag| flag.get());
    if in_intercept {
        let real_fn: Option<unsafe extern "C" fn(EGLDisplay, *const EGLint, *mut EGLConfig, EGLint, *mut EGLint) -> u32> = {
            let sym = libc::dlsym(RTLD_NEXT, b"eglChooseConfig\0".as_ptr() as *const c_char);
            if sym.is_null() { None } else { Some(std::mem::transmute(sym)) }
        };
        if let Some(f) = real_fn {
            return f(dpy, attrib_list, configs, config_size, num_config);
        }
        return EGL_FALSE;
    }

    debug!("eglChooseConfig intercepted (dpy={:?})", dpy);

    // Check if this is our hwcomposer display
    let our_display = drm_hwcomposer_shim_get_egl_display();
    if dpy == our_display {
        // Return our pre-chosen config
        let global = GLOBAL_DRM.lock().unwrap();
        if let Some(ref drm) = *global {
            if let Ok(config) = drm.egl_config() {
                if !configs.is_null() && config_size >= 1 {
                    *configs = config;
                }
                if !num_config.is_null() {
                    *num_config = 1;
                }
                info!("eglChooseConfig: returning hwcomposer EGL config {:?}", config);
                return EGL_TRUE;
            }
        }
    }

    // Call real eglChooseConfig via dlsym
    let real_fn: Option<unsafe extern "C" fn(EGLDisplay, *const EGLint, *mut EGLConfig, EGLint, *mut EGLint) -> u32> = {
        let sym = libc::dlsym(RTLD_NEXT, b"eglChooseConfig\0".as_ptr() as *const c_char);
        if sym.is_null() { None } else { Some(std::mem::transmute(sym)) }
    };

    if let Some(f) = real_fn {
        f(dpy, attrib_list, configs, config_size, num_config)
    } else {
        error!("Real eglChooseConfig not available");
        EGL_FALSE
    }
}

/// Intercept eglCreateContext
#[no_mangle]
pub unsafe extern "C" fn eglCreateContext(
    dpy: EGLDisplay,
    config: EGLConfig,
    share_context: EGLContext,
    attrib_list: *const EGLint,
) -> EGLContext {
    // Check for recursion to avoid deadlock
    let in_intercept = IN_EGL_INTERCEPT.with(|flag| flag.get());
    if in_intercept {
        type EGLCtx = *mut c_void;
        let real_fn: Option<unsafe extern "C" fn(EGLDisplay, EGLConfig, EGLCtx, *const EGLint) -> EGLCtx> = {
            let sym = libc::dlsym(RTLD_NEXT, b"eglCreateContext\0".as_ptr() as *const c_char);
            if sym.is_null() { None } else { Some(std::mem::transmute(sym)) }
        };
        if let Some(f) = real_fn {
            return f(dpy, config, share_context, attrib_list);
        }
        return ptr::null_mut();
    }

    debug!("eglCreateContext intercepted (dpy={:?})", dpy);

    // Check if this is our hwcomposer display
    let our_display = drm_hwcomposer_shim_get_egl_display();
    if dpy == our_display {
        // Return our pre-created context
        let global = GLOBAL_DRM.lock().unwrap();
        if let Some(ref drm) = *global {
            if let Ok(ctx) = drm.egl_context() {
                info!("eglCreateContext: returning hwcomposer EGL context {:?}", ctx);
                return ctx;
            }
        }
    }

    // Call real eglCreateContext via dlsym
    type EGLContext = *mut c_void;
    let real_fn: Option<unsafe extern "C" fn(EGLDisplay, EGLConfig, EGLContext, *const EGLint) -> EGLContext> = {
        let sym = libc::dlsym(RTLD_NEXT, b"eglCreateContext\0".as_ptr() as *const c_char);
        if sym.is_null() { None } else { Some(std::mem::transmute(sym)) }
    };

    if let Some(f) = real_fn {
        f(dpy, config, share_context, attrib_list)
    } else {
        error!("Real eglCreateContext not available");
        ptr::null_mut()
    }
}

/// Intercept eglMakeCurrent
#[no_mangle]
pub unsafe extern "C" fn eglMakeCurrent(
    dpy: EGLDisplay,
    draw: EGLSurface,
    read: EGLSurface,
    ctx: EGLContext,
) -> u32 {
    // Check for recursion to avoid deadlock
    let in_intercept = IN_EGL_INTERCEPT.with(|flag| flag.get());
    if in_intercept {
        type EGLCtx = *mut c_void;
        let real_fn: Option<unsafe extern "C" fn(EGLDisplay, EGLSurface, EGLSurface, EGLCtx) -> u32> = {
            let sym = libc::dlsym(RTLD_NEXT, b"eglMakeCurrent\0".as_ptr() as *const c_char);
            if sym.is_null() { None } else { Some(std::mem::transmute(sym)) }
        };
        if let Some(f) = real_fn {
            return f(dpy, draw, read, ctx);
        }
        return EGL_FALSE;
    }

    debug!("eglMakeCurrent intercepted (dpy={:?})", dpy);

    // Check if this is our hwcomposer display
    let our_display = drm_hwcomposer_shim_get_egl_display();
    if dpy == our_display {
        // Already made current during init, just return success
        info!("eglMakeCurrent: hwcomposer context already current");
        return EGL_TRUE;
    }

    // Call real eglMakeCurrent via dlsym
    type EGLContext = *mut c_void;
    let real_fn: Option<unsafe extern "C" fn(EGLDisplay, EGLSurface, EGLSurface, EGLContext) -> u32> = {
        let sym = libc::dlsym(RTLD_NEXT, b"eglMakeCurrent\0".as_ptr() as *const c_char);
        if sym.is_null() { None } else { Some(std::mem::transmute(sym)) }
    };

    if let Some(f) = real_fn {
        f(dpy, draw, read, ctx)
    } else {
        error!("Real eglMakeCurrent not available");
        EGL_FALSE
    }
}

// Additional type for EGLContext
type EGLContext = *mut c_void;
