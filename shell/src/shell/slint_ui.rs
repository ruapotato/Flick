//! Slint UI integration for Flick Shell
//!
//! This module bridges Slint's software renderer with Smithay's compositor.
//! The Slint UI is rendered to a pixel buffer which is then composited as
//! a texture element in Smithay's render pipeline.

use std::cell::RefCell;
use std::rc::Rc;

use slint::platform::software_renderer::{MinimalSoftwareWindow, RepaintBufferType};
use slint::platform::{Platform, WindowAdapter, PointerEventButton, WindowEvent};
use slint::{LogicalPosition, PhysicalSize, Rgb8Pixel, SharedPixelBuffer};
use smithay::utils::{Logical, Size};
use tracing::{info, warn};

// Include the generated Slint code
slint::include_modules!();

/// Actions that can be triggered from popup menu
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum PopupAction {
    PickDefault,
    Move,
    Close,
}

/// Actions that can be triggered from Quick Settings
#[derive(Debug, Clone, PartialEq)]
pub enum QuickSettingsAction {
    WifiToggle,
    BluetoothToggle,
    DndToggle,
    FlashlightToggle,
    AirplaneToggle,
    RotationToggle,
    TouchEffectsToggle,
    Lock,
    Settings,  // Now launches Flutter Settings app
    BrightnessChanged(f32),
}

/// Actions that can be triggered from the on-screen keyboard
#[derive(Debug, Clone, PartialEq)]
pub enum KeyboardAction {
    /// A character key was pressed
    Character(String),
    /// Backspace key
    Backspace,
    /// Enter/Return key
    Enter,
    /// Space key
    Space,
    /// Shift was toggled
    ShiftToggled,
    /// Layout was toggled (letters <-> numbers/symbols)
    LayoutToggled,
    /// Hide keyboard requested
    Hide,
}

/// Actions that can be triggered from the lock screen
#[derive(Debug, Clone, PartialEq)]
pub enum LockScreenAction {
    /// PIN digit pressed
    PinDigit(String),
    /// PIN backspace pressed
    PinBackspace,
    /// Pattern node touched (index 0-8)
    PatternNode(i32),
    /// Pattern drawing completed (finger lifted)
    PatternComplete,
    /// Pattern drawing started (finger down)
    PatternStarted,
    /// Switch to password mode requested
    UsePassword,
    /// Password field tapped (show keyboard)
    PasswordFieldTapped,
    /// Password submit button pressed
    PasswordSubmit,
}

/// Slint UI state for the shell
pub struct SlintShell {
    /// The Slint window adapter
    window: Rc<MinimalSoftwareWindow>,
    /// The FlickShell component instance
    shell: FlickShell,
    /// Current screen size
    size: Size<i32, Logical>,
    /// Pixel buffer for software rendering (RGBA8888)
    pixel_buffer: RefCell<Vec<u8>>,
    /// Pending app tap index (set by callback, polled by compositor)
    pending_app_tap: Rc<RefCell<Option<i32>>>,
    /// Pending Quick Settings actions (set by callbacks, polled by compositor)
    pending_qs_actions: Rc<RefCell<Vec<QuickSettingsAction>>>,
    /// Pending switcher window tap (window ID, set by callback, polled by compositor)
    pending_switcher_tap: Rc<RefCell<Option<i32>>>,
    /// Whether popup is showing (needed for hit testing)
    popup_showing: RefCell<bool>,
    /// Whether popup can pick default
    popup_can_pick: RefCell<bool>,
    /// Wiggle mode state
    wiggle_mode: RefCell<bool>,
    /// Pending keyboard actions (set by callbacks, polled by compositor)
    pending_keyboard_actions: Rc<RefCell<Vec<KeyboardAction>>>,
    /// Pending lock screen actions (set by callbacks, polled by compositor)
    pending_lock_actions: Rc<RefCell<Vec<LockScreenAction>>>,
}

