//! DRM Shim backend - uses drm-hwcomposer-shim for libhybris devices
//!
//! This backend provides the same DRM/GBM interface as the udev backend,
//! but internally uses Android's hwcomposer via the shim layer.
//! This allows a single code path for both native Linux and libhybris devices.

use std::{
    cell::RefCell,
    rc::Rc,
    sync::Arc,
    time::Duration,
};

use anyhow::Result;
use tracing::{error, info, warn};

use smithay::{
    output::{Mode, Output, PhysicalProperties, Subpixel},
    reexports::{
        calloop::{EventLoop, timer::{Timer, TimeoutAction}},
        wayland_server::Display,
    },
    utils::Transform,
};

use drm_hwcomposer_shim::{HwcDrmDevice, HwcGbmDevice};

use khronos_egl as egl;

use crate::state::Flick;

/// DRM Shim display state
struct ShimDisplay {
    drm_device: Arc<HwcDrmDevice>,
    #[allow(dead_code)]
    gbm_device: Arc<HwcGbmDevice>,
    egl_instance: egl::DynamicInstance<egl::EGL1_4>,
    egl_display: egl::Display,
    egl_surface: egl::Surface,
    egl_context: egl::Context,
    width: u32,
    height: u32,
}

impl Drop for ShimDisplay {
    fn drop(&mut self) {
        info!("ShimDisplay cleanup");

        // Make EGL context not current
        let _ = self.egl_instance.make_current(
            self.egl_display,
            None,
            None,
            None,
        );

        // Destroy EGL resources
        if let Err(e) = self.egl_instance.destroy_surface(self.egl_display, self.egl_surface) {
            warn!("Failed to destroy EGL surface: {:?}", e);
        }
        if let Err(e) = self.egl_instance.destroy_context(self.egl_display, self.egl_context) {
            warn!("Failed to destroy EGL context: {:?}", e);
        }
        if let Err(e) = self.egl_instance.terminate(self.egl_display) {
            warn!("Failed to terminate EGL display: {:?}", e);
        }

        info!("ShimDisplay cleanup complete");
    }
}

/// Initialize the DRM shim display
fn init_shim_display() -> Result<ShimDisplay> {
    info!("Initializing DRM shim display");

    // Create DRM device (initializes hwcomposer internally)
    let drm_device = Arc::new(HwcDrmDevice::new()?);

    let (width, height) = drm_device.get_dimensions();
    let refresh_rate = drm_device.get_refresh_rate();
    let (dpi_x, dpi_y) = drm_device.get_dpi();

    info!("Display: {}x{} @ {}Hz, DPI: {:.1}x{:.1}",
          width, height, refresh_rate, dpi_x, dpi_y);

    // Create GBM device for buffer allocation
    let gbm_device = Arc::new(HwcGbmDevice::new(drm_device.clone())?);

    // Initialize EGL
    info!("Initializing EGL");
    let egl_instance = unsafe { egl::DynamicInstance::<egl::EGL1_4>::load_required()? };

    // Initialize EGL on the DRM device (this sets up the native window)
    drm_device.init_egl()?;

    // Get the EGL display from the shim
    let egl_display_ptr = drm_device.egl_display()?;
    let egl_display = unsafe {
        egl::Display::from_ptr(egl_display_ptr as *mut _)
    };

    // Get EGL surface from shim
    let egl_surface_ptr = drm_device.egl_surface()?;
    let egl_surface = unsafe {
        egl::Surface::from_ptr(egl_surface_ptr as *mut _)
    };

    // Get EGL context from shim
    let egl_context_ptr = drm_device.egl_context()?;
    let egl_context = unsafe {
        egl::Context::from_ptr(egl_context_ptr as *mut _)
    };

    // Make context current
    egl_instance.make_current(
        egl_display,
        Some(egl_surface),
        Some(egl_surface),
        Some(egl_context),
    )?;

    info!("EGL initialized successfully");

    // Load OpenGL ES functions
    unsafe {
        gl::load_with(|s| {
            egl_instance.get_proc_address(s)
                .map(|p| p as *const _)
                .unwrap_or(std::ptr::null())
        });
    }
    info!("OpenGL ES functions loaded");

    Ok(ShimDisplay {
        drm_device,
        gbm_device,
        egl_instance,
        egl_display,
        egl_surface,
        egl_context,
        width,
        height,
    })
}

