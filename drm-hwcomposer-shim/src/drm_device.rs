//! DRM device shim that wraps hwcomposer
//!
//! This provides a DRM-compatible interface that can be used with
//! standard DRM/KMS libraries while actually using hwcomposer internally.
//!
//! # DRM Object IDs
//! We use the following object ID scheme:
//! - Connector: 1
//! - CRTC: 10
//! - Primary Plane: 20
//! - Cursor Plane: 21
//! - Framebuffers: 100+

use crate::hwcomposer::{DisplayMode, Hwcomposer};
use crate::{Error, Result};
use std::collections::HashMap;
use std::os::unix::io::{AsRawFd, RawFd};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use tracing::{debug, info, warn};

/// DRM fourcc format codes
pub mod drm_fourcc {
    pub const DRM_FORMAT_XRGB8888: u32 = 0x34325258; // 'XR24'
    pub const DRM_FORMAT_ARGB8888: u32 = 0x34325241; // 'AR24'
    pub const DRM_FORMAT_RGB565: u32 = 0x36314752;   // 'RG16'
    pub const DRM_FORMAT_XBGR8888: u32 = 0x34324258; // 'XB24'
    pub const DRM_FORMAT_ABGR8888: u32 = 0x34324241; // 'AB24'
}

/// Object IDs
const CONNECTOR_ID: u32 = 1;
const ENCODER_ID: u32 = 5;
const CRTC_ID: u32 = 10;
const PRIMARY_PLANE_ID: u32 = 20;
const CURSOR_PLANE_ID: u32 = 21;
const FB_ID_BASE: u32 = 100;

/// A virtual DRM device backed by hwcomposer
///
/// This struct provides a DRM-compatible interface that internally
/// uses hwcomposer for display output.
pub struct HwcDrmDevice {
    hwc: Arc<Mutex<Hwcomposer>>,
    fd: RawFd,
    mode: DisplayMode,
    // Framebuffer tracking
    fb_counter: AtomicU32,
    framebuffers: Mutex<HashMap<u32, FramebufferInfo>>,
    // Plane state
    primary_plane_fb: AtomicU32,
    cursor_plane_fb: AtomicU32,
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

/// DRM plane types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlaneType {
    Primary = 1,
    Cursor = 2,
    Overlay = 0,
}

/// DRM plane info
#[derive(Debug, Clone)]
pub struct PlaneInfo {
    pub id: u32,
    pub plane_type: PlaneType,
    pub possible_crtcs: u32,
    pub formats: Vec<u32>,
    pub fb_id: u32,
    pub crtc_id: u32,
    pub crtc_x: i32,
    pub crtc_y: i32,
    pub crtc_w: u32,
    pub crtc_h: u32,
    pub src_x: u32,
    pub src_y: u32,
    pub src_w: u32,
    pub src_h: u32,
}

/// DRM framebuffer info
#[derive(Debug, Clone)]
pub struct FramebufferInfo {
    pub id: u32,
    pub width: u32,
    pub height: u32,
    pub pitch: u32,
    pub bpp: u32,
    pub depth: u32,
    pub format: u32,
    pub handle: u32,
}

