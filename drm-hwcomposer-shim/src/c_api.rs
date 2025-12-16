//! C API for libgbm/libdrm compatibility
//!
//! This module provides C-compatible functions that match the libgbm and libdrm APIs,
//! allowing existing applications to use this shim as a drop-in replacement.

use crate::drm_device::{HwcDrmDevice, drm_fourcc, PlaneType};
use crate::gbm_device::{GbmFormat, HwcGbmBo, HwcGbmDevice, HwcGbmSurface, gbm_usage};
use std::ffi::{c_char, c_int, c_uint, c_void, CStr};
use std::ptr;
use std::sync::{Arc, Mutex};
use tracing::{debug, error, info, warn};

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

    // Get or create global DRM device
    let drm = {
        let mut global = GLOBAL_DRM.lock().unwrap();
        if global.is_none() {
            match HwcDrmDevice::new() {
                Ok(d) => {
                    *global = Some(Arc::new(d));
                }
                Err(e) => {
                    error!("Failed to create DRM device: {}", e);
                    return ptr::null_mut();
                }
            }
        }
        global.clone().unwrap()
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

/// Get DMA-BUF fd (not yet implemented)
#[no_mangle]
pub unsafe extern "C" fn gbm_bo_get_fd(bo: *mut gbm_bo) -> c_int {
    warn!("gbm_bo_get_fd: DMA-BUF export not yet implemented");
    -1
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

    // Get or create global DRM device
    let drm = {
        let mut global = GLOBAL_DRM.lock().unwrap();
        if global.is_none() {
            match HwcDrmDevice::new() {
                Ok(d) => {
                    *global = Some(Arc::new(d));
                }
                Err(e) => {
                    error!("Failed to create DRM device: {}", e);
                    return ptr::null_mut();
                }
            }
        }
        global.clone().unwrap()
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
// Initialization
// =============================================================================

/// Initialize the shim (call this before using any other functions)
#[no_mangle]
pub extern "C" fn drm_hwcomposer_shim_init() -> c_int {
    info!("drm_hwcomposer_shim_init");

    // Initialize tracing
    let _ = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .try_init();

    // Create global DRM device
    let mut global = GLOBAL_DRM.lock().unwrap();
    if global.is_none() {
        match HwcDrmDevice::new() {
            Ok(d) => {
                *global = Some(Arc::new(d));
                0
            }
            Err(e) => {
                error!("Failed to initialize: {}", e);
                -1
            }
        }
    } else {
        0
    }
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