impl SlintShell {
    /// Create a new Slint shell with the given screen size
    pub fn new(size: Size<i32, Logical>) -> Self {
        info!("Creating Slint shell with size {:?}", size);

        // Create the minimal software window
        // IMPORTANT: Use NewBuffer because we create a fresh buffer each frame
        // ReusedBuffer would only repaint damaged areas, leaving the rest black
        let window = MinimalSoftwareWindow::new(RepaintBufferType::NewBuffer);
        window.set_size(PhysicalSize::new(size.w as u32, size.h as u32));

        // Set up the Slint platform
        let window_clone = window.clone();
        slint::platform::set_platform(Box::new(FlickPlatform {
            window: window_clone,
        }))
        .expect("Failed to set Slint platform");

        // Create the shell component
        let shell = FlickShell::new().expect("Failed to create FlickShell component");

        // Show the window (required for rendering)
        shell.show().expect("Failed to show FlickShell");

        // Allocate pixel buffer (RGBA = 4 bytes per pixel)
        let buffer_size = (size.w * size.h * 4) as usize;
        let pixel_buffer = RefCell::new(vec![0u8; buffer_size]);

        // Create pending app tap storage for callback communication
        let pending_app_tap = Rc::new(RefCell::new(None));

        // Connect the app-tapped callback
        let pending_tap_clone = pending_app_tap.clone();
        shell.on_app_tapped(move |index| {
            info!("Slint app tapped callback: index={}", index);
            *pending_tap_clone.borrow_mut() = Some(index);
        });

        // Create pending Quick Settings actions storage
        let pending_qs_actions = Rc::new(RefCell::new(Vec::new()));

        // Connect Quick Settings callbacks
        let qs_clone = pending_qs_actions.clone();
        shell.on_wifi_toggled(move || {
            info!("Slint WiFi toggle callback");
            qs_clone.borrow_mut().push(QuickSettingsAction::WifiToggle);
        });

        let qs_clone = pending_qs_actions.clone();
        shell.on_bluetooth_toggled(move || {
            info!("Slint Bluetooth toggle callback");
            qs_clone.borrow_mut().push(QuickSettingsAction::BluetoothToggle);
        });

        let qs_clone = pending_qs_actions.clone();
        shell.on_dnd_toggled(move || {
            info!("Slint DND toggle callback");
            qs_clone.borrow_mut().push(QuickSettingsAction::DndToggle);
        });

        let qs_clone = pending_qs_actions.clone();
        shell.on_flashlight_toggled(move || {
            info!("Slint Flashlight toggle callback");
            qs_clone.borrow_mut().push(QuickSettingsAction::FlashlightToggle);
        });

        let qs_clone = pending_qs_actions.clone();
        shell.on_airplane_toggled(move || {
            info!("Slint Airplane toggle callback");
            qs_clone.borrow_mut().push(QuickSettingsAction::AirplaneToggle);
        });

        let qs_clone = pending_qs_actions.clone();
        shell.on_rotation_toggled(move || {
            info!("Slint Rotation toggle callback");
            qs_clone.borrow_mut().push(QuickSettingsAction::RotationToggle);
        });

        let qs_clone = pending_qs_actions.clone();
        shell.on_touch_effects_toggled(move || {
            info!("Slint Touch Effects toggle callback");
            qs_clone.borrow_mut().push(QuickSettingsAction::TouchEffectsToggle);
        });

        let qs_clone = pending_qs_actions.clone();
        shell.on_lock_pressed(move || {
            info!("Slint Lock button callback");
            qs_clone.borrow_mut().push(QuickSettingsAction::Lock);
        });

        let qs_clone = pending_qs_actions.clone();
        shell.on_settings_pressed(move || {
            info!("Slint Settings button callback");
            qs_clone.borrow_mut().push(QuickSettingsAction::Settings);
        });

        let qs_clone = pending_qs_actions.clone();
        shell.on_brightness_changed(move |value| {
            info!("Slint Brightness changed callback: {}", value);
            qs_clone.borrow_mut().push(QuickSettingsAction::BrightnessChanged(value));
        });

        // Create pending switcher tap storage
        let pending_switcher_tap = Rc::new(RefCell::new(None));

        // Connect the switcher window tapped callback
        let switcher_tap_clone = pending_switcher_tap.clone();
        shell.on_switcher_window_tapped(move |window_id| {
            info!("Slint switcher window tapped callback: window_id={}", window_id);
            *switcher_tap_clone.borrow_mut() = Some(window_id);
        });

        // Create pending keyboard actions storage
        let pending_keyboard_actions = Rc::new(RefCell::new(Vec::new()));

        // Connect keyboard callbacks
        let kb_clone = pending_keyboard_actions.clone();
        shell.on_keyboard_key_pressed(move |ch| {
            info!("Slint keyboard key pressed: {}", ch);
            kb_clone.borrow_mut().push(KeyboardAction::Character(ch.to_string()));
        });

        let kb_clone = pending_keyboard_actions.clone();
        shell.on_keyboard_backspace(move || {
            info!("Slint keyboard backspace");
            kb_clone.borrow_mut().push(KeyboardAction::Backspace);
        });

        let kb_clone = pending_keyboard_actions.clone();
        shell.on_keyboard_enter(move || {
            info!("Slint keyboard enter");
            kb_clone.borrow_mut().push(KeyboardAction::Enter);
        });

        let kb_clone = pending_keyboard_actions.clone();
        shell.on_keyboard_space(move || {
            info!("Slint keyboard space");
            kb_clone.borrow_mut().push(KeyboardAction::Space);
        });

        let kb_clone = pending_keyboard_actions.clone();
        shell.on_keyboard_shift_toggled(move || {
            info!("Slint keyboard shift toggled");
            kb_clone.borrow_mut().push(KeyboardAction::ShiftToggled);
        });

        let kb_clone = pending_keyboard_actions.clone();
        shell.on_keyboard_layout_toggled(move || {
            info!("Slint keyboard layout toggled");
            kb_clone.borrow_mut().push(KeyboardAction::LayoutToggled);
        });

        let kb_clone = pending_keyboard_actions.clone();
        shell.on_keyboard_hide(move || {
            info!("Slint keyboard hide");
            kb_clone.borrow_mut().push(KeyboardAction::Hide);
        });

        // Create pending lock screen actions storage
        let pending_lock_actions = Rc::new(RefCell::new(Vec::new()));

        // Connect lock screen callbacks
        let lock_clone = pending_lock_actions.clone();
        shell.on_pin_digit_pressed(move |digit| {
            info!("Slint PIN digit pressed: {}", digit);
            lock_clone.borrow_mut().push(LockScreenAction::PinDigit(digit.to_string()));
        });

        let lock_clone = pending_lock_actions.clone();
        shell.on_pin_backspace_pressed(move || {
            info!("Slint PIN backspace pressed");
            lock_clone.borrow_mut().push(LockScreenAction::PinBackspace);
        });

        let lock_clone = pending_lock_actions.clone();
        shell.on_pattern_node_touched(move |idx| {
            info!("Slint pattern node touched: {}", idx);
            lock_clone.borrow_mut().push(LockScreenAction::PatternNode(idx));
        });

        let lock_clone = pending_lock_actions.clone();
        shell.on_pattern_complete(move || {
            info!("Slint pattern complete");
            lock_clone.borrow_mut().push(LockScreenAction::PatternComplete);
        });

        let lock_clone = pending_lock_actions.clone();
        shell.on_pattern_started(move || {
            info!("Slint pattern started");
            lock_clone.borrow_mut().push(LockScreenAction::PatternStarted);
        });

        let lock_clone = pending_lock_actions.clone();
        shell.on_use_password_pressed(move || {
            info!("Slint use password pressed");
            lock_clone.borrow_mut().push(LockScreenAction::UsePassword);
        });

        let lock_clone = pending_lock_actions.clone();
        shell.on_password_field_tapped(move || {
            info!("Slint password field tapped");
            lock_clone.borrow_mut().push(LockScreenAction::PasswordFieldTapped);
        });

        let lock_clone = pending_lock_actions.clone();
        shell.on_password_submit(move || {
            info!("Slint password submit pressed");
            lock_clone.borrow_mut().push(LockScreenAction::PasswordSubmit);
        });

        Self {
            window,
            shell,
            size,
            pixel_buffer,
            pending_app_tap,
            pending_qs_actions,
            pending_switcher_tap,
            popup_showing: RefCell::new(false),
            popup_can_pick: RefCell::new(true),
            wiggle_mode: RefCell::new(false),
            pending_keyboard_actions,
            pending_lock_actions,
        }
    }