/// DRM resources enumeration
#[derive(Debug, Clone)]
pub struct DrmResources {
    pub min_width: u32,
    pub max_width: u32,
    pub min_height: u32,
    pub max_height: u32,
    pub connectors: Vec<u32>,
    pub crtcs: Vec<u32>,
    pub encoders: Vec<u32>,
    pub fbs: Vec<u32>,
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
            fb_counter: AtomicU32::new(FB_ID_BASE),
            framebuffers: Mutex::new(HashMap::new()),
            primary_plane_fb: AtomicU32::new(0),
            cursor_plane_fb: AtomicU32::new(0),
        })
    }

    /// Get DRM resources (connectors, CRTCs, encoders)
    pub fn get_resources(&self) -> DrmResources {
        DrmResources {
            min_width: 1,
            max_width: 8192,
            min_height: 1,
            max_height: 8192,
            connectors: vec![CONNECTOR_ID],
            crtcs: vec![CRTC_ID],
            encoders: vec![ENCODER_ID],
            fbs: self.framebuffers.lock().unwrap().keys().cloned().collect(),
        }
    }

    /// Get plane resources
    pub fn get_plane_resources(&self) -> Vec<u32> {
        vec![PRIMARY_PLANE_ID, CURSOR_PLANE_ID]
    }

    /// Get plane info by ID
    pub fn get_plane(&self, plane_id: u32) -> Option<PlaneInfo> {
        match plane_id {
            PRIMARY_PLANE_ID => Some(PlaneInfo {
                id: PRIMARY_PLANE_ID,
                plane_type: PlaneType::Primary,
                possible_crtcs: 1, // Bitmask - CRTC index 0
                formats: vec![
                    drm_fourcc::DRM_FORMAT_XRGB8888,
                    drm_fourcc::DRM_FORMAT_ARGB8888,
                    drm_fourcc::DRM_FORMAT_XBGR8888,
                    drm_fourcc::DRM_FORMAT_ABGR8888,
                    drm_fourcc::DRM_FORMAT_RGB565,
                ],
                fb_id: self.primary_plane_fb.load(Ordering::Relaxed),
                crtc_id: CRTC_ID,
                crtc_x: 0,
                crtc_y: 0,
                crtc_w: self.mode.width,
                crtc_h: self.mode.height,
                src_x: 0,
                src_y: 0,
                src_w: self.mode.width << 16,
                src_h: self.mode.height << 16,
            }),
            CURSOR_PLANE_ID => Some(PlaneInfo {
                id: CURSOR_PLANE_ID,
                plane_type: PlaneType::Cursor,
                possible_crtcs: 1,
                formats: vec![drm_fourcc::DRM_FORMAT_ARGB8888],
                fb_id: self.cursor_plane_fb.load(Ordering::Relaxed),
                crtc_id: 0,
                crtc_x: 0,
                crtc_y: 0,
                crtc_w: 64,
                crtc_h: 64,
                src_x: 0,
                src_y: 0,
                src_w: 64 << 16,
                src_h: 64 << 16,
            }),
            _ => None,
        }
    }

    /// Create a framebuffer
    pub fn add_framebuffer(
        &self,
        width: u32,
        height: u32,
        pitch: u32,
        bpp: u32,
        depth: u32,
        format: u32,
        handle: u32,
    ) -> Result<u32> {
        let fb_id = self.fb_counter.fetch_add(1, Ordering::Relaxed);

        let fb_info = FramebufferInfo {
            id: fb_id,
            width,
            height,
            pitch,
            bpp,
            depth,
            format,
            handle,
        };

        debug!("Created framebuffer {}: {}x{} format=0x{:08x}",
               fb_id, width, height, format);

        self.framebuffers.lock().unwrap().insert(fb_id, fb_info);
        Ok(fb_id)
    }

    /// Remove a framebuffer
    pub fn remove_framebuffer(&self, fb_id: u32) -> Result<()> {
        if self.framebuffers.lock().unwrap().remove(&fb_id).is_some() {
            debug!("Removed framebuffer {}", fb_id);
            Ok(())
        } else {
            Err(Error::Drm(format!("Framebuffer {} not found", fb_id)))
        }
    }

    /// Get framebuffer info
    pub fn get_framebuffer(&self, fb_id: u32) -> Option<FramebufferInfo> {
        self.framebuffers.lock().unwrap().get(&fb_id).cloned()
    }

    /// Set plane (simplified - just updates the fb_id)
    pub fn set_plane(
        &self,
        plane_id: u32,
        _crtc_id: u32,
        fb_id: u32,
        _crtc_x: i32,
        _crtc_y: i32,
        _crtc_w: u32,
        _crtc_h: u32,
    ) -> Result<()> {
        match plane_id {
            PRIMARY_PLANE_ID => {
                self.primary_plane_fb.store(fb_id, Ordering::Relaxed);
                debug!("Set primary plane FB to {}", fb_id);
                Ok(())
            }
            CURSOR_PLANE_ID => {
                self.cursor_plane_fb.store(fb_id, Ordering::Relaxed);
                debug!("Set cursor plane FB to {}", fb_id);
                Ok(())
            }
            _ => Err(Error::Drm(format!("Unknown plane {}", plane_id))),
        }
    }

    /// Page flip (present framebuffer to display)
    pub fn page_flip(&self, _crtc_id: u32, fb_id: u32) -> Result<()> {
        let fb = self.get_framebuffer(fb_id)
            .ok_or_else(|| Error::Drm(format!("Framebuffer {} not found", fb_id)))?;

        debug!("Page flip to FB {} ({}x{})", fb_id, fb.width, fb.height);

        // In a full implementation, we would present this buffer via hwcomposer
        // For now, just update the primary plane
        self.primary_plane_fb.store(fb_id, Ordering::Relaxed);

        Ok(())
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

    /// Get the EGL config handle
    pub fn egl_config(&self) -> Result<*mut std::ffi::c_void> {
        let hwc = self.hwc.lock().map_err(|e| Error::HwcInit(e.to_string()))?;
        Ok(hwc.egl_config())
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
