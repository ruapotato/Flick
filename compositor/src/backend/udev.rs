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
        drm::{DrmDevice, DrmDeviceFd, DrmEvent, DrmEventMetadata, DrmEventTime, GbmBufferedSurface},
        egl::{EGLContext, EGLDisplay},
        input::InputEvent,
        libinput::{LibinputInputBackend, LibinputSessionInterface},
        renderer::{
            damage::OutputDamageTracker,
            gles::GlesRenderer,
            Bind, Frame, Renderer,
        },
        session::{
            libseat::LibSeatSession,
            Event as SessionEvent, Session,
        },
        udev::{UdevBackend, UdevEvent},
    },
    output::{Mode, Output, PhysicalProperties, Subpixel},
    reexports::{
        calloop::{EventLoop, RegistrationToken},
        drm::control::{connector, crtc, Device as DrmControlDevice, ModeTypeFlags},
        input::Libinput,
        wayland_server::Display,
    },
    utils::{DeviceFd, Transform},
};

// Re-import libinput types for keyboard handling
use smithay::reexports::input::event::keyboard::KeyboardEventTrait;

use smithay::wayland::xwayland_shell::XWaylandShellState;
use smithay::xwayland::{XWayland, XWaylandEvent, xwm::X11Wm};

use crate::state::Flick;

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

/// Keyboard modifier state for tracking Ctrl+Alt
#[derive(Default)]
struct ModifierState {
    ctrl: bool,
    alt: bool,
}

