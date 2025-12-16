//! DRM device shim that wraps hwcomposer
//!
//! This provides a DRM-compatible file descriptor that can be used with
//! standard DRM/KMS libraries while actually using hwcomposer internally.

use crate::hwcomposer::{DisplayMode, Hwcomposer};
use crate::{Error, Result};
use std::os::unix::io::{AsRawFd, RawFd};
use std::sync::{Arc, Mutex};
use tracing::{debug, info};

/// A virtual DRM device backed by hwcomposer
///
/// This struct provides a file descriptor that responds to DRM ioctls
/// but internally uses hwcomposer for display output.
pub struct HwcDrmDevice {
    hwc: Arc<Mutex<Hwcomposer>>,
    // File descriptor for the virtual DRM device
    // In a full implementation, this would be created via FUSE or CUSE
    // For now, we'll use a different approach via custom trait implementations
    fd: RawFd,
    mode: DisplayMode,
}

/// DRM connector info
#[derive(Debug, Clone)]
pub struct ConnectorInfo {
    pub id: u32,
    pub connected: bool,
    pub width_mm: u32,
    pub height_mm: u32,
}

/// DRM CRTC info
#[derive(Debug, Clone)]
pub struct CrtcInfo {
    pub id: u32,
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
    pub mode_valid: bool,
}

/// DRM mode info (matching kernel's drm_mode_modeinfo)
#[derive(Debug, Clone)]
pub struct ModeInfo {
    pub clock: u32,
    pub hdisplay: u16,
    pub hsync_start: u16,
    pub hsync_end: u16,
    pub htotal: u16,
    pub vdisplay: u16,
    pub vsync_start: u16,
    pub vsync_end: u16,
    pub vtotal: u16,
    pub vrefresh: u32,
    pub flags: u32,
    pub name: String,
}

impl HwcDrmDevice {
    /// Create a new DRM device backed by hwcomposer
    pub fn new() -> Result<Self> {
        info!("Creating HwcDrmDevice");

        let hwc = Hwcomposer::new()?;
        let mode = hwc.get_mode().clone();

        // In a full implementation, we would create a virtual device file
        // For now, we'll use a placeholder fd and implement the DRM traits directly
        let fd = -1; // Placeholder - real impl would use FUSE/CUSE or similar

        Ok(Self {
            hwc: Arc::new(Mutex::new(hwc)),
            fd,
            mode,
        })
    }

    /// Get display mode as DRM mode info
    pub fn get_mode_info(&self) -> ModeInfo {
        let refresh = self.mode.refresh_rate;
        let hdisplay = self.mode.width as u16;
        let vdisplay = self.mode.height as u16;

        // Calculate timing values (simplified)
        let htotal = hdisplay + 200; // Add blanking
        let vtotal = vdisplay + 50;
        let clock = (htotal as u32 * vtotal as u32 * refresh) / 1000;

        ModeInfo {
            clock,
            hdisplay,
            hsync_start: hdisplay + 50,
            hsync_end: hdisplay + 100,
            htotal,
            vdisplay,
            vsync_start: vdisplay + 10,
            vsync_end: vdisplay + 20,
            vtotal,
            vrefresh: refresh,
            flags: 0,
            name: format!("{}x{}@{}", hdisplay, vdisplay, refresh),
        }
    }

    /// Get connector info
    pub fn get_connector(&self) -> ConnectorInfo {
        // Calculate physical size from DPI if available
        let (width_mm, height_mm) = if self.mode.dpi_x > 0.0 && self.mode.dpi_y > 0.0 {
            (
                (self.mode.width as f32 * 25.4 / self.mode.dpi_x) as u32,
                (self.mode.height as f32 * 25.4 / self.mode.dpi_y) as u32,
            )
        } else {
            // Approximate for typical phone (assume ~400 DPI)
            (
                (self.mode.width as f32 * 25.4 / 400.0) as u32,
                (self.mode.height as f32 * 25.4 / 400.0) as u32,
            )
        };

        ConnectorInfo {
            id: 1,
            connected: true,
            width_mm,
            height_mm,
        }
    }

    /// Get CRTC info
    pub fn get_crtc(&self) -> CrtcInfo {
        CrtcInfo {
            id: 1,
            x: 0,
            y: 0,
            width: self.mode.width,
            height: self.mode.height,
            mode_valid: true,
        }
    }

    /// Get the display dimensions
    pub fn get_dimensions(&self) -> (u32, u32) {
        (self.mode.width, self.mode.height)
    }

    /// Get the refresh rate in Hz
    pub fn get_refresh_rate(&self) -> u32 {
        self.mode.refresh_rate
    }

    /// Get the DPI
    pub fn get_dpi(&self) -> (f32, f32) {
        (self.mode.dpi_x, self.mode.dpi_y)
    }

    /// Initialize EGL context for this device
    pub fn init_egl(&self) -> Result<()> {
        let mut hwc = self.hwc.lock().map_err(|e| Error::HwcInit(e.to_string()))?;
        hwc.init_egl()
    }

    /// Swap EGL buffers (present to display)
    pub fn swap_buffers(&self) -> Result<()> {
        let hwc = self.hwc.lock().map_err(|e| Error::HwcInit(e.to_string()))?;
        hwc.swap_buffers()
    }

    /// Present a buffer to the display (legacy)
    pub fn present(&self, buffer: *mut std::ffi::c_void) -> Result<()> {
        let mut hwc = self.hwc.lock().map_err(|e| Error::HwcInit(e.to_string()))?;
        hwc.present(buffer)
    }

    /// Wait for vsync
    pub fn wait_vsync(&self) -> Result<u64> {
        let hwc = self.hwc.lock().map_err(|e| Error::HwcInit(e.to_string()))?;
        hwc.wait_vsync()
    }

    /// Get the underlying hwcomposer device
    pub fn hwcomposer(&self) -> Arc<Mutex<Hwcomposer>> {
        Arc::clone(&self.hwc)
    }

    /// Get the EGL display handle
    pub fn egl_display(&self) -> Result<*mut std::ffi::c_void> {
        let hwc = self.hwc.lock().map_err(|e| Error::HwcInit(e.to_string()))?;
        Ok(hwc.egl_display())
    }

    /// Get the EGL surface handle
    pub fn egl_surface(&self) -> Result<*mut std::ffi::c_void> {
        let hwc = self.hwc.lock().map_err(|e| Error::HwcInit(e.to_string()))?;
        Ok(hwc.egl_surface())
    }

    /// Get the EGL context handle
    pub fn egl_context(&self) -> Result<*mut std::ffi::c_void> {
        let hwc = self.hwc.lock().map_err(|e| Error::HwcInit(e.to_string()))?;
        Ok(hwc.egl_context())
    }
}

impl AsRawFd for HwcDrmDevice {
    fn as_raw_fd(&self) -> RawFd {
        self.fd
    }
}

// Note: A full implementation would also implement:
// - drm::Device trait
// - drm::control::Device trait
// - Buffer management (dumb buffers, prime)
// - Atomic modesetting
// - Event handling (vblank, page flip)
