//! Android hwcomposer interface via libhybris
//!
//! This module provides safe Rust wrappers around hwcomposer2 HAL functions.

use crate::ffi::{self, *};
use crate::{Error, Result};
use std::os::raw::c_void;
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use std::sync::{Arc, Mutex};
use tracing::{debug, error, info, warn};

/// Display types from hwcomposer
#[repr(i32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DisplayType {
    Primary = 0,
    External = 1,
    Virtual = 2,
}

/// Display mode information
#[derive(Debug, Clone)]
pub struct DisplayMode {
    pub width: u32,
    pub height: u32,
    pub refresh_rate: u32,
    pub vsync_period: u64,
    pub dpi_x: f32,
    pub dpi_y: f32,
}

/// VSync callback data
struct VsyncCallbackData {
    timestamp: AtomicI64,
    triggered: AtomicBool,
}

/// Represents an Android hwcomposer device
pub struct Hwcomposer {
    device: *mut Hwc2CompatDevice,
    display: *mut Hwc2CompatDisplay,
    display_type: DisplayType,
    mode: DisplayMode,
    layer: *mut Hwc2CompatLayer,
    native_window: *mut ANativeWindow,
    egl_display: ffi::EGLDisplay,
    egl_surface: ffi::EGLSurface,
    egl_context: ffi::EGLContext,
    egl_config: ffi::EGLConfig,
    vsync_data: Arc<Mutex<VsyncCallbackData>>,
    event_listener: Box<HWC2EventListener>,
}

// Present callback for HWCNativeWindow
extern "C" fn present_callback(
    user_data: *mut c_void,
    _window: *mut ANativeWindow,
    buffer: *mut ANativeWindowBuffer,
) {
    if user_data.is_null() {
        return;
    }

    let hwc = unsafe { &mut *(user_data as *mut Hwcomposer) };

    // Set the client target buffer
    let result = unsafe {
        hwc2_compat_display_set_client_target(
            hwc.display,
            0,    // slot
            buffer,
            -1,   // acquire fence (none)
            0,    // dataspace (unknown)
        )
    };

    if result != HWC2_ERROR_NONE {
        error!("Failed to set client target: {}", result);
        return;
    }

    // Validate the display
    let mut num_types: u32 = 0;
    let mut num_requests: u32 = 0;
    let result = unsafe {
        hwc2_compat_display_validate(hwc.display, &mut num_types, &mut num_requests)
    };

    if result != HWC2_ERROR_NONE {
        error!("Display validation failed: {}", result);
        return;
    }

    // Accept changes if needed
    if num_types > 0 {
        let _ = unsafe { hwc2_compat_display_accept_changes(hwc.display) };
    }

    // Present
    let mut present_fence: i32 = -1;
    let result = unsafe { hwc2_compat_display_present(hwc.display, &mut present_fence) };

    if result != HWC2_ERROR_NONE {
        error!("Display present failed: {}", result);
    }

    // Set the fence on the buffer for synchronization
    if present_fence >= 0 {
        unsafe { HWCNativeBufferSetFence(buffer, present_fence) };
    }

    debug!("Present completed, fence: {}", present_fence);
}

// VSync callback
extern "C" fn vsync_callback(
    listener: *mut HWC2EventListener,
    _sequence_id: i32,
    _display: Hwc2DisplayT,
    timestamp: i64,
) {
    debug!("VSync callback: timestamp={}", timestamp);
    // In a real implementation, we'd signal waiters here
    // For now, just log
}

// Hotplug callback
extern "C" fn hotplug_callback(
    _listener: *mut HWC2EventListener,
    _sequence_id: i32,
    display_id: Hwc2DisplayT,
    connected: bool,
    primary_display: bool,
) {
    info!(
        "Hotplug callback: display_id={}, connected={}, primary={}",
        display_id, connected, primary_display
    );
}

// Refresh callback
extern "C" fn refresh_callback(
    _listener: *mut HWC2EventListener,
    _sequence_id: i32,
    display_id: Hwc2DisplayT,
) {
    debug!("Refresh callback: display_id={}", display_id);
}

