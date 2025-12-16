//! GBM device implementation backed by Android gralloc
//!
//! This provides GBM-compatible buffer allocation using Android's gralloc HAL.

use crate::drm_device::HwcDrmDevice;
use crate::ffi::*;
use crate::{Error, Result};
use std::os::raw::c_void;
use std::sync::Arc;
use tracing::{debug, info};

/// GBM buffer format (subset of common formats)
#[repr(u32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GbmFormat {
    Xrgb8888 = 0x34325258, // 'XR24'
    Argb8888 = 0x34325241, // 'AR24'
    Rgb565 = 0x36314752,   // 'RG16'
    Xbgr8888 = 0x34324258, // 'XB24'
    Abgr8888 = 0x34324241, // 'AB24'
}

impl GbmFormat {
    /// Convert to HAL pixel format
    pub fn to_hal_format(&self) -> i32 {
        match self {
            GbmFormat::Argb8888 | GbmFormat::Abgr8888 => HAL_PIXEL_FORMAT_RGBA_8888,
            GbmFormat::Xrgb8888 | GbmFormat::Xbgr8888 => HAL_PIXEL_FORMAT_RGBX_8888,
            GbmFormat::Rgb565 => HAL_PIXEL_FORMAT_RGB_565,
        }
    }
}

/// GBM buffer usage flags
#[repr(u32)]
#[derive(Debug, Clone, Copy)]
pub enum GbmUsage {
    Scanout = 1 << 0,
    Cursor = 1 << 1,
    Rendering = 1 << 2,
    Write = 1 << 3,
    Linear = 1 << 4,
}

/// A buffer object allocated via gralloc
pub struct HwcGbmBo {
    handle: *mut c_void, // gralloc buffer handle
    width: u32,
    height: u32,
    stride: u32,
    format: GbmFormat,
    fd: i32, // DMA-BUF fd if available
}

/// GBM surface for rendering
pub struct HwcGbmSurface {
    device: Arc<HwcGbmDevice>,
    width: u32,
    height: u32,
    format: GbmFormat,
    buffers: Vec<HwcGbmBo>,
    current_buffer: usize,
}

/// GBM device backed by Android gralloc
pub struct HwcGbmDevice {
    drm_device: Arc<HwcDrmDevice>,
    gralloc_device: *mut c_void,
}

impl HwcGbmDevice {
    /// Create a new GBM device from a DRM device
    pub fn new(drm_device: Arc<HwcDrmDevice>) -> Result<Self> {
        info!("Creating HwcGbmDevice backed by gralloc");

        // In a full implementation, we would:
        // 1. Load gralloc HAL via hw_get_module
        // 2. Open the gralloc device
        // For now, use a placeholder

        Ok(Self {
            drm_device,
            gralloc_device: std::ptr::null_mut(),
        })
    }

    /// Allocate a buffer object
    pub fn create_bo(
        &self,
        width: u32,
        height: u32,
        format: GbmFormat,
        _usage: u32,
    ) -> Result<HwcGbmBo> {
        info!("Allocating buffer {}x{} format {:?}", width, height, format);

        // Calculate stride (assuming 4 bytes per pixel for ARGB)
        let bpp = match format {
            GbmFormat::Rgb565 => 2,
            _ => 4,
        };
        let stride = width * bpp;

        // In a full implementation, we would:
        // 1. Call gralloc_alloc with appropriate usage flags
        // 2. Get the buffer handle and DMA-BUF fd
        // For now, create a placeholder

        Ok(HwcGbmBo {
            handle: std::ptr::null_mut(),
            width,
            height,
            stride,
            format,
            fd: -1,
        })
    }

    /// Create a surface for rendering
    pub fn create_surface(
        self: &Arc<Self>,
        width: u32,
        height: u32,
        format: GbmFormat,
        usage: u32,
    ) -> Result<HwcGbmSurface> {
        info!("Creating surface {}x{}", width, height);

        // Create triple-buffered surface
        let mut buffers = Vec::with_capacity(3);
        for _ in 0..3 {
            buffers.push(self.create_bo(width, height, format, usage)?);
        }

        Ok(HwcGbmSurface {
            device: Arc::clone(self),
            width,
            height,
            format,
            buffers,
            current_buffer: 0,
        })
    }

    /// Get the underlying DRM device
    pub fn drm_device(&self) -> &Arc<HwcDrmDevice> {
        &self.drm_device
    }

    /// Import a DMA-BUF as a buffer object
    pub fn import_dmabuf(
        &self,
        fd: i32,
        width: u32,
        height: u32,
        stride: u32,
        format: GbmFormat,
    ) -> Result<HwcGbmBo> {
        debug!("Importing DMA-BUF fd={} {}x{}", fd, width, height);

        // In a full implementation, we would:
        // 1. Import the fd via gralloc
        // 2. Create EGL image from the buffer

        Ok(HwcGbmBo {
            handle: std::ptr::null_mut(),
            width,
            height,
            stride,
            format,
            fd,
        })
    }
}

impl HwcGbmBo {
    /// Get the width of the buffer
    pub fn width(&self) -> u32 {
        self.width
    }

    /// Get the height of the buffer
    pub fn height(&self) -> u32 {
        self.height
    }

    /// Get the stride (bytes per row)
    pub fn stride(&self) -> u32 {
        self.stride
    }

    /// Get the format
    pub fn format(&self) -> GbmFormat {
        self.format
    }

    /// Get the DMA-BUF file descriptor (if available)
    pub fn fd(&self) -> Option<i32> {
        if self.fd >= 0 {
            Some(self.fd)
        } else {
            None
        }
    }

    /// Get the native handle (for Android HAL)
    pub fn native_handle(&self) -> *mut c_void {
        self.handle
    }
}

impl HwcGbmSurface {
    /// Lock the front buffer for rendering
    pub fn lock_front_buffer(&mut self) -> Result<&HwcGbmBo> {
        let buffer = &self.buffers[self.current_buffer];
        self.current_buffer = (self.current_buffer + 1) % self.buffers.len();
        Ok(buffer)
    }

    /// Get surface dimensions
    pub fn dimensions(&self) -> (u32, u32) {
        (self.width, self.height)
    }
}

impl Drop for HwcGbmBo {
    fn drop(&mut self) {
        // Free gralloc buffer
        debug!("Freeing GBM buffer");
        // gralloc_free(self.handle)
    }
}

impl Drop for HwcGbmDevice {
    fn drop(&mut self) {
        // Close gralloc device
        debug!("Closing GBM device");
    }
}

unsafe impl Send for HwcGbmDevice {}
unsafe impl Sync for HwcGbmDevice {}
unsafe impl Send for HwcGbmBo {}
