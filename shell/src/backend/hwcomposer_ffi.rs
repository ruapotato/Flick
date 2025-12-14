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

/// Opaque type for HWC2 output fences
#[repr(C)]
pub struct hwc2_compat_out_fences_t {
    _opaque: [u8; 0],
}

/// HWC2 display ID type
pub type hwc2_display_t = u64;

/// HWC2 config ID type
pub type hwc2_config_t = u32;

/// HWC2 power modes
pub mod hwc2_power_mode {
    pub const HWC2_POWER_MODE_OFF: i32 = 0;
    pub const HWC2_POWER_MODE_DOZE: i32 = 1;
    pub const HWC2_POWER_MODE_ON: i32 = 2;
    pub const HWC2_POWER_MODE_DOZE_SUSPEND: i32 = 3;
}

/// HWC2 composition types
pub mod hwc2_composition {
    pub const HWC2_COMPOSITION_INVALID: i32 = 0;
    pub const HWC2_COMPOSITION_CLIENT: i32 = 1;
    pub const HWC2_COMPOSITION_DEVICE: i32 = 2;
    pub const HWC2_COMPOSITION_SOLID_COLOR: i32 = 3;
    pub const HWC2_COMPOSITION_CURSOR: i32 = 4;
    pub const HWC2_COMPOSITION_SIDEBAND: i32 = 5;
}

/// HWC2 blend modes
pub mod hwc2_blend_mode {
    pub const HWC2_BLEND_MODE_INVALID: i32 = 0;
    pub const HWC2_BLEND_MODE_NONE: i32 = 1;
    pub const HWC2_BLEND_MODE_PREMULTIPLIED: i32 = 2;
    pub const HWC2_BLEND_MODE_COVERAGE: i32 = 3;
}

/// HWC2 error codes
pub type hwc2_error_t = i32;

/// Display configuration returned by get_active_config
#[repr(C)]
pub struct HWC2DisplayConfig {
    pub id: hwc2_config_t,
    pub display: hwc2_display_t,
    pub width: i32,
    pub height: i32,
    pub vsync_period: i64,
    pub dpi_x: f32,
    pub dpi_y: f32,
}

/// Vsync callback
pub type OnVsyncReceivedCallback = Option<
    unsafe extern "C" fn(
        listener: *mut HWC2EventListener,
        sequence_id: i32,
        display: hwc2_display_t,
        timestamp: i64,
    ),
>;

/// Hotplug callback
pub type OnHotplugReceivedCallback = Option<
    unsafe extern "C" fn(
        listener: *mut HWC2EventListener,
        sequence_id: i32,
        display: hwc2_display_t,
        connected: bool,
        primary_display: bool,
    ),
>;

/// Refresh callback
pub type OnRefreshReceivedCallback = Option<
    unsafe extern "C" fn(
        listener: *mut HWC2EventListener,
        sequence_id: i32,
        display: hwc2_display_t,
    ),
>;

/// Event listener struct for HWC2 callbacks
#[repr(C)]
pub struct HWC2EventListener {
    pub on_vsync_received: OnVsyncReceivedCallback,
    pub on_hotplug_received: OnHotplugReceivedCallback,
    pub on_refresh_received: OnRefreshReceivedCallback,
}

