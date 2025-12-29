//! Hwcomposer backend for Droidian/libhybris devices
//!
//! This backend runs on Android-based Linux distributions (Droidian, UBports, etc.)
//! that use libhybris to access Android's hwcomposer HAL for graphics.
//!
//! Uses our C shim library (libflick_hwc) which handles:
//! - gralloc initialization
//! - HWC2 device/display/layer setup
//! - Native window creation
//! - Frame presentation via hwcomposer
//!
//! Environment variables:
//! - EGL_PLATFORM=hwcomposer (set automatically by shim)
//! - FLICK_DISPLAY_WIDTH / FLICK_DISPLAY_HEIGHT (optional, override display size)

use std::{
    cell::RefCell,
    rc::Rc,
    time::Duration,
};

use anyhow::Result;
use tracing::{debug, error, info, warn};

use smithay::{
    backend::{
        allocator::{
            dmabuf::Dmabuf,
            Buffer, Format, Fourcc, Modifier,
        },
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
        wayland_server::{Display, Resource},
    },
    utils::Transform,
    wayland::compositor,
    wayland::dmabuf::{DmabufFeedbackBuilder, get_dmabuf},
    wayland::xwayland_shell::XWaylandShellState,
    xwayland::{XWayland, XWaylandEvent, xwm::X11Wm},
};

use crate::state::Flick;
use crate::shell::ShellView;
use smithay::input::keyboard::FilterResult;

/// Convert a character to evdev keycode and shift state
fn char_to_evdev(c: char) -> Option<(u32, bool)> {
    let (keycode, shift) = match c {
        // Numbers (row 1)
        '1' => (2, false),  '!' => (2, true),
        '2' => (3, false),  '@' => (3, true),
        '3' => (4, false),  '#' => (4, true),
        '4' => (5, false),  '$' => (5, true),
        '5' => (6, false),  '%' => (6, true),
        '6' => (7, false),  '^' => (7, true),
        '7' => (8, false),  '&' => (8, true),
        '8' => (9, false),  '*' => (9, true),
        '9' => (10, false), '(' => (10, true),
        '0' => (11, false), ')' => (11, true),
        '-' => (12, false), '_' => (12, true),
        '=' => (13, false), '+' => (13, true),

        // Row 2: qwertyuiop
        'q' => (16, false), 'Q' => (16, true),
        'w' => (17, false), 'W' => (17, true),
        'e' => (18, false), 'E' => (18, true),
        'r' => (19, false), 'R' => (19, true),
        't' => (20, false), 'T' => (20, true),
        'y' => (21, false), 'Y' => (21, true),
        'u' => (22, false), 'U' => (22, true),
        'i' => (23, false), 'I' => (23, true),
        'o' => (24, false), 'O' => (24, true),
        'p' => (25, false), 'P' => (25, true),
        '[' => (26, false), '{' => (26, true),
        ']' => (27, false), '}' => (27, true),
        '\\' => (43, false), '|' => (43, true),

        // Row 3: asdfghjkl
        'a' => (30, false), 'A' => (30, true),
        's' => (31, false), 'S' => (31, true),
        'd' => (32, false), 'D' => (32, true),
        'f' => (33, false), 'F' => (33, true),
        'g' => (34, false), 'G' => (34, true),
        'h' => (35, false), 'H' => (35, true),
        'j' => (36, false), 'J' => (36, true),
        'k' => (37, false), 'K' => (37, true),
        'l' => (38, false), 'L' => (38, true),
        ';' => (39, false), ':' => (39, true),
        '\'' => (40, false), '"' => (40, true),
        '`' => (41, false), '~' => (41, true),

        // Row 4: zxcvbnm
        'z' => (44, false), 'Z' => (44, true),
        'x' => (45, false), 'X' => (45, true),
        'c' => (46, false), 'C' => (46, true),
        'v' => (47, false), 'V' => (47, true),
        'b' => (48, false), 'B' => (48, true),
        'n' => (49, false), 'N' => (49, true),
        'm' => (50, false), 'M' => (50, true),
        ',' => (51, false), '<' => (51, true),
        '.' => (52, false), '>' => (52, true),
        '/' => (53, false), '?' => (53, true),

        // Space
        ' ' => (57, false),

        _ => return None,
    };
    Some((keycode, shift))
}

// Use our C shim FFI bindings
use super::hwc_shim_ffi::{HwcContext, FlickDisplayInfo};


// Re-use khronos-egl for raw EGL access
use khronos_egl as egl;

// EGL extension constants for wayland buffer import
const EGL_WAYLAND_BUFFER_WL: u32 = 0x31D5;
const EGL_TEXTURE_FORMAT: u32 = 0x3080;
const EGL_TEXTURE_RGB: u32 = 0x305D;
const EGL_TEXTURE_RGBA: u32 = 0x305E;
const EGL_TEXTURE_EXTERNAL_WL: u32 = 0x31DA;
const EGL_TEXTURE_Y_U_V_WL: u32 = 0x31D7;
const EGL_TEXTURE_Y_UV_WL: u32 = 0x31D8;
const EGL_TEXTURE_Y_XUXV_WL: u32 = 0x31D9;
const EGL_WIDTH: u32 = 0x3057;
const EGL_HEIGHT: u32 = 0x3056;

// EGL image types
type EGLImageKHR = *mut std::ffi::c_void;
const EGL_NO_IMAGE_KHR: EGLImageKHR = std::ptr::null_mut();

// EGL extension function types
type EglQueryWaylandBufferWL = unsafe extern "C" fn(
    dpy: *mut std::ffi::c_void,
    buffer: *mut std::ffi::c_void,
    attribute: i32,
    value: *mut i32,
) -> u32;

type EglCreateImageKHR = unsafe extern "C" fn(
    dpy: *mut std::ffi::c_void,
    ctx: *mut std::ffi::c_void,
    target: u32,
    buffer: *mut std::ffi::c_void,
    attrib_list: *const i32,
) -> EGLImageKHR;

type EglDestroyImageKHR = unsafe extern "C" fn(
    dpy: *mut std::ffi::c_void,
    image: EGLImageKHR,
) -> u32;

type GlEGLImageTargetTexture2DOES = unsafe extern "C" fn(
    target: u32,
    image: EGLImageKHR,
);

/// Imported EGL buffer for wayland clients
#[derive(Debug)]
struct ImportedEglBuffer {
    /// OpenGL texture ID
    texture_id: u32,
    /// EGL image handle (for cleanup)
    egl_image: EGLImageKHR,
    /// Buffer width
    width: u32,
    /// Buffer height
    height: u32,
}

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
///
/// Now uses our C shim which handles all HWC2 complexity internally.
/// The shim's present_callback is invoked by eglSwapBuffers to submit
/// frames to hwcomposer.
struct HwcDisplay {
    /// C shim context (handles HWC2 device/display/layer internally)
    hwc_ctx: HwcContext,
    /// EGL instance
    egl_instance: egl::DynamicInstance<egl::EGL1_4>,
    /// EGL display
    egl_display: egl::Display,
    /// EGL surface (created from native window)
    egl_surface: egl::Surface,
    /// EGL context
    egl_context: egl::Context,
    /// Display width in pixels
    width: u32,
    /// Display height in pixels
    height: u32,
    /// EGL extension: query wayland buffer attributes
    egl_query_wayland_buffer: Option<EglQueryWaylandBufferWL>,
    /// EGL extension: create EGL image from buffer
    egl_create_image: Option<EglCreateImageKHR>,
    /// EGL extension: destroy EGL image
    egl_destroy_image: Option<EglDestroyImageKHR>,
    /// GL extension: bind EGL image to texture
    gl_egl_image_target_texture_2d: Option<GlEGLImageTargetTexture2DOES>,
}

impl Drop for HwcDisplay {
    fn drop(&mut self) {
        info!("HwcDisplay cleanup: destroying EGL resources");

        // Make EGL context not current before destroying
        let _ = self.egl_instance.make_current(
            self.egl_display,
            None, // No draw surface
            None, // No read surface
            None, // No context
        );

        // Destroy EGL surface
        if let Err(e) = self.egl_instance.destroy_surface(self.egl_display, self.egl_surface) {
            warn!("Failed to destroy EGL surface: {:?}", e);
        }

        // Destroy EGL context
        if let Err(e) = self.egl_instance.destroy_context(self.egl_display, self.egl_context) {
            warn!("Failed to destroy EGL context: {:?}", e);
        }

        // Terminate EGL display
        if let Err(e) = self.egl_instance.terminate(self.egl_display) {
            warn!("Failed to terminate EGL display: {:?}", e);
        }

        // HWC2 cleanup is handled by HwcContext Drop
        // (which calls flick_hwc_destroy)
        info!("HwcDisplay cleanup complete");
    }
}

// All HWC2 callbacks, present logic, and buffer management are now handled
// by our C shim (libflick_hwc). The shim's present_callback is invoked
// automatically by eglSwapBuffers.

/// Get display dimensions from environment or system (fallback before shim init)
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

    // Default
    info!("Using default display size: 1080x2340");
    (1080, 2340)
}

