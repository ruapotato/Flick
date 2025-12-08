//! Udev backend for real hardware
//!
//! This backend runs on actual hardware using DRM for display and libinput for input.

use std::{
    cell::RefCell,
    collections::HashMap,
    path::Path,
    rc::Rc,
    time::Duration,
};

use anyhow::Result;
use tracing::{debug, error, info, warn};

use smithay::{
    backend::{
        allocator::{
            gbm::{GbmAllocator, GbmBufferFlags, GbmDevice},
            Fourcc,
        },
        drm::{DrmDevice, DrmDeviceFd, DrmEvent, GbmBufferedSurface},
        egl::{EGLContext, EGLDisplay},
        input::InputEvent,
        libinput::{LibinputInputBackend, LibinputSessionInterface},
        renderer::{
            damage::OutputDamageTracker,
            gles::GlesRenderer,
            Bind, Frame, Renderer,
            element::{
                AsRenderElements,
                utils::{
                    CropRenderElement, RelocateRenderElement, RescaleRenderElement, Relocate,
                },
            },
        },
        session::{
            libseat::LibSeatSession,
            Event as SessionEvent, Session,
        },
        udev::{UdevBackend, UdevEvent},
    },
    output::{Mode, Output, PhysicalProperties, Subpixel},
    reexports::{
        calloop::EventLoop,
        drm::control::{connector, crtc, Device as DrmControlDevice, ModeTypeFlags},
        input::Libinput,
        wayland_server::Display,
    },
    utils::{DeviceFd, Rectangle, Scale, Transform},
};

// Re-import libinput types for keyboard handling

use smithay::wayland::xwayland_shell::XWaylandShellState;
use smithay::xwayland::{XWayland, XWaylandEvent, xwm::X11Wm};
use smithay::backend::renderer::element::solid::SolidColorRenderElement;
use smithay::backend::renderer::element::surface::WaylandSurfaceRenderElement;
use smithay::backend::renderer::element::memory::{MemoryRenderBuffer, MemoryRenderBufferRenderElement};
use smithay::backend::renderer::{ImportAll, ImportMem};

use crate::state::Flick;

