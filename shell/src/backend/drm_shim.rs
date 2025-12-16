//! DRM Shim backend - uses drm-hwcomposer-shim for libhybris devices
//!
//! This backend provides display and rendering via hwcomposer, using
//! the drm-hwcomposer-shim crate to abstract Android's hwcomposer.
//! Touch input comes from libinput via LibSeatSession.

use std::{
    cell::RefCell,
    rc::Rc,
    sync::Arc,
    time::Duration,
};

use anyhow::Result;
use tracing::{debug, error, info, warn};

use smithay::{
    backend::{
        input::InputEvent,
        libinput::{LibinputInputBackend, LibinputSessionInterface},
        session::{
            libseat::LibSeatSession,
            Event as SessionEvent, Session,
        },
    },
    input::keyboard::ModifiersState as ModifierState,
    output::{Mode, Output, PhysicalProperties, Subpixel},
    reexports::{
        calloop::{EventLoop, LoopHandle, timer::{Timer, TimeoutAction}},
        input::Libinput,
        wayland_server::Display,
    },
    utils::{Point, Transform},
    wayland::compositor,
};

use smithay::reexports::input::{LibinputInterface};

use drm_hwcomposer_shim::{HwcDrmDevice, HwcGbmDevice};

use khronos_egl as egl;

use crate::state::Flick;
use crate::shell::ShellView;

/// Direct input interface that bypasses libseat
/// Used as a fallback when libseat session isn't available
struct DirectInputInterface;

impl LibinputInterface for DirectInputInterface {
    fn open_restricted(&mut self, path: &std::path::Path, flags: i32) -> Result<std::os::unix::io::OwnedFd, i32> {
        use std::os::unix::io::OwnedFd;
        use std::os::unix::fs::OpenOptionsExt;
        use std::os::unix::io::IntoRawFd;

        info!("DirectInput: Opening device {:?}", path);

        let mut options = std::fs::OpenOptions::new();
        options.read(true);
        options.custom_flags(flags);

        // For input devices we also need write access
        if flags & libc::O_RDWR != 0 {
            options.write(true);
        }

        match options.open(path) {
            Ok(file) => {
                let fd = file.into_raw_fd();
                info!("DirectInput: Opened {:?} as fd {}", path, fd);
                // SAFETY: We just got this fd from open(), it's valid and we own it
                Ok(unsafe { OwnedFd::from_raw_fd(fd) })
            }
            Err(e) => {
                warn!("DirectInput: Failed to open {:?}: {}", path, e);
                Err(e.raw_os_error().unwrap_or(libc::ENOENT))
            }
        }
    }

    fn close_restricted(&mut self, fd: std::os::unix::io::OwnedFd) {
        use std::os::unix::io::AsRawFd;
        info!("DirectInput: Closing fd {}", fd.as_raw_fd());
        // OwnedFd will close the fd when dropped
        drop(fd);
    }
}

use std::os::unix::io::{FromRawFd, AsRawFd};

/// DRM Shim display state
pub struct ShimDisplay {
    pub drm_device: Arc<HwcDrmDevice>,
    #[allow(dead_code)]
    pub gbm_device: Arc<HwcGbmDevice>,
    pub egl_instance: egl::DynamicInstance<egl::EGL1_4>,
    pub egl_display: egl::Display,
    pub egl_surface: egl::Surface,
    pub egl_context: egl::Context,
    pub width: u32,
    pub height: u32,
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

    // Initialize OpenGL ES
    unsafe { gl::init(); }
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
    let shim_display = Rc::new(RefCell::new(shim_display));

    // Check if running as root - if so, use direct input access since libseat won't work properly
    let running_as_root = unsafe { libc::geteuid() } == 0;

    // Try to initialize libseat session for input device access
    // Fall back to direct input access if libseat is not available or running as root
    let (session, notifier, libinput_backend) = if running_as_root {
        info!("Running as root, using direct input access (bypassing libseat)");

        // Initialize libinput with direct access (bypasses libseat)
        let mut libinput_context = Libinput::new_with_udev(DirectInputInterface);
        libinput_context.udev_assign_seat("seat0").unwrap();
        let libinput_backend = LibinputInputBackend::new(libinput_context);

        (None, None, libinput_backend)
    } else {
        match LibSeatSession::new() {
            Ok((session, notifier)) => {
                let session = Rc::new(RefCell::new(session));
                info!("Session created, seat: {}", session.borrow().seat());

                // Initialize libinput with libseat
                let libinput_session = LibinputSessionInterface::from(session.borrow().clone());
                let mut libinput_context = Libinput::new_with_udev(libinput_session);
                libinput_context.udev_assign_seat(&session.borrow().seat()).unwrap();
                let libinput_backend = LibinputInputBackend::new(libinput_context);

                (Some(session), Some(notifier), libinput_backend)
            }
            Err(e) => {
                warn!("LibSeatSession not available: {:?}", e);
                info!("Falling back to direct input access");

                // Initialize libinput with direct access (bypasses libseat)
                let mut libinput_context = Libinput::new_with_udev(DirectInputInterface);
                libinput_context.udev_assign_seat("seat0").unwrap();
                let libinput_backend = LibinputInputBackend::new(libinput_context);

                (None, None, libinput_backend)
            }
        }
    };

