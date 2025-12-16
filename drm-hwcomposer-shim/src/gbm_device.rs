//! GBM device implementation backed by Android gralloc
//!
//! This provides GBM-compatible buffer allocation using Android's gralloc HAL.
//! Applications can use this as a drop-in replacement for libgbm.

use crate::drm_device::HwcDrmDevice;
use crate::ffi::{self, *};
use crate::{Error, Result};
use std::os::raw::c_void;
use std::ptr;
use std::sync::Arc;
use tracing::{debug, error, info, warn};

/// GBM buffer format (subset of common formats)
/// These are DRM fourcc codes
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

    /// Get bytes per pixel
    pub fn bpp(&self) -> u32 {
        match self {
            GbmFormat::Rgb565 => 2,
            _ => 4,
        }
    }
}

/// GBM buffer usage flags (compatible with standard GBM)
pub mod gbm_usage {
    pub const GBM_BO_USE_SCANOUT: u32 = 1 << 0;
    pub const GBM_BO_USE_CURSOR: u32 = 1 << 1;
    pub const GBM_BO_USE_RENDERING: u32 = 1 << 2;
    pub const GBM_BO_USE_WRITE: u32 = 1 << 3;
    pub const GBM_BO_USE_LINEAR: u32 = 1 << 4;
}

/// Convert GBM usage flags to gralloc usage
fn gbm_to_gralloc_usage(gbm_usage: u32) -> i32 {
    let mut usage: u64 = 0;

    if gbm_usage & gbm_usage::GBM_BO_USE_SCANOUT != 0 {
        usage |= GRALLOC_USAGE_HW_FB | GRALLOC_USAGE_HW_COMPOSER;
    }
    if gbm_usage & gbm_usage::GBM_BO_USE_RENDERING != 0 {
        usage |= GRALLOC_USAGE_HW_RENDER | GRALLOC_USAGE_HW_TEXTURE;
    }
    if gbm_usage & gbm_usage::GBM_BO_USE_WRITE != 0 {
        usage |= GRALLOC_USAGE_SW_WRITE_OFTEN;
    }
    if gbm_usage & gbm_usage::GBM_BO_USE_CURSOR != 0 {
        usage |= GRALLOC_USAGE_HW_FB;
    }

    // Default: at least allow HW composer access
    if usage == 0 {
        usage = GRALLOC_USAGE_HW_COMPOSER | GRALLOC_USAGE_HW_RENDER;
    }

    usage as i32
}

/// A buffer object allocated via gralloc
pub struct HwcGbmBo {
    handle: BufferHandleT,
    width: u32,
    height: u32,
    stride: u32,
    format: GbmFormat,
    was_allocated: bool, // true if we allocated, false if imported
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

    /// Get the native gralloc handle
    pub fn handle(&self) -> BufferHandleT {
        self.handle
    }

    /// Lock buffer for CPU write access
    /// Returns a pointer to the buffer data
    pub fn map(&self) -> Result<*mut c_void> {
        if self.handle.is_null() {
            return Err(Error::Gralloc("Cannot map null buffer".into()));
        }

        let mut vaddr: *mut c_void = ptr::null_mut();
        let usage = (GRALLOC_USAGE_SW_WRITE_OFTEN | GRALLOC_USAGE_SW_READ_OFTEN) as i32;

        let ret = unsafe {
            hybris_gralloc_lock(
                self.handle,
                usage,
                0,
                0,
                self.width as i32,
                self.height as i32,
                &mut vaddr,
            )
        };

        if ret != 0 {
            return Err(Error::Gralloc(format!(
                "Failed to lock buffer: {}",
                ret
            )));
        }

        Ok(vaddr)
    }

    /// Unlock buffer after CPU access
    pub fn unmap(&self) -> Result<()> {
        if self.handle.is_null() {
            return Ok(());
        }

        let ret = unsafe { hybris_gralloc_unlock(self.handle) };
        if ret != 0 {
            return Err(Error::Gralloc(format!(
                "Failed to unlock buffer: {}",
                ret
            )));
        }

        Ok(())
    }
}

impl Drop for HwcGbmBo {
    fn drop(&mut self) {
        if !self.handle.is_null() {
            debug!("Releasing gralloc buffer");
            let was_alloc = if self.was_allocated { 1 } else { 0 };
            let ret = unsafe { hybris_gralloc_release(self.handle, was_alloc) };
            if ret != 0 {
                warn!("Failed to release gralloc buffer: {}", ret);
            }
        }
    }
}

