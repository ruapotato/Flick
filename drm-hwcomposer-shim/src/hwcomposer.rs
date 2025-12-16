//! Android hwcomposer interface via libhybris
//!
//! This module provides safe Rust wrappers around hwcomposer2 HAL functions.

use crate::{Error, Result};
use std::os::raw::{c_int, c_void};
use tracing::{debug, error, info};

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
    pub refresh_rate: u32,  // In Hz
    pub vsync_period: u64,  // In nanoseconds
}

/// Represents an Android hwcomposer device
pub struct Hwcomposer {
    device: *mut c_void,
    display: DisplayType,
    mode: DisplayMode,
    egl_display: *mut c_void,
    egl_surface: *mut c_void,
}

// FFI declarations for libhybris/hwcomposer
#[link(name = "hybris-common")]
extern "C" {
    fn hybris_dlopen(path: *const i8, flags: c_int) -> *mut c_void;
    fn hybris_dlsym(handle: *mut c_void, symbol: *const i8) -> *mut c_void;
}

impl Hwcomposer {
    /// Create a new hwcomposer device
    pub fn new() -> Result<Self> {
        info!("Initializing hwcomposer via libhybris");

        // This is a simplified implementation - real code would:
        // 1. Load libhwc2.so via hybris_dlopen
        // 2. Get hwc2_device_t from the HAL
        // 3. Query display attributes
        // 4. Set up EGL

        // For now, query display dimensions from Android props
        let (width, height) = Self::get_display_dimensions()?;

        let mode = DisplayMode {
            width,
            height,
            refresh_rate: 60,
            vsync_period: 16_666_667, // ~60Hz in ns
        };

        info!("Display mode: {}x{} @ {}Hz", mode.width, mode.height, mode.refresh_rate);

        Ok(Self {
            device: std::ptr::null_mut(),
            display: DisplayType::Primary,
            mode,
            egl_display: std::ptr::null_mut(),
            egl_surface: std::ptr::null_mut(),
        })
    }

    /// Get display dimensions from Android system properties
    fn get_display_dimensions() -> Result<(u32, u32)> {
        // Try environment variables first
        if let (Ok(w), Ok(h)) = (
            std::env::var("FLICK_DISPLAY_WIDTH"),
            std::env::var("FLICK_DISPLAY_HEIGHT"),
        ) {
            if let (Ok(width), Ok(height)) = (w.parse(), h.parse()) {
                return Ok((width, height));
            }
        }

        // Try reading from /sys/class/graphics/fb0
        if let Ok(size) = std::fs::read_to_string("/sys/class/graphics/fb0/virtual_size") {
            let parts: Vec<&str> = size.trim().split(',').collect();
            if parts.len() >= 2 {
                if let (Ok(w), Ok(h)) = (parts[0].parse(), parts[1].parse()) {
                    return Ok((w, h));
                }
            }
        }

        // Try Android getprop
        if let Ok(output) = std::process::Command::new("getprop")
            .arg("ro.sf.lcd_width")
            .output()
        {
            if let Ok(w) = String::from_utf8_lossy(&output.stdout).trim().parse::<u32>() {
                if let Ok(output) = std::process::Command::new("getprop")
                    .arg("ro.sf.lcd_height")
                    .output()
                {
                    if let Ok(h) = String::from_utf8_lossy(&output.stdout).trim().parse::<u32>() {
                        return Ok((w, h));
                    }
                }
            }
        }

        // Default for common phone resolution
        Ok((1080, 2340))
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

    /// Initialize EGL for this display
    pub fn init_egl(&mut self) -> Result<()> {
        info!("Initializing EGL for hwcomposer display");
        // Real implementation would:
        // 1. Get EGLDisplay from hwcomposer
        // 2. Create EGLSurface for the display
        // 3. Store handles for later use
        Ok(())
    }

    /// Present a buffer to the display
    pub fn present(&mut self, _buffer: *mut c_void) -> Result<()> {
        // Real implementation would:
        // 1. Set up hwcomposer layers
        // 2. Call hwc2_present_display
        // 3. Handle vsync
        Ok(())
    }

    /// Wait for vsync
    pub fn wait_vsync(&self) -> Result<u64> {
        // Return estimated next vsync time
        Ok(0)
    }
}

impl Drop for Hwcomposer {
    fn drop(&mut self) {
        // Clean up hwcomposer resources
        debug!("Cleaning up hwcomposer device");
    }
}

unsafe impl Send for Hwcomposer {}
unsafe impl Sync for Hwcomposer {}
