//! Hwcomposer backend for Droidian/libhybris devices
//!
//! This backend runs on Android-based Linux distributions (Droidian, UBports, etc.)
//! that use libhybris to access Android's hwcomposer HAL for graphics.
//!
//! Environment variables:
//! - EGL_PLATFORM=hwcomposer (set automatically)
//! - FLICK_DISPLAY_WIDTH / FLICK_DISPLAY_HEIGHT (optional, override display size)

use std::{
    cell::RefCell,
    ffi::c_void,
    rc::Rc,
    sync::atomic::{AtomicBool, Ordering},
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
    output::{Mode, Output, PhysicalProperties, Subpixel},
    reexports::{
        calloop::{EventLoop, timer::{Timer, TimeoutAction}},
        input::Libinput,
        wayland_server::Display,
    },
    utils::Transform,
};

// Note: ImportAll/ImportMem will be needed once we integrate proper Smithay rendering

use crate::state::Flick;
use crate::shell::ShellView;

use super::hwcomposer_ffi::{self, HwcNativeWindow, ANativeWindow, ANativeWindowBuffer, hal_format};

// Re-use khronos-egl for raw EGL access
use khronos_egl as egl;

// Note: Render element macros would go here once we integrate proper Smithay rendering
// For now, we use direct OpenGL rendering as a proof-of-concept

/// Keyboard modifier state
#[derive(Default)]
struct ModifierState {
    ctrl: bool,
    alt: bool,
    shift: bool,
    #[allow(dead_code)]
    super_key: bool,
}

/// Hwcomposer display state
struct HwcDisplay {
    #[allow(dead_code)]
    native_window: HwcNativeWindow,
    egl_instance: egl::DynamicInstance<egl::EGL1_4>,
    egl_display: egl::Display,
    egl_surface: egl::Surface,
    #[allow(dead_code)]
    egl_context: egl::Context,
    #[allow(dead_code)]
    width: u32,
    #[allow(dead_code)]
    height: u32,
}

/// Present callback data
struct PresentCallbackData {
    frame_ready: Rc<AtomicBool>,
}

/// Present callback - called when hwcomposer has a buffer ready to display
unsafe extern "C" fn present_callback(
    user_data: *mut c_void,
    _window: *mut ANativeWindow,
    buffer: *mut ANativeWindowBuffer,
) {
    if user_data.is_null() {
        return;
    }

    let data = &*(user_data as *const PresentCallbackData);

    // Get and close the fence (synchronous wait)
    let fence_fd = hwcomposer_ffi::get_buffer_fence(buffer);
    if fence_fd >= 0 {
        unsafe { libc::close(fence_fd) };
    }

    data.frame_ready.store(true, Ordering::Release);
}

/// Get display dimensions from environment or system
fn get_display_dimensions() -> (u32, u32) {
    // Try environment variables first
    if let (Ok(w), Ok(h)) = (
        std::env::var("FLICK_DISPLAY_WIDTH"),
        std::env::var("FLICK_DISPLAY_HEIGHT"),
    ) {
        if let (Ok(width), Ok(height)) = (w.parse(), h.parse()) {
            info!("Display size from environment: {}x{}", width, height);
            return (width, height);
        }
    }

    // Try /sys/class/graphics/fb0
    if let Ok(contents) = std::fs::read_to_string("/sys/class/graphics/fb0/virtual_size") {
        let parts: Vec<&str> = contents.trim().split(',').collect();
        if parts.len() >= 2 {
            if let (Ok(w), Ok(h)) = (parts[0].parse(), parts[1].parse()) {
                info!("Display size from fb0: {}x{}", w, h);
                return (w, h);
            }
        }
    }

    // Try Android properties
    if let Ok(output) = std::process::Command::new("getprop")
        .arg("ro.sf.lcd_width")
        .output()
    {
        if let Ok(width) = String::from_utf8_lossy(&output.stdout).trim().parse::<u32>() {
            if let Ok(output) = std::process::Command::new("getprop")
                .arg("ro.sf.lcd_height")
                .output()
            {
                if let Ok(height) = String::from_utf8_lossy(&output.stdout).trim().parse::<u32>() {
                    info!("Display size from Android props: {}x{}", width, height);
                    return (width, height);
                }
            }
        }
    }

    // Default
    info!("Using default display size: 1080x2340");
    (1080, 2340)
}

