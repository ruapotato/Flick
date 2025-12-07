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

// Define a combined element type for the app switcher that can hold both
// solid color elements (for card backgrounds, shadows, text) and
// constrained window elements (for actual window content previews)
smithay::backend::renderer::element::render_elements! {
    /// Render elements for the app switcher view
    pub SwitcherRenderElement<R> where
        R: ImportAll;
    /// Solid color rectangles (backgrounds, shadows, text pixels)
    Solid=SolidColorRenderElement,
    /// Constrained window content (scaled and cropped to fit cards)
    Window=CropRenderElement<RelocateRenderElement<RescaleRenderElement<WaylandSurfaceRenderElement<R>>>>,
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
    use smithay::backend::renderer::element::solid::{SolidColorBuffer, SolidColorRenderElement};
    use smithay::backend::renderer::element::Kind;
    use smithay::backend::renderer::element::surface::WaylandSurfaceRenderElement;
    use crate::shell::ShellView;
    use crate::shell::primitives::colors;
    use crate::shell::text;

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
    let bg_color = if shell_view == ShellView::LockScreen {
        [0.05, 0.05, 0.1, 1.0]  // Dark blue for lock screen
    } else if shell_view == ShellView::Home || gesture_active || bottom_gesture {
        colors::BACKGROUND
    } else if shell_view == ShellView::Switcher {
        [0.0, 0.3, 0.0, 1.0]  // Dark green for Switcher - should be visible
    } else if shell_view == ShellView::QuickSettings {
        [0.1, 0.1, 0.15, 1.0]  // Dark blue-gray for Quick Settings
    } else {
        [0.05, 0.05, 0.15, 1.0]
    };

    // Build Slint UI elements for shell views
    let mut slint_elements: Vec<HomeRenderElement<GlesRenderer>> = Vec::new();

    // Render shell views using Slint (lock screen, home, quick settings, pick default)
    if shell_view == ShellView::LockScreen || shell_view == ShellView::Home || shell_view == ShellView::QuickSettings || shell_view == ShellView::PickDefault {
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
                    slint_ui.set_view("quick-settings");
                    slint_ui.set_brightness(state.shell.quick_settings.brightness);
                    // Get wifi/bluetooth enabled state from toggles
                    let wifi_enabled = state.shell.quick_settings.toggles.iter()
                        .find(|t| t.id == "wifi")
                        .map(|t| t.enabled)
                        .unwrap_or(false);
                    let bluetooth_enabled = state.shell.quick_settings.toggles.iter()
                        .find(|t| t.id == "bluetooth")
                        .map(|t| t.enabled)
                        .unwrap_or(false);
                    slint_ui.set_wifi_enabled(wifi_enabled);
                    slint_ui.set_bluetooth_enabled(bluetooth_enabled);
                    slint_ui.set_wifi_ssid(state.shell.quick_settings.wifi_ssid.as_deref().unwrap_or(""));
                    slint_ui.set_battery_percent(state.shell.quick_settings.battery_percent as i32);
                }
                _ => {}
            }

            // Render Slint UI to pixel buffer
            slint_ui.request_redraw();
            if let Some((width, height, pixels)) = slint_ui.render() {
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
                if let Ok(slint_element) = MemoryRenderBufferRenderElement::from_buffer(
                    renderer,
                    loc.to_f64(),
                    &mem_buffer,
                    None,
                    None,
                    None,
                    Kind::Unspecified,
                ) {
                    slint_elements.push(HomeRenderElement::Icon(slint_element));
                    tracing::debug!("Slint {:?} rendered", shell_view);
                }
            }
        }
    }

    // Switcher uses a separate element type that can hold both solid colors and window content
    let mut switcher_elements: Vec<SwitcherRenderElement<GlesRenderer>> = Vec::new();

    if shell_view == ShellView::Switcher {
        // Full Switcher UI with horizontal card layout (Android-style)
        // NOTE: Elements must be in FRONT-TO-BACK order (front first, background last)
        let screen_w = state.screen_size.w as f64;
        let screen_h = state.screen_size.h as f64;

        let window_count = state.space.elements().count();

        // Horizontal card layout - cards are phone-shaped (tall and narrow)
        // Card dimensions: maintain screen aspect ratio but scaled down
        let card_height = (screen_h * 0.65) as i32;  // 65% of screen height
        let card_width = (card_height as f64 * (screen_w / screen_h)) as i32;  // Maintain aspect ratio
        let card_spacing = card_width + 24;  // Gap between cards
        let card_y = ((screen_h - card_height as f64) / 2.0) as i32;  // Center vertically

        // Collect windows and their positions
        let start_x = 32i32;  // Left margin
        let scroll_offset = state.shell.switcher_scroll as i32;

        // Build card data with window references
        let windows: Vec<_> = state.space.elements().cloned().collect();

        // Render cards (front-to-back: later windows drawn first as they're "on top")
        for (i, window) in windows.iter().enumerate().rev() {
            let x_pos = start_x + (i as i32 * card_spacing) - scroll_offset;

            // Skip cards that are off-screen
            if x_pos + card_width < 0 || x_pos > screen_w as i32 {
                continue;
            }

            // Get window title - try title first, then instance, then class, then fallback
            let title = window.x11_surface()
                .map(|x11| {
                    let t = x11.title();
                    if !t.is_empty() {
                        t
                    } else {
                        // Try instance name as fallback (res_name part of WM_CLASS)
                        let inst = x11.instance();
                        if !inst.is_empty() {
                            inst
                        } else {
                            // Try class name as fallback (res_class part of WM_CLASS)
                            let c = x11.class();
                            if !c.is_empty() {
                                c
                            } else {
                                format!("Window {}", i + 1)
                            }
                        }
                    }
                })
                .unwrap_or_else(|| format!("Window {}", i + 1));

            // Window title text (frontmost - rendered first)
            let text_scale = 2.5;
            let text_color: [f32; 4] = [1.0, 1.0, 1.0, 1.0];
            let text_center_x = x_pos as f64 + card_width as f64 / 2.0;
            let text_y = (card_y + card_height + 12) as f64;
            let text_rects = text::render_text_centered(&title, text_center_x, text_y, text_scale, text_color);
            for (rect, color) in text_rects {
                let buffer = SolidColorBuffer::new(
                    (rect.width as i32, rect.height as i32),
                    color,
                );
                let loc: smithay::utils::Point<i32, smithay::utils::Physical> =
                    (rect.x as i32, rect.y as i32).into();
                switcher_elements.push(SolidColorRenderElement::from_buffer(
                    &buffer, loc, scale as f64, 1.0, Kind::Unspecified
                ).into());
            }

            // Render actual window content scaled into the card
            // Get window geometry (the actual content area)
            let window_geo = window.geometry();

            // Get window render elements at origin (0,0)
            let window_render_elements: Vec<WaylandSurfaceRenderElement<GlesRenderer>> = window
                .render_elements::<WaylandSurfaceRenderElement<GlesRenderer>>(
                    renderer,
                    (0, 0).into(),  // Render at origin
                    Scale::from(scale),
                    1.0,  // alpha
                );

            // Card content area (with padding)
            let content_width = card_width - 8;
            let content_height = card_height - 8;
            let content_x = x_pos + 4;
            let content_y = card_y + 4;

            // Calculate scale to fit window in card (maintain aspect ratio)
            let scale_x = content_width as f64 / window_geo.size.w as f64;
            let scale_y = content_height as f64 / window_geo.size.h as f64;
            let fit_scale = f64::min(scale_x, scale_y);

            // Calculate centering offset
            let scaled_w = (window_geo.size.w as f64 * fit_scale) as i32;
            let scaled_h = (window_geo.size.h as f64 * fit_scale) as i32;
            let center_offset_x = (content_width - scaled_w) / 2;
            let center_offset_y = (content_height - scaled_h) / 2;

            // Final position for the scaled window
            let final_x = content_x + center_offset_x;
            let final_y = content_y + center_offset_y;

            // Crop rectangle at the final screen position
            let crop_rect: Rectangle<i32, smithay::utils::Physical> = Rectangle::new(
                (final_x, final_y).into(),
                (scaled_w, scaled_h).into(),
            );

            // Apply transformations: scale at origin, then relocate to final position
            for elem in window_render_elements {
                // Scale the element (relative to origin since element is at origin)
                let scaled = RescaleRenderElement::from_element(
                    elem,
                    (0, 0).into(),  // Scale relative to origin
                    Scale::from(fit_scale),
                );
                // Relocate to the final position
                let final_pos: smithay::utils::Point<i32, smithay::utils::Physical> = (final_x, final_y).into();
                let relocated = RelocateRenderElement::from_element(
                    scaled,
                    final_pos,
                    Relocate::Absolute,
                );
                // Crop to the card bounds
                if let Some(cropped) = CropRenderElement::from_element(
                    relocated,
                    Scale::from(scale),
                    crop_rect,
                ) {
                    switcher_elements.push(cropped.into());
                }
            }

            // Card background/border (behind window content)
            let card_buffer = SolidColorBuffer::new(
                (card_width, card_height),
                [0.15, 0.15, 0.18, 1.0],
            );
            let card_loc: smithay::utils::Point<i32, smithay::utils::Physical> =
                (x_pos, card_y).into();
            switcher_elements.push(SolidColorRenderElement::from_buffer(
                &card_buffer, card_loc, scale as f64, 1.0, Kind::Unspecified
            ).into());

            // Card shadow (behind card)
            let shadow_buffer = SolidColorBuffer::new(
                (card_width + 6, card_height + 6),
                [0.0, 0.0, 0.0, 0.4],
            );
            let shadow_loc: smithay::utils::Point<i32, smithay::utils::Physical> =
                (x_pos - 3, card_y - 3).into();
            switcher_elements.push(SolidColorRenderElement::from_buffer(
                &shadow_buffer, shadow_loc, scale as f64, 1.0, Kind::Unspecified
            ).into());
        }

        // If no windows, show "No Apps" text
        if window_count == 0 {
            let no_apps_text = "NO APPS";
            let text_scale = 4.0;
            let text_color: [f32; 4] = [0.6, 0.6, 0.7, 1.0];
            let text_width = text::text_width(no_apps_text) * text_scale;
            let text_x = (screen_w - text_width) / 2.0;
            let text_y = screen_h / 2.0 - 20.0;
            let text_rects = text::render_text(no_apps_text, text_x, text_y, text_scale, text_color);
            for (rect, color) in text_rects {
                let buffer = SolidColorBuffer::new(
                    (rect.width as i32, rect.height as i32),
                    color,
                );
                let loc: smithay::utils::Point<i32, smithay::utils::Physical> =
                    (rect.x as i32, rect.y as i32).into();
                switcher_elements.push(SolidColorRenderElement::from_buffer(
                    &buffer, loc, scale as f64, 1.0, Kind::Unspecified
                ).into());
            }
        }

        // Header title text (in front of header bar)
        let header_text = "RECENT APPS";
        let header_text_scale = 2.5;
        let header_text_color: [f32; 4] = [1.0, 1.0, 1.0, 1.0];
        let header_text_width = text::text_width(header_text) * header_text_scale;
        let header_text_x = (screen_w - header_text_width) / 2.0;
        let header_text_y = 18.0;
        let header_text_rects = text::render_text(header_text, header_text_x, header_text_y, header_text_scale, header_text_color);
        for (rect, color) in header_text_rects {
            let buffer = SolidColorBuffer::new(
                (rect.width as i32, rect.height as i32),
                color,
            );
            let loc: smithay::utils::Point<i32, smithay::utils::Physical> =
                (rect.x as i32, rect.y as i32).into();
            switcher_elements.push(SolidColorRenderElement::from_buffer(
                &buffer, loc, scale as f64, 1.0, Kind::Unspecified
            ).into());
        }

        // Header bar (behind cards but in front of background)
        let header_buffer = SolidColorBuffer::new(
            (screen_w as i32, 60),
            [0.15, 0.15, 0.20, 1.0],
        );
        let header_loc: smithay::utils::Point<i32, smithay::utils::Physical> = (0, 0).into();
        switcher_elements.push(SolidColorRenderElement::from_buffer(
            &header_buffer, header_loc, scale as f64, 1.0, Kind::Unspecified
        ).into());

        // Background (backmost - rendered last in array)
        let bg_buffer = SolidColorBuffer::new(
            (screen_w as i32, screen_h as i32),
            [0.08, 0.08, 0.12, 1.0],
        );
        let bg_loc: smithay::utils::Point<i32, smithay::utils::Physical> = (0, 0).into();
        switcher_elements.push(SolidColorRenderElement::from_buffer(
            &bg_buffer, bg_loc, scale as f64, 1.0, Kind::Unspecified
        ).into());

        tracing::info!("Switcher: {} windows, {} elements", window_count, switcher_elements.len());
    }

    // Render based on what view we're in
    // For Switcher: use a fresh damage tracker to guarantee full redraw
    let mut switcher_tracker = if shell_view == ShellView::Switcher {
        tracing::info!("Switcher: creating fresh damage tracker for full redraw");
        Some(OutputDamageTracker::from_output(output))
    } else {
        None
    };

    let render_res = if shell_view == ShellView::Switcher {
        // Switcher view - render window cards
        let tracker = switcher_tracker.as_mut().unwrap();
        tracker.render_output(
            renderer,
            &mut fb,
            0,  // age=0 for full redraw
            &switcher_elements,
            bg_color,
        )
    } else if shell_view == ShellView::LockScreen || shell_view == ShellView::Home || shell_view == ShellView::QuickSettings || shell_view == ShellView::PickDefault {
        // Shell views - render Slint UI
        surface_data.damage_tracker.render_output(
            renderer,
            &mut fb,
            0, // Force full redraw for Slint views
            &slint_elements,
            bg_color,
        )
    } else if home_gesture_active {
        // During home gesture: render app window sliding UP, with home background showing behind
        use smithay::backend::renderer::element::surface::WaylandSurfaceRenderElement;
        use smithay::desktop::space::SpaceRenderElements;

        let window_elements: Vec<SpaceRenderElements<GlesRenderer, WaylandSurfaceRenderElement<GlesRenderer>>> = state
            .space
            .render_elements_for_output(renderer, output, scale as f32)
            .unwrap_or_default();

        // Render windows with home background (window position is updated by update_home_gesture)
        surface_data.damage_tracker.render_output(
            renderer,
            &mut fb,
            0, // Force full redraw during gesture
            &window_elements,
            bg_color, // Home background color shows through as window slides up
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
                tracing::info!("Switcher render OK: has_damage={}, damage_rects={}", has_damage, damage_rects);
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
                        tracing::info!("Switcher frame queued successfully");
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
                    }
                }
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
                    // Done button bounds (same as in render)
                    let btn_width = 100.0;
                    let btn_height = 40.0;
                    let btn_x = (state.screen_size.w as f64 - btn_width) / 2.0;
                    let btn_y = state.screen_size.h as f64 - 80.0;

                    if touch_pos.x >= btn_x && touch_pos.x <= btn_x + btn_width &&
                       touch_pos.y >= btn_y && touch_pos.y <= btn_y + btn_height {
                        // Touch on Done button - handled on touch_up
                    } else if let Some(index) = state.shell.hit_test_category_index(touch_pos) {
                        // Start dragging this category
                        state.shell.start_drag(index, touch_pos);
                        info!("Started dragging category at index {}", index);
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

            // Check if touch is on app switcher card (horizontal layout)
            if state.shell.view == crate::shell::ShellView::Switcher {
                // Card layout matches render code - horizontal layout
                let screen_w = state.screen_size.w as f64;
                let screen_h = state.screen_size.h as f64;

                // Calculate card dimensions (same as render code)
                let card_height = (screen_h * 0.65) as i32;
                let card_width = (card_height as f64 * (screen_w / screen_h)) as i32;
                let card_spacing = card_width + 24;
                let card_y = ((screen_h - card_height as f64) / 2.0) as i32;
                let start_x = 32i32;
                let scroll_offset = state.shell.switcher_scroll as i32;

                // Collect windows and find which card was touched
                let windows: Vec<_> = state.space.elements().cloned().collect();
                let mut touched_index = None;

                for (i, _window) in windows.iter().enumerate() {
                    // Calculate card position for this window
                    let x_pos = (start_x + (i as i32 * card_spacing) - scroll_offset) as f64;

                    // Check if touch is within this card
                    if touch_pos.x >= x_pos && touch_pos.x < x_pos + card_width as f64 &&
                       touch_pos.y >= card_y as f64 && touch_pos.y < (card_y + card_height) as f64 {
                        touched_index = Some(i);
                        break;
                    }
                }

                // Start tracking touch - don't switch app yet, wait for touch up
                state.shell.start_switcher_touch(touch_pos.x, touched_index);
            }

            // Check if touch is on Quick Settings panel
            if state.shell.view == crate::shell::ShellView::QuickSettings {
                state.shell.start_qs_touch(touch_pos.x, touch_pos.y);
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
            }

            // Handle horizontal scrolling in app switcher
            if state.shell.view == crate::shell::ShellView::Switcher && state.shell.switcher_touch_start_x.is_some() {
                let screen_h = state.screen_size.h as f64;
                let card_height = (screen_h * 0.65) as i32;
                let screen_w = state.screen_size.w as f64;
                let card_width = (card_height as f64 * (screen_w / screen_h)) as i32;
                let card_spacing = card_width + 24;
                let num_windows = state.space.elements().count();
                state.shell.update_switcher_scroll(touch_pos.x, num_windows, card_spacing);
            }

            // Handle scrolling/brightness on Quick Settings panel
            if state.shell.view == crate::shell::ShellView::QuickSettings && state.shell.qs_touch_start_y.is_some() {
                state.shell.update_qs_scroll(touch_pos.x, touch_pos.y);
                // Apply brightness to system backlight in real-time while dragging
                let brightness = state.shell.get_qs_brightness();
                state.system.set_brightness(brightness);
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

            debug!("Touch up at slot {:?}", event.slot());

            // Save touch position BEFORE touch_up removes it from gesture recognizer
            let slot_id: i32 = event.slot().into();
            let last_touch_pos = state.gesture_recognizer.get_touch_position(slot_id);

            // Feed to gesture recognizer and handle completed gestures
            // Track if an EDGE SWIPE gesture was handled so we don't also process as app tap
            // Note: Tap and LongPress gestures should NOT block app launch processing
            let mut edge_gesture_handled = false;
            if let Some(gesture_event) = state.gesture_recognizer.touch_up(slot_id) {
                debug!("Gesture completed: {:?}", gesture_event);

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
                    // Sync Quick Settings with system status when opening it
                    if *edge == crate::input::Edge::Left && *completed {
                        state.system.refresh();
                        state.shell.sync_quick_settings(&state.system);
                        info!("Quick Settings opened - synced with system status");
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
                        } else if state.shell.dragging_index.is_some() {
                            // End drag - find drop position
                            let drop_index = state.shell.hit_test_category_index(pos);
                            let reordered = state.shell.end_drag(drop_index);
                            if reordered {
                                info!("Icon reordered to index {:?}", drop_index);
                            }
                        }
                    } else {
                        // No position, just cancel any drag
                        state.shell.dragging_index = None;
                        state.shell.drag_position = None;
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
                if let Some(window_index) = state.shell.end_switcher_touch() {
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
                // Execute system action if a toggle was tapped
                if let Some(toggle_id) = state.shell.end_qs_touch() {
                    use crate::system::{WifiManager, BluetoothManager, AirplaneMode, Flashlight};
                    match toggle_id.as_str() {
                        "wifi" => {
                            WifiManager::toggle();
                            state.system.wifi_enabled = WifiManager::is_enabled();
                            state.system.wifi_ssid = WifiManager::current_connection();
                            info!("WiFi toggled: {}", if state.system.wifi_enabled { "ON" } else { "OFF" });
                        }
                        "bluetooth" => {
                            BluetoothManager::toggle();
                            state.system.bluetooth_enabled = BluetoothManager::is_enabled();
                            info!("Bluetooth toggled: {}", if state.system.bluetooth_enabled { "ON" } else { "OFF" });
                        }
                        "airplane" => {
                            AirplaneMode::toggle();
                            state.system.wifi_enabled = WifiManager::is_enabled();
                            state.system.bluetooth_enabled = BluetoothManager::is_enabled();
                            info!("Airplane mode toggled");
                        }
                        "flashlight" => {
                            Flashlight::toggle();
                            info!("Flashlight toggled");
                        }
                        "dnd" => {
                            state.system.dnd.toggle();
                            info!("Do Not Disturb: {}", if state.system.dnd.enabled { "ON" } else { "OFF" });
                        }
                        "rotation" => {
                            state.system.rotation_lock.toggle();
                            info!("Rotation lock: {}", if state.system.rotation_lock.locked { "ON" } else { "OFF" });
                        }
                        _ => {
                            info!("Unknown toggle: {}", toggle_id);
                        }
                    }
                }

                // Apply brightness to system backlight
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
