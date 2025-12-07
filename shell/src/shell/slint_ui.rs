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
use tracing::info;

// Include the generated Slint code
slint::include_modules!();

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
}

impl SlintShell {
    /// Create a new Slint shell with the given screen size
    pub fn new(size: Size<i32, Logical>) -> Self {
        info!("Creating Slint shell with size {:?}", size);

        // Create the minimal software window
        let window = MinimalSoftwareWindow::new(RepaintBufferType::ReusedBuffer);
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

        Self {
            window,
            shell,
            size,
            pixel_buffer,
            pending_app_tap,
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

    /// Set WiFi SSID
    pub fn set_wifi_ssid(&self, ssid: &str) {
        self.shell.set_wifi_ssid(ssid.into());
    }

    /// Set battery percentage
    pub fn set_battery_percent(&self, percent: i32) {
        self.shell.set_battery_percent(percent);
    }

    /// Set app categories for home screen
    pub fn set_categories(&self, categories: Vec<(String, String, [f32; 4])>) {
        let model: Vec<AppCategory> = categories
            .into_iter()
            .map(|(name, icon, color)| AppCategory {
                name: name.into(),
                icon: icon.into(),
                color: slint::Color::from_argb_f32(color[3], color[0], color[1], color[2]),
            })
            .collect();

        let model_rc = std::rc::Rc::new(slint::VecModel::from(model));
        self.shell.set_categories(model_rc.into());
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

        // Check if we need to redraw
        self.window.draw_if_needed(|renderer| {
            // Create a SharedPixelBuffer for rendering (RGB888)
            let mut buffer = SharedPixelBuffer::<Rgb8Pixel>::new(width, height);

            // Render to the buffer
            renderer.render(buffer.make_mut_slice(), width as usize);

            // Convert RGB888 to RGBA8888
            let rgb_data = buffer.as_bytes();
            let mut pixel_buffer = self.pixel_buffer.borrow_mut();

            // Ensure buffer is correct size (RGBA = 4 bytes per pixel)
            let expected_size = (width * height * 4) as usize;
            if pixel_buffer.len() != expected_size {
                pixel_buffer.resize(expected_size, 0);
            }

            // Convert RGB to RGBA (add opaque alpha channel)
            for (i, chunk) in rgb_data.chunks(3).enumerate() {
                if chunk.len() == 3 {
                    let offset = i * 4;
                    if offset + 3 < pixel_buffer.len() {
                        pixel_buffer[offset] = chunk[0];     // R
                        pixel_buffer[offset + 1] = chunk[1]; // G
                        pixel_buffer[offset + 2] = chunk[2]; // B
                        pixel_buffer[offset + 3] = 255;      // A (opaque)
                    }
                }
            }
        });

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
