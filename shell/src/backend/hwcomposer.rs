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

    info!("HWComposer display initialized successfully via shim");

    Ok(HwcDisplay {
        hwc_ctx,
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

            // Power button (evdev keycode 116) - toggle dim/wake on lock screen, or lock
            if evdev_keycode == 116 && pressed {
                if state.shell.lock_screen_active {
                    if state.shell.lock_screen_dimmed {
                        // Wake the dimmed lock screen
                        info!("Power button pressed, waking dimmed lock screen");
                        state.shell.wake_lock_screen();
                    } else {
                        // Dim the lock screen immediately
                        info!("Power button pressed, dimming lock screen");
                        state.shell.lock_screen_dimmed = true;
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.set_lock_screen_dimmed(true);
                        }
                    }
                } else {
                    // Lock the screen
                    info!("Power button pressed, locking screen");
                    state.shell.lock();
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
            let position = event.position_transformed(state.screen_size);
            let touch_pos = Point::from((position.x, position.y));

            // Update last activity time for auto-lock
            state.last_activity = std::time::Instant::now();

            // If lock screen is active, handle touch
            if state.shell.lock_screen_active {
                if state.shell.lock_screen_dimmed {
                    // Require double-tap to wake dimmed screen
                    const DOUBLE_TAP_MS: u128 = 400; // Max time between taps
                    let now = std::time::Instant::now();
                    if let Some(last_tap) = state.shell.lock_screen_last_tap {
                        if now.duration_since(last_tap).as_millis() < DOUBLE_TAP_MS {
                            // Double tap detected - wake screen
                            info!("Double-tap detected, waking lock screen");
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
                    // Not dimmed - reset activity timer
                    state.shell.reset_lock_screen_activity();
                }
            }

            // Track touch position
            state.last_touch_pos.insert(slot_id, touch_pos);

            // Forward to gesture recognizer
            if let Some(gesture_event) = state.gesture_recognizer.touch_down(slot_id, touch_pos) {
                debug!("Gesture touch_down: {:?}", gesture_event);

                // Handle edge swipe start for quick settings, app switcher, and home/close gestures
                if let crate::input::GestureEvent::EdgeSwipeStart { edge, .. } = &gesture_event {
                    let shell_view = state.shell.view;
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
            // Never forward to Wayland when lock screen is active - Slint handles lock screen touch
            if has_wayland_window && !touch_on_keyboard && shell_view == crate::shell::ShellView::App && !state.shell.lock_screen_active {
                if let Some(touch) = state.seat.get_touch() {
                    let serial = smithay::utils::SERIAL_COUNTER.next_serial();

                    // For mobile fullscreen apps, use keyboard focus to determine which window gets touch
                    // This ensures the focused/topmost window receives touch events
                    let focus = state.seat.get_keyboard()
                        .and_then(|kb| kb.current_focus())
                        .map(|surface| (surface, smithay::utils::Point::from((0.0, 0.0))));

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
            } else {
                // Forward to Slint UI based on current view
                match shell_view {
                    crate::shell::ShellView::Home => {
                        // Hit test to find which category was touched
                        let touched_category = state.shell.hit_test_category(touch_pos);

                        // If touching a category, use start_category_touch for app launching
                        if let Some(category) = touched_category {
                            info!("Touch down on category {:?}", category);
                            state.shell.start_category_touch(touch_pos, category);
                        } else {
                            // Not on a category - just track for scrolling
                            state.shell.start_home_touch(touch_pos.y, None);
                        }

                        // Forward to Slint for visual feedback
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.dispatch_pointer_pressed(touch_pos.x as f32, touch_pos.y as f32);
                        }
                    }
                    crate::shell::ShellView::LockScreen => {
                        // Forward to Slint for lock screen interaction
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
                        // Touch on keyboard overlay - forward to Slint
                        if touch_on_keyboard {
                            info!("Keyboard TouchDown at ({}, {})", touch_pos.x, touch_pos.y);
                            if let Some(ref slint_ui) = state.shell.slint_ui {
                                slint_ui.dispatch_pointer_pressed(touch_pos.x as f32, touch_pos.y as f32);
                            }
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
            let position = event.position_transformed(state.screen_size);
            let touch_pos = Point::from((position.x, position.y));

            // Update tracked touch position
            state.last_touch_pos.insert(slot_id, touch_pos);

            // Forward to gesture recognizer
            if let Some(gesture_event) = state.gesture_recognizer.touch_motion(slot_id, touch_pos) {
                debug!("Gesture touch_motion: {:?}", gesture_event);

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
            // Never forward to Wayland when lock screen is active - Slint handles lock screen touch
            if has_wayland_window && !touch_on_keyboard && shell_view == crate::shell::ShellView::App && !state.shell.lock_screen_active {
                if let Some(touch) = state.seat.get_touch() {
                    // For mobile fullscreen apps, use keyboard focus to determine which window gets touch
                    let focus = state.seat.get_keyboard()
                        .and_then(|kb| kb.current_focus())
                        .map(|surface| (surface, smithay::utils::Point::from((0.0, 0.0))));

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
            } else {
                // Forward to Slint UI based on current view
                match shell_view {
                    crate::shell::ShellView::Home => {
                        // Forward to Slint for scroll/drag feedback
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.dispatch_pointer_moved(touch_pos.x as f32, touch_pos.y as f32);
                        }
                    }
                    crate::shell::ShellView::LockScreen => {
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.dispatch_pointer_moved(touch_pos.x as f32, touch_pos.y as f32);

                            // Poll and process lock screen actions during motion (for pattern drawing)
                            use crate::shell::slint_ui::LockScreenAction;
                            let actions = slint_ui.poll_lock_actions();
                            for action in &actions {
                                match action {
                                    LockScreenAction::PatternNode(idx) => {
                                        let idx_u8 = *idx as u8;
                                        if !state.shell.lock_state.pattern_nodes.contains(&idx_u8) {
                                            state.shell.lock_state.pattern_nodes.push(idx_u8);
                                        }
                                    }
                                    LockScreenAction::PatternStarted => {
                                        state.shell.lock_state.pattern_active = true;
                                        state.shell.lock_state.pattern_nodes.clear();
                                    }
                                    _ => {} // Other actions handled on touch up
                                }
                            }

                            // Update pattern nodes UI immediately
                            if !actions.is_empty() {
                                let mut nodes = [false; 9];
                                for &n in &state.shell.lock_state.pattern_nodes {
                                    if (n as usize) < 9 {
                                        nodes[n as usize] = true;
                                    }
                                }
                                slint_ui.set_pattern_nodes(&nodes);
                            }
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
                        // Touch motion on keyboard overlay - forward to Slint
                        if touch_on_keyboard {
                            if let Some(ref slint_ui) = state.shell.slint_ui {
                                slint_ui.dispatch_pointer_moved(touch_pos.x as f32, touch_pos.y as f32);
                            }
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
                            // Open Quick Settings
                            state.shell.view = crate::shell::ShellView::QuickSettings;
                            state.system.refresh();
                            state.shell.sync_quick_settings(&state.system);
                            info!("Quick Settings OPENED via gesture");
                        }
                        state.qs_gesture_active = false;
                        state.qs_gesture_progress = 0.0;
                    }
                    // Right edge = App Switcher
                    if *edge == crate::input::Edge::Right {
                        if *completed && state.switcher_gesture_active {
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

                                        (i as i32, title, app_class, i as i32)
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
            // Never forward to Wayland when lock screen is active - Slint handles lock screen touch
            if has_wayland_window && !touch_on_keyboard && shell_view == crate::shell::ShellView::App && !state.shell.lock_screen_active {
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

                        // End home touch tracking - returns pending app if it was a tap (not scroll)
                        if let Some(exec) = state.shell.end_home_touch() {
                            info!("Launching app from home touch: {}", exec);
                            // Get socket name for WAYLAND_DISPLAY
                            let socket_name = state.socket_name.to_str().unwrap_or("wayland-1");
                            // Get text scale for app scaling
                            let text_scale = state.shell.text_scale;
                            let qt_scale = format!("{}", text_scale);
                            let gdk_scale = format!("{}", text_scale.round() as i32);
                            std::process::Command::new("sh")
                                .arg("-c")
                                .arg(&exec)
                                .env("WAYLAND_DISPLAY", socket_name)
                                // Force software rendering so apps use SHM buffers
                                // hwcomposer can't handle EGL/DMA-BUF buffers from apps
                                .env("LIBGL_ALWAYS_SOFTWARE", "1")
                                .env("GDK_BACKEND", "wayland")
                                // GTK4 specific - force Cairo rendering instead of GPU
                                .env("GSK_RENDERER", "cairo")
                                .env("GDK_RENDERING", "image")
                                // Disable hardware acceleration hints
                                .env("GALLIUM_DRIVER", "llvmpipe")
                                .env("__EGL_VENDOR_LIBRARY_FILENAMES", "")
                                // Also set for Qt apps
                                .env("QT_QUICK_BACKEND", "software")
                                .env("QT_OPENGL", "software")
                                // Text/UI scaling for apps from settings
                                .env("QT_SCALE_FACTOR", &qt_scale)
                                .env("QT_FONT_DPI", format!("{}", (96.0 * text_scale) as i32))
                                .env("GDK_SCALE", &gdk_scale)
                                .env("GDK_DPI_SCALE", &qt_scale)
                                .spawn()
                                .ok();

                            // Switch to App view to show the window
                            state.shell.view = crate::shell::ShellView::App;
                        }
                    }
                    crate::shell::ShellView::LockScreen => {
                        use crate::shell::slint_ui::LockScreenAction;

                        // Dispatch to Slint
                        if let Some(pos) = last_pos {
                            if let Some(ref slint_ui) = state.shell.slint_ui {
                                slint_ui.dispatch_pointer_released(pos.x as f32, pos.y as f32);
                            }
                        }

                        // Poll lock actions from Slint
                        let actions: Vec<LockScreenAction> = if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.poll_lock_actions()
                        } else {
                            Vec::new()
                        };

                        // Track if we need to show keyboard or update mode
                        let mut show_keyboard = false;
                        let mut switch_to_password = false;

                        // Process actions
                        for action in &actions {
                            match action {
                                LockScreenAction::PinDigit(digit) => {
                                    if state.shell.lock_state.entered_pin.len() < 6 {
                                        state.shell.lock_state.entered_pin.push_str(digit);
                                    }
                                }
                                LockScreenAction::PinBackspace => {
                                    state.shell.lock_state.entered_pin.pop();
                                }
                                LockScreenAction::PatternNode(idx) => {
                                    let idx_u8 = *idx as u8;
                                    if !state.shell.lock_state.pattern_nodes.contains(&idx_u8) {
                                        state.shell.lock_state.pattern_nodes.push(idx_u8);
                                    }
                                }
                                LockScreenAction::PatternStarted => {
                                    state.shell.lock_state.pattern_active = true;
                                    state.shell.lock_state.pattern_nodes.clear();
                                }
                                LockScreenAction::PatternComplete => {
                                    state.shell.lock_state.pattern_active = false;
                                    if state.shell.lock_state.pattern_nodes.len() >= 4 {
                                        state.shell.try_unlock();
                                    } else if !state.shell.lock_state.pattern_nodes.is_empty() {
                                        state.shell.lock_state.error_message = Some("Pattern too short (min 4 dots)".to_string());
                                    }
                                    state.shell.lock_state.pattern_nodes.clear();
                                }
                                LockScreenAction::UsePassword => {
                                    state.shell.lock_state.switch_to_password();
                                    switch_to_password = true;
                                    info!("Switched to password mode");
                                }
                                LockScreenAction::PasswordFieldTapped => {
                                    show_keyboard = true;
                                    info!("Password field tapped - showing keyboard");
                                }
                                LockScreenAction::PasswordSubmit => {
                                    info!("Password submit - attempting PAM auth");
                                    state.shell.try_unlock();
                                }
                                LockScreenAction::WakeScreen => {
                                    info!("Wake screen requested");
                                    state.shell.wake_lock_screen();
                                }
                            }
                            // Reset activity on any lock screen action
                            state.shell.reset_lock_screen_activity();
                        }

                        // Update Slint UI
                        if !actions.is_empty() {
                            if let Some(ref slint_ui) = state.shell.slint_ui {
                                slint_ui.set_pin_length(state.shell.lock_state.entered_pin.len() as i32);
                                slint_ui.set_password_length(state.shell.lock_state.entered_password.len() as i32);

                                // Update pattern nodes
                                let mut nodes = [false; 9];
                                for &n in &state.shell.lock_state.pattern_nodes {
                                    if (n as usize) < 9 {
                                        nodes[n as usize] = true;
                                    }
                                }
                                slint_ui.set_pattern_nodes(&nodes);

                                if let Some(ref err) = state.shell.lock_state.error_message {
                                    slint_ui.set_lock_error(err);
                                }

                                if switch_to_password {
                                    slint_ui.set_lock_mode("password");
                                }

                                if show_keyboard {
                                    slint_ui.set_keyboard_visible(true);
                                }
                            }
                        }

                        // Try to unlock if PIN is long enough
                        if state.shell.lock_state.entered_pin.len() >= 4 {
                            if state.shell.try_unlock() {
                                info!("Lock screen unlocked!");
                            } else {
                                // Failed attempt - reset PIN
                                state.shell.lock_state.entered_pin.clear();
                                if let Some(ref slint_ui) = state.shell.slint_ui {
                                    slint_ui.set_pin_length(0);
                                }
                            }
                        }

                        // Handle keyboard input for password entry
                        if touch_on_keyboard {
                            if let Some(pos) = last_pos {
                                info!("LockScreen Keyboard TouchUp at ({}, {})", pos.x, pos.y);

                                use crate::shell::slint_ui::KeyboardAction;
                                let actions = if let Some(ref slint_ui) = state.shell.slint_ui {
                                    slint_ui.dispatch_pointer_released(pos.x as f32, pos.y as f32);
                                    slint_ui.take_pending_keyboard_actions()
                                } else {
                                    Vec::new()
                                };

                                // Process keyboard actions - add to password
                                for action in actions {
                                    info!("LockScreen KB ACTION: {:?}", action);
                                    match action {
                                        KeyboardAction::Character(ch) => {
                                            state.shell.lock_state.entered_password.push_str(&ch);
                                        }
                                        KeyboardAction::Backspace => {
                                            state.shell.lock_state.entered_password.pop();
                                        }
                                        KeyboardAction::Enter => {
                                            // Submit password
                                            info!("Password submit via Enter key");
                                            state.shell.try_unlock();
                                        }
                                        KeyboardAction::Space => {
                                            state.shell.lock_state.entered_password.push(' ');
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
                                        }
                                    }
                                }

                                // Update password length in UI
                                if let Some(ref slint_ui) = state.shell.slint_ui {
                                    slint_ui.set_password_length(state.shell.lock_state.entered_password.len() as i32);
                                }
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
                                        QuickSettingsAction::RotationToggle => {
                                            state.system.rotation_lock.toggle();
                                            info!("Rotation lock: {}", if state.system.rotation_lock.locked { "ON" } else { "OFF" });
                                        }
                                        QuickSettingsAction::TouchEffectsToggle => {
                                            let enabled = !state.touch_effects_enabled;
                                            state.set_touch_effects_enabled(enabled);
                                            info!("Touch effects: {}", if enabled { "ON" } else { "OFF" });
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
                                                let exec_clone = exec.clone();
                                                let text_scale = state.shell.text_scale;
                                                let socket = state.socket_name.to_str().unwrap_or("wayland-1").to_string();
                                                std::thread::spawn(move || {
                                                    let qt_scale = format!("{}", text_scale);
                                                    let gdk_scale = format!("{}", text_scale.round() as i32);
                                                    if let Err(e) = std::process::Command::new("/bin/sh")
                                                        .arg("-c")
                                                        .arg(&exec_clone)
                                                        .env("WAYLAND_DISPLAY", &socket)
                                                        .env("QT_SCALE_FACTOR", &qt_scale)
                                                        .env("QT_FONT_DPI", format!("{}", (96.0 * text_scale) as i32))
                                                        .env("GDK_SCALE", &gdk_scale)
                                                        .env("GDK_DPI_SCALE", &qt_scale)
                                                        .spawn()
                                                    {
                                                        error!("Failed to launch settings app: {}", e);
                                                    }
                                                });
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
                                        let windows: Vec<_> = state.space.elements().cloned().collect();
                                        if let Some(window) = windows.get(window_id) {
                                            // Raise window to top
                                            let loc = state.space.element_location(window).unwrap_or_default();
                                            state.space.map_element(window.clone(), loc, true);

                                            // Set keyboard focus
                                            if let Some(toplevel) = window.toplevel() {
                                                let serial = smithay::utils::SERIAL_COUNTER.next_serial();
                                                if let Some(keyboard) = state.seat.get_keyboard() {
                                                    keyboard.set_focus(state, Some(toplevel.wl_surface().clone()), serial);
                                                }
                                            } else if let Some(x11) = window.x11_surface() {
                                                if let Some(wl_surface) = x11.wl_surface() {
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
                        // Touch up on keyboard overlay - forward to Slint
                        if touch_on_keyboard {
                            if let Some(pos) = last_pos {
                                info!("Keyboard TouchUp at ({}, {})", pos.x, pos.y);

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
                                        }
                                    }
                                }
                            }
                        }
                    }
                    _ => {}
                }
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

    // Update state with actual screen size from hwc_display
    // (may differ from initial estimate if shim got real dimensions)
    let width = hwc_display.width;
    let height = hwc_display.height;
    state.screen_size = (width as i32, height as i32).into();
    state.gesture_recognizer.screen_size = state.screen_size;
    state.shell.screen_size = state.screen_size;
    state.shell.quick_settings.screen_size = state.screen_size;

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

        // Check for unlock signal from external lock screen app (QML lockscreen)
        if state.shell.check_unlock_signal() {
            info!("=== UNLOCK SIGNAL DETECTED (hwcomposer) ===");
            info!("Before unlock: view={:?}, lock_screen_active={}", state.shell.view, state.shell.lock_screen_active);

            // Close all windows (the QML lock screen) from the space
            let windows_to_close: Vec<_> = state.space.elements().cloned().collect();
            info!("Closing {} windows from space after unlock", windows_to_close.len());
            for window in windows_to_close {
                state.space.unmap_elem(&window);
                if let Some(toplevel) = window.toplevel() {
                    toplevel.send_close();
                }
            }

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

        // Skip rendering if session not active
        if !*session_active.borrow() {
            debug!("Loop {}: session not active, skipping render", loop_count);
            continue;
        }

        // Check if lock screen should be dimmed (power saving)
        if state.shell.view == crate::shell::ShellView::LockScreen {
            state.shell.check_lock_screen_dim();
        }

        // Periodic system refresh (battery, wifi, etc.) - every 10 seconds
        if state.system_last_refresh.elapsed().as_secs() >= 10 {
            state.system.refresh();
            state.shell.sync_quick_settings(&state.system);
            state.system_last_refresh = std::time::Instant::now();
        }

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

    // Set viewport to full screen
    unsafe {
        if let Some(f) = gl::FN_VIEWPORT {
            f(0, 0, display.width as i32, display.height as i32);
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

        // Render Slint UI for shell views
        // Always render Slint for lock screen (we use Slint lock screen, not QML anymore)
        // Also render during switcher gesture preview
        if !qml_lockscreen_connected || shell_view == ShellView::LockScreen {
            match shell_view {
                ShellView::Home | ShellView::QuickSettings | ShellView::Switcher | ShellView::PickDefault | ShellView::LockScreen
                if !switcher_gesture_preview => {
                    // Update Slint timers and animations (needed for clock updates, etc.)
                    slint::platform::update_timers_and_animations();

                    // Set up Slint UI state based on current view
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        match shell_view {
                            ShellView::LockScreen => {
                                // Use built-in Slint lock screen
                                slint_ui.set_view("lock");

                                // Set lock mode based on config
                                let lock_mode = match state.shell.lock_config.method {
                                    crate::shell::lock_screen::LockMethod::Pin => "pin",
                                    crate::shell::lock_screen::LockMethod::Pattern => "pattern",
                                    crate::shell::lock_screen::LockMethod::Password => "password",
                                    crate::shell::lock_screen::LockMethod::None => "none",
                                };
                                slint_ui.set_lock_mode(lock_mode);

                                // Update lock screen state
                                slint_ui.set_pin_length(state.shell.lock_state.entered_pin.len() as i32);
                                slint_ui.set_password_length(state.shell.lock_state.entered_password.len() as i32);

                                // Update pattern nodes
                                let mut nodes = [false; 9];
                                for &n in &state.shell.lock_state.pattern_nodes {
                                    if (n as usize) < 9 {
                                        nodes[n as usize] = true;
                                    }
                                }
                                slint_ui.set_pattern_nodes(&nodes);

                                // Show error message if any
                                if let Some(ref err) = state.shell.lock_state.error_message {
                                    slint_ui.set_lock_error(err);
                                } else {
                                    slint_ui.set_lock_error("");
                                }

                                // Update battery and text scale for lock screen
                                slint_ui.set_battery_percent(state.shell.quick_settings.battery_percent as i32);
                                slint_ui.set_text_scale(state.shell.text_scale);

                                // Only update animations and time when not dimmed (power saving)
                                if !state.shell.lock_screen_dimmed {
                                    // Update time/date for lock screen
                                    let now = chrono::Local::now();
                                    slint_ui.set_lock_time(&now.format("%H:%M").to_string());
                                    slint_ui.set_lock_date(&now.format("%A, %B %d").to_string());

                                    // Update star twinkling animation time
                                    let elapsed = state.start_time.elapsed().as_secs_f32();
                                    slint_ui.set_star_time(elapsed);
                                }
                            }
                            ShellView::Home => {
                                slint_ui.set_view("home");
                                let slint_categories = state.shell.get_categories_with_icons();
                                slint_ui.set_categories(slint_categories);
                                slint_ui.set_show_popup(state.shell.popup_showing);
                                slint_ui.set_wiggle_mode(state.shell.wiggle_mode);
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
                                slint_ui.set_wifi_enabled(state.system.wifi_enabled);
                                slint_ui.set_bluetooth_enabled(state.system.bluetooth_enabled);
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

                                        (i as i32, title, app_class, i as i32)
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

                            (i as i32, title, app_class, i as i32)
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

        // Render Wayland windows ONLY for App view (not during switcher gesture preview)
        // NEVER render client windows when lock screen is active - Slint handles the lock UI
        if shell_view == ShellView::App && !switcher_gesture_preview && !state.shell.lock_screen_active {
            // Render Wayland client surfaces (windows)
            let windows: Vec<_> = state.space.elements().cloned().collect();
            debug!("Rendering {} Wayland windows", windows.len());

            for (i, window) in windows.iter().enumerate() {
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

                    // Get stored buffer from surface user data
                    let buffer_info: Option<(u32, u32, Vec<u8>)> = compositor::with_states(&wl_surface, |data| {
                        debug!("  stored: inside with_states");
                        use std::cell::RefCell;
                        use crate::state::SurfaceBufferData;

                        if let Some(buffer_data) = data.data_map.get::<RefCell<SurfaceBufferData>>() {
                            let data = buffer_data.borrow();
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

                    // Render outside of with_states to avoid holding locks
                    if let Some((width, height, pixels)) = buffer_info {
                        // Get window position from space (for close gesture animation)
                        let window_pos = state.space.element_location(window)
                            .unwrap_or_default();

                        // Log periodically - check center pixel
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
                            info!("{} RENDER frame {}: {}x{} at ({},{}) corner=RGBA({},{},{},{}) center=RGBA({},{},{},{})",
                                window_type, frame_num, width, height, window_pos.x, window_pos.y,
                                pixels[0], pixels[1], pixels[2], pixels[3],
                                cr, cg, cb, ca);
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

    static mut INITIALIZED: bool = false;
    static mut SHADER_PROGRAM: u32 = 0;
    static mut ATTR_POSITION: i32 = -1;
    static mut ATTR_TEXCOORD: i32 = -1;
    static mut UNIFORM_TEXTURE: i32 = -1;

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
        // Note: Y is flipped for texcoord because Slint renders top-down
        #[rustfmt::skip]
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

        // Flush to ensure commands are sent to GPU
        Flush();

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

        // Convert screen coordinates to normalized device coordinates (-1 to 1)
        // Screen: (0,0) is top-left, (width, height) is bottom-right
        // NDC: (-1,-1) is bottom-left, (1,1) is top-right
        let sw = screen_width as f32;
        let sh = screen_height as f32;
        let tw = tex_width as f32;
        let th = tex_height as f32;

        // Calculate NDC positions
        let left = (x as f32 / sw) * 2.0 - 1.0;
        let right = ((x as f32 + tw) / sw) * 2.0 - 1.0;
        let top = 1.0 - (y as f32 / sh) * 2.0;
        let bottom = 1.0 - ((y as f32 + th) / sh) * 2.0;

        // Quad vertices with position offset
        #[rustfmt::skip]
        let vertices: [f32; 16] = [
            // Position (x, y)  // TexCoord (u, v)
            left,  bottom,      0.0, 1.0,  // Bottom-left
            right, bottom,      1.0, 1.0,  // Bottom-right
            left,  top,         0.0, 0.0,  // Top-left
            right, top,         1.0, 0.0,  // Top-right
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

        // Flush
        Flush();

        // Cleanup
        if let Some(f) = FN_DISABLE { f(BLEND); }
        if let Some(f) = FN_DELETE_TEXTURES { f(1, &texture); }
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