/// Initialize EGL and hwcomposer display
fn init_hwc_display(output: &Output) -> Result<HwcDisplay> {
    let (width, height) = get_display_dimensions();
    info!("Initializing hwcomposer display: {}x{}", width, height);

    // Set EGL platform environment variable
    std::env::set_var("EGL_PLATFORM", "hwcomposer");

    // Create present callback data
    let frame_ready = Rc::new(AtomicBool::new(true));
    let callback_data = Box::new(PresentCallbackData {
        frame_ready: frame_ready.clone(),
    });
    let callback_data_ptr = Box::into_raw(callback_data) as *mut c_void;

    // Create HWC native window
    let native_window = unsafe {
        HwcNativeWindow::new(
            width,
            height,
            hal_format::HAL_PIXEL_FORMAT_RGBA_8888,
            Some(present_callback),
            callback_data_ptr,
        )
    }.ok_or_else(|| anyhow::anyhow!("Failed to create HWC native window"))?;

    // Set triple buffering
    if let Err(e) = native_window.set_buffer_count(3) {
        warn!("Failed to set buffer count: {}", e);
    }

    info!("Created HWC native window");

    // Load EGL dynamically
    let egl = unsafe { egl::DynamicInstance::<egl::EGL1_4>::load_required() }
        .map_err(|e| anyhow::anyhow!("Failed to load EGL: {:?}", e))?;

    info!("Loaded EGL library");

    // Get EGL display (will use hwcomposer platform due to EGL_PLATFORM env var)
    let egl_display = unsafe { egl.get_display(egl::DEFAULT_DISPLAY) }
        .ok_or_else(|| anyhow::anyhow!("Failed to get EGL display"))?;

    info!("Got EGL display");

    // Initialize EGL
    let (major, minor) = egl.initialize(egl_display)
        .map_err(|e| anyhow::anyhow!("Failed to initialize EGL: {:?}", e))?;

    info!("EGL initialized: {}.{}", major, minor);

    // Choose EGL config
    let config_attribs = [
        egl::RED_SIZE, 8,
        egl::GREEN_SIZE, 8,
        egl::BLUE_SIZE, 8,
        egl::ALPHA_SIZE, 8,
        egl::DEPTH_SIZE, 0,
        egl::STENCIL_SIZE, 0,
        egl::RENDERABLE_TYPE, egl::OPENGL_ES2_BIT,
        egl::SURFACE_TYPE, egl::WINDOW_BIT,
        egl::NONE,
    ];

    let config = egl.choose_first_config(egl_display, &config_attribs)
        .map_err(|e| anyhow::anyhow!("Failed to choose EGL config: {:?}", e))?
        .ok_or_else(|| anyhow::anyhow!("No suitable EGL config found"))?;

    info!("Chose EGL config");

    // Create EGL context
    let context_attribs = [
        egl::CONTEXT_CLIENT_VERSION, 2,
        egl::NONE,
    ];

    let egl_context = egl.create_context(egl_display, config, None, &context_attribs)
        .map_err(|e| anyhow::anyhow!("Failed to create EGL context: {:?}", e))?;

    info!("Created EGL context");

    // Create EGL surface from native window
    let surface_attribs = [egl::NONE];

    let egl_surface = unsafe {
        egl.create_window_surface(
            egl_display,
            config,
            native_window.as_ptr() as egl::NativeWindowType,
            Some(&surface_attribs),
        )
    }.map_err(|e| anyhow::anyhow!("Failed to create EGL surface: {:?}", e))?;

    info!("Created EGL surface");

    // Make context current
    egl.make_current(egl_display, Some(egl_surface), Some(egl_surface), Some(egl_context))
        .map_err(|e| anyhow::anyhow!("Failed to make EGL context current: {:?}", e))?;

    info!("Made EGL context current");

    // Initialize GL function pointers
    unsafe { gl::init(); }

    // For now, skip Smithay's renderer and use direct OpenGL rendering
    // This is a proof-of-concept to verify hwcomposer works
    // Later we can properly integrate with Smithay's rendering pipeline

    info!("HWComposer display initialized successfully");

    Ok(HwcDisplay {
        native_window,
        egl_instance: egl,
        egl_display,
        egl_surface,
        egl_context,
        width,
        height,
    })
}