    // session is kept around for its lifetime (input device access)
    let _session = session;

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

    // Update state with actual screen size
    state.screen_size = (width as i32, height as i32).into();
    state.gesture_recognizer.screen_size = state.screen_size;
    state.shell.screen_size = state.screen_size;
    state.shell.quick_settings.screen_size = state.screen_size;

    if let Some(ref mut slint_ui) = state.shell.slint_ui {
        slint_ui.set_size(state.screen_size);
    }

    // Track session state
    let session_active = Rc::new(RefCell::new(true));
    let session_active_for_notifier = session_active.clone();

    let modifiers = Rc::new(RefCell::new(ModifierState::default()));
    let modifiers_for_notifier = modifiers.clone();

    // Add session notifier (only if libseat session is available)
    if let Some(notifier) = notifier {
        loop_handle
            .insert_source(notifier, move |event, _, _state| match event {
                SessionEvent::PauseSession => {
                    info!("Session paused");
                    *session_active_for_notifier.borrow_mut() = false;
                }
                SessionEvent::ActivateSession => {
                    info!("Session activated");
                    *session_active_for_notifier.borrow_mut() = true;
                    *modifiers_for_notifier.borrow_mut() = ModifierState::default();
                }
            })
            .map_err(|e| anyhow::anyhow!("Failed to insert session source: {:?}", e))?;
    } else {
        info!("No session notifier - running in direct input mode");
    }

    // Add libinput to event loop
    let modifiers_for_input = modifiers.clone();

    loop_handle
        .insert_source(libinput_backend, move |event, _, state| {
            handle_input_event(state, event, &modifiers_for_input);
        })
        .map_err(|e| anyhow::anyhow!("Failed to insert input source: {:?}", e))?;

    info!("libinput initialized for touch input");

    // Frame timer for rendering at 60fps
    let frame_timer = Timer::from_duration(Duration::from_millis(16));
    let shim_display_clone = shim_display.clone();

    loop_handle.insert_source(frame_timer, move |_, _, state| {
        // Render frame
        render_frame(&shim_display_clone, state);

        // Schedule next frame
        TimeoutAction::ToDuration(Duration::from_millis(16))
    }).expect("Failed to insert frame timer");

    info!("DRM shim backend initialized, entering event loop");

    // Run the event loop
    loop {
        // Dispatch Wayland events
        state.dispatch_clients();

        // Check for unlock signal from external lock screen app
        if state.shell.check_unlock_signal() {
            info!("Unlock signal received, unlocking");
            state.shell.lock_screen_active = false;
            state.shell.view = ShellView::Home;
        }

        // Run one iteration of the event loop
        if let Err(e) = event_loop.dispatch(Some(Duration::from_millis(1)), &mut state) {
            error!("Event loop error: {:?}", e);
        }
    }
}

/// Frame counter for render_frame logging
static mut FRAME_COUNT: u64 = 0;