/// Initialize EGL and hwcomposer display using the C shim
fn init_hwc_display(_output: &Output) -> Result<HwcDisplay> {
    info!("Initializing hwcomposer display via C shim");

    // Initialize hwcomposer via our C shim
    // This handles: gralloc init, HWC2 device/display/layer, native window
    let hwc_ctx = HwcContext::new()
        .map_err(|e| anyhow::anyhow!("Failed to initialize hwcomposer shim: {}", e))?;

    // Get display info from the shim
    let display_info = hwc_ctx.get_display_info()
        .map_err(|e| anyhow::anyhow!("Failed to get display info: {}", e))?;

    let width = display_info.width as u32;
    let height = display_info.height as u32;
    info!("Display: {}x{} @ {:.1}Hz, DPI: {:.1}x{:.1}",
          width, height, display_info.refresh_rate,
          display_info.dpi_x, display_info.dpi_y);

    // Get native window from shim
    let native_window = hwc_ctx.get_native_window();
    if native_window.is_null() {
        return Err(anyhow::anyhow!("Shim returned null native window"));
    }

    // Load EGL dynamically
    let egl = unsafe { egl::DynamicInstance::<egl::EGL1_4>::load_required() }
        .map_err(|e| anyhow::anyhow!("Failed to load EGL: {:?}", e))?;
    info!("Loaded EGL library");

    // Get EGL display (shim sets EGL_PLATFORM=hwcomposer)
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
            native_window as egl::NativeWindowType,
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

    // Load EGL extension functions for wayland buffer import
    let egl_query_wayland_buffer: Option<EglQueryWaylandBufferWL> = unsafe {
        let ptr = egl.get_proc_address("eglQueryWaylandBufferWL");
        ptr.map(|p| std::mem::transmute(p))
    };
    if egl_query_wayland_buffer.is_some() {
        info!("Loaded eglQueryWaylandBufferWL extension");
    } else {
        warn!("eglQueryWaylandBufferWL not available - camera preview may not work");
    }

    let egl_create_image: Option<EglCreateImageKHR> = unsafe {
        let ptr = egl.get_proc_address("eglCreateImageKHR");
        ptr.map(|p| std::mem::transmute(p))
    };
    if egl_create_image.is_some() {
        info!("Loaded eglCreateImageKHR extension");
    } else {
        warn!("eglCreateImageKHR not available");
    }

    let egl_destroy_image: Option<EglDestroyImageKHR> = unsafe {
        let ptr = egl.get_proc_address("eglDestroyImageKHR");
        ptr.map(|p| std::mem::transmute(p))
    };
    if egl_destroy_image.is_some() {
        info!("Loaded eglDestroyImageKHR extension");
    }

    // Load GL extension for EGL image to texture
    let gl_egl_image_target_texture_2d: Option<GlEGLImageTargetTexture2DOES> = unsafe {
        let ptr = egl.get_proc_address("glEGLImageTargetTexture2DOES");
        ptr.map(|p| std::mem::transmute(p))
    };
    if gl_egl_image_target_texture_2d.is_some() {
        info!("Loaded glEGLImageTargetTexture2DOES extension");
    } else {
        warn!("glEGLImageTargetTexture2DOES not available");
    }

    info!("HWComposer display initialized successfully via shim");

    Ok(HwcDisplay {
        hwc_ctx,
        egl_instance: egl,
        egl_display,
        egl_surface,
        egl_context,
        width,
        height,
        egl_query_wayland_buffer,
        egl_create_image,
        egl_destroy_image,
        gl_egl_image_target_texture_2d,
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

    // Log all input events (brief)
    info!("INPUT EVENT: {:?}", std::mem::discriminant(&event));
    match &event {
        InputEvent::DeviceAdded { device } => {
            use smithay::backend::input::Device;
            info!("INPUT: DeviceAdded: {:?}", device.name());
        }
        InputEvent::DeviceRemoved { device } => {
            info!("INPUT: DeviceRemoved: {:?}", device.name());
        }
        InputEvent::TouchDown { .. } => info!("INPUT: TouchDown"),
        InputEvent::TouchUp { .. } => info!("INPUT: TouchUp"),
        InputEvent::TouchMotion { .. } => {} // too spammy
        InputEvent::Keyboard { ref event } => {
            use smithay::backend::input::KeyboardKeyEvent;
            info!("INPUT: Keyboard key={} state={:?}", event.key_code().raw(), event.state());
        }
        _ => {}
    }

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
            info!("Keyboard event: raw={}, evdev={}, pressed={}", raw_keycode, evdev_keycode, pressed);

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

            // Update last activity time for auto-lock
            state.last_activity = std::time::Instant::now();

            // Volume buttons (evdev keycodes: 114=down, 115=up)
            if evdev_keycode == 115 && pressed {
                info!("Volume up pressed");
                state.system.volume_up();
                state.system.haptic_tap();
                info!("Volume now: {}%", state.system.volume);
            }
            if evdev_keycode == 114 && pressed {
                info!("Volume down pressed");
                state.system.volume_down();
                state.system.haptic_tap();
                info!("Volume now: {}%", state.system.volume);
            }

            // KEY_WAKEUP (evdev keycode 143) - wake blanked screen
            // This is generated by hardware touch-to-wake sensors
            if evdev_keycode == 143 && pressed {
                if state.shell.lock_screen_active && (state.shell.display_blanked || state.shell.lock_screen_dimmed) {
                    info!("KEY_WAKEUP received, waking lock screen");
                    state.shell.wake_lock_screen();
                }
                return;
            }

            // Power button (evdev keycode 116) - toggle blank/wake on lock screen, or lock
            if evdev_keycode == 116 && pressed {
                if state.shell.lock_screen_active {
                    if state.shell.display_blanked || state.shell.lock_screen_dimmed {
                        // Wake the blanked/dimmed lock screen
                        info!("Power button pressed, waking lock screen");
                        state.shell.wake_lock_screen();
                    } else {
                        // Blank the display immediately (skip dimming)
                        info!("Power button pressed, blanking display");
                        state.shell.lock_screen_dimmed = true;
                        state.shell.display_blanked = true;
                    }
                } else {
                    // Lock the screen and blank display
                    info!("Power button pressed, locking screen");
                    state.shell.lock();
                    state.shell.lock_screen_dimmed = true;
                    state.shell.display_blanked = true;
                    // Launch lock screen app
                    if let Some(socket) = state.socket_name.to_str() {
                        state.shell.launch_lock_screen_app(socket);
                    }
                }
                return;
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
            // Get raw position (in physical display coordinates)
            let raw_position = event.position();
            let touch_pos = Point::from((raw_position.x, raw_position.y));

            // Update last activity time for auto-lock
            state.last_activity = std::time::Instant::now();

            // If lock screen is active, handle touch
            if state.shell.lock_screen_active {
                if state.shell.display_blanked || state.shell.lock_screen_dimmed {
                    // Require double-tap to wake blanked/dimmed screen
                    const DOUBLE_TAP_MS: u128 = 600; // Max time between taps
                    let now = std::time::Instant::now();
                    if let Some(last_tap) = state.shell.lock_screen_last_tap {
                        if now.duration_since(last_tap).as_millis() < DOUBLE_TAP_MS {
                            // Double tap detected - wake screen
                            info!("Double-tap detected, waking lock screen");
                            state.system.haptic_click();
                            state.shell.wake_lock_screen();
                            state.shell.lock_screen_last_tap = None;
                        } else {
                            // Too slow, start new tap sequence
                            state.shell.lock_screen_last_tap = Some(now);
                        }
                    } else {
                        // First tap
                        state.shell.lock_screen_last_tap = Some(now);
                    }
                } else {
                    // Not dimmed/blanked - reset activity timer
                    state.shell.reset_lock_screen_activity();
                }
            }

            // Track touch position
            state.last_touch_pos.insert(slot_id, touch_pos);

            // Create touch effect (ripple) at touch position
            state.add_touch_effect(touch_pos.x, touch_pos.y, slot_id as u64);

            // Forward to gesture recognizer
            if let Some(gesture_event) = state.gesture_recognizer.touch_down(slot_id, touch_pos) {
                debug!("Gesture touch_down: {:?}", gesture_event);

                // Handle edge swipe start for quick settings, app switcher, and home/close gestures
                if let crate::input::GestureEvent::EdgeSwipeStart { edge, .. } = &gesture_event {
                    let shell_view = state.shell.view;

                    // Cancel any pending touch sequences immediately when edge gesture starts
                    // This prevents the app from having a "stuck" touch when gesture is recognized
                    if shell_view == crate::shell::ShellView::App {
                        if let Some(touch) = state.seat.get_touch() {
                            touch.cancel(state);
                            info!("Edge gesture started: cancelled pending touch sequences");
                        }
                    }

                    // Left edge = Quick Settings (blocked on lock screen)
                    if *edge == crate::input::Edge::Left && shell_view != crate::shell::ShellView::LockScreen {
                        state.qs_gesture_active = true;
                        state.qs_gesture_progress = 0.0;
                        info!("QS gesture STARTED");
                    }
                    // Right edge = App Switcher (blocked on lock screen)
                    if *edge == crate::input::Edge::Right && shell_view != crate::shell::ShellView::LockScreen {
                        state.switcher_gesture_active = true;
                        state.switcher_gesture_progress = 0.0;
                        info!("Switcher gesture STARTED");
                    }
                    // Bottom edge = Home gesture (swipe up from bottom)
                    if *edge == crate::input::Edge::Bottom && shell_view != crate::shell::ShellView::LockScreen {
                        state.start_home_gesture();
                        info!("Home gesture STARTED");
                    }
                    // Top edge = Close gesture (swipe down from top) - only in App view
                    if *edge == crate::input::Edge::Top && shell_view == crate::shell::ShellView::App {
                        state.start_close_gesture();
                        info!("Close gesture STARTED");
                    }
                }
            }

            // Check if QML lockscreen is connected (has windows in space)
            let has_wayland_window = state.space.elements().count() > 0;
            let shell_view = state.shell.view;
            info!("TouchDown: shell_view={:?}, has_wayland_window={}", shell_view, has_wayland_window);

            // Check if touch is on keyboard overlay (in App or LockScreen view with keyboard visible)
            let touch_on_keyboard = if shell_view == crate::shell::ShellView::App || shell_view == crate::shell::ShellView::LockScreen {
                if let Some(ref slint_ui) = state.shell.slint_ui {
                    if slint_ui.is_keyboard_visible() {
                        // Keyboard is ~22% of screen height at the bottom
                        let screen_height = state.screen_size.h as f64;
                        let keyboard_height = (screen_height * 0.22).max(200.0);
                        let keyboard_top = screen_height - keyboard_height;
                        touch_pos.y >= keyboard_top
                    } else {
                        false
                    }
                } else {
                    false
                }
            } else {
                false
            };

            // Forward touch to Wayland client if connected (but not if touching keyboard)
            // Forward to QML lock screen when on lock screen, or to apps when not locked
            // Don't forward while an edge gesture is active (touch was cancelled)
            let gesture_active = state.switcher_gesture_active || state.qs_gesture_active ||
                                 state.home_gesture_window.is_some() || state.close_gesture_window.is_some();
            let forward_to_wayland = has_wayland_window && !touch_on_keyboard && !gesture_active &&
                (shell_view == crate::shell::ShellView::App && !state.shell.lock_screen_active ||
                 shell_view == crate::shell::ShellView::LockScreen);
            if forward_to_wayland {
                if let Some(touch) = state.seat.get_touch() {
                    let serial = smithay::utils::SERIAL_COUNTER.next_serial();

                    // Debug: log all windows in the space
                    let element_count = state.space.elements().count();
                    info!("TouchDown: {} windows in space", element_count);
                    for (i, window) in state.space.elements().enumerate() {
                        let is_wayland = window.toplevel().is_some();
                        let is_x11 = window.x11_surface().is_some();
                        let (surface_id, client_info) = if let Some(toplevel) = window.toplevel() {
                            let surface = toplevel.wl_surface();
                            let id = format!("{:?}", surface.id());
                            let client = surface.client().map(|c| format!("{:?}", c.id())).unwrap_or_else(|| "no-client".to_string());
                            (id, client)
                        } else if let Some(x11) = window.x11_surface() {
                            if let Some(s) = x11.wl_surface() {
                                let id = format!("{:?}", s.id());
                                let client = s.client().map(|c| format!("{:?}", c.id())).unwrap_or_else(|| "no-client".to_string());
                                (id, client)
                            } else {
                                ("no-surface".to_string(), "no-client".to_string())
                            }
                        } else {
                            ("no-surface".to_string(), "no-client".to_string())
                        };
                        info!("  Window {}: {} (client: {}), wayland={}, x11={}",
                              i, surface_id, client_info, is_wayland, is_x11);
                    }

                    // ALWAYS use the topmost window from the space - this is the window
                    // that's actually being rendered on top. Don't rely on keyboard focus
                    // as it may not be synchronized with the space stacking order.
                    let topmost_surface = state.space.elements().last()
                        .and_then(|window| {
                            if let Some(toplevel) = window.toplevel() {
                                let surface = toplevel.wl_surface().clone();
                                let client_info = surface.client().map(|c| format!("{:?}", c.id())).unwrap_or_else(|| "no-client".to_string());
                                info!("TouchDown: Using SPACE TOPMOST surface {:?} (client: {})", surface.id(), client_info);
                                Some(surface)
                            } else if let Some(x11) = window.x11_surface() {
                                x11.wl_surface().map(|s| {
                                    let client_info = s.client().map(|c| format!("{:?}", c.id())).unwrap_or_else(|| "no-client".to_string());
                                    info!("TouchDown: Using SPACE TOPMOST X11 surface (client: {})", client_info);
                                    s.clone()
                                })
                            } else {
                                None
                            }
                        });

                    // Also log keyboard focus for comparison
                    if let Some(kb) = state.seat.get_keyboard() {
                        if let Some(kb_focus) = kb.current_focus() {
                            let kb_client = kb_focus.client().map(|c| format!("{:?}", c.id())).unwrap_or_else(|| "no-client".to_string());
                            info!("TouchDown: (keyboard focus is {:?}, client: {})", kb_focus.id(), kb_client);
                        } else {
                            info!("TouchDown: (keyboard focus is None)");
                        }
                    }

                    if topmost_surface.is_none() {
                        info!("TouchDown: WARNING - No topmost surface!");
                    }

                    // Use topmost surface for touch focus
                    let focus = topmost_surface
                        .map(|surface| (surface, smithay::utils::Point::from((0.0, 0.0))));

                    if focus.is_some() {
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
                    } else {
                        info!("TouchDown: No surface found for touch event");
                    }
                }
            } else {
                // Forward to Slint UI based on current view
                match shell_view {
                    crate::shell::ShellView::Home => {
                        // Hit test to find which category was touched
                        let touched_category = state.shell.hit_test_category(touch_pos);
                        let touched_index = state.shell.hit_test_category_index(touch_pos);

                        if state.shell.wiggle_mode {
                            // In wiggle mode - track for potential drag or tap to select app
                            if let Some(index) = touched_index {
                                info!("Wiggle mode: touch down on index {}", index);
                                state.shell.start_drag(index, touch_pos);
                            }
                        } else {
                            // Normal mode - track for app launching
                            if let Some(category) = touched_category {
                                info!("Touch down on category {:?}", category);
                                state.shell.start_category_touch(touch_pos, category);
                            } else {
                                // Not on a category - just track for scrolling
                                state.shell.start_home_touch(touch_pos.y, None);
                            }
                        }

                        // Forward to Slint for visual feedback
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.dispatch_pointer_pressed(touch_pos.x as f32, touch_pos.y as f32);
                        }
                    }
                    crate::shell::ShellView::QuickSettings => {
                        // Forward to Slint for quick settings
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.dispatch_pointer_pressed(touch_pos.x as f32, touch_pos.y as f32);
                        }
                    }
                    crate::shell::ShellView::Switcher => {
                        info!("Switcher TouchDown at ({}, {})", touch_pos.x, touch_pos.y);
                        // Start tracking horizontal scroll
                        state.shell.switcher_touch_start_x = Some(touch_pos.x);
                        state.shell.switcher_touch_last_x = Some(touch_pos.x);
                        state.shell.is_scrolling = false;

                        // Forward to Slint for app switcher window selection
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.dispatch_pointer_pressed(touch_pos.x as f32, touch_pos.y as f32);
                        }
                    }
                    crate::shell::ShellView::App => {
                        // Touch on keyboard overlay - track for swipe-down dismiss
                        if touch_on_keyboard {
                            info!("Keyboard TouchDown at ({}, {})", touch_pos.x, touch_pos.y);
                            // Start tracking for potential swipe-down to dismiss
                            state.keyboard_swipe_start_y = Some(touch_pos.y);
                            state.keyboard_swipe_active = false;
                            if let Some(ref slint_ui) = state.shell.slint_ui {
                                slint_ui.dispatch_pointer_pressed(touch_pos.x as f32, touch_pos.y as f32);
                            }
                        }
                    }
                    crate::shell::ShellView::PickDefault => {
                        // Forward to Slint for pick default app selection
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.dispatch_pointer_pressed(touch_pos.x as f32, touch_pos.y as f32);
                        }
                    }
                    _ => {}
                }
            }
        }

        InputEvent::TouchMotion { event } => {
            use smithay::backend::input::{TouchEvent, AbsolutePositionEvent};
            use smithay::utils::Point;

            let slot_id: i32 = event.slot().into();
            // Get raw position (in physical display coordinates)
            let raw_position = event.position();
            let touch_pos = Point::from((raw_position.x, raw_position.y));

            // Update tracked touch position
            state.last_touch_pos.insert(slot_id, touch_pos);

            // Update touch effect (adds ripples along swipe path)
            state.update_touch_effect(touch_pos.x, touch_pos.y, slot_id as u64);

            // Forward to gesture recognizer
            if let Some(gesture_event) = state.gesture_recognizer.touch_motion(slot_id, touch_pos) {
                debug!("Gesture touch_motion: {:?}", gesture_event);

                // Handle edge swipe start (when PotentialEdgeSwipe activates after min drag distance)
                if let crate::input::GestureEvent::EdgeSwipeStart { edge, .. } = &gesture_event {
                    let shell_view = state.shell.view;

                    // Cancel any pending touch sequences immediately when edge gesture starts
                    // This prevents the app from having a "stuck" touch when gesture is recognized
                    if shell_view == crate::shell::ShellView::App {
                        if let Some(touch) = state.seat.get_touch() {
                            touch.cancel(state);
                            info!("Edge gesture started (motion): cancelled pending touch sequences");
                        }
                    }

                    // Left edge = Quick Settings
                    if *edge == crate::input::Edge::Left && shell_view != crate::shell::ShellView::LockScreen {
                        state.qs_gesture_active = true;
                        state.qs_gesture_progress = 0.0;
                    }
                    // Right edge = App Switcher
                    if *edge == crate::input::Edge::Right && shell_view != crate::shell::ShellView::LockScreen {
                        state.switcher_gesture_active = true;
                        state.switcher_gesture_progress = 0.0;
                    }
                    // Bottom edge = Home gesture (swipe up)
                    if *edge == crate::input::Edge::Bottom && shell_view != crate::shell::ShellView::LockScreen {
                        state.start_home_gesture();
                    }
                    // Top edge = Close gesture (swipe down)
                    if *edge == crate::input::Edge::Top && shell_view == crate::shell::ShellView::App {
                        state.start_close_gesture();
                    }
                }

                // Handle edge swipe progress updates
                if let crate::input::GestureEvent::EdgeSwipeUpdate { edge, progress, .. } = &gesture_event {
                    let shell_view = state.shell.view;
                    // Left edge = Quick Settings
                    if *edge == crate::input::Edge::Left && shell_view != crate::shell::ShellView::LockScreen {
                        state.qs_gesture_active = true;
                        state.qs_gesture_progress = progress.clamp(0.0, 1.5);
                    }
                    // Right edge = App Switcher
                    if *edge == crate::input::Edge::Right && shell_view != crate::shell::ShellView::LockScreen {
                        state.switcher_gesture_active = true;
                        state.switcher_gesture_progress = progress.clamp(0.0, 1.0);
                    }
                    // Bottom edge = Home gesture (swipe up)
                    if *edge == crate::input::Edge::Bottom && shell_view != crate::shell::ShellView::LockScreen {
                        state.update_home_gesture(*progress);
                    }
                    // Top edge = Close gesture (swipe down)
                    if *edge == crate::input::Edge::Top && shell_view == crate::shell::ShellView::App {
                        state.update_close_gesture(*progress);
                    }
                }
            }

            // Check if QML lockscreen is connected
            let has_wayland_window = state.space.elements().count() > 0;
            let shell_view = state.shell.view;

            // Check if touch is on keyboard overlay (in App or LockScreen view with keyboard visible)
            let touch_on_keyboard = if shell_view == crate::shell::ShellView::App || shell_view == crate::shell::ShellView::LockScreen {
                if let Some(ref slint_ui) = state.shell.slint_ui {
                    if slint_ui.is_keyboard_visible() {
                        let screen_height = state.screen_size.h as f64;
                        let keyboard_height = (screen_height * 0.22).max(200.0);
                        let keyboard_top = screen_height - keyboard_height;
                        touch_pos.y >= keyboard_top
                    } else {
                        false
                    }
                } else {
                    false
                }
            } else {
                false
            };

            // Forward touch to Wayland client if connected (but not if touching keyboard)
            // Forward to QML lock screen when on lock screen, or to apps when not locked
            // Don't forward while an edge gesture is active (touch was cancelled)
            let gesture_active = state.switcher_gesture_active || state.qs_gesture_active ||
                                 state.home_gesture_window.is_some() || state.close_gesture_window.is_some();
            let forward_to_wayland = has_wayland_window && !touch_on_keyboard && !gesture_active &&
                (shell_view == crate::shell::ShellView::App && !state.shell.lock_screen_active ||
                 shell_view == crate::shell::ShellView::LockScreen);
            if forward_to_wayland {
                if let Some(touch) = state.seat.get_touch() {
                    // Use space topmost for touch motion - same source as touch down
                    let focus = state.space.elements().last()
                        .and_then(|window| {
                            if let Some(toplevel) = window.toplevel() {
                                Some((toplevel.wl_surface().clone(), smithay::utils::Point::from((0.0, 0.0))))
                            } else if let Some(x11) = window.x11_surface() {
                                x11.wl_surface().map(|s| (s.clone(), smithay::utils::Point::from((0.0, 0.0))))
                            } else {
                                None
                            }
                        });

                    if focus.is_some() {
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
            } else {
                // Forward to Slint UI based on current view
                match shell_view {
                    crate::shell::ShellView::Home => {
                        // Check for long press to enter wiggle mode
                        if !state.shell.wiggle_mode && !state.shell.is_scrolling {
                            if let Some(_category) = state.shell.check_long_press() {
                                info!("Long press detected - entering wiggle mode");
                                state.shell.enter_wiggle_mode();
                            }
                        }

                        // Update drag position in wiggle mode
                        if state.shell.wiggle_mode && state.shell.dragging_index.is_some() {
                            state.shell.update_drag(touch_pos);
                        }

                        // Track scrolling in normal mode
                        if !state.shell.wiggle_mode {
                            state.shell.update_home_scroll(touch_pos.y);
                        }

                        // Forward to Slint for scroll/drag feedback
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.dispatch_pointer_moved(touch_pos.x as f32, touch_pos.y as f32);
                        }
                    }
                    crate::shell::ShellView::QuickSettings => {
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.dispatch_pointer_moved(touch_pos.x as f32, touch_pos.y as f32);
                        }
                    }
                    crate::shell::ShellView::Switcher => {
                        // Horizontal scrolling in app switcher
                        if let Some(start_x) = state.shell.switcher_touch_start_x {
                            let total_move = (touch_pos.x - start_x).abs();
                            // Use higher threshold for scrolling detection (30px) to allow taps
                            if total_move > 30.0 {
                                state.shell.is_scrolling = true;
                            }
                        }

                        if let Some(last_x) = state.shell.switcher_touch_last_x {
                            let delta_x = last_x - touch_pos.x;
                            state.shell.switcher_scroll += delta_x;

                            // Clamp scroll to valid range
                            let num_windows = state.space.elements().count();
                            let screen_w = state.screen_size.w as f64;
                            let card_width = screen_w * 0.80;
                            let card_spacing = card_width * 0.35;
                            let max_scroll = state.shell.get_switcher_max_scroll(num_windows, card_spacing);
                            state.shell.switcher_scroll = state.shell.switcher_scroll.clamp(0.0, max_scroll);
                        }
                        state.shell.switcher_touch_last_x = Some(touch_pos.x);

                        // Forward to Slint
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.dispatch_pointer_moved(touch_pos.x as f32, touch_pos.y as f32);
                        }
                    }
                    crate::shell::ShellView::App => {
                        // Touch motion on keyboard overlay - check for swipe down
                        if touch_on_keyboard {
                            // Check for swipe-down gesture to dismiss keyboard
                            if let Some(start_y) = state.keyboard_swipe_start_y {
                                let delta_y = touch_pos.y - start_y;
                                // If moved down by 50+ pixels, activate swipe dismiss
                                if delta_y > 50.0 && !state.keyboard_swipe_active {
                                    state.keyboard_swipe_active = true;
                                    info!("Keyboard swipe-down detected, will dismiss on release");
                                }
                            }
                            // Only forward to Slint if not in swipe mode
                            if !state.keyboard_swipe_active {
                                if let Some(ref slint_ui) = state.shell.slint_ui {
                                    slint_ui.dispatch_pointer_moved(touch_pos.x as f32, touch_pos.y as f32);
                                }
                            }
                        }
                    }
                    crate::shell::ShellView::PickDefault => {
                        // Forward to Slint for pick default scrolling
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.dispatch_pointer_moved(touch_pos.x as f32, touch_pos.y as f32);
                        }
                    }
                    _ => {}
                }
            }
        }

        InputEvent::TouchUp { event } => {
            use smithay::backend::input::TouchEvent;

            let slot_id: i32 = event.slot().into();

            // Get last touch position
            let last_pos = state.last_touch_pos.remove(&slot_id);

            // Track if switcher was just opened by gesture (to skip tap detection)
            let mut switcher_opened_by_gesture = false;

            // Forward to gesture recognizer
            if let Some(gesture_event) = state.gesture_recognizer.touch_up(slot_id) {
                debug!("Gesture touch_up: {:?}", gesture_event);

                // Handle edge swipe completion
                if let crate::input::GestureEvent::EdgeSwipeEnd { edge, completed, .. } = &gesture_event {
                    // Left edge = Quick Settings
                    if *edge == crate::input::Edge::Left {
                        if *completed && state.qs_gesture_active {
                            // Cancel touch sequences before leaving App view
                            if let Some(touch) = state.seat.get_touch() {
                                touch.cancel(state);
                                info!("Quick Settings gesture: cancelled pending touch sequences");
                            }
                            // Open Quick Settings
                            state.shell.view = crate::shell::ShellView::QuickSettings;
                            state.system.refresh();
                            state.shell.sync_quick_settings(&state.system);
                            // Load and set UI icons if not yet done
                            if !state.shell.ui_icons_loaded.get() {
                                let ui_icons = state.shell.load_ui_icons();
                                if let Some(ref slint_ui) = state.shell.slint_ui {
                                    slint_ui.set_ui_icons(ui_icons);
                                    state.shell.ui_icons_loaded.set(true);
                                    info!("UI icons loaded and set to Slint");
                                }
                            }
                            info!("Quick Settings OPENED via gesture");
                        }
                        state.qs_gesture_active = false;
                        state.qs_gesture_progress = 0.0;
                    }
                    // Right edge = App Switcher
                    if *edge == crate::input::Edge::Right {
                        if *completed && state.switcher_gesture_active {
                            // Cancel touch sequences before leaving App view
                            if let Some(touch) = state.seat.get_touch() {
                                touch.cancel(state);
                                info!("Switcher gesture: cancelled pending touch sequences");
                            }
                            // Open App Switcher with proper initialization
                            let num_windows = state.space.elements().count();
                            let screen_w = state.screen_size.w as f64;
                            let card_width = screen_w * 0.80;
                            let card_spacing = card_width * 0.35;
                            state.shell.open_switcher(num_windows, card_spacing);
                            switcher_opened_by_gesture = true;
                            info!("App Switcher OPENED via gesture, {} windows", num_windows);

                            // Update Slint UI with window list
                            if let Some(ref slint_ui) = state.shell.slint_ui {
                                let windows: Vec<_> = state.space.elements()
                                    .enumerate()
                                    .map(|(i, window)| {
                                        // Try X11 surface first, then Wayland toplevel, fall back to generic name
                                        let title = if let Some(x11) = window.x11_surface() {
                                            let t = x11.title();
                                            if !t.is_empty() { t } else { x11.class() }
                                        } else if let Some(toplevel) = window.toplevel() {
                                            // Get title from Wayland toplevel
                                            compositor::with_states(toplevel.wl_surface(), |states| {
                                                states
                                                    .data_map
                                                    .get::<smithay::wayland::shell::xdg::XdgToplevelSurfaceData>()
                                                    .and_then(|data| {
                                                        let data = data.lock().unwrap();
                                                        let title = data.title.clone();
                                                        if title.as_ref().map(|t| !t.is_empty()).unwrap_or(false) {
                                                            title
                                                        } else {
                                                            data.app_id.clone()
                                                        }
                                                    })
                                            }).unwrap_or_else(|| format!("Window {}", i + 1))
                                        } else {
                                            format!("Window {}", i + 1)
                                        };

                                        let app_class = if let Some(x11) = window.x11_surface() {
                                            x11.class()
                                        } else if let Some(toplevel) = window.toplevel() {
                                            compositor::with_states(toplevel.wl_surface(), |states| {
                                                states
                                                    .data_map
                                                    .get::<smithay::wayland::shell::xdg::XdgToplevelSurfaceData>()
                                                    .and_then(|data| data.lock().unwrap().app_id.clone())
                                            }).unwrap_or_else(|| "app".to_string())
                                        } else {
                                            "app".to_string()
                                        };

                                        // Capture window preview from SHM buffer or EGL texture
                                        let preview: Option<slint::Image> = if let Some(toplevel) = window.toplevel() {
                                            compositor::with_states(toplevel.wl_surface(), |states| {
                                                use std::cell::RefCell;
                                                use crate::state::SurfaceBufferData;
                                                if let Some(buffer_data) = states.data_map.get::<RefCell<SurfaceBufferData>>() {
                                                    let bd = buffer_data.borrow();
                                                    // First try SHM buffer (software rendered apps)
                                                    if let Some(ref buffer) = bd.buffer {
                                                        let pixel_buffer = slint::SharedPixelBuffer::<slint::Rgba8Pixel>::clone_from_slice(
                                                            &buffer.pixels,
                                                            buffer.width,
                                                            buffer.height,
                                                        );
                                                        Some(slint::Image::from_rgba8(pixel_buffer))
                                                    } else if let Some(ref egl_tex) = bd.egl_texture {
                                                        // Try reading from EGL texture (hardware rendered apps)
                                                        unsafe {
                                                            if let Some(pixels) = gl::read_texture_pixels(egl_tex.texture_id, egl_tex.width, egl_tex.height) {
                                                                let pixel_buffer = slint::SharedPixelBuffer::<slint::Rgba8Pixel>::clone_from_slice(
                                                                    &pixels,
                                                                    egl_tex.width,
                                                                    egl_tex.height,
                                                                );
                                                                Some(slint::Image::from_rgba8(pixel_buffer))
                                                            } else {
                                                                None
                                                            }
                                                        }
                                                    } else {
                                                        None
                                                    }
                                                } else {
                                                    None
                                                }
                                            })
                                        } else {
                                            None
                                        };

                                        (i as i32, title, app_class, i as i32, preview)
                                    })
                                    .collect();

                                // Sort by render order: furthest from center first, center last
                                // This ensures center card renders on top
                                let scroll = state.shell.switcher_scroll;
                                let card_spacing = screen_w * 0.80 * 0.35;
                                let mut windows = windows;
                                windows.sort_by(|a, b| {
                                    let dist_a = ((a.3 as f64) * card_spacing - scroll).abs();
                                    let dist_b = ((b.3 as f64) * card_spacing - scroll).abs();
                                    // Reverse order: larger distance first (renders behind)
                                    dist_b.partial_cmp(&dist_a).unwrap_or(std::cmp::Ordering::Equal)
                                });

                                slint_ui.set_switcher_windows(windows);
                            }
                        }
                        state.switcher_gesture_active = false;
                        state.switcher_gesture_progress = 0.0;
                    }
                    // Bottom edge = Home gesture (swipe up)
                    if *edge == crate::input::Edge::Bottom {
                        let shell_view = state.shell.view;
                        // In Switcher or QuickSettings, just go directly home on swipe up
                        if shell_view == crate::shell::ShellView::Switcher ||
                           shell_view == crate::shell::ShellView::QuickSettings {
                            if *completed {
                                info!("Swipe up from {} - going home", if shell_view == crate::shell::ShellView::Switcher { "Switcher" } else { "QuickSettings" });
                                state.shell.set_view(crate::shell::ShellView::Home);
                            }
                        } else {
                            // In App view, use the home gesture with keyboard handling
                            state.end_home_gesture(*completed);
                        }
                        info!("Home gesture END, completed={}", completed);
                    }
                    // Top edge = Close gesture (swipe down)
                    if *edge == crate::input::Edge::Top {
                        state.end_close_gesture(*completed);
                        info!("Close gesture END, completed={}", completed);
                    }
                }
            }

            // Check if QML lockscreen is connected
            let has_wayland_window = state.space.elements().count() > 0;
            let shell_view = state.shell.view;

            // Check if touch was on keyboard overlay (in App or LockScreen view with keyboard visible)
            let touch_on_keyboard = if shell_view == crate::shell::ShellView::App || shell_view == crate::shell::ShellView::LockScreen {
                if let Some(pos) = last_pos {
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        if slint_ui.is_keyboard_visible() {
                            let screen_height = state.screen_size.h as f64;
                            let keyboard_height = (screen_height * 0.22).max(200.0);
                            let keyboard_top = screen_height - keyboard_height;
                            pos.y >= keyboard_top
                        } else {
                            false
                        }
                    } else {
                        false
                    }
                } else {
                    false
                }
            } else {
                false
            };

            // Forward touch to Wayland client if connected (but not if touching keyboard)
            // Forward to QML lock screen when on lock screen, or to apps when not locked
            // Don't forward while an edge gesture is active (touch was cancelled)
            let gesture_active = state.switcher_gesture_active || state.qs_gesture_active ||
                                 state.home_gesture_window.is_some() || state.close_gesture_window.is_some();
            let forward_to_wayland = has_wayland_window && !touch_on_keyboard && !gesture_active &&
                (shell_view == crate::shell::ShellView::App && !state.shell.lock_screen_active ||
                 shell_view == crate::shell::ShellView::LockScreen);
            if forward_to_wayland {
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

                // Reset lock screen activity on touch
                if shell_view == crate::shell::ShellView::LockScreen {
                    state.shell.reset_lock_screen_activity();
                }
            } else {
                // Forward to Slint UI and handle app launching
                match shell_view {
                    crate::shell::ShellView::Home => {
                        // Forward to Slint
                        if let Some(pos) = last_pos {
                            if let Some(ref slint_ui) = state.shell.slint_ui {
                                slint_ui.dispatch_pointer_released(pos.x as f32, pos.y as f32);
                            }
                        }

                        if state.shell.wiggle_mode {
                            // In wiggle mode - handle drag end or tap to pick app
                            let dragging_index = state.shell.dragging_index;
                            let drag_start = state.shell.drag_start_position;  // Use INITIAL position

                            if let (Some(from_index), Some(start_pos), Some(end_pos)) = (dragging_index, drag_start, last_pos) {
                                // Check if this was a drag (moved significantly) or a tap
                                let drag_dist = ((end_pos.x - start_pos.x).powi(2) + (end_pos.y - start_pos.y).powi(2)).sqrt();
                                info!("Wiggle mode: drag_dist = {:.1}px (threshold 50px)", drag_dist);

                                if drag_dist > 50.0 {
                                    // This was a drag - reorder the grid
                                    if let Some(to_index) = state.shell.hit_test_category_index(end_pos) {
                                        if from_index != to_index {
                                            info!("Wiggle mode: reordering {} -> {}", from_index, to_index);
                                            state.shell.app_manager.move_category(from_index, to_index);
                                        }
                                    }
                                } else {
                                    // This was a tap - check if in Done button zone first
                                    let screen_height = state.shell.screen_size.h as f64;
                                    let text_scale = state.shell.text_scale as f64;
                                    // Done button is at: y = screen_height - (120 * text_scale) - 40
                                    // With height: 100 * text_scale
                                    // Use margin for easier tapping
                                    let done_zone_top = screen_height - (120.0 * text_scale) - 60.0;

                                    if end_pos.y > done_zone_top {
                                        // Tap in Done button zone - don't open pick default
                                        info!("Wiggle mode: tap in Done button zone (y={:.0} > {:.0})", end_pos.y, done_zone_top);
                                    } else {
                                        // Show pick app popup
                                        let category = state.shell.app_manager.config.grid_order.get(from_index).copied();
                                        if let Some(cat) = category {
                                            info!("Wiggle mode: tap on {} - showing app picker", cat.display_name());
                                            state.shell.enter_pick_default(cat);
                                        }
                                    }
                                }
                            }

                            // Clear drag state
                            state.shell.dragging_index = None;
                            state.shell.drag_start_position = None;
                            state.shell.drag_position = None;

                            // Check for wiggle done and new category button presses
                            // Extract values first to avoid borrow conflicts
                            let (wiggle_done, new_category) = if let Some(ref slint_ui) = state.shell.slint_ui {
                                (slint_ui.take_wiggle_done(), slint_ui.take_new_category())
                            } else {
                                (false, false)
                            };

                            if wiggle_done {
                                info!("Wiggle mode done - exiting");
                                state.shell.exit_wiggle_mode();
                                // Also clear Slint's dragging index
                                if let Some(ref slint_ui) = state.shell.slint_ui {
                                    slint_ui.set_dragging_index(-1);
                                }
                            }
                            if new_category {
                                info!("New category button pressed - TODO: show category creation dialog");
                                // TODO: Implement category creation dialog
                            }
                        } else {
                            // Normal mode - end home touch tracking, returns pending app if it was a tap (not scroll)
                            if let Some(exec) = state.shell.end_home_touch() {
                                info!("Launching app from home touch: {}", exec);
                                // Get socket name for WAYLAND_DISPLAY
                                let socket_name = state.socket_name.to_str().unwrap_or("wayland-1");
                                // Get text scale for app scaling
                                let text_scale = state.shell.text_scale as f64;
                                // Launch app as user with hwcomposer-specific settings
                                if let Err(e) = crate::spawn_user::spawn_as_user_hwcomposer(&exec, socket_name, text_scale) {
                                    error!("Failed to launch app: {}", e);
                                }

                                // Switch to App view to show the window
                                state.shell.view = crate::shell::ShellView::App;
                            }
                        }
                    }
                    crate::shell::ShellView::QuickSettings => {
                        if let Some(pos) = last_pos {
                            if let Some(ref slint_ui) = state.shell.slint_ui {
                                slint_ui.dispatch_pointer_released(pos.x as f32, pos.y as f32);

                                // Process pending Quick Settings actions
                                use crate::system::{WifiManager, BluetoothManager, AirplaneMode, Flashlight};
                                use crate::shell::slint_ui::QuickSettingsAction;

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
                                        QuickSettingsAction::TouchEffectsToggle => {
                                            // Toggle both touch effects AND living pixels
                                            let enabled = !state.touch_effects_enabled;
                                            state.set_touch_effects_enabled(enabled);
                                            // Also toggle living pixels in the config
                                            state.set_living_pixels_enabled(enabled);
                                            // Immediately update UI for instant feedback
                                            if let Some(ref slint_ui) = state.shell.slint_ui {
                                                slint_ui.set_touch_effects_enabled(enabled);
                                            }
                                            info!("All effects (FX): {}", if enabled { "ON" } else { "OFF" });
                                        }
                                        QuickSettingsAction::Lock => {
                                            info!("Lock button pressed - locking screen");
                                            state.shell.lock();
                                            if let Some(socket) = state.socket_name.to_str() {
                                                state.shell.launch_lock_screen_app(socket);
                                            }
                                        }
                                        QuickSettingsAction::Settings => {
                                            info!("Settings button pressed - launching settings app");
                                            use crate::shell::apps::AppCategory;
                                            if let Some(exec) = state.shell.app_manager.get_exec(AppCategory::Settings) {
                                                state.shell.set_view(crate::shell::ShellView::App);
                                                let socket_name = state.socket_name.to_str().unwrap_or("wayland-1");
                                                let text_scale = state.shell.text_scale as f64;
                                                // Launch as user with hwcomposer-specific settings
                                                if let Err(e) = crate::spawn_user::spawn_as_user_hwcomposer(&exec, socket_name, text_scale) {
                                                    error!("Failed to launch settings app: {}", e);
                                                }
                                            }
                                        }
                                        QuickSettingsAction::BrightnessChanged(value) => {
                                            state.system.set_brightness(value);
                                            info!("Brightness set to {:.0}%", value * 100.0);
                                        }
                                        QuickSettingsAction::VolumeChanged(value) => {
                                            state.system.set_volume(value);
                                            info!("Volume set to {}%", value);
                                        }
                                    }
                                }
                            }
                        }
                    }
                    crate::shell::ShellView::Switcher => {
                        // Only handle tap if not scrolling and not just opened by gesture
                        let was_scrolling = state.shell.is_scrolling;
                        let touch_pos = last_pos;

                        // Clear touch tracking
                        state.shell.switcher_touch_start_x = None;
                        state.shell.switcher_touch_last_x = None;
                        state.shell.is_scrolling = false;

                        // Calculate which card was tapped based on touch position
                        // Skip if switcher was just opened by gesture (the opening swipe shouldn't count as a tap)
                        if !was_scrolling && !switcher_opened_by_gesture {
                            if let Some(pos) = touch_pos {
                                let screen_w = state.screen_size.w as f64;
                                let screen_h = state.screen_size.h as f64;
                                let card_width = screen_w * 0.80;
                                let card_height = screen_h * 0.55;
                                let card_spacing = card_width * 0.35;
                                let scroll = state.shell.switcher_scroll;
                                let num_windows = state.space.elements().count();

                                // Card area starts at y=60px, ends at screen_h - 40px
                                let card_area_top = 60.0;
                                let card_area_bottom = screen_h - 40.0;
                                let card_area_height = card_area_bottom - card_area_top;

                                // Check if tap is in the card area vertically
                                if pos.y >= card_area_top && pos.y <= card_area_bottom {
                                    // Find which card was tapped (check from center outward for z-order)
                                    let mut tapped_window: Option<usize> = None;

                                    // Calculate center index based on scroll
                                    let center_idx = (scroll / card_spacing).round() as i32;

                                    // Check cards in order of visual z-order (center first, then outward)
                                    for offset in 0..=(num_windows as i32) {
                                        for sign in [-1i32, 1i32] {
                                            if offset == 0 && sign == -1 { continue; } // Don't check center twice

                                            let idx = center_idx + offset * sign;
                                            if idx < 0 || idx >= num_windows as i32 { continue; }
                                            let idx = idx as usize;

                                            // Calculate card position
                                            let normalized_pos = (idx as f64 * card_spacing - scroll) / card_spacing;
                                            let distance = normalized_pos.abs();
                                            let scale = (1.0 - distance * 0.1).max(0.75);

                                            let card_w = card_width * scale;
                                            let card_h = card_height * scale;
                                            let card_x = idx as f64 * card_spacing - scroll + (screen_w - card_width) / 2.0;
                                            let card_y = card_area_top + (card_area_height - card_h) / 2.0;

                                            // Check if tap is within this card
                                            if pos.x >= card_x && pos.x <= card_x + card_w &&
                                               pos.y >= card_y && pos.y <= card_y + card_h {
                                                tapped_window = Some(idx);
                                                break;
                                            }
                                        }
                                        if tapped_window.is_some() { break; }
                                    }

                                    if let Some(window_id) = tapped_window {
                                        info!("Switcher tap: tapped window index {} at ({}, {})", window_id, pos.x, pos.y);

                                        // Cancel any pending touch sequences before switching apps
                                        // This clears any touch grab the previous app might have
                                        if let Some(touch) = state.seat.get_touch() {
                                            touch.cancel(state);
                                            info!("Switcher: Cancelled pending touch sequences");
                                        }

                                        let windows: Vec<_> = state.space.elements().cloned().collect();
                                        if let Some(window) = windows.get(window_id) {
                                            // DEACTIVATE all windows first
                                            for (i, w) in windows.iter().enumerate() {
                                                if let Some(toplevel) = w.toplevel() {
                                                    toplevel.with_pending_state(|s| {
                                                        s.states.unset(smithay::reexports::wayland_protocols::xdg::shell::server::xdg_toplevel::State::Activated);
                                                    });
                                                    toplevel.send_configure();
                                                    info!("Switcher: Deactivated window {}", i);
                                                }
                                            }

                                            // Raise window to top of stacking order
                                            info!("Raising window {} to top", window_id);
                                            state.space.raise_element(window, true);

                                            // Set as active window for touch input
                                            state.active_window = Some(window.clone());
                                            info!("Active window set to window {}", window_id);

                                            // ACTIVATE the selected window and set keyboard focus
                                            if let Some(toplevel) = window.toplevel() {
                                                // Send activated state
                                                toplevel.with_pending_state(|s| {
                                                    s.states.set(smithay::reexports::wayland_protocols::xdg::shell::server::xdg_toplevel::State::Activated);
                                                });
                                                toplevel.send_configure();
                                                info!("Switcher: Activated window {}", window_id);

                                                let surface = toplevel.wl_surface();
                                                let client_info = surface.client().map(|c| format!("{:?}", c.id())).unwrap_or_else(|| "no-client".to_string());
                                                info!("Switcher: Setting keyboard focus to {:?} (client: {})", surface.id(), client_info);
                                                let serial = smithay::utils::SERIAL_COUNTER.next_serial();
                                                if let Some(keyboard) = state.seat.get_keyboard() {
                                                    keyboard.set_focus(state, Some(surface.clone()), serial);
                                                }
                                            } else if let Some(x11) = window.x11_surface() {
                                                if let Some(wl_surface) = x11.wl_surface() {
                                                    let client_info = wl_surface.client().map(|c| format!("{:?}", c.id())).unwrap_or_else(|| "no-client".to_string());
                                                    info!("Switcher: Setting keyboard focus to X11 {:?} (client: {})", wl_surface.id(), client_info);
                                                    let serial = smithay::utils::SERIAL_COUNTER.next_serial();
                                                    if let Some(keyboard) = state.seat.get_keyboard() {
                                                        keyboard.set_focus(state, Some(wl_surface), serial);
                                                    }
                                                }
                                            }

                                            // Switch to App view
                                            state.shell.set_view(crate::shell::ShellView::App);
                                        }
                                    }
                                }
                            }
                        }
                    }
                    crate::shell::ShellView::App => {
                        // Touch up on keyboard overlay
                        if touch_on_keyboard {
                            // Check if this was a swipe-down to dismiss
                            if state.keyboard_swipe_active {
                                info!("Keyboard swipe-down complete - dismissing keyboard");
                                // Reset swipe state
                                state.keyboard_swipe_start_y = None;
                                state.keyboard_swipe_active = false;
                                // Dismiss keyboard and resize app
                                if let Some(ref slint_ui) = state.shell.slint_ui {
                                    slint_ui.set_keyboard_visible(false);
                                }
                                state.resize_windows_for_keyboard(false);
                                // Don't process as key press
                            } else if let Some(pos) = last_pos {
                                info!("Keyboard TouchUp at ({}, {})", pos.x, pos.y);
                                // Reset swipe state
                                state.keyboard_swipe_start_y = None;

                                // Dispatch to Slint and get pending keyboard actions
                                use crate::shell::slint_ui::KeyboardAction;
                                let actions = if let Some(ref slint_ui) = state.shell.slint_ui {
                                    slint_ui.dispatch_pointer_released(pos.x as f32, pos.y as f32);
                                    slint_ui.take_pending_keyboard_actions()
                                } else {
                                    Vec::new()
                                };

                                // Process keyboard actions (after dropping slint_ui borrow)
                                for action in actions {
                                    // Trigger haptic feedback for key presses
                                    state.system.haptic_tap();
                                    info!("KB ACTION: {:?}", action);
                                    match action {
                                        KeyboardAction::Character(ch) => {
                                            if let Some(c) = ch.chars().next() {
                                                if let Some((keycode, needs_shift)) = char_to_evdev(c) {
                                                    if let Some(keyboard) = state.seat.get_keyboard() {
                                                        let serial = smithay::utils::SERIAL_COUNTER.next_serial();
                                                        let time = std::time::SystemTime::now()
                                                            .duration_since(std::time::UNIX_EPOCH)
                                                            .unwrap_or_default()
                                                            .as_millis() as u32;
                                                        let xkb_keycode = keycode + 8;
                                                        info!("Injecting key '{}' keycode={}", c, xkb_keycode);
                                                        if needs_shift {
                                                            keyboard.input::<(), _>(state, smithay::input::keyboard::Keycode::new(42 + 8), smithay::backend::input::KeyState::Pressed, serial, time, |_, _, _| { FilterResult::Forward::<()> });
                                                        }
                                                        keyboard.input::<(), _>(state, smithay::input::keyboard::Keycode::new(xkb_keycode), smithay::backend::input::KeyState::Pressed, serial, time, |_, _, _| { FilterResult::Forward::<()> });
                                                        keyboard.input::<(), _>(state, smithay::input::keyboard::Keycode::new(xkb_keycode), smithay::backend::input::KeyState::Released, serial, time, |_, _, _| { FilterResult::Forward::<()> });
                                                        if needs_shift {
                                                            keyboard.input::<(), _>(state, smithay::input::keyboard::Keycode::new(42 + 8), smithay::backend::input::KeyState::Released, serial, time, |_, _, _| { FilterResult::Forward::<()> });
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        KeyboardAction::Backspace => {
                                            if let Some(keyboard) = state.seat.get_keyboard() {
                                                let serial = smithay::utils::SERIAL_COUNTER.next_serial();
                                                let time = std::time::SystemTime::now()
                                                    .duration_since(std::time::UNIX_EPOCH)
                                                    .unwrap_or_default()
                                                    .as_millis() as u32;
                                                keyboard.input::<(), _>(state, smithay::input::keyboard::Keycode::new(14 + 8), smithay::backend::input::KeyState::Pressed, serial, time, |_, _, _| { FilterResult::Forward::<()> });
                                                keyboard.input::<(), _>(state, smithay::input::keyboard::Keycode::new(14 + 8), smithay::backend::input::KeyState::Released, serial, time, |_, _, _| { FilterResult::Forward::<()> });
                                            }
                                        }
                                        KeyboardAction::Enter => {
                                            if let Some(keyboard) = state.seat.get_keyboard() {
                                                let serial = smithay::utils::SERIAL_COUNTER.next_serial();
                                                let time = std::time::SystemTime::now()
                                                    .duration_since(std::time::UNIX_EPOCH)
                                                    .unwrap_or_default()
                                                    .as_millis() as u32;
                                                keyboard.input::<(), _>(state, smithay::input::keyboard::Keycode::new(28 + 8), smithay::backend::input::KeyState::Pressed, serial, time, |_, _, _| { FilterResult::Forward::<()> });
                                                keyboard.input::<(), _>(state, smithay::input::keyboard::Keycode::new(28 + 8), smithay::backend::input::KeyState::Released, serial, time, |_, _, _| { FilterResult::Forward::<()> });
                                            }
                                        }
                                        KeyboardAction::Space => {
                                            if let Some(keyboard) = state.seat.get_keyboard() {
                                                let serial = smithay::utils::SERIAL_COUNTER.next_serial();
                                                let time = std::time::SystemTime::now()
                                                    .duration_since(std::time::UNIX_EPOCH)
                                                    .unwrap_or_default()
                                                    .as_millis() as u32;
                                                keyboard.input::<(), _>(state, smithay::input::keyboard::Keycode::new(57 + 8), smithay::backend::input::KeyState::Pressed, serial, time, |_, _, _| { FilterResult::Forward::<()> });
                                                keyboard.input::<(), _>(state, smithay::input::keyboard::Keycode::new(57 + 8), smithay::backend::input::KeyState::Released, serial, time, |_, _, _| { FilterResult::Forward::<()> });
                                            }
                                        }
                                        KeyboardAction::ShiftToggled => {
                                            if let Some(ref slint_ui) = state.shell.slint_ui {
                                                let current = slint_ui.is_keyboard_shifted();
                                                slint_ui.set_keyboard_shifted(!current);
                                            }
                                        }
                                        KeyboardAction::LayoutToggled => {
                                            if let Some(ref slint_ui) = state.shell.slint_ui {
                                                let current = slint_ui.get_keyboard_layout();
                                                slint_ui.set_keyboard_layout(if current == 0 { 1 } else { 0 });
                                            }
                                        }
                                        KeyboardAction::Hide => {
                                            if let Some(ref slint_ui) = state.shell.slint_ui {
                                                slint_ui.set_keyboard_visible(false);
                                            }
                                            state.resize_windows_for_keyboard(false);
                                        }
                                    }
                                }
                            }
                        }
                    }
                    crate::shell::ShellView::PickDefault => {
                        // Forward to Slint for pick default app selection
                        if let Some(pos) = last_pos {
                            if let Some(ref slint_ui) = state.shell.slint_ui {
                                slint_ui.dispatch_pointer_released(pos.x as f32, pos.y as f32);
                            }
                        }
                    }
                    _ => {}
                }
            }

            // End touch effect (ripple) when finger is lifted
            state.end_touch_effect(slot_id as u64);
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
    info!("Libinput context created with udev");
    libinput_context.udev_assign_seat(&session.borrow().seat()).unwrap();
    info!("Libinput seat assigned: {}", session.borrow().seat());

    // Initial dispatch to pick up devices
    libinput_context.dispatch().unwrap();
    info!("Libinput dispatched initially");

    let libinput_backend = LibinputInputBackend::new(libinput_context.clone());
    info!("Libinput backend created");

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

    // Bind EGL to Wayland display for libhybris clients
    // This is required for EGL_WL_bind_wayland_display extension to work
    {
        let mut display_ref = state.display.borrow_mut();
        let backend = display_ref.backend();

        unsafe {
            #[allow(unused_imports)]
            use wayland_backend::server::Backend as WaylandBackend;

            let wl_display_ptr = backend.handle().display_ptr();

            type EglBindWaylandDisplayWL = unsafe extern "C" fn(
                *mut std::ffi::c_void,
                *mut std::ffi::c_void,
            ) -> u32;

            let bind_fn_ptr = hwc_display.egl_instance.get_proc_address("eglBindWaylandDisplayWL");
            if let Some(fn_ptr) = bind_fn_ptr {
                let bind_wayland_display: EglBindWaylandDisplayWL = std::mem::transmute(fn_ptr);
                let result = bind_wayland_display(
                    hwc_display.egl_display.as_ptr() as *mut std::ffi::c_void,
                    wl_display_ptr as *mut std::ffi::c_void,
                );
                if result == egl::TRUE as u32 {
                    info!("Successfully bound EGL to Wayland display");
                } else {
                    warn!("Failed to bind EGL to Wayland display (result={})", result);
                }
            } else {
                info!("eglBindWaylandDisplayWL not available");
            }
        }
    }

    // Create dmabuf global for buffer sharing (required for camera preview)
    {
        // Try to find a render node for dmabuf
        let render_node = std::fs::read_dir("/dev/dri")
            .ok()
            .and_then(|entries| {
                entries
                    .filter_map(|e| e.ok())
                    .find(|e| e.file_name().to_string_lossy().starts_with("renderD"))
                    .map(|e| e.path())
            });

        if let Some(render_path) = render_node {
            info!("Found render node: {:?}", render_path);

            // Open the render node to get the device
            if let Ok(file) = std::fs::File::open(&render_path) {
                use std::os::unix::io::AsRawFd;
                let fd = file.as_raw_fd();

                // Get device info using fstat
                let mut stat: libc::stat = unsafe { std::mem::zeroed() };
                let stat_result = unsafe { libc::fstat(fd, &mut stat) };

                if stat_result == 0 {
                    let dev = stat.st_rdev;
                    info!("Render node device: major={}, minor={}",
                          unsafe { libc::major(dev) },
                          unsafe { libc::minor(dev) });

                    // Common DRM formats supported by most Android devices
                    let formats = vec![
                        Format { code: Fourcc::Argb8888, modifier: Modifier::Linear },
                        Format { code: Fourcc::Xrgb8888, modifier: Modifier::Linear },
                        Format { code: Fourcc::Abgr8888, modifier: Modifier::Linear },
                        Format { code: Fourcc::Xbgr8888, modifier: Modifier::Linear },
                        // Also support invalid modifier (means driver will choose)
                        Format { code: Fourcc::Argb8888, modifier: Modifier::Invalid },
                        Format { code: Fourcc::Xrgb8888, modifier: Modifier::Invalid },
                        Format { code: Fourcc::Abgr8888, modifier: Modifier::Invalid },
                        Format { code: Fourcc::Xbgr8888, modifier: Modifier::Invalid },
                    ];

                    // Build dmabuf feedback
                    match DmabufFeedbackBuilder::new(dev, formats.clone()).build() {
                        Ok(default_feedback) => {
                            let dmabuf_global = state.dmabuf_state
                                .create_global_with_default_feedback::<Flick>(
                                    &state.display_handle,
                                    &default_feedback,
                                );
                            state.dmabuf_global = Some(dmabuf_global);
                            info!("Created dmabuf global with {} formats", formats.len());
                        }
                        Err(e) => {
                            warn!("Failed to build dmabuf feedback: {:?}", e);
                        }
                    }

                    // Keep file open to maintain the device reference
                    std::mem::forget(file);
                } else {
                    warn!("Failed to stat render node");
                }
            } else {
                warn!("Failed to open render node");
            }
        } else {
            info!("No render node found - dmabuf not available");
        }
    }

    // Update state with actual screen size from hwc_display
    // (may differ from initial estimate if shim got real dimensions)
    let width = hwc_display.width;
    let height = hwc_display.height;
    state.screen_size = (width as i32, height as i32).into();
    state.physical_display_size = (width as i32, height as i32).into(); // Store physical size
    state.gesture_recognizer.screen_size = state.screen_size;
    state.shell.screen_size = state.screen_size;
    state.shell.quick_settings.screen_size = state.screen_size;

    // Update the Wayland output mode with correct dimensions
    // This ensures Wayland clients receive the correct screen size
    if let Some(output) = state.outputs.first() {
        let correct_mode = Mode {
            size: (width as i32, height as i32).into(),
            refresh: 60_000,
        };
        output.change_current_state(
            Some(correct_mode),
            None,
            None,
            None,
        );
        output.set_preferred(correct_mode);
        info!("Updated Wayland output mode to {}x{}", width, height);
    }

    if let Some(ref mut slint_ui) = state.shell.slint_ui {
        slint_ui.set_size(state.screen_size);
    }

    // Launch QML lock screen app if configured
    if state.shell.lock_screen_active {
        info!("Lock screen active - launching QML lock screen app");
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

    // Initialize XWayland for X11 app support
    info!("Starting XWayland...");
    if let Err(e) = init_xwayland(&mut state, &loop_handle) {
        warn!("Failed to start XWayland: {:?}", e);
        warn!("X11 applications will not be available");
    } else {
        info!("XWayland started successfully");
    }

    info!("Entering event loop");

    // Main event loop
    let mut loop_count: u64 = 0;
    let mut was_blanked = false; // Track previous blanked state for unblank transitions
    loop {
        loop_count += 1;
        let log_loop = loop_count % 1000 == 0;

        if log_loop {
            debug!("Event loop iteration {}", loop_count);
        }

        // Dispatch incoming Wayland client requests - this is critical!
        // Without this, clients connect but their protocol messages are never processed.
        // Use the safe dispatch_clients method that handles the borrow properly.
        state.dispatch_clients();

        // Reload settings from config file (for Settings app changes)
        state.reload_settings_if_needed();

        // Check for unlock signal from external lock screen app (QML lockscreen)
        if state.shell.check_unlock_signal() {
            info!("=== UNLOCK SIGNAL DETECTED (hwcomposer) ===");
            info!("Before unlock: view={:?}, lock_screen_active={}", state.shell.view, state.shell.lock_screen_active);

            // Don't close windows here - the lock screen app closes itself via Qt.quit()
            // and user app windows should remain open
            let window_count = state.space.elements().count();
            info!("Unlock: {} windows in space (preserving user apps)", window_count);

            state.shell.unlock();
            info!("After unlock: view={:?}, lock_screen_active={}", state.shell.view, state.shell.lock_screen_active);
        }

        // Auto-lock check - only when not already locked and timeout is set (0 = never)
        if !state.shell.lock_screen_active && state.shell.screen_timeout_secs > 0 {
            let idle_duration = state.last_activity.elapsed();
            let timeout = Duration::from_secs(state.shell.screen_timeout_secs);
            if idle_duration >= timeout {
                info!("Auto-lock triggered after {:?} idle (timeout={}s)", idle_duration, state.shell.screen_timeout_secs);
                state.shell.lock();
                if let Some(socket) = state.socket_name.to_str() {
                    state.shell.launch_lock_screen_app(socket);
                }
            }
        }

        // Log every loop iteration for debugging
        debug!("Loop {}: after dispatch_clients", loop_count);

        // Dispatch calloop events
        event_loop
            .dispatch(Some(Duration::from_millis(1)), &mut state)
            .map_err(|e| anyhow::anyhow!("Event loop error: {:?}", e))?;

        debug!("Loop {}: after calloop dispatch", loop_count);

        // Check for long press to enter wiggle mode (runs every frame)
        if state.shell.view == crate::shell::ShellView::Home
            && !state.shell.wiggle_mode
            && !state.shell.is_scrolling
            && state.shell.long_press_start.is_some()
        {
            if let Some(_category) = state.shell.check_long_press() {
                info!("Long press detected - entering wiggle mode");
                state.shell.enter_wiggle_mode();
            }
        }

        // Poll for pick default callbacks (runs every frame when in PickDefault view)
        if state.shell.view == crate::shell::ShellView::PickDefault {
            // Get pending actions from Slint first (to avoid borrow conflicts)
            let (selected_exec, back_pressed) = if let Some(ref slint_ui) = state.shell.slint_ui {
                (slint_ui.take_pick_default_selection(), slint_ui.take_pick_default_back())
            } else {
                (None, false)
            };

            // Now handle the actions with mutable access
            if let Some(exec) = selected_exec {
                info!("App selected from pick default: {}", exec);
                state.shell.select_default_app(&exec);
            } else if back_pressed {
                info!("Pick default back pressed");
                state.shell.exit_pick_default();
            }
        }

        // Skip rendering if session not active
        if !*session_active.borrow() {
            debug!("Loop {}: session not active, skipping render", loop_count);
            continue;
        }

        // Check if lock screen should be dimmed (power saving)
        if state.shell.view == crate::shell::ShellView::LockScreen {
            state.shell.check_lock_screen_dim();
            // Also check timeout-based blanking
            state.shell.check_display_blank();
        }

        // Handle display power state transitions
        if !was_blanked && state.shell.display_blanked {
            // Transition to blanked - turn off display
            info!("Blanking display (power off)");
            if let Err(e) = hwc_display.hwc_ctx.set_power(false) {
                error!("Failed to blank display: {}", e);
            }
        } else if was_blanked && !state.shell.display_blanked {
            // Transition to unblanked - turn on display
            info!("Unblanking display (power on)");
            if let Err(e) = hwc_display.hwc_ctx.set_power(true) {
                error!("Failed to unblank display: {}", e);
            }
        }
        was_blanked = state.shell.display_blanked;

        // Skip rendering if display is blanked
        if state.shell.display_blanked {
            // Still need to dispatch events but don't render
            std::thread::sleep(Duration::from_millis(100));
            continue;
        }

        // Periodic system refresh (battery, wifi, etc.) - every 10 seconds
        if state.system_last_refresh.elapsed().as_secs() >= 10 {
            state.system.refresh();
            state.shell.sync_quick_settings(&state.system);
            // Reload text scale from settings (allows live changes)
            state.shell.reload_text_scale();
            state.system_last_refresh = std::time::Instant::now();
        }

        // Check for phone status (incoming calls) - rate limited internally to 500ms
        let new_incoming = state.system.check_phone();
        if new_incoming {
            // New incoming call - wake screen and show overlay
            tracing::info!("Incoming call from: {}", state.system.phone.number);
            // Wake screen if blanked
            if state.shell.display_blanked {
                state.shell.wake_lock_screen();
                hwc_display.hwc_ctx.set_power(true);
            }
            // Vibrate for incoming call (continuous pattern)
            state.system.haptic_heavy();
        }

        // Check for haptic requests from apps (via /tmp/flick_haptic)
        state.system.check_app_haptic();

        // Check for app notifications (via ~/.local/state/flick/app_notifications.json)
        crate::shell::quick_settings::check_app_notifications();
        // Check for dismiss requests from lock screen
        crate::shell::quick_settings::check_dismiss_requests();
        // Export notifications for lock screen display
        crate::shell::quick_settings::export_notifications_for_lockscreen();

        // Check for music scan requests from apps (via /tmp/flick_music_scan_request)
        if let Ok(path) = std::fs::read_to_string("/tmp/flick_music_scan_request") {
            let path = path.trim();
            if !path.is_empty() {
                // Scan the directory and write file listing
                if let Ok(entries) = std::fs::read_dir(path) {
                    let files: Vec<String> = entries
                        .filter_map(|e| e.ok())
                        .filter_map(|e| e.file_name().into_string().ok())
                        .collect();
                    let listing = files.join("\n");
                    let _ = std::fs::write("/tmp/flick_music_files", listing);
                    tracing::info!("Music scan: found {} files in {}", files.len(), path);
                }
                // Clear the request
                let _ = std::fs::write("/tmp/flick_music_scan_request", "");
            }
        }

        // Update Slint UI with phone status
        if let Some(ref slint_ui) = state.shell.slint_ui {
            let has_incoming = state.system.has_incoming_call();
            slint_ui.set_incoming_call(has_incoming, state.system.incoming_call_number());

            // Handle phone call actions from UI
            use crate::shell::slint_ui::PhoneCallAction;
            for action in slint_ui.take_pending_phone_actions() {
                match action {
                    PhoneCallAction::Answer => {
                        tracing::info!("Phone: user answered call");
                        state.system.answer_call();
                    }
                    PhoneCallAction::Reject => {
                        tracing::info!("Phone: user rejected call");
                        state.system.reject_call();
                    }
                }
            }
        }

        // Clean up expired touch effects before rendering
        state.cleanup_touch_effects();

        debug!("Loop {}: calling render_frame", loop_count);
        // Render frame
        if let Err(e) = render_frame(&mut hwc_display, &state, &output) {
            error!("Render error: {:?}", e);
        }
        debug!("Loop {}: after render_frame", loop_count);

        // Send frame callbacks to Wayland clients
        state.space.elements().for_each(|window| {
            window.send_frame(
                &output,
                state.start_time.elapsed(),
                Some(Duration::ZERO),
                |_, _| Some(output.clone()),
            );
        });
    }
}

// Frame counter for render_frame logging
static mut RENDER_FRAME_COUNT: u64 = 0;

/// Try to import a wayland buffer as an EGL image and create a GL texture
/// Returns (texture_id, width, height, egl_image) on success
fn try_import_egl_buffer(
    wl_surface: &smithay::reexports::wayland_server::protocol::wl_surface::WlSurface,
    display: &HwcDisplay,
) -> Option<(u32, u32, u32, *mut std::ffi::c_void)> {
    use smithay::wayland::compositor::{with_states, SurfaceAttributes};

    // Check if we have the required EGL extensions
    let query_fn = match display.egl_query_wayland_buffer {
        Some(f) => f,
        None => {
            info!("try_import_egl_buffer: no egl_query_wayland_buffer");
            return None;
        }
    };
    let create_image_fn = match display.egl_create_image {
        Some(f) => f,
        None => {
            info!("try_import_egl_buffer: no egl_create_image");
            return None;
        }
    };
    let image_target_fn = match display.gl_egl_image_target_texture_2d {
        Some(f) => f,
        None => {
            info!("try_import_egl_buffer: no gl_egl_image_target_texture_2d");
            return None;
        }
    };

    // Get the stored wl_buffer pointer from the surface data
    use std::cell::RefCell;
    use crate::state::SurfaceBufferData;

    let buffer_ptr: Option<*mut std::ffi::c_void> = with_states(wl_surface, |data| {
        // First check if we have a stored buffer pointer from commit
        if let Some(buffer_data) = data.data_map.get::<RefCell<SurfaceBufferData>>() {
            let bd = buffer_data.borrow();
            if let Some(ptr) = bd.wl_buffer_ptr {
                info!("try_import_egl_buffer: using stored buffer ptr {:?}", ptr);
                return Some(ptr);
            }
        }

        // Fallback: try to get from buffer assignment (may already be cleared)
        let mut binding = data.cached_state.get::<SurfaceAttributes>();
        let attrs = binding.current();

        if let Some(ref buffer_assignment) = attrs.buffer {
            use smithay::wayland::compositor::BufferAssignment;
            match buffer_assignment {
                BufferAssignment::NewBuffer(buffer) => {
                    use smithay::reexports::wayland_server::Resource;
                    info!("try_import_egl_buffer: found NewBuffer {:?}", buffer.id());
                    Some(buffer.id().as_ptr() as *mut std::ffi::c_void)
                }
                BufferAssignment::Removed => {
                    info!("try_import_egl_buffer: buffer was Removed");
                    None
                }
            }
        } else {
            info!("try_import_egl_buffer: no buffer assignment");
            None
        }
    });

    let buffer_ptr = match buffer_ptr {
        Some(p) => p,
        None => {
            info!("try_import_egl_buffer: no buffer pointer available");
            return None;
        }
    };

    // Query buffer dimensions
    let mut width: i32 = 0;
    let mut height: i32 = 0;
    let mut texture_format: i32 = 0;

    let egl_display_ptr = display.egl_display.as_ptr() as *mut std::ffi::c_void;

    unsafe {
        // Query width
        let result = query_fn(egl_display_ptr, buffer_ptr, EGL_WIDTH as i32, &mut width);
        if result == 0 {
            debug!("eglQueryWaylandBufferWL failed for width");
            return None;
        }

        // Query height
        let result = query_fn(egl_display_ptr, buffer_ptr, EGL_HEIGHT as i32, &mut height);
        if result == 0 {
            debug!("eglQueryWaylandBufferWL failed for height");
            return None;
        }

        // Query texture format
        let result = query_fn(egl_display_ptr, buffer_ptr, EGL_TEXTURE_FORMAT as i32, &mut texture_format);
        if result == 0 {
            debug!("eglQueryWaylandBufferWL failed for format");
            return None;
        }
    }

    info!("EGL buffer query: {}x{}, format={}", width, height, texture_format);

    // Create EGL image from the wayland buffer
    let attribs: [i32; 1] = [egl::NONE as i32];

    let egl_image = unsafe {
        create_image_fn(
            egl_display_ptr,
            egl::NO_CONTEXT as *mut std::ffi::c_void, // No context for wayland buffer
            EGL_WAYLAND_BUFFER_WL,
            buffer_ptr,
            attribs.as_ptr(),
        )
    };

    if egl_image == EGL_NO_IMAGE_KHR {
        info!("eglCreateImageKHR failed for buffer {:?}", buffer_ptr);
        return None;
    }

    info!("Created EGL image: {:?}", egl_image);

    // Create GL texture and bind EGL image to it
    let texture_id = unsafe { gl::create_texture_from_egl_image(egl_image, image_target_fn) };

    info!("Created GL texture {} from EGL image", texture_id);

    Some((texture_id, width as u32, height as u32, egl_image))
}

/// Recursively render subsurfaces of a parent surface
/// This is needed for camera preview which uses EGL/dmabuf subsurfaces
fn render_subsurfaces(
    parent: &smithay::reexports::wayland_server::protocol::wl_surface::WlSurface,
    parent_pos: smithay::utils::Point<i32, smithay::utils::Logical>,
    display: &mut HwcDisplay,
    log_frame: bool,
    frame_num: u64,
) {
    use std::cell::RefCell;
    use crate::state::{SurfaceBufferData, EglTextureBuffer};

    // Get all child surfaces (subsurfaces)
    let children = compositor::get_children(parent);

    if log_frame && !children.is_empty() {
        info!("Surface {:?} has {} subsurfaces", parent.id(), children.len());
    }

    for (idx, child) in children.iter().enumerate() {
        // Get subsurface position relative to parent
        let subsurface_offset = compositor::with_states(child, |data| {
            // Get cached state for subsurface position
            use smithay::wayland::compositor::SubsurfaceCachedState;
            let mut cached = data.cached_state.get::<SubsurfaceCachedState>();
            cached.current().location
        });

        let child_pos = smithay::utils::Point::from((
            parent_pos.x + subsurface_offset.x,
            parent_pos.y + subsurface_offset.y,
        ));

        // Check buffer state for this subsurface
        let buffer_state = compositor::with_states(child, |data| {
            if let Some(buffer_data) = data.data_map.get::<RefCell<SurfaceBufferData>>() {
                let bd = buffer_data.borrow();
                (bd.needs_egl_import, bd.buffer.is_some(), bd.egl_texture.is_some(),
                 bd.egl_texture.as_ref().map(|t| (t.texture_id, t.width, t.height)))
            } else {
                (false, false, false, None)
            }
        });

        let (needs_egl, has_shm, has_egl_tex, egl_info) = buffer_state;

        if log_frame {
            info!("  Subsurface[{}] {:?}: needs_egl={}, has_shm={}, has_egl_tex={}, pos=({},{})",
                  idx, child.id(), needs_egl, has_shm, has_egl_tex, child_pos.x, child_pos.y);
        }

        // Render EGL texture if available
        if let Some((texture_id, width, height)) = egl_info {
            if log_frame {
                info!("  Subsurface[{}] RENDERING EGL texture {} ({}x{})", idx, texture_id, width, height);
            }
            unsafe {
                gl::render_egl_texture_at(texture_id, width, height, display.width, display.height,
                                          child_pos.x, child_pos.y);
            }
        } else if needs_egl {
            // Try to import EGL buffer
            if log_frame {
                info!("  Subsurface[{}] attempting EGL import...", idx);
            }
            if let Some(imported) = try_import_egl_buffer(child, display) {
                // Store the imported texture
                compositor::with_states(child, |data| {
                    data.data_map.insert_if_missing(|| RefCell::new(SurfaceBufferData::default()));
                    if let Some(buffer_data) = data.data_map.get::<RefCell<SurfaceBufferData>>() {
                        let mut bd = buffer_data.borrow_mut();
                        bd.egl_texture = Some(EglTextureBuffer {
                            texture_id: imported.0,
                            width: imported.1,
                            height: imported.2,
                            egl_image: imported.3,
                        });
                        bd.needs_egl_import = false;
                    }
                });

                if log_frame {
                    info!("  Subsurface[{}] EGL IMPORT SUCCESS: texture {} ({}x{})",
                          idx, imported.0, imported.1, imported.2);
                }

                unsafe {
                    gl::render_egl_texture_at(imported.0, imported.1, imported.2,
                                              display.width, display.height, child_pos.x, child_pos.y);
                }
            } else if log_frame {
                info!("  Subsurface[{}] EGL import FAILED", idx);
            }
        } else if has_shm {
            // Render SHM buffer
            let pixels_info: Option<(u32, u32, Vec<u8>)> = compositor::with_states(child, |data| {
                if let Some(buffer_data) = data.data_map.get::<RefCell<SurfaceBufferData>>() {
                    let bd = buffer_data.borrow();
                    if let Some(ref stored) = bd.buffer {
                        return Some((stored.width, stored.height, stored.pixels.clone()));
                    }
                }
                None
            });

            if let Some((width, height, pixels)) = pixels_info {
                if log_frame {
                    info!("  Subsurface[{}] RENDERING SHM {}x{}", idx, width, height);
                }
                unsafe {
                    gl::render_texture_at(width, height, &pixels, display.width, display.height,
                                          child_pos.x, child_pos.y);
                }
            }
        }

        // Recursively render this child's subsurfaces
        render_subsurfaces(child, child_pos, display, log_frame, frame_num);
    }
}

/// Render a frame to the hwcomposer display
fn render_frame(
    display: &mut HwcDisplay,
    state: &Flick,
    _output: &Output,
) -> Result<()> {
    let frame_num = unsafe {
        RENDER_FRAME_COUNT += 1;
        RENDER_FRAME_COUNT
    };
    let log_frame = frame_num % 60 == 0;

    // Make our EGL context current
    display.egl_instance.make_current(
        display.egl_display,
        Some(display.egl_surface),
        Some(display.egl_surface),
        Some(display.egl_context),
    ).map_err(|e| anyhow::anyhow!("Failed to make context current: {:?}", e))?;

    // Calculate effect time for animated effects (living pixels, CRT flicker)
    let effect_time = unsafe {
        if gl::EFFECT_START_TIME.is_none() {
            gl::EFFECT_START_TIME = Some(std::time::Instant::now());
        }
        gl::EFFECT_START_TIME.unwrap().elapsed().as_secs_f32()
    };

    // Check if distortion effects will be active (for scene FBO rendering)
    // We need to know this early to decide whether to render to FBO or default framebuffer
    let shader_data_preview = state.touch_effects.get_shader_data(
        display.width as f64,
        display.height as f64,
        effect_time,
    );
    // Living pixels needs rendering even with no touches, CRT mode always renders
    let distortion_active = shader_data_preview.count > 0
        || shader_data_preview.effect_style == 2
        || shader_data_preview.living_pixels == 1;

    // If distortion is active, render to scene FBO instead of default framebuffer
    // This avoids the tiled GPU issue of reading from the framebuffer we're writing to
    let using_scene_fbo = if distortion_active {
        let result = unsafe { gl::begin_scene_render(display.width as u32, display.height as u32) };
        if log_frame {
            let fbo_support = unsafe { gl::has_fbo_support() };
            info!("Scene FBO: active={}, fbo_support={}, result={}", distortion_active, fbo_support, result);
        }
        result
    } else {
        false
    };

    // Set viewport to full screen (already set by begin_scene_render if using FBO)
    if !using_scene_fbo {
        unsafe {
            if let Some(f) = gl::FN_VIEWPORT {
                f(0, 0, display.width as i32, display.height as i32);
            }
        }
    }

    // Test mode disabled - QML lockscreen confirmed working
    let test_mode = false;

    if test_mode {
        // Cycle through bright colors: red, green, blue every 40 frames
        let color = match (frame_num / 40) % 3 {
            0 => [1.0f32, 0.0, 0.0, 1.0], // Red
            1 => [0.0, 1.0, 0.0, 1.0],    // Green
            _ => [0.0, 0.0, 1.0, 1.0],    // Blue
        };

        unsafe {
            gl::ClearColor(color[0], color[1], color[2], color[3]);
            gl::Clear(gl::COLOR_BUFFER_BIT);
            gl::Flush();
        }

        if log_frame || frame_num == 1 || frame_num == 40 || frame_num == 80 || frame_num == 120 {
            let (sw, sh) = (display.width, display.height);
            info!("Test mode frame {}: color=({:.1},{:.1},{:.1}) screen={}x{}",
                frame_num, color[0], color[1], color[2], sw, sh);
        }
    } else {
        // Normal rendering mode
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

        // Log status every 60 frames, or on any change
        static mut LAST_ELEMENT_COUNT: usize = 999;
        static mut LAST_QML_CONNECTED: bool = false;
        let element_changed = unsafe { LAST_ELEMENT_COUNT != element_count };
        let connected_changed = unsafe { LAST_QML_CONNECTED != qml_lockscreen_connected };

        if log_frame || element_changed || connected_changed {
            info!("RENDER frame {}: view={:?}, lock_active={}, elements={}, qml_connected={}",
                frame_num, shell_view, state.shell.lock_screen_active, element_count, qml_lockscreen_connected);
            unsafe {
                LAST_ELEMENT_COUNT = element_count;
                LAST_QML_CONNECTED = qml_lockscreen_connected;
            }
        }

        // Check if we're in a gesture that needs to preview the switcher
        let switcher_gesture_preview = state.switcher_gesture_active && shell_view == ShellView::App;

        // Render Slint UI for shell views (not for lock screen when QML is connected)
        // When QML lock screen is connected, render QML windows instead of Slint
        let render_slint_lock = shell_view == ShellView::LockScreen && !qml_lockscreen_connected;
        if !qml_lockscreen_connected || render_slint_lock {
            match shell_view {
                ShellView::Home | ShellView::QuickSettings | ShellView::Switcher | ShellView::PickDefault
                if !switcher_gesture_preview => {
                    // Update Slint timers and animations (needed for clock updates, etc.)
                    slint::platform::update_timers_and_animations();

                    // Set up Slint UI state based on current view
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        match shell_view {
                            ShellView::Home => {
                                slint_ui.set_view("home");
                                let slint_categories = state.shell.get_categories_with_icons();
                                slint_ui.set_categories(slint_categories);
                                slint_ui.set_show_popup(state.shell.popup_showing);
                                slint_ui.set_wiggle_mode(state.shell.wiggle_mode);

                                // Update wiggle mode animation and state
                                if state.shell.wiggle_mode {
                                    // Update wiggle animation time
                                    if let Some(start) = state.shell.wiggle_start_time {
                                        let elapsed = start.elapsed().as_secs_f32();
                                        slint_ui.set_wiggle_time(elapsed);
                                    }

                                    // Sync drag state to Slint
                                    let drag_idx = state.shell.dragging_index.map(|i| i as i32).unwrap_or(-1);
                                    slint_ui.set_dragging_index(drag_idx);
                                    if let Some(pos) = state.shell.drag_position {
                                        slint_ui.set_drag_position(pos.x as f32, pos.y as f32);
                                    }

                                    // Check wiggle done button - handled in main loop with mutable state
                                    // (can't mutate here since render_frame takes immutable state)
                                }

                                // Update time for status bar
                                let now = chrono::Local::now();
                                slint_ui.set_time(&now.format("%H:%M").to_string());
                                // Update battery from system info
                                slint_ui.set_battery_percent(state.shell.quick_settings.battery_percent as i32);
                                // Update text scale from settings
                                slint_ui.set_text_scale(state.shell.text_scale);
                            }
                            ShellView::QuickSettings => {
                                slint_ui.set_view("quick-settings");
                                slint_ui.set_brightness(state.shell.quick_settings.brightness);
                                slint_ui.set_volume(state.system.volume as i32);
                                slint_ui.set_muted(state.system.muted);
                                slint_ui.set_wifi_enabled(state.system.wifi_enabled);
                                slint_ui.set_bluetooth_enabled(state.system.bluetooth_enabled);
                                // UI icons are loaded when QuickSettings is first opened (see edge gesture handler)
                            }
                            ShellView::Switcher => {
                                slint_ui.set_view("switcher");
                                slint_ui.set_switcher_scroll(state.shell.switcher_scroll as f32);
                                // Update enter animation progress
                                let enter_progress = state.shell.get_switcher_enter_progress();
                                slint_ui.set_switcher_enter_progress(enter_progress);
                                // Update window list for Slint Switcher
                                let windows: Vec<_> = state.space.elements()
                                    .enumerate()
                                    .map(|(i, window)| {
                                        // Try X11 surface first, then Wayland toplevel, fall back to generic name
                                        let title = if let Some(x11) = window.x11_surface() {
                                            let t = x11.title();
                                            if !t.is_empty() { t } else { x11.class() }
                                        } else if let Some(toplevel) = window.toplevel() {
                                            compositor::with_states(toplevel.wl_surface(), |states| {
                                                states
                                                    .data_map
                                                    .get::<smithay::wayland::shell::xdg::XdgToplevelSurfaceData>()
                                                    .and_then(|data| {
                                                        let data = data.lock().unwrap();
                                                        let title = data.title.clone();
                                                        if title.as_ref().map(|t| !t.is_empty()).unwrap_or(false) {
                                                            title
                                                        } else {
                                                            data.app_id.clone()
                                                        }
                                                    })
                                            }).unwrap_or_else(|| format!("Window {}", i + 1))
                                        } else {
                                            format!("Window {}", i + 1)
                                        };

                                        let app_class = if let Some(x11) = window.x11_surface() {
                                            x11.class()
                                        } else if let Some(toplevel) = window.toplevel() {
                                            compositor::with_states(toplevel.wl_surface(), |states| {
                                                states
                                                    .data_map
                                                    .get::<smithay::wayland::shell::xdg::XdgToplevelSurfaceData>()
                                                    .and_then(|data| data.lock().unwrap().app_id.clone())
                                            }).unwrap_or_else(|| "app".to_string())
                                        } else {
                                            "app".to_string()
                                        };

                                        // Capture window preview from SHM buffer or EGL texture
                                        let preview: Option<slint::Image> = if let Some(toplevel) = window.toplevel() {
                                            compositor::with_states(toplevel.wl_surface(), |states| {
                                                use std::cell::RefCell;
                                                use crate::state::SurfaceBufferData;
                                                if let Some(buffer_data) = states.data_map.get::<RefCell<SurfaceBufferData>>() {
                                                    let bd = buffer_data.borrow();
                                                    // First try SHM buffer (software rendered apps)
                                                    if let Some(ref buffer) = bd.buffer {
                                                        let pixel_buffer = slint::SharedPixelBuffer::<slint::Rgba8Pixel>::clone_from_slice(
                                                            &buffer.pixels,
                                                            buffer.width,
                                                            buffer.height,
                                                        );
                                                        Some(slint::Image::from_rgba8(pixel_buffer))
                                                    } else if let Some(ref egl_tex) = bd.egl_texture {
                                                        // Try reading from EGL texture (hardware rendered apps)
                                                        unsafe {
                                                            if let Some(pixels) = gl::read_texture_pixels(egl_tex.texture_id, egl_tex.width, egl_tex.height) {
                                                                let pixel_buffer = slint::SharedPixelBuffer::<slint::Rgba8Pixel>::clone_from_slice(
                                                                    &pixels,
                                                                    egl_tex.width,
                                                                    egl_tex.height,
                                                                );
                                                                Some(slint::Image::from_rgba8(pixel_buffer))
                                                            } else {
                                                                None
                                                            }
                                                        }
                                                    } else {
                                                        None
                                                    }
                                                } else {
                                                    None
                                                }
                                            })
                                        } else {
                                            None
                                        };

                                        (i as i32, title, app_class, i as i32, preview)
                                    })
                                    .collect();

                                // Sort by render order: furthest from center first, center last
                                // This ensures center card renders on top
                                let scroll = state.shell.switcher_scroll;
                                let screen_w = state.screen_size.w as f64;
                                let card_spacing = screen_w * 0.80 * 0.35;
                                let mut windows = windows;
                                windows.sort_by(|a, b| {
                                    let dist_a = ((a.3 as f64) * card_spacing - scroll).abs();
                                    let dist_b = ((b.3 as f64) * card_spacing - scroll).abs();
                                    // Reverse order: larger distance first (renders behind)
                                    dist_b.partial_cmp(&dist_a).unwrap_or(std::cmp::Ordering::Equal)
                                });

                                if log_frame {
                                    info!("Switcher: {} windows in space", windows.len());
                                }
                                slint_ui.set_switcher_windows(windows);
                            }
                            ShellView::PickDefault => {
                                slint_ui.set_view("pick-default");
                                if let Some(category) = state.shell.popup_category {
                                    slint_ui.set_pick_default_category(category.display_name());
                                    // Get available apps for this category (includes discovered + Flick apps)
                                    let apps = state.shell.app_manager.apps_for_category(category);
                                    let mut available_apps: Vec<(String, String)> = apps
                                        .iter()
                                        .map(|app| (app.name.clone(), app.exec.clone()))
                                        .collect();

                                    // Always add Flick native app if it exists and not already in list
                                    let flick_exec = format!(r#"sh -c "$HOME/Flick/apps/{}/run_{}.sh""#,
                                        category.display_name().to_lowercase(),
                                        category.display_name().to_lowercase());
                                    let flick_name = format!("Flick {}", category.display_name());
                                    if !available_apps.iter().any(|(_, exec)| exec.contains("/Flick/apps/")) {
                                        available_apps.insert(0, (flick_name, flick_exec));
                                    }

                                    slint_ui.set_available_apps(available_apps);
                                    // Set current selection and check if it's a Flick default
                                    if let Some(exec) = state.shell.app_manager.get_exec(category) {
                                        slint_ui.set_current_app_selection(&exec);
                                        // Check if using Flick default by looking at the exec path
                                        let is_flick_default = exec.contains("/Flick/apps/");
                                        slint_ui.set_using_flick_default(is_flick_default);
                                    } else {
                                        slint_ui.set_using_flick_default(true);
                                    }
                                }
                            }
                            _ => {}
                        }
                    }

                    // Get Slint rendered pixels
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        if let Some((width, height, pixels)) = slint_ui.render() {
                            // Only log periodically to reduce spam
                            if log_frame {
                                info!("SLINT RENDER frame {}: {}x{}", frame_num, width, height);
                            }
                            unsafe {
                                gl::render_texture(width, height, &pixels, display.width, display.height);
                            }
                        }
                    }
                }
                _ => {}
            }

            // Volume overlay - shown on top of ALL views when hardware buttons pressed
            // This must be outside the view-specific match so it works in App view too
            if let Some(ref slint_ui) = state.shell.slint_ui {
                slint_ui.set_show_volume_overlay(state.system.should_show_volume_overlay());
                slint_ui.set_volume(state.system.volume as i32);
                slint_ui.set_muted(state.system.muted);
            }

            // Render switcher preview during edge gesture (while still in App view)
            if switcher_gesture_preview {
                slint::platform::update_timers_and_animations();

                if let Some(ref slint_ui) = state.shell.slint_ui {
                    slint_ui.set_view("switcher");
                    // Use gesture progress to drive the shrink animation
                    // gesture_progress goes 0.0 -> 1.0 as you drag
                    let enter_progress = state.switcher_gesture_progress as f32;
                    slint_ui.set_switcher_enter_progress(enter_progress);

                    // Update window list for preview
                    let screen_w = state.screen_size.w as f64;
                    let card_width = screen_w * 0.80;
                    let card_spacing = card_width * 0.35;
                    let num_windows = state.space.elements().count();

                    // Use same scroll as when switcher opens: center the topmost (last) window
                    let scroll = if num_windows > 0 {
                        (num_windows - 1) as f64 * card_spacing
                    } else {
                        0.0
                    };
                    slint_ui.set_switcher_scroll(scroll as f32);

                    let windows: Vec<_> = state.space.elements()
                        .enumerate()
                        .map(|(i, window)| {
                            let title = if let Some(x11) = window.x11_surface() {
                                let t = x11.title();
                                if !t.is_empty() { t } else { x11.class() }
                            } else if let Some(toplevel) = window.toplevel() {
                                compositor::with_states(toplevel.wl_surface(), |states| {
                                    states
                                        .data_map
                                        .get::<smithay::wayland::shell::xdg::XdgToplevelSurfaceData>()
                                        .and_then(|data| {
                                            let data = data.lock().unwrap();
                                            data.title.clone().or(data.app_id.clone())
                                        })
                                }).unwrap_or_else(|| format!("Window {}", i + 1))
                            } else {
                                format!("Window {}", i + 1)
                            };

                            let app_class = if let Some(x11) = window.x11_surface() {
                                x11.class()
                            } else if let Some(toplevel) = window.toplevel() {
                                compositor::with_states(toplevel.wl_surface(), |states| {
                                    states
                                        .data_map
                                        .get::<smithay::wayland::shell::xdg::XdgToplevelSurfaceData>()
                                        .and_then(|data| data.lock().unwrap().app_id.clone())
                                }).unwrap_or_else(|| "app".to_string())
                            } else {
                                "app".to_string()
                            };

                            // Capture window preview from SHM buffer or EGL texture
                            let preview: Option<slint::Image> = if let Some(toplevel) = window.toplevel() {
                                compositor::with_states(toplevel.wl_surface(), |states| {
                                    use std::cell::RefCell;
                                    use crate::state::SurfaceBufferData;
                                    if let Some(buffer_data) = states.data_map.get::<RefCell<SurfaceBufferData>>() {
                                        let bd = buffer_data.borrow();
                                        // First try SHM buffer (software rendered apps)
                                        if let Some(ref buffer) = bd.buffer {
                                            // Convert RGBA pixels to slint::Image
                                            let pixel_buffer = slint::SharedPixelBuffer::<slint::Rgba8Pixel>::clone_from_slice(
                                                &buffer.pixels,
                                                buffer.width,
                                                buffer.height,
                                            );
                                            Some(slint::Image::from_rgba8(pixel_buffer))
                                        } else if let Some(ref egl_tex) = bd.egl_texture {
                                            // Try reading from EGL texture (hardware rendered apps)
                                            unsafe {
                                                if let Some(pixels) = gl::read_texture_pixels(egl_tex.texture_id, egl_tex.width, egl_tex.height) {
                                                    let pixel_buffer = slint::SharedPixelBuffer::<slint::Rgba8Pixel>::clone_from_slice(
                                                        &pixels,
                                                        egl_tex.width,
                                                        egl_tex.height,
                                                    );
                                                    Some(slint::Image::from_rgba8(pixel_buffer))
                                                } else {
                                                    None
                                                }
                                            }
                                        } else {
                                            None
                                        }
                                    } else {
                                        None
                                    }
                                })
                            } else {
                                None
                            };

                            (i as i32, title, app_class, i as i32, preview)
                        })
                        .collect();

                    // Sort by render order (furthest from center first, using same scroll)
                    let mut windows = windows;
                    windows.sort_by(|a, b| {
                        let dist_a = ((a.3 as f64) * card_spacing - scroll).abs();
                        let dist_b = ((b.3 as f64) * card_spacing - scroll).abs();
                        dist_b.partial_cmp(&dist_a).unwrap_or(std::cmp::Ordering::Equal)
                    });

                    slint_ui.set_switcher_windows(windows);

                    // Render the switcher preview
                    if let Some((width, height, pixels)) = slint_ui.render() {
                        unsafe {
                            gl::render_texture(width, height, &pixels, display.width, display.height);
                        }
                    }
                }
            }
        }

        // Render QML lock screen window when on lock screen with QML connected
        if shell_view == ShellView::LockScreen && qml_lockscreen_connected {
            let windows: Vec<_> = state.space.elements().cloned().collect();
            for window in windows.iter() {
                let wl_surface = if let Some(toplevel) = window.toplevel() {
                    Some(toplevel.wl_surface().clone())
                } else {
                    None
                };

                if let Some(wl_surface) = wl_surface {
                    // Check if we need to import EGL buffer
                    let (needs_import, egl_texture_info) = compositor::with_states(&wl_surface, |data| {
                        use std::cell::RefCell;
                        use crate::state::SurfaceBufferData;

                        if let Some(buffer_data) = data.data_map.get::<RefCell<SurfaceBufferData>>() {
                            let bd = buffer_data.borrow();
                            let egl_info = bd.egl_texture.as_ref().map(|t| (t.texture_id, t.width, t.height));
                            (bd.needs_egl_import, egl_info)
                        } else {
                            (false, None)
                        }
                    });

                    // Try EGL import if needed
                    if needs_import {
                        if let Some(imported) = try_import_egl_buffer(&wl_surface, display) {
                            compositor::with_states(&wl_surface, |data| {
                                use std::cell::RefCell;
                                use crate::state::{SurfaceBufferData, EglTextureBuffer};
                                data.data_map.insert_if_missing(|| RefCell::new(SurfaceBufferData::default()));
                                if let Some(buffer_data) = data.data_map.get::<RefCell<SurfaceBufferData>>() {
                                    let mut bd = buffer_data.borrow_mut();
                                    bd.egl_texture = Some(EglTextureBuffer {
                                        texture_id: imported.0,
                                        width: imported.1,
                                        height: imported.2,
                                        egl_image: imported.3,
                                    });
                                    bd.needs_egl_import = false;
                                    bd.wl_buffer_ptr = None;
                                    if let Some(buffer) = bd.pending_buffer.take() {
                                        buffer.release();
                                    }
                                }
                            });
                            // Render the newly imported texture
                            unsafe {
                                gl::render_egl_texture_at(imported.0, imported.1, imported.2, display.width, display.height, 0, 0);
                            }
                        }
                    } else if let Some((texture_id, width, height)) = egl_texture_info {
                        // Render existing EGL texture
                        unsafe {
                            gl::render_egl_texture_at(texture_id, width, height, display.width, display.height, 0, 0);
                        }
                    } else {
                        // Fallback to SHM buffer
                        let buffer_info: Option<(u32, u32, Vec<u8>)> = compositor::with_states(&wl_surface, |data| {
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

                        if let Some((width, height, pixels)) = buffer_info {
                            unsafe {
                                gl::render_texture(width, height, &pixels, display.width, display.height);
                            }
                        }
                    }
                }
            }
        }

        // Render Slint fallback for lock screen when QML is not yet connected
        if shell_view == ShellView::LockScreen && !qml_lockscreen_connected {
            slint::platform::update_timers_and_animations();
            if let Some(ref slint_ui) = state.shell.slint_ui {
                slint_ui.set_view("lock");
                if let Some((width, height, pixels)) = slint_ui.render() {
                    unsafe {
                        gl::render_texture(width, height, &pixels, display.width, display.height);
                    }
                }
            }
        }

        // Render Wayland windows ONLY for App view (not during switcher gesture preview)
        if shell_view == ShellView::App && !switcher_gesture_preview && !state.shell.lock_screen_active {
            // Render ONLY the topmost Wayland client surface (last in elements order)
            // This ensures only the active window is visible and receives input
            let windows: Vec<_> = state.space.elements().cloned().collect();
            debug!("Rendering {} Wayland windows", windows.len());

            // Only render the LAST (topmost) window
            let start_idx = if windows.len() > 0 { windows.len() - 1 } else { 0 };
            for (i, window) in windows.iter().enumerate().skip(start_idx) {
                debug!("Processing window {}", i);

                // Get the wl_surface from either Wayland toplevel or X11 surface
                let wl_surface = if let Some(toplevel) = window.toplevel() {
                    debug!("Window {} is Wayland toplevel", i);
                    Some(toplevel.wl_surface().clone())
                } else if let Some(x11_surface) = window.x11_surface() {
                    debug!("Window {} is X11 surface", i);
                    x11_surface.wl_surface().map(|s| s.clone())
                } else {
                    debug!("Window {} has no surface", i);
                    None
                };

                if let Some(wl_surface) = wl_surface {
                    debug!("Window {} surface: {:?}", i, wl_surface.id());

                    // Render using stored buffer data from commit handler
                    debug!("Window {} trying to render stored buffer", i);

                    // Check buffer state - do we need to (re-)import?
                    let (needs_import, has_shm, egl_texture_info) = compositor::with_states(&wl_surface, |data| {
                        use std::cell::RefCell;
                        use crate::state::SurfaceBufferData;

                        if let Some(buffer_data) = data.data_map.get::<RefCell<SurfaceBufferData>>() {
                            let bd = buffer_data.borrow();
                            let egl_info = bd.egl_texture.as_ref().map(|t| (t.texture_id, t.width, t.height));
                            (bd.needs_egl_import, bd.buffer.is_some(), egl_info)
                        } else {
                            (false, false, None)
                        }
                    });

                    // If we need to import (new buffer arrived), do it now
                    if needs_import {
                        if log_frame {
                            info!("Window {} needs EGL re-import", i);
                        }
                        if let Some(imported) = try_import_egl_buffer(&wl_surface, display) {
                            // Store the imported texture and release the buffer
                            compositor::with_states(&wl_surface, |data| {
                                use std::cell::RefCell;
                                use crate::state::{SurfaceBufferData, EglTextureBuffer};
                                data.data_map.insert_if_missing(|| RefCell::new(SurfaceBufferData::default()));
                                if let Some(buffer_data) = data.data_map.get::<RefCell<SurfaceBufferData>>() {
                                    let mut bd = buffer_data.borrow_mut();
                                    bd.egl_texture = Some(EglTextureBuffer {
                                        texture_id: imported.0,
                                        width: imported.1,
                                        height: imported.2,
                                        egl_image: imported.3,
                                    });
                                    bd.needs_egl_import = false;
                                    bd.wl_buffer_ptr = None; // Clear after import
                                    // Release the buffer so client can reuse it
                                    if let Some(buffer) = bd.pending_buffer.take() {
                                        buffer.release();
                                        info!("Released wl_buffer after EGL import");
                                    }
                                }
                            });

                            // Render the newly imported texture
                            let window_pos = state.space.element_location(window).unwrap_or_default();
                            if log_frame {
                                info!("EGL IMPORT+RENDER[{}] frame {}: texture_id={}, {}x{}", i, frame_num, imported.0, imported.1, imported.2);
                            }
                            unsafe {
                                gl::render_egl_texture_at(imported.0, imported.1, imported.2, display.width, display.height,
                                                           window_pos.x, window_pos.y);
                            }
                        } else {
                            // EGL import failed - clear the flag and try to use cached texture
                            if log_frame {
                                info!("EGL IMPORT FAILED[{}] frame {}, trying cached texture", i, frame_num);
                            }
                            compositor::with_states(&wl_surface, |data| {
                                use std::cell::RefCell;
                                use crate::state::SurfaceBufferData;
                                if let Some(buffer_data) = data.data_map.get::<RefCell<SurfaceBufferData>>() {
                                    let mut bd = buffer_data.borrow_mut();
                                    bd.needs_egl_import = false; // Don't retry on every frame
                                }
                            });
                            // Try to use existing cached texture as fallback
                            if let Some((texture_id, width, height)) = egl_texture_info {
                                let window_pos = state.space.element_location(window).unwrap_or_default();
                                if log_frame {
                                    info!("EGL FALLBACK[{}] frame {}: using cached texture_id={}", i, frame_num, texture_id);
                                }
                                unsafe {
                                    gl::render_egl_texture_at(texture_id, width, height, display.width, display.height,
                                                               window_pos.x, window_pos.y);
                                }
                            }
                        }
                    } else if let Some((texture_id, width, height)) = egl_texture_info {
                        // Use existing cached EGL texture
                        let window_pos = state.space.element_location(window).unwrap_or_default();
                        if log_frame {
                            info!("EGL RENDER[{}] frame {}: texture_id={}, {}x{}", i, frame_num, texture_id, width, height);
                        }
                        unsafe {
                            gl::render_egl_texture_at(texture_id, width, height, display.width, display.height,
                                                       window_pos.x, window_pos.y);
                        }
                    }

                    // Get stored SHM buffer from surface user data (fallback)
                    let buffer_info: Option<(u32, u32, Vec<u8>)> = compositor::with_states(&wl_surface, |data| {
                        debug!("  stored: inside with_states");
                        use std::cell::RefCell;
                        use crate::state::SurfaceBufferData;

                        if let Some(buffer_data) = data.data_map.get::<RefCell<SurfaceBufferData>>() {
                            let data = buffer_data.borrow();
                            // Skip if we already rendered via EGL
                            if data.egl_texture.is_some() {
                                return None;
                            }
                            if let Some(ref stored) = data.buffer {
                                debug!("  stored: found buffer {}x{}", stored.width, stored.height);
                                Some((stored.width, stored.height, stored.pixels.clone()))
                            } else {
                                debug!("  stored: no buffer in data_map");
                                None
                            }
                        } else {
                            debug!("  stored: no SurfaceBufferData in data_map");
                            None
                        }
                    });
                    debug!("Window {} after with_states", i);

                    // Render SHM buffer outside of with_states to avoid holding locks
                    if let Some((width, height, pixels)) = buffer_info {
                        // Get window position from space (for close gesture animation)
                        let window_pos = state.space.element_location(window)
                            .unwrap_or_default();

                        // Log periodically - check center pixel and client ID
                        if log_frame && pixels.len() >= 4 {
                            let center_x = width / 2;
                            let center_y = height / 2; // Actual center
                            let center_idx = ((center_y * width + center_x) * 4) as usize;
                            let (cr, cg, cb, ca) = if center_idx + 3 < pixels.len() {
                                (pixels[center_idx], pixels[center_idx+1], pixels[center_idx+2], pixels[center_idx+3])
                            } else {
                                (0, 0, 0, 0)
                            };
                            let window_type = if window.toplevel().is_some() { "Wayland" } else { "X11" };
                            let client_info = wl_surface.client().map(|c| format!("{:?}", c.id())).unwrap_or_else(|| "no-client".to_string());
                            info!("{} RENDER[{}] frame {}: {}x{} center_pixel=RGBA({},{},{},{}) client={}",
                                window_type, i, frame_num, width, height, cr, cg, cb, ca, client_info);
                        }

                        // Use positioned rendering to support close gesture animation
                        unsafe {
                            gl::render_texture_at(width, height, &pixels, display.width, display.height,
                                                   window_pos.x, window_pos.y);
                        }
                    } else if log_frame {
                        let window_type = if window.toplevel().is_some() { "Wayland" } else { "X11" };
                        info!("{} NO BUFFER frame {}: window {} has no stored buffer", window_type, frame_num, i);
                    }

                    // === RENDER SUBSURFACES ===
                    // Camera preview and other video surfaces are subsurfaces
                    // They may use EGL/dmabuf buffers for hardware-accelerated rendering
                    let window_pos = state.space.element_location(window).unwrap_or_default();
                    render_subsurfaces(&wl_surface, window_pos, display, log_frame, frame_num);
                }
            }
            debug!("Finished rendering windows");

            // Render Slint keyboard overlay on top of app window if keyboard is visible
            if let Some(ref slint_ui) = state.shell.slint_ui {
                if slint_ui.is_keyboard_visible() {
                    slint::platform::update_timers_and_animations();
                    slint_ui.set_view("app");  // Use app view to show only keyboard overlay
                    if let Some((width, height, pixels)) = slint_ui.render() {
                        if log_frame {
                            info!("KEYBOARD OVERLAY frame {}: {}x{}", frame_num, width, height);
                        }
                        unsafe {
                            gl::render_texture(width, height, &pixels, display.width, display.height);
                        }
                    }
                }
            }
        }
    }

    // End scene FBO rendering if active, switch back to default framebuffer
    if using_scene_fbo {
        unsafe {
            gl::end_scene_render();
            // Reset viewport for default framebuffer
            if let Some(f) = gl::FN_VIEWPORT {
                f(0, 0, display.width as i32, display.height as i32);
            }
        }
    }

    // Render touch distortion effects (fisheye while touching, ripple on release)
    // Also render continuously for ASCII mode (style 2)
    // Use the shader_data we already computed at the start
    if distortion_active {
        if log_frame {
            info!("DISTORTION frame {}: {} effects, style {}, scene_fbo={}",
                frame_num, shader_data_preview.count, shader_data_preview.effect_style, using_scene_fbo);
        }
        unsafe {
            gl::render_distortion(
                display.width as u32,
                display.height as u32,
                &shader_data_preview,
                using_scene_fbo, // Pass whether we're using scene texture
            );
        }
    }

    debug!("render_frame: before swap_buffers");
    // Swap EGL buffers - this triggers the present callback which handles display
    display.egl_instance.swap_buffers(display.egl_display, display.egl_surface)
        .map_err(|e| anyhow::anyhow!("Failed to swap buffers: {:?}", e))?;

    Ok(())
}

// OpenGL ES 2.0 bindings for texture rendering
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
    type DeleteShaderFn = unsafe extern "C" fn(u32);
    type DeleteProgramFn = unsafe extern "C" fn(u32);
    type GetErrorFn = unsafe extern "C" fn() -> u32;
    type FlushFn = unsafe extern "C" fn();
    type FinishFn = unsafe extern "C" fn();
    type CopyTexImage2DFn = unsafe extern "C" fn(u32, i32, u32, i32, i32, i32, i32, i32);
    type Uniform1fFn = unsafe extern "C" fn(i32, f32);
    type Uniform2fvFn = unsafe extern "C" fn(i32, i32, *const f32);
    type Uniform4fvFn = unsafe extern "C" fn(i32, i32, *const f32);
    type GetIntegervFn = unsafe extern "C" fn(u32, *mut i32);

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
    static mut FN_DELETE_SHADER: Option<DeleteShaderFn> = None;
    static mut FN_DELETE_PROGRAM: Option<DeleteProgramFn> = None;
    static mut FN_GET_ERROR: Option<GetErrorFn> = None;
    static mut FN_FLUSH: Option<FlushFn> = None;
    static mut FN_FINISH: Option<FinishFn> = None;
    static mut FN_COPY_TEX_IMAGE_2D: Option<CopyTexImage2DFn> = None;
    static mut FN_UNIFORM1F: Option<Uniform1fFn> = None;
    static mut FN_UNIFORM2FV: Option<Uniform2fvFn> = None;
    static mut FN_UNIFORM4FV: Option<Uniform4fvFn> = None;

    static mut INITIALIZED: bool = false;
    static mut SHADER_PROGRAM: u32 = 0;
    static mut ATTR_POSITION: i32 = -1;
    static mut ATTR_TEXCOORD: i32 = -1;
    static mut UNIFORM_TEXTURE: i32 = -1;

    // Distortion shader program and uniforms
    static mut DISTORT_PROGRAM: u32 = 0;
    static mut DISTORT_ATTR_POSITION: i32 = -1;
    static mut DISTORT_ATTR_TEXCOORD: i32 = -1;
    static mut DISTORT_UNIFORM_TEXTURE: i32 = -1;
    static mut DISTORT_UNIFORM_POSITIONS: i32 = -1;
    static mut DISTORT_UNIFORM_PARAMS: i32 = -1;
    static mut DISTORT_UNIFORM_COUNT: i32 = -1;
    static mut DISTORT_UNIFORM_ASPECT: i32 = -1;
    static mut DISTORT_UNIFORM_STYLE: i32 = -1;
    static mut DISTORT_UNIFORM_DENSITY: i32 = -1;
    static mut DISTORT_UNIFORM_LIVING: i32 = -1;
    static mut DISTORT_UNIFORM_TIME: i32 = -1;
    static mut DISTORT_UNIFORM_LP_FLAGS: i32 = -1;
    static mut DISTORT_UNIFORM_TOUCH_X: i32 = -1;
    static mut DISTORT_UNIFORM_TOUCH_Y: i32 = -1;
    static mut DISTORT_UNIFORM_TOUCH_TIME: i32 = -1;

    // Time tracking for animated effects
    pub static mut EFFECT_START_TIME: Option<std::time::Instant> = None;

    // Persistent capture texture for distortion effects (avoids create/delete each frame)
    static mut CAPTURE_TEXTURE: u32 = 0;
    static mut CAPTURE_TEX_WIDTH: u32 = 0;
    static mut CAPTURE_TEX_HEIGHT: u32 = 0;

    // FBO for reliable framebuffer capture (avoids tile-based GPU issues)
    static mut CAPTURE_FBO: u32 = 0;
    static mut FBO_TEXTURE: u32 = 0;
    static mut FBO_WIDTH: u32 = 0;
    static mut FBO_HEIGHT: u32 = 0;

    // Scene FBO - render everything here first, then use for distortion
    // This avoids the tiled GPU issue of reading from the framebuffer we're writing to
    static mut SCENE_FBO: u32 = 0;
    static mut SCENE_TEXTURE: u32 = 0;
    static mut SCENE_WIDTH: u32 = 0;
    static mut SCENE_HEIGHT: u32 = 0;
    static mut SCENE_RENDERING_ACTIVE: bool = false;

    // FBO function pointers
    static mut FN_GEN_FRAMEBUFFERS: Option<unsafe extern "C" fn(i32, *mut u32)> = None;
    static mut FN_BIND_FRAMEBUFFER: Option<unsafe extern "C" fn(u32, u32)> = None;
    static mut FN_FRAMEBUFFER_TEXTURE_2D: Option<unsafe extern "C" fn(u32, u32, u32, u32, i32)> = None;
    static mut FN_CHECK_FRAMEBUFFER_STATUS: Option<unsafe extern "C" fn(u32) -> u32> = None;
    static mut FN_DELETE_FRAMEBUFFERS: Option<unsafe extern "C" fn(i32, *const u32)> = None;
    static mut FN_BLIT_FRAMEBUFFER: Option<unsafe extern "C" fn(i32, i32, i32, i32, i32, i32, i32, i32, u32, u32)> = None;
    static mut FN_READ_PIXELS: Option<unsafe extern "C" fn(i32, i32, i32, i32, u32, u32, *mut c_void)> = None;
    static mut FN_GET_INTEGERV: Option<GetIntegervFn> = None;

    // Persistent FBO for texture readback (avoid recreating each time)
    static mut READBACK_FBO: u32 = 0;

    // GL state query constants
    const GL_FRAMEBUFFER_BINDING: u32 = 0x8CA6;
    const GL_VIEWPORT_BINDING: u32 = 0x0BA2;  // GL_VIEWPORT
    const GL_TEXTURE_BINDING_2D: u32 = 0x8069;
    const GL_CURRENT_PROGRAM: u32 = 0x8B8D;

    // FBO constants
    const GL_FRAMEBUFFER: u32 = 0x8D40;
    const GL_READ_FRAMEBUFFER: u32 = 0x8CA8;
    const GL_DRAW_FRAMEBUFFER: u32 = 0x8CA9;
    const GL_COLOR_ATTACHMENT0: u32 = 0x8CE0;
    const GL_FRAMEBUFFER_COMPLETE: u32 = 0x8CD5;
    const GL_COLOR_BUFFER_BIT_BLIT: u32 = 0x00004000;
    const GL_NEAREST: u32 = 0x2600;

    // Vertex shader - simple pass-through
    const VERTEX_SHADER_SRC: &str = r#"
        attribute vec2 a_position;
        attribute vec2 a_texcoord;
        varying vec2 v_texcoord;
        void main() {
            gl_Position = vec4(a_position, 0.0, 1.0);
            v_texcoord = a_texcoord;
        }
    "#;

    // Fragment shader - texture sampling
    const FRAGMENT_SHADER_SRC: &str = r#"
        precision mediump float;
        varying vec2 v_texcoord;
        uniform sampler2D u_texture;
        void main() {
            gl_FragColor = texture2D(u_texture, v_texcoord);
        }
    "#;

    // Distortion fragment shader - STABLE version
    // Style: 0=water, 1=snow (ice crystals), 2=CRT, 3=terminal_ripple
    // Living pixels: overlay that adds twinkling stars to black, blinking eyes to white
    const DISTORT_FRAGMENT_SRC: &str = r#"
        precision highp float;
        varying vec2 v_texcoord;
        uniform sampler2D u_texture;
        uniform vec2 u_positions[10];
        uniform vec4 u_params[10];
        uniform int u_count;
        uniform float u_aspect;
        uniform int u_style;
        uniform float u_density;
        uniform int u_living;
        uniform float u_time;
        uniform int u_lp_flags;     // Sub-toggles: bit0=stars, bit1=shooting, bit2=fireflies, bit3=dust, bit4=shimmer, bit5=eyes
        uniform float u_touch_x;    // Last touch X (normalized 0-1)
        uniform float u_touch_y;    // Last touch Y (normalized 0-1)
        uniform float u_touch_time; // Seconds since last touch

        float hash(vec2 p) {
            return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
        }

        float hash2(vec2 p) {
            return fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453);
        }

        float hash3(vec2 p, float t) {
            return fract(sin(dot(p, vec2(127.1, 311.7)) + t * 0.1) * 43758.5453);
        }

        // ASCII character bitmaps - 5x7 font patterns (16 levels)
        float getCharPixel(int charIdx, vec2 pos) {
            int px = int(pos.x * 5.0);
            int py = int(pos.y * 7.0);
            if (px < 0 || px > 4 || py < 0 || py > 6) return 0.0;
            int row = 6 - py;

            if (charIdx == 0) return 0.0; // space
            if (charIdx == 1) { if (row == 0 && px == 2) return 1.0; return 0.0; } // .
            if (charIdx == 2) { if ((row == 0 || row == 1) && px == 2) return 1.0; return 0.0; } // ,
            if (charIdx == 3) { if ((row == 1 || row == 4) && px == 2) return 1.0; return 0.0; } // :
            if (charIdx == 4) { if ((row == 0 || row == 1 || row == 4) && px == 2) return 1.0; return 0.0; } // ;
            if (charIdx == 5) { // i
                if (row == 5 && px == 2) return 1.0;
                if (row >= 0 && row <= 3 && px == 2) return 1.0;
                if (row == 0 && (px == 1 || px == 3)) return 1.0;
                return 0.0;
            }
            if (charIdx == 6) { // l
                if (px == 2 && row >= 0 && row <= 5) return 1.0;
                if (row == 0 && px == 3) return 1.0;
                return 0.0;
            }
            if (charIdx == 7) { // c
                if ((row == 0 || row == 3) && px >= 1 && px <= 3) return 1.0;
                if (px == 0 && row >= 1 && row <= 2) return 1.0;
                return 0.0;
            }
            if (charIdx == 8) { // r
                if (px == 1 && row >= 0 && row <= 3) return 1.0;
                if (row == 3 && px >= 2 && px <= 3) return 1.0;
                return 0.0;
            }
            if (charIdx == 9) { // x
                if ((px == 0 || px == 4) && (row == 0 || row == 3)) return 1.0;
                if ((px == 1 || px == 3) && (row == 1 || row == 2)) return 1.0;
                return 0.0;
            }
            if (charIdx == 10) { // o
                if ((row == 0 || row == 3) && px >= 1 && px <= 3) return 1.0;
                if ((px == 0 || px == 4) && row >= 1 && row <= 2) return 1.0;
                return 0.0;
            }
            if (charIdx == 11) { // a
                if (row == 0 && px >= 1 && px <= 4) return 1.0;
                if (row == 2 && px >= 1 && px <= 4) return 1.0;
                if (row == 3 && px >= 1 && px <= 3) return 1.0;
                if (px == 4 && row >= 0 && row <= 2) return 1.0;
                return 0.0;
            }
            if (charIdx == 12) { // #
                if ((px == 1 || px == 3) && row >= 1 && row <= 5) return 1.0;
                if ((row == 2 || row == 4) && px >= 0 && px <= 4) return 1.0;
                return 0.0;
            }
            if (charIdx == 13) { // W
                if ((px == 0 || px == 4) && row >= 0 && row <= 5) return 1.0;
                if (px == 2 && row >= 0 && row <= 3) return 1.0;
                return 0.0;
            }
            if (charIdx == 14) { // M
                if ((px == 0 || px == 4) && row >= 0 && row <= 5) return 1.0;
                if ((px == 1 || px == 3) && row == 4) return 1.0;
                if (px == 2 && row == 3) return 1.0;
                return 0.0;
            }
            // 15: @ - densest
            if ((row == 1 || row == 5) && px >= 1 && px <= 3) return 1.0;
            if ((px == 0 || px == 4) && row >= 2 && row <= 4) return 1.0;
            if (row == 3 && px >= 2 && px <= 3) return 1.0;
            if (row == 4 && px >= 1 && px <= 3) return 1.0;
            return 0.0;
        }

        // Apply ASCII effect to a color at given UV with given influence
        vec3 applyASCII(vec2 uv, float influence, float density) {
            float charsAcross = density * 15.0;
            float charWidth = 1.0 / charsAcross;
            float charHeight = charWidth * u_aspect * 1.4;

            vec2 cellIdx = floor(uv / vec2(charWidth, charHeight));
            vec2 cellUV = fract(uv / vec2(charWidth, charHeight));
            vec2 cellBase = cellIdx * vec2(charWidth, charHeight);

            // Sample center of cell
            vec4 sampleColor = texture2D(u_texture, clamp(cellBase + vec2(0.5, 0.5) * vec2(charWidth, charHeight), vec2(0.0), vec2(1.0)));
            float lum = dot(sampleColor.rgb, vec3(0.299, 0.587, 0.114));

            int charIdx = int(lum * 15.99);
            float pixel = getCharPixel(charIdx, cellUV);

            vec3 charColor = sampleColor.rgb * (0.9 + lum * 0.3);
            vec3 bgColor = sampleColor.rgb * 0.15;
            vec3 asciiColor = mix(bgColor, charColor, pixel);

            // Add green phosphor tint for terminal feel
            asciiColor = mix(asciiColor, asciiColor * vec3(0.7, 1.0, 0.8), 0.3);

            return mix(sampleColor.rgb, asciiColor, influence);
        }

        // Living pixels: the screen comes alive with effects based on brightness
        // Uses u_lp_flags for sub-toggles: bit0=stars, bit1=shooting, bit2=fireflies, bit3=dust, bit4=shimmer, bit5=eyes, bit6=rain
        // Uses u_touch_x, u_touch_y, u_touch_time for eye behavior
        vec3 applyLivingPixels(vec3 color, vec2 uv, float time) {
            float lum = dot(color, vec3(0.299, 0.587, 0.114));
            int flags = u_lp_flags;
            bool doStars = (flags / 1) - (flags / 2) * 2 == 1;
            bool doShooting = (flags / 2) - (flags / 4) * 2 == 1;
            bool doFireflies = (flags / 4) - (flags / 8) * 2 == 1;
            bool doDust = (flags / 8) - (flags / 16) * 2 == 1;
            bool doShimmer = (flags / 16) - (flags / 32) * 2 == 1;
            bool doEyes = (flags / 32) - (flags / 64) * 2 == 1;
            bool doRain = (flags / 64) - (flags / 128) * 2 == 1;

            // === DARK AREAS: Night sky with stars and nebula colors ===
            // Use stepped time for ~12fps updates (cheaper on CPU/GPU)
            float starTime = floor(time * 12.0) / 12.0;

            if (lum < 0.15 && doStars) {
                float darkIntensity = 1.0 - lum / 0.15;

                // Static nebula color wash (no time dependency - free!)
                float nebulaX = sin(uv.x * 3.0 + uv.y * 2.0) * 0.5 + 0.5;
                float nebulaY = cos(uv.y * 4.0 - uv.x * 1.5) * 0.5 + 0.5;
                vec3 nebula1 = vec3(0.1, 0.05, 0.15) * nebulaX;  // Purple
                vec3 nebula2 = vec3(0.05, 0.1, 0.15) * nebulaY;  // Teal
                color += (nebula1 + nebula2) * darkIntensity * 0.3;

                // Twinkling stars - stepped time for cheaper updates
                vec2 starGrid = uv * 50.0;
                vec2 starCell = floor(starGrid);
                vec2 starUV = fract(starGrid);
                float starRand = hash(starCell + 50.0);

                if (starRand > 0.9) {
                    // Simpler twinkle with stepped time
                    float phase = hash2(starCell) * 6.28;
                    float twinkle = sin(starTime * 2.0 + phase) * 0.35 + 0.65;

                    float dist = length(starUV - 0.5);
                    float star = smoothstep(0.12, 0.0, dist);

                    // 4-pointed sparkle for bright stars (simpler)
                    if (starRand > 0.96) {
                        float sparkleX = smoothstep(0.1, 0.0, abs(starUV.x - 0.5)) * smoothstep(0.35, 0.05, dist);
                        float sparkleY = smoothstep(0.1, 0.0, abs(starUV.y - 0.5)) * smoothstep(0.35, 0.05, dist);
                        star += (sparkleX + sparkleY) * 0.5;
                    }

                    float brightness = star * twinkle;
                    // Varied star colors
                    vec3 starColor;
                    float colorPick = hash(starCell * 3.3);
                    if (colorPick < 0.3) starColor = vec3(0.7, 0.85, 1.0);      // Blue
                    else if (colorPick < 0.6) starColor = vec3(1.0, 1.0, 0.95); // White
                    else if (colorPick < 0.8) starColor = vec3(1.0, 0.9, 0.7);  // Yellow
                    else starColor = vec3(1.0, 0.7, 0.6);                        // Orange-red
                    color += starColor * brightness * darkIntensity;
                }
            }

            // Shooting stars - static streaks that flash briefly (cheap!)
            // Three fixed size categories for variety
            if (lum < 0.15 && doShooting) {
                float darkIntensity = 1.0 - lum / 0.15;

                // Channel 0: Small streaks (most common, every 6 seconds)
                {
                    float period = 6.0;
                    float shootSlot = floor(time / period);
                    float timeInSlot = mod(time, period);

                    if (timeInSlot < 0.15) {
                        float seed = shootSlot * 17.3;
                        float angle = hash(vec2(seed, 1.0)) * 6.28;
                        vec2 shootDir = vec2(cos(angle), sin(angle));
                        vec2 shootPos = vec2(
                            hash(vec2(seed, 2.0)) * 0.7 + 0.15,
                            hash(vec2(seed, 3.0)) * 0.7 + 0.15
                        );

                        float trailLen = 0.08 + hash(vec2(seed, 4.0)) * 0.07;
                        vec2 toPoint = uv - shootPos;
                        float alongTrail = dot(toPoint, shootDir);
                        float perpDist = length(toPoint - alongTrail * shootDir);

                        if (alongTrail > -trailLen && alongTrail < 0.003 && perpDist < 0.004) {
                            float fade = (1.0 + alongTrail / trailLen) * (1.0 - perpDist / 0.004);
                            fade *= smoothstep(0.15, 0.0, timeInSlot);
                            color += vec3(1.0, 0.97, 0.92) * fade * 1.8 * darkIntensity;
                        }
                    }
                }

                // Channel 1: Medium streaks (every 12 seconds)
                {
                    float period = 12.0;
                    float shootSlot = floor(time / period);
                    float timeInSlot = mod(time, period);

                    if (timeInSlot < 0.15) {
                        float seed = shootSlot * 31.7 + 500.0;
                        float angle = hash(vec2(seed, 1.0)) * 6.28;
                        vec2 shootDir = vec2(cos(angle), sin(angle));
                        vec2 shootPos = vec2(
                            hash(vec2(seed, 2.0)) * 0.6 + 0.2,
                            hash(vec2(seed, 3.0)) * 0.6 + 0.2
                        );

                        float trailLen = 0.25 + hash(vec2(seed, 4.0)) * 0.15;
                        vec2 toPoint = uv - shootPos;
                        float alongTrail = dot(toPoint, shootDir);
                        float perpDist = length(toPoint - alongTrail * shootDir);

                        if (alongTrail > -trailLen && alongTrail < 0.004 && perpDist < 0.003) {
                            float fade = (1.0 + alongTrail / trailLen) * (1.0 - perpDist / 0.003);
                            fade *= smoothstep(0.15, 0.0, timeInSlot);
                            color += vec3(1.0, 0.98, 0.95) * fade * 2.2 * darkIntensity;
                        }
                    }
                }

                // Channel 2: Full screen streaks (rare, every 25 seconds)
                {
                    float period = 25.0;
                    float shootSlot = floor(time / period);
                    float timeInSlot = mod(time, period);

                    if (timeInSlot < 0.2) {
                        float seed = shootSlot * 47.1 + 1000.0;
                        float angle = hash(vec2(seed, 1.0)) * 6.28;
                        vec2 shootDir = vec2(cos(angle), sin(angle));

                        // Start from edge
                        vec2 shootPos;
                        float edge = hash(vec2(seed, 5.0));
                        if (abs(shootDir.x) > abs(shootDir.y)) {
                            shootPos.x = shootDir.x > 0.0 ? 0.95 : 0.05;
                            shootPos.y = edge * 0.8 + 0.1;
                        } else {
                            shootPos.x = edge * 0.8 + 0.1;
                            shootPos.y = shootDir.y > 0.0 ? 0.95 : 0.05;
                        }

                        float trailLen = 1.2 + hash(vec2(seed, 4.0)) * 0.5;
                        vec2 toPoint = uv - shootPos;
                        float alongTrail = dot(toPoint, shootDir);
                        float perpDist = length(toPoint - alongTrail * shootDir);

                        if (alongTrail > -trailLen && alongTrail < 0.008 && perpDist < 0.002) {
                            float fade = (1.0 + alongTrail / trailLen) * (1.0 - perpDist / 0.002);
                            fade *= smoothstep(0.2, 0.0, timeInSlot);
                            color += vec3(1.0, 1.0, 0.98) * fade * 3.0 * darkIntensity;
                        }
                    }
                }
            }

            // Subtle global breathing
            float breathe = sin(time * 0.5) * 0.015;
            color = color * (1.0 + breathe);

            return color;
        }

        void main() {
            vec2 uv = v_texcoord;

            // === CRT MODE (style 2) - Scanlines, RGB separation, vignette ===
            if (u_style == 2) {
                // RGB separation (chromatic aberration)
                float sep = 0.002;
                float r = texture2D(u_texture, uv + vec2(sep, 0.0)).r;
                float g = texture2D(u_texture, uv).g;
                float b = texture2D(u_texture, uv - vec2(sep, 0.0)).b;
                vec3 color = vec3(r, g, b);

                // Scanlines
                float scanline = sin(uv.y * 800.0) * 0.5 + 0.5;
                scanline = pow(scanline, 0.8);
                color *= 0.8 + scanline * 0.2;

                // Vertical RGB stripes (like CRT phosphors)
                float stripe = mod(gl_FragCoord.x, 3.0);
                if (stripe < 1.0) color *= vec3(1.1, 0.9, 0.9);
                else if (stripe < 2.0) color *= vec3(0.9, 1.1, 0.9);
                else color *= vec3(0.9, 0.9, 1.1);

                // Vignette
                vec2 vigUV = uv * 2.0 - 1.0;
                float vig = 1.0 - dot(vigUV, vigUV) * 0.3;
                color *= vig;

                // Slight curve distortion at edges
                vec2 curved = uv - 0.5;
                curved *= 1.0 + dot(curved, curved) * 0.02;
                curved += 0.5;

                // Screen flicker
                float flicker = 0.98 + sin(u_time * 8.0) * 0.02;
                color *= flicker;

                // Apply living pixels if enabled
                if (u_living == 1) {
                    color = applyLivingPixels(color, uv, u_time);
                }

                gl_FragColor = vec4(color, 1.0);
                return;
            }

            // === CALCULATE DISTORTION AND INFLUENCE ===
            vec2 totalOffset = vec2(0.0);
            float totalInf = 0.0;
            float iceAmount = 0.0;
            float asciiInf = 0.0; // For terminal ripple mode

            for (int i = 0; i < 10; i++) {
                if (i >= u_count) break;

                vec2 center = vec2(u_positions[i].x, 1.0 - u_positions[i].y);
                float radius = u_params[i].x;
                float strength = u_params[i].y;
                float effectType = u_params[i].z;

                vec2 delta = uv - center;
                delta.x *= u_aspect;
                float dist = length(delta);

                if (dist < 0.001) continue;
                vec2 dir = delta / dist;

                // FISHEYE (effectType < 0.5) - finger is down
                if (effectType < 0.5 && dist < radius) {
                    float nd = dist / radius;
                    float power = 1.0 + strength * 2.0;
                    float displaced = pow(nd, power) * radius;
                    vec2 offset = dir * (dist - displaced) * 0.5;
                    offset.x /= u_aspect;
                    totalOffset += offset;
                    totalInf += (1.0 - nd) * strength;

                    // For snow: accumulate ice
                    if (u_style == 1) {
                        iceAmount += (1.0 - nd * nd) * strength * 3.0;
                    }

                    // For terminal ripple: ASCII in touched area
                    if (u_style == 3) {
                        asciiInf = max(asciiInf, (1.0 - nd) * 1.5);
                    }
                }
                // RIPPLE (effectType >= 1.0) - finger released
                else if (effectType >= 1.0) {
                    float progress = effectType - 1.0;
                    if (progress > 1.0) continue;

                    float fade = 1.0 - progress;

                    if (u_style == 1) {
                        // SNOW: Ice melting
                        float meltRadius = radius * (1.0 - fade * 0.7);
                        if (dist < meltRadius) {
                            float meltND = dist / meltRadius;
                            iceAmount += (1.0 - meltND) * fade * fade * strength * 2.0;
                        }
                    } else if (u_style == 3) {
                        // TERMINAL RIPPLE: ASCII follows the ripple ring
                        float ringPos = radius * progress;
                        float ringWidth = 0.08 * (1.0 + progress * 0.5); // Wider ring
                        float ringDist = abs(dist - ringPos);
                        if (ringDist < ringWidth) {
                            float wave = 1.0 - ringDist / ringWidth;
                            wave = wave * wave * (3.0 - 2.0 * wave);
                            // ASCII influence follows the ring
                            asciiInf = max(asciiInf, wave * fade * 1.2);
                            // Also apply distortion
                            float phase = (dist < ringPos) ? 1.0 : -1.0;
                            vec2 offset = dir * wave * strength * phase * 0.08 * fade;
                            offset.x /= u_aspect;
                            totalOffset += offset;
                            totalInf += wave * fade * strength;
                        }
                    } else {
                        // WATER: Expanding ripple ring
                        float ringPos = radius * progress;
                        float ringWidth = 0.05 * (1.0 - progress * 0.3);
                        float ringDist = abs(dist - ringPos);
                        if (ringDist < ringWidth) {
                            float wave = 1.0 - ringDist / ringWidth;
                            wave = wave * wave * (3.0 - 2.0 * wave);
                            float phase = (dist < ringPos) ? 1.0 : -1.0;
                            vec2 offset = dir * wave * strength * phase * 0.1 * fade;
                            offset.x /= u_aspect;
                            totalOffset += offset;
                            totalInf += wave * fade * strength;
                        }
                    }
                }
            }

            // === RAIN RIPPLE DISPLACEMENT (Compiz-style) ===
            // Add displacement ripples if living pixels rain is enabled
            if (u_living == 1) {
                int flags = u_lp_flags;
                bool doRain = (flags / 64) - (flags / 128) * 2 == 1;

                if (doRain) {
                    // Multiple ripples at different positions/timings - FAST
                    for (float rippleIdx = 0.0; rippleIdx < 8.0; rippleIdx += 1.0) {
                        float period = 1.0 + rippleIdx * 0.2;  // Fast: 1.0-2.4 second periods
                        float rippleTime = mod(u_time + rippleIdx * 0.7, period);
                        float progress = rippleTime / period;

                        if (progress < 0.7) {  // Active for 70% of period
                            float seed = floor((u_time + rippleIdx * 1.3) / period);
                            vec2 center = vec2(
                                hash(vec2(seed + rippleIdx, 0.0)) * 0.8 + 0.1,
                                hash(vec2(seed + rippleIdx, 1.0)) * 0.8 + 0.1
                            );

                            vec2 delta = uv - center;
                            delta.x *= u_aspect;
                            float dist = length(delta);

                            if (dist > 0.001) {
                                vec2 dir = delta / dist;

                                // Expanding ripple ring
                                float maxRadius = 0.25;
                                float ringPos = progress * maxRadius;
                                float ringWidth = 0.04 * (1.0 - progress * 0.5);
                                float ringDist = abs(dist - ringPos);

                                if (ringDist < ringWidth) {
                                    float wave = 1.0 - ringDist / ringWidth;
                                    wave = wave * wave * (3.0 - 2.0 * wave);  // Smoothstep
                                    float fade = 1.0 - progress;
                                    fade = fade * fade;

                                    // Displacement like water ripple - very subtle
                                    float phase = (dist < ringPos) ? 1.0 : -1.0;
                                    float strength = 0.012 * wave * fade;
                                    vec2 offset = dir * strength * phase;
                                    offset.x /= u_aspect;
                                    totalOffset += offset;
                                }
                            }
                        }
                    }
                }
            }

            vec2 sampleUV = clamp(uv - totalOffset, vec2(0.0), vec2(1.0));
            vec4 color = texture2D(u_texture, sampleUV);

            // === TERMINAL RIPPLE (style 3) ===
            if (u_style == 3 && asciiInf > 0.01) {
                asciiInf = clamp(asciiInf, 0.0, 1.0);
                color.rgb = applyASCII(sampleUV, asciiInf, u_density);
            }
            // === WATER (style 0) ===
            else if (u_style == 0 && totalInf > 0.01) {
                float inf = clamp(totalInf, 0.0, 1.0);
                color.rgb = mix(color.rgb, color.rgb * vec3(0.8, 0.9, 1.2), inf * 0.5);
            }
            // === SNOW (style 1) - Unique snowflake grown by dragging finger ===
            else if (u_style == 1) {
                for (int i = 0; i < 10; i++) {
                    if (i >= u_count) break;

                    vec2 center = vec2(u_positions[i].x, 1.0 - u_positions[i].y);
                    float radius = u_params[i].x;
                    float growth = u_params[i].y;  // Driven by drag distance from touch point

                    vec2 delta = sampleUV - center;
                    delta.x *= u_aspect;
                    float dist = length(delta);

                    float maxRadius = radius * 3.5;

                    if (dist < maxRadius && growth > 0.005) {
                        float crystal = 0.0;
                        float PI = 3.14159;

                        // === UNIQUE RANDOMIZATION per crystal ===
                        float seed1 = hash(center * 127.1);
                        float seed2 = hash(center * 269.5 + 0.5);
                        float seed3 = hash(center * 419.3 + 1.0);

                        // Random rotation for whole crystal
                        float rotOffset = seed1 * PI / 3.0;

                        // 6-fold symmetry with unique variations
                        for (float b = 0.0; b < 6.0; b += 1.0) {
                            float branchAngle = b * PI / 3.0 + rotOffset;
                            vec2 branchDir = vec2(cos(branchAngle), sin(branchAngle));

                            // Unique length per branch arm
                            float bSeed = hash(center * 50.0 + b * 13.7);
                            float lenMult = 0.6 + bSeed * 0.8;
                            float mainLen = growth * maxRadius * lenMult;

                            // Main branch
                            float proj = dot(delta, branchDir);
                            if (proj > 0.0 && proj < mainLen) {
                                vec2 closest = branchDir * proj;
                                float perpDist = length(delta - closest);
                                float widthBase = 0.006 + bSeed * 0.004;
                                float width = widthBase * maxRadius * (1.0 - proj / mainLen * 0.6);
                                float line = smoothstep(width, width * 0.2, perpDist);
                                crystal = max(crystal, line);
                            }

                            // Side dendrites - unique spacing/angles per crystal
                            if (growth > 0.05) {
                                float spacing = 0.06 + hash(center * 33.0 + b * 7.0) * 0.06;
                                float startOff = hash(center * 22.0 + b * 11.0) * spacing * 0.5;

                                for (float d = 0.08 + startOff; d < growth * 0.88; d += spacing) {
                                    for (float side = -1.0; side <= 1.0; side += 2.0) {
                                        float dSeed = hash(center * 77.0 + b * 19.0 + d * 31.0 + side * 3.0);

                                        // Skip some dendrites randomly for variety
                                        if (dSeed < 0.15) continue;

                                        // Unique angle variation
                                        float angleVar = (dSeed - 0.5) * 0.5;
                                        float dendAngle = branchAngle + side * (PI / 3.0 + angleVar);
                                        vec2 dendDir = vec2(cos(dendAngle), sin(dendAngle));

                                        vec2 dendOrigin = branchDir * d * maxRadius;
                                        float dendLenMult = 0.25 + dSeed * 0.45;
                                        float dendLen = (growth - d) * maxRadius * dendLenMult;
                                        if (dendLen < 0.004 * maxRadius) continue;

                                        vec2 toDend = delta - dendOrigin;
                                        float dendProj = dot(toDend, dendDir);
                                        if (dendProj > 0.0 && dendProj < dendLen) {
                                            vec2 closest = dendOrigin + dendDir * dendProj;
                                            float perpDist = length(delta - closest);
                                            float width = 0.004 * maxRadius * (1.0 - dendProj / dendLen * 0.7);
                                            float line = smoothstep(width, width * 0.15, perpDist);
                                            crystal = max(crystal, line * 0.92);
                                        }

                                        // Tertiary - random presence
                                        if (growth > 0.25 && dSeed > 0.4) {
                                            float tSeed = hash(center * 99.0 + d * 41.0 + side * 5.0);
                                            float tPos = 0.25 + tSeed * 0.35;
                                            float tLen = dendLen * (0.5 - tPos * 0.5) * (0.4 + tSeed * 0.4);

                                            if (tLen > 0.002 * maxRadius) {
                                                vec2 tOrigin = dendOrigin + dendDir * dendLen * tPos;
                                                vec2 tDir = branchDir;

                                                vec2 toT = delta - tOrigin;
                                                float tProj = dot(toT, tDir);
                                                if (tProj > 0.0 && tProj < tLen) {
                                                    vec2 closest = tOrigin + tDir * tProj;
                                                    float perpDist = length(delta - closest);
                                                    float width = 0.002 * maxRadius;
                                                    float line = smoothstep(width, width * 0.1, perpDist);
                                                    crystal = max(crystal, line * 0.8);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Central seed - varies per crystal
                        float coreSize = 0.01 * maxRadius * (0.7 + seed2 * 0.6);
                        if (dist < coreSize) {
                            crystal = max(crystal, 1.0);
                        }

                        // Apply with unique color tint
                        if (crystal > 0.01) {
                            vec3 iceColor = vec3(0.80 + seed3 * 0.1, 0.88 + seed2 * 0.08, 0.98 + seed1 * 0.02);
                            float sparkle = pow(hash(sampleUV * 700.0 + u_time * 0.15), 30.0);
                            iceColor += sparkle * 0.25;
                            color.rgb = mix(color.rgb, iceColor, crystal * 0.94);
                        }
                    }
                }
                color.rgb = min(color.rgb, vec3(1.0));
            }

            // Apply living pixels overlay (works with all styles)
            if (u_living == 1) {
                color.rgb = applyLivingPixels(color.rgb, uv, u_time);
            }

            gl_FragColor = color;
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

        // Load libGLESv2
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

        // Load all GL functions
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
        FN_DELETE_SHADER = load_fn(lib, b"glDeleteShader\0");
        FN_DELETE_PROGRAM = load_fn(lib, b"glDeleteProgram\0");
        FN_GET_ERROR = load_fn(lib, b"glGetError\0");
        FN_FLUSH = load_fn(lib, b"glFlush\0");
        FN_FINISH = load_fn(lib, b"glFinish\0");
        FN_COPY_TEX_IMAGE_2D = load_fn(lib, b"glCopyTexImage2D\0");
        FN_UNIFORM1F = load_fn(lib, b"glUniform1f\0");
        FN_UNIFORM2FV = load_fn(lib, b"glUniform2fv\0");
        FN_UNIFORM4FV = load_fn(lib, b"glUniform4fv\0");

        // Load FBO functions for reliable framebuffer capture
        FN_GEN_FRAMEBUFFERS = load_fn(lib, b"glGenFramebuffers\0");
        FN_BIND_FRAMEBUFFER = load_fn(lib, b"glBindFramebuffer\0");
        FN_FRAMEBUFFER_TEXTURE_2D = load_fn(lib, b"glFramebufferTexture2D\0");
        FN_CHECK_FRAMEBUFFER_STATUS = load_fn(lib, b"glCheckFramebufferStatus\0");
        FN_DELETE_FRAMEBUFFERS = load_fn(lib, b"glDeleteFramebuffers\0");
        FN_BLIT_FRAMEBUFFER = load_fn(lib, b"glBlitFramebuffer\0");
        FN_READ_PIXELS = load_fn(lib, b"glReadPixels\0");
        FN_GET_INTEGERV = load_fn(lib, b"glGetIntegerv\0");

        tracing::info!("FBO support: gen={}, bind={}, attach={}, check={}, blit={}, read={}",
            FN_GEN_FRAMEBUFFERS.is_some(), FN_BIND_FRAMEBUFFER.is_some(),
            FN_FRAMEBUFFER_TEXTURE_2D.is_some(), FN_CHECK_FRAMEBUFFER_STATUS.is_some(),
            FN_BLIT_FRAMEBUFFER.is_some(), FN_READ_PIXELS.is_some());

        // Create shader program
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

        // Create distortion shader program
        if let Some(program) = create_distort_shader_program() {
            DISTORT_PROGRAM = program;

            let pos_name = CString::new("a_position").unwrap();
            let tex_name = CString::new("a_texcoord").unwrap();
            let tex_uni = CString::new("u_texture").unwrap();
            let pos_uni = CString::new("u_positions").unwrap();
            let params_uni = CString::new("u_params").unwrap();
            let count_uni = CString::new("u_count").unwrap();
            let aspect_uni = CString::new("u_aspect").unwrap();
            let style_uni = CString::new("u_style").unwrap();
            let density_uni = CString::new("u_density").unwrap();
            let living_uni = CString::new("u_living").unwrap();
            let time_uni = CString::new("u_time").unwrap();
            let lp_flags_uni = CString::new("u_lp_flags").unwrap();
            let touch_x_uni = CString::new("u_touch_x").unwrap();
            let touch_y_uni = CString::new("u_touch_y").unwrap();
            let touch_time_uni = CString::new("u_touch_time").unwrap();

            if let Some(f) = FN_GET_ATTRIB_LOCATION {
                DISTORT_ATTR_POSITION = f(program, pos_name.as_ptr());
                DISTORT_ATTR_TEXCOORD = f(program, tex_name.as_ptr());
            }
            if let Some(f) = FN_GET_UNIFORM_LOCATION {
                DISTORT_UNIFORM_TEXTURE = f(program, tex_uni.as_ptr());
                DISTORT_UNIFORM_POSITIONS = f(program, pos_uni.as_ptr());
                DISTORT_UNIFORM_PARAMS = f(program, params_uni.as_ptr());
                DISTORT_UNIFORM_COUNT = f(program, count_uni.as_ptr());
                DISTORT_UNIFORM_ASPECT = f(program, aspect_uni.as_ptr());
                DISTORT_UNIFORM_STYLE = f(program, style_uni.as_ptr());
                DISTORT_UNIFORM_DENSITY = f(program, density_uni.as_ptr());
                DISTORT_UNIFORM_LIVING = f(program, living_uni.as_ptr());
                DISTORT_UNIFORM_TIME = f(program, time_uni.as_ptr());
                DISTORT_UNIFORM_LP_FLAGS = f(program, lp_flags_uni.as_ptr());
                DISTORT_UNIFORM_TOUCH_X = f(program, touch_x_uni.as_ptr());
                DISTORT_UNIFORM_TOUCH_Y = f(program, touch_y_uni.as_ptr());
                DISTORT_UNIFORM_TOUCH_TIME = f(program, touch_time_uni.as_ptr());
            }

            tracing::info!("Distortion shader created: program={}, positions={}, params={}, count={}, aspect={}, style={}, density={}, living={}, time={}, lp_flags={}, touch_x={}, touch_y={}, touch_time={}",
                DISTORT_PROGRAM, DISTORT_UNIFORM_POSITIONS, DISTORT_UNIFORM_PARAMS,
                DISTORT_UNIFORM_COUNT, DISTORT_UNIFORM_ASPECT, DISTORT_UNIFORM_STYLE, DISTORT_UNIFORM_DENSITY,
                DISTORT_UNIFORM_LIVING, DISTORT_UNIFORM_TIME,
                DISTORT_UNIFORM_LP_FLAGS, DISTORT_UNIFORM_TOUCH_X, DISTORT_UNIFORM_TOUCH_Y, DISTORT_UNIFORM_TOUCH_TIME);
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

        // Create vertex shader
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

        // Create fragment shader
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

        // Create program
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

    unsafe fn create_distort_shader_program() -> Option<u32> {
        let create_shader = FN_CREATE_SHADER?;
        let shader_source = FN_SHADER_SOURCE?;
        let compile_shader = FN_COMPILE_SHADER?;
        let get_shaderiv = FN_GET_SHADERIV?;
        let create_program = FN_CREATE_PROGRAM?;
        let attach_shader = FN_ATTACH_SHADER?;
        let link_program = FN_LINK_PROGRAM?;
        let get_programiv = FN_GET_PROGRAMIV?;

        // Create vertex shader (same as normal)
        let vs = create_shader(VERTEX_SHADER);
        let vs_src = CString::new(VERTEX_SHADER_SRC).unwrap();
        let vs_ptr = vs_src.as_ptr();
        shader_source(vs, 1, &vs_ptr, std::ptr::null());
        compile_shader(vs);

        let mut status: i32 = 0;
        get_shaderiv(vs, COMPILE_STATUS, &mut status);
        if status == 0 {
            tracing::error!("Distortion vertex shader compilation failed");
            return None;
        }

        // Create distortion fragment shader
        let fs = create_shader(FRAGMENT_SHADER);
        let fs_src = CString::new(DISTORT_FRAGMENT_SRC).unwrap();
        let fs_ptr = fs_src.as_ptr();
        shader_source(fs, 1, &fs_ptr, std::ptr::null());
        compile_shader(fs);

        get_shaderiv(fs, COMPILE_STATUS, &mut status);
        if status == 0 {
            tracing::error!("Distortion fragment shader compilation failed");
            return None;
        }

        // Create program
        let program = create_program();
        attach_shader(program, vs);
        attach_shader(program, fs);
        link_program(program);

        get_programiv(program, LINK_STATUS, &mut status);
        if status == 0 {
            tracing::error!("Distortion shader program linking failed");
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

    #[allow(non_snake_case)]
    pub unsafe fn Finish() {
        if let Some(f) = FN_FINISH { f(); }
    }

    fn check_error(location: &str) {
        unsafe {
            let err = GetError();
            if err != 0 {
                tracing::error!("GL error at {}: 0x{:04X}", location, err);
            }
        }
    }

    // Frame counter for throttled logging
    static mut FRAME_COUNT: u64 = 0;

    /// Render a texture (RGBA pixel buffer) to fill the screen
    pub unsafe fn render_texture(tex_width: u32, tex_height: u32, pixels: &[u8], screen_width: u32, screen_height: u32) {
        FRAME_COUNT += 1;
        let log_frame = FRAME_COUNT % 60 == 0; // Log every 60 frames

        if SHADER_PROGRAM == 0 || ATTR_POSITION < 0 || ATTR_TEXCOORD < 0 {
            tracing::warn!("Shader not initialized");
            return;
        }

        // Clear any pending errors
        while GetError() != 0 {}

        // Set viewport
        if let Some(f) = FN_VIEWPORT {
            f(0, 0, screen_width as i32, screen_height as i32);
        }
        check_error("viewport");

        // Create and bind texture
        let mut texture: u32 = 0;
        if let Some(f) = FN_GEN_TEXTURES { f(1, &mut texture); }
        check_error("genTextures");

        if let Some(f) = FN_BIND_TEXTURE { f(TEXTURE_2D, texture); }
        check_error("bindTexture");

        // Set texture parameters
        if let Some(f) = FN_TEX_PARAMETERI {
            f(TEXTURE_2D, TEXTURE_MIN_FILTER, LINEAR);
            f(TEXTURE_2D, TEXTURE_MAG_FILTER, LINEAR);
        }
        check_error("texParameteri");

        // Upload texture data
        let expected_size = (tex_width * tex_height * 4) as usize;
        if pixels.len() != expected_size {
            tracing::error!("Pixel buffer size mismatch: got {}, expected {}", pixels.len(), expected_size);
            return;
        }

        if let Some(f) = FN_TEX_IMAGE_2D {
            f(TEXTURE_2D, 0, RGBA as i32, tex_width as i32, tex_height as i32,
              0, RGBA, UNSIGNED_BYTE, pixels.as_ptr() as *const c_void);
        }
        check_error("texImage2D");

        // Use shader program
        if let Some(f) = FN_USE_PROGRAM { f(SHADER_PROGRAM); }
        check_error("useProgram");

        // Set texture uniform
        if let Some(f) = FN_ACTIVE_TEXTURE { f(0x84C0); } // GL_TEXTURE0
        check_error("activeTexture");

        if let Some(f) = FN_BIND_TEXTURE { f(TEXTURE_2D, texture); }
        check_error("bindTexture2");

        if let Some(f) = FN_UNIFORM1I { f(UNIFORM_TEXTURE, 0); }
        check_error("uniform1i");

        // Full-screen quad vertices (position + texcoord interleaved)
        // Shell always renders in portrait - NO rotation applied here
        let vertices: [f32; 16] = [
            // Position (x, y)  // TexCoord (u, v)
            -1.0, -1.0,         0.0, 1.0,  // Bottom-left
             1.0, -1.0,         1.0, 1.0,  // Bottom-right
            -1.0,  1.0,         0.0, 0.0,  // Top-left
             1.0,  1.0,         1.0, 0.0,  // Top-right
        ];

        // Set vertex attributes
        if let Some(f) = FN_ENABLE_VERTEX_ATTRIB_ARRAY {
            f(ATTR_POSITION as u32);
            f(ATTR_TEXCOORD as u32);
        }
        check_error("enableVertexAttribArray");

        if let Some(f) = FN_VERTEX_ATTRIB_POINTER {
            let stride = 4 * std::mem::size_of::<f32>() as i32;
            f(ATTR_POSITION as u32, 2, FLOAT, FALSE, stride, vertices.as_ptr() as *const c_void);
            f(ATTR_TEXCOORD as u32, 2, FLOAT, FALSE, stride,
              (vertices.as_ptr() as *const f32).add(2) as *const c_void);
        }
        check_error("vertexAttribPointer");

        // Enable blending for transparency
        if let Some(f) = FN_ENABLE { f(BLEND); }
        if let Some(f) = FN_BLEND_FUNC { f(SRC_ALPHA, ONE_MINUS_SRC_ALPHA); }
        check_error("blend setup");

        // Draw
        if let Some(f) = FN_DRAW_ARRAYS {
            f(TRIANGLE_STRIP, 0, 4);
        }
        check_error("drawArrays");

        // Finish to ensure GPU completes all rendering (prevents tearing on tiled GPUs)
        Finish();

        // Cleanup
        if let Some(f) = FN_DISABLE { f(BLEND); }
        if let Some(f) = FN_DELETE_TEXTURES { f(1, &texture); }

        if log_frame {
            // Log first few pixels to verify content
            let r = pixels.get(0).copied().unwrap_or(0);
            let g = pixels.get(1).copied().unwrap_or(0);
            let b = pixels.get(2).copied().unwrap_or(0);
            let a = pixels.get(3).copied().unwrap_or(0);
            tracing::info!("Frame {}: texture={}x{} -> screen={}x{}, tex_id={}, first_pixel=RGBA({},{},{},{})",
                FRAME_COUNT, tex_width, tex_height, screen_width, screen_height, texture, r, g, b, a);
        }
    }

    /// Render texture at a specific screen position (for window animations)
    /// x, y are in screen pixels from top-left
    pub unsafe fn render_texture_at(tex_width: u32, tex_height: u32, pixels: &[u8],
                                     screen_width: u32, screen_height: u32,
                                     x: i32, y: i32) {
        if SHADER_PROGRAM == 0 || ATTR_POSITION < 0 || ATTR_TEXCOORD < 0 {
            return;
        }

        // Clear any pending errors
        while GetError() != 0 {}

        // Set viewport
        if let Some(f) = FN_VIEWPORT {
            f(0, 0, screen_width as i32, screen_height as i32);
        }

        // Create and bind texture
        let mut texture: u32 = 0;
        if let Some(f) = FN_GEN_TEXTURES { f(1, &mut texture); }
        if let Some(f) = FN_BIND_TEXTURE { f(TEXTURE_2D, texture); }

        // Set texture parameters
        if let Some(f) = FN_TEX_PARAMETERI {
            f(TEXTURE_2D, TEXTURE_MIN_FILTER, LINEAR);
            f(TEXTURE_2D, TEXTURE_MAG_FILTER, LINEAR);
        }

        // Upload texture data
        let expected_size = (tex_width * tex_height * 4) as usize;
        if pixels.len() != expected_size {
            return;
        }

        if let Some(f) = FN_TEX_IMAGE_2D {
            f(TEXTURE_2D, 0, RGBA as i32, tex_width as i32, tex_height as i32,
              0, RGBA, UNSIGNED_BYTE, pixels.as_ptr() as *const c_void);
        }

        // Use shader program
        if let Some(f) = FN_USE_PROGRAM { f(SHADER_PROGRAM); }

        // Set texture uniform
        if let Some(f) = FN_ACTIVE_TEXTURE { f(0x84C0); } // GL_TEXTURE0
        if let Some(f) = FN_BIND_TEXTURE { f(TEXTURE_2D, texture); }
        if let Some(f) = FN_UNIFORM1I { f(UNIFORM_TEXTURE, 0); }

        // Calculate positioned vertices
        let sw = screen_width as f32;
        let sh = screen_height as f32;
        let tw = tex_width as f32;
        let th = tex_height as f32;
        let left = (x as f32 / sw) * 2.0 - 1.0;
        let right = ((x as f32 + tw) / sw) * 2.0 - 1.0;
        let top = 1.0 - (y as f32 / sh) * 2.0;
        let bottom = 1.0 - ((y as f32 + th) / sh) * 2.0;
        let vertices: [f32; 16] = [
            left,  bottom,      0.0, 1.0,
            right, bottom,      1.0, 1.0,
            left,  top,         0.0, 0.0,
            right, top,         1.0, 0.0,
        ];

        // Set vertex attributes
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

        // Enable blending for transparency
        if let Some(f) = FN_ENABLE { f(BLEND); }
        if let Some(f) = FN_BLEND_FUNC { f(SRC_ALPHA, ONE_MINUS_SRC_ALPHA); }

        // Draw
        if let Some(f) = FN_DRAW_ARRAYS {
            f(TRIANGLE_STRIP, 0, 4);
        }

        // Finish to ensure GPU completes all rendering (prevents tearing on tiled GPUs)
        Finish();

        // Cleanup
        if let Some(f) = FN_DISABLE { f(BLEND); }
        if let Some(f) = FN_DELETE_TEXTURES { f(1, &texture); }
    }

    /// Render an existing GL texture at a specific position (for EGL-imported buffers)
    /// Unlike render_texture_at, this uses an existing texture ID and doesn't upload pixels
    pub unsafe fn render_egl_texture_at(texture_id: u32, tex_width: u32, tex_height: u32,
                                         screen_width: u32, screen_height: u32,
                                         x: i32, y: i32) {
        if SHADER_PROGRAM == 0 || ATTR_POSITION < 0 || ATTR_TEXCOORD < 0 {
            return;
        }

        // Clear any pending errors
        while GetError() != 0 {}

        // Set viewport
        if let Some(f) = FN_VIEWPORT {
            f(0, 0, screen_width as i32, screen_height as i32);
        }

        // Bind the existing texture
        if let Some(f) = FN_BIND_TEXTURE { f(TEXTURE_2D, texture_id); }

        // Set texture parameters (in case they weren't set)
        if let Some(f) = FN_TEX_PARAMETERI {
            f(TEXTURE_2D, TEXTURE_MIN_FILTER, LINEAR);
            f(TEXTURE_2D, TEXTURE_MAG_FILTER, LINEAR);
        }

        // Use shader program
        if let Some(f) = FN_USE_PROGRAM { f(SHADER_PROGRAM); }

        // Set texture uniform
        if let Some(f) = FN_ACTIVE_TEXTURE { f(0x84C0); } // GL_TEXTURE0
        if let Some(f) = FN_BIND_TEXTURE { f(TEXTURE_2D, texture_id); }
        if let Some(f) = FN_UNIFORM1I { f(UNIFORM_TEXTURE, 0); }

        // Calculate positioned vertices
        let sw = screen_width as f32;
        let sh = screen_height as f32;
        let tw = tex_width as f32;
        let th = tex_height as f32;
        let left = (x as f32 / sw) * 2.0 - 1.0;
        let right = ((x as f32 + tw) / sw) * 2.0 - 1.0;
        let top = 1.0 - (y as f32 / sh) * 2.0;
        let bottom = 1.0 - ((y as f32 + th) / sh) * 2.0;
        let vertices: [f32; 16] = [
            left,  bottom,      0.0, 1.0,
            right, bottom,      1.0, 1.0,
            left,  top,         0.0, 0.0,
            right, top,         1.0, 0.0,
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

        // Finish to ensure GPU completes all rendering (prevents tearing on tiled GPUs)
        Finish();

        if let Some(f) = FN_DISABLE { f(BLEND); }
        // Note: Don't delete the texture - it's cached for reuse
    }

    /// Create a GL texture from an EGL image
    /// This is used for importing camera/video preview buffers
    pub unsafe fn create_texture_from_egl_image(
        egl_image: *mut std::ffi::c_void,
        image_target_fn: super::GlEGLImageTargetTexture2DOES,
    ) -> u32 {
        let mut texture_id: u32 = 0;

        if let Some(gen_textures) = FN_GEN_TEXTURES {
            gen_textures(1, &mut texture_id);
        }
        if let Some(bind_texture) = FN_BIND_TEXTURE {
            bind_texture(TEXTURE_2D, texture_id);
        }

        // Bind EGL image to texture
        image_target_fn(TEXTURE_2D, egl_image);

        // Set texture parameters
        const TEXTURE_WRAP_S: u32 = 0x2802;
        const TEXTURE_WRAP_T: u32 = 0x2803;
        const CLAMP_TO_EDGE: i32 = 0x812F;

        if let Some(tex_param) = FN_TEX_PARAMETERI {
            tex_param(TEXTURE_2D, TEXTURE_MIN_FILTER, LINEAR);
            tex_param(TEXTURE_2D, TEXTURE_MAG_FILTER, LINEAR);
            tex_param(TEXTURE_2D, TEXTURE_WRAP_S, CLAMP_TO_EDGE);
            tex_param(TEXTURE_2D, TEXTURE_WRAP_T, CLAMP_TO_EDGE);
        }

        texture_id
    }

    /// Delete a GL texture
    pub unsafe fn delete_texture(texture_id: u32) {
        if let Some(f) = FN_DELETE_TEXTURES {
            f(1, &texture_id);
        }
    }

    /// Apply distortion effects to the current framebuffer
    /// This captures the screen, applies fisheye/ripple distortion, and renders the result
    /// If use_scene_texture is true, uses the pre-rendered scene texture (no framebuffer copy needed)
    pub unsafe fn render_distortion(
        screen_width: u32,
        screen_height: u32,
        shader_data: &crate::touch_effects::TouchEffectShaderData,
        use_scene_texture: bool,
    ) {
        if DISTORT_PROGRAM == 0 || DISTORT_ATTR_POSITION < 0 {
            return;
        }

        // For CRT mode (style 2) or living pixels, always render even with no touches
        // For other modes, only render when there are active effects
        if shader_data.count == 0 && shader_data.effect_style != 2 && shader_data.living_pixels != 1 {
            return;
        }

        // Clear any pending errors
        while GetError() != 0 {}

        let w = screen_width as i32;
        let h = screen_height as i32;

        // Determine which texture to use as the scene source
        let source_texture = if use_scene_texture && SCENE_TEXTURE != 0 {
            // Best path: Use the scene FBO texture directly
            // The entire scene was rendered to this texture, so no copy is needed
            // This completely avoids the tiled GPU issue
            SCENE_TEXTURE
        } else {
            // Fallback: Copy from the framebuffer (may flicker on tiled GPUs)
            let need_new_texture = CAPTURE_TEXTURE == 0
                || CAPTURE_TEX_WIDTH != screen_width
                || CAPTURE_TEX_HEIGHT != screen_height;

            if need_new_texture {
                if CAPTURE_TEXTURE != 0 {
                    if let Some(f) = FN_DELETE_TEXTURES { f(1, &CAPTURE_TEXTURE); }
                }
                if let Some(f) = FN_GEN_TEXTURES { f(1, &mut CAPTURE_TEXTURE); }
                CAPTURE_TEX_WIDTH = screen_width;
                CAPTURE_TEX_HEIGHT = screen_height;

                if let Some(f) = FN_BIND_TEXTURE { f(TEXTURE_2D, CAPTURE_TEXTURE); }
                if let Some(f) = FN_TEX_PARAMETERI {
                    f(TEXTURE_2D, TEXTURE_MIN_FILTER, LINEAR);
                    f(TEXTURE_2D, TEXTURE_MAG_FILTER, LINEAR);
                    f(TEXTURE_2D, 0x2802, 0x812F);
                    f(TEXTURE_2D, 0x2803, 0x812F);
                }
            } else {
                if let Some(f) = FN_BIND_TEXTURE { f(TEXTURE_2D, CAPTURE_TEXTURE); }
            }

            if let Some(f) = FN_COPY_TEX_IMAGE_2D {
                f(TEXTURE_2D, 0, RGBA, 0, 0, w, h, 0);
            }
            CAPTURE_TEXTURE
        };

        // Select which texture to use
        let use_texture = source_texture;

        // Set viewport
        if let Some(f) = FN_VIEWPORT {
            f(0, 0, screen_width as i32, screen_height as i32);
        }

        // Use distortion shader
        if let Some(f) = FN_USE_PROGRAM { f(DISTORT_PROGRAM); }

        // Bind the capture texture
        if let Some(f) = FN_ACTIVE_TEXTURE { f(0x84C0); } // GL_TEXTURE0
        if let Some(f) = FN_BIND_TEXTURE { f(TEXTURE_2D, use_texture); }
        if let Some(f) = FN_UNIFORM1I { f(DISTORT_UNIFORM_TEXTURE, 0); }

        // Set uniforms
        if let Some(f) = FN_UNIFORM2FV {
            f(DISTORT_UNIFORM_POSITIONS, 10, shader_data.positions.as_ptr());
        }
        if let Some(f) = FN_UNIFORM4FV {
            f(DISTORT_UNIFORM_PARAMS, 10, shader_data.params.as_ptr());
        }
        if let Some(f) = FN_UNIFORM1I {
            f(DISTORT_UNIFORM_COUNT, shader_data.count);
            f(DISTORT_UNIFORM_STYLE, shader_data.effect_style);
            f(DISTORT_UNIFORM_LIVING, shader_data.living_pixels);
            f(DISTORT_UNIFORM_LP_FLAGS, shader_data.lp_flags);
            // Debug: log style every 60 frames
            static mut DEBUG_COUNTER: u32 = 0;
            DEBUG_COUNTER += 1;
            if DEBUG_COUNTER % 60 == 0 {
                tracing::info!("Touch effect uniforms: style={}, living={}, time={:.2}, lp_flags=0x{:02X}",
                    shader_data.effect_style, shader_data.living_pixels, shader_data.time, shader_data.lp_flags);
            }
        }
        if let Some(f) = FN_UNIFORM1F {
            let aspect = screen_width as f32 / screen_height as f32;
            f(DISTORT_UNIFORM_ASPECT, aspect);
            f(DISTORT_UNIFORM_DENSITY, shader_data.ascii_density);
            f(DISTORT_UNIFORM_TIME, shader_data.time);
            f(DISTORT_UNIFORM_TOUCH_X, shader_data.last_touch_x);
            f(DISTORT_UNIFORM_TOUCH_Y, shader_data.last_touch_y);
            f(DISTORT_UNIFORM_TOUCH_TIME, shader_data.time_since_touch);
        }

        // Fullscreen quad vertices
        // Framebuffer has Y=0 at bottom, so use v=0 at bottom, v=1 at top
        #[rustfmt::skip]
        let vertices: [f32; 16] = [
            // Position       // TexCoord
            -1.0, -1.0,       0.0, 0.0,  // Bottom-left
             1.0, -1.0,       1.0, 0.0,  // Bottom-right
            -1.0,  1.0,       0.0, 1.0,  // Top-left
             1.0,  1.0,       1.0, 1.0,  // Top-right
        ];

        // Set vertex attributes
        if let Some(f) = FN_ENABLE_VERTEX_ATTRIB_ARRAY {
            f(DISTORT_ATTR_POSITION as u32);
            f(DISTORT_ATTR_TEXCOORD as u32);
        }

        if let Some(f) = FN_VERTEX_ATTRIB_POINTER {
            let stride = 4 * std::mem::size_of::<f32>() as i32;
            f(DISTORT_ATTR_POSITION as u32, 2, FLOAT, FALSE, stride, vertices.as_ptr() as *const c_void);
            f(DISTORT_ATTR_TEXCOORD as u32, 2, FLOAT, FALSE, stride,
              (vertices.as_ptr() as *const f32).add(2) as *const c_void);
        }

        // Draw fullscreen quad
        if let Some(f) = FN_DRAW_ARRAYS {
            f(TRIANGLE_STRIP, 0, 4);
        }

        // Finish to ensure GPU completes all rendering (prevents tearing on tiled GPUs)
        Finish();

        // Note: Don't delete CAPTURE_TEXTURE - it's persistent and reused each frame

        // Switch back to normal shader
        if let Some(f) = FN_USE_PROGRAM { f(SHADER_PROGRAM); }
    }

    /// Check if FBO rendering is supported
    pub unsafe fn has_fbo_support() -> bool {
        FN_GEN_FRAMEBUFFERS.is_some() && FN_BIND_FRAMEBUFFER.is_some()
            && FN_FRAMEBUFFER_TEXTURE_2D.is_some() && FN_CHECK_FRAMEBUFFER_STATUS.is_some()
    }

    /// Begin rendering to the scene FBO (call before rendering all windows)
    /// Returns true if scene FBO is active, false if rendering directly to default framebuffer
    pub unsafe fn begin_scene_render(width: u32, height: u32) -> bool {
        if !has_fbo_support() {
            return false;
        }

        // Check if we need to create or resize the scene FBO
        let need_new_fbo = SCENE_FBO == 0
            || SCENE_WIDTH != width
            || SCENE_HEIGHT != height;

        if need_new_fbo {
            // Clean up old resources
            if SCENE_FBO != 0 {
                if let Some(f) = FN_DELETE_FRAMEBUFFERS { f(1, &SCENE_FBO); }
            }
            if SCENE_TEXTURE != 0 {
                if let Some(f) = FN_DELETE_TEXTURES { f(1, &SCENE_TEXTURE); }
            }

            // Create texture for scene FBO
            if let Some(f) = FN_GEN_TEXTURES { f(1, &mut SCENE_TEXTURE); }
            if let Some(f) = FN_BIND_TEXTURE { f(TEXTURE_2D, SCENE_TEXTURE); }

            // Allocate texture storage
            if let Some(f) = FN_TEX_IMAGE_2D {
                f(TEXTURE_2D, 0, RGBA as i32, width as i32, height as i32, 0, RGBA, UNSIGNED_BYTE, std::ptr::null());
            }
            if let Some(f) = FN_TEX_PARAMETERI {
                f(TEXTURE_2D, TEXTURE_MIN_FILTER, LINEAR);
                f(TEXTURE_2D, TEXTURE_MAG_FILTER, LINEAR);
                f(TEXTURE_2D, 0x2802, 0x812F); // CLAMP_TO_EDGE
                f(TEXTURE_2D, 0x2803, 0x812F); // CLAMP_TO_EDGE
            }

            // Create FBO and attach texture
            if let Some(f) = FN_GEN_FRAMEBUFFERS { f(1, &mut SCENE_FBO); }
            if let Some(f) = FN_BIND_FRAMEBUFFER { f(GL_FRAMEBUFFER, SCENE_FBO); }
            if let Some(f) = FN_FRAMEBUFFER_TEXTURE_2D {
                f(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, TEXTURE_2D, SCENE_TEXTURE, 0);
            }

            // Check FBO status
            if let Some(f) = FN_CHECK_FRAMEBUFFER_STATUS {
                let status = f(GL_FRAMEBUFFER);
                if status != GL_FRAMEBUFFER_COMPLETE {
                    tracing::error!("Scene FBO incomplete: {:#x}", status);
                    // Fall back to direct rendering
                    if let Some(bind) = FN_BIND_FRAMEBUFFER { bind(GL_FRAMEBUFFER, 0); }
                    return false;
                }
            }

            SCENE_WIDTH = width;
            SCENE_HEIGHT = height;
            tracing::info!("Created scene FBO {}x{} for distortion", width, height);
        } else {
            // Bind existing scene FBO
            if let Some(f) = FN_BIND_FRAMEBUFFER { f(GL_FRAMEBUFFER, SCENE_FBO); }
        }

        // Set viewport
        if let Some(f) = FN_VIEWPORT {
            f(0, 0, width as i32, height as i32);
        }

        SCENE_RENDERING_ACTIVE = true;
        true
    }

    /// End scene rendering and switch back to default framebuffer
    pub unsafe fn end_scene_render() {
        if !SCENE_RENDERING_ACTIVE {
            return;
        }

        // Use glFinish to ensure all rendering to the FBO is complete before we use its texture
        // glFlush wasn't enough - tiled GPUs need full sync to avoid diagonal tear artifacts
        Finish();

        // Unbind scene FBO, switch to default framebuffer
        if let Some(f) = FN_BIND_FRAMEBUFFER { f(GL_FRAMEBUFFER, 0); }
        SCENE_RENDERING_ACTIVE = false;
    }

    /// Check if scene texture is available for distortion
    pub unsafe fn has_scene_texture() -> bool {
        SCENE_TEXTURE != 0 && !SCENE_RENDERING_ACTIVE
    }

    /// Get the scene texture ID for use in distortion shader
    pub unsafe fn get_scene_texture() -> u32 {
        SCENE_TEXTURE
    }

    // Static resources for preview capture
    static mut PREVIEW_FBO: u32 = 0;
    static mut PREVIEW_TEXTURE: u32 = 0;
    static mut PREVIEW_TEX_WIDTH: u32 = 0;
    static mut PREVIEW_TEX_HEIGHT: u32 = 0;

    /// Read pixels from an EGL texture for preview capture
    /// This works by rendering the texture to an intermediate FBO, then reading from that
    /// Returns RGBA pixels if successful, None if readback not supported
    pub unsafe fn read_texture_pixels(texture_id: u32, width: u32, height: u32) -> Option<Vec<u8>> {
        // Need FBO, texture, and shader support
        let gen_fbo = FN_GEN_FRAMEBUFFERS?;
        let bind_fbo = FN_BIND_FRAMEBUFFER?;
        let attach_tex = FN_FRAMEBUFFER_TEXTURE_2D?;
        let check_status = FN_CHECK_FRAMEBUFFER_STATUS?;
        let read_pixels = FN_READ_PIXELS?;
        let gen_textures = FN_GEN_TEXTURES?;
        let bind_texture = FN_BIND_TEXTURE?;
        let tex_image = FN_TEX_IMAGE_2D?;
        let tex_param = FN_TEX_PARAMETERI?;
        let viewport = FN_VIEWPORT?;
        let clear = FN_CLEAR?;
        let clear_color = FN_CLEAR_COLOR?;
        let get_integerv = FN_GET_INTEGERV?;

        if SHADER_PROGRAM == 0 {
            return None;
        }

        // Save current GL state
        let mut saved_fbo: i32 = 0;
        let mut saved_viewport: [i32; 4] = [0; 4];
        let mut saved_texture: i32 = 0;
        let mut saved_program: i32 = 0;
        get_integerv(GL_FRAMEBUFFER_BINDING, &mut saved_fbo);
        get_integerv(0x0BA2, saved_viewport.as_mut_ptr()); // GL_VIEWPORT
        get_integerv(GL_TEXTURE_BINDING_2D, &mut saved_texture);
        get_integerv(GL_CURRENT_PROGRAM, &mut saved_program);

        // Create or resize preview FBO and texture if needed
        if PREVIEW_FBO == 0 || PREVIEW_TEX_WIDTH != width || PREVIEW_TEX_HEIGHT != height {
            // Delete old resources
            if PREVIEW_FBO != 0 {
                if let Some(del_fbo) = FN_DELETE_FRAMEBUFFERS {
                    del_fbo(1, &PREVIEW_FBO);
                }
            }
            if PREVIEW_TEXTURE != 0 {
                if let Some(del_tex) = FN_DELETE_TEXTURES {
                    del_tex(1, &PREVIEW_TEXTURE);
                }
            }

            // Create new texture
            gen_textures(1, &mut PREVIEW_TEXTURE);
            bind_texture(TEXTURE_2D, PREVIEW_TEXTURE);
            tex_image(TEXTURE_2D, 0, RGBA as i32, width as i32, height as i32, 0, RGBA, UNSIGNED_BYTE, std::ptr::null());
            tex_param(TEXTURE_2D, TEXTURE_MIN_FILTER, LINEAR);
            tex_param(TEXTURE_2D, TEXTURE_MAG_FILTER, LINEAR);

            // Create new FBO
            gen_fbo(1, &mut PREVIEW_FBO);
            bind_fbo(GL_FRAMEBUFFER, PREVIEW_FBO);
            attach_tex(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, TEXTURE_2D, PREVIEW_TEXTURE, 0);

            let status = check_status(GL_FRAMEBUFFER);
            if status != GL_FRAMEBUFFER_COMPLETE {
                bind_fbo(GL_FRAMEBUFFER, 0);
                return None;
            }

            PREVIEW_TEX_WIDTH = width;
            PREVIEW_TEX_HEIGHT = height;
        }

        // Bind our preview FBO
        bind_fbo(GL_FRAMEBUFFER, PREVIEW_FBO);
        viewport(0, 0, width as i32, height as i32);

        // Clear to transparent
        clear_color(0.0, 0.0, 0.0, 0.0);
        clear(0x00004000); // GL_COLOR_BUFFER_BIT

        // Render the source texture to our FBO using the shader
        // Set up shader
        if let Some(use_prog) = FN_USE_PROGRAM { use_prog(SHADER_PROGRAM); }
        if let Some(active_tex) = FN_ACTIVE_TEXTURE { active_tex(0x84C0); } // GL_TEXTURE0
        bind_texture(TEXTURE_2D, texture_id);
        if let Some(uniform) = FN_UNIFORM1I { uniform(UNIFORM_TEXTURE, 0); }

        // Full-screen quad vertices (fills the FBO)
        let vertices: [f32; 16] = [
            -1.0, -1.0,    0.0, 1.0,  // bottom-left
             1.0, -1.0,    1.0, 1.0,  // bottom-right
            -1.0,  1.0,    0.0, 0.0,  // top-left
             1.0,  1.0,    1.0, 0.0,  // top-right
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

        if let Some(f) = FN_DRAW_ARRAYS {
            f(TRIANGLE_STRIP, 0, 4);
        }

        Finish();

        // Now read the pixels from our preview FBO
        let size = (width * height * 4) as usize;
        let mut pixels = vec![0u8; size];
        read_pixels(0, 0, width as i32, height as i32, RGBA, UNSIGNED_BYTE, pixels.as_mut_ptr() as *mut c_void);

        // Restore GL state
        bind_fbo(GL_FRAMEBUFFER, saved_fbo as u32);
        viewport(saved_viewport[0], saved_viewport[1], saved_viewport[2], saved_viewport[3]);
        bind_texture(TEXTURE_2D, saved_texture as u32);
        if let Some(use_prog) = FN_USE_PROGRAM { use_prog(saved_program as u32); }

        // Flip vertically (OpenGL has origin at bottom-left, we need top-left)
        let row_size = (width * 4) as usize;
        let mut flipped = vec![0u8; size];
        for y in 0..height as usize {
            let src_row = (height as usize - 1 - y) * row_size;
            let dst_row = y * row_size;
            flipped[dst_row..dst_row + row_size].copy_from_slice(&pixels[src_row..src_row + row_size]);
        }

        Some(flipped)
    }
}

/// Initialize XWayland for X11 application support
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