    /// Update the screen size
    pub fn set_size(&mut self, size: Size<i32, Logical>) {
        if self.size != size {
            self.size = size;
            self.window
                .set_size(PhysicalSize::new(size.w as u32, size.h as u32));

            // Reallocate pixel buffer
            let buffer_size = (size.w * size.h * 4) as usize;
            *self.pixel_buffer.borrow_mut() = vec![0u8; buffer_size];
        }
    }

    /// Set the current view (lock, home, quick-settings, app)
    pub fn set_view(&self, view: &str) {
        self.shell.set_current_view(view.into());
    }

    /// Set lock screen time
    pub fn set_lock_time(&self, time: &str) {
        self.shell.set_lock_time(time.into());
    }

    /// Set lock screen date
    pub fn set_lock_date(&self, date: &str) {
        self.shell.set_lock_date(date.into());
    }

    /// Set PIN entry length (number of digits entered)
    pub fn set_pin_length(&self, len: i32) {
        self.shell.set_pin_length(len);
    }

    /// Set lock screen error message
    pub fn set_lock_error(&self, error: &str) {
        self.shell.set_lock_error(error.into());
    }

    /// Set lock screen mode (pin, pattern, password, none)
    pub fn set_lock_mode(&self, mode: &str) {
        self.shell.set_lock_mode(mode.into());
    }

    /// Set pattern nodes state (9 bools for 3x3 grid)
    pub fn set_pattern_nodes(&self, nodes: &[bool; 9]) {
        use slint::ModelRc;
        use slint::VecModel;
        let model: Rc<VecModel<bool>> = Rc::new(VecModel::from(nodes.to_vec()));
        self.shell.set_pattern_nodes(ModelRc::from(model));
    }

    /// Set lockout message (shown when too many failed attempts)
    pub fn set_lockout_message(&self, msg: &str) {
        self.shell.set_lockout_message(msg.into());
    }

    /// Set password length (for dots display)
    pub fn set_password_length(&self, len: i32) {
        self.shell.set_password_length(len);
    }

    /// Poll for pending lock screen actions
    pub fn poll_lock_actions(&self) -> Vec<LockScreenAction> {
        self.pending_lock_actions.borrow_mut().drain(..).collect()
    }

    /// Set brightness value (0.0 to 1.0)
    pub fn set_brightness(&self, brightness: f32) {
        self.shell.set_brightness(brightness);
    }

    /// Set WiFi enabled state
    pub fn set_wifi_enabled(&self, enabled: bool) {
        self.shell.set_wifi_enabled(enabled);
    }

    /// Set Bluetooth enabled state
    pub fn set_bluetooth_enabled(&self, enabled: bool) {
        self.shell.set_bluetooth_enabled(enabled);
    }

    /// Set Do Not Disturb enabled state
    pub fn set_dnd_enabled(&self, enabled: bool) {
        self.shell.set_dnd_enabled(enabled);
    }

    /// Set Flashlight enabled state
    pub fn set_flashlight_enabled(&self, enabled: bool) {
        self.shell.set_flashlight_enabled(enabled);
    }

    /// Set Airplane mode enabled state
    pub fn set_airplane_enabled(&self, enabled: bool) {
        self.shell.set_airplane_enabled(enabled);
    }

    /// Set Rotation locked state
    pub fn set_rotation_locked(&self, locked: bool) {
        self.shell.set_rotation_locked(locked);
    }

    /// Set Touch Effects enabled state
    pub fn set_touch_effects_enabled(&self, enabled: bool) {
        self.shell.set_touch_effects_enabled(enabled);
    }

    /// Set WiFi SSID
    pub fn set_wifi_ssid(&self, ssid: &str) {
        self.shell.set_wifi_ssid(ssid.into());
    }