/// Render a frame
fn render_frame(
    display: &Rc<RefCell<ShimDisplay>>,
    state: &Flick,
) {
    let display = display.borrow();

    unsafe {
        FRAME_COUNT += 1;
    }
    let frame_num = unsafe { FRAME_COUNT };
    let log_frame = frame_num % 60 == 0; // Log every 60 frames

    // Set viewport
    unsafe {
        if let Some(f) = gl::FN_VIEWPORT {
            f(0, 0, display.width as i32, display.height as i32);
        }
    }

    // Determine background color based on shell view
    let shell_view = state.shell.view;
    if log_frame {
        info!("Shell view: {:?}, lock_screen_active: {}", shell_view, state.shell.lock_screen_active);
    }
    let bg_color = match shell_view {
        ShellView::Home | ShellView::QuickSettings | ShellView::PickDefault | ShellView::LockScreen => [0.1, 0.1, 0.15, 1.0],
        ShellView::Switcher => [0.05, 0.05, 0.08, 1.0],
        ShellView::App => [0.0, 0.0, 0.0, 1.0],
    };

    // Clear screen with background color
    unsafe {
        gl::ClearColor(bg_color[0], bg_color[1], bg_color[2], bg_color[3]);
        gl::Clear(gl::COLOR_BUFFER_BIT);
    }

    // Check if QML lockscreen app is connected
    let element_count = state.space.elements().count();
    let qml_lockscreen_connected = shell_view == ShellView::LockScreen
        && state.shell.lock_screen_active
        && element_count > 0;

    if log_frame {
        info!("RENDER frame {}: view={:?}, lock_active={}, elements={}, qml_connected={}",
            frame_num, shell_view, state.shell.lock_screen_active, element_count, qml_lockscreen_connected);
    }

    // Render Slint UI for shell views (but not when QML lockscreen is connected)
    if !qml_lockscreen_connected {
        match shell_view {
            ShellView::Home | ShellView::QuickSettings | ShellView::Switcher | ShellView::PickDefault | ShellView::LockScreen => {
                // Update Slint timers and animations
                slint::platform::update_timers_and_animations();

                // Set up Slint UI state based on current view
                if let Some(ref slint_ui) = state.shell.slint_ui {
                    match shell_view {
                        ShellView::LockScreen => {
                            slint_ui.set_view("lock");
                            slint_ui.set_lock_time(&chrono::Local::now().format("%H:%M").to_string());
                            slint_ui.set_lock_date(&chrono::Local::now().format("%A, %B %e").to_string());
                            slint_ui.set_pin_length(state.shell.lock_state.entered_pin.len() as i32);
                        }
                        ShellView::Home => {
                            slint_ui.set_view("home");
                            let slint_categories = state.shell.get_categories_with_icons();
                            slint_ui.set_categories(slint_categories);
                            slint_ui.set_show_popup(state.shell.popup_showing);
                            slint_ui.set_wiggle_mode(state.shell.wiggle_mode);
                        }
                        ShellView::QuickSettings => {
                            slint_ui.set_view("quick-settings");
                            slint_ui.set_brightness(state.shell.quick_settings.brightness);
                            slint_ui.set_wifi_enabled(state.system.wifi_enabled);
                            slint_ui.set_bluetooth_enabled(state.system.bluetooth_enabled);
                        }
                        ShellView::Switcher => {
                            slint_ui.set_view("switcher");
                            slint_ui.set_switcher_scroll(state.shell.switcher_scroll as f32);
                            let windows: Vec<_> = state.space.elements()
                                .enumerate()
                                .map(|(i, window)| {
                                    let title = window.x11_surface()
                                        .map(|x11| {
                                            let t = x11.title();
                                            if !t.is_empty() { t } else { x11.class() }
                                        })
                                        .unwrap_or_else(|| format!("Window {}", i + 1));
                                    let app_class = window.x11_surface()
                                        .map(|x11| x11.class())
                                        .unwrap_or_else(|| "app".to_string());
                                    (i as i32, title, app_class)
                                })
                                .collect();
                            slint_ui.set_switcher_windows(windows);
                        }
                        ShellView::PickDefault => {
                            slint_ui.set_view("pick-default");
                        }
                        _ => {}
                    }
                }

                // Get Slint rendered pixels
                if let Some(ref slint_ui) = state.shell.slint_ui {
                    if let Some((tex_width, tex_height, pixels)) = slint_ui.render() {
                        if log_frame {
                            info!("SLINT RENDER frame {}: {}x{}", frame_num, tex_width, tex_height);
                        }
                        unsafe {
                            gl::render_texture(tex_width, tex_height, &pixels, display.width, display.height);
                        }
                    }
                }
            }
            _ => {}
        }
    }

    // Render Wayland windows for App view OR QML lockscreen
    if shell_view == ShellView::App || qml_lockscreen_connected {
        let windows: Vec<_> = state.space.elements().cloned().collect();
        debug!("Rendering {} Wayland windows", windows.len());

        for (i, window) in windows.iter().enumerate() {
            if let Some(toplevel) = window.toplevel() {
                let wl_surface = toplevel.wl_surface();

                // Get stored buffer from surface user data
                let buffer_info: Option<(u32, u32, Vec<u8>)> = compositor::with_states(wl_surface, |data| {
                    use std::cell::RefCell;
                    use crate::state::SurfaceBufferData;

                    if let Some(buffer_data) = data.data_map.get::<RefCell<SurfaceBufferData>>() {
                        let data = buffer_data.borrow();
                        if let Some(ref stored) = data.buffer {
                            Some((stored.width, stored.height, stored.pixels.clone()))
                        } else {
                            None
                        }
                    } else {
                        None
                    }
                });

                if let Some((tex_width, tex_height, pixels)) = buffer_info {
                    if log_frame {
                        info!("Window {} RENDER: {}x{}", i, tex_width, tex_height);
                    }
                    unsafe {
                        gl::render_texture(tex_width, tex_height, &pixels, display.width, display.height);
                    }
                }
            }
        }
    }

    // Swap buffers
    if let Err(e) = display.drm_device.swap_buffers() {
        error!("Failed to swap buffers: {}", e);
    }
}

