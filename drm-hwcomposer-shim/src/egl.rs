//! EGL integration for hwcomposer buffers
//!
//! This module provides EGL context creation and buffer sharing between
//! hwcomposer and OpenGL ES rendering.

use crate::gbm_device::{HwcGbmBo, HwcGbmDevice};
use crate::{Error, Result};
use std::os::raw::c_void;
use std::sync::Arc;
use tracing::{debug, info, warn};

/// EGL configuration attributes
#[derive(Debug, Clone)]
pub struct EglConfig {
    pub red_size: i32,
    pub green_size: i32,
    pub blue_size: i32,
    pub alpha_size: i32,
    pub depth_size: i32,
    pub stencil_size: i32,
    pub samples: i32,
}

impl Default for EglConfig {
    fn default() -> Self {
        Self {
            red_size: 8,
            green_size: 8,
            blue_size: 8,
            alpha_size: 8,
            depth_size: 0,
            stencil_size: 0,
            samples: 0,
        }
    }
}

/// EGL context wrapper for hwcomposer
pub struct HwcEglContext {
    display: *mut c_void,
    context: *mut c_void,
    surface: *mut c_void,
    config: *mut c_void,
    gbm_device: Arc<HwcGbmDevice>,
}

/// EGL image handle for buffer sharing
pub struct HwcEglImage {
    image: *mut c_void,
    width: u32,
    height: u32,
}

// EGL constants (from EGL headers)
const EGL_NO_DISPLAY: *mut c_void = std::ptr::null_mut();
const EGL_NO_CONTEXT: *mut c_void = std::ptr::null_mut();
const EGL_NO_SURFACE: *mut c_void = std::ptr::null_mut();

impl HwcEglContext {
    /// Create a new EGL context from a GBM device
    pub fn new(gbm_device: Arc<HwcGbmDevice>, config: EglConfig) -> Result<Self> {
        info!("Creating EGL context for hwcomposer");

        // In a full implementation:
        // 1. Get EGL display from hwcomposer's native display
        // 2. Initialize EGL
        // 3. Choose config
        // 4. Create context
        // 5. Create window surface

        Ok(Self {
            display: EGL_NO_DISPLAY,
            context: EGL_NO_CONTEXT,
            surface: EGL_NO_SURFACE,
            config: std::ptr::null_mut(),
            gbm_device,
        })
    }

    /// Make this context current
    pub fn make_current(&self) -> Result<()> {
        debug!("Making EGL context current");
        // eglMakeCurrent(display, surface, surface, context)
        Ok(())
    }

    /// Swap buffers (present to display)
    pub fn swap_buffers(&self) -> Result<()> {
        debug!("Swapping EGL buffers");
        // eglSwapBuffers(display, surface)
        Ok(())
    }

    /// Create an EGL image from a GBM buffer object
    pub fn create_image(&self, bo: &HwcGbmBo) -> Result<HwcEglImage> {
        debug!("Creating EGL image from buffer {}x{}", bo.width(), bo.height());

        // In a full implementation:
        // 1. Get DMA-BUF fd from the bo
        // 2. Create EGLImage using eglCreateImageKHR with EGL_LINUX_DMA_BUF_EXT

        Ok(HwcEglImage {
            image: std::ptr::null_mut(),
            width: bo.width(),
            height: bo.height(),
        })
    }

    /// Import an external DMA-BUF as an EGL image
    pub fn import_dmabuf(
        &self,
        fd: i32,
        width: u32,
        height: u32,
        format: u32,
        modifier: u64,
    ) -> Result<HwcEglImage> {
        debug!("Importing DMA-BUF fd={} as EGL image", fd);

        // eglCreateImageKHR with:
        // - EGL_LINUX_DMA_BUF_EXT target
        // - EGL_WIDTH, EGL_HEIGHT
        // - EGL_LINUX_DRM_FOURCC_EXT
        // - EGL_DMA_BUF_PLANE0_FD_EXT
        // - EGL_DMA_BUF_PLANE0_OFFSET_EXT
        // - EGL_DMA_BUF_PLANE0_PITCH_EXT
        // - EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT (if modifier != INVALID)

        Ok(HwcEglImage {
            image: std::ptr::null_mut(),
            width,
            height,
        })
    }

    /// Get the EGL display handle
    pub fn display(&self) -> *mut c_void {
        self.display
    }

    /// Get the EGL context handle
    pub fn context(&self) -> *mut c_void {
        self.context
    }

    /// Get the EGL surface handle
    pub fn surface(&self) -> *mut c_void {
        self.surface
    }

    /// Check if an EGL extension is supported
    pub fn has_extension(&self, name: &str) -> bool {
        // Query EGL extensions
        // Real implementation would call eglQueryString(display, EGL_EXTENSIONS)
        debug!("Checking for EGL extension: {}", name);
        false
    }

    /// Get the GBM device
    pub fn gbm_device(&self) -> &Arc<HwcGbmDevice> {
        &self.gbm_device
    }
}

impl HwcEglImage {
    /// Get the raw EGL image handle
    pub fn handle(&self) -> *mut c_void {
        self.image
    }

    /// Get image dimensions
    pub fn dimensions(&self) -> (u32, u32) {
        (self.width, self.height)
    }

    /// Bind this image as a texture (via glEGLImageTargetTexture2DOES)
    pub fn bind_as_texture(&self, target: u32) -> Result<()> {
        debug!("Binding EGL image as texture");
        // glEGLImageTargetTexture2DOES(target, self.image)
        Ok(())
    }
}

impl Drop for HwcEglContext {
    fn drop(&mut self) {
        debug!("Destroying EGL context");
        // eglDestroyContext
        // eglDestroySurface
        // eglTerminate
    }
}

impl Drop for HwcEglImage {
    fn drop(&mut self) {
        debug!("Destroying EGL image");
        // eglDestroyImageKHR
    }
}

unsafe impl Send for HwcEglContext {}
unsafe impl Sync for HwcEglContext {}
unsafe impl Send for HwcEglImage {}