    /// Set battery percentage
    pub fn set_battery_percent(&self, percent: i32) {
        self.shell.set_battery_percent(percent);
    }

    /// Show/hide the long press popup menu
    pub fn set_show_popup(&self, show: bool) {
        *self.popup_showing.borrow_mut() = show;
        self.shell.set_show_popup(show);
    }

    /// Set the popup category name
    pub fn set_popup_category_name(&self, name: &str) {
        self.shell.set_popup_category_name(name.into());
    }

    /// Set whether popup can pick default (false for Settings)
    pub fn set_popup_can_pick_default(&self, can_pick: bool) {
        *self.popup_can_pick.borrow_mut() = can_pick;
        self.shell.set_popup_can_pick_default(can_pick);
    }

    /// Set wiggle mode state
    pub fn set_wiggle_mode(&self, wiggle: bool) {
        *self.wiggle_mode.borrow_mut() = wiggle;
        self.shell.set_wiggle_mode(wiggle);
    }

    /// Set wiggle animation time (updated each frame from Rust)
    pub fn set_wiggle_time(&self, time: f32) {
        self.shell.set_wiggle_time(time);
    }

    /// Set the index of the tile being dragged (-1 if none)
    pub fn set_dragging_index(&self, index: i32) {
        self.shell.set_dragging_index(index);
    }

    /// Set the drag position (screen coordinates)
    pub fn set_drag_position(&self, x: f32, y: f32) {
        self.shell.set_drag_x(x);
        self.shell.set_drag_y(y);
    }

    /// Check if popup is showing
    pub fn is_popup_showing(&self) -> bool {
        *self.popup_showing.borrow()
    }

    /// Check if wiggle mode is active
    pub fn is_wiggle_mode(&self) -> bool {
        *self.wiggle_mode.borrow()
    }

    /// Set the category name for pick default view
    pub fn set_pick_default_category(&self, name: &str) {
        self.shell.set_pick_default_category(name.into());
    }

    /// Set the current app selection (exec command)
    pub fn set_current_app_selection(&self, exec: &str) {
        self.shell.set_current_app_selection(exec.into());
    }

    /// Set available apps for pick default view
    pub fn set_available_apps(&self, apps: Vec<(String, String)>) {
        let model: Vec<AvailableApp> = apps
            .into_iter()
            .map(|(name, exec)| AvailableApp {
                name: name.into(),
                exec: exec.into(),
            })
            .collect();

        let model_rc = std::rc::Rc::new(slint::VecModel::from(model));
        self.shell.set_available_apps(model_rc.into());
    }

    /// Set app categories for home screen
    pub fn set_categories(&self, categories: Vec<(String, slint::Image, [f32; 4])>) {
        let model: Vec<AppCategory> = categories
            .into_iter()
            .map(|(name, icon, color)| AppCategory {
                name: name.into(),
                icon,
                color: slint::Color::from_argb_f32(color[3], color[0], color[1], color[2]),
            })
            .collect();

        let model_rc = std::rc::Rc::new(slint::VecModel::from(model));
        self.shell.set_categories(model_rc.into());
    }

    /// Set switcher window cards (id, title, app_class, original_index)
    /// Windows should be sorted by render order (furthest from center first, center last)
    pub fn set_switcher_windows(&self, windows: Vec<(i32, String, String, i32)>) {
        let model: Vec<WindowCard> = windows
            .into_iter()
            .map(|(id, title, app_class, original_index)| WindowCard {
                id,
                title: title.into(),
                app_class: app_class.into(),
                original_index,
            })
            .collect();

        let model_rc = std::rc::Rc::new(slint::VecModel::from(model));
        self.shell.set_switcher_windows(model_rc.into());
    }

    /// Set switcher horizontal scroll offset
    pub fn set_switcher_scroll(&self, offset: f32) {
        self.shell.set_switcher_scroll(offset);
    }

    /// Set switcher enter animation progress (0.0 = full screen, 1.0 = card size)
    pub fn set_switcher_enter_progress(&self, progress: f32) {
        self.shell.set_switcher_enter_progress(progress);
    }

    /// Poll for pending switcher window tap (from Slint callback)
    /// Returns the window ID if there was a tap, and clears the pending state
    pub fn take_pending_switcher_tap(&self) -> Option<i32> {
        self.pending_switcher_tap.borrow_mut().take()
    }

    /// Connect PIN digit pressed callback
    pub fn on_pin_digit_pressed(&self, callback: impl Fn(String) + 'static) {
        self.shell.on_pin_digit_pressed(move |digit| {
            callback(digit.to_string());
        });
    }

    /// Connect PIN backspace callback
    pub fn on_pin_backspace(&self, callback: impl Fn() + 'static) {
        self.shell.on_pin_backspace_pressed(move || {
            callback();
        });
    }

    /// Connect app tapped callback
    pub fn on_app_tapped(&self, callback: impl Fn(i32) + 'static) {
        self.shell.on_app_tapped(move |index| {
            callback(index);
        });
    }

    /// Connect brightness changed callback
    pub fn on_brightness_changed(&self, callback: impl Fn(f32) + 'static) {
        self.shell.on_brightness_changed(move |value| {
            callback(value);
        });
    }

    /// Connect WiFi toggle callback
    pub fn on_wifi_toggled(&self, callback: impl Fn() + 'static) {
        self.shell.on_wifi_toggled(move || {
            callback();
        });
    }