/// Handle input events from libinput
fn handle_input_event(
    state: &mut Flick,
    event: InputEvent<LibinputInputBackend>,
    _modifiers: &Rc<RefCell<ModifierState>>,
) {
    use smithay::backend::input::{
        Event, TouchEvent, AbsolutePositionEvent,
    };

    match event {
        InputEvent::DeviceAdded { device } => {
            info!("Input device added: {}", device.name());
        }
        InputEvent::DeviceRemoved { device } => {
            info!("Input device removed: {}", device.name());
        }
        InputEvent::TouchDown { event } => {
            use smithay::backend::input::TouchEvent;
            let slot_id: i32 = event.slot().into();
            let position = event.position_transformed(state.screen_size);
            let touch_pos = Point::from((position.x, position.y));

            info!("TOUCH DOWN: slot={}, pos=({:.0}, {:.0}), view={:?}",
                  slot_id, touch_pos.x, touch_pos.y, state.shell.view);

            // Track touch position
            state.last_touch_pos.insert(slot_id, touch_pos);

            // Process gesture
            if let Some(gesture_event) = state.gesture_recognizer.touch_down(slot_id, touch_pos) {
                debug!("Gesture touch_down: {:?}", gesture_event);
            }

            // Handle shell-specific touch
            let shell_view = state.shell.view;
            match shell_view {
                ShellView::App => {
                    // Forward touch to Wayland client
                    if let Some(touch) = state.seat.get_touch() {
                        let serial = smithay::utils::SERIAL_COUNTER.next_serial();

                        // Find surface under touch point
                        let under = state.space.element_under(touch_pos.to_f64())
                            .map(|(window, loc)| {
                                let surface = window.toplevel()
                                    .map(|t| t.wl_surface().clone());
                                (surface, loc)
                            });

                        let focus = under.as_ref().and_then(|(surface, loc)| {
                            surface.as_ref().map(|s| (s.clone(), loc.to_f64()))
                        });

                        touch.down(
                            state,
                            focus,
                            &smithay::input::touch::DownEvent {
                                slot: event.slot(),
                                location: touch_pos.to_f64(),
                                serial,
                                time: event.time_msec(),
                            },
                        );
                        touch.frame(state);
                    }
                }
                ShellView::Home => {
                    let touched_category = state.shell.hit_test_category(touch_pos);
                    if let Some(category) = touched_category {
                        info!("Touch down on category {:?}", category);
                        state.shell.start_category_touch(touch_pos, category);
                    } else {
                        state.shell.start_home_touch(touch_pos.y, None);
                    }
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_pressed(touch_pos.x as f32, touch_pos.y as f32);
                    }
                }
                ShellView::QuickSettings => {
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_pressed(touch_pos.x as f32, touch_pos.y as f32);
                    }
                }
                ShellView::LockScreen => {
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_pressed(touch_pos.x as f32, touch_pos.y as f32);
                    }
                }
                _ => {}
            }
        }
        InputEvent::TouchMotion { event } => {
            use smithay::backend::input::TouchEvent;
            let slot_id: i32 = event.slot().into();
            let position = event.position_transformed(state.screen_size);
            let touch_pos = Point::from((position.x, position.y));

            // Update tracked touch position
            state.last_touch_pos.insert(slot_id, touch_pos);

            // Process gesture
            if let Some(gesture_event) = state.gesture_recognizer.touch_motion(slot_id, touch_pos) {
                debug!("Gesture touch_motion: {:?}", gesture_event);
                state.shell.handle_gesture(&gesture_event);
            }

            // Handle shell-specific motion
            let shell_view = state.shell.view;
            match shell_view {
                ShellView::App => {
                    // Forward to Wayland client
                    if let Some(touch) = state.seat.get_touch() {
                        // Find surface under touch point
                        let under = state.space.element_under(touch_pos.to_f64())
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
                                location: touch_pos.to_f64(),
                                time: event.time_msec(),
                            },
                        );
                        touch.frame(state);
                    }
                }
                ShellView::Home => {
                    state.shell.update_drag(touch_pos);
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_moved(touch_pos.x as f32, touch_pos.y as f32);
                    }
                }
                ShellView::QuickSettings => {
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_moved(touch_pos.x as f32, touch_pos.y as f32);
                    }
                }
                ShellView::LockScreen => {
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_moved(touch_pos.x as f32, touch_pos.y as f32);
                    }
                }
                _ => {}
            }
        }
        InputEvent::TouchUp { event } => {
            use smithay::backend::input::TouchEvent;
            let slot_id: i32 = event.slot().into();

            // Get last known position
            let last_pos = state.last_touch_pos.get(&slot_id).copied()
                .unwrap_or_else(|| Point::from((0.0, 0.0)));

            info!("TOUCH UP: slot={}, pos=({:.0}, {:.0}), view={:?}",
                  slot_id, last_pos.x, last_pos.y, state.shell.view);

            // Process gesture
            if let Some(gesture_event) = state.gesture_recognizer.touch_up(slot_id) {
                debug!("Gesture touch_up: {:?}", gesture_event);
                state.shell.handle_gesture(&gesture_event);
            }

            // Handle shell-specific touch up
            let shell_view = state.shell.view;
            match shell_view {
                ShellView::App => {
                    // Forward to Wayland client
                    if let Some(touch) = state.seat.get_touch() {
                        let serial = smithay::utils::SERIAL_COUNTER.next_serial();
                        touch.up(
                            state,
                            &smithay::input::touch::UpEvent {
                                slot: event.slot(),
                                serial,
                                time: event.time_msec(),
                            },
                        );
                        touch.frame(state);
                    }
                }
                ShellView::Home => {
                    state.shell.end_home_touch();
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_released(last_pos.x as f32, last_pos.y as f32);
                    }
                }
                ShellView::QuickSettings => {
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_released(last_pos.x as f32, last_pos.y as f32);
                    }
                }
                ShellView::LockScreen => {
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_released(last_pos.x as f32, last_pos.y as f32);
                    }
                }
                _ => {}
            }

            // Clean up
            state.last_touch_pos.remove(&slot_id);
        }
        InputEvent::TouchCancel { .. } => {
            debug!("Touch cancel");
            state.gesture_recognizer.touch_cancel();
            state.last_touch_pos.clear();
        }
        InputEvent::TouchFrame { .. } => {
            // Frame marker - no action needed
        }
        _ => {
            // Other events (keyboard, pointer) - handle if needed
        }
    }
}