/// Main entry point for the DRM shim backend
pub fn run() -> Result<()> {
    info!("Starting Flick with DRM shim backend");

    // Initialize the shim display
    let shim_display = init_shim_display()?;
    let width = shim_display.width;
    let height = shim_display.height;
    let _drm_device = shim_display.drm_device.clone();
    let shim_display = Rc::new(RefCell::new(shim_display));

    // Create Wayland display
    let wayland_display: Display<Flick> = Display::new()?;

    // Create event loop
    let mut event_loop: EventLoop<Flick> = EventLoop::try_new()?;
    let loop_handle = event_loop.handle();

    // Create output
    let output = Output::new(
        "SHIM-1".to_string(),
        PhysicalProperties {
            size: (62, 127).into(), // Approximate phone size in mm
            subpixel: Subpixel::Unknown,
            make: "DRM-Shim".to_string(),
            model: "HWComposer".to_string(),
            serial_number: "Unknown".to_string(),
        },
    );

    let mode = Mode {
        size: (width as i32, height as i32).into(),
        refresh: 60_000, // 60 Hz in mHz
    };

    output.change_current_state(
        Some(mode),
        Some(Transform::Normal),
        None,
        Some((0, 0).into()),
    );
    output.set_preferred(mode);

    // Create compositor state (takes ownership of wayland_display)
    let screen_size = smithay::utils::Size::from((width as i32, height as i32));
    let mut state = Flick::new(
        wayland_display,
        loop_handle.clone(),
        screen_size,
    );
    state.space.map_output(&output, (0, 0));

    // Skip input setup for now - just test display
    // TODO: Add input support after display works
    info!("Skipping input setup for initial display test");

    // Frame timer for rendering at 60fps
    let frame_timer = Timer::from_duration(Duration::from_millis(16));
    let shim_display_clone = shim_display.clone();

    loop_handle.insert_source(frame_timer, move |_, _, state| {
        // Render frame (test mode - color cycling)
        render_frame(&shim_display_clone, state);

        // Schedule next frame
        TimeoutAction::ToDuration(Duration::from_millis(16))
    }).expect("Failed to insert frame timer");

    info!("DRM shim backend initialized, entering event loop");

    // Run the event loop
    loop {
        // Dispatch Wayland events
        state.dispatch_clients();

        // Run one iteration of the event loop
        if let Err(e) = event_loop.dispatch(Some(Duration::from_millis(1)), &mut state) {
            error!("Event loop error: {:?}", e);
        }
    }
}

/// Frame counter for color cycling (test mode)
static mut FRAME_COUNT: u64 = 0;

/// Render a frame
fn render_frame(
    display: &Rc<RefCell<ShimDisplay>>,
    _state: &mut Flick,
) {
    let display = display.borrow();

    // Cycle through colors to show the display is working
    let frame = unsafe {
        FRAME_COUNT += 1;
        FRAME_COUNT
    };

    // Change color every 60 frames (1 second at 60fps)
    let color_index = (frame / 60) % 6;
    let (r, g, b) = match color_index {
        0 => (0.8, 0.1, 0.1), // Red
        1 => (0.1, 0.8, 0.1), // Green
        2 => (0.1, 0.1, 0.8), // Blue
        3 => (0.8, 0.8, 0.1), // Yellow
        4 => (0.8, 0.1, 0.8), // Magenta
        _ => (0.1, 0.8, 0.8), // Cyan
    };

    // Clear screen with current color
    unsafe {
        gl::ClearColor(r as f32, g as f32, b as f32, 1.0);
        gl::Clear(gl::COLOR_BUFFER_BIT);
    }

    // Log every 60 frames
    if frame % 60 == 0 {
        let colors = ["RED", "GREEN", "BLUE", "YELLOW", "MAGENTA", "CYAN"];
        info!("Frame {}: Showing {}", frame, colors[color_index as usize]);
    }

    // Swap buffers via the shim
    if let Err(e) = display.drm_device.swap_buffers() {
        error!("Failed to swap buffers: {}", e);
    }
}

// OpenGL bindings (minimal set needed for rendering)
mod gl {
    use std::ffi::c_void;

    pub type GLenum = u32;
    pub type GLbitfield = u32;
    pub type GLfloat = f32;

    pub const COLOR_BUFFER_BIT: GLbitfield = 0x00004000;

    type GlClearColor = extern "C" fn(GLfloat, GLfloat, GLfloat, GLfloat);
    type GlClear = extern "C" fn(GLbitfield);

    static mut GL_CLEAR_COLOR: Option<GlClearColor> = None;
    static mut GL_CLEAR: Option<GlClear> = None;

    pub unsafe fn load_with<F>(mut loader: F)
    where
        F: FnMut(&str) -> *const c_void,
    {
        GL_CLEAR_COLOR = std::mem::transmute(loader("glClearColor"));
        GL_CLEAR = std::mem::transmute(loader("glClear"));
    }

    pub unsafe fn ClearColor(r: GLfloat, g: GLfloat, b: GLfloat, a: GLfloat) {
        if let Some(f) = GL_CLEAR_COLOR {
            f(r, g, b, a);
        }
    }

    pub unsafe fn Clear(mask: GLbitfield) {
        if let Some(f) = GL_CLEAR {
            f(mask);
        }
    }
}