    /// Connect Bluetooth toggle callback
    pub fn on_bluetooth_toggled(&self, callback: impl Fn() + 'static) {
        self.shell.on_bluetooth_toggled(move || {
            callback();
        });
    }

    /// Connect lock button callback
    pub fn on_lock_pressed(&self, callback: impl Fn() + 'static) {
        self.shell.on_lock_pressed(move || {
            callback();
        });
    }

    /// Render the Slint UI and return the pixel buffer
    /// Returns (width, height, RGBA pixel data)
    pub fn render(&self) -> Option<(u32, u32, Vec<u8>)> {
        let width = self.size.w as u32;
        let height = self.size.h as u32;

        // Track if we actually drew
        let drew = std::cell::Cell::new(false);

        // ALWAYS force a redraw for debugging - bypass draw_if_needed check
        // This ensures we render every frame regardless of Slint's "needs redraw" state
        self.window.request_redraw();

        // Use draw_if_needed which renders if the window needs repainting
        self.window.draw_if_needed(|renderer| {
            drew.set(true);

            // Create a SharedPixelBuffer for rendering (RGB888)
            let mut buffer = SharedPixelBuffer::<Rgb8Pixel>::new(width, height);

            // Render to the buffer
            renderer.render(buffer.make_mut_slice(), width as usize);

            // Convert RGB888 to RGBA8888 with chroma key for transparency
            // The shell uses #FF00FF (magenta) as the chroma key color for "app" view
            let rgb_data = buffer.as_bytes();
            let mut pixel_buffer = self.pixel_buffer.borrow_mut();

            // Ensure buffer is correct size (RGBA = 4 bytes per pixel)
            let expected_size = (width * height * 4) as usize;
            if pixel_buffer.len() != expected_size {
                pixel_buffer.resize(expected_size, 0);
            }

            // Convert RGB to RGBA with chroma key transparency
            // Magenta (#FF00FF) becomes transparent, everything else is opaque
            for (i, chunk) in rgb_data.chunks(3).enumerate() {
                if chunk.len() == 3 {
                    let offset = i * 4;
                    if offset + 3 < pixel_buffer.len() {
                        let r = chunk[0];
                        let g = chunk[1];
                        let b = chunk[2];
                        pixel_buffer[offset] = r;
                        pixel_buffer[offset + 1] = g;
                        pixel_buffer[offset + 2] = b;
                        // Chroma key: magenta (#FF00FF) becomes transparent
                        if r == 255 && g == 0 && b == 255 {
                            pixel_buffer[offset + 3] = 0; // Transparent
                        } else {
                            pixel_buffer[offset + 3] = 255; // Opaque
                        }
                    }
                }
            }
        });

        // Log if we drew or not
        if drew.get() {
            // Sample some pixels to verify content
            let buffer = self.pixel_buffer.borrow();
            let center = (width * height * 2) as usize; // Middle of buffer
            let sample = if buffer.len() > center + 4 {
                (buffer[center], buffer[center+1], buffer[center+2], buffer[center+3])
            } else {
                (0, 0, 0, 0)
            };
            tracing::debug!("Slint draw_if_needed: rendered, center pixel RGBA={:?}", sample);
        } else {
            tracing::warn!("Slint draw_if_needed: skipped (no repaint needed)");
        }

        // Return a copy of the pixel buffer
        let buffer = self.pixel_buffer.borrow();
        Some((width, height, buffer.clone()))
    }

    /// Request a redraw
    pub fn request_redraw(&self) {
        self.window.request_redraw();
    }

    /// Process pending Slint events (timers, animations, etc.)
    pub fn process_events(&self) {
        slint::platform::update_timers_and_animations();
    }

    /// Dispatch touch/pointer down event to Slint
    pub fn dispatch_pointer_pressed(&self, x: f32, y: f32) {
        let window_size = self.window.size();
        info!("Slint dispatch_pointer_pressed({}, {}) window_size={}x{}",
              x, y, window_size.width, window_size.height);
        let position = LogicalPosition::new(x, y);
        // First move the pointer to the position (enter the TouchArea)
        self.window.dispatch_event(WindowEvent::PointerMoved { position });
        // Then press
        self.window.dispatch_event(WindowEvent::PointerPressed {
            position,
            button: PointerEventButton::Left,
        });
        // Request redraw to process the input
        self.window.request_redraw();
        // Process events immediately
        slint::platform::update_timers_and_animations();
    }

    /// Dispatch touch/pointer move event to Slint
    pub fn dispatch_pointer_moved(&self, x: f32, y: f32) {
        let position = LogicalPosition::new(x, y);
        self.window.dispatch_event(WindowEvent::PointerMoved { position });
    }

    /// Dispatch touch/pointer up event to Slint
    pub fn dispatch_pointer_released(&self, x: f32, y: f32) {
        info!("Slint dispatch_pointer_released({}, {})", x, y);
        let position = LogicalPosition::new(x, y);
        self.window.dispatch_event(WindowEvent::PointerReleased {
            position,
            button: PointerEventButton::Left,
        });
        // Process events immediately to trigger callbacks
        slint::platform::update_timers_and_animations();
    }

    /// Dispatch pointer exit event to Slint (touch cancelled or left area)
    pub fn dispatch_pointer_exit(&self) {
        self.window.dispatch_event(WindowEvent::PointerExited);
    }

    /// Poll for pending app tap (from Slint callback)
    /// Returns the app index if there was a tap, and clears the pending state
    pub fn take_pending_app_tap(&self) -> Option<i32> {
        self.pending_app_tap.borrow_mut().take()
    }