#[link(name = "hwc2")]
extern "C" {
    /// Initialize HWC2 subsystem - may need to be called before hwc2_compat_device_new
    pub fn hybris_hwc2_initialize();

    /// Create a new HWC2 device
    /// useVrComposer should typically be false
    pub fn hwc2_compat_device_new(use_vr_composer: bool) -> *mut hwc2_compat_device_t;

    /// Register callbacks (vsync, hotplug, etc.)
    pub fn hwc2_compat_device_register_callback(
        device: *mut hwc2_compat_device_t,
        listener: *mut HWC2EventListener,
        composer_sequence_id: c_int,
    );

    /// Handle hotplug event
    pub fn hwc2_compat_device_on_hotplug(
        device: *mut hwc2_compat_device_t,
        display_id: hwc2_display_t,
        connected: bool,
    );

    /// Get display by ID (typically 0 for primary display)
    pub fn hwc2_compat_device_get_display_by_id(
        device: *mut hwc2_compat_device_t,
        id: hwc2_display_t,
    ) -> *mut hwc2_compat_display_t;

    /// Destroy a display
    pub fn hwc2_compat_device_destroy_display(
        device: *mut hwc2_compat_device_t,
        display: *mut hwc2_compat_display_t,
    );

    /// Get active display config - returns pointer to config struct
    pub fn hwc2_compat_display_get_active_config(
        display: *mut hwc2_compat_display_t,
    ) -> *mut HWC2DisplayConfig;

    /// Accept display changes after validate
    pub fn hwc2_compat_display_accept_changes(
        display: *mut hwc2_compat_display_t,
    ) -> hwc2_error_t;

    /// Create a layer - returns layer pointer directly
    pub fn hwc2_compat_display_create_layer(
        display: *mut hwc2_compat_display_t,
    ) -> *mut hwc2_compat_layer_t;

    /// Destroy a layer
    pub fn hwc2_compat_display_destroy_layer(
        display: *mut hwc2_compat_display_t,
        layer: *mut hwc2_compat_layer_t,
    );

    /// Get release fences after present
    pub fn hwc2_compat_display_get_release_fences(
        display: *mut hwc2_compat_display_t,
        out_fences: *mut *mut hwc2_compat_out_fences_t,
    ) -> hwc2_error_t;

    /// Present the display (actually show the frame!)
    pub fn hwc2_compat_display_present(
        display: *mut hwc2_compat_display_t,
        out_present_fence: *mut i32,
    ) -> hwc2_error_t;

    /// Set client target (the buffer we're rendering to)
    /// Note: slot parameter is used for buffer queue management
    pub fn hwc2_compat_display_set_client_target(
        display: *mut hwc2_compat_display_t,
        slot: u32,
        buffer: *mut ANativeWindowBuffer,
        acquire_fence: i32,
        dataspace: i32,
    ) -> hwc2_error_t;

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

    /// Validate display composition
    pub fn hwc2_compat_display_validate(
        display: *mut hwc2_compat_display_t,
        out_num_types: *mut u32,
        out_num_requests: *mut u32,
    ) -> hwc2_error_t;

    /// Present or validate in one call
    pub fn hwc2_compat_display_present_or_validate(
        display: *mut hwc2_compat_display_t,
        out_num_types: *mut u32,
        out_num_requests: *mut u32,
        out_present_fence: *mut i32,
        out_state: *mut u32,
    ) -> hwc2_error_t;

    // Layer functions
    pub fn hwc2_compat_layer_set_buffer(
        layer: *mut hwc2_compat_layer_t,
        slot: u32,
        buffer: *mut ANativeWindowBuffer,
        acquire_fence: i32,
    ) -> hwc2_error_t;

    pub fn hwc2_compat_layer_set_blend_mode(
        layer: *mut hwc2_compat_layer_t,
        mode: i32,
    ) -> hwc2_error_t;

    pub fn hwc2_compat_layer_set_composition_type(
        layer: *mut hwc2_compat_layer_t,
        comp_type: i32,
    ) -> hwc2_error_t;

    pub fn hwc2_compat_layer_set_display_frame(
        layer: *mut hwc2_compat_layer_t,
        left: i32,
        top: i32,
        right: i32,
        bottom: i32,
    ) -> hwc2_error_t;

    pub fn hwc2_compat_layer_set_source_crop(
        layer: *mut hwc2_compat_layer_t,
        left: f32,
        top: f32,
        right: f32,
        bottom: f32,
    ) -> hwc2_error_t;

    pub fn hwc2_compat_layer_set_plane_alpha(
        layer: *mut hwc2_compat_layer_t,
        alpha: f32,
    ) -> hwc2_error_t;

    pub fn hwc2_compat_layer_set_visible_region(
        layer: *mut hwc2_compat_layer_t,
        left: i32,
        top: i32,
        right: i32,
        bottom: i32,
    ) -> hwc2_error_t;

    /// Get fence from output fences
    pub fn hwc2_compat_out_fences_get_fence(
        fences: *mut hwc2_compat_out_fences_t,
        layer: *mut hwc2_compat_layer_t,
    ) -> i32;

    /// Destroy output fences
    pub fn hwc2_compat_out_fences_destroy(fences: *mut hwc2_compat_out_fences_t);
}

/// Initialize the HWC2 subsystem
/// Call this before creating any HWC2 devices
pub fn hwc2_initialize() {
    unsafe { hybris_hwc2_initialize() };
}

/// Safe wrapper for HWC2 device
pub struct Hwc2Device {
    device: *mut hwc2_compat_device_t,
}

unsafe impl Send for Hwc2Device {}

impl Hwc2Device {
    /// Create a new HWC2 device
    /// Note: Call hwc2_initialize() before this if needed
    pub fn new() -> Option<Self> {
        let device = unsafe { hwc2_compat_device_new(false) };
        if device.is_null() {
            None
        } else {
            Some(Self { device })
        }
    }

    /// Get raw device pointer
    pub fn as_ptr(&self) -> *mut hwc2_compat_device_t {
        self.device
    }

    /// Get display by ID
    pub fn get_display_by_id(&self, id: u64) -> Option<Hwc2Display> {
        let display = unsafe { hwc2_compat_device_get_display_by_id(self.device, id) };
        if display.is_null() {
            None
        } else {
            Some(Hwc2Display { display })
        }
    }

