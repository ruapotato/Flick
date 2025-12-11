//! Winit backend for development/testing/demos
//!
//! Runs the compositor in a window on X11 or Wayland, useful for:
//! - Development without switching TTYs
//! - Recording demos
//! - Testing different screen sizes
//!
//! This backend uses the shared input handling from `crate::input::handler`
//! to avoid code duplication with the udev (TTY) backend.

use std::time::Duration;

use anyhow::Result;
use tracing::{debug, info, warn};

use smithay::{
    backend::{
        input::{
            AbsolutePositionEvent, Axis, AxisSource, ButtonState, InputEvent,
            KeyboardKeyEvent, MouseButton, PointerAxisEvent, PointerButtonEvent,
        },
        renderer::{
            damage::OutputDamageTracker,
            element::{
                AsRenderElements,
                memory::MemoryRenderBufferRenderElement,
                surface::WaylandSurfaceRenderElement,
            },
            gles::GlesRenderer,
            ImportAll, ImportMem,
        },
        winit::{self, WinitEvent, WinitGraphicsBackend, WinitInput},
    },
    input::{
        keyboard::FilterResult,
        pointer::{AxisFrame, ButtonEvent, MotionEvent},
    },
    output::{Mode, Output, PhysicalProperties, Subpixel},
    reexports::{
        calloop::{
            timer::{TimeoutAction, Timer},
            EventLoop,
        },
        wayland_server::Display,
        winit::platform::pump_events::PumpStatus,
    },
    utils::{Logical, Point, Size, Transform, SERIAL_COUNTER},
};

use crate::{
    input::{GestureEvent, xkb_to_char, process_lock_actions, process_keyboard_actions, handle_home_tap},
    shell::{ShellView, lock_screen::LockInputMode, slint_ui::{KeyboardAction, LockScreenAction, SlintShell}},
    state::Flick,
    Args,
};

/// Parse size string like "720x1440" into (width, height)
fn parse_size(s: &str) -> Option<(i32, i32)> {
    let parts: Vec<&str> = s.split('x').collect();
    if parts.len() == 2 {
        let w = parts[0].parse().ok()?;
        let h = parts[1].parse().ok()?;
        Some((w, h))
    } else {
        None
    }
}

/// Combined render element type for winit backend
smithay::backend::renderer::element::render_elements! {
    pub WinitRenderElement<R> where R: ImportAll + ImportMem;
    Surface=WaylandSurfaceRenderElement<R>,
    Slint=MemoryRenderBufferRenderElement<R>,
}

pub fn run(args: Args) -> Result<()> {
    // Parse size from args
    let (width, height) = parse_size(&args.size).unwrap_or((720, 1440));
    let scale = args.scale;

    // Window size applies scale
    let window_width = (width as f32 * scale) as i32;
    let window_height = (height as f32 * scale) as i32;

    info!("Winit backend: logical size {}x{}, window size {}x{} (scale {})",
          width, height, window_width, window_height, scale);

    // Create event loop
    let mut event_loop: EventLoop<Flick> = EventLoop::try_new()?;
    let loop_handle = event_loop.handle();

    // Initialize winit backend with custom size
    let (mut backend, mut winit_evt) = winit::init_from_attributes::<GlesRenderer>(
        smithay::reexports::winit::window::WindowAttributes::default()
            .with_title("Flick Shell")
            .with_inner_size(smithay::reexports::winit::dpi::LogicalSize::new(
                window_width as f64,
                window_height as f64,
            ))
            .with_resizable(false),
    )
    .map_err(|e| anyhow::anyhow!("Failed to init winit: {:?}", e))?;

    // Create Wayland display
    let display: Display<Flick> = Display::new()?;

    // Create compositor state with the LOGICAL size (not window size)
    let screen_size = Size::from((width, height));
    let mut state = Flick::new(display, loop_handle.clone(), screen_size);

    // Create output for the winit window
    let output = Output::new(
        "winit".to_string(),
        PhysicalProperties {
            size: (width, height).into(),
            subpixel: Subpixel::Unknown,
            make: "Flick".to_string(),
            model: "Winit Window".to_string(),
            serial_number: "Unknown".to_string(),
        },
    );

    let mode = Mode {
        size: (width, height).into(),
        refresh: 60_000,
    };

    // Use Flipped180 transform to handle display orientation
    // This ensures both Slint content and client windows are displayed correctly
    // Input coordinates need to be transformed to match visual coordinates
    output.change_current_state(Some(mode), Some(Transform::Flipped180), None, Some((0, 0).into()));
    output.set_preferred(mode);

    // IMPORTANT: Create the wl_output global so clients can see this output!
    output.create_global::<Flick>(&state.display_handle);

    state.space.map_output(&output, (0, 0));
    state.outputs.push(output.clone());

    info!("Wayland socket: {:?}", state.socket_name);

    // Set WAYLAND_DISPLAY for child processes
    std::env::set_var("WAYLAND_DISPLAY", &state.socket_name);

    // In embedded mode, use the Slint lock screen instead of Python app
    // (Python/SDL2 lock screen doesn't work well in nested compositor)
    if state.shell.lock_screen_active {
        info!("Showing Slint lock screen in embedded mode");
        state.shell.set_view(crate::shell::ShellView::LockScreen);
    }

    // Initialize Slint UI
    if let Some(ref mut slint_ui) = state.shell.slint_ui {
        slint_ui.set_size(screen_size);
    }

    // Create damage tracker for rendering
    let mut damage_tracker = OutputDamageTracker::from_output(&output);

    // Track mouse state for gesture simulation
    let mut mouse_pos: Point<f64, Logical> = Point::from((0.0, 0.0));
    let mut mouse_pressed = false;
    let mut shift_pressed = false;

    // Track for touchscreen tap detection on X11
    // When cursor moves and stops briefly, treat as a tap
    let mut last_motion_time: u32 = 0;
    let mut pending_tap_pos: Option<Point<f64, Logical>> = None;
    let mut recent_synthetic_tap_time: u32 = 0;  // Suppress duplicate TouchDown after synthetic tap
    let mut x11_touch_active = false;  // Track when X11 touchscreen gesture is in progress
    let mut x11_touch_start_pos: Point<f64, Logical> = Point::from((0.0, 0.0));  // Starting position of X11 touch

    // Add a timer for periodic updates (60fps)
    loop_handle
        .insert_source(Timer::immediate(), move |_, _, _state| {
            TimeoutAction::ToDuration(Duration::from_millis(16))
        })
        .expect("Failed to insert timer");

    info!("Entering event loop");
    info!("WAYLAND_DISPLAY={:?} - run clients with this env var", state.socket_name);
    info!("Mouse clicks simulate touch. Click and drag to gesture.");

    // Main event loop
    loop {
        // Process winit events
        let status = winit_evt.dispatch_new_events(|event| {
            match event {
                WinitEvent::Resized { size, .. } => {
                    debug!("Window resized: {:?}", size);
                    // Don't change mode - we keep the logical size fixed
                }

                WinitEvent::Input(input_event) => {
                    debug!("Winit input event: {:?}", input_event);
                    handle_winit_input(
                        &mut state,
                        input_event,
                        &mut mouse_pos,
                        &mut mouse_pressed,
                        &mut shift_pressed,
                        &mut last_motion_time,
                        &mut pending_tap_pos,
                        &mut recent_synthetic_tap_time,
                        &mut x11_touch_active,
                        &mut x11_touch_start_pos,
                        scale,
                        width,
                        height,
                    );
                }

                WinitEvent::Redraw => {
                    // Redraw handled below in main loop
                }

                WinitEvent::CloseRequested => {
                    info!("Close requested, exiting...");
                    std::process::exit(0);
                }

                WinitEvent::Focus(focused) => {
                    debug!("Focus changed: {}", focused);
                }
            }
        });

        if let PumpStatus::Exit(_) = status {
            info!("Winit exit requested");
            break;
        }

        // Check for unlock signal (like udev backend does)
        state.shell.check_unlock_signal();

        // Dispatch calloop events (Wayland clients, etc.)
        event_loop
            .dispatch(Some(Duration::from_millis(1)), &mut state)
            .expect("Failed to dispatch event loop");

        // Process Wayland client requests and flush responses
        // This is CRITICAL for nested apps to work - without this,
        // clients never receive responses to their protocol requests
        state.dispatch_clients();

        // Render frame on every iteration (not just on Redraw events)
        // This ensures the UI updates after input events
        render_frame(&mut state, &mut backend, &output, &mut damage_tracker, scale);
    }

    Ok(())
}