    /// Poll for pending Quick Settings actions (from Slint callbacks)
    /// Returns all pending actions and clears the pending state
    pub fn take_pending_qs_actions(&self) -> Vec<QuickSettingsAction> {
        std::mem::take(&mut *self.pending_qs_actions.borrow_mut())
    }

    /// Hit test a tap position and return the app index if an app tile was tapped
    /// This bypasses Slint's input handling which doesn't work with MinimalSoftwareWindow
    pub fn hit_test_app_tap(&self, x: f32, y: f32) -> Option<i32> {
        let width = self.size.w as f32;
        let _height = self.size.h as f32;

        // Layout constants matching shell.slint HomeScreen
        let status_bar_height = 48.0;
        let padding = 24.0;
        let row_height = 140.0;
        let row_spacing = 16.0;
        let col_spacing = 12.0;

        // Grid starts after status bar + padding
        let grid_start_y = status_bar_height + padding;

        // Check if tap is in the grid area
        if y < grid_start_y {
            return None;
        }

        // Calculate which row
        let relative_y = y - grid_start_y;
        let row_with_spacing = row_height + row_spacing;
        let row = (relative_y / row_with_spacing) as i32;

        // Check if tap is between rows (in the spacing)
        let y_in_row = relative_y - (row as f32 * row_with_spacing);
        if y_in_row > row_height {
            return None; // In the gap between rows
        }

        // Calculate column (4 columns)
        let grid_width = width - 2.0 * padding;
        let col_width = (grid_width - 3.0 * col_spacing) / 4.0;
        let relative_x = x - padding;

        if relative_x < 0.0 || relative_x > grid_width {
            return None;
        }

        let col_with_spacing = col_width + col_spacing;
        let col = (relative_x / col_with_spacing) as i32;

        // Check if tap is between columns (in the spacing)
        let x_in_col = relative_x - (col as f32 * col_with_spacing);
        if x_in_col > col_width {
            return None; // In the gap between columns
        }

        // Calculate app index (row * 4 + col)
        if col >= 0 && col < 4 && row >= 0 && row < 4 {
            let index = row * 4 + col;
            info!("Hit test: tap at ({}, {}) -> row={}, col={}, index={}",
                  x, y, row, col, index);
            Some(index)
        } else {
            None
        }
    }

    /// Hit test a tap on the popup menu
    /// Returns the action if a button was tapped
    pub fn hit_test_popup(&self, x: f32, y: f32) -> Option<PopupAction> {
        if !*self.popup_showing.borrow() {
            return None;
        }

        let width = self.size.w as f32;
        let height = self.size.h as f32;

        // Popup dimensions (matching shell.slint LongPressPopup)
        let popup_width = 280.0;
        let can_pick = *self.popup_can_pick.borrow();
        let popup_height = if can_pick { 180.0 } else { 130.0 };

        // Popup is centered
        let popup_left = (width - popup_width) / 2.0;
        let popup_top = (height - popup_height) / 2.0;
        let popup_right = popup_left + popup_width;
        let popup_bottom = popup_top + popup_height;

        // Check if tap is outside popup (dismiss)
        if x < popup_left || x > popup_right || y < popup_top || y > popup_bottom {
            info!("Popup hit test: tap outside -> Close");
            return Some(PopupAction::Close);
        }

        // Inside popup - check which button
        // Layout: 16px padding, title ~26px, 8px space, then buttons (56px each with 8px spacing)
        let content_start_y = popup_top + 16.0 + 26.0 + 8.0; // After title

        if can_pick {
            // Two buttons: Pick Default (first), Move (second)
            let pick_btn_top = content_start_y;
            let pick_btn_bottom = pick_btn_top + 56.0;
            let move_btn_top = pick_btn_bottom + 8.0;
            let move_btn_bottom = move_btn_top + 56.0;

            if y >= pick_btn_top && y <= pick_btn_bottom {
                info!("Popup hit test: Pick Default");
                return Some(PopupAction::PickDefault);
            } else if y >= move_btn_top && y <= move_btn_bottom {
                info!("Popup hit test: Move");
                return Some(PopupAction::Move);
            }
        } else {
            // Only Move button
            let move_btn_top = content_start_y;
            let move_btn_bottom = move_btn_top + 56.0;

            if y >= move_btn_top && y <= move_btn_bottom {
                info!("Popup hit test: Move");
                return Some(PopupAction::Move);
            }
        }

        None
    }

    /// Hit test a tap on the wiggle Done button
    /// Returns true if the Done button was tapped
    pub fn hit_test_wiggle_done(&self, x: f32, y: f32) -> bool {
        if !*self.wiggle_mode.borrow() {
            return false;
        }

        let width = self.size.w as f32;
        let height = self.size.h as f32;

        // Done button dimensions (matching shell.slint WiggleDoneButton position)
        let btn_width = 200.0;
        let btn_height = 56.0;
        let btn_left = (width - btn_width) / 2.0;
        let btn_top = height - 100.0;
        let btn_right = btn_left + btn_width;
        let btn_bottom = btn_top + btn_height;

        if x >= btn_left && x <= btn_right && y >= btn_top && y <= btn_bottom {
            info!("Wiggle Done button hit");
            true
        } else {
            false
        }
    }