/// Handle input events from libinput
fn handle_input_event(
    state: &mut Flick,
    event: InputEvent<LibinputInputBackend>,
    _session: &Rc<RefCell<LibSeatSession>>,
    modifiers: &Rc<RefCell<ModifierState>>,
) {
    use smithay::backend::input::{
        Event, KeyboardKeyEvent, PointerMotionEvent, PointerButtonEvent,
    };
    use smithay::input::keyboard::FilterResult;

    match event {
        InputEvent::Keyboard { event } => {
            use smithay::backend::input::KeyState;

            let keycode = event.key_code();
            let raw_keycode: u32 = keycode.raw();
            let key_state = event.state();
            let pressed = key_state == KeyState::Pressed;

            // Smithay Keycode.raw() returns XKB keycodes (evdev + 8)
            // Subtract 8 to get the raw evdev keycode
            let evdev_keycode = raw_keycode.saturating_sub(8);
            debug!("Keyboard event: evdev_keycode={}, pressed={}", evdev_keycode, pressed);

            // Track modifier state
            // Evdev keycodes: 29=LCtrl, 97=RCtrl, 56=LAlt, 100=RAlt, 42=LShift, 54=RShift, 125=LSuper, 126=RSuper
            {
                let mut mods = modifiers.borrow_mut();
                match evdev_keycode {
                    29 | 97 => mods.ctrl = pressed,
                    56 | 100 => mods.alt = pressed,
                    42 | 54 => mods.shift = pressed,
                    125 | 126 => mods.super_key = pressed,
                    _ => {}
                }
            }

            let serial = smithay::utils::SERIAL_COUNTER.next_serial();
            let time = event.time_msec();

            if let Some(keyboard) = state.seat.get_keyboard() {
                keyboard.input::<(), _>(
                    state,
                    keycode,
                    key_state,
                    serial,
                    time,
                    |_, _, _| FilterResult::Forward,
                );
            }
        }

        InputEvent::PointerMotion { event } => {
            use smithay::backend::input::PointerMotionEvent;

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
                pointer_pos.x = pointer_pos.x.max(0.0).min(screen.w as f64);
                pointer_pos.y = pointer_pos.y.max(0.0).min(screen.h as f64);

                // No focus tracking for now - mobile is touch-focused
                let focus = None;

                pointer.motion(
                    state,
                    focus,
                    &smithay::input::pointer::MotionEvent {
                        location: pointer_pos,
                        serial,
                        time: event.time_msec(),
                    },
                );
            }
        }

        InputEvent::PointerButton { event } => {
            let serial = smithay::utils::SERIAL_COUNTER.next_serial();
            let button = event.button_code();
            let button_state = event.state();

            let pointer = state.seat.get_pointer().unwrap();
            pointer.button(
                state,
                &smithay::input::pointer::ButtonEvent {
                    button,
                    state: button_state.into(),
                    serial,
                    time: event.time_msec(),
                },
            );
        }

        InputEvent::TouchDown { event } => {
            use smithay::backend::input::{TouchEvent, AbsolutePositionEvent};
            use smithay::utils::Point;

            let slot_id: i32 = event.slot().into();
            let position = event.position_transformed(state.screen_size);
            let touch_pos = Point::from((position.x, position.y));

            if let Some(gesture_event) = state.gesture_recognizer.touch_down(slot_id, touch_pos) {
                debug!("Gesture touch_down: {:?}", gesture_event);
            }
        }

        InputEvent::TouchMotion { event } => {
            use smithay::backend::input::{TouchEvent, AbsolutePositionEvent};
            use smithay::utils::Point;

            let slot_id: i32 = event.slot().into();
            let position = event.position_transformed(state.screen_size);
            let touch_pos = Point::from((position.x, position.y));

            if let Some(gesture_event) = state.gesture_recognizer.touch_motion(slot_id, touch_pos) {
                debug!("Gesture touch_motion: {:?}", gesture_event);
            }
        }

        InputEvent::TouchUp { event } => {
            use smithay::backend::input::TouchEvent;

            let slot_id: i32 = event.slot().into();

            if let Some(gesture_event) = state.gesture_recognizer.touch_up(slot_id) {
                debug!("Gesture touch_up: {:?}", gesture_event);
            }
        }

        _ => {}
    }
}