    /// Get primary display (ID 0)
    pub fn get_primary_display(&self) -> Option<Hwc2Display> {
        self.get_display_by_id(0)
    }

    /// Trigger hotplug event for display
    pub fn on_hotplug(&self, display_id: u64, connected: bool) {
        unsafe { hwc2_compat_device_on_hotplug(self.device, display_id, connected) };
    }

    /// Register event listener
    pub fn register_callback(&self, listener: *mut HWC2EventListener, sequence_id: i32) {
        unsafe { hwc2_compat_device_register_callback(self.device, listener, sequence_id) };
    }
}

// Note: HWC2 device doesn't have a destroy function - it's a singleton
// managed by the hwc2 library internally

/// Safe wrapper for HWC2 display
pub struct Hwc2Display {
    display: *mut hwc2_compat_display_t,
}

impl Hwc2Display {
    /// Get raw display pointer
    pub fn as_ptr(&self) -> *mut hwc2_compat_display_t {
        self.display
    }

    /// Get active display configuration
    pub fn get_active_config(&self) -> Option<&HWC2DisplayConfig> {
        let config = unsafe { hwc2_compat_display_get_active_config(self.display) };
        if config.is_null() {
            None
        } else {
            Some(unsafe { &*config })
        }
    }

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

    /// Create a layer
    pub fn create_layer(&self) -> Option<Hwc2Layer> {
        let layer = unsafe { hwc2_compat_display_create_layer(self.display) };
        if layer.is_null() {
            None
        } else {
            Some(Hwc2Layer { layer })
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
        slot: u32,
        buffer: *mut ANativeWindowBuffer,
        acquire_fence: i32,
    ) -> Result<(), hwc2_error_t> {
        let err = unsafe {
            hwc2_compat_display_set_client_target(self.display, slot, buffer, acquire_fence, 0)
        };
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
}

/// Safe wrapper for HWC2 layer
pub struct Hwc2Layer {
    layer: *mut hwc2_compat_layer_t,
}

impl Hwc2Layer {
    /// Get raw layer pointer
    pub fn as_ptr(&self) -> *mut hwc2_compat_layer_t {
        self.layer
    }

    /// Set layer buffer
    pub fn set_buffer(
        &self,
        slot: u32,
        buffer: *mut ANativeWindowBuffer,
        acquire_fence: i32,
    ) -> Result<(), hwc2_error_t> {
        let err = unsafe { hwc2_compat_layer_set_buffer(self.layer, slot, buffer, acquire_fence) };
        if err == 0 {
            Ok(())
        } else {
            Err(err)
        }
    }

    /// Set composition type (CLIENT, DEVICE, etc.)
    pub fn set_composition_type(&self, comp_type: i32) -> Result<(), hwc2_error_t> {
        let err = unsafe { hwc2_compat_layer_set_composition_type(self.layer, comp_type) };
        if err == 0 {
            Ok(())
        } else {
            Err(err)
        }
    }

    /// Set blend mode
    pub fn set_blend_mode(&self, mode: i32) -> Result<(), hwc2_error_t> {
        let err = unsafe { hwc2_compat_layer_set_blend_mode(self.layer, mode) };
        if err == 0 {
            Ok(())
        } else {
            Err(err)
        }
    }

    /// Set display frame (where on screen)
    pub fn set_display_frame(&self, left: i32, top: i32, right: i32, bottom: i32) -> Result<(), hwc2_error_t> {
        let err = unsafe { hwc2_compat_layer_set_display_frame(self.layer, left, top, right, bottom) };
        if err == 0 {
            Ok(())
        } else {
            Err(err)
        }
    }

    /// Set source crop (portion of buffer to display)
    pub fn set_source_crop(&self, left: f32, top: f32, right: f32, bottom: f32) -> Result<(), hwc2_error_t> {
        let err = unsafe { hwc2_compat_layer_set_source_crop(self.layer, left, top, right, bottom) };
        if err == 0 {
            Ok(())
        } else {
            Err(err)
        }
    }

    /// Set plane alpha
    pub fn set_plane_alpha(&self, alpha: f32) -> Result<(), hwc2_error_t> {
        let err = unsafe { hwc2_compat_layer_set_plane_alpha(self.layer, alpha) };
        if err == 0 {
            Ok(())
        } else {
            Err(err)
        }
    }

    /// Set visible region
    pub fn set_visible_region(&self, left: i32, top: i32, right: i32, bottom: i32) -> Result<(), hwc2_error_t> {
        let err = unsafe { hwc2_compat_layer_set_visible_region(self.layer, left, top, right, bottom) };
        if err == 0 {
            Ok(())
        } else {
            Err(err)
        }
    }
}