/// Simple 5x7 bitmap font for window titles
/// Each character is 7 rows of 5-bit patterns
fn get_char_bitmap(c: char) -> [u8; 7] {
    match c.to_ascii_uppercase() {
        'A' => [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
        'B' => [0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110],
        'C' => [0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110],
        'D' => [0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110],
        'E' => [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111],
        'F' => [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000],
        'G' => [0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01110],
        'H' => [0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
        'I' => [0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
        'J' => [0b00111, 0b00010, 0b00010, 0b00010, 0b00010, 0b10010, 0b01100],
        'K' => [0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001],
        'L' => [0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111],
        'M' => [0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001],
        'N' => [0b10001, 0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001],
        'O' => [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
        'P' => [0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000],
        'Q' => [0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101],
        'R' => [0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001],
        'S' => [0b01110, 0b10001, 0b10000, 0b01110, 0b00001, 0b10001, 0b01110],
        'T' => [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100],
        'U' => [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
        'V' => [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100],
        'W' => [0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b11011, 0b10001],
        'X' => [0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001],
        'Y' => [0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100],
        'Z' => [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111],
        '0' => [0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110],
        '1' => [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
        '2' => [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111],
        '3' => [0b01110, 0b10001, 0b00001, 0b00110, 0b00001, 0b10001, 0b01110],
        '4' => [0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010],
        '5' => [0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110],
        '6' => [0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110],
        '7' => [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000],
        '8' => [0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110],
        '9' => [0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100],
        ' ' => [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000],
        '-' => [0b00000, 0b00000, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000],
        '.' => [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b01100, 0b01100],
        ':' => [0b00000, 0b01100, 0b01100, 0b00000, 0b01100, 0b01100, 0b00000],
        '(' => [0b00010, 0b00100, 0b01000, 0b01000, 0b01000, 0b00100, 0b00010],
        ')' => [0b01000, 0b00100, 0b00010, 0b00010, 0b00010, 0b00100, 0b01000],
        _ => [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000], // Space for unknown
    }
}

// Define a combined element type for the app switcher that can hold both
// solid color elements (for card backgrounds, shadows, text) and
// constrained window elements (for actual window content previews)
smithay::backend::renderer::element::render_elements! {
    /// Render elements for the app switcher view
    pub SwitcherRenderElement<R> where
        R: ImportAll + ImportMem;
    /// Solid color rectangles (backgrounds, shadows, text pixels)
    Solid=SolidColorRenderElement,
    /// Constrained window content (scaled and cropped to fit cards)
    Window=CropRenderElement<RelocateRenderElement<RescaleRenderElement<WaylandSurfaceRenderElement<R>>>>,
    /// Memory buffer element (Slint UI backdrop)
    Icon=MemoryRenderBufferRenderElement<R>,
}

// Define a combined element type for the home screen that can hold both
// solid color elements (for tile backgrounds, text) and memory buffer elements (for icons)
smithay::backend::renderer::element::render_elements! {
    /// Render elements for the home screen view
    pub HomeRenderElement<R> where
        R: ImportMem;
    /// Solid color rectangles (tile backgrounds, text pixels)
    Solid=SolidColorRenderElement,
    /// Memory buffer elements (icons loaded from PNG files)
    Icon=MemoryRenderBufferRenderElement<R>,
}

/// Per-GPU state
struct GpuData {
    renderer: GlesRenderer,
    #[allow(dead_code)]
    gbm_device: GbmDevice<DrmDeviceFd>,
    #[allow(dead_code)]
    drm_device: DrmDevice,
    surfaces: HashMap<crtc::Handle, Rc<RefCell<SurfaceData>>>,
}

/// Per-output surface state
struct SurfaceData {
    surface: GbmBufferedSurface<GbmAllocator<DrmDeviceFd>, ()>,
    #[allow(dead_code)]
    damage_tracker: OutputDamageTracker,
    /// Whether we have a frame pending (waiting for vsync)
    frame_pending: bool,
    /// Whether we're ready to render (vblank received)
    ready_to_render: bool,
}

/// Keyboard modifier state for tracking Ctrl+Alt+Shift+Super
#[derive(Default)]
struct ModifierState {
    ctrl: bool,
    alt: bool,
    shift: bool,
    super_key: bool,
}

/// Convert evdev keycode to character (simplified US QWERTY layout)
fn evdev_to_char(keycode: u32, shift: bool) -> Option<char> {
    // Row 1: numbers
    let c = match keycode {
        2 => if shift { '!' } else { '1' },
        3 => if shift { '@' } else { '2' },
        4 => if shift { '#' } else { '3' },
        5 => if shift { '$' } else { '4' },
        6 => if shift { '%' } else { '5' },
        7 => if shift { '^' } else { '6' },
        8 => if shift { '&' } else { '7' },
        9 => if shift { '*' } else { '8' },
        10 => if shift { '(' } else { '9' },
        11 => if shift { ')' } else { '0' },
        12 => if shift { '_' } else { '-' },
        13 => if shift { '+' } else { '=' },
        // Row 2: qwertyuiop
        16 => if shift { 'Q' } else { 'q' },
        17 => if shift { 'W' } else { 'w' },
        18 => if shift { 'E' } else { 'e' },
        19 => if shift { 'R' } else { 'r' },
        20 => if shift { 'T' } else { 't' },
        21 => if shift { 'Y' } else { 'y' },
        22 => if shift { 'U' } else { 'u' },
        23 => if shift { 'I' } else { 'i' },
        24 => if shift { 'O' } else { 'o' },
        25 => if shift { 'P' } else { 'p' },
        // Row 3: asdfghjkl
        30 => if shift { 'A' } else { 'a' },
        31 => if shift { 'S' } else { 's' },
        32 => if shift { 'D' } else { 'd' },
        33 => if shift { 'F' } else { 'f' },
        34 => if shift { 'G' } else { 'g' },
        35 => if shift { 'H' } else { 'h' },
        36 => if shift { 'J' } else { 'j' },
        37 => if shift { 'K' } else { 'k' },
        38 => if shift { 'L' } else { 'l' },
        // Row 4: zxcvbnm
        44 => if shift { 'Z' } else { 'z' },
        45 => if shift { 'X' } else { 'x' },
        46 => if shift { 'C' } else { 'c' },
        47 => if shift { 'V' } else { 'v' },
        48 => if shift { 'B' } else { 'b' },
        49 => if shift { 'N' } else { 'n' },
        50 => if shift { 'M' } else { 'm' },
        // Space
        57 => ' ',
        _ => return None,
    };
    Some(c)
}

pub fn run() -> Result<()> {
    info!("Starting udev backend");

    // Create event loop
    let mut event_loop: EventLoop<Flick> = EventLoop::try_new()?;
    let loop_handle = event_loop.handle();

    // Initialize libseat session - wrap in Rc<RefCell> for shared access
    let (session, notifier) = LibSeatSession::new()
        .map_err(|e| anyhow::anyhow!("Failed to create session: {:?}", e))?;

    let session = Rc::new(RefCell::new(session));

    info!("Session created, seat: {}", session.borrow().seat());

    // Set up udev backend to monitor DRM devices
    let udev_backend = UdevBackend::new(session.borrow().seat())
        .map_err(|e| anyhow::anyhow!("Failed to create udev backend: {:?}", e))?;

    // Initialize libinput
    let libinput_session = LibinputSessionInterface::from(session.borrow().clone());
    let mut libinput_context = Libinput::new_with_udev(libinput_session);
    libinput_context.udev_assign_seat(&session.borrow().seat()).unwrap();

    let libinput_backend = LibinputInputBackend::new(libinput_context.clone());

    // Create Wayland display
    let display: Display<Flick> = Display::new()?;

    // Initial screen size (will be updated when we find outputs)
    let screen_size = (720, 1440).into();
    let mut state = Flick::new(display, loop_handle.clone(), screen_size);

    info!("Wayland socket: {:?}", state.socket_name);

    // Set environment variables
    std::env::set_var("WAYLAND_DISPLAY", &state.socket_name);

    // Track session active state
    let session_active = Rc::new(RefCell::new(true));
    let session_active_for_notifier = session_active.clone();

    // Track if we need to reset buffers after VT switch
    let needs_buffer_reset = Rc::new(RefCell::new(false));
    let needs_buffer_reset_for_notifier = needs_buffer_reset.clone();

    // Track modifier state for VT switching (needed in session notifier too)
    let modifiers = Rc::new(RefCell::new(ModifierState::default()));
    let modifiers_for_notifier = modifiers.clone();

    // Add session notifier to event loop
    loop_handle
        .insert_source(notifier, move |event, _, _state| match event {
            SessionEvent::PauseSession => {
                info!("Session paused - stopping rendering");
                *session_active_for_notifier.borrow_mut() = false;
            }
            SessionEvent::ActivateSession => {
                info!("Session activated - resuming rendering");
                *session_active_for_notifier.borrow_mut() = true;
                // Mark that we need to reset buffers after VT switch
                *needs_buffer_reset_for_notifier.borrow_mut() = true;
                // Reset modifier state - keys may have been released while on other VT
                *modifiers_for_notifier.borrow_mut() = ModifierState::default();
                info!("Reset modifier state after VT switch");
            }
        })
        .map_err(|e| anyhow::anyhow!("Failed to insert session source: {:?}", e))?;

    let session_for_input = session.clone();
    let modifiers_for_input = modifiers.clone();

    // Add libinput to event loop
    loop_handle
        .insert_source(libinput_backend, move |event, _, state| {
            handle_input_event(state, event, &session_for_input, &modifiers_for_input);
        })
        .map_err(|e| anyhow::anyhow!("Failed to insert input source: {:?}", e))?;

    // Store GPU data - we'll initialize this when we find a GPU
    let mut gpu_data: Option<GpuData> = None;
    let mut primary_output: Option<Output> = None;
    let mut drm_notifier_opt: Option<DrmNotifier> = None;

    // Process initial udev devices
    for (device_id, path) in udev_backend.device_list() {
        info!("Found GPU: {:?} at {:?}", device_id, path);
        match init_gpu(&mut state, &mut *session.borrow_mut(), path) {
            Ok((data, output, notifier)) => {
                gpu_data = Some(data);
                primary_output = Some(output);
                drm_notifier_opt = Some(notifier);
                break; // Just use first GPU for now
            }
            Err(e) => {
                warn!("Failed to initialize GPU {:?}: {:?}", device_id, e);
            }
        }
    }

    let Some(mut gpu) = gpu_data else {
        return Err(anyhow::anyhow!("No usable GPU found"));
    };

    let Some(output) = primary_output else {
        return Err(anyhow::anyhow!("No output found"));
    };

    let Some(drm_notifier) = drm_notifier_opt else {
        return Err(anyhow::anyhow!("No DRM notifier"));
    };

    // Update screen size to actual output size
    if let Some(mode) = output.current_mode() {
        state.screen_size = mode.size.to_logical(1);
        // Update gesture recognizer with actual screen size
        state.gesture_recognizer.screen_size = state.screen_size;
        // Update shell with actual screen size
        state.shell.screen_size = state.screen_size;
        state.shell.quick_settings.screen_size = state.screen_size;
        // Update Slint UI with actual screen size
        if let Some(ref mut slint_ui) = state.shell.slint_ui {
            slint_ui.set_size(state.screen_size);
            info!("Slint UI size updated to: {:?}", state.screen_size);
        }
        info!("Screen size updated to: {:?}", state.screen_size);
    }

    // Clone surfaces for DRM event handler
    let surfaces_for_drm = gpu.surfaces.clone();

    // Add DRM event handler for page flip events (vsync)
    loop_handle
        .insert_source(drm_notifier, move |event, _metadata, _state| {
            match event {
                DrmEvent::VBlank(crtc) => {
                    debug!("VBlank event for CRTC {:?}", crtc);
                    // Page flip completed - mark surface as ready to render
                    if let Some(surface_data) = surfaces_for_drm.get(&crtc) {
                        let mut data = surface_data.borrow_mut();
                        if data.frame_pending {
                            // Acknowledge the frame
                            if let Err(e) = data.surface.frame_submitted() {
                                warn!("Failed to acknowledge frame: {:?}", e);
                            }
                            data.frame_pending = false;
                            data.ready_to_render = true;
                            debug!("Surface ready for next frame");
                        }
                    } else {
                        warn!("VBlank for unknown CRTC {:?}", crtc);
                    }
                }
                DrmEvent::Error(e) => {
                    error!("DRM error: {:?}", e);
                }
            }
        })
        .map_err(|e| anyhow::anyhow!("Failed to insert DRM source: {:?}", e))?;

    // Add udev backend to event loop (for hotplug)
    loop_handle
        .insert_source(udev_backend, move |event, _, _state| match event {
            UdevEvent::Added { device_id, path } => {
                info!("GPU added: {:?} at {:?}", device_id, path);
            }
            UdevEvent::Changed { device_id } => {
                info!("GPU changed: {:?}", device_id);
            }
            UdevEvent::Removed { device_id } => {
                info!("GPU removed: {:?}", device_id);
            }
        })
        .map_err(|e| anyhow::anyhow!("Failed to insert udev source: {:?}", e))?;

    // Shell is integrated - no need to start external process

    // Initialize XWayland
    info!("Starting XWayland...");
    if let Err(e) = init_xwayland(&mut state, &event_loop.handle()) {
        warn!("Failed to start XWayland: {:?}", e);
        warn!("X11 applications will not be available");
    } else {
        info!("XWayland started successfully");
    }

    info!("Entering render loop");
    info!("Press Ctrl+Alt+F1-F12 to switch VT");

    // Main render loop
    loop {
        // Dispatch events (16ms timeout for ~60fps)
        if let Err(e) = event_loop.dispatch(Some(Duration::from_millis(16)), &mut state) {
            error!("Event loop dispatch error: {:?}", e);
            // Continue running - some errors are recoverable
        }

        // Dispatch client requests and flush responses
        state.dispatch_clients();

        // Update window list for shell (throttled to avoid excessive I/O)
        state.update_window_list();

        // Check for focus requests from shell
        state.check_focus_request();

        // Check for long press (periodic check since touch_motion may not fire if finger is still)
        if state.shell.view == crate::shell::ShellView::Home {
            state.shell.check_and_show_long_press();
        }

        // Update app switcher physics (momentum/snap animation)
        if state.shell.view == crate::shell::ShellView::Switcher {
            let num_windows = state.space.elements().count();
            let screen_w = state.screen_size.w as f64;
            let card_width = screen_w * 0.80;
            let card_spacing = card_width * 0.35;
            state.shell.update_switcher_physics(num_windows, card_spacing);
        }

        // Skip rendering if session is not active (VT switched away)
        if !*session_active.borrow() {
            continue;
        }

        // Reset buffers after VT switch back
        if *needs_buffer_reset.borrow() {
            info!("Resetting GPU buffers after VT switch");
            for (_crtc, surface_data_rc) in gpu.surfaces.iter() {
                let mut surface_data = surface_data_rc.borrow_mut();
                surface_data.surface.reset_buffers();
                surface_data.frame_pending = false;
                surface_data.ready_to_render = true;
            }
            *needs_buffer_reset.borrow_mut() = false;
        }

        // Render to each surface that is ready
        for (crtc, surface_data_rc) in gpu.surfaces.iter() {
            let mut surface_data = surface_data_rc.borrow_mut();

            // Only render if we're ready (not waiting for vsync)
            if !surface_data.ready_to_render {
                continue;
            }

            // Catch any panics during rendering
            let render_result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                render_surface(
                    &mut gpu.renderer,
                    &mut surface_data,
                    &state,
                    &output,
                )
            }));

            match render_result {
                Ok(Ok(())) => {}
                Ok(Err(e)) => {
                    error!("Render error on {:?}: {:?}", crtc, e);
                }
                Err(panic) => {
                    error!("PANIC during render on {:?}: {:?}", crtc, panic);
                }
            }
        }
    }
}

/// Type alias for DRM notifier
type DrmNotifier = smithay::backend::drm::DrmDeviceNotifier;

fn init_gpu(
    state: &mut Flick,
    session: &mut LibSeatSession,
    path: &Path,
) -> Result<(GpuData, Output, DrmNotifier)> {
    info!("Initializing GPU from {:?}", path);

    // Open the DRM device
    let fd = session
        .open(
            path,
            smithay::reexports::rustix::fs::OFlags::RDWR
                | smithay::reexports::rustix::fs::OFlags::CLOEXEC
                | smithay::reexports::rustix::fs::OFlags::NOCTTY
                | smithay::reexports::rustix::fs::OFlags::NONBLOCK,
        )
        .map_err(|e| anyhow::anyhow!("Failed to open DRM device: {:?}", e))?;

    let fd = DrmDeviceFd::new(DeviceFd::from(fd));
    let (mut drm_device, drm_notifier) = DrmDevice::new(fd.clone(), true)
        .map_err(|e| anyhow::anyhow!("Failed to create DRM device: {:?}", e))?;

    // Create GBM device for buffer allocation
    let gbm_device = GbmDevice::new(fd.clone())
        .map_err(|e| anyhow::anyhow!("Failed to create GBM device: {:?}", e))?;

    // Create EGL display and context
    let egl_display = unsafe { EGLDisplay::new(gbm_device.clone()) }
        .map_err(|e| anyhow::anyhow!("Failed to create EGL display: {:?}", e))?;

    let egl_context = EGLContext::new(&egl_display)
        .map_err(|e| anyhow::anyhow!("Failed to create EGL context: {:?}", e))?;

    // Get supported render formats from EGL
    let render_formats = egl_context.dmabuf_render_formats().clone();
    info!("Got render formats from EGL context");

    // Create renderer
    let renderer = unsafe { GlesRenderer::new(egl_context) }
        .map_err(|e| anyhow::anyhow!("Failed to create GLES renderer: {:?}", e))?;

    info!("GPU initialized successfully");

    // Find connected outputs and create surfaces
    let res_handles = drm_device.resource_handles()
        .map_err(|e| anyhow::anyhow!("Failed to get resource handles: {:?}", e))?;

    let mut surfaces = HashMap::new();
    let mut output_result = None;

    for conn in res_handles.connectors() {
        let connector_info = drm_device.get_connector(*conn, false)
            .map_err(|e| anyhow::anyhow!("Failed to get connector info: {:?}", e))?;

        if connector_info.state() != connector::State::Connected {
            continue;
        }

        info!("Found connected display: {:?}", connector_info.interface());

        // Get preferred mode
        let mode = connector_info
            .modes()
            .iter()
            .find(|m| m.mode_type().contains(ModeTypeFlags::PREFERRED))
            .or_else(|| connector_info.modes().first())
            .copied()
            .ok_or_else(|| anyhow::anyhow!("No modes available"))?;

        let (w, h) = mode.size();
        info!("Display mode: {}x{}@{}Hz", w, h, mode.vrefresh());

        // Find a suitable CRTC
        let encoder_info = connector_info
            .current_encoder()
            .and_then(|e| drm_device.get_encoder(e).ok());

        let crtc = if let Some(encoder) = encoder_info {
            encoder.crtc().ok_or_else(|| anyhow::anyhow!("Encoder has no CRTC"))?
        } else {
            // Find any available CRTC
            *res_handles.crtcs().first()
                .ok_or_else(|| anyhow::anyhow!("No CRTCs available"))?
        };

        info!("Using CRTC: {:?}", crtc);

        // Create DRM surface
        let drm_surface = drm_device
            .create_surface(crtc, mode, &[*conn])
            .map_err(|e| anyhow::anyhow!("Failed to create DRM surface: {:?}", e))?;

        // Create GBM allocator
        let gbm_allocator = GbmAllocator::new(
            gbm_device.clone(),
            GbmBufferFlags::RENDERING | GbmBufferFlags::SCANOUT,
        );

        // Create buffered surface for double buffering
        let color_formats = [Fourcc::Argb8888, Fourcc::Xrgb8888];
        let gbm_surface = GbmBufferedSurface::new(
            drm_surface,
            gbm_allocator,
            &color_formats,
            render_formats.iter().copied(),
        )
        .map_err(|e| anyhow::anyhow!("Failed to create GBM surface: {:?}", e))?;

        // Create Wayland output
        let phys_size = connector_info.size().unwrap_or((0, 0));
        let output = Output::new(
            format!("{:?}-{}", connector_info.interface(), connector_info.interface_id()),
            PhysicalProperties {
                size: (phys_size.0 as i32, phys_size.1 as i32).into(),
                subpixel: Subpixel::Unknown,
                make: "Flick".to_string(),
                model: format!("{:?}", connector_info.interface()),
                serial_number: "Unknown".to_string(),
            },
        );

        let wl_mode = Mode {
            size: (w as i32, h as i32).into(),
            refresh: (mode.vrefresh() * 1000) as i32,
        };

        output.change_current_state(
            Some(wl_mode),
            Some(Transform::Normal),
            None,
            Some((0, 0).into()),
        );
        output.set_preferred(wl_mode);

        // IMPORTANT: Create the wl_output global so clients can see this output!
        output.create_global::<Flick>(&state.display_handle);

        state.space.map_output(&output, (0, 0));
        state.outputs.push(output.clone());

        info!("Output registered with Wayland display");

        // Create damage tracker
        let damage_tracker = OutputDamageTracker::from_output(&output);

        surfaces.insert(crtc, Rc::new(RefCell::new(SurfaceData {
            surface: gbm_surface,
            damage_tracker,
            frame_pending: false,
            ready_to_render: true,  // Start ready
        })));

        output_result = Some(output);

        info!("Output configured: {}x{}", w, h);
        break; // Just use first output for now
    }

    let output = output_result.ok_or_else(|| anyhow::anyhow!("No connected output found"))?;

    Ok((
        GpuData {
            renderer,
            gbm_device,
            drm_device,
            surfaces,
        },
        output,
        drm_notifier,
    ))
}


fn render_surface(
    renderer: &mut GlesRenderer,
    surface_data: &mut SurfaceData,
    state: &Flick,
    output: &Output,
) -> Result<()> {
    use smithay::backend::renderer::element::Kind;
    use smithay::backend::renderer::element::surface::WaylandSurfaceRenderElement;
    use crate::shell::ShellView;

    // Should already be checked by caller, but double-check
    if !surface_data.ready_to_render || surface_data.frame_pending {
        return Ok(());
    }

    // Get next buffer to render to
    let (mut dmabuf, _age) = match surface_data.surface.next_buffer() {
        Ok(buf) => buf,
        Err(e) => {
            debug!("No buffer available: {:?}", e);
            return Ok(());
        }
    };

    // Bind the dmabuf to the renderer
    let mut fb = renderer
        .bind(&mut dmabuf)
        .map_err(|e| anyhow::anyhow!("Failed to bind dmabuf: {:?}", e))?;

    let scale = output.current_scale().fractional_scale();
    let shell_view = state.shell.view;
    let gesture_active = state.shell.gesture.edge.is_some();

    // Check if home gesture is active early for background color decision
    let bottom_gesture = state.shell.gesture.edge == Some(crate::input::Edge::Bottom);

    // Check if home gesture is active (bottom edge swipe from App view)
    let home_gesture_active = shell_view == ShellView::App &&
        state.shell.gesture.edge == Some(crate::input::Edge::Bottom);

    // Choose background color based on state
    // Note: QuickSettings has its own background, so gesture_active shouldn't override it
    let bg_color = if shell_view == ShellView::LockScreen {
        [0.05, 0.05, 0.1, 1.0]  // Dark blue for lock screen
    } else if shell_view == ShellView::QuickSettings {
        [0.1, 0.1, 0.15, 1.0]  // Dark blue-gray for Quick Settings
    } else if shell_view == ShellView::Home || gesture_active || bottom_gesture {
        [0.10, 0.10, 0.18, 1.0]  // Dark blue-gray background
    } else if shell_view == ShellView::Switcher {
        [0.0, 0.3, 0.0, 1.0]  // Dark green for Switcher - should be visible
    } else {
        [0.05, 0.05, 0.15, 1.0]
    };

    tracing::info!("render_surface: view={:?}, gesture_active={}, qs_gesture_active={}, qs_progress={:.2}, bg_color={:?}",
                   shell_view, gesture_active, state.qs_gesture_active, state.qs_gesture_progress, bg_color);

    // Build Slint UI elements for shell views
    let mut slint_elements: Vec<HomeRenderElement<GlesRenderer>> = Vec::new();
    // For Switcher, we save the Slint element separately to add to switcher_elements
    let mut switcher_slint_element: Option<MemoryRenderBufferRenderElement<GlesRenderer>> = None;

    // Render shell views using Slint (lock screen, home, quick settings, pick default, switcher)
    // Also render home during home gesture so the grid shows behind the sliding app
    if shell_view == ShellView::LockScreen || shell_view == ShellView::Home || shell_view == ShellView::QuickSettings || shell_view == ShellView::PickDefault || shell_view == ShellView::Switcher || home_gesture_active {
        if let Some(ref slint_ui) = state.shell.slint_ui {
            // Update Slint UI state based on current view
            match shell_view {
                ShellView::LockScreen => {
                    slint_ui.set_view("lock");
                    slint_ui.set_lock_time(&chrono::Local::now().format("%H:%M").to_string());
                    slint_ui.set_lock_date(&chrono::Local::now().format("%A, %B %e").to_string());
                    slint_ui.set_pin_length(state.shell.lock_state.entered_pin.len() as i32);
                    if let Some(ref err) = state.shell.lock_state.error_message {
                        slint_ui.set_lock_error(err);
                    } else {
                        slint_ui.set_lock_error("");
                    }
                }
                ShellView::Home => {
                    slint_ui.set_view("home");
                    // Update categories
                    let categories = state.shell.app_manager.get_category_info();
                    let slint_categories: Vec<(String, String, [f32; 4])> = categories
                        .iter()
                        .map(|cat| {
                            let icon = cat.icon.as_deref().unwrap_or(&cat.name[..1]).to_string();
                            (cat.name.clone(), icon, cat.color)
                        })
                        .collect();
                    slint_ui.set_categories(slint_categories);

                    // Sync popup state
                    slint_ui.set_show_popup(state.shell.popup_showing);
                    if let Some(category) = state.shell.popup_category {
                        slint_ui.set_popup_category_name(category.display_name());
                        slint_ui.set_popup_can_pick_default(category.is_customizable());
                    }

                    // Sync wiggle mode
                    slint_ui.set_wiggle_mode(state.shell.wiggle_mode);

                    // Update wiggle animation time (drive animation from Rust)
                    if state.shell.wiggle_mode {
                        if let Some(start) = state.shell.wiggle_start_time {
                            let elapsed = start.elapsed().as_secs_f32();
                            slint_ui.set_wiggle_time(elapsed);
                        }
                    }
                }
                ShellView::PickDefault => {
                    slint_ui.set_view("pick-default");
                    if let Some(category) = state.shell.popup_category {
                        slint_ui.set_pick_default_category(category.display_name());
                        // Get available apps for this category
                        let apps = state.shell.app_manager.apps_for_category(category);
                        let available_apps: Vec<(String, String)> = apps
                            .iter()
                            .map(|app| (app.name.clone(), app.exec.clone()))
                            .collect();
                        slint_ui.set_available_apps(available_apps);
                        // Set current selection
                        if let Some(exec) = state.shell.app_manager.get_exec(category) {
                            slint_ui.set_current_app_selection(&exec);
                        }
                    }
                }
                ShellView::QuickSettings => {
                    tracing::info!("Rendering QuickSettings view via Slint");
                    slint_ui.set_view("quick-settings");
                    slint_ui.set_brightness(state.shell.quick_settings.brightness);
                    // Sync all toggle states from system
                    slint_ui.set_wifi_enabled(state.system.wifi_enabled);
                    slint_ui.set_bluetooth_enabled(state.system.bluetooth_enabled);
                    slint_ui.set_dnd_enabled(state.system.dnd.enabled);
                    slint_ui.set_flashlight_enabled(crate::system::Flashlight::is_on());
                    slint_ui.set_airplane_enabled(crate::system::AirplaneMode::is_enabled());
                    slint_ui.set_rotation_locked(state.system.rotation_lock.locked);
                    slint_ui.set_wifi_ssid(state.system.wifi_ssid.as_deref().unwrap_or(""));
                    slint_ui.set_battery_percent(state.shell.quick_settings.battery_percent as i32);
                }
                ShellView::Switcher => {
                    tracing::info!("Rendering Switcher view via Slint");
                    slint_ui.set_view("switcher");
                    slint_ui.set_switcher_scroll(state.shell.switcher_scroll as f32);

                    // Collect window data for Slint
                    let windows: Vec<(i32, String, String)> = state.space.elements()
                        .enumerate()
                        .map(|(i, window)| {
                            let id = i as i32;
                            let title = window.x11_surface()
                                .map(|x11| {
                                    let t = x11.title();
                                    if !t.is_empty() {
                                        t
                                    } else {
                                        let inst = x11.instance();
                                        if !inst.is_empty() {
                                            inst
                                        } else {
                                            x11.class()
                                        }
                                    }
                                })
                                .unwrap_or_else(|| format!("Window {}", i + 1));
                            let app_class = window.x11_surface()
                                .map(|x11| x11.class())
                                .unwrap_or_default();
                            (id, title, app_class)
                        })
                        .collect();
                    slint_ui.set_switcher_windows(windows);
                }
                ShellView::App => {
                    // During home gesture, show the home grid behind the sliding app
                    if home_gesture_active {
                        slint_ui.set_view("home");
                        // Update categories (same as Home view)
                        let categories = state.shell.app_manager.get_category_info();
                        let slint_categories: Vec<(String, String, [f32; 4])> = categories
                            .iter()
                            .map(|cat| {
                                let icon = cat.icon.as_deref().unwrap_or(&cat.name[..1]).to_string();
                                (cat.name.clone(), icon, cat.color)
                            })
                            .collect();
                        slint_ui.set_categories(slint_categories);
                        slint_ui.set_show_popup(false);
                        slint_ui.set_wiggle_mode(false);
                    }
                }
            }

            // Process Slint events (timers, animations) before rendering
            slint_ui.process_events();

            // Render Slint UI to pixel buffer
            slint_ui.request_redraw();
            let render_result = slint_ui.render();
            tracing::info!("Slint render result: {:?}", render_result.as_ref().map(|(w, h, _)| (*w, *h)));
            if let Some((width, height, pixels)) = render_result {
                // DEBUG: Sample center pixel from Slint output
                let center_offset = (width * height * 2) as usize; // middle of RGBA buffer
                if pixels.len() > center_offset + 4 {
                    let sample = (pixels[center_offset], pixels[center_offset+1], pixels[center_offset+2], pixels[center_offset+3]);
                    tracing::info!("UDEV: {:?} Slint center pixel RGBA={:?}", shell_view, sample);
                }

                // Create MemoryRenderBuffer from Slint's pixel output
                let mut mem_buffer = MemoryRenderBuffer::new(
                    Fourcc::Abgr8888, // RGBA in little-endian byte order
                    (width as i32, height as i32),
                    1, // scale
                    Transform::Normal,
                    None,
                );

                // Write pixels into buffer
                let pixels_clone = pixels.clone();
                let _: Result<(), std::convert::Infallible> = mem_buffer.render().draw(|buffer| {
                    buffer.copy_from_slice(&pixels_clone);
                    Ok(vec![Rectangle::from_size((width as i32, height as i32).into())])
                });

                // Create render element
                let loc: smithay::utils::Point<i32, smithay::utils::Physical> = (0, 0).into();
                match MemoryRenderBufferRenderElement::from_buffer(
                    renderer,
                    loc.to_f64(),
                    &mem_buffer,
                    None,
                    None,
                    None,
                    Kind::Unspecified,
                ) {
                    Ok(slint_element) => {
                        // For Switcher, save the element to add to switcher_elements later
                        // For other views, add to slint_elements as normal
                        if shell_view == ShellView::Switcher {
                            switcher_slint_element = Some(slint_element);
                            tracing::info!("Slint {:?} element saved for switcher_elements", shell_view);
                        } else {
                            slint_elements.push(HomeRenderElement::Icon(slint_element));
                            tracing::info!("Slint {:?} element created and pushed", shell_view);
                        }
                    }
                    Err(e) => {
                        tracing::error!("Failed to create Slint render element: {:?}", e);
                    }
                }
            }
        } else {
            tracing::warn!("slint_ui is None, cannot render {:?}", shell_view);
        }
    } else {
        tracing::debug!("View {:?} not rendered via Slint (not in Slint render list)", shell_view);
    }

    // Switcher uses a separate element type that can hold both solid colors and window content
    let mut switcher_elements: Vec<SwitcherRenderElement<GlesRenderer>> = Vec::new();

    if shell_view == ShellView::Switcher {
        // Android-style stacked card switcher with depth and scale effects
        // NOTE: Elements must be in FRONT-TO-BACK order (front first, background last)
        let screen_w = state.screen_size.w as f64;
        let screen_h = state.screen_size.h as f64;

        let window_count = state.space.elements().count();

        // Stacked card layout - cards overlap significantly like Android
        // Base card dimensions (focused card)
        let base_card_width = (screen_w * 0.80) as i32;  // 80% of screen width
        let base_card_height = (screen_h * 0.58) as i32; // 58% of screen height (leave room for title)
        let card_spacing = base_card_width as f64 * 0.35; // 35% spacing = 65% overlap

        // Center of screen for card positioning
        let center_y = screen_h / 2.0;

        let scroll_offset = state.shell.switcher_scroll;
        let focused_index = state.shell.get_focused_card_index(card_spacing);

        // Build card data with window references
        let windows: Vec<_> = state.space.elements().cloned().collect();

        // Sort windows by distance from focused position (focused card rendered first = on top)
        // Front-to-back order means first rendered = in front
        let mut sorted_indices: Vec<usize> = (0..windows.len()).collect();
        sorted_indices.sort_by(|&a, &b| {
            let dist_a = ((a as f64 * card_spacing - scroll_offset) / card_spacing).abs();
            let dist_b = ((b as f64 * card_spacing - scroll_offset) / card_spacing).abs();
            dist_a.partial_cmp(&dist_b).unwrap()
        });

        // First pass: collect card backgrounds (rendered behind window content)
        let mut card_backgrounds: Vec<SwitcherRenderElement<GlesRenderer>> = Vec::new();

        // Render cards sorted by distance from center (closest = on top)
        for &i in sorted_indices.iter() {
            let window = &windows[i];
            // Calculate card position relative to scroll
            let card_scroll_pos = i as f64 * card_spacing - scroll_offset;
            let normalized_pos = card_scroll_pos / card_spacing;
            let distance = normalized_pos.abs();
            let scale_factor = (1.0 - distance * 0.12).max(0.7);

            let card_width = (base_card_width as f64 * scale_factor) as i32;
            let card_height = (base_card_height as f64 * scale_factor) as i32;
            let x_offset = card_scroll_pos + (screen_w - card_width as f64) / 2.0;
            let x_pos = x_offset as i32;
            let y_offset = distance * 20.0;
            let y_pos = ((center_y - card_height as f64 / 2.0) + y_offset) as i32;

            // Skip off-screen cards
            if x_pos + card_width < -200 || x_pos > screen_w as i32 + 200 {
                continue;
            }

            // Get window geometry first to calculate actual preview size
            let window_geo = window.geometry();

            // Calculate scale to fit window in card area
            let max_content_width = card_width - 16; // max width with padding
            let max_content_height = card_height - 16;
            let scale_x = max_content_width as f64 / window_geo.size.w as f64;
            let scale_y = max_content_height as f64 / window_geo.size.h as f64;
            let fit_scale = f64::min(scale_x, scale_y);

            // Actual scaled window dimensions
            let scaled_w = (window_geo.size.w as f64 * fit_scale) as i32;
            let scaled_h = (window_geo.size.h as f64 * fit_scale) as i32;

            // Background size = window size + padding
            let padding = 8;
            let bg_width = scaled_w + padding * 2;
            let bg_height = scaled_h + padding * 2;

            // Center the background horizontally, position based on scroll
            let bg_x = x_pos + (card_width - bg_width) / 2;
            let bg_y = y_pos + (card_height - bg_height) / 2;

            // Card background color (darker for cards further away)
            let bg_brightness = (0.24 - distance * 0.04).max(0.15) as f32;
            let card_bg_color = [bg_brightness, bg_brightness, bg_brightness + 0.05, 1.0];

            // Create card background element sized to match window preview
            use smithay::backend::renderer::element::solid::SolidColorBuffer;
            let card_buffer = SolidColorBuffer::new((bg_width, bg_height), card_bg_color);
            let card_bg = SolidColorRenderElement::from_buffer(
                &card_buffer,
                (bg_x, bg_y),
                Scale::from(1.0),
                1.0,
                Kind::Unspecified,
            );
            card_backgrounds.push(SwitcherRenderElement::Solid(card_bg));

            // Get window render elements
            let window_render_elements: Vec<WaylandSurfaceRenderElement<GlesRenderer>> = window
                .render_elements::<WaylandSurfaceRenderElement<GlesRenderer>>(
                    renderer,
                    (0, 0).into(),
                    Scale::from(scale),
                    1.0,
                );

            // Window content position (centered in background)
            let final_x = bg_x + padding;
            let final_y = bg_y + padding;

            let crop_rect: Rectangle<i32, smithay::utils::Physical> = Rectangle::new(
                (final_x, final_y).into(),
                (scaled_w, scaled_h).into(),
            );

            // Add window content (front-to-back order)
            for elem in window_render_elements {
                let scaled = RescaleRenderElement::from_element(
                    elem,
                    (0, 0).into(),
                    Scale::from(fit_scale),
                );
                let final_pos: smithay::utils::Point<i32, smithay::utils::Physical> = (final_x, final_y).into();
                let relocated = RelocateRenderElement::from_element(
                    scaled,
                    final_pos,
                    Relocate::Absolute,
                );
                if let Some(cropped) = CropRenderElement::from_element(
                    relocated,
                    Scale::from(scale),
                    crop_rect,
                ) {
                    switcher_elements.push(cropped.into());
                }
            }
        }

        // Add card backgrounds after window content (they render behind)
        switcher_elements.extend(card_backgrounds);

        // Second pass: render window titles below cards (same sorted order)
        for &i in sorted_indices.iter() {
            let window = &windows[i];
            let card_scroll_pos = i as f64 * card_spacing - scroll_offset;
            let normalized_pos = card_scroll_pos / card_spacing;
            let distance = normalized_pos.abs();
            let scale_factor = (1.0 - distance * 0.12).max(0.7);

            let card_width = (base_card_width as f64 * scale_factor) as i32;
            let card_height = (base_card_height as f64 * scale_factor) as i32;
            let x_offset = card_scroll_pos + (screen_w - card_width as f64) / 2.0;
            let x_pos = x_offset as i32;
            let y_offset = distance * 20.0;
            let y_pos = ((center_y - card_height as f64 / 2.0) + y_offset) as i32;

            // Skip off-screen cards
            if x_pos + card_width < -200 || x_pos > screen_w as i32 + 200 {
                continue;
            }

            // Get window title
            let title = window.x11_surface()
                .map(|x11| {
                    let t = x11.title();
                    if t.is_empty() { x11.class() } else { t }
                })
                .unwrap_or_else(|| "Window".to_string());

            // Truncate title if too long
            let max_chars = 20;
            let title: String = if title.len() > max_chars {
                format!("{}...", &title[..max_chars-3])
            } else {
                title
            };

            // Render title as bitmap text (small rectangles)
            let text_scale = 2.0; // 2x scale for readability
            let char_width = 5.0 * text_scale;
            let char_spacing = 1.0 * text_scale;
            let text_width = title.len() as f64 * (char_width + char_spacing) - char_spacing;
            let text_x = x_pos as f64 + (card_width as f64 - text_width) / 2.0;
            let text_y = (y_pos + card_height + 12) as f64; // 12px below card

            // Text color (white with slight transparency for depth)
            let text_alpha = (1.0 - distance * 0.15).max(0.6) as f32;
            let text_color = [1.0, 1.0, 1.0, text_alpha];

            // Simple bitmap font - render each character
            use smithay::backend::renderer::element::solid::SolidColorBuffer;
            let mut cursor_x = text_x;
            for c in title.chars() {
                let bitmap = get_char_bitmap(c);
                for (row, &row_bits) in bitmap.iter().enumerate() {
                    for col in 0..5u8 {
                        if (row_bits >> (4 - col)) & 1 == 1 {
                            let px = (cursor_x + col as f64 * text_scale) as i32;
                            let py = (text_y + row as f64 * text_scale) as i32;
                            let pixel_buffer = SolidColorBuffer::new(
                                (text_scale as i32, text_scale as i32),
                                text_color,
                            );
                            let pixel_elem = SolidColorRenderElement::from_buffer(
                                &pixel_buffer,
                                (px, py),
                                Scale::from(1.0),
                                1.0,
                                Kind::Unspecified,
                            );
                            switcher_elements.push(SwitcherRenderElement::Solid(pixel_elem));
                        }
                    }
                }
                cursor_x += char_width + char_spacing;
            }
        }

        // Add Slint backdrop element (background, header, text)
        if let Some(slint_elem) = switcher_slint_element {
            switcher_elements.push(SwitcherRenderElement::Icon(slint_elem));
        }

        tracing::debug!("Switcher: {} windows, focused={}, scroll={:.1}", window_count, focused_index, scroll_offset);
    }

    // Render based on what view we're in
    // For Switcher: use a fresh damage tracker to guarantee full redraw
    let mut fresh_tracker = if shell_view == ShellView::Switcher {
        tracing::info!("{:?}: creating fresh damage tracker for full redraw", shell_view);
        Some(OutputDamageTracker::from_output(output))
    } else {
        None
    };

    let render_res = if shell_view == ShellView::Switcher {
        // Switcher view - render window cards
        let tracker = fresh_tracker.as_mut().unwrap();
        tracker.render_output(
            renderer,
            &mut fb,
            0,  // age=0 for full redraw
            &switcher_elements,
            bg_color,
        )
    } else if (shell_view == ShellView::LockScreen || shell_view == ShellView::Home || shell_view == ShellView::PickDefault || shell_view == ShellView::QuickSettings) && !state.qs_gesture_active {
        // Shell views - render Slint UI (but not during QS gesture transition)
        tracing::info!("Rendering {:?} with {} slint_elements, bg={:?}", shell_view, slint_elements.len(), bg_color);
        surface_data.damage_tracker.render_output(
            renderer,
            &mut fb,
            0, // Force full redraw for Slint views
            &slint_elements,
            bg_color,
        )
    } else if home_gesture_active {
        // During home gesture: render home grid with ONLY the topmost window sliding UP
        use smithay::backend::renderer::element::surface::WaylandSurfaceRenderElement;
        use smithay::backend::renderer::element::utils::{RescaleRenderElement, Relocate, RelocateRenderElement, CropRenderElement};

        let mut home_gesture_elements: Vec<SwitcherRenderElement<GlesRenderer>> = Vec::new();

        // Add the topmost window FIRST (will be rendered on top - front-to-back order)
        if let Some(ref window) = state.home_gesture_window {
            if let Some(loc) = state.space.element_location(window) {
                // Get window render elements at origin
                let window_render_elements: Vec<WaylandSurfaceRenderElement<GlesRenderer>> = window
                    .render_elements::<WaylandSurfaceRenderElement<GlesRenderer>>(
                        renderer,
                        (0, 0).into(),
                        Scale::from(scale),
                        1.0,
                    );

                tracing::info!("Home gesture: rendering window at loc=({}, {}), {} elements",
                    loc.x, loc.y, window_render_elements.len());

                // Relocate each element to the window's current position in the space
                // Use screen-sized crop rect to ensure window isn't clipped when moving up
                let screen_w = state.screen_size.w;
                let screen_h = state.screen_size.h * 2; // Extra height for off-screen
                let crop_rect: Rectangle<i32, smithay::utils::Physical> = Rectangle::new(
                    (-screen_w, -screen_h).into(),
                    (screen_w * 3, screen_h * 2).into(),
                );

                for elem in window_render_elements {
                    let scaled = RescaleRenderElement::from_element(elem, (0, 0).into(), Scale::from(1.0));
                    let final_pos: smithay::utils::Point<i32, smithay::utils::Physical> = (loc.x, loc.y).into();
                    let relocated = RelocateRenderElement::from_element(scaled, final_pos, Relocate::Relative);
                    // Wrap in CropRenderElement to match SwitcherRenderElement::Window type
                    if let Some(cropped) = CropRenderElement::from_element(relocated, Scale::from(scale), crop_rect) {
                        home_gesture_elements.push(cropped.into());
                    }
                }
            }
        } else {
            tracing::warn!("Home gesture active but no home_gesture_window set!");
        }

        // Add Slint home grid elements AFTER window (will be behind in front-to-back order)
        for elem in slint_elements.into_iter() {
            match elem {
                HomeRenderElement::Icon(icon) => home_gesture_elements.push(SwitcherRenderElement::Icon(icon)),
                HomeRenderElement::Solid(solid) => home_gesture_elements.push(SwitcherRenderElement::Solid(solid)),
                _ => {}
            }
        }

        tracing::info!("Home gesture: total {} elements", home_gesture_elements.len());

        surface_data.damage_tracker.render_output(
            renderer,
            &mut fb,
            0, // Force full redraw during gesture
            &home_gesture_elements,
            bg_color,
        )
    } else if state.switcher_gesture_active {
        // During switcher gesture: render all apps transitioning to card positions
        use smithay::backend::renderer::element::surface::WaylandSurfaceRenderElement;
        use smithay::backend::renderer::element::solid::SolidColorBuffer;

        let progress = state.switcher_gesture_progress;
        let screen_w = state.screen_size.w as f64;
        let screen_h = state.screen_size.h as f64;

        // Target card dimensions (same as switcher render code)
        let base_card_width = (screen_w * 0.80) as i32;
        let base_card_height = (screen_h * 0.58) as i32;
        let card_spacing = base_card_width as f64 * 0.35;
        let center_y = screen_h / 2.0;

        let windows: Vec<_> = state.space.elements().cloned().collect();
        let mut transition_elements: Vec<SwitcherRenderElement<GlesRenderer>> = Vec::new();
        let num_windows = windows.len();

        // When the switcher opens, scroll_offset = (num_windows - 1) * card_spacing
        // so topmost window (last in list) is centered at position 0.
        // During transition, simulate this same scroll offset.
        let target_scroll_offset = (num_windows.saturating_sub(1)) as f64 * card_spacing;

        for (i, window) in windows.iter().enumerate() {
            let window_geo = window.geometry();
            let is_topmost = i == num_windows - 1;

            // Use same formula as switcher: i * card_spacing - scroll_offset
            let card_scroll_pos = i as f64 * card_spacing - target_scroll_offset;

            // Card scale based on position (same as switcher)
            let normalized_pos = card_scroll_pos / card_spacing;
            let distance = normalized_pos.abs();
            let card_scale_factor = (1.0 - distance * 0.12).max(0.7);

            let card_width = (base_card_width as f64 * card_scale_factor) as i32;
            let card_height = (base_card_height as f64 * card_scale_factor) as i32;

            // Target card position
            let card_x_offset = card_scroll_pos + (screen_w - card_width as f64) / 2.0;
            let card_x = card_x_offset as i32;
            let card_y_offset = distance * 20.0;
            let card_y = ((center_y - card_height as f64 / 2.0) + card_y_offset) as i32;

            // Calculate window scale to fit in card
            let max_content_width = card_width - 16;
            let max_content_height = card_height - 16;
            let scale_x = max_content_width as f64 / window_geo.size.w as f64;
            let scale_y = max_content_height as f64 / window_geo.size.h as f64;
            let target_scale = f64::min(scale_x, scale_y);

            let scaled_w = (window_geo.size.w as f64 * target_scale) as i32;
            let scaled_h = (window_geo.size.h as f64 * target_scale) as i32;
            let padding = 8;
            let bg_width = scaled_w + padding * 2;
            let bg_height = scaled_h + padding * 2;
            let target_x = card_x + (card_width - bg_width) / 2 + padding;
            let target_y = card_y + (card_height - bg_height) / 2 + padding;
            let bg_x = card_x + (card_width - bg_width) / 2;
            let bg_y = card_y + (card_height - bg_height) / 2;

            if is_topmost {
                // Topmost window: interpolate from fullscreen to card position
                let current_scale = 1.0 + (target_scale - 1.0) * progress;
                let current_x = (0.0 + target_x as f64 * progress) as i32;
                let current_y = (0.0 + target_y as f64 * progress) as i32;
                let current_w = (window_geo.size.w as f64 * current_scale) as i32;
                let current_h = (window_geo.size.h as f64 * current_scale) as i32;

                // Card background (interpolate size and position)
                if progress > 0.1 {
                    let bg_alpha = ((progress - 0.1) / 0.9).min(1.0) as f32;
                    let interp_bg_w = screen_w as i32 + ((bg_width - screen_w as i32) as f64 * progress) as i32;
                    let interp_bg_h = screen_h as i32 + ((bg_height - screen_h as i32) as f64 * progress) as i32;
                    let interp_bg_x = (0.0 + bg_x as f64 * progress) as i32;
                    let interp_bg_y = (0.0 + bg_y as f64 * progress) as i32;

                    let card_buffer = SolidColorBuffer::new((interp_bg_w, interp_bg_h), [0.24, 0.24, 0.29, bg_alpha]);
                    let card_bg = SolidColorRenderElement::from_buffer(&card_buffer, (interp_bg_x, interp_bg_y), Scale::from(1.0), 1.0, Kind::Unspecified);
                    transition_elements.push(SwitcherRenderElement::Solid(card_bg));
                }

                // Window content
                let window_render_elements: Vec<WaylandSurfaceRenderElement<GlesRenderer>> = window
                    .render_elements::<WaylandSurfaceRenderElement<GlesRenderer>>(renderer, (0, 0).into(), Scale::from(scale), 1.0);

                let crop_rect: Rectangle<i32, smithay::utils::Physical> = Rectangle::new((current_x, current_y).into(), (current_w, current_h).into());

                for elem in window_render_elements {
                    let scaled = RescaleRenderElement::from_element(elem, (0, 0).into(), Scale::from(current_scale));
                    let final_pos: smithay::utils::Point<i32, smithay::utils::Physical> = (current_x, current_y).into();
                    let relocated = RelocateRenderElement::from_element(scaled, final_pos, Relocate::Absolute);
                    if let Some(cropped) = CropRenderElement::from_element(relocated, Scale::from(scale), crop_rect) {
                        transition_elements.insert(0, cropped.into());
                    }
                }
            } else {
                // Other windows: fade in at their card positions
                let alpha = (progress * 1.5).min(1.0) as f32; // Fade in faster
                if alpha > 0.05 {
                    // Card background
                    let card_buffer = SolidColorBuffer::new((bg_width, bg_height), [0.24, 0.24, 0.29, alpha]);
                    let card_bg = SolidColorRenderElement::from_buffer(&card_buffer, (bg_x, bg_y), Scale::from(1.0), 1.0, Kind::Unspecified);
                    transition_elements.push(SwitcherRenderElement::Solid(card_bg));

                    // Window content
                    let window_render_elements: Vec<WaylandSurfaceRenderElement<GlesRenderer>> = window
                        .render_elements::<WaylandSurfaceRenderElement<GlesRenderer>>(renderer, (0, 0).into(), Scale::from(scale), alpha);

                    let crop_rect: Rectangle<i32, smithay::utils::Physical> = Rectangle::new((target_x, target_y).into(), (scaled_w, scaled_h).into());

                    for elem in window_render_elements {
                        let scaled_elem = RescaleRenderElement::from_element(elem, (0, 0).into(), Scale::from(target_scale));
                        let final_pos: smithay::utils::Point<i32, smithay::utils::Physical> = (target_x, target_y).into();
                        let relocated = RelocateRenderElement::from_element(scaled_elem, final_pos, Relocate::Absolute);
                        if let Some(cropped) = CropRenderElement::from_element(relocated, Scale::from(scale), crop_rect) {
                            transition_elements.push(cropped.into());
                        }
                    }
                }
            }
        }

        // Render with switcher background color
        surface_data.damage_tracker.render_output(
            renderer,
            &mut fb,
            0, // Force full redraw during gesture
            &transition_elements,
            [0.1, 0.1, 0.12, 1.0], // Switcher background
        )
    } else if state.qs_gesture_active {
        // During quick settings gesture: slide current view right, reveal QS panel from left
        // Use simple solid color panel for smooth animation (full UI renders on completion)
        use smithay::backend::renderer::element::surface::WaylandSurfaceRenderElement;
        use smithay::backend::renderer::element::solid::SolidColorBuffer;
        use smithay::backend::renderer::element::utils::{RescaleRenderElement, Relocate, RelocateRenderElement, CropRenderElement};

        let progress = state.qs_gesture_progress;
        let screen_w = state.screen_size.w;
        let screen_h = state.screen_size.h;

        // Current view slides right based on progress
        let slide_offset = (progress * screen_w as f64 * 0.85) as i32;

        let mut qs_elements: Vec<SwitcherRenderElement<GlesRenderer>> = Vec::new();

        // Add QS panel background (solid color sliding in from left - fast!)
        // Panel reveals from left edge as current view slides right
        let panel_width = slide_offset.max(0);
        if panel_width > 0 {
            let panel_buffer = SolidColorBuffer::new(
                (panel_width, screen_h),
                [0.1, 0.1, 0.18, 1.0], // QS background color
            );
            let panel_bg = SolidColorRenderElement::from_buffer(
                &panel_buffer,
                (0, 0),
                Scale::from(1.0),
                1.0,
                Kind::Unspecified,
            );
            qs_elements.push(SwitcherRenderElement::Solid(panel_bg));
        }

        // Add windows sliding to the right (home grid not shown during gesture for performance)
        let windows: Vec<_> = state.space.elements().cloned().collect();
        for window in windows.iter() {
            if let Some(loc) = state.space.element_location(window) {
                let window_render_elements: Vec<WaylandSurfaceRenderElement<GlesRenderer>> = window
                    .render_elements::<WaylandSurfaceRenderElement<GlesRenderer>>(
                        renderer,
                        (0, 0).into(),
                        Scale::from(scale),
                        1.0,
                    );

                let crop_rect: Rectangle<i32, smithay::utils::Physical> = Rectangle::new(
                    (-screen_w, -screen_h).into(),
                    (screen_w * 3, screen_h * 3).into(),
                );

                for elem in window_render_elements {
                    let scaled = RescaleRenderElement::from_element(elem, (0, 0).into(), Scale::from(1.0));
                    let final_pos: smithay::utils::Point<i32, smithay::utils::Physical> = (loc.x + slide_offset, loc.y).into();
                    let relocated = RelocateRenderElement::from_element(scaled, final_pos, Relocate::Relative);
                    if let Some(cropped) = CropRenderElement::from_element(relocated, Scale::from(scale), crop_rect) {
                        qs_elements.insert(0, cropped.into());
                    }
                }
            }
        }

        surface_data.damage_tracker.render_output(
            renderer,
            &mut fb,
            0,
            &qs_elements,
            [0.1, 0.1, 0.18, 1.0],
        )
    } else {
        // App view - render windows
        use smithay::backend::renderer::element::surface::WaylandSurfaceRenderElement;
        use smithay::desktop::space::SpaceRenderElements;

        let window_elements: Vec<SpaceRenderElements<GlesRenderer, WaylandSurfaceRenderElement<GlesRenderer>>> = state
            .space
            .render_elements_for_output(renderer, output, scale as f32)
            .unwrap_or_default();

        // Render windows
        surface_data.damage_tracker.render_output(
            renderer,
            &mut fb,
            _age as usize,
            &window_elements,
            bg_color,
        )
    };

    match render_res {
        Ok(render_output_result) => {
            // Log render result for debugging
            let has_damage = render_output_result.damage.is_some();
            let damage_rects = render_output_result.damage.as_ref().map(|d| d.len()).unwrap_or(0);
            if shell_view == ShellView::Switcher {
                tracing::info!("{:?} render OK: has_damage={}, damage_rects={}", shell_view, has_damage, damage_rects);
            }

            // Get sync point from the render
            let sync_point = render_output_result.sync.clone();

            // Queue the buffer with damage info
            match surface_data.surface.queue_buffer(
                Some(sync_point),
                render_output_result.damage.cloned(),
                (),
            ) {
                Ok(_) => {
                    surface_data.frame_pending = true;
                    surface_data.ready_to_render = false;
                    if shell_view == ShellView::Switcher {
                        tracing::info!("{:?} frame queued successfully", shell_view);
                    }
                    debug!("Frame queued successfully");
                }
                Err(e) => {
                    warn!("Failed to queue buffer: {:?}", e);
                    surface_data.surface.reset_buffers();
                }
            }
        }
        Err(e) => {
            warn!("Render error: {:?}", e);
            if shell_view == ShellView::Switcher {
                tracing::error!("Switcher render FAILED: {:?}", e);
            }
            surface_data.surface.reset_buffers();
        }
    }

    // Send frame callbacks to clients so they know to render
    state.space.elements().for_each(|window| {
        window.send_frame(
            output,
            state.start_time.elapsed(),
            Some(Duration::ZERO),
            |_, _| Some(output.clone()),
        );
    });

    Ok(())
}

/// Handle input events including VT switching
fn handle_input_event(
    state: &mut Flick,
    event: InputEvent<LibinputInputBackend>,
    session: &Rc<RefCell<LibSeatSession>>,
    modifiers: &Rc<RefCell<ModifierState>>,
) {
    use smithay::backend::input::{
        KeyState, KeyboardKeyEvent, PointerMotionEvent, PointerButtonEvent,
        Event,
    };
    use smithay::input::keyboard::FilterResult;

    // Log ALL input events to debug touch handling
    match &event {
        InputEvent::TouchDown { .. } => info!("INPUT: TouchDown event received"),
        InputEvent::TouchMotion { .. } => {} // too spammy
        InputEvent::TouchUp { .. } => info!("INPUT: TouchUp event received"),
        InputEvent::PointerMotionAbsolute { event } => {
            use smithay::backend::input::AbsolutePositionEvent;
            info!("INPUT: PointerMotionAbsolute at ({:.0}, {:.0})",
                event.x_transformed(1920), event.y_transformed(1200));
        }
        InputEvent::PointerMotion { .. } => {} // spammy relative motion
        InputEvent::PointerButton { .. } => info!("INPUT: PointerButton event received"),
        InputEvent::TabletToolProximity { .. } => info!("INPUT: TabletToolProximity"),
        InputEvent::TabletToolTip { .. } => info!("INPUT: TabletToolTip"),
        _ => {}
    }

    match event {
        InputEvent::Keyboard { event } => {
            let keycode = event.key_code();
            let raw_keycode: u32 = keycode.raw();
            let key_state = event.state();
            let pressed = key_state == KeyState::Pressed;

            // Smithay Keycode.raw() returns XKB keycodes (evdev + 8)
            // Subtract 8 to get the raw evdev keycode
            let evdev_keycode = raw_keycode.saturating_sub(8);
            debug!("Keyboard event: xkb_keycode={}, evdev_keycode={}, pressed={}", raw_keycode, evdev_keycode, pressed);

            // Track modifier state for VT switching, shortcuts, and password input
            // Evdev keycodes: 29=LCtrl, 97=RCtrl, 56=LAlt, 100=RAlt, 42=LShift, 54=RShift, 125=LSuper, 126=RSuper
            match evdev_keycode {
                29 | 97 => {
                    modifiers.borrow_mut().ctrl = pressed;
                }
                56 | 100 => {
                    modifiers.borrow_mut().alt = pressed;
                }
                42 | 54 => {
                    modifiers.borrow_mut().shift = pressed;
                }
                125 | 126 => {
                    modifiers.borrow_mut().super_key = pressed;
                }
                _ => {}
            }

            // Check for VT switch: Ctrl+Alt+F1-F12
            // F1-F12 evdev keycodes: 59-70
            if pressed {
                let mods = modifiers.borrow();
                if mods.ctrl && mods.alt {
                    if evdev_keycode >= 59 && evdev_keycode <= 70 {
                        let vt = (evdev_keycode - 59 + 1) as i32;
                        info!("VT switch requested: F{} -> VT{}", evdev_keycode - 58, vt);
                        if let Err(e) = session.borrow_mut().change_vt(vt) {
                            error!("Failed to switch VT: {:?}", e);
                        }
                        return;
                    }
                }
            }

            // Power button (evdev keycode 116) locks the screen
            if evdev_keycode == 116 && pressed {
                if state.shell.view != crate::shell::ShellView::LockScreen {
                    info!("Power button pressed, locking screen");
                    state.shell.lock();
                }
                return;
            }

            // Super+L (evdev: L=38) locks the screen
            if evdev_keycode == 38 && pressed {
                let mods = modifiers.borrow();
                if mods.super_key {
                    drop(mods); // Release borrow before calling lock()
                    if state.shell.view != crate::shell::ShellView::LockScreen {
                        info!("Super+L pressed, locking screen");
                        state.shell.lock();
                    }
                    return;
                }
            }

            // Handle keyboard input for lock screen password mode
            if state.shell.view == crate::shell::ShellView::LockScreen {
                if state.shell.lock_state.input_mode == crate::shell::lock_screen::LockInputMode::Password {
                    if pressed {
                        // Common keycodes (evdev):
                        // Enter = 28, Backspace = 14
                        // Letters a-z = 30-38, 44-50, 16-25
                        // Numbers 0-9 = 11, 2-10
                        match evdev_keycode {
                            28 => {
                                // Enter - attempt unlock
                                if !state.shell.lock_state.entered_password.is_empty() {
                                    state.shell.try_unlock();
                                }
                            }
                            14 => {
                                // Backspace
                                state.shell.lock_state.entered_password.pop();
                            }
                            _ => {
                                // Try to convert keycode to character
                                // This is a simplified mapping - a full implementation would use xkb
                                let mods = modifiers.borrow();
                                let char_opt = evdev_to_char(evdev_keycode, mods.shift);
                                if let Some(c) = char_opt {
                                    if state.shell.lock_state.entered_password.len() < 64 {
                                        state.shell.lock_state.entered_password.push(c);
                                    }
                                }
                            }
                        }
                    }
                    // Don't forward keyboard events to clients when on lock screen
                    return;
                }
            }

            // Forward keyboard event to clients
            let serial = smithay::utils::SERIAL_COUNTER.next_serial();
            let time = Event::time_msec(&event);
            if let Some(keyboard) = state.seat.get_keyboard() {
                // Check if we have focus
                let has_focus = keyboard.current_focus().is_some();
                debug!("Forwarding key {} to client, has_focus={}", raw_keycode, has_focus);

                keyboard.input::<(), _>(
                    state,
                    keycode,
                    key_state,
                    serial,
                    time,
                    |_, _, _| FilterResult::Forward,
                );
            } else {
                warn!("No keyboard available to forward events");
            }
        }
        InputEvent::PointerMotion { event } => {
            let delta = event.delta();
            debug!("Pointer motion: delta=({}, {})", delta.x, delta.y);

            // Get pointer and notify of relative motion
            if let Some(pointer) = state.seat.get_pointer() {
                let serial = smithay::utils::SERIAL_COUNTER.next_serial();
                let mut pointer_pos = pointer.current_location();
                pointer_pos.x += delta.x;
                pointer_pos.y += delta.y;

                // Clamp to screen bounds
                let screen = state.screen_size;
                pointer_pos.x = pointer_pos.x.clamp(0.0, screen.w as f64);
                pointer_pos.y = pointer_pos.y.clamp(0.0, screen.h as f64);

                // Find surface under pointer (handles both Wayland and X11 windows)
                let under = state.space.element_under(pointer_pos)
                    .map(|(window, loc)| {
                        let surface = window.toplevel()
                            .map(|t| t.wl_surface().clone())
                            .or_else(|| window.x11_surface().and_then(|x| x.wl_surface()));
                        (surface, loc)
                    });

                let focus = under.as_ref().and_then(|(surface, loc)| {
                    surface.as_ref().map(|s| (s.clone(), loc.to_f64()))
                });

                pointer.motion(
                    state,
                    focus,
                    &smithay::input::pointer::MotionEvent {
                        location: pointer_pos,
                        serial,
                        time: Event::time_msec(&event),
                    },
                );
            }
        }
        InputEvent::PointerMotionAbsolute { event } => {
            use smithay::backend::input::AbsolutePositionEvent;

            debug!("Pointer motion absolute");
            if let Some(pointer) = state.seat.get_pointer() {
                let serial = smithay::utils::SERIAL_COUNTER.next_serial();
                let screen = state.screen_size;
                let pointer_pos = smithay::utils::Point::<f64, smithay::utils::Logical>::from((
                    event.x_transformed(screen.w),
                    event.y_transformed(screen.h),
                ));

                // Find surface under pointer (handles both Wayland and X11 windows)
                let under = state.space.element_under(pointer_pos)
                    .map(|(window, loc)| {
                        let surface = window.toplevel()
                            .map(|t| t.wl_surface().clone())
                            .or_else(|| window.x11_surface().and_then(|x| x.wl_surface()));
                        (surface, loc)
                    });

                let focus = under.as_ref().and_then(|(surface, loc)| {
                    surface.as_ref().map(|s| (s.clone(), loc.to_f64()))
                });

                pointer.motion(
                    state,
                    focus,
                    &smithay::input::pointer::MotionEvent {
                        location: pointer_pos,
                        serial,
                        time: Event::time_msec(&event),
                    },
                );
            }
        }
        InputEvent::PointerButton { event } => {
            use smithay::backend::input::ButtonState;

            let button = event.button_code();
            let button_state = event.state();
            debug!("Pointer button: {} {:?}", button, button_state);

            if let Some(pointer) = state.seat.get_pointer() {
                let serial = smithay::utils::SERIAL_COUNTER.next_serial();

                // On click, set keyboard focus to the window under the pointer
                if button_state == ButtonState::Pressed {
                    let pointer_pos = pointer.current_location();
                    if let Some((window, _)) = state.space.element_under(pointer_pos) {
                        // Handle both Wayland and X11 windows
                        let wl_surface = window.toplevel()
                            .map(|t| t.wl_surface().clone())
                            .or_else(|| window.x11_surface().and_then(|x| x.wl_surface()));
                        if let Some(surface) = wl_surface {
                            if let Some(keyboard) = state.seat.get_keyboard() {
                                keyboard.set_focus(state, Some(surface), serial);
                                debug!("Keyboard focus set via click");
                            }
                        }
                    }
                }

                pointer.button(
                    state,
                    &smithay::input::pointer::ButtonEvent {
                        button,
                        state: button_state,
                        serial,
                        time: Event::time_msec(&event),
                    },
                );
            }
        }
        InputEvent::TouchDown { event } => {
            use smithay::backend::input::{TouchEvent, AbsolutePositionEvent};

            debug!("Touch down at slot {:?}", event.slot());
            let screen = state.screen_size;
            let touch_pos = smithay::utils::Point::<f64, smithay::utils::Logical>::from((
                event.x_transformed(screen.w),
                event.y_transformed(screen.h),
            ));

            // Feed to gesture recognizer (use slot id or 0 for single-touch)
            let slot_id: i32 = event.slot().into();

            // Debug: Log touch position and screen size
            info!("Touch down at ({:.0}, {:.0}), screen size: {:?}", touch_pos.x, touch_pos.y, screen);

            if let Some(gesture_event) = state.gesture_recognizer.touch_down(slot_id, touch_pos) {
                info!("Gesture touch_down returned: {:?}", gesture_event);
                // In Switcher view, ignore left/right edge gestures to allow horizontal scrolling
                let should_process = if state.shell.view == crate::shell::ShellView::Switcher {
                    if let crate::input::GestureEvent::EdgeSwipeStart { edge, .. } = &gesture_event {
                        // Only process top/bottom edge gestures in Switcher (for going home/closing)
                        // Cancel left/right edge gestures to allow horizontal scrolling
                        if *edge == crate::input::Edge::Left || *edge == crate::input::Edge::Right {
                            state.gesture_recognizer.touch_cancel(); // Cancel the edge gesture
                            false
                        } else {
                            true
                        }
                    } else {
                        true
                    }
                } else {
                    true
                };

                if should_process {
                    info!("Gesture started: {:?}", gesture_event);
                    // Update integrated shell state
                    state.shell.handle_gesture(&gesture_event);

                    // Start close gesture animation when swiping from top
                    if let crate::input::GestureEvent::EdgeSwipeStart { edge, .. } = &gesture_event {
                        if *edge == crate::input::Edge::Top {
                            state.start_close_gesture();
                        }
                        // Start home gesture animation when swiping from bottom
                        if *edge == crate::input::Edge::Bottom {
                            state.start_home_gesture();
                        }
                        // Start quick settings transition when swiping from left
                        if *edge == crate::input::Edge::Left {
                            state.qs_gesture_active = true;
                            state.qs_gesture_progress = 0.0;
                            tracing::info!("QS gesture STARTED: qs_gesture_active=true");
                        }
                    }
                }
            } else {
                // No edge gesture detected - log for debugging
                info!("Touch down at ({:.0}, {:.0}) - no edge detected (edge_threshold={})",
                      touch_pos.x, touch_pos.y, state.gesture_recognizer.config.edge_threshold);
            }

            // Handle lock screen touch - block all other interactions
            if state.shell.view == crate::shell::ShellView::LockScreen {
                use crate::shell::lock_screen::{LockInputMode, get_pin_button_rects, get_pattern_dot_positions, hit_test_pattern_dot};

                match state.shell.lock_state.input_mode {
                    LockInputMode::Pin => {
                        // Check which PIN button was pressed
                        let buttons = get_pin_button_rects(state.screen_size);
                        for (i, (rect, _label)) in buttons.iter().enumerate() {
                            if touch_pos.x >= rect.x && touch_pos.x <= rect.x + rect.width &&
                               touch_pos.y >= rect.y && touch_pos.y <= rect.y + rect.height {
                                state.shell.lock_state.pressed_button = Some(i);
                                break;
                            }
                        }
                    }
                    LockInputMode::Pattern => {
                        // Start pattern gesture
                        let dots = get_pattern_dot_positions(state.screen_size);
                        if let Some(dot_idx) = hit_test_pattern_dot(touch_pos, &dots) {
                            state.shell.lock_state.pattern_active = true;
                            state.shell.lock_state.pattern_nodes.clear();
                            state.shell.lock_state.pattern_nodes.push(dot_idx);
                            state.shell.lock_state.pattern_touch_pos = Some(touch_pos);
                        }
                    }
                    LockInputMode::Password => {
                        // Check "Use Password" link hit - handled on touch_up
                    }
                }

                // Check for "Use Password" fallback link
                let screen_h = state.screen_size.h as f64;
                let link_y = screen_h * 0.9;
                if touch_pos.y >= link_y - 20.0 && touch_pos.y <= link_y + 30.0 {
                    // Touched near the fallback link - will switch on touch_up
                }
            }

            // Check if touch is on shell UI (home screen app grid)
            // Don't launch immediately - wait for touch up to distinguish tap from scroll
            // Skip if an edge gesture was detected (edge gestures take priority)
            let edge_gesture_active = matches!(
                state.gesture_recognizer.active_gesture,
                Some(crate::input::ActiveGesture::EdgeSwipe { .. })
            );
            info!("Home touch check: view={:?}, edge_gesture_active={}, wiggle={}, long_press_menu={}",
                  state.shell.view, edge_gesture_active, state.shell.wiggle_mode, state.shell.long_press_menu.is_some());
            if state.shell.view == crate::shell::ShellView::Home && !edge_gesture_active {
                // If long press menu is open, handle menu interaction
                if state.shell.long_press_menu.is_some() {
                    // Touch on menu - track position for item selection
                    // Menu handling is done on touch up
                } else if state.shell.wiggle_mode {
                    // In wiggle mode - check for drag start or Done button
                    // Done button bounds (matching shell.slint WiggleDoneButton)
                    let btn_width = 200.0;
                    let btn_height = 56.0;
                    let btn_x = (state.screen_size.w as f64 - btn_width) / 2.0;
                    let btn_y = state.screen_size.h as f64 - 100.0;

                    if touch_pos.x >= btn_x && touch_pos.x <= btn_x + btn_width &&
                       touch_pos.y >= btn_y && touch_pos.y <= btn_y + btn_height {
                        // Touch on Done button - handled on touch_up
                    } else if let Some(index) = state.shell.hit_test_category_index(touch_pos) {
                        // Start dragging this category
                        state.shell.start_drag(index, touch_pos);
                        info!("Started dragging category at index {}", index);
                        // Update Slint to show floating tile
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.set_dragging_index(index as i32);
                            slint_ui.set_drag_position(touch_pos.x as f32, touch_pos.y as f32);
                        }
                    }
                } else {
                    // Forward touch to Slint for visual feedback
                    info!("Dispatching touch to Slint at ({}, {}), slint_ui={}",
                          touch_pos.x, touch_pos.y, state.shell.slint_ui.is_some());
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_pressed(touch_pos.x as f32, touch_pos.y as f32);
                    } else {
                        info!("WARNING: slint_ui is None!");
                    }

                    // Detect which category was touched for long press tracking
                    // Use shell.hit_test_category() which properly handles scroll offset
                    let touched_category = state.shell.hit_test_category(touch_pos);

                    // If touching a category, use start_category_touch for long press detection
                    if let Some(category) = touched_category {
                        info!("Touch down on category {:?}", category);
                        state.shell.start_category_touch(touch_pos, category);
                    } else {
                        // Not on a category - just track for scrolling
                        state.shell.start_home_touch(touch_pos.y, None);
                    }
                }
            }

            // Check if touch is on app switcher card (stacked layout)
            if state.shell.view == crate::shell::ShellView::Switcher {
                // Stacked card layout - matches render code
                let screen_w = state.screen_size.w as f64;
                let screen_h = state.screen_size.h as f64;

                // Base card dimensions (same as render code)
                let base_card_width = screen_w * 0.80;
                let base_card_height = screen_h * 0.58;
                let card_spacing = base_card_width * 0.35;
                let center_y = screen_h / 2.0;

                let scroll_offset = state.shell.switcher_scroll;

                // Collect windows and sort by z-order (closest to center = on top)
                let windows: Vec<_> = state.space.elements().cloned().collect();
                let mut sorted_indices: Vec<usize> = (0..windows.len()).collect();
                sorted_indices.sort_by(|&a, &b| {
                    let dist_a = ((a as f64 * card_spacing - scroll_offset) / card_spacing).abs();
                    let dist_b = ((b as f64 * card_spacing - scroll_offset) / card_spacing).abs();
                    dist_a.partial_cmp(&dist_b).unwrap()
                });

                // Check cards in z-order (front to back), first hit wins
                let mut touched_index = None;
                for &i in sorted_indices.iter() {
                    let window = &windows[i];
                    let card_scroll_pos = i as f64 * card_spacing - scroll_offset;
                    let normalized_pos = card_scroll_pos / card_spacing;
                    let distance = normalized_pos.abs();
                    let scale_factor = (1.0 - distance * 0.12).max(0.7);

                    // Use same integer truncation as render code
                    let card_width = (base_card_width * scale_factor) as i32;
                    let card_height = (base_card_height * scale_factor) as i32;
                    let x_offset = card_scroll_pos + (screen_w - card_width as f64) / 2.0;
                    let x_pos = x_offset as i32;
                    let y_offset = distance * 20.0;
                    let y_pos = ((center_y - card_height as f64 / 2.0) + y_offset) as i32;

                    // Calculate actual background bounds (matches render code)
                    let window_geo = window.geometry();
                    let max_content_width = card_width - 16;
                    let max_content_height = card_height - 16;
                    let scale_x = max_content_width as f64 / window_geo.size.w as f64;
                    let scale_y = max_content_height as f64 / window_geo.size.h as f64;
                    let fit_scale = f64::min(scale_x, scale_y);
                    let scaled_w = (window_geo.size.w as f64 * fit_scale) as i32;
                    let scaled_h = (window_geo.size.h as f64 * fit_scale) as i32;
                    let padding = 8;
                    let bg_width = scaled_w + padding * 2;
                    let bg_height = scaled_h + padding * 2;
                    let bg_x = x_pos + (card_width - bg_width) / 2;
                    let bg_y = y_pos + (card_height - bg_height) / 2;

                    // Check if touch is within the actual visible background
                    if touch_pos.x >= bg_x as f64 && touch_pos.x < (bg_x + bg_width) as f64 &&
                       touch_pos.y >= bg_y as f64 && touch_pos.y < (bg_y + bg_height) as f64 {
                        touched_index = Some(i);
                        break; // First hit in z-order wins
                    }
                }

                // Start tracking touch - don't switch app yet, wait for touch up
                state.shell.start_switcher_touch(touch_pos.x, touched_index);
            }

            // Check if touch is on Quick Settings panel
            if state.shell.view == crate::shell::ShellView::QuickSettings {
                state.shell.start_qs_touch(touch_pos.x, touch_pos.y);
                // Dispatch to Slint for toggle visual feedback and callbacks
                if let Some(ref slint_ui) = state.shell.slint_ui {
                    slint_ui.dispatch_pointer_pressed(touch_pos.x as f32, touch_pos.y as f32);
                }
            }

            // Only forward touch events to apps when in App view (not Home or Switcher)
            if state.shell.view == crate::shell::ShellView::App {
                if let Some(touch) = state.seat.get_touch() {
                    let serial = smithay::utils::SERIAL_COUNTER.next_serial();

                    // Find surface under touch point (handles both Wayland and X11 windows)
                    let under = state.space.element_under(touch_pos)
                        .map(|(window, loc)| {
                            let surface = window.toplevel()
                                .map(|t| t.wl_surface().clone())
                                .or_else(|| window.x11_surface().and_then(|x| x.wl_surface()));
                            (surface, loc)
                        });

                    let focus = under.as_ref().and_then(|(surface, loc)| {
                        surface.as_ref().map(|s| (s.clone(), loc.to_f64()))
                    });

                    // Set keyboard focus on touch
                    if let Some((ref surface, _)) = focus {
                        if let Some(keyboard) = state.seat.get_keyboard() {
                            keyboard.set_focus(state, Some(surface.clone()), serial);
                            debug!("Keyboard focus set via touch");
                        }
                    }

                    touch.down(
                        state,
                        focus,
                        &smithay::input::touch::DownEvent {
                            slot: event.slot(),
                            location: touch_pos,
                            serial,
                            time: Event::time_msec(&event),
                        },
                    );
                }
            }
        }
        InputEvent::TouchMotion { event } => {
            use smithay::backend::input::{TouchEvent, AbsolutePositionEvent};

            debug!("Touch motion at slot {:?}", event.slot());
            let screen = state.screen_size;
            let touch_pos = smithay::utils::Point::<f64, smithay::utils::Logical>::from((
                event.x_transformed(screen.w),
                event.y_transformed(screen.h),
            ));

            // Feed to gesture recognizer
            let slot_id: i32 = event.slot().into();
            if let Some(gesture_event) = state.gesture_recognizer.touch_motion(slot_id, touch_pos) {
                debug!("Gesture update: {:?}", gesture_event);
                // Update integrated shell state
                state.shell.handle_gesture(&gesture_event);

                // Update close gesture animation when swiping from top
                if let crate::input::GestureEvent::EdgeSwipeUpdate { edge, progress, .. } = &gesture_event {
                    if *edge == crate::input::Edge::Top {
                        state.update_close_gesture(*progress);
                    }
                    // Update home gesture animation when swiping from bottom
                    if *edge == crate::input::Edge::Bottom {
                        state.update_home_gesture(*progress);
                    }
                    // Update switcher transition when swiping from right (only in App view)
                    if *edge == crate::input::Edge::Right && state.shell.view == crate::shell::ShellView::App {
                        state.switcher_gesture_active = true;
                        state.switcher_gesture_progress = progress.clamp(0.0, 1.0);
                    }
                    // Update quick settings transition when swiping from left
                    if *edge == crate::input::Edge::Left {
                        state.qs_gesture_active = true;
                        state.qs_gesture_progress = progress.clamp(0.0, 1.0);
                        tracing::info!("QS gesture UPDATE: progress={:.2}", state.qs_gesture_progress);
                    }
                }
            }

            // Handle pattern gesture on lock screen
            if state.shell.view == crate::shell::ShellView::LockScreen {
                if state.shell.lock_state.pattern_active {
                    use crate::shell::lock_screen::{get_pattern_dot_positions, hit_test_pattern_dot};
                    let dots = get_pattern_dot_positions(state.screen_size);
                    state.shell.lock_state.pattern_touch_pos = Some(touch_pos);

                    // Check if we've touched a new dot
                    if let Some(dot_idx) = hit_test_pattern_dot(touch_pos, &dots) {
                        // Only add if not already in pattern
                        if !state.shell.lock_state.pattern_nodes.contains(&dot_idx) {
                            state.shell.lock_state.pattern_nodes.push(dot_idx);
                        }
                    }
                }
            }

            // Handle scrolling on home screen
            if state.shell.view == crate::shell::ShellView::Home && state.shell.scroll_touch_start_y.is_some() {
                state.shell.update_home_scroll(touch_pos.y);

                // Check for long press (300ms without scrolling)
                // This also runs in the render loop for cases where finger is completely still
                state.shell.check_and_show_long_press();

                // Forward touch motion to Slint (if not in wiggle mode)
                if !state.shell.wiggle_mode {
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_moved(touch_pos.x as f32, touch_pos.y as f32);
                    }
                }
            }

            // Update drag position in wiggle mode
            if state.shell.view == crate::shell::ShellView::Home && state.shell.wiggle_mode && state.shell.dragging_index.is_some() {
                state.shell.update_drag(touch_pos);
                // Update Slint floating tile position
                if let Some(ref slint_ui) = state.shell.slint_ui {
                    slint_ui.set_drag_position(touch_pos.x as f32, touch_pos.y as f32);
                }
            }

            // Handle horizontal scrolling in app switcher
            if state.shell.view == crate::shell::ShellView::Switcher && state.shell.switcher_touch_start_x.is_some() {
                let screen_w = state.screen_size.w as f64;
                // Stacked card layout - cards overlap significantly
                let card_width = screen_w * 0.80; // 85% of screen width
                let card_spacing = card_width * 0.35; // 35% spacing = 65% overlap
                let num_windows = state.space.elements().count();
                state.shell.update_switcher_scroll(touch_pos.x, num_windows, card_spacing);
            }

            // Handle scrolling/brightness on Quick Settings panel
            if state.shell.view == crate::shell::ShellView::QuickSettings && state.shell.qs_touch_start_y.is_some() {
                state.shell.update_qs_scroll(touch_pos.x, touch_pos.y);
                // Apply brightness to system backlight in real-time while dragging
                let brightness = state.shell.get_qs_brightness();
                state.system.set_brightness(brightness);
                // Dispatch to Slint for brightness slider interaction
                if let Some(ref slint_ui) = state.shell.slint_ui {
                    slint_ui.dispatch_pointer_moved(touch_pos.x as f32, touch_pos.y as f32);
                }
            }

            // Only forward touch motion to apps when in App view (not Home or Switcher)
            if state.shell.view == crate::shell::ShellView::App {
                if let Some(touch) = state.seat.get_touch() {
                    // Find surface under touch point (handles both Wayland and X11 windows)
                    let under = state.space.element_under(touch_pos)
                        .map(|(window, loc)| {
                            let surface = window.toplevel()
                                .map(|t| t.wl_surface().clone())
                                .or_else(|| window.x11_surface().and_then(|x| x.wl_surface()));
                            (surface, loc)
                        });

                    let focus = under.as_ref().and_then(|(surface, loc)| {
                        surface.as_ref().map(|s| (s.clone(), loc.to_f64()))
                    });

                    touch.motion(
                        state,
                        focus,
                        &smithay::input::touch::MotionEvent {
                            slot: event.slot(),
                            location: touch_pos,
                            time: Event::time_msec(&event),
                        },
                    );
                }
            }
        }
        InputEvent::TouchUp { event } => {
            use smithay::backend::input::TouchEvent;
            use crate::input::gesture_to_action;

            info!("Touch up at slot {:?}", event.slot());

            // Save touch position BEFORE touch_up removes it from gesture recognizer
            let slot_id: i32 = event.slot().into();
            let last_touch_pos = state.gesture_recognizer.get_touch_position(slot_id);

            // Feed to gesture recognizer and handle completed gestures
            // Track if an EDGE SWIPE gesture was handled so we don't also process as app tap
            // Note: Tap and LongPress gestures should NOT block app launch processing
            let mut edge_gesture_handled = false;
            if let Some(gesture_event) = state.gesture_recognizer.touch_up(slot_id) {
                info!("Gesture completed: {:?}", gesture_event);

                // Update integrated shell state
                state.shell.handle_gesture(&gesture_event);

                // Handle close gesture animation end
                if let crate::input::GestureEvent::EdgeSwipeEnd { edge, completed, .. } = &gesture_event {
                    edge_gesture_handled = true;  // Only edge swipes block app tap processing
                    if *edge == crate::input::Edge::Top {
                        state.end_close_gesture(*completed);
                    }
                    // Handle home gesture animation end
                    if *edge == crate::input::Edge::Bottom {
                        state.end_home_gesture(*completed);
                    }
                    // Handle switcher transition end
                    if *edge == crate::input::Edge::Right {
                        // Reset gesture state
                        state.switcher_gesture_active = false;
                        state.switcher_gesture_progress = 0.0;

                        // If gesture completed, open switcher with correct scroll position
                        // so the current (topmost) app is centered
                        if *completed {
                            let num_windows = state.space.elements().count();
                            let screen_w = state.screen_size.w as f64;
                            let card_width = screen_w * 0.80;
                            let card_spacing = card_width * 0.35;
                            state.shell.open_switcher(num_windows, card_spacing);
                        }
                    }
                    // Handle quick settings transition end
                    if *edge == crate::input::Edge::Left {
                        // Reset gesture state
                        state.qs_gesture_active = false;
                        state.qs_gesture_progress = 0.0;

                        // Sync Quick Settings with system status when opening it
                        if *completed {
                            state.system.refresh();
                            state.shell.sync_quick_settings(&state.system);
                            info!("Quick Settings opened - synced with system status");
                        }
                    }
                }

                // Handle window management for completed gestures (still needed for close)
                let action = gesture_to_action(&gesture_event);
                state.handle_gesture_complete(&action);
            }

            // Handle lock screen touch up
            if state.shell.view == crate::shell::ShellView::LockScreen {
                use crate::shell::lock_screen::{LockInputMode, PIN_BUTTONS};

                match state.shell.lock_state.input_mode {
                    LockInputMode::Pin => {
                        // Process PIN button tap
                        if let Some(button_idx) = state.shell.lock_state.pressed_button {
                            if button_idx < PIN_BUTTONS.len() {
                                let label = PIN_BUTTONS[button_idx];
                                match label {
                                    "<" => {
                                        // Backspace
                                        state.shell.lock_state.entered_pin.pop();
                                    }
                                    "OK" => {
                                        // Attempt unlock
                                        if !state.shell.lock_state.entered_pin.is_empty() {
                                            state.shell.try_unlock();
                                        }
                                    }
                                    digit => {
                                        // Add digit (max 6 digits)
                                        if state.shell.lock_state.entered_pin.len() < 6 {
                                            state.shell.lock_state.entered_pin.push_str(digit);
                                        }
                                    }
                                }
                            }
                            state.shell.lock_state.pressed_button = None;
                        }

                        // Check for "Use Password" link tap
                        if let Some(pos) = last_touch_pos {
                            let screen_h = state.screen_size.h as f64;
                            let link_y = screen_h * 0.9;
                            if pos.y >= link_y - 20.0 && pos.y <= link_y + 30.0 {
                                state.shell.lock_state.switch_to_password();
                                info!("Switched to password mode");
                            }
                        }
                    }
                    LockInputMode::Pattern => {
                        // Pattern gesture ended - attempt unlock if enough nodes
                        if state.shell.lock_state.pattern_active {
                            state.shell.lock_state.pattern_active = false;
                            state.shell.lock_state.pattern_touch_pos = None;

                            if state.shell.lock_state.pattern_nodes.len() >= 4 {
                                state.shell.try_unlock();
                            } else if !state.shell.lock_state.pattern_nodes.is_empty() {
                                // Too short - show error
                                state.shell.lock_state.error_message = Some("Pattern too short (min 4 dots)".to_string());
                                state.shell.lock_state.pattern_nodes.clear();
                            }
                        }

                        // Check for "Use Password" link tap
                        if let Some(pos) = last_touch_pos {
                            let screen_h = state.screen_size.h as f64;
                            let link_y = screen_h * 0.9;
                            if pos.y >= link_y - 20.0 && pos.y <= link_y + 30.0 {
                                state.shell.lock_state.switch_to_password();
                                info!("Switched to password mode");
                            }
                        }
                    }
                    LockInputMode::Password => {
                        // Password mode - Enter key submits (handled via keyboard)
                    }
                }
            }

            // Handle home screen tap to launch app (only if not scrolling and not an edge gesture)
            if state.shell.view == crate::shell::ShellView::Home && !edge_gesture_handled {
                info!("touch_up: Home view, menu_open={}, just_opened={}, wiggle={}, dragging={:?}, last_pos={:?}",
                      state.shell.long_press_menu.is_some(),
                      state.shell.menu_just_opened,
                      state.shell.wiggle_mode,
                      state.shell.dragging_index,
                      last_touch_pos);

                // Handle wiggle mode (reordering icons)
                if state.shell.wiggle_mode {
                    if let Some(pos) = last_touch_pos {
                        // Check if Done button was tapped using Slint hit testing
                        let done_tapped = if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.hit_test_wiggle_done(pos.x as f32, pos.y as f32)
                        } else {
                            false
                        };

                        if done_tapped {
                            info!("Done button tapped, exiting wiggle mode");
                            state.shell.exit_wiggle_mode();
                            // Clear Slint drag state
                            if let Some(ref slint_ui) = state.shell.slint_ui {
                                slint_ui.set_dragging_index(-1);
                            }
                        } else if state.shell.dragging_index.is_some() {
                            // End drag - find drop position
                            let drop_index = state.shell.hit_test_category_index(pos);
                            let reordered = state.shell.end_drag(drop_index);
                            if reordered {
                                info!("Icon reordered to index {:?}", drop_index);
                            }
                            // Clear Slint drag state
                            if let Some(ref slint_ui) = state.shell.slint_ui {
                                slint_ui.set_dragging_index(-1);
                            }
                        }
                    } else {
                        // No position, just cancel any drag
                        state.shell.dragging_index = None;
                        state.shell.drag_position = None;
                        // Clear Slint drag state
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.set_dragging_index(-1);
                        }
                    }
                    state.shell.end_home_touch();
                }
                // If popup/long press menu is open, handle menu interaction
                else if state.shell.popup_showing {
                    // If menu just opened on this touch, don't process tap - just clear the flag
                    if state.shell.menu_just_opened {
                        info!("Popup just opened, keeping it open");
                        state.shell.menu_just_opened = false;
                        state.shell.end_home_touch();
                    } else {
                        // Use Slint hit testing for popup
                        if let Some(pos) = last_touch_pos {
                            if let Some(ref slint_ui) = state.shell.slint_ui {
                                use crate::shell::slint_ui::PopupAction;

                                if let Some(action) = slint_ui.hit_test_popup(pos.x as f32, pos.y as f32) {
                                    info!("Popup action: {:?}", action);
                                    match action {
                                        PopupAction::PickDefault => {
                                            // Get the category and enter pick default view
                                            if let Some(category) = state.shell.popup_category {
                                                state.shell.enter_pick_default(category);
                                            }
                                        }
                                        PopupAction::Move => {
                                            // Enter wiggle mode
                                            state.shell.enter_wiggle_mode();
                                        }
                                        PopupAction::Close => {
                                            state.shell.close_long_press_menu();
                                        }
                                    }
                                }
                            }
                        } else {
                            // No touch position - just close popup
                            info!("No touch position for popup, closing");
                            state.shell.close_long_press_menu();
                        }
                        // Clear touch state
                        state.shell.end_home_touch();
                    }
                } else {
                    // Use shell's hit testing which handles scroll offset properly
                    if let Some(pos) = last_touch_pos {
                        // Use hit_test_category which accounts for scroll offset
                        if let Some(category) = state.shell.hit_test_category(pos) {
                            info!("App tap detected: category={:?}", category);
                            // Use get_exec() which properly handles Settings (uses built-in Flick Settings)
                            if let Some(exec) = state.shell.app_manager.get_exec(category) {
                                info!("Launching app: {}", exec);
                                std::process::Command::new("sh")
                                    .arg("-c")
                                    .arg(&exec)
                                    .spawn()
                                    .ok();
                                state.shell.app_launched();
                            }
                        }
                    }
                    // Clear the old touch state
                    state.shell.end_home_touch();
                }
            }

            // Handle app switcher tap to switch app (only if not scrolling)
            if state.shell.view == crate::shell::ShellView::Switcher {
                // Calculate card spacing for momentum physics
                let screen_w = state.screen_size.w as f64;
                let card_width = screen_w * 0.80;
                let card_spacing = card_width * 0.35;
                let num_windows = state.space.elements().count();
                if let Some(window_index) = state.shell.end_switcher_touch(num_windows, card_spacing) {
                    let windows: Vec<_> = state.space.elements().cloned().collect();
                    if let Some(window) = windows.get(window_index) {
                        info!("Switcher: switching to window {}", window_index);
                        // Raise window and focus it (handles both Wayland and X11 windows)
                        if let Some(keyboard) = state.seat.get_keyboard() {
                            let wl_surface = window.toplevel()
                                .map(|t| t.wl_surface().clone())
                                .or_else(|| window.x11_surface().and_then(|x| x.wl_surface()));
                            if let Some(surface) = wl_surface {
                                let serial = smithay::utils::SERIAL_COUNTER.next_serial();
                                keyboard.set_focus(state, Some(surface), serial);
                            }
                        }
                        state.space.raise_element(window, true);
                        state.shell.switch_to_app();
                    }
                }
            }

            // Handle Quick Settings touch up (toggle tap) and sync brightness
            if state.shell.view == crate::shell::ShellView::QuickSettings {
                use crate::system::{WifiManager, BluetoothManager, AirplaneMode, Flashlight};
                use crate::shell::slint_ui::QuickSettingsAction;

                // Clear old coordinate-based touch tracking
                state.shell.end_qs_touch();

                // Dispatch pointer release to Slint to trigger callbacks
                if let Some(pos) = last_touch_pos {
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_released(pos.x as f32, pos.y as f32);

                        // Poll for Slint callback actions
                        let actions = slint_ui.take_pending_qs_actions();
                        for action in actions {
                            match action {
                                QuickSettingsAction::WifiToggle => {
                                    WifiManager::toggle();
                                    state.system.wifi_enabled = WifiManager::is_enabled();
                                    state.system.wifi_ssid = WifiManager::current_connection();
                                    info!("WiFi toggled: {}", if state.system.wifi_enabled { "ON" } else { "OFF" });
                                }
                                QuickSettingsAction::BluetoothToggle => {
                                    BluetoothManager::toggle();
                                    state.system.bluetooth_enabled = BluetoothManager::is_enabled();
                                    info!("Bluetooth toggled: {}", if state.system.bluetooth_enabled { "ON" } else { "OFF" });
                                }
                                QuickSettingsAction::DndToggle => {
                                    state.system.dnd.toggle();
                                    info!("Do Not Disturb: {}", if state.system.dnd.enabled { "ON" } else { "OFF" });
                                }
                                QuickSettingsAction::FlashlightToggle => {
                                    Flashlight::toggle();
                                    info!("Flashlight toggled");
                                }
                                QuickSettingsAction::AirplaneToggle => {
                                    AirplaneMode::toggle();
                                    state.system.wifi_enabled = WifiManager::is_enabled();
                                    state.system.bluetooth_enabled = BluetoothManager::is_enabled();
                                    info!("Airplane mode toggled");
                                }
                                QuickSettingsAction::RotationToggle => {
                                    state.system.rotation_lock.toggle();
                                    info!("Rotation lock: {}", if state.system.rotation_lock.locked { "ON" } else { "OFF" });
                                }
                                QuickSettingsAction::Lock => {
                                    info!("Lock button pressed - locking screen");
                                    state.shell.lock();
                                }
                                QuickSettingsAction::Settings => {
                                    info!("Settings button pressed - launching settings app");
                                    // Get the settings app exec command
                                    use crate::shell::apps::AppCategory;
                                    if let Some(exec) = state.shell.app_manager.get_exec(AppCategory::Settings) {
                                        let exec_clone = exec.clone();
                                        // Close quick settings (need to check if any windows exist)
                                        let has_windows = state.space.elements().count() > 0;
                                        state.shell.close_quick_settings(has_windows);
                                        // Launch the settings app
                                        if let Err(e) = std::process::Command::new("sh")
                                            .arg("-c")
                                            .arg(&exec_clone)
                                            .spawn()
                                        {
                                            tracing::error!("Failed to launch settings app '{}': {}", exec_clone, e);
                                        } else {
                                            state.shell.switch_to_app();
                                        }
                                    } else {
                                        info!("No settings app configured");
                                    }
                                }
                                QuickSettingsAction::BrightnessChanged(value) => {
                                    state.system.set_brightness(value);
                                    info!("Brightness set to {:.0}%", value * 100.0);
                                }
                            }
                        }
                    }
                }

                // Apply brightness to system backlight (in case of drag)
                let brightness = state.shell.get_qs_brightness();
                state.system.set_brightness(brightness);
            }

            // Handle PickDefault view touch up
            if state.shell.view == crate::shell::ShellView::PickDefault {
                // If view just opened on this touch, don't process tap - just clear the flag
                if state.shell.pick_default_just_opened {
                    info!("PickDefault just opened, skipping touch processing");
                    state.shell.pick_default_just_opened = false;
                } else if let Some(pos) = last_touch_pos {
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        // Check back button first
                        if slint_ui.hit_test_pick_default_back(pos.x as f32, pos.y as f32) {
                            info!("PickDefault: back button pressed");
                            state.shell.exit_pick_default();
                        } else if let Some(category) = state.shell.popup_category {
                            // Check app list
                            let apps = state.shell.app_manager.apps_for_category(category);
                            if let Some(index) = slint_ui.hit_test_pick_default_app(pos.x as f32, pos.y as f32, apps.len()) {
                                if let Some(app) = apps.get(index) {
                                    info!("PickDefault: selected app '{}' with exec '{}'", app.name, app.exec);
                                    let exec = app.exec.clone();
                                    state.shell.select_default_app(&exec);
                                }
                            }
                        }
                    }
                }
            }

            // Always clear home touch state at end of touch up to prevent stale long press detection
            // This is a safety net in case view changed during gesture and normal handler was skipped
            if edge_gesture_handled {
                state.shell.end_home_touch();
            }

            if let Some(touch) = state.seat.get_touch() {
                let serial = smithay::utils::SERIAL_COUNTER.next_serial();

                touch.up(
                    state,
                    &smithay::input::touch::UpEvent {
                        slot: event.slot(),
                        serial,
                        time: Event::time_msec(&event),
                    },
                );
            }
        }
        InputEvent::TouchCancel { event: _ } => {
            debug!("Touch cancel");
            // Reset gesture recognizer
            state.gesture_recognizer.touch_cancel();

            // Reset home scroll state
            state.shell.end_home_touch();

            if let Some(touch) = state.seat.get_touch() {
                touch.cancel(state);
            }
        }
        InputEvent::TouchFrame { event: _ } => {
            debug!("Touch frame");
            if let Some(touch) = state.seat.get_touch() {
                touch.frame(state);
            }
        }
        _ => {}
    }
}