    /// Hit test a tap on the PickDefault view's back button
    /// Returns true if back button was tapped
    pub fn hit_test_pick_default_back(&self, x: f32, y: f32) -> bool {
        // Header is 80px, back button is 44x44 at (20px padding, centered vertically)
        let header_height = 80.0;
        let padding = 20.0;
        let btn_size = 44.0;

        // Back button is at (20, 18) with size 44x44 (centered in 80px header)
        let btn_left = padding;
        let btn_top = (header_height - btn_size) / 2.0;
        let btn_right = btn_left + btn_size;
        let btn_bottom = btn_top + btn_size;

        if x >= btn_left && x <= btn_right && y >= btn_top && y <= btn_bottom {
            info!("PickDefault back button hit");
            true
        } else {
            false
        }
    }

    /// Hit test a tap on the PickDefault view's app list
    /// Returns the index of the tapped app, or None if not on an app
    pub fn hit_test_pick_default_app(&self, x: f32, y: f32, app_count: usize) -> Option<usize> {
        // Header is 80px, then ScrollView with VerticalLayout has padding: 8px
        // App items are 64px with 4px spacing
        let header_height = 80.0;
        let list_padding = 8.0;  // padding in VerticalLayout inside ScrollView
        let item_height = 64.0;
        let item_spacing = 4.0;

        // App list starts after header + padding
        let list_start = header_height + list_padding;
        if y < list_start {
            return None;
        }

        let relative_y = y - list_start;
        let item_with_spacing = item_height + item_spacing;
        let index = (relative_y / item_with_spacing) as usize;

        // Check if tap is in the spacing between items
        let y_in_item = relative_y - (index as f32 * item_with_spacing);
        if y_in_item > item_height {
            return None; // In the gap between items
        }

        // Check if index is valid
        if index < app_count {
            info!("PickDefault app hit: index={}", index);
            Some(index)
        } else {
            None
        }
    }

    // ============== Keyboard Methods ==============

    /// Show or hide the on-screen keyboard
    pub fn set_keyboard_visible(&self, visible: bool) {
        info!("Setting keyboard visible: {}", visible);
        self.shell.set_keyboard_visible(visible);
        // Reset y-offset when hiding
        if !visible {
            self.shell.set_keyboard_y_offset(0.0);
        }
    }

    /// Check if the keyboard is currently visible
    pub fn is_keyboard_visible(&self) -> bool {
        self.shell.get_keyboard_visible()
    }

    /// Set keyboard y-offset for swipe-to-dismiss animation
    pub fn set_keyboard_y_offset(&self, offset: f32) {
        self.shell.set_keyboard_y_offset(offset);
    }

    /// Set keyboard shift state
    pub fn set_keyboard_shifted(&self, shifted: bool) {
        self.shell.set_keyboard_shifted(shifted);
    }

    /// Get keyboard shift state (includes caps lock)
    pub fn is_keyboard_shifted(&self) -> bool {
        self.shell.get_keyboard_shifted() || self.shell.get_keyboard_caps_lock()
    }

    /// Set keyboard caps lock state
    pub fn set_keyboard_caps_lock(&self, caps_lock: bool) {
        self.shell.set_keyboard_caps_lock(caps_lock);
    }

    /// Get keyboard caps lock state
    pub fn is_keyboard_caps_lock(&self) -> bool {
        self.shell.get_keyboard_caps_lock()
    }

    /// Set keyboard layout (0 = letters, 1 = numbers/symbols)
    pub fn set_keyboard_layout(&self, layout: i32) {
        self.shell.set_keyboard_layout(layout);
    }

    /// Get keyboard layout
    pub fn get_keyboard_layout(&self) -> i32 {
        self.shell.get_keyboard_layout()
    }

    /// Toggle keyboard shift state
    pub fn toggle_keyboard_shift(&self) {
        let shifted = self.is_keyboard_shifted();
        self.set_keyboard_shifted(!shifted);
    }

    /// Toggle keyboard layout between letters and symbols
    pub fn toggle_keyboard_layout(&self) {
        let layout = self.get_keyboard_layout();
        self.set_keyboard_layout(if layout == 0 { 1 } else { 0 });
    }

    /// Poll for pending keyboard actions (from Slint callbacks)
    /// Returns all pending actions and clears the pending state
    pub fn take_pending_keyboard_actions(&self) -> Vec<KeyboardAction> {
        std::mem::take(&mut *self.pending_keyboard_actions.borrow_mut())
    }