pub fn run() -> Result<()> {
    info!("Starting hwcomposer backend");

    // Set EGL platform
    std::env::set_var("EGL_PLATFORM", "hwcomposer");

    // Create event loop
    let mut event_loop: EventLoop<Flick> = EventLoop::try_new()?;
    let loop_handle = event_loop.handle();

    // Initialize libseat session
    let (session, notifier) = LibSeatSession::new()
        .map_err(|e| anyhow::anyhow!("Failed to create session: {:?}", e))?;

    let session = Rc::new(RefCell::new(session));
    info!("Session created, seat: {}", session.borrow().seat());

    // Initialize libinput
    let libinput_session = LibinputSessionInterface::from(session.borrow().clone());
    let mut libinput_context = Libinput::new_with_udev(libinput_session);
    libinput_context.udev_assign_seat(&session.borrow().seat()).unwrap();

    let libinput_backend = LibinputInputBackend::new(libinput_context.clone());

    // Create Wayland display
    let display: Display<Flick> = Display::new()?;

    // Get display dimensions
    let (width, height) = get_display_dimensions();
    let screen_size = (width as i32, height as i32).into();

    let mut state = Flick::new(display, loop_handle.clone(), screen_size);

    info!("Wayland socket: {:?}", state.socket_name);
    std::env::set_var("WAYLAND_DISPLAY", &state.socket_name);

    // Create Wayland output
    let output = Output::new(
        "hwcomposer-0".to_string(),
        PhysicalProperties {
            size: (0, 0).into(),
            subpixel: Subpixel::Unknown,
            make: "Flick".to_string(),
            model: "HWComposer".to_string(),
            serial_number: "Unknown".to_string(),
        },
    );

    let mode = Mode {
        size: (width as i32, height as i32).into(),
        refresh: 60_000,
    };

    output.change_current_state(
        Some(mode),
        Some(Transform::Normal),
        None,
        Some((0, 0).into()),
    );
    output.set_preferred(mode);

    output.create_global::<Flick>(&state.display_handle);
    state.space.map_output(&output, (0, 0));
    state.outputs.push(output.clone());

    info!("Output registered: {}x{}", width, height);

    // Initialize hwcomposer display
    let mut hwc_display = init_hwc_display(&output)?;

    // Update state with actual screen size
    state.screen_size = (width as i32, height as i32).into();
    state.gesture_recognizer.screen_size = state.screen_size;
    state.shell.screen_size = state.screen_size;
    state.shell.quick_settings.screen_size = state.screen_size;

    if let Some(ref mut slint_ui) = state.shell.slint_ui {
        slint_ui.set_size(state.screen_size);
    }

    // Launch lock screen if configured
    if state.shell.lock_screen_active {
        info!("Lock screen configured - launching on startup");
        if let Some(socket) = state.socket_name.to_str() {
            state.shell.launch_lock_screen_app(socket);
        }
    }

    // Track session state
    let session_active = Rc::new(RefCell::new(true));
    let session_active_for_notifier = session_active.clone();

    let modifiers = Rc::new(RefCell::new(ModifierState::default()));
    let modifiers_for_notifier = modifiers.clone();

    // Add session notifier
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

    // Add libinput to event loop
    let session_for_input = session.clone();
    let modifiers_for_input = modifiers.clone();

    loop_handle
        .insert_source(libinput_backend, move |event, _, state| {
            handle_input_event(state, event, &session_for_input, &modifiers_for_input);
        })
        .map_err(|e| anyhow::anyhow!("Failed to insert input source: {:?}", e))?;

    // Add render timer (60fps target)
    let render_timer = Timer::immediate();
    loop_handle
        .insert_source(render_timer, move |_, _, _| {
            TimeoutAction::ToDuration(Duration::from_millis(16))
        })
        .map_err(|e| anyhow::anyhow!("Failed to insert render timer: {:?}", e))?;

    info!("Entering event loop");

    // Main event loop
    loop {
        // Process Wayland events
        state.display_handle.flush_clients().ok();

        // Dispatch calloop events
        event_loop
            .dispatch(Some(Duration::from_millis(1)), &mut state)
            .map_err(|e| anyhow::anyhow!("Event loop error: {:?}", e))?;

        // Skip rendering if session not active
        if !*session_active.borrow() {
            continue;
        }

        // Render frame
        if let Err(e) = render_frame(&mut hwc_display, &state, &output) {
            error!("Render error: {:?}", e);
        }
    }
}

