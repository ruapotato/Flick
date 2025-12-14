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

// ============================================================================
// HWC2 Compatibility Layer bindings
// These are needed to actually present frames to the display
// ============================================================================

/// Opaque type for HWC2 device
#[repr(C)]
pub struct hwc2_compat_device_t {
    _opaque: [u8; 0],
}

/// Opaque type for HWC2 display
#[repr(C)]
pub struct hwc2_compat_display_t {
    _opaque: [u8; 0],
}

/// Opaque type for HWC2 layer
#[repr(C)]
pub struct hwc2_compat_layer_t {
    _opaque: [u8; 0],
}

/// HWC2 power modes
pub mod hwc2_power_mode {
    pub const HWC2_POWER_MODE_OFF: i32 = 0;
    pub const HWC2_POWER_MODE_DOZE: i32 = 1;
    pub const HWC2_POWER_MODE_DOZE_SUSPEND: i32 = 3;
    pub const HWC2_POWER_MODE_ON: i32 = 2;
}

/// HWC2 error codes
pub type hwc2_error_t = i32;

/// Callback type for vsync events
pub type HWC2EventCallback = Option<
    unsafe extern "C" fn(callback_data: *mut c_void, display: u64, timestamp: i64),
>;

#[link(name = "hwc2")]
extern "C" {
    /// Create a new HWC2 device
    /// useVrComposer should typically be false
    pub fn hwc2_compat_device_new(use_vr_composer: bool) -> *mut hwc2_compat_device_t;

    /// Destroy HWC2 device
    pub fn hwc2_compat_device_destroy(device: *mut hwc2_compat_device_t);

    /// Get display by ID (typically 0 for primary display)
    pub fn hwc2_compat_device_get_display_by_id(
        device: *mut hwc2_compat_device_t,
        id: u64,
    ) -> *mut hwc2_compat_display_t;

    /// Register callbacks (vsync, hotplug, etc.)
    pub fn hwc2_compat_device_register_callback(
        device: *mut hwc2_compat_device_t,
        callback: HWC2EventCallback,
        data: *mut c_void,
    );

    /// Set display power mode
    pub fn hwc2_compat_display_set_power_mode(
        display: *mut hwc2_compat_display_t,
        mode: i32,
    ) -> hwc2_error_t;

    /// Set vsync enabled state
    pub fn hwc2_compat_display_set_vsync_enabled(
        display: *mut hwc2_compat_display_t,
        enabled: i32,
    ) -> hwc2_error_t;

    /// Get display configs count
    pub fn hwc2_compat_display_get_configs(
        display: *mut hwc2_compat_display_t,
        out_num_configs: *mut u32,
    ) -> hwc2_error_t;

    /// Get active display config
    pub fn hwc2_compat_display_get_active_config(
        display: *mut hwc2_compat_display_t,
        out_config: *mut u32,
    ) -> hwc2_error_t;

    /// Accept display changes after validate
    pub fn hwc2_compat_display_accept_changes(
        display: *mut hwc2_compat_display_t,
    ) -> hwc2_error_t;

    /// Create a layer
    pub fn hwc2_compat_display_create_layer(
        display: *mut hwc2_compat_display_t,
        out_layer: *mut *mut hwc2_compat_layer_t,
    ) -> hwc2_error_t;

    /// Destroy a layer
    pub fn hwc2_compat_display_destroy_layer(
        display: *mut hwc2_compat_display_t,
        layer: *mut hwc2_compat_layer_t,
    ) -> hwc2_error_t;

    /// Set client target (the buffer we're rendering to)
    pub fn hwc2_compat_display_set_client_target(
        display: *mut hwc2_compat_display_t,
        target: *mut ANativeWindowBuffer,
        acquire_fence: i32,
        dataspace: i32,
    ) -> hwc2_error_t;

    /// Validate display composition
    pub fn hwc2_compat_display_validate(
        display: *mut hwc2_compat_display_t,
        out_num_types: *mut u32,
        out_num_requests: *mut u32,
    ) -> hwc2_error_t;

    /// Present the display (actually show the frame!)
    pub fn hwc2_compat_display_present(
        display: *mut hwc2_compat_display_t,
        out_present_fence: *mut i32,
    ) -> hwc2_error_t;

    /// Get release fences after present
    pub fn hwc2_compat_display_get_release_fences(
        display: *mut hwc2_compat_display_t,
        out_num_elements: *mut u32,
        out_layers: *mut *mut hwc2_compat_layer_t,
        out_fences: *mut i32,
    ) -> hwc2_error_t;
}

/// Safe wrapper for HWC2 device
pub struct Hwc2Device {
    device: *mut hwc2_compat_device_t,
}

unsafe impl Send for Hwc2Device {}

impl Hwc2Device {
    /// Create a new HWC2 device
    pub fn new() -> Option<Self> {
        let device = unsafe { hwc2_compat_device_new(false) };
        if device.is_null() {
            None
        } else {
            Some(Self { device })
        }
    }

    /// Get primary display (ID 0)
    pub fn get_primary_display(&self) -> Option<Hwc2Display> {
        let display = unsafe { hwc2_compat_device_get_display_by_id(self.device, 0) };
        if display.is_null() {
            None
        } else {
            Some(Hwc2Display { display })
        }
    }
}

impl Drop for Hwc2Device {
    fn drop(&mut self) {
        if !self.device.is_null() {
            unsafe { hwc2_compat_device_destroy(self.device) };
        }
    }
}

/// Safe wrapper for HWC2 display
pub struct Hwc2Display {
    display: *mut hwc2_compat_display_t,
}

impl Hwc2Display {
    /// Set power mode (on/off)
    pub fn set_power_mode(&self, on: bool) -> Result<(), hwc2_error_t> {
        let mode = if on {
            hwc2_power_mode::HWC2_POWER_MODE_ON
        } else {
            hwc2_power_mode::HWC2_POWER_MODE_OFF
        };
        let err = unsafe { hwc2_compat_display_set_power_mode(self.display, mode) };
        if err == 0 {
            Ok(())
        } else {
            Err(err)
        }
    }

    /// Present the frame
    pub fn present(&self) -> Result<i32, hwc2_error_t> {
        let mut present_fence: i32 = -1;
        let err = unsafe { hwc2_compat_display_present(self.display, &mut present_fence) };
        if err == 0 {
            Ok(present_fence)
        } else {
            Err(err)
        }
    }

    /// Validate display
    pub fn validate(&self) -> Result<(u32, u32), hwc2_error_t> {
        let mut num_types: u32 = 0;
        let mut num_requests: u32 = 0;
        let err = unsafe {
            hwc2_compat_display_validate(self.display, &mut num_types, &mut num_requests)
        };
        if err == 0 || err == 3 /* HAS_CHANGES */ {
            Ok((num_types, num_requests))
        } else {
            Err(err)
        }
    }

    /// Accept changes after validate
    pub fn accept_changes(&self) -> Result<(), hwc2_error_t> {
        let err = unsafe { hwc2_compat_display_accept_changes(self.display) };
        if err == 0 {
            Ok(())
        } else {
            Err(err)
        }
    }

    /// Set client target buffer
    pub fn set_client_target(
        &self,
        buffer: *mut ANativeWindowBuffer,
        acquire_fence: i32,
    ) -> Result<(), hwc2_error_t> {
        let err = unsafe {
            hwc2_compat_display_set_client_target(self.display, buffer, acquire_fence, 0)
        };
        if err == 0 {
            Ok(())
        } else {
            Err(err)
        }
    }
}
