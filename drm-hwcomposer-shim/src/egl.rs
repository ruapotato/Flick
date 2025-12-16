//! EGL integration for hwcomposer buffers
//!
//! This module provides EGL context creation and buffer sharing between
//! hwcomposer and OpenGL ES rendering.

use crate::ffi::{self, *};
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
    display: ffi::EGLDisplay,
    context: ffi::EGLContext,
    surface: ffi::EGLSurface,
    config: ffi::EGLConfig,
    gbm_device: Arc<HwcGbmDevice>,
}

/// EGL image handle for buffer sharing
pub struct HwcEglImage {
    image: *mut c_void,
    width: u32,
    height: u32,
}

impl HwcEglContext {
    /// Create a new EGL context from a GBM device
    pub fn new(gbm_device: Arc<HwcGbmDevice>, _config: EglConfig) -> Result<Self> {
        info!("Creating EGL context for hwcomposer");

        // The EGL context is managed by the hwcomposer/drm_device
        // This wrapper provides access to the underlying EGL resources

        Ok(Self {
            display: ffi::EGL_NO_DISPLAY,
            context: ffi::EGL_NO_CONTEXT,
            surface: ffi::EGL_NO_SURFACE,
            config: std::ptr::null_mut(),
            gbm_device,
        })
    }

    /// Initialize from existing EGL handles (from hwcomposer)
    pub fn from_handles(
        gbm_device: Arc<HwcGbmDevice>,
        display: ffi::EGLDisplay,
        context: ffi::EGLContext,
        surface: ffi::EGLSurface,
        config: ffi::EGLConfig,
    ) -> Self {
        Self {
            display,
            context,
            surface,
            config,
            gbm_device,
        }
    }

    /// Make this context current
    pub fn make_current(&self) -> Result<()> {
        debug!("Making EGL context current");

        if self.display == ffi::EGL_NO_DISPLAY {
            return Err(Error::Egl("No EGL display".into()));
        }

        if unsafe { eglMakeCurrent(self.display, self.surface, self.surface, self.context) }
            == ffi::EGL_FALSE
        {
            let err = unsafe { eglGetError() };
            return Err(Error::Egl(format!("eglMakeCurrent failed: 0x{:X}", err)));
        }

        Ok(())
    }

    /// Swap buffers (present to display)
    pub fn swap_buffers(&self) -> Result<()> {
        debug!("Swapping EGL buffers");

        if self.display == ffi::EGL_NO_DISPLAY {
            return Err(Error::Egl("No EGL display".into()));
        }

        if unsafe { eglSwapBuffers(self.display, self.surface) } == ffi::EGL_FALSE {
            let err = unsafe { eglGetError() };
            return Err(Error::Egl(format!("eglSwapBuffers failed: 0x{:X}", err)));
        }

        Ok(())
    }

    /// Create an EGL image from a GBM buffer object
    pub fn create_image(&self, bo: &HwcGbmBo) -> Result<HwcEglImage> {
        debug!(
            "Creating EGL image from buffer {}x{}",
            bo.width(),
            bo.height()
        );

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
        _format: u32,
        _modifier: u64,
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
    pub fn display(&self) -> ffi::EGLDisplay {
        self.display
    }

    /// Get the EGL context handle
    pub fn context(&self) -> ffi::EGLContext {
        self.context
    }

    /// Get the EGL surface handle
    pub fn surface(&self) -> ffi::EGLSurface {
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
    pub fn bind_as_texture(&self, _target: u32) -> Result<()> {
        debug!("Binding EGL image as texture");
        // glEGLImageTargetTexture2DOES(target, self.image)
        Ok(())
    }
}

impl Drop for HwcEglContext {
    fn drop(&mut self) {
        debug!("Destroying EGL context");
        // Note: The context is owned by hwcomposer, we don't destroy it here
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
