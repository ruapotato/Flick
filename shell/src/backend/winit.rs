//! Winit backend for development/testing/demos
//!
//! Runs the compositor in a window on X11 or Wayland, useful for:
//! - Development without switching TTYs
//! - Recording demos
//! - Testing different screen sizes

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
    input::GestureEvent,
    shell::{ShellView, slint_ui::{LockScreenAction, SlintShell}},
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

    // Use Flipped180 transform to display right-side up
    output.change_current_state(Some(mode), Some(Transform::Flipped180), None, Some((0, 0).into()));
    output.set_preferred(mode);

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

    // Track for touchscreen tap detection on X11
    // When cursor moves and stops briefly, treat as a tap
    let mut last_motion_time: u32 = 0;
    let mut pending_tap_pos: Option<Point<f64, Logical>> = None;
    let mut recent_synthetic_tap_time: u32 = 0;  // Suppress duplicate TouchDown after synthetic tap

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
                        &mut last_motion_time,
                        &mut pending_tap_pos,
                        &mut recent_synthetic_tap_time,
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

        // Render frame on every iteration (not just on Redraw events)
        // This ensures the UI updates after input events
        render_frame(&mut state, &mut backend, &output, &mut damage_tracker, scale);
    }

    Ok(())
}

/// Handle winit input events, converting to touch-like gestures
fn handle_winit_input(
    state: &mut Flick,
    event: InputEvent<WinitInput>,
    mouse_pos: &mut Point<f64, Logical>,
    mouse_pressed: &mut bool,
    last_motion_time: &mut u32,
    pending_tap_pos: &mut Option<Point<f64, Logical>>,
    recent_synthetic_tap_time: &mut u32,
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
            let logical_x = event.x_transformed(width) as f64;
            let logical_y = event.y_transformed(height) as f64;
            let new_pos = Point::from((logical_x, logical_y));

            // Detect touchscreen taps on X11: when cursor "jumps" to a new position
            // (more than 30px away), treat it as a touchscreen tap immediately
            // This handles touchscreens that only generate PointerMotionAbsolute without TouchDown
            let distance = ((new_pos.x - mouse_pos.x).powi(2) + (new_pos.y - mouse_pos.y).powi(2)).sqrt();
            let time_delta = time.saturating_sub(*last_motion_time);

            // Check if new position is within window bounds
            let in_bounds = new_pos.x >= 0.0 && new_pos.x < width as f64
                         && new_pos.y >= 0.0 && new_pos.y < height as f64;

            // If cursor jumped significantly, is within bounds, and we're not already tracking a touch
            if distance > 30.0 && in_bounds && !*mouse_pressed {
                info!("Touchscreen tap detected at {:?} (jump={:.1}px, dt={}ms)", new_pos, distance, time_delta);

                // Record time to suppress duplicate TouchDown
                *recent_synthetic_tap_time = time;

                // Simulate immediate tap (press + release)
                if let Some(ref slint_ui) = state.shell.slint_ui {
                    slint_ui.dispatch_pointer_pressed(new_pos.x as f32, new_pos.y as f32);
                }
                state.gesture_recognizer.touch_down(0, new_pos);

                // Immediate release for tap
                if let Some(gesture_event) = state.gesture_recognizer.touch_up(0) {
                    state.shell.handle_gesture(&gesture_event);
                    if let GestureEvent::Tap { position } = &gesture_event {
                        handle_tap(state, *position);
                    }
                }

                // Dispatch release to Slint and process lock screen actions
                let actions: Vec<LockScreenAction> = if let Some(ref slint_ui) = state.shell.slint_ui {
                    slint_ui.dispatch_pointer_released(new_pos.x as f32, new_pos.y as f32);
                    slint_ui.poll_lock_actions()
                } else {
                    Vec::new()
                };

                if state.shell.view == ShellView::LockScreen {
                    process_lock_actions(state, &actions);
                }
            }

            // Clear pending tap since we handle immediately now
            *pending_tap_pos = None;

            *mouse_pos = new_pos;
            *last_motion_time = time;

            // If mouse is pressed, this is a drag - feed to gesture recognizer
            if *mouse_pressed {
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

                        // Complete gesture
                        if let Some(gesture_event) = state.gesture_recognizer.touch_up(0) {
                            info!("Gesture completed: {:?}", gesture_event);
                            state.shell.handle_gesture(&gesture_event);

                            // Handle tap on home screen
                            if let GestureEvent::Tap { position } = &gesture_event {
                                handle_tap(state, *position);
                            }
                        }

                        // Dispatch to Slint and process lock screen actions
                        let actions: Vec<LockScreenAction> = if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.dispatch_pointer_released(
                                mouse_pos.x as f32,
                                mouse_pos.y as f32,
                            );
                            slint_ui.poll_lock_actions()
                        } else {
                            Vec::new()
                        };

                        // Process lock screen actions
                        if state.shell.view == ShellView::LockScreen {
                            process_lock_actions(state, &actions);
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

            if let Some(keyboard) = state.seat.get_keyboard() {
                // Winit keycodes are already in XKB format - use directly
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
            let logical_x = event.x_transformed(width) as f64;
            let logical_y = event.y_transformed(width) as f64;  // Use width due to Smithay bug
            let touch_pos = Point::from((logical_x, logical_y));

            *mouse_pos = touch_pos;
            *mouse_pressed = true;

            debug!("Touch down at {:?}", touch_pos);

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
            let logical_x = event.x_transformed(width) as f64;
            let logical_y = event.y_transformed(width) as f64;  // Use width due to Smithay bug
            let touch_pos = Point::from((logical_x, logical_y));

            *mouse_pos = touch_pos;

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

            // Complete gesture
            if let Some(gesture_event) = state.gesture_recognizer.touch_up(0) {
                info!("Gesture completed: {:?}", gesture_event);
                state.shell.handle_gesture(&gesture_event);

                // Handle tap on home screen
                if let GestureEvent::Tap { position } = &gesture_event {
                    handle_tap(state, *position);
                }
            }

            // Dispatch to Slint and process lock screen actions
            let actions: Vec<LockScreenAction> = if let Some(ref slint_ui) = state.shell.slint_ui {
                slint_ui.dispatch_pointer_released(mouse_pos.x as f32, mouse_pos.y as f32);
                slint_ui.poll_lock_actions()
            } else {
                Vec::new()
            };

            // Process lock screen actions
            if state.shell.view == ShellView::LockScreen {
                process_lock_actions(state, &actions);
            }
        }

        _ => {}
    }
}