/// Transform input coordinates to match output transform
/// Note: In embedded/windowed mode, Smithay may handle the output transform
/// at the display level, so input coords may not need transformation
fn transform_coords(x: f64, y: f64, _width: i32, _height: i32) -> (f64, f64) {
    // Don't transform - let Smithay handle coordinate mapping
    (x, y)
}

/// Handle winit input events, converting to touch-like gestures
fn handle_winit_input(
    state: &mut Flick,
    event: InputEvent<WinitInput>,
    mouse_pos: &mut Point<f64, Logical>,
    mouse_pressed: &mut bool,
    shift_pressed: &mut bool,
    last_motion_time: &mut u32,
    pending_tap_pos: &mut Option<Point<f64, Logical>>,
    recent_synthetic_tap_time: &mut u32,
    x11_touch_active: &mut bool,
    x11_touch_start_pos: &mut Point<f64, Logical>,
    _scale: f32,
    width: i32,
    height: i32,
) {
    let serial = SERIAL_COUNTER.next_serial();
    let time = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u32;

    match event {
        InputEvent::PointerMotionAbsolute { event, .. } => {
            use smithay::backend::input::AbsolutePositionEvent;

            // Convert from normalized 0-1 coordinates to pixel coordinates
            // Note: Pointer events work correctly - only Touch events have the Smithay bug
            let raw_x = event.x_transformed(width) as f64;
            let raw_y = event.y_transformed(height) as f64;
            // Transform for Flipped180 output
            let (logical_x, logical_y) = transform_coords(raw_x, raw_y, width, height);
            let new_pos = Point::from((logical_x, logical_y));

            // Detect touchscreen taps on X11: when cursor "jumps" to a new position
            // (more than 30px away), treat it as a touchscreen tap immediately
            // This handles touchscreens that only generate PointerMotionAbsolute without TouchDown
            let distance = ((new_pos.x - mouse_pos.x).powi(2) + (new_pos.y - mouse_pos.y).powi(2)).sqrt();
            let time_delta = time.saturating_sub(*last_motion_time);

            // Check if new position is within window bounds
            let in_bounds = new_pos.x >= 0.0 && new_pos.x < width as f64
                         && new_pos.y >= 0.0 && new_pos.y < height as f64;

            // Require cooldown since last synthetic tap to prevent rapid-fire during swipes
            let since_last_synthetic = time.saturating_sub(*recent_synthetic_tap_time);

            // Check if keyboard is visible and we're on keyboard area
            let keyboard_visible = state.shell.slint_ui.as_ref()
                .map(|ui| ui.is_keyboard_visible())
                .unwrap_or(false);
            let keyboard_height = state.get_keyboard_height();
            let keyboard_top = height - keyboard_height;
            let on_keyboard = keyboard_visible && new_pos.y >= keyboard_top as f64;

            // X11 touchscreen gesture handling:
            // - Cursor jump > 30px = finger touched down at new position
            // - Small motion < 30px = finger dragging
            // - Another big jump = finger lifted and touched elsewhere

            if distance > 30.0 && in_bounds && !*mouse_pressed {
                // Cursor jumped significantly - this is a new touch position

                // If there was an active X11 touch, complete it first
                if *x11_touch_active {
                    info!("X11 touch ended (cursor jumped to new position)");

                    // Complete keyboard swipe if active
                    if state.keyboard_dismiss_slot == Some(99) {
                        let offset = state.keyboard_dismiss_offset;
                        if offset < -150.0 {
                            info!("X11 touchscreen keyboard swipe up complete (offset={:.0}), going home", offset);
                            if let Some(ref slint_ui) = state.shell.slint_ui {
                                slint_ui.set_keyboard_visible(false);
                            }
                            state.start_home_gesture();
                            state.end_home_gesture(true);
                        } else if offset > 80.0 {
                            info!("X11 touchscreen keyboard swipe down complete (offset={:.0}), dismissing", offset);
                            if let Some(ref slint_ui) = state.shell.slint_ui {
                                slint_ui.set_keyboard_visible(false);
                            }
                        }
                        state.keyboard_dismiss_slot = None;
                        state.keyboard_dismiss_offset = 0.0;
                        state.keyboard_dismiss_start_y = 0.0;
                    }

                    // Complete the gesture
                    if let Some(gesture_event) = state.gesture_recognizer.touch_up(0) {
                        info!("X11 gesture completed: {:?}", gesture_event);
                        state.shell.handle_gesture(&gesture_event);
                        if let GestureEvent::Tap { position } = &gesture_event {
                            handle_tap(state, *position);
                        }
                    }

                    // Dispatch release to Slint
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_released(mouse_pos.x as f32, mouse_pos.y as f32);
                    }

                    *x11_touch_active = false;
                }

                // Wait for cooldown before starting new touch (to avoid rapid-fire)
                if since_last_synthetic >= 100 {
                    // Start new X11 touch gesture
                    info!("X11 touch started at {:?} (jump={:.1}px)", new_pos, distance);
                    *x11_touch_active = true;
                    *x11_touch_start_pos = new_pos;
                    *recent_synthetic_tap_time = time;

                    // Check if touch is on keyboard area
                    if on_keyboard {
                        state.keyboard_dismiss_slot = Some(99);
                        state.keyboard_dismiss_start_y = new_pos.y;
                        state.keyboard_dismiss_offset = 0.0;
                    }

                    // Start gesture recognition
                    state.gesture_recognizer.touch_down(0, new_pos);

                    // Dispatch to Slint
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_pressed(new_pos.x as f32, new_pos.y as f32);
                    }
                }
            } else if *x11_touch_active && distance < 30.0 {
                // Small motion while X11 touch is active - this is a drag

                // Track keyboard swipe
                if state.keyboard_dismiss_slot == Some(99) {
                    let offset = new_pos.y - state.keyboard_dismiss_start_y;
                    state.keyboard_dismiss_offset = offset;

                    // Check for upward swipe - transition to home gesture
                    if offset < -30.0 && state.home_gesture_window.is_none() {
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.set_keyboard_visible(false);
                        }
                        info!("X11 keyboard swipe up detected (offset={:.0}), starting home gesture", offset);
                        state.start_home_gesture();
                        state.keyboard_dismiss_slot = None;
                    } else if offset > 100.0 {
                        // Swiped down far enough - dismiss keyboard
                        info!("X11 keyboard swipe down complete (offset={:.0}), dismissing", offset);
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.set_keyboard_visible(false);
                        }
                        state.keyboard_dismiss_slot = None;
                        state.keyboard_dismiss_offset = 0.0;
                        state.keyboard_dismiss_start_y = 0.0;
                    }
                }

                // Continue home gesture if active
                if state.home_gesture_window.is_some() && state.keyboard_dismiss_start_y > 0.0 {
                    let total_upward = state.keyboard_dismiss_start_y - new_pos.y;
                    let progress = (total_upward / 300.0).max(0.0);
                    state.update_home_gesture(progress);
                }

                // Feed motion to gesture recognizer
                if let Some(gesture_event) = state.gesture_recognizer.touch_motion(0, new_pos) {
                    state.shell.handle_gesture(&gesture_event);
                }

                // Update Slint with pointer position
                if let Some(ref slint_ui) = state.shell.slint_ui {
                    slint_ui.dispatch_pointer_moved(new_pos.x as f32, new_pos.y as f32);
                }
            }

            // Clear pending tap since we handle immediately now
            *pending_tap_pos = None;

            *mouse_pos = new_pos;
            *last_motion_time = time;

            // If mouse is pressed, this is a drag - feed to gesture recognizer
            if *mouse_pressed {
                // Track keyboard swipe movement (using shared state)
                if state.keyboard_dismiss_slot.is_some() {
                    let offset = mouse_pos.y - state.keyboard_dismiss_start_y;
                    state.keyboard_dismiss_offset = offset;

                    // Check for upward swipe - transition to home gesture
                    let upward_threshold = -30.0; // Start home gesture after 30px upward swipe
                    if offset < upward_threshold && state.home_gesture_window.is_none() {
                        // Swiping up from keyboard - hide keyboard and start going home
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.set_keyboard_visible(false);
                        }
                        info!("Keyboard mouse swipe up detected (offset={:.0}), starting home gesture", offset);
                        state.start_home_gesture();
                        state.keyboard_dismiss_slot = None;
                    }
                }

                // Continue home gesture if active (from keyboard swipe)
                if state.home_gesture_window.is_some() && state.keyboard_dismiss_start_y > 0.0 {
                    let total_upward = state.keyboard_dismiss_start_y - mouse_pos.y;
                    let progress = (total_upward / 300.0).max(0.0);
                    state.update_home_gesture(progress);
                }

                // Simulate touch move
                if let Some(gesture_event) = state.gesture_recognizer.touch_motion(0, *mouse_pos) {
                    state.shell.handle_gesture(&gesture_event);
                }

                // For pointer motion to apps, just send the location
                // (Focus management is simplified for winit backend)
                if let Some(pointer) = state.seat.get_pointer() {
                    pointer.motion(
                        state,
                        None, // Winit: simplified - let Smithay figure out focus
                        &MotionEvent {
                            location: *mouse_pos,
                            serial,
                            time,
                        },
                    );
                }
            }

            // Update Slint UI with pointer position
            if let Some(ref slint_ui) = state.shell.slint_ui {
                if *mouse_pressed {
                    slint_ui.dispatch_pointer_moved(logical_x as f32, logical_y as f32);
                }
            }
        }

        InputEvent::PointerButton { event, .. } => {
            let button = event.button();
            let button_state = event.state();

            info!("PointerButton event: button={:?} state={:?} pos={:?}", button, button_state, mouse_pos);

            // Only handle left click as touch
            if button == Some(MouseButton::Left) {
                // BTN_LEFT = 0x110
                let btn_code = 0x110u32;

                match button_state {
                    ButtonState::Pressed => {
                        *mouse_pressed = true;
                        info!("Mouse click pressed at {:?}", mouse_pos);

                        // Check if click is on keyboard area for swipe-to-dismiss (using shared state)
                        let keyboard_visible = state.shell.slint_ui.as_ref()
                            .map(|ui| ui.is_keyboard_visible())
                            .unwrap_or(false);

                        if keyboard_visible && state.keyboard_dismiss_slot.is_none() {
                            // Keyboard takes up bottom ~22% of screen
                            let keyboard_height = state.get_keyboard_height();
                            let keyboard_top = height - keyboard_height;

                            if mouse_pos.y >= keyboard_top as f64 {
                                // Click started on keyboard - track for potential swipe-to-dismiss
                                state.keyboard_dismiss_slot = Some(0); // Use slot 0 for mouse
                                state.keyboard_dismiss_start_y = mouse_pos.y;
                                state.keyboard_dismiss_offset = 0.0;
                                debug!("Keyboard click started at y={:.0}", mouse_pos.y);
                            }
                        }

                        // Start gesture recognition
                        state.gesture_recognizer.touch_down(0, *mouse_pos);

                        // Dispatch to Slint for UI interaction
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.dispatch_pointer_pressed(
                                mouse_pos.x as f32,
                                mouse_pos.y as f32,
                            );
                        }

                        // Also send pointer button to focused client
                        if let Some(pointer) = state.seat.get_pointer() {
                            pointer.button(
                                state,
                                &ButtonEvent {
                                    button: btn_code,
                                    state: ButtonState::Pressed,
                                    serial,
                                    time,
                                },
                            );
                        }
                    }
                    ButtonState::Released => {
                        *mouse_pressed = false;
                        debug!("Touch up at {:?}", mouse_pos);

                        // Also complete X11 touch gesture if active (some X11 setups send button release)
                        if *x11_touch_active {
                            info!("X11 touch ended (PointerButton released)");

                            // Complete keyboard swipe if active
                            if state.keyboard_dismiss_slot == Some(99) {
                                let offset = state.keyboard_dismiss_offset;
                                if offset < -150.0 {
                                    info!("X11 keyboard swipe up complete (offset={:.0}), going home", offset);
                                    if let Some(ref slint_ui) = state.shell.slint_ui {
                                        slint_ui.set_keyboard_visible(false);
                                    }
                                    state.start_home_gesture();
                                    state.end_home_gesture(true);
                                } else if offset > 80.0 {
                                    info!("X11 keyboard swipe down complete (offset={:.0}), dismissing", offset);
                                    if let Some(ref slint_ui) = state.shell.slint_ui {
                                        slint_ui.set_keyboard_visible(false);
                                    }
                                }
                                state.keyboard_dismiss_slot = None;
                                state.keyboard_dismiss_offset = 0.0;
                                state.keyboard_dismiss_start_y = 0.0;
                            }

                            // Complete the gesture
                            if let Some(gesture_event) = state.gesture_recognizer.touch_up(0) {
                                info!("X11 gesture completed (via button release): {:?}", gesture_event);
                                state.shell.handle_gesture(&gesture_event);
                                if let GestureEvent::Tap { position } = &gesture_event {
                                    handle_tap(state, *position);
                                }
                            }

                            // Dispatch release to Slint and process actions
                            let (actions, pending_app_tap) = if let Some(ref slint_ui) = state.shell.slint_ui {
                                slint_ui.dispatch_pointer_released(mouse_pos.x as f32, mouse_pos.y as f32);
                                (slint_ui.poll_lock_actions(), slint_ui.take_pending_app_tap())
                            } else {
                                (Vec::new(), None)
                            };

                            if state.shell.view == ShellView::LockScreen {
                                process_lock_actions(state, &actions);
                            }

                            // Handle app tap
                            if state.shell.view == ShellView::Home {
                                if let Some(app_index) = pending_app_tap {
                                    let categories = &state.shell.app_manager.config.grid_order;
                                    if (app_index as usize) < categories.len() {
                                        let category = categories[app_index as usize];
                                        info!("App tap from Slint callback: index={} category={:?}", app_index, category);
                                        if let Some(exec) = state.shell.app_manager.get_exec(category) {
                                            info!("Launching app via Slint callback: {}", exec);
                                            std::process::Command::new("sh")
                                                .arg("-c")
                                                .arg(&exec)
                                                .env("WAYLAND_DISPLAY", state.socket_name.to_str().unwrap_or("wayland-1"))
                                                .env_remove("DISPLAY")
                                                .spawn()
                                                .ok();
                                            state.shell.app_launched();
                                        }
                                    }
                                }
                            }

                            *x11_touch_active = false;
                            return;  // Already handled the gesture
                        }

                        // Handle home gesture completion if it was started from keyboard swipe
                        let home_gesture_from_keyboard = state.home_gesture_window.is_some() && state.keyboard_dismiss_start_y > 0.0;
                        if home_gesture_from_keyboard {
                            let total_upward = state.keyboard_dismiss_start_y - mouse_pos.y;
                            let completed = total_upward > 150.0; // Need to swipe up 150px to go home
                            info!("Home gesture from keyboard ended: upward={:.0}px, completed={}", total_upward, completed);
                            state.end_home_gesture(completed);
                            state.keyboard_dismiss_start_y = 0.0;
                        }

                        // Check for keyboard swipe-to-dismiss completion (using shared state)
                        let keyboard_was_dismissed = if state.keyboard_dismiss_slot == Some(0) {
                            let offset = state.keyboard_dismiss_offset;
                            let dismiss_threshold = 80.0; // Pixels to drag down to dismiss

                            if offset > dismiss_threshold {
                                // Dragged down far enough - dismiss keyboard
                                if let Some(ref slint_ui) = state.shell.slint_ui {
                                    info!("Keyboard dismissed by drag down (offset={:.0})", offset);
                                    slint_ui.set_keyboard_visible(false);
                                }
                                true
                            } else {
                                debug!("Keyboard drag too short (offset={:.0}, threshold={})", offset, dismiss_threshold);
                                false
                            }
                        } else {
                            false
                        };
                        // Reset shared state
                        state.keyboard_dismiss_slot = None;
                        state.keyboard_dismiss_offset = 0.0;

                        // Complete gesture
                        if let Some(gesture_event) = state.gesture_recognizer.touch_up(0) {
                            info!("Gesture completed: {:?}", gesture_event);
                            state.shell.handle_gesture(&gesture_event);

                            // Handle tap on home screen (but skip if keyboard was dismissed)
                            if !keyboard_was_dismissed {
                                if let GestureEvent::Tap { position } = &gesture_event {
                                    handle_tap(state, *position);
                                }
                            }
                        }

                        // Dispatch to Slint and process lock screen actions
                        let (actions, pending_app_tap) = if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.dispatch_pointer_released(
                                mouse_pos.x as f32,
                                mouse_pos.y as f32,
                            );
                            (slint_ui.poll_lock_actions(), slint_ui.take_pending_app_tap())
                        } else {
                            (Vec::new(), None)
                        };

                        // Process lock screen actions
                        if state.shell.view == ShellView::LockScreen {
                            process_lock_actions(state, &actions);
                        }

                        // Handle app tap from Slint callback (works even for edge areas)
                        if state.shell.view == ShellView::Home && !keyboard_was_dismissed {
                            if let Some(app_index) = pending_app_tap {
                                let categories = &state.shell.app_manager.config.grid_order;
                                if (app_index as usize) < categories.len() {
                                    let category = categories[app_index as usize];
                                    info!("App tap from Slint callback: index={} category={:?}", app_index, category);
                                    if let Some(exec) = state.shell.app_manager.get_exec(category) {
                                        info!("Launching app via Slint callback: {}", exec);
                                        std::process::Command::new("sh")
                                            .arg("-c")
                                            .arg(&exec)
                                            .env("WAYLAND_DISPLAY", state.socket_name.to_str().unwrap_or("wayland-1"))
                                            .env_remove("DISPLAY")
                                            .spawn()
                                            .ok();
                                        state.shell.app_launched();
                                    }
                                }
                            }
                        }

                        // Send pointer button release
                        if let Some(pointer) = state.seat.get_pointer() {
                            pointer.button(
                                state,
                                &ButtonEvent {
                                    button: btn_code,
                                    state: ButtonState::Released,
                                    serial,
                                    time,
                                },
                            );
                        }
                    }
                }
            }
        }

        InputEvent::Keyboard { event, .. } => {
            let keycode = event.key_code();
            let key_state = event.state();
            let pressed = key_state == smithay::backend::input::KeyState::Pressed;
            let raw_keycode: u32 = keycode.raw();

            // Track shift state (XKB keycodes: Shift_L=50, Shift_R=62)
            if raw_keycode == 50 || raw_keycode == 62 {
                *shift_pressed = pressed;
            }

            // Handle keyboard input for lock screen (PIN and Password modes)
            if state.shell.view == ShellView::LockScreen {
                if state.shell.lock_state.input_mode == LockInputMode::Pin {
                    if pressed {
                        // XKB keycodes: Enter=36, Backspace=22, 0=19, 1-9=10-18
                        match raw_keycode {
                            36 => {
                                // Enter - attempt unlock if we have digits
                                let pin_len = state.shell.lock_state.entered_pin.len();
                                if pin_len >= 4 {
                                    info!("PIN entered via physical keyboard, attempting unlock (len={})", pin_len);
                                    state.shell.try_unlock();
                                }
                            }
                            22 => {
                                // Backspace
                                state.shell.lock_state.entered_pin.pop();
                                let pin_len = state.shell.lock_state.entered_pin.len();
                                info!("PIN backspace via physical keyboard, length: {}", pin_len);
                                if let Some(ref slint_ui) = state.shell.slint_ui {
                                    slint_ui.set_pin_length(pin_len as i32);
                                }
                            }
                            // Number keys: 1-9 are XKB 10-18, 0 is XKB 19
                            10..=19 => {
                                let digit = if raw_keycode == 19 { '0' } else { (b'1' + (raw_keycode - 10) as u8) as char };
                                if state.shell.lock_state.entered_pin.len() < 6 {
                                    state.shell.lock_state.entered_pin.push(digit);
                                    let pin_len = state.shell.lock_state.entered_pin.len();
                                    info!("PIN digit '{}' entered via physical keyboard, length: {}", digit, pin_len);
                                    if let Some(ref slint_ui) = state.shell.slint_ui {
                                        slint_ui.set_pin_length(pin_len as i32);
                                    }
                                    // Try to unlock: silent for 4-5 digits, with reset at 6
                                    if pin_len >= 4 && pin_len < 6 {
                                        state.shell.try_pin_silent();
                                    } else if pin_len == 6 {
                                        state.shell.try_unlock();
                                    }
                                }
                            }
                            _ => {}
                        }
                    }
                    // Don't forward keyboard events to clients when on lock screen
                    return;
                }
                if state.shell.lock_state.input_mode == LockInputMode::Password {
                    if pressed {
                        // XKB keycodes: Enter=36, Backspace=22 (XKB = evdev + 8)
                        match raw_keycode {
                            36 => {
                                // Enter - attempt unlock
                                if !state.shell.lock_state.entered_password.is_empty() {
                                    info!("Password entered, attempting unlock");
                                    state.shell.try_unlock();
                                }
                            }
                            22 => {
                                // Backspace
                                state.shell.lock_state.entered_password.pop();
                                // Update Slint UI with password length
                                if let Some(ref slint_ui) = state.shell.slint_ui {
                                    slint_ui.set_password_length(state.shell.lock_state.entered_password.len() as i32);
                                }
                            }
                            _ => {
                                // Try to convert keycode to character
                                if let Some(c) = xkb_to_char(raw_keycode, *shift_pressed) {
                                    if state.shell.lock_state.entered_password.len() < 64 {
                                        state.shell.lock_state.entered_password.push(c);
                                        // Update Slint UI with password length
                                        if let Some(ref slint_ui) = state.shell.slint_ui {
                                            slint_ui.set_password_length(state.shell.lock_state.entered_password.len() as i32);
                                        }
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
            if let Some(keyboard) = state.seat.get_keyboard() {
                keyboard.input::<(), _>(
                    state,
                    keycode,
                    key_state,
                    serial,
                    time,
                    |_, _, _| FilterResult::Forward::<()>,
                );
            }
        }

        InputEvent::PointerAxis { event, .. } => {
            // Handle scroll wheel
            if let Some(pointer) = state.seat.get_pointer() {
                let horizontal = event.amount(Axis::Horizontal).unwrap_or(0.0);
                let vertical = event.amount(Axis::Vertical).unwrap_or(0.0);

                let mut frame = AxisFrame::new(time).source(AxisSource::Wheel);

                if horizontal != 0.0 {
                    frame = frame.value(Axis::Horizontal, horizontal);
                }
                if vertical != 0.0 {
                    frame = frame.value(Axis::Vertical, vertical);
                }

                pointer.axis(state, frame);
            }
        }

        InputEvent::TouchDown { event, .. } => {
            use smithay::backend::input::TouchEvent;

            // Skip if we just processed a synthetic tap (within 200ms)
            if time.saturating_sub(*recent_synthetic_tap_time) < 200 {
                debug!("Skipping TouchDown - already processed synthetic tap");
                return;
            }

            // Get touch position in pixel coordinates
            // Note: Smithay's winit backend has a bug where touch Y is normalized against width
            // instead of height, so we use y_transformed(width) to get correct pixel Y
            let raw_x = event.x_transformed(width) as f64;
            let raw_y = event.y_transformed(width) as f64;  // Use width due to Smithay bug
            // Transform for Flipped180 output
            let (logical_x, logical_y) = transform_coords(raw_x, raw_y, width, height);
            let touch_pos = Point::from((logical_x, logical_y));

            *mouse_pos = touch_pos;
            *mouse_pressed = true;

            debug!("Touch down at {:?}", touch_pos);

            // Check if touch started on keyboard area for swipe-to-dismiss (using shared state)
            let keyboard_visible = state.shell.slint_ui.as_ref()
                .map(|ui| ui.is_keyboard_visible())
                .unwrap_or(false);

            if keyboard_visible && state.keyboard_dismiss_slot.is_none() {
                // Keyboard takes up bottom ~22% of screen
                let keyboard_height = state.get_keyboard_height();
                let keyboard_top = height - keyboard_height;

                if touch_pos.y >= keyboard_top as f64 {
                    // Touch started on keyboard - track for potential swipe-to-dismiss
                    state.keyboard_dismiss_slot = Some(0); // Use slot 0 for touch
                    state.keyboard_dismiss_start_y = touch_pos.y;
                    state.keyboard_dismiss_offset = 0.0;
                    debug!("Keyboard touch started at y={:.0}", touch_pos.y);
                }
            }

            // Start gesture recognition
            state.gesture_recognizer.touch_down(0, touch_pos);

            // Dispatch to Slint for UI interaction
            if let Some(ref slint_ui) = state.shell.slint_ui {
                slint_ui.dispatch_pointer_pressed(logical_x as f32, logical_y as f32);
            }
        }

        InputEvent::TouchMotion { event, .. } => {
            use smithay::backend::input::TouchEvent;

            // Note: Smithay's winit backend has a bug where touch Y is normalized against width
            // instead of height, so we use y_transformed(width) to get correct pixel Y
            let raw_x = event.x_transformed(width) as f64;
            let raw_y = event.y_transformed(width) as f64;  // Use width due to Smithay bug
            // Transform for Flipped180 output
            let (logical_x, logical_y) = transform_coords(raw_x, raw_y, width, height);
            let touch_pos = Point::from((logical_x, logical_y));

            *mouse_pos = touch_pos;

            // Track keyboard swipe movement (using shared state)
            if state.keyboard_dismiss_slot.is_some() {
                let offset = touch_pos.y - state.keyboard_dismiss_start_y;
                state.keyboard_dismiss_offset = offset;

                // Check for upward swipe - transition to home gesture
                let upward_threshold = -30.0; // Start home gesture after 30px upward swipe
                if offset < upward_threshold && state.home_gesture_window.is_none() {
                    // Swiping up from keyboard - hide keyboard and start going home
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.set_keyboard_visible(false);
                    }
                    info!("Keyboard swipe up detected (offset={:.0}), starting home gesture", offset);
                    state.start_home_gesture();
                    state.keyboard_dismiss_slot = None;
                }
            }

            // Continue home gesture if active (from keyboard swipe or edge swipe)
            if state.home_gesture_window.is_some() && state.keyboard_dismiss_start_y > 0.0 {
                // Calculate progress based on upward movement from keyboard start position
                let total_upward = state.keyboard_dismiss_start_y - touch_pos.y;
                let progress = (total_upward / 300.0).max(0.0);
                state.update_home_gesture(progress);
            }

            // Feed to gesture recognizer
            if let Some(gesture_event) = state.gesture_recognizer.touch_motion(0, touch_pos) {
                state.shell.handle_gesture(&gesture_event);
            }

            // Update Slint
            if let Some(ref slint_ui) = state.shell.slint_ui {
                slint_ui.dispatch_pointer_moved(logical_x as f32, logical_y as f32);
            }
        }

        InputEvent::TouchUp { event: _, .. } => {
            *mouse_pressed = false;
            debug!("Touch up at {:?}", mouse_pos);

            // Handle home gesture completion if it was started from keyboard swipe
            let home_gesture_from_keyboard = state.home_gesture_window.is_some() && state.keyboard_dismiss_start_y > 0.0;
            if home_gesture_from_keyboard {
                // Calculate if gesture should complete (swiped far enough)
                let total_upward = state.keyboard_dismiss_start_y - mouse_pos.y;
                let completed = total_upward > 150.0; // Need to swipe up 150px to go home
                info!("Home gesture from keyboard ended: upward={:.0}px, completed={}", total_upward, completed);
                state.end_home_gesture(completed);
                state.keyboard_dismiss_start_y = 0.0;
            }

            // Check for keyboard swipe-to-dismiss completion (using shared state)
            let keyboard_was_dismissed = if state.keyboard_dismiss_slot == Some(0) {
                let offset = state.keyboard_dismiss_offset;
                let dismiss_threshold = 80.0; // Pixels to swipe down to dismiss

                if offset > dismiss_threshold {
                    // Swiped down far enough - dismiss keyboard
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        info!("Keyboard dismissed by swipe down (offset={:.0})", offset);
                        slint_ui.set_keyboard_visible(false);
                    }
                    true
                } else {
                    debug!("Keyboard swipe too short (offset={:.0}, threshold={})", offset, dismiss_threshold);
                    false
                }
            } else {
                false
            };
            // Reset shared state
            state.keyboard_dismiss_slot = None;
            state.keyboard_dismiss_offset = 0.0;

            // Complete gesture
            if let Some(gesture_event) = state.gesture_recognizer.touch_up(0) {
                info!("Gesture completed: {:?}", gesture_event);
                state.shell.handle_gesture(&gesture_event);

                // Handle tap on home screen (but skip if keyboard was dismissed)
                if !keyboard_was_dismissed {
                    if let GestureEvent::Tap { position } = &gesture_event {
                        handle_tap(state, *position);
                    }
                }
            }

            // Dispatch to Slint and process lock screen actions
            let (actions, pending_app_tap) = if let Some(ref slint_ui) = state.shell.slint_ui {
                slint_ui.dispatch_pointer_released(mouse_pos.x as f32, mouse_pos.y as f32);
                (slint_ui.poll_lock_actions(), slint_ui.take_pending_app_tap())
            } else {
                (Vec::new(), None)
            };

            // Process lock screen actions
            if state.shell.view == ShellView::LockScreen {
                process_lock_actions(state, &actions);
            }

            // Handle app tap from Slint callback (works even for edge areas)
            if state.shell.view == ShellView::Home && !keyboard_was_dismissed {
                if let Some(app_index) = pending_app_tap {
                    let categories = &state.shell.app_manager.config.grid_order;
                    if (app_index as usize) < categories.len() {
                        let category = categories[app_index as usize];
                        info!("App tap from Slint callback: index={} category={:?}", app_index, category);
                        if let Some(exec) = state.shell.app_manager.get_exec(category) {
                            info!("Launching app via Slint callback: {}", exec);
                            std::process::Command::new("sh")
                                .arg("-c")
                                .arg(&exec)
                                .env("WAYLAND_DISPLAY", state.socket_name.to_str().unwrap_or("wayland-1"))
                                .env_remove("DISPLAY")
                                .spawn()
                                .ok();
                            state.shell.app_launched();
                        }
                    }
                }
            }

            // Process on-screen keyboard actions using shared handler
            let keyboard_actions: Vec<KeyboardAction> = if let Some(ref slint_ui) = state.shell.slint_ui {
                slint_ui.take_pending_keyboard_actions()
            } else {
                Vec::new()
            };
            process_keyboard_actions(state, keyboard_actions);
        }

        _ => {}
    }
}

/// Handle tap events on the UI
/// Uses shared input handler for home screen taps, handles other views locally
fn handle_tap(state: &mut Flick, position: Point<f64, Logical>) {
    let shell_view = state.shell.view.clone();

    match shell_view {
        ShellView::Home => {
            // Use shared handler for home screen taps
            handle_home_tap(state, position);
        }
        ShellView::Switcher => {
            // Switcher taps handled via Slint callbacks
            if let Some(ref slint_ui) = state.shell.slint_ui {
                if let Some(window_id) = slint_ui.take_pending_switcher_tap() {
                    info!("Switcher tap: window {} - handled via callback", window_id);
                }
            }
        }
        _ => {}
    }
}

// Note: process_lock_actions is now imported from crate::input::handler

/// Render a frame
fn render_frame(
    state: &mut Flick,
    backend: &mut WinitGraphicsBackend<GlesRenderer>,
    output: &Output,
    damage_tracker: &mut OutputDamageTracker,
    scale: f32,
) {
    let age = backend.buffer_age().unwrap_or(0);
    let output_scale = output.current_scale().fractional_scale() as f32;

    let render_result = backend.bind().and_then(|(renderer, mut fb)| {
        // Collect render elements
        let mut elements: Vec<WinitRenderElement<GlesRenderer>> = Vec::new();

        // Get shell view to determine what to render
        let shell_view = state.shell.view.clone();

        // Check if we should render the Python lock screen app
        let window_count = state.space.elements().count();
        let render_python_lock = shell_view == ShellView::LockScreen
            && state.shell.lock_screen_active
            && window_count > 0;

        // Render app windows when in App view
        let render_app_windows = shell_view == ShellView::App && window_count > 0;

        if render_python_lock || render_app_windows {
            // Render Wayland surfaces (apps or Python lock screen)
            debug!("Rendering {} Wayland window(s)", window_count);
            let windows: Vec<_> = state.space.elements().cloned().collect();

            for window in windows.iter() {
                let window_render_elements: Vec<WaylandSurfaceRenderElement<GlesRenderer>> = window
                    .render_elements::<WaylandSurfaceRenderElement<GlesRenderer>>(
                        renderer,
                        (0, 0).into(),
                        smithay::utils::Scale::from(1.0),
                        1.0,
                    );

                for elem in window_render_elements {
                    elements.push(WinitRenderElement::Surface(elem));
                }
            }

            // Check if keyboard should be rendered on top of app windows
            let keyboard_visible = state.shell.slint_ui.as_ref()
                .map(|ui| ui.is_keyboard_visible())
                .unwrap_or(false);

            if keyboard_visible && render_app_windows {
                // Render keyboard overlay from Slint on top of app
                if let Some(ref mut slint_ui) = state.shell.slint_ui {
                    // Set view to app for keyboard-only render
                    slint_ui.set_view("app");
                    slint_ui.process_events();
                    slint_ui.request_redraw();

                    if let Some((width, height, pixels)) = slint_ui.render() {
                        // Keyboard height is 22% of screen, minimum 200px (matches Slint)
                        let keyboard_height: u32 = std::cmp::max(200, (height as f32 * 0.22) as u32);
                        let keyboard_y = height.saturating_sub(keyboard_height);
                        info!("Winit keyboard overlay: {}x{}, keyboard_height={}, keyboard_y={}",
                            width, height, keyboard_height, keyboard_y);

                        // Create a smaller buffer just for the keyboard
                        let mut keyboard_pixels = Vec::with_capacity((width * keyboard_height * 4) as usize);

                        // Copy only the keyboard rows from the full render
                        for y in keyboard_y..height {
                            let row_start = (y * width * 4) as usize;
                            let row_end = row_start + (width * 4) as usize;
                            if row_end <= pixels.len() {
                                keyboard_pixels.extend_from_slice(&pixels[row_start..row_end]);
                            }
                        }

                        // Create memory buffer for keyboard overlay
                        use smithay::backend::renderer::element::memory::MemoryRenderBuffer;

                        let keyboard_buffer = MemoryRenderBuffer::from_slice(
                            &keyboard_pixels,
                            smithay::backend::allocator::Fourcc::Abgr8888,
                            (width as i32, keyboard_height as i32),
                            1,
                            Transform::Normal,
                            None,
                        );

                        // Position keyboard at bottom of screen
                        let keyboard_y_pos = keyboard_y as f64;

                        let keyboard_element = MemoryRenderBufferRenderElement::from_buffer(
                            renderer,
                            (0.0, keyboard_y_pos),
                            &keyboard_buffer,
                            None,
                            None,
                            None,
                            smithay::backend::renderer::element::Kind::Unspecified,
                        );

                        if let Ok(elem) = keyboard_element {
                            // Insert at front so keyboard renders ON TOP of app
                            elements.insert(0, WinitRenderElement::Slint(elem));
                        }
                    }
                }
            }
        } else {
            // Render Slint UI for home screen, quick settings, lock screen (loading), etc.
            let should_render_slint = matches!(
                shell_view,
                ShellView::Home | ShellView::QuickSettings | ShellView::LockScreen | ShellView::Switcher | ShellView::PickDefault
            );

            // Get values we need before borrowing slint_ui mutably
            let pin_length = state.shell.lock_state.entered_pin.len();
            let categories = state.shell.app_manager.get_category_info();

            if should_render_slint {
                if let Some(ref mut slint_ui) = state.shell.slint_ui {
                    // Update Slint state before rendering
                    update_slint_state(&shell_view, pin_length, &categories, slint_ui);

                    // Render Slint to pixel buffer
                    if let Some((width, height, pixels)) = slint_ui.render() {
                        // Create memory buffer from pixels
                        // Output transform (Flipped180) handles display orientation
                        use smithay::backend::renderer::element::memory::MemoryRenderBuffer;

                        let buffer = MemoryRenderBuffer::from_slice(
                            &pixels,
                            smithay::backend::allocator::Fourcc::Abgr8888,
                            (width as i32, height as i32),
                            1,
                            Transform::Normal,
                            None,
                        );

                        let element = MemoryRenderBufferRenderElement::from_buffer(
                            renderer,
                            (0.0, 0.0),
                            &buffer,
                            None,
                            None,
                            None,
                            smithay::backend::renderer::element::Kind::Unspecified,
                        );

                        if let Ok(elem) = element {
                            elements.push(WinitRenderElement::Slint(elem));
                        }
                    }
                }
            }
        }

        // Choose background color based on view
        let bg_color = match shell_view {
            ShellView::Home => [0.05, 0.05, 0.08, 1.0],      // Dark blue-black
            ShellView::LockScreen => [0.02, 0.02, 0.05, 1.0], // Very dark
            ShellView::QuickSettings => [0.1, 0.1, 0.15, 1.0],
            ShellView::Switcher => [0.08, 0.08, 0.12, 1.0],
            ShellView::PickDefault => [0.08, 0.08, 0.12, 1.0],
            ShellView::App => [0.0, 0.0, 0.0, 1.0],
        };

        // Render
        let res = damage_tracker.render_output(
            renderer,
            &mut fb,
            age,
            &elements,
            bg_color,
        );

        match res {
            Ok(r) => Ok(r),
            Err(e) => Err(smithay::backend::SwapBuffersError::ContextLost(
                Box::new(std::io::Error::new(
                    std::io::ErrorKind::Other,
                    format!("{:?}", e),
                )),
            )),
        }
    });

    match render_result {
        Ok(render_output_result) => {
            if let Some(damage) = render_output_result.damage {
                if let Err(e) = backend.submit(Some(damage)) {
                    warn!("Failed to submit: {:?}", e);
                }
            } else {
                let _ = backend.submit(None);
            }
        }
        Err(err) => {
            warn!("Render error: {:?}", err);
            let _ = backend.submit(None);
        }
    }

    // Send frame callbacks to clients
    state.space.elements().for_each(|window| {
        window.send_frame(
            output,
            state.start_time.elapsed(),
            Some(Duration::ZERO),
            |_, _| Some(output.clone()),
        );
    });
}

/// Update Slint UI state before rendering
fn update_slint_state(shell_view: &ShellView, pin_length: usize, categories: &[crate::shell::apps::CategoryInfo], slint_ui: &mut SlintShell) {
    match shell_view {
        ShellView::Home => {
            slint_ui.set_view("home");
            // Update app categories
            let slint_categories: Vec<(String, String, [f32; 4])> = categories
                .iter()
                .map(|cat| {
                    let icon = cat.icon.as_deref().unwrap_or(&cat.name[..1]).to_string();
                    (cat.name.clone(), icon, cat.color)
                })
                .collect();
            info!("WINIT: Setting {} categories for home view", slint_categories.len());
            slint_ui.set_categories(slint_categories);
            slint_ui.set_show_popup(false);
            slint_ui.set_wiggle_mode(false);
        }
        ShellView::LockScreen => {
            slint_ui.set_view("lock");
            slint_ui.set_lock_time(&chrono::Local::now().format("%H:%M").to_string());
            slint_ui.set_lock_date(&chrono::Local::now().format("%A, %B %e").to_string());
            slint_ui.set_pin_length(pin_length as i32);
        }
        ShellView::QuickSettings => {
            slint_ui.set_view("quick-settings");
        }
        ShellView::Switcher => {
            slint_ui.set_view("switcher");
        }
        ShellView::PickDefault => {
            slint_ui.set_view("pick-default");
        }
        ShellView::App => {
            // Don't update Slint when showing an app
        }
    }
}