/// Render a frame to the hwcomposer display
fn render_frame(
    display: &mut HwcDisplay,
    state: &Flick,
    _output: &Output,
) -> Result<()> {
    // Make our EGL context current
    display.egl_instance.make_current(
        display.egl_display,
        Some(display.egl_surface),
        Some(display.egl_surface),
        Some(display.egl_context),
    ).map_err(|e| anyhow::anyhow!("Failed to make context current: {:?}", e))?;

    // Determine background color based on shell view
    let shell_view = state.shell.view;
    let bg_color = match shell_view {
        ShellView::Home | ShellView::QuickSettings | ShellView::PickDefault => [0.1, 0.1, 0.15, 1.0],
        ShellView::Switcher => [0.05, 0.05, 0.08, 1.0],
        ShellView::App | ShellView::LockScreen => [0.0, 0.0, 0.0, 1.0],
    };

    // Clear screen with background color using raw GL
    unsafe {
        gl::ClearColor(bg_color[0], bg_color[1], bg_color[2], bg_color[3]);
        gl::Clear(gl::COLOR_BUFFER_BIT);
    }

    // TODO: Add full rendering logic here
    // For now, just swap buffers to verify the pipeline works

    // Swap buffers
    display.egl_instance.swap_buffers(display.egl_display, display.egl_surface)
        .map_err(|e| anyhow::anyhow!("Failed to swap buffers: {:?}", e))?;

    Ok(())
}

// OpenGL ES function types and constants
mod gl {
    use std::os::raw::c_void;

    pub const COLOR_BUFFER_BIT: u32 = 0x00004000;

    // Function pointer types
    type GlClearColorFn = unsafe extern "C" fn(f32, f32, f32, f32);
    type GlClearFn = unsafe extern "C" fn(u32);

    // Cached function pointers
    static mut GL_CLEAR_COLOR: Option<GlClearColorFn> = None;
    static mut GL_CLEAR: Option<GlClearFn> = None;
    static mut INITIALIZED: bool = false;

    /// Initialize GL function pointers using libGLESv2
    pub unsafe fn init() {
        if INITIALIZED {
            return;
        }

        // Load libGLESv2
        let lib = libc::dlopen(
            b"libGLESv2.so.2\0".as_ptr() as *const _,
            libc::RTLD_NOW | libc::RTLD_GLOBAL,
        );
        if lib.is_null() {
            // Try alternate name
            let lib = libc::dlopen(
                b"libGLESv2.so\0".as_ptr() as *const _,
                libc::RTLD_NOW | libc::RTLD_GLOBAL,
            );
            if lib.is_null() {
                tracing::error!("Failed to load libGLESv2");
                return;
            }
        }

        // Load glClearColor
        let clear_color = libc::dlsym(lib, b"glClearColor\0".as_ptr() as *const _);
        if !clear_color.is_null() {
            GL_CLEAR_COLOR = Some(std::mem::transmute::<*mut c_void, GlClearColorFn>(clear_color));
        }

        // Load glClear
        let clear = libc::dlsym(lib, b"glClear\0".as_ptr() as *const _);
        if !clear.is_null() {
            GL_CLEAR = Some(std::mem::transmute::<*mut c_void, GlClearFn>(clear));
        }

        INITIALIZED = true;
        tracing::info!("OpenGL ES functions loaded");
    }

    pub unsafe fn ClearColor(r: f32, g: f32, b: f32, a: f32) {
        if let Some(func) = GL_CLEAR_COLOR {
            func(r, g, b, a);
        }
    }

    pub unsafe fn Clear(mask: u32) {
        if let Some(func) = GL_CLEAR {
            func(mask);
        }
    }
}
