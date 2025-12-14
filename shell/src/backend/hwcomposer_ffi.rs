//! FFI bindings for libhybris hwcomposer
//!
//! These bindings provide access to Android's hwcomposer HAL through libhybris,
//! enabling Wayland compositing on Droidian and other libhybris-based Linux systems.

#![allow(non_camel_case_types)]
#![allow(dead_code)]

use std::os::raw::{c_int, c_uint, c_void};

/// Opaque type representing an Android native window (ANativeWindow)
#[repr(C)]
pub struct ANativeWindow {
    _opaque: [u8; 0],
}

/// Opaque type representing an Android native window buffer (ANativeWindowBuffer)
#[repr(C)]
pub struct ANativeWindowBuffer {
    _opaque: [u8; 0],
}

/// Callback function type for buffer presentation
/// Called by HWCNativeWindow when a buffer is ready to be displayed
pub type HWCPresentCallback = Option<
    unsafe extern "C" fn(user_data: *mut c_void, window: *mut ANativeWindow, buffer: *mut ANativeWindowBuffer),
>;

// Android HAL pixel formats (from hardware/graphics.h)
pub mod hal_format {
    pub const HAL_PIXEL_FORMAT_RGBA_8888: u32 = 1;
    pub const HAL_PIXEL_FORMAT_RGBX_8888: u32 = 2;
    pub const HAL_PIXEL_FORMAT_RGB_888: u32 = 3;
    pub const HAL_PIXEL_FORMAT_RGB_565: u32 = 4;
    pub const HAL_PIXEL_FORMAT_BGRA_8888: u32 = 5;
}

#[link(name = "hybris-hwcomposerwindow")]
extern "C" {
    /// Create a new HWC ANativeWindow.
    ///
    /// The window can be cast to EGLNativeWindowType and used to create an EGLSurface.
    /// The specified present callback will be called when a new buffer is ready to be
    /// presented on screen.
    ///
    /// # Arguments
    /// * `width` - Width of the window in pixels
    /// * `height` - Height of the window in pixels
    /// * `format` - HAL pixel format (e.g., HAL_PIXEL_FORMAT_RGBA_8888)
    /// * `present` - Callback function called when buffer is ready
    /// * `cb_data` - User data passed to the callback
    ///
    /// # Returns
    /// Pointer to the native window on success, NULL on failure
    pub fn HWCNativeWindowCreate(
        width: c_uint,
        height: c_uint,
        format: c_uint,
        present: HWCPresentCallback,
        cb_data: *mut c_void,
    ) -> *mut ANativeWindow;

    /// Destroy a HWC ANativeWindow.
    ///
    /// Note: It's not necessary to call this after eglDestroyWindowSurface()
    /// with an EGLSurface backing a valid ANativeWindow - the window will
    /// be destroyed automatically.
    pub fn HWCNativeWindowDestroy(window: *mut ANativeWindow);

    /// Set the buffer count of a native window.
    ///
    /// The default buffer count is 2 (double buffering).
    ///
    /// # Returns
    /// 0 on success
    pub fn HWCNativeWindowSetBufferCount(window: *mut ANativeWindow, cnt: c_int) -> c_int;

    /// Get the current fence FD on a buffer.
    ///
    /// The buffer must be a buffer passed from the HWC layer through the present callback.
    pub fn HWCNativeBufferGetFence(buf: *mut ANativeWindowBuffer) -> c_int;

    /// Set the current fence FD on a buffer.
    ///
    /// The buffer must be a buffer passed from the HWC layer through the present callback.
    pub fn HWCNativeBufferSetFence(buf: *mut ANativeWindowBuffer, fd: c_int);
}

/// Safe wrapper around HWCNativeWindow
pub struct HwcNativeWindow {
    window: *mut ANativeWindow,
}

// ANativeWindow pointer can be sent between threads
unsafe impl Send for HwcNativeWindow {}

impl HwcNativeWindow {
    /// Create a new hwcomposer native window
    ///
    /// # Safety
    /// The present callback must be valid for the lifetime of this window.
    /// The callback_data pointer must remain valid for the lifetime of this window.
    pub unsafe fn new(
        width: u32,
        height: u32,
        format: u32,
        present: HWCPresentCallback,
        callback_data: *mut c_void,
    ) -> Option<Self> {
        let window = HWCNativeWindowCreate(
            width as c_uint,
            height as c_uint,
            format as c_uint,
            present,
            callback_data,
        );

        if window.is_null() {
            None
        } else {
            Some(Self { window })
        }
    }

    /// Get the raw ANativeWindow pointer for use with EGL
    ///
    /// This pointer can be cast to EGLNativeWindowType
    pub fn as_ptr(&self) -> *mut ANativeWindow {
        self.window
    }

    /// Set the buffer count (default is 2 for double buffering)
    pub fn set_buffer_count(&self, count: i32) -> Result<(), i32> {
        let result = unsafe { HWCNativeWindowSetBufferCount(self.window, count as c_int) };
        if result == 0 {
            Ok(())
        } else {
            Err(result)
        }
    }
}

impl Drop for HwcNativeWindow {
    fn drop(&mut self) {
        if !self.window.is_null() {
            unsafe {
                HWCNativeWindowDestroy(self.window);
            }
        }
    }
}

/// Helper to get fence from a buffer in the present callback
pub fn get_buffer_fence(buffer: *mut ANativeWindowBuffer) -> i32 {
    unsafe { HWCNativeBufferGetFence(buffer) as i32 }
}

/// Helper to set fence on a buffer in the present callback
pub fn set_buffer_fence(buffer: *mut ANativeWindowBuffer, fd: i32) {
    unsafe {
        HWCNativeBufferSetFence(buffer, fd as c_int);
    }
}