// OpenGL ES bindings
mod gl {
    use std::os::raw::{c_char, c_int, c_uint, c_void};
    use std::ffi::CString;

    // GL constants
    pub const COLOR_BUFFER_BIT: u32 = 0x00004000;
    pub const TEXTURE_2D: u32 = 0x0DE1;
    pub const RGBA: u32 = 0x1908;
    pub const UNSIGNED_BYTE: u32 = 0x1401;
    pub const TEXTURE_MIN_FILTER: u32 = 0x2801;
    pub const TEXTURE_MAG_FILTER: u32 = 0x2800;
    pub const LINEAR: i32 = 0x2601;
    pub const FLOAT: u32 = 0x1406;
    pub const TRIANGLE_STRIP: u32 = 0x0005;
    pub const VERTEX_SHADER: u32 = 0x8B31;
    pub const FRAGMENT_SHADER: u32 = 0x8B30;
    pub const COMPILE_STATUS: u32 = 0x8B81;
    pub const LINK_STATUS: u32 = 0x8B82;
    pub const BLEND: u32 = 0x0BE2;
    pub const SRC_ALPHA: u32 = 0x0302;
    pub const ONE_MINUS_SRC_ALPHA: u32 = 0x0303;
    pub const FALSE: u8 = 0;

    // Function pointer types
    type ClearColorFn = unsafe extern "C" fn(f32, f32, f32, f32);
    type ClearFn = unsafe extern "C" fn(u32);
    type ViewportFn = unsafe extern "C" fn(i32, i32, i32, i32);
    type GenTexturesFn = unsafe extern "C" fn(i32, *mut u32);
    type BindTextureFn = unsafe extern "C" fn(u32, u32);
    type TexImage2DFn = unsafe extern "C" fn(u32, i32, i32, i32, i32, i32, u32, u32, *const c_void);
    type TexParameteriFn = unsafe extern "C" fn(u32, u32, i32);
    type CreateShaderFn = unsafe extern "C" fn(u32) -> u32;
    type ShaderSourceFn = unsafe extern "C" fn(u32, i32, *const *const c_char, *const i32);
    type CompileShaderFn = unsafe extern "C" fn(u32);
    type GetShaderivFn = unsafe extern "C" fn(u32, u32, *mut i32);
    type CreateProgramFn = unsafe extern "C" fn() -> u32;
    type AttachShaderFn = unsafe extern "C" fn(u32, u32);
    type LinkProgramFn = unsafe extern "C" fn(u32);
    type GetProgramivFn = unsafe extern "C" fn(u32, u32, *mut i32);
    type UseProgramFn = unsafe extern "C" fn(u32);
    type GetAttribLocationFn = unsafe extern "C" fn(u32, *const c_char) -> i32;
    type GetUniformLocationFn = unsafe extern "C" fn(u32, *const c_char) -> i32;
    type EnableVertexAttribArrayFn = unsafe extern "C" fn(u32);
    type VertexAttribPointerFn = unsafe extern "C" fn(u32, i32, u32, u8, i32, *const c_void);
    type DrawArraysFn = unsafe extern "C" fn(u32, i32, i32);
    type Uniform1iFn = unsafe extern "C" fn(i32, i32);
    type ActiveTextureFn = unsafe extern "C" fn(u32);
    type EnableFn = unsafe extern "C" fn(u32);
    type DisableFn = unsafe extern "C" fn(u32);
    type BlendFuncFn = unsafe extern "C" fn(u32, u32);
    type DeleteTexturesFn = unsafe extern "C" fn(i32, *const u32);
    type GetErrorFn = unsafe extern "C" fn() -> u32;
    type FlushFn = unsafe extern "C" fn();