impl Hwcomposer {
    /// Create a new hwcomposer device
    pub fn new() -> Result<Self> {
        info!("Initializing hwcomposer via libhybris");

        // Create HWC2 device
        let device = unsafe { hwc2_compat_device_new(false) };
        if device.is_null() {
            return Err(Error::HwcInit("Failed to create HWC2 device".into()));
        }

        // Create vsync callback data
        let vsync_data = Arc::new(Mutex::new(VsyncCallbackData {
            timestamp: AtomicI64::new(0),
            triggered: AtomicBool::new(false),
        }));

        // Set up event listener
        let mut event_listener = Box::new(HWC2EventListener {
            on_vsync_received: Some(vsync_callback),
            on_hotplug_received: Some(hotplug_callback),
            on_refresh_received: Some(refresh_callback),
        });

        unsafe {
            hwc2_compat_device_register_callback(device, event_listener.as_mut(), 0);
        }

        // Trigger hotplug for primary display
        unsafe {
            hwc2_compat_device_on_hotplug(device, 0, true);
        }

        // Get primary display
        let display = unsafe { hwc2_compat_device_get_display_by_id(device, 0) };
        if display.is_null() {
            return Err(Error::HwcInit("Failed to get primary display".into()));
        }

        // Get display configuration
        let config_ptr = unsafe { hwc2_compat_display_get_active_config(display) };
        let mode = if config_ptr.is_null() {
            warn!("Could not get active config, using fallback dimensions");
            Self::get_fallback_display_mode()?
        } else {
            let config = unsafe { &*config_ptr };
            DisplayMode {
                width: config.width as u32,
                height: config.height as u32,
                refresh_rate: if config.vsync_period > 0 {
                    (1_000_000_000 / config.vsync_period) as u32
                } else {
                    60
                },
                vsync_period: config.vsync_period as u64,
                dpi_x: config.dpi_x,
                dpi_y: config.dpi_y,
            }
        };

        info!(
            "Display mode: {}x{} @ {}Hz, DPI: {:.1}x{:.1}",
            mode.width, mode.height, mode.refresh_rate, mode.dpi_x, mode.dpi_y
        );

        // Set power mode to ON
        let result = unsafe { hwc2_compat_display_set_power_mode(display, HWC2_POWER_MODE_ON) };
        if result != HWC2_ERROR_NONE {
            warn!("Failed to set power mode: {}", result);
        }

        // Create a layer for client composition
        let layer = unsafe { hwc2_compat_display_create_layer(display) };
        if layer.is_null() {
            warn!("Failed to create layer, will use client-only composition");
        } else {
            // Configure the layer for client composition
            unsafe {
                hwc2_compat_layer_set_composition_type(layer, HWC2_COMPOSITION_CLIENT);
                hwc2_compat_layer_set_blend_mode(layer, HWC2_BLEND_MODE_PREMULTIPLIED);
                hwc2_compat_layer_set_display_frame(
                    layer,
                    0,
                    0,
                    mode.width as i32,
                    mode.height as i32,
                );
                hwc2_compat_layer_set_source_crop(
                    layer,
                    0.0,
                    0.0,
                    mode.width as f32,
                    mode.height as f32,
                );
                hwc2_compat_layer_set_plane_alpha(layer, 1.0);
            }
        }

        let mut hwc = Self {
            device,
            display,
            display_type: DisplayType::Primary,
            mode,
            layer,
            native_window: ptr::null_mut(),
            egl_display: ffi::EGL_NO_DISPLAY,
            egl_surface: ffi::EGL_NO_SURFACE,
            egl_context: ffi::EGL_NO_CONTEXT,
            egl_config: ptr::null_mut(),
            vsync_data,
            event_listener,
        };

        Ok(hwc)
    }