/// GBM surface for rendering (manages a set of buffers)
pub struct HwcGbmSurface {
    device: Arc<HwcGbmDevice>,
    width: u32,
    height: u32,
    format: GbmFormat,
    usage: u32,
    buffers: Vec<HwcGbmBo>,
    current_buffer: usize,
}

impl HwcGbmSurface {
    /// Lock the front buffer for scanout
    pub fn lock_front_buffer(&mut self) -> Result<&HwcGbmBo> {
        if self.buffers.is_empty() {
            return Err(Error::Gralloc("No buffers in surface".into()));
        }
        let buffer = &self.buffers[self.current_buffer];
        self.current_buffer = (self.current_buffer + 1) % self.buffers.len();
        Ok(buffer)
    }

    /// Get surface dimensions
    pub fn dimensions(&self) -> (u32, u32) {
        (self.width, self.height)
    }

    /// Get surface format
    pub fn format(&self) -> GbmFormat {
        self.format
    }
}

/// GBM device backed by Android gralloc
pub struct HwcGbmDevice {
    drm_device: Arc<HwcDrmDevice>,
    initialized: bool,
}

impl HwcGbmDevice {
    /// Create a new GBM device from a DRM device
    /// Note: gralloc must be initialized before calling this
    pub fn new(drm_device: Arc<HwcDrmDevice>) -> Result<Self> {
        info!("Creating HwcGbmDevice backed by gralloc");

        Ok(Self {
            drm_device,
            initialized: true,
        })
    }

    /// Allocate a buffer object
    pub fn create_bo(
        &self,
        width: u32,
        height: u32,
        format: GbmFormat,
        usage: u32,
    ) -> Result<HwcGbmBo> {
        if !self.initialized {
            return Err(Error::Gralloc("GBM device not initialized".into()));
        }

        info!(
            "Allocating gralloc buffer {}x{} format {:?}",
            width, height, format
        );

        let hal_format = format.to_hal_format();
        let gralloc_usage = gbm_to_gralloc_usage(usage);

        let mut handle: BufferHandleT = ptr::null_mut();
        let mut stride: u32 = 0;

        let ret = unsafe {
            hybris_gralloc_allocate(
                width as i32,
                height as i32,
                hal_format,
                gralloc_usage,
                &mut handle,
                &mut stride,
            )
        };

        if ret != 0 || handle.is_null() {
            error!("Failed to allocate gralloc buffer: ret={}", ret);
            return Err(Error::Gralloc(format!(
                "gralloc_allocate failed: {}",
                ret
            )));
        }

        info!(
            "Allocated gralloc buffer: handle={:p}, stride={}",
            handle, stride
        );

        Ok(HwcGbmBo {
            handle,
            width,
            height,
            stride,
            format,
            was_allocated: true,
        })
    }

    /// Create a surface for rendering (with multiple buffers)
    pub fn create_surface(
        self: &Arc<Self>,
        width: u32,
        height: u32,
        format: GbmFormat,
        usage: u32,
    ) -> Result<HwcGbmSurface> {
        info!("Creating GBM surface {}x{} with triple buffering", width, height);

        // Create triple-buffered surface
        let mut buffers = Vec::with_capacity(3);
        for i in 0..3 {
            match self.create_bo(width, height, format, usage) {
                Ok(bo) => buffers.push(bo),
                Err(e) => {
                    error!("Failed to allocate buffer {} for surface: {}", i, e);
                    return Err(e);
                }
            }
        }

        Ok(HwcGbmSurface {
            device: Arc::clone(self),
            width,
            height,
            format,
            usage,
            buffers,
            current_buffer: 0,
        })
    }

    /// Get the underlying DRM device
    pub fn drm_device(&self) -> &Arc<HwcDrmDevice> {
        &self.drm_device
    }
}

impl Drop for HwcGbmDevice {
    fn drop(&mut self) {
        debug!("Closing GBM device");
        // Buffers will be freed when dropped
    }
}

unsafe impl Send for HwcGbmDevice {}
unsafe impl Sync for HwcGbmDevice {}
unsafe impl Send for HwcGbmBo {}
unsafe impl Sync for HwcGbmBo {}