    // Cached function pointers
    static mut FN_CLEAR_COLOR: Option<ClearColorFn> = None;
    static mut FN_CLEAR: Option<ClearFn> = None;
    pub static mut FN_VIEWPORT: Option<ViewportFn> = None;
    static mut FN_GEN_TEXTURES: Option<GenTexturesFn> = None;
    static mut FN_BIND_TEXTURE: Option<BindTextureFn> = None;
    static mut FN_TEX_IMAGE_2D: Option<TexImage2DFn> = None;
    static mut FN_TEX_PARAMETERI: Option<TexParameteriFn> = None;
    static mut FN_CREATE_SHADER: Option<CreateShaderFn> = None;
    static mut FN_SHADER_SOURCE: Option<ShaderSourceFn> = None;
    static mut FN_COMPILE_SHADER: Option<CompileShaderFn> = None;
    static mut FN_GET_SHADERIV: Option<GetShaderivFn> = None;
    static mut FN_CREATE_PROGRAM: Option<CreateProgramFn> = None;
    static mut FN_ATTACH_SHADER: Option<AttachShaderFn> = None;
    static mut FN_LINK_PROGRAM: Option<LinkProgramFn> = None;
    static mut FN_GET_PROGRAMIV: Option<GetProgramivFn> = None;
    static mut FN_USE_PROGRAM: Option<UseProgramFn> = None;
    static mut FN_GET_ATTRIB_LOCATION: Option<GetAttribLocationFn> = None;
    static mut FN_GET_UNIFORM_LOCATION: Option<GetUniformLocationFn> = None;
    static mut FN_ENABLE_VERTEX_ATTRIB_ARRAY: Option<EnableVertexAttribArrayFn> = None;
    static mut FN_VERTEX_ATTRIB_POINTER: Option<VertexAttribPointerFn> = None;
    static mut FN_DRAW_ARRAYS: Option<DrawArraysFn> = None;
    static mut FN_UNIFORM1I: Option<Uniform1iFn> = None;
    static mut FN_ACTIVE_TEXTURE: Option<ActiveTextureFn> = None;
    static mut FN_ENABLE: Option<EnableFn> = None;
    static mut FN_DISABLE: Option<DisableFn> = None;
    static mut FN_BLEND_FUNC: Option<BlendFuncFn> = None;
    static mut FN_DELETE_TEXTURES: Option<DeleteTexturesFn> = None;
    static mut FN_GET_ERROR: Option<GetErrorFn> = None;
    static mut FN_FLUSH: Option<FlushFn> = None;

    static mut INITIALIZED: bool = false;
    static mut SHADER_PROGRAM: u32 = 0;
    static mut ATTR_POSITION: i32 = -1;
    static mut ATTR_TEXCOORD: i32 = -1;
    static mut UNIFORM_TEXTURE: i32 = -1;

    const VERTEX_SHADER_SRC: &str = r#"
        attribute vec2 a_position;
        attribute vec2 a_texcoord;
        varying vec2 v_texcoord;
        void main() {
            gl_Position = vec4(a_position, 0.0, 1.0);
            v_texcoord = a_texcoord;
        }
    "#;

    const FRAGMENT_SHADER_SRC: &str = r#"
        precision mediump float;
        varying vec2 v_texcoord;
        uniform sampler2D u_texture;
        void main() {
            gl_FragColor = texture2D(u_texture, v_texcoord);
        }
    "#;

    unsafe fn load_fn<T>(lib: *mut c_void, name: &[u8]) -> Option<T> {
        let ptr = libc::dlsym(lib, name.as_ptr() as *const _);
        if ptr.is_null() {
            None
        } else {
            Some(std::mem::transmute_copy(&ptr))
        }
    }