    /// Directly trigger a keyboard key based on touch position
    /// This is used as a fallback if Slint's touch detection misses the tap
    /// Returns true if a key was triggered
    pub fn trigger_keyboard_key_at(&self, x: f32, y: f32, keyboard_height: f32, screen_width: f32, shifted: bool, layout: i32) -> bool {
        // ALWAYS log keyboard math for debugging
        info!("KEYBOARD MATH: x={:.1}, y={:.1}, kb_height={:.1}, screen_w={:.1}, shifted={}, layout={}",
              x, y, keyboard_height, screen_width, shifted, layout);

        // Calculate which row was tapped (4 rows total)
        let row_height = keyboard_height / 4.0;
        let raw_row = (keyboard_height - y) / row_height;
        let row = raw_row.floor() as i32;  // 0 = bottom row, 3 = top row
        let row = row.clamp(0, 3);
        info!("KEYBOARD MATH: row_height={:.1}, raw_row={:.2}, final_row={}", row_height, raw_row, row);

        // Define key layouts for each row
        let key = match (row, layout) {
            // Row 0 (bottom): 123/ABC, comma, SPACE, period, ENTER
            (0, _) => {
                let key_widths = [1.5, 1.0, 5.0, 1.0, 1.5]; // relative widths
                let total_width: f32 = key_widths.iter().sum();
                let x_normalized = x / screen_width * total_width;
                let mut cumulative = 0.0;
                let mut key_idx = 0;
                for (i, &w) in key_widths.iter().enumerate() {
                    if x_normalized < cumulative + w {
                        key_idx = i;
                        break;
                    }
                    cumulative += w;
                    key_idx = i;
                }
                match key_idx {
                    0 => Some(KeyboardAction::LayoutToggled),
                    1 => Some(KeyboardAction::Character(",".to_string())),
                    2 => Some(KeyboardAction::Space),
                    3 => Some(KeyboardAction::Character(".".to_string())),
                    4 => Some(KeyboardAction::Enter),
                    _ => None,
                }
            }
            // Row 1 (shift row): SHIFT, 7 keys, DEL
            (1, 0) => {
                let keys = ["SHIFT", "z", "x", "c", "v", "b", "n", "m", "DEL"];
                let key_widths = [1.5, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.5];
                let total_width: f32 = key_widths.iter().sum();
                let x_normalized = x / screen_width * total_width;
                let mut cumulative = 0.0;
                let mut key_idx = 0;
                for (i, &w) in key_widths.iter().enumerate() {
                    if x_normalized < cumulative + w {
                        key_idx = i;
                        break;
                    }
                    cumulative += w;
                    key_idx = i;
                }
                match keys.get(key_idx) {
                    Some(&"SHIFT") => Some(KeyboardAction::ShiftToggled),
                    Some(&"DEL") => Some(KeyboardAction::Backspace),
                    Some(k) => {
                        let ch = if shifted { k.to_uppercase() } else { k.to_string() };
                        Some(KeyboardAction::Character(ch))
                    }
                    None => None,
                }
            }
            (1, 1) => {
                let keys = ["SHIFT", "/", "`", "@", "#", "&", "*", "(", "DEL"];
                let key_widths = [1.5, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.5];
                let total_width: f32 = key_widths.iter().sum();
                let x_normalized = x / screen_width * total_width;
                let mut cumulative = 0.0;
                let mut key_idx = 0;
                for (i, &w) in key_widths.iter().enumerate() {
                    if x_normalized < cumulative + w {
                        key_idx = i;
                        break;
                    }
                    cumulative += w;
                    key_idx = i;
                }
                match keys.get(key_idx) {
                    Some(&"SHIFT") => Some(KeyboardAction::ShiftToggled),
                    Some(&"DEL") => Some(KeyboardAction::Backspace),
                    Some(k) => Some(KeyboardAction::Character(k.to_string())),
                    None => None,
                }
            }
            // Row 2 (middle): 9 keys
            (2, 0) => {
                let keys = ["a", "s", "d", "f", "g", "h", "j", "k", "l"];
                let key_idx = ((x / screen_width) * keys.len() as f32).floor() as usize;
                let key_idx = key_idx.min(keys.len() - 1);
                let ch = if shifted { keys[key_idx].to_uppercase() } else { keys[key_idx].to_string() };
                Some(KeyboardAction::Character(ch))
            }
            (2, 1) => {
                let keys = ["-", "=", "[", "]", "\\", ";", "'", ",", "."];
                let key_idx = ((x / screen_width) * keys.len() as f32).floor() as usize;
                let key_idx = key_idx.min(keys.len() - 1);
                Some(KeyboardAction::Character(keys[key_idx].to_string()))
            }
            // Row 3 (top): 10 keys
            (3, 0) => {
                let keys = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"];
                let key_idx = ((x / screen_width) * keys.len() as f32).floor() as usize;
                let key_idx = key_idx.min(keys.len() - 1);
                let ch = if shifted { keys[key_idx].to_uppercase() } else { keys[key_idx].to_string() };
                Some(KeyboardAction::Character(ch))
            }
            (3, 1) => {
                let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"];
                let key_idx = ((x / screen_width) * keys.len() as f32).floor() as usize;
                let key_idx = key_idx.min(keys.len() - 1);
                Some(KeyboardAction::Character(keys[key_idx].to_string()))
            }
            _ => None,
        };

        if let Some(action) = key {
            info!("KEYBOARD MATH: ACTION={:?} at ({:.1}, {:.1}) row={} layout={}", action, x, y, row, layout);
            self.pending_keyboard_actions.borrow_mut().push(action);
            true
        } else {
            warn!("KEYBOARD MATH: NO KEY FOUND! x={:.1}, y={:.1}, row={}, layout={}", x, y, row, layout);
            false
        }
    }
}

/// Custom Slint platform for Flick
struct FlickPlatform {
    window: Rc<MinimalSoftwareWindow>,
}

impl Platform for FlickPlatform {
    fn create_window_adapter(&self) -> Result<Rc<dyn WindowAdapter>, slint::PlatformError> {
        Ok(self.window.clone())
    }

    fn duration_since_start(&self) -> std::time::Duration {
        // Use a simple monotonic clock
        static START: std::sync::OnceLock<std::time::Instant> = std::sync::OnceLock::new();
        START.get_or_init(std::time::Instant::now).elapsed()
    }

    fn run_event_loop(&self) -> Result<(), slint::PlatformError> {
        // We don't use Slint's event loop - Smithay drives our event loop
        Ok(())
    }
}