    /// Get fallback display dimensions from system
    fn get_fallback_display_mode() -> Result<DisplayMode> {
        // Try environment variables first
        if let (Ok(w), Ok(h)) = (
            std::env::var("FLICK_DISPLAY_WIDTH"),
            std::env::var("FLICK_DISPLAY_HEIGHT"),
        ) {
            if let (Ok(width), Ok(height)) = (w.parse(), h.parse()) {
                return Ok(DisplayMode {
                    width,
                    height,
                    refresh_rate: 60,
                    vsync_period: 16_666_667,
                    dpi_x: 0.0,
                    dpi_y: 0.0,
                });
            }
        }

        // Try reading from /sys/class/graphics/fb0
        if let Ok(size) = std::fs::read_to_string("/sys/class/graphics/fb0/virtual_size") {
            let parts: Vec<&str> = size.trim().split(',').collect();
            if parts.len() >= 2 {
                if let (Ok(w), Ok(h)) = (parts[0].parse(), parts[1].parse()) {
                    return Ok(DisplayMode {
                        width: w,
                        height: h,
                        refresh_rate: 60,
                        vsync_period: 16_666_667,
                        dpi_x: 0.0,
                        dpi_y: 0.0,
                    });
                }
            }
        }

        // Default for common phone resolution
        Ok(DisplayMode {
            width: 1080,
            height: 2340,
            refresh_rate: 60,
            vsync_period: 16_666_667,
            dpi_x: 400.0,
            dpi_y: 400.0,
        })
    }

    /// Get the current display mode
    pub fn get_mode(&self) -> &DisplayMode {
        &self.mode
    }

    /// Get the EGL display handle
    pub fn egl_display(&self) -> *mut c_void {
        self.egl_display
    }

    /// Get the EGL surface handle
    pub fn egl_surface(&self) -> *mut c_void {
        self.egl_surface
    }

    /// Get the EGL context handle
    pub fn egl_context(&self) -> *mut c_void {
        self.egl_context
    }

    /// Get the native window handle
    pub fn native_window(&self) -> *mut ANativeWindow {
        self.native_window
    }

    /// Initialize EGL for this display
    pub fn init_egl(&mut self) -> Result<()> {
        info!("Initializing EGL for hwcomposer display");

        // Create native window for rendering
        let hwc_ptr = self as *mut Hwcomposer as *mut c_void;
        self.native_window = unsafe {
            HWCNativeWindowCreate(
                self.mode.width,
                self.mode.height,
                HAL_PIXEL_FORMAT_RGBA_8888 as u32,
                present_callback,
                hwc_ptr,
            )
        };

        if self.native_window.is_null() {
            return Err(Error::HwcInit("Failed to create native window".into()));
        }

        // Set triple buffering
        unsafe { HWCNativeWindowSetBufferCount(self.native_window, 3) };

        // Get EGL display
        self.egl_display = unsafe { eglGetDisplay(ffi::EGL_DEFAULT_DISPLAY) };
        if self.egl_display == ffi::EGL_NO_DISPLAY {
            return Err(Error::HwcInit("Failed to get EGL display".into()));
        }

        // Initialize EGL
        let mut major: EGLint = 0;
        let mut minor: EGLint = 0;
        if unsafe { eglInitialize(self.egl_display, &mut major, &mut minor) } == ffi::EGL_FALSE {
            return Err(Error::HwcInit("Failed to initialize EGL".into()));
        }
        info!("EGL version: {}.{}", major, minor);

        // Choose config
        let config_attribs: [EGLint; 15] = [
            EGL_SURFACE_TYPE,
            EGL_WINDOW_BIT,
            EGL_RENDERABLE_TYPE,
            EGL_OPENGL_ES2_BIT,
            EGL_RED_SIZE,
            8,
            EGL_GREEN_SIZE,
            8,
            EGL_BLUE_SIZE,
            8,
            EGL_ALPHA_SIZE,
            8,
            EGL_DEPTH_SIZE,
            0,
            EGL_NONE,
        ];

        let mut num_configs: EGLint = 0;
        if unsafe {
            eglChooseConfig(
                self.egl_display,
                config_attribs.as_ptr(),
                &mut self.egl_config,
                1,
                &mut num_configs,
            )
        } == ffi::EGL_FALSE
            || num_configs == 0
        {
            return Err(Error::HwcInit("Failed to choose EGL config".into()));
        }

        // Create window surface
        self.egl_surface = unsafe {
            eglCreateWindowSurface(
                self.egl_display,
                self.egl_config,
                self.native_window,
                ptr::null(),
            )
        };

        if self.egl_surface == ffi::EGL_NO_SURFACE {
            let err = unsafe { eglGetError() };
            return Err(Error::HwcInit(format!(
                "Failed to create EGL surface: 0x{:X}",
                err
            )));
        }

        // Create context
        let context_attribs: [EGLint; 3] = [EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE];

        self.egl_context = unsafe {
            eglCreateContext(
                self.egl_display,
                self.egl_config,
                ffi::EGL_NO_CONTEXT,
                context_attribs.as_ptr(),
            )
        };

        if self.egl_context == ffi::EGL_NO_CONTEXT {
            let err = unsafe { eglGetError() };
            return Err(Error::HwcInit(format!(
                "Failed to create EGL context: 0x{:X}",
                err
            )));
        }

        // Make context current
        if unsafe {
            eglMakeCurrent(
                self.egl_display,
                self.egl_surface,
                self.egl_surface,
                self.egl_context,
            )
        } == ffi::EGL_FALSE
        {
            return Err(Error::HwcInit("Failed to make EGL context current".into()));
        }

        info!("EGL initialized successfully");
        Ok(())
    }