pub fn run(shell_cmd: Option<String>) -> Result<()> {
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
            }
        })
        .map_err(|e| anyhow::anyhow!("Failed to insert session source: {:?}", e))?;

    // Track modifier state for VT switching
    let modifiers = Rc::new(RefCell::new(ModifierState::default()));
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

    // Start shell if requested
    if let Some(cmd) = shell_cmd {
        info!("Starting shell: {}", cmd);

        // Get XDG_RUNTIME_DIR - where the Wayland socket is created
        let xdg_runtime_dir = std::env::var("XDG_RUNTIME_DIR")
            .unwrap_or_else(|_| "/run/user/1000".to_string());

        info!("WAYLAND_DISPLAY={:?}", state.socket_name);
        info!("XDG_RUNTIME_DIR={}", xdg_runtime_dir);

        // Check if the socket exists
        let socket_path = std::path::Path::new(&xdg_runtime_dir)
            .join(state.socket_name.to_str().unwrap_or("wayland-0"));
        info!("Socket path: {:?}, exists: {}", socket_path, socket_path.exists());

        // Run wayland-info in a thread (so it doesn't block before event loop starts)
        let socket_name_clone = state.socket_name.clone();
        let xdg_clone = xdg_runtime_dir.clone();
        std::thread::spawn(move || {
            // Small delay to let the event loop start
            std::thread::sleep(std::time::Duration::from_millis(500));

            let wayland_info_output = std::process::Command::new("wayland-info")
                .env("WAYLAND_DISPLAY", &socket_name_clone)
                .env("XDG_RUNTIME_DIR", &xdg_clone)
                .output();

            match wayland_info_output {
                Ok(output) => {
                    let stdout = String::from_utf8_lossy(&output.stdout);
                    let stderr = String::from_utf8_lossy(&output.stderr);
                    // Write to a file since we can't use tracing from a thread easily
                    let _ = std::fs::write(
                        format!("{}/wayland-info.log", xdg_clone),
                        format!("STDOUT:\n{}\n\nSTDERR:\n{}", stdout, stderr)
                    );
                }
                Err(e) => {
                    let _ = std::fs::write(
                        format!("{}/wayland-info.log", xdg_clone),
                        format!("ERROR: {:?}", e)
                    );
                }
            }
        });

        // Redirect shell output to a log file so we can debug issues
        let shell_log_path = format!("{}/flick-shell.log", xdg_runtime_dir);
        let shell_log = std::fs::File::create(&shell_log_path)
            .unwrap_or_else(|_| std::fs::File::create("/tmp/flick-shell.log").unwrap());
        let shell_log_err = shell_log.try_clone().unwrap();

        let child = std::process::Command::new("sh")
            .arg("-c")
            .arg(&cmd)
            .env("WAYLAND_DISPLAY", &state.socket_name)
            .env("XDG_RUNTIME_DIR", &xdg_runtime_dir)
            .env("WAYLAND_DEBUG", "1")  // Enable protocol debugging
            .stdout(shell_log)
            .stderr(shell_log_err)
            .spawn();

        match child {
            Ok(child) => {
                info!("Shell process started with PID: {}", child.id());
                info!("Shell output logged to: {}", shell_log_path);
            }
            Err(e) => {
                error!("Failed to start shell: {:?}", e);
            }
        }
    }

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
    use smithay::backend::renderer::element::surface::WaylandSurfaceRenderElement;
    use smithay::desktop::space::SpaceRenderElements;

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

    let window_count = state.space.elements().count();
    if window_count > 0 {
        debug!("Rendering {} windows", window_count);
        // Log details of each window for debugging
        for (i, window) in state.space.elements().enumerate() {
            let geo = window.geometry();
            let is_x11 = window.x11_surface().is_some();
            debug!("  Window {}: x11={}, geometry={:?}", i, is_x11, geo);
        }
    }

    // Get output size
    let output_size = output
        .current_mode()
        .map(|m| m.size)
        .unwrap_or_else(|| (1920, 1080).into());

    // Bind the dmabuf to the renderer
    let mut fb = renderer
        .bind(&mut dmabuf)
        .map_err(|e| anyhow::anyhow!("Failed to bind dmabuf: {:?}", e))?;

    // Get render elements from space
    let scale = output.current_scale().fractional_scale();
    let elements: Vec<SpaceRenderElements<GlesRenderer, WaylandSurfaceRenderElement<GlesRenderer>>> = state
        .space
        .render_elements_for_output(renderer, output, scale as f32)
        .unwrap_or_default();

    if !elements.is_empty() {
        debug!("Got {} render elements to draw", elements.len());
    }

    // Use damage tracker for proper rendering (handles textures, blending, etc.)
    let render_res = surface_data.damage_tracker.render_output(
        renderer,
        &mut fb,
        _age as usize,
        &elements,
        [0.1, 0.1, 0.3, 1.0],  // Dark blue background
    );

    match render_res {
        Ok(render_output_result) => {
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

            // Track modifier state for VT switching
            // Evdev keycodes: 29=LCtrl, 97=RCtrl, 56=LAlt, 100=RAlt
            match evdev_keycode {
                29 | 97 => {
                    modifiers.borrow_mut().ctrl = pressed;
                }
                56 | 100 => {
                    modifiers.borrow_mut().alt = pressed;
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

                // Find surface under pointer
                let under = state.space.element_under(pointer_pos)
                    .map(|(window, loc)| {
                        let surface = window.toplevel()
                            .map(|t| t.wl_surface().clone());
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

                // Find surface under pointer
                let under = state.space.element_under(pointer_pos)
                    .map(|(window, loc)| {
                        let surface = window.toplevel()
                            .map(|t| t.wl_surface().clone());
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
                        if let Some(toplevel) = window.toplevel() {
                            let wl_surface = toplevel.wl_surface().clone();
                            if let Some(keyboard) = state.seat.get_keyboard() {
                                keyboard.set_focus(state, Some(wl_surface), serial);
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
            if let Some(gesture_event) = state.gesture_recognizer.touch_down(slot_id, touch_pos) {
                debug!("Gesture event: {:?}", gesture_event);
            }

            if let Some(touch) = state.seat.get_touch() {
                let serial = smithay::utils::SERIAL_COUNTER.next_serial();

                // Find surface under touch point
                let under = state.space.element_under(touch_pos)
                    .map(|(window, loc)| {
                        let surface = window.toplevel()
                            .map(|t| t.wl_surface().clone());
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
            }

            if let Some(touch) = state.seat.get_touch() {
                // Find surface under touch point
                let under = state.space.element_under(touch_pos)
                    .map(|(window, loc)| {
                        let surface = window.toplevel()
                            .map(|t| t.wl_surface().clone());
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
        InputEvent::TouchUp { event } => {
            use smithay::backend::input::TouchEvent;
            use crate::input::gesture_to_action;

            debug!("Touch up at slot {:?}", event.slot());

            // Feed to gesture recognizer and handle completed gestures
            let slot_id: i32 = event.slot().into();
            if let Some(gesture_event) = state.gesture_recognizer.touch_up(slot_id) {
                debug!("Gesture completed: {:?}", gesture_event);
                let action = gesture_to_action(&gesture_event);
                state.send_gesture_action(&action);
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
