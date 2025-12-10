//! Shared input handling for both TTY (udev) and embedded (winit) backends
//!
//! This module contains common input processing logic that is shared between
//! the two backends, eliminating code duplication. The backends only need to:
//! 1. Translate their specific input events to common types
//! 2. Call these shared processing functions
//! 3. Handle backend-specific rendering

use smithay::input::keyboard::{FilterResult, Keycode};
use tracing::{info, warn};

use crate::shell::slint_ui::{KeyboardAction, LockScreenAction};
use crate::shell::lock_screen::LockInputMode;
use crate::shell::ShellView;
use crate::state::Flick;

/// Convert evdev keycode to character (US QWERTY layout)
/// Used by udev backend which receives evdev keycodes directly from libinput
pub fn evdev_to_char(keycode: u32, shift: bool) -> Option<char> {
    let c = match keycode {
        // Row 1: numbers
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

/// Convert XKB keycode to character (XKB = evdev + 8)
/// Used by winit backend which receives XKB keycodes
pub fn xkb_to_char(keycode: u32, shift: bool) -> Option<char> {
    // XKB keycodes are evdev + 8
    let evdev = keycode.saturating_sub(8);
    evdev_to_char(evdev, shift)
}

/// Convert character to evdev keycode (US QWERTY layout)
/// Returns (keycode, needs_shift)
pub fn char_to_evdev(c: char) -> Option<(u32, bool)> {
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

/// Process lock screen actions from Slint UI
/// This is called by both backends after collecting actions from Slint
pub fn process_lock_actions(state: &mut Flick, actions: &[LockScreenAction]) {
    for action in actions {
        match action {
            LockScreenAction::PinDigit(digit) => {
                if state.shell.lock_state.entered_pin.len() < 6 {
                    state.shell.lock_state.entered_pin.push_str(digit);
                    let pin_len = state.shell.lock_state.entered_pin.len();
                    info!("PIN digit entered, length: {}", pin_len);
                    // Try to unlock: silent for 4-5 digits, with reset at 6
                    if pin_len >= 4 && pin_len < 6 {
                        // Silent try - don't reset on failure (user may have longer PIN)
                        state.shell.try_pin_silent();
                    } else if pin_len == 6 {
                        // Max length reached - full try with reset on failure
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

            // Update lock mode if changed to password, and show keyboard automatically
            if actions.iter().any(|a| matches!(a, LockScreenAction::UsePassword)) {
                slint_ui.set_lock_mode("password");
                // Auto-show keyboard when switching to password mode (phone UX)
                slint_ui.set_keyboard_visible(true);
                info!("Switched to password mode - showing keyboard");
            }

            // Show keyboard if password field was tapped
            if actions.iter().any(|a| matches!(a, LockScreenAction::PasswordFieldTapped)) {
                slint_ui.set_keyboard_visible(true);
                info!("Password field tapped - keyboard visible");
            }
        }
    }
}

/// Process on-screen keyboard actions
/// Handles character injection, backspace, enter, etc.
/// Used by both backends for processing keyboard taps
pub fn process_keyboard_actions(state: &mut Flick, actions: Vec<KeyboardAction>) {
    // Check if we're on lock screen password mode
    let is_lock_screen_password = state.shell.view == ShellView::LockScreen
        && state.shell.lock_state.input_mode == LockInputMode::Password;

    for action in actions {
        info!("Processing keyboard action: {:?}", action);
        match action {
            KeyboardAction::Character(ch) => {
                if is_lock_screen_password {
                    // Direct password entry for lock screen
                    state.shell.lock_state.entered_password.push_str(&ch);
                    info!("Added character to lock screen password (len={})",
                          state.shell.lock_state.entered_password.len());
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.set_password_length(state.shell.lock_state.entered_password.len() as i32);
                    }
                } else {
                    // Inject key to focused app
                    inject_character(state, &ch);
                }
            }
            KeyboardAction::Backspace => {
                if is_lock_screen_password {
                    state.shell.lock_state.entered_password.pop();
                    info!("Removed character from lock screen password (len={})",
                          state.shell.lock_state.entered_password.len());
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.set_password_length(state.shell.lock_state.entered_password.len() as i32);
                    }
                } else {
                    inject_keycode(state, 14); // Backspace evdev keycode
                }
            }
            KeyboardAction::Enter => {
                if is_lock_screen_password {
                    info!("Enter pressed on lock screen password - attempting auth");
                    state.shell.try_unlock();
                } else {
                    inject_keycode(state, 28); // Enter evdev keycode
                }
            }
            KeyboardAction::Space => {
                if is_lock_screen_password {
                    state.shell.lock_state.entered_password.push(' ');
                    info!("Added space to lock screen password (len={})",
                          state.shell.lock_state.entered_password.len());
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.set_password_length(state.shell.lock_state.entered_password.len() as i32);
                    }
                } else {
                    inject_keycode(state, 57); // Space evdev keycode
                }
            }
            KeyboardAction::ShiftToggled => {
                if let Some(ref slint_ui) = state.shell.slint_ui {
                    slint_ui.toggle_keyboard_shift();
                }
                info!("Keyboard shift toggled");
            }
            KeyboardAction::LayoutToggled => {
                if let Some(ref slint_ui) = state.shell.slint_ui {
                    slint_ui.toggle_keyboard_layout();
                }
                info!("Keyboard layout toggled");
            }
            KeyboardAction::Hide => {
                if let Some(ref slint_ui) = state.shell.slint_ui {
                    slint_ui.set_keyboard_visible(false);
                }
                info!("Keyboard hidden");
            }
        }
    }
}

/// Inject a character as a keyboard event to the focused client
fn inject_character(state: &mut Flick, ch: &str) {
    if let Some(c) = ch.chars().next() {
        if let Some((keycode, needs_shift)) = char_to_evdev(c) {
            if let Some(keyboard) = state.seat.get_keyboard() {
                let serial = smithay::utils::SERIAL_COUNTER.next_serial();
                let time = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_millis() as u32;

                let xkb_keycode = keycode + 8;
                let focus_info = keyboard.current_focus()
                    .map(|f| format!("{:?}", f))
                    .unwrap_or_else(|| "NONE".to_string());
                info!(">>>KEY>>> Injecting '{}' keycode={} xkb={} focus={}",
                      c, keycode, xkb_keycode, focus_info);

                // Press shift if needed
                if needs_shift {
                    keyboard.input::<(), _>(
                        state,
                        Keycode::new(42 + 8), // Left Shift
                        smithay::backend::input::KeyState::Pressed,
                        serial, time,
                        |_, _, _| FilterResult::Forward::<()>
                    );
                }

                // Press and release the key
                keyboard.input::<(), _>(
                    state,
                    Keycode::new(xkb_keycode),
                    smithay::backend::input::KeyState::Pressed,
                    serial, time,
                    |_, _, _| FilterResult::Forward::<()>
                );
                keyboard.input::<(), _>(
                    state,
                    Keycode::new(xkb_keycode),
                    smithay::backend::input::KeyState::Released,
                    serial, time,
                    |_, _, _| FilterResult::Forward::<()>
                );

                // Release shift if needed
                if needs_shift {
                    keyboard.input::<(), _>(
                        state,
                        Keycode::new(42 + 8),
                        smithay::backend::input::KeyState::Released,
                        serial, time,
                        |_, _, _| FilterResult::Forward::<()>
                    );
                }
                info!(">>>KEY>>> Injection complete for '{}'", c);
            } else {
                warn!(">>>KB ERROR>>> No keyboard available for injection!");
            }
        } else {
            warn!(">>>KB ERROR>>> char_to_evdev returned None for '{}'", c);
        }
    } else {
        warn!(">>>KB ERROR>>> Character action has empty string!");
    }
}

/// Inject a single keycode (evdev) as press+release
fn inject_keycode(state: &mut Flick, evdev_keycode: u32) {
    if let Some(keyboard) = state.seat.get_keyboard() {
        let serial = smithay::utils::SERIAL_COUNTER.next_serial();
        let time = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u32;

        let xkb_keycode = evdev_keycode + 8;

        keyboard.input::<(), _>(
            state,
            Keycode::new(xkb_keycode),
            smithay::backend::input::KeyState::Pressed,
            serial, time,
            |_, _, _| FilterResult::Forward::<()>
        );
        keyboard.input::<(), _>(
            state,
            Keycode::new(xkb_keycode),
            smithay::backend::input::KeyState::Released,
            serial, time,
            |_, _, _| FilterResult::Forward::<()>
        );
    }
}

/// Handle physical keyboard input for lock screen password mode
/// Returns true if the event was consumed (should not be forwarded to apps)
pub fn handle_lock_screen_keyboard(
    state: &mut Flick,
    keycode: u32,  // evdev keycode
    pressed: bool,
    shift_pressed: bool,
) -> bool {
    if state.shell.view != ShellView::LockScreen {
        return false;
    }

    if state.shell.lock_state.input_mode != LockInputMode::Password {
        return false;
    }

    if !pressed {
        return true; // Consume key release events on lock screen
    }

    // evdev keycodes: Enter=28, Backspace=14
    match keycode {
        28 => {
            // Enter - attempt unlock
            if !state.shell.lock_state.entered_password.is_empty() {
                info!("Password entered, attempting unlock");
                state.shell.try_unlock();
            }
        }
        14 => {
            // Backspace
            state.shell.lock_state.entered_password.pop();
            if let Some(ref slint_ui) = state.shell.slint_ui {
                slint_ui.set_password_length(state.shell.lock_state.entered_password.len() as i32);
            }
        }
        _ => {
            // Try to convert keycode to character
            if let Some(c) = evdev_to_char(keycode, shift_pressed) {
                if state.shell.lock_state.entered_password.len() < 64 {
                    state.shell.lock_state.entered_password.push(c);
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.set_password_length(state.shell.lock_state.entered_password.len() as i32);
                    }
                }
            }
        }
    }

    true // Consumed - don't forward to apps
}

/// Handle tap events on the home screen UI
/// Returns true if an app was launched
pub fn handle_home_tap(state: &mut Flick, position: smithay::utils::Point<f64, smithay::utils::Logical>) -> bool {
    if state.shell.view != ShellView::Home {
        return false;
    }

    // Use hit_test_category which accounts for scroll offset
    if let Some(category) = state.shell.hit_test_category(position) {
        info!("App tap detected: category={:?} at {:?}", category, position);
        // Use get_exec() which properly handles Settings (uses built-in Flick Settings)
        if let Some(exec) = state.shell.app_manager.get_exec(category) {
            info!("Launching app: {}", exec);
            // Launch the app - remove DISPLAY so apps use Wayland instead of X11
            std::process::Command::new("sh")
                .arg("-c")
                .arg(&exec)
                .env("WAYLAND_DISPLAY", state.socket_name.to_str().unwrap_or("wayland-1"))
                .env_remove("DISPLAY")
                .spawn()
                .ok();
            state.shell.app_launched();
            return true;
        }
    }
    false
}
