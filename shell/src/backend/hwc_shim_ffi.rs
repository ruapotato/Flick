//! FFI bindings for the flick_hwc shim library
//!
//! These bindings call into our C shim (libflick_hwc) which wraps
//! all the hwcomposer complexity.

use std::ffi::{c_void, CStr};
use std::os::raw::{c_char, c_int};

/// Opaque context handle from the C shim
#[repr(C)]
pub struct FlickHwcContext {
    _opaque: [u8; 0],
}

/// Display information from hwcomposer
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct FlickDisplayInfo {
    pub width: i32,
    pub height: i32,
    pub physical_width: i32,
    pub physical_height: i32,
    pub vsync_period_ns: i64,
    pub refresh_rate: f32,
    pub dpi_x: f32,
    pub dpi_y: f32,
}

/// Vsync callback function type
pub type FlickVsyncCallback = Option<unsafe extern "C" fn(user_data: *mut c_void, timestamp_ns: i64)>;

#[link(name = "flick_hwc")]
extern "C" {
    /// Initialize the hwcomposer subsystem
    pub fn flick_hwc_init() -> *mut FlickHwcContext;

    /// Get display information
    pub fn flick_hwc_get_display_info(
        ctx: *mut FlickHwcContext,
        info: *mut FlickDisplayInfo,
    ) -> c_int;

    /// Get native window pointer for EGL
    pub fn flick_hwc_get_native_window(ctx: *mut FlickHwcContext) -> *mut c_void;

    /// Set display power mode
    pub fn flick_hwc_set_power(ctx: *mut FlickHwcContext, on: bool) -> c_int;

    /// Enable/disable vsync events
    pub fn flick_hwc_set_vsync_enabled(ctx: *mut FlickHwcContext, enabled: bool) -> c_int;

    /// Set vsync callback
    pub fn flick_hwc_set_vsync_callback(
        ctx: *mut FlickHwcContext,
        callback: FlickVsyncCallback,
        user_data: *mut c_void,
    ) -> c_int;

    /// Get frame statistics
    pub fn flick_hwc_get_stats(
        ctx: *mut FlickHwcContext,
        out_frame_count: *mut u32,
        out_error_count: *mut u32,
    ) -> c_int;

    /// Try to unblank the display
    pub fn flick_hwc_unblank_display();

    /// Destroy the context
    pub fn flick_hwc_destroy(ctx: *mut FlickHwcContext);

    /// Get last error message
    pub fn flick_hwc_get_error() -> *const c_char;
}

/// Safe wrapper around the hwc shim context
pub struct HwcContext {
    ctx: *mut FlickHwcContext,
}

// The context can be sent between threads (hwcomposer handles synchronization)
unsafe impl Send for HwcContext {}

impl HwcContext {
    /// Initialize hwcomposer and create context
    pub fn new() -> Result<Self, String> {
        let ctx = unsafe { flick_hwc_init() };
        if ctx.is_null() {
            let err = unsafe { flick_hwc_get_error() };
            let msg = if err.is_null() {
                "unknown error".to_string()
            } else {
                unsafe { CStr::from_ptr(err) }
                    .to_string_lossy()
                    .into_owned()
            };
            return Err(msg);
        }
        Ok(Self { ctx })
    }

    /// Get display information
    pub fn get_display_info(&self) -> Result<FlickDisplayInfo, String> {
        let mut info = FlickDisplayInfo::default();
        let ret = unsafe { flick_hwc_get_display_info(self.ctx, &mut info) };
        if ret != 0 {
            return Err(self.get_error_string());
        }
        Ok(info)
    }

    /// Get native window pointer for EGL
    ///
    /// The returned pointer can be cast to EGLNativeWindowType
    pub fn get_native_window(&self) -> *mut c_void {
        unsafe { flick_hwc_get_native_window(self.ctx) }
    }

    /// Set display power mode
    pub fn set_power(&self, on: bool) -> Result<(), String> {
        let ret = unsafe { flick_hwc_set_power(self.ctx, on) };
        if ret != 0 {
            return Err(self.get_error_string());
        }
        Ok(())
    }

    /// Enable/disable vsync events
    pub fn set_vsync_enabled(&self, enabled: bool) -> Result<(), String> {
        let ret = unsafe { flick_hwc_set_vsync_enabled(self.ctx, enabled) };
        if ret != 0 {
            return Err(self.get_error_string());
        }
        Ok(())
    }

    /// Get frame statistics
    pub fn get_stats(&self) -> (u32, u32) {
        let mut frame_count = 0u32;
        let mut error_count = 0u32;
        unsafe {
            flick_hwc_get_stats(self.ctx, &mut frame_count, &mut error_count);
        }
        (frame_count, error_count)
    }

    /// Get raw context pointer (for advanced use)
    pub fn as_ptr(&self) -> *mut FlickHwcContext {
        self.ctx
    }

    fn get_error_string(&self) -> String {
        let err = unsafe { flick_hwc_get_error() };
        if err.is_null() {
            "unknown error".to_string()
        } else {
            unsafe { CStr::from_ptr(err) }
                .to_string_lossy()
                .into_owned()
        }
    }
}

impl Drop for HwcContext {
    fn drop(&mut self) {
        if !self.ctx.is_null() {
            unsafe { flick_hwc_destroy(self.ctx) };
            self.ctx = std::ptr::null_mut();
        }
    }
}

/// Try to unblank the display via sysfs
pub fn unblank_display() {
    unsafe { flick_hwc_unblank_display() };
}