/// Initialize XWayland support
fn init_xwayland(
    state: &mut Flick,
    loop_handle: &smithay::reexports::calloop::LoopHandle<'static, Flick>,
) -> Result<()> {
    use std::process::Stdio;

    // Initialize XWayland shell state
    state.xwayland_shell_state = Some(XWaylandShellState::new::<Flick>(&state.display_handle));

    // Spawn XWayland
    let (xwayland, client) = XWayland::spawn(
        &state.display_handle,
        None,  // Let Smithay choose display number
        std::iter::empty::<(&str, &str)>(),  // No extra env vars
        true,  // Enable abstract socket
        Stdio::null(),  // stdout
        Stdio::null(),  // stderr
        |_| {},  // user_data initialization
    ).map_err(|e| anyhow::anyhow!("Failed to spawn XWayland: {:?}", e))?;

    // Register XWayland event source - XWayland implements EventSource directly
    let client_clone = client.clone();
    let loop_handle_clone = loop_handle.clone();
    loop_handle
        .insert_source(xwayland, move |event, _, state| {
            match event {
                XWaylandEvent::Ready {
                    x11_socket,
                    display_number,
                } => {
                    info!("XWayland ready on display :{}", display_number);

                    // Start the X11 window manager
                    match X11Wm::start_wm(
                        loop_handle_clone.clone(),
                        &state.display_handle,
                        x11_socket,
                        client_clone.clone(),
                    ) {
                        Ok(wm) => {
                            info!("X11 Window Manager started");
                            state.xwm = Some(wm);

                            // Set DISPLAY for child processes
                            let display_str = format!(":{}", display_number);
                            std::env::set_var("DISPLAY", &display_str);

                            // Write display number to runtime file for shell to read
                            if let Ok(runtime_dir) = std::env::var("XDG_RUNTIME_DIR") {
                                let display_file = format!("{}/flick-xwayland-display", runtime_dir);
                                if let Err(e) = std::fs::write(&display_file, &display_str) {
                                    warn!("Failed to write XWayland display file: {:?}", e);
                                } else {
                                    info!("Wrote XWayland display {} to {}", display_str, display_file);
                                }
                            }
                        }
                        Err(e) => {
                            error!("Failed to start X11 WM: {:?}", e);
                        }
                    }
                }
                XWaylandEvent::Error => {
                    error!("XWayland encountered an error");
                }
            }
        })
        .map_err(|e| anyhow::anyhow!("Failed to insert XWayland source: {:?}", e))?;

    Ok(())
}