/// Handle tap events on the UI
fn handle_tap(state: &mut Flick, position: Point<f64, Logical>) {
    let shell_view = state.shell.view.clone();

    match shell_view {
        ShellView::Home => {
            // Use hit_test_category which accounts for scroll offset
            if let Some(category) = state.shell.hit_test_category(position) {
                info!("App tap detected: category={:?} at {:?}", category, position);
                // Use get_exec() which properly handles Settings (uses built-in Flick Settings)
                if let Some(exec) = state.shell.app_manager.get_exec(category) {
                    info!("Launching app: {}", exec);
                    // Launch the app
                    std::process::Command::new("sh")
                        .arg("-c")
                        .arg(&exec)
                        .env("WAYLAND_DISPLAY", state.socket_name.to_str().unwrap_or("wayland-1"))
                        .spawn()
                        .ok();
                    state.shell.app_launched();
                }
            }
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

/// Process lock screen actions from Slint UI
fn process_lock_actions(state: &mut Flick, actions: &[LockScreenAction]) {
    for action in actions {
        match action {
            LockScreenAction::PinDigit(digit) => {
                if state.shell.lock_state.entered_pin.len() < 6 {
                    state.shell.lock_state.entered_pin.push_str(digit);
                    info!("PIN digit entered, length: {}", state.shell.lock_state.entered_pin.len());
                    // Try to unlock after each digit (supports 4-6 digit PINs)
                    if state.shell.lock_state.entered_pin.len() >= 4 {
                        state.shell.try_unlock();
                    }
                }
            }
            LockScreenAction::PinBackspace => {
                state.shell.lock_state.entered_pin.pop();
                info!("PIN backspace, length: {}", state.shell.lock_state.entered_pin.len());
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
                if state.shell.lock_state.pattern_nodes.len() >= 4 {
                    state.shell.try_unlock();
                } else if !state.shell.lock_state.pattern_nodes.is_empty() {
                    state.shell.lock_state.error_message = Some("Pattern too short (min 4 dots)".to_string());
                }
                state.shell.lock_state.pattern_nodes.clear();
            }
            LockScreenAction::UsePassword => {
                state.shell.lock_state.switch_to_password();
                info!("Switched to password mode");
            }
            LockScreenAction::PasswordFieldTapped => {
                info!("Password field tapped - showing keyboard");
            }
            LockScreenAction::PasswordSubmit => {
                info!("Password submit - attempting PAM auth");
                state.shell.try_unlock();
            }
        }
    }

    // Update Slint UI with results
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

            // Update error message if any
            if let Some(ref err) = state.shell.lock_state.error_message {
                slint_ui.set_lock_error(err);
            }

            // Update lock mode if changed to password
            if actions.iter().any(|a| matches!(a, LockScreenAction::UsePassword)) {
                slint_ui.set_lock_mode("password");
            }

            // Show keyboard if password field was tapped
            if actions.iter().any(|a| matches!(a, LockScreenAction::PasswordFieldTapped)) {
                slint_ui.set_keyboard_visible(true);
            }
        }
    }
}

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

        if render_python_lock {
            // Render Python lock screen app as Wayland surface
            debug!("Rendering Python lock screen app");
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
                        use smithay::backend::renderer::element::memory::MemoryRenderBuffer;

                        let buffer = MemoryRenderBuffer::from_slice(
                            &pixels,
                            smithay::backend::allocator::Fourcc::Argb8888,
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