    pub unsafe fn init() {
        if INITIALIZED {
            return;
        }

        let lib = libc::dlopen(
            b"libGLESv2.so.2\0".as_ptr() as *const _,
            libc::RTLD_NOW | libc::RTLD_GLOBAL,
        );
        let lib = if lib.is_null() {
            libc::dlopen(
                b"libGLESv2.so\0".as_ptr() as *const _,
                libc::RTLD_NOW | libc::RTLD_GLOBAL,
            )
        } else {
            lib
        };

        if lib.is_null() {
            tracing::error!("Failed to load libGLESv2");
            return;
        }

        FN_CLEAR_COLOR = load_fn(lib, b"glClearColor\0");
        FN_CLEAR = load_fn(lib, b"glClear\0");
        FN_VIEWPORT = load_fn(lib, b"glViewport\0");
        FN_GEN_TEXTURES = load_fn(lib, b"glGenTextures\0");
        FN_BIND_TEXTURE = load_fn(lib, b"glBindTexture\0");
        FN_TEX_IMAGE_2D = load_fn(lib, b"glTexImage2D\0");
        FN_TEX_PARAMETERI = load_fn(lib, b"glTexParameteri\0");
        FN_CREATE_SHADER = load_fn(lib, b"glCreateShader\0");
        FN_SHADER_SOURCE = load_fn(lib, b"glShaderSource\0");
        FN_COMPILE_SHADER = load_fn(lib, b"glCompileShader\0");
        FN_GET_SHADERIV = load_fn(lib, b"glGetShaderiv\0");
        FN_CREATE_PROGRAM = load_fn(lib, b"glCreateProgram\0");
        FN_ATTACH_SHADER = load_fn(lib, b"glAttachShader\0");
        FN_LINK_PROGRAM = load_fn(lib, b"glLinkProgram\0");
        FN_GET_PROGRAMIV = load_fn(lib, b"glGetProgramiv\0");
        FN_USE_PROGRAM = load_fn(lib, b"glUseProgram\0");
        FN_GET_ATTRIB_LOCATION = load_fn(lib, b"glGetAttribLocation\0");
        FN_GET_UNIFORM_LOCATION = load_fn(lib, b"glGetUniformLocation\0");
        FN_ENABLE_VERTEX_ATTRIB_ARRAY = load_fn(lib, b"glEnableVertexAttribArray\0");
        FN_VERTEX_ATTRIB_POINTER = load_fn(lib, b"glVertexAttribPointer\0");
        FN_DRAW_ARRAYS = load_fn(lib, b"glDrawArrays\0");
        FN_UNIFORM1I = load_fn(lib, b"glUniform1i\0");
        FN_ACTIVE_TEXTURE = load_fn(lib, b"glActiveTexture\0");
        FN_ENABLE = load_fn(lib, b"glEnable\0");
        FN_DISABLE = load_fn(lib, b"glDisable\0");
        FN_BLEND_FUNC = load_fn(lib, b"glBlendFunc\0");
        FN_DELETE_TEXTURES = load_fn(lib, b"glDeleteTextures\0");
        FN_GET_ERROR = load_fn(lib, b"glGetError\0");
        FN_FLUSH = load_fn(lib, b"glFlush\0");

        if let Some(program) = create_shader_program() {
            SHADER_PROGRAM = program;

            let pos_name = CString::new("a_position").unwrap();
            let tex_name = CString::new("a_texcoord").unwrap();
            let uni_name = CString::new("u_texture").unwrap();

            if let Some(f) = FN_GET_ATTRIB_LOCATION {
                ATTR_POSITION = f(program, pos_name.as_ptr());
                ATTR_TEXCOORD = f(program, tex_name.as_ptr());
            }
            if let Some(f) = FN_GET_UNIFORM_LOCATION {
                UNIFORM_TEXTURE = f(program, uni_name.as_ptr());
            }

            tracing::info!("GL shader program created: program={}, pos={}, tex={}, uni={}",
                SHADER_PROGRAM, ATTR_POSITION, ATTR_TEXCOORD, UNIFORM_TEXTURE);
        }

        INITIALIZED = true;
        tracing::info!("OpenGL ES 2.0 functions loaded");
    }

    unsafe fn create_shader_program() -> Option<u32> {
        let create_shader = FN_CREATE_SHADER?;
        let shader_source = FN_SHADER_SOURCE?;
        let compile_shader = FN_COMPILE_SHADER?;
        let get_shaderiv = FN_GET_SHADERIV?;
        let create_program = FN_CREATE_PROGRAM?;
        let attach_shader = FN_ATTACH_SHADER?;
        let link_program = FN_LINK_PROGRAM?;
        let get_programiv = FN_GET_PROGRAMIV?;

        let vs = create_shader(VERTEX_SHADER);
        let vs_src = CString::new(VERTEX_SHADER_SRC).unwrap();
        let vs_ptr = vs_src.as_ptr();
        shader_source(vs, 1, &vs_ptr, std::ptr::null());
        compile_shader(vs);

        let mut status: i32 = 0;
        get_shaderiv(vs, COMPILE_STATUS, &mut status);
        if status == 0 {
            tracing::error!("Vertex shader compilation failed");
            return None;
        }

        let fs = create_shader(FRAGMENT_SHADER);
        let fs_src = CString::new(FRAGMENT_SHADER_SRC).unwrap();
        let fs_ptr = fs_src.as_ptr();
        shader_source(fs, 1, &fs_ptr, std::ptr::null());
        compile_shader(fs);

        get_shaderiv(fs, COMPILE_STATUS, &mut status);
        if status == 0 {
            tracing::error!("Fragment shader compilation failed");
            return None;
        }

        let program = create_program();
        attach_shader(program, vs);
        attach_shader(program, fs);
        link_program(program);

        get_programiv(program, LINK_STATUS, &mut status);
        if status == 0 {
            tracing::error!("Shader program linking failed");
            return None;
        }

        Some(program)
    }