    /// Swap EGL buffers (present to display)
    pub fn swap_buffers(&self) -> Result<()> {
        if self.egl_display == ffi::EGL_NO_DISPLAY {
            return Err(Error::HwcInit("EGL not initialized".into()));
        }

        if unsafe { eglSwapBuffers(self.egl_display, self.egl_surface) } == ffi::EGL_FALSE {
            let err = unsafe { eglGetError() };
            return Err(Error::HwcPresent(format!(
                "eglSwapBuffers failed: 0x{:X}",
                err
            )));
        }

        Ok(())
    }

    /// Present a buffer to the display (legacy API)
    pub fn present(&mut self, _buffer: *mut c_void) -> Result<()> {
        self.swap_buffers()
    }

    /// Wait for vsync
    pub fn wait_vsync(&self) -> Result<u64> {
        // Enable vsync if not already enabled
        unsafe {
            hwc2_compat_display_set_vsync_enabled(self.display, HWC2_VSYNC_ENABLE);
        }

        // For now, just return the vsync period
        // A real implementation would wait for the vsync callback
        Ok(self.mode.vsync_period)
    }

    /// Enable or disable vsync events
    pub fn set_vsync_enabled(&self, enabled: bool) -> Result<()> {
        let mode = if enabled {
            HWC2_VSYNC_ENABLE
        } else {
            HWC2_VSYNC_DISABLE
        };

        let result = unsafe { hwc2_compat_display_set_vsync_enabled(self.display, mode) };
        if result != HWC2_ERROR_NONE {
            return Err(Error::HwcInit(format!(
                "Failed to set vsync enabled: {}",
                result
            )));
        }

        Ok(())
    }

    /// Get the raw HWC2 device pointer
    pub fn raw_device(&self) -> *mut Hwc2CompatDevice {
        self.device
    }

    /// Get the raw HWC2 display pointer
    pub fn raw_display(&self) -> *mut Hwc2CompatDisplay {
        self.display
    }
}

impl Drop for Hwcomposer {
    fn drop(&mut self) {
        debug!("Cleaning up hwcomposer device");

        // Destroy EGL resources
        if self.egl_context != ffi::EGL_NO_CONTEXT {
            unsafe {
                eglMakeCurrent(
                    self.egl_display,
                    ffi::EGL_NO_SURFACE,
                    ffi::EGL_NO_SURFACE,
                    ffi::EGL_NO_CONTEXT,
                );
                eglDestroyContext(self.egl_display, self.egl_context);
            }
        }

        if self.egl_surface != ffi::EGL_NO_SURFACE {
            unsafe {
                eglDestroySurface(self.egl_display, self.egl_surface);
            }
        }

        if self.egl_display != ffi::EGL_NO_DISPLAY {
            unsafe {
                eglTerminate(self.egl_display);
            }
        }

        // Destroy native window
        if !self.native_window.is_null() {
            unsafe {
                HWCNativeWindowDestroy(self.native_window);
            }
        }

        // Destroy layer
        if !self.layer.is_null() {
            unsafe {
                hwc2_compat_display_destroy_layer(self.display, self.layer);
            }
        }

        // Destroy display
        if !self.display.is_null() {
            unsafe {
                hwc2_compat_device_destroy_display(self.device, self.display);
            }
        }

        // Note: device cleanup is handled by libhybris
    }
}

unsafe impl Send for Hwcomposer {}
unsafe impl Sync for Hwcomposer {}