    #[allow(non_snake_case)]
    pub unsafe fn ClearColor(r: f32, g: f32, b: f32, a: f32) {
        if let Some(f) = FN_CLEAR_COLOR { f(r, g, b, a); }
    }

    #[allow(non_snake_case)]
    pub unsafe fn Clear(mask: u32) {
        if let Some(f) = FN_CLEAR { f(mask); }
    }

    #[allow(non_snake_case)]
    pub unsafe fn GetError() -> u32 {
        if let Some(f) = FN_GET_ERROR { f() } else { 0 }
    }

    #[allow(non_snake_case)]
    pub unsafe fn Flush() {
        if let Some(f) = FN_FLUSH { f(); }
    }

    pub unsafe fn render_texture(tex_width: u32, tex_height: u32, pixels: &[u8], screen_width: u32, screen_height: u32) {
        if SHADER_PROGRAM == 0 || ATTR_POSITION < 0 || ATTR_TEXCOORD < 0 {
            return;
        }

        while GetError() != 0 {}

        if let Some(f) = FN_VIEWPORT {
            f(0, 0, screen_width as i32, screen_height as i32);
        }

        let mut texture: u32 = 0;
        if let Some(f) = FN_GEN_TEXTURES { f(1, &mut texture); }
        if let Some(f) = FN_BIND_TEXTURE { f(TEXTURE_2D, texture); }

        if let Some(f) = FN_TEX_PARAMETERI {
            f(TEXTURE_2D, TEXTURE_MIN_FILTER, LINEAR);
            f(TEXTURE_2D, TEXTURE_MAG_FILTER, LINEAR);
        }

        let expected_size = (tex_width * tex_height * 4) as usize;
        if pixels.len() != expected_size {
            return;
        }

        if let Some(f) = FN_TEX_IMAGE_2D {
            f(TEXTURE_2D, 0, RGBA as i32, tex_width as i32, tex_height as i32,
              0, RGBA, UNSIGNED_BYTE, pixels.as_ptr() as *const c_void);
        }

        if let Some(f) = FN_USE_PROGRAM { f(SHADER_PROGRAM); }
        if let Some(f) = FN_ACTIVE_TEXTURE { f(0x84C0); }
        if let Some(f) = FN_BIND_TEXTURE { f(TEXTURE_2D, texture); }
        if let Some(f) = FN_UNIFORM1I { f(UNIFORM_TEXTURE, 0); }

        #[rustfmt::skip]
        let vertices: [f32; 16] = [
            -1.0, -1.0,  0.0, 1.0,
             1.0, -1.0,  1.0, 1.0,
            -1.0,  1.0,  0.0, 0.0,
             1.0,  1.0,  1.0, 0.0,
        ];

        if let Some(f) = FN_ENABLE_VERTEX_ATTRIB_ARRAY {
            f(ATTR_POSITION as u32);
            f(ATTR_TEXCOORD as u32);
        }

        if let Some(f) = FN_VERTEX_ATTRIB_POINTER {
            let stride = 4 * std::mem::size_of::<f32>() as i32;
            f(ATTR_POSITION as u32, 2, FLOAT, FALSE, stride, vertices.as_ptr() as *const c_void);
            f(ATTR_TEXCOORD as u32, 2, FLOAT, FALSE, stride,
              (vertices.as_ptr() as *const f32).add(2) as *const c_void);
        }

        if let Some(f) = FN_ENABLE { f(BLEND); }
        if let Some(f) = FN_BLEND_FUNC { f(SRC_ALPHA, ONE_MINUS_SRC_ALPHA); }

        if let Some(f) = FN_DRAW_ARRAYS {
            f(TRIANGLE_STRIP, 0, 4);
        }

        Flush();

        if let Some(f) = FN_DISABLE { f(BLEND); }
        if let Some(f) = FN_DELETE_TEXTURES { f(1, &texture); }
    }
}
