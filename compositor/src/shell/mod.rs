//! Integrated shell UI - rendered directly by the compositor
//!
//! Components:
//! - App grid (home screen)
//! - App switcher (Android-style card stack)
//! - Quick settings panel (notifications/toggles)
//! - Gesture overlays (close indicators)

pub mod primitives;
pub mod app_grid;
pub mod app_switcher;
pub mod quick_settings;
pub mod overlay;
pub mod text;

use smithay::utils::{Logical, Point, Size};
use crate::input::{Edge, GestureEvent};

/// App definition for the launcher
#[derive(Debug, Clone)]
pub struct AppInfo {
    pub name: String,
    pub exec: String,
    pub color: [f32; 4], // RGBA
}

impl AppInfo {
    pub fn new(name: &str, exec: &str, color: [f32; 4]) -> Self {
        Self {
            name: name.to_string(),
            exec: exec.to_string(),
            color,
        }
    }
}

/// Default apps for the launcher
pub fn default_apps() -> Vec<AppInfo> {
    vec![
        // X11 apps (via XWayland) - more likely to work
        AppInfo::new("XTerm", "xterm", [0.2, 0.6, 0.3, 1.0]),      // Green
        AppInfo::new("XCalc", "xcalc", [0.3, 0.5, 0.8, 1.0]),      // Blue
        AppInfo::new("XClock", "xclock", [0.8, 0.6, 0.2, 1.0]),    // Orange
        AppInfo::new("XEyes", "xeyes", [0.7, 0.3, 0.5, 1.0]),      // Purple
        AppInfo::new("XEdit", "xedit", [0.5, 0.5, 0.5, 1.0]),      // Gray
        AppInfo::new("XLoad", "xload", [0.6, 0.4, 0.3, 1.0]),      // Brown
    ]
}

/// Current shell view state
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ShellView {
    /// Showing a running app (shell hidden)
    App,
    /// Home screen with app grid
    Home,
    /// App switcher overlay
    Switcher,
    /// Quick settings / notifications panel
    QuickSettings,
}

/// Active gesture state for animations
#[derive(Debug, Clone)]
pub struct GestureState {
    /// Which edge the gesture started from (if any)
    pub edge: Option<Edge>,
    /// Progress 0.0 to 1.0+
    pub progress: f64,
    /// Velocity for momentum
    pub velocity: f64,
    /// Whether gesture completed successfully
    pub completed: bool,
}

impl Default for GestureState {
    fn default() -> Self {
        Self {
            edge: None,
            progress: 0.0,
            velocity: 0.0,
            completed: false,
        }
    }
}

/// Shell state - manages UI views and animations
pub struct Shell {
    /// Current view
    pub view: ShellView,
    /// Screen size
    pub screen_size: Size<i32, Logical>,
    /// Active gesture for animations
    pub gesture: GestureState,
    /// Apps for the launcher
    pub apps: Vec<AppInfo>,
    /// Selected app index (for touch feedback)
    pub selected_app: Option<usize>,
    /// Scroll offset for app switcher
    pub switcher_scroll: f64,
    /// Scroll offset for app grid (home screen)
    pub home_scroll: f64,
    /// Touch tracking for scrolling (home screen - vertical)
    pub scroll_touch_start_y: Option<f64>,
    pub scroll_touch_last_y: Option<f64>,
    /// Touch tracking for app switcher (horizontal)
    pub switcher_touch_start_x: Option<f64>,
    pub switcher_touch_last_x: Option<f64>,
    /// Pending app launch (exec command) - waits for touch up to confirm tap vs scroll
    pub pending_app_launch: Option<String>,
    /// Pending switcher window index - waits for touch up to confirm tap vs scroll
    pub pending_switcher_index: Option<usize>,
    /// Whether current touch is scrolling (moved significantly)
    pub is_scrolling: bool,
    /// Quick Settings panel state
    pub quick_settings: quick_settings::QuickSettingsPanel,
    /// Quick settings touch tracking
    pub qs_touch_start_y: Option<f64>,
    pub qs_touch_last_y: Option<f64>,
    /// Pending toggle index for Quick Settings
    pub pending_toggle_index: Option<usize>,
}

impl Shell {
    pub fn new(screen_size: Size<i32, Logical>) -> Self {
        Self {
            view: ShellView::Home, // Start at home
            screen_size,
            gesture: GestureState::default(),
            apps: default_apps(),
            selected_app: None,
            switcher_scroll: 0.0,
            home_scroll: 0.0,
            scroll_touch_start_y: None,
            scroll_touch_last_y: None,
            switcher_touch_start_x: None,
            switcher_touch_last_x: None,
            pending_app_launch: None,
            pending_switcher_index: None,
            is_scrolling: false,
            quick_settings: quick_settings::QuickSettingsPanel::new(screen_size),
            qs_touch_start_y: None,
            qs_touch_last_y: None,
            pending_toggle_index: None,
        }
    }

    /// Start tracking a touch on home screen (potential scroll or tap)
    pub fn start_home_touch(&mut self, y: f64, pending_app: Option<String>) {
        self.scroll_touch_start_y = Some(y);
        self.scroll_touch_last_y = Some(y);
        self.pending_app_launch = pending_app;
        self.is_scrolling = false;
    }

    /// Update scroll position based on touch movement
    /// Returns true if scrolling is happening
    pub fn update_home_scroll(&mut self, y: f64) -> bool {
        if let Some(start_y) = self.scroll_touch_start_y {
            let total_delta = (y - start_y).abs();
            // If moved more than 40 pixels, it's a scroll, not a tap
            // (increased from 20px for better tap reliability on touch screens)
            if total_delta > 40.0 {
                self.is_scrolling = true;
                self.pending_app_launch = None; // Cancel pending app launch
            }
        }

        if let Some(last_y) = self.scroll_touch_last_y {
            let delta = last_y - y; // Scroll down when finger moves up

            // Calculate max scroll based on content height (must match AppGrid calculation)
            let rows = (self.apps.len() + 2) / 3; // 3 columns
            let cell_height = (self.screen_size.w as f64 - 32.0) / 3.0 * 1.2;
            let content_height = rows as f64 * cell_height + 72.0; // top_offset = 72
            let max_scroll = (content_height - self.screen_size.h as f64 + 100.0).max(0.0);

            self.home_scroll = (self.home_scroll + delta).clamp(0.0, max_scroll);
        }
        self.scroll_touch_last_y = Some(y);
        self.is_scrolling
    }

    /// End touch gesture - returns app exec string if this was a tap (not scroll)
    pub fn end_home_touch(&mut self) -> Option<String> {
        let app = if !self.is_scrolling {
            self.pending_app_launch.take()
        } else {
            None
        };
        self.scroll_touch_start_y = None;
        self.scroll_touch_last_y = None;
        self.pending_app_launch = None;
        self.is_scrolling = false;
        app
    }

    /// Start tracking a touch on app switcher (potential horizontal scroll or tap)
    pub fn start_switcher_touch(&mut self, x: f64, pending_index: Option<usize>) {
        self.switcher_touch_start_x = Some(x);
        self.switcher_touch_last_x = Some(x);
        self.pending_switcher_index = pending_index;
        self.is_scrolling = false;
    }

    /// Update horizontal scroll position based on touch movement
    /// Returns true if scrolling is happening
    pub fn update_switcher_scroll(&mut self, x: f64, num_windows: usize, card_spacing: i32) -> bool {
        if let Some(start_x) = self.switcher_touch_start_x {
            let total_delta = (x - start_x).abs();
            // If moved more than 40 pixels, it's a scroll, not a tap
            // (increased from 20px for better tap reliability on touch screens)
            if total_delta > 40.0 {
                self.is_scrolling = true;
                self.pending_switcher_index = None; // Cancel pending window switch
            }
        }

        if let Some(last_x) = self.switcher_touch_last_x {
            let delta = last_x - x; // Scroll right when finger moves left
            // Calculate max scroll based on number of windows
            let max_scroll = if num_windows > 0 {
                ((num_windows - 1) as i32 * card_spacing) as f64
            } else {
                0.0
            };
            self.switcher_scroll = (self.switcher_scroll + delta).clamp(0.0, max_scroll);
        }
        self.switcher_touch_last_x = Some(x);
        self.is_scrolling
    }

    /// End switcher touch gesture - returns window index if this was a tap (not scroll)
    pub fn end_switcher_touch(&mut self) -> Option<usize> {
        let index = if !self.is_scrolling {
            self.pending_switcher_index.take()
        } else {
            None
        };
        self.switcher_touch_start_x = None;
        self.switcher_touch_last_x = None;
        self.pending_switcher_index = None;
        self.is_scrolling = false;
        index
    }

    /// Update gesture state from gesture events
    pub fn handle_gesture(&mut self, event: &GestureEvent) {
        match event {
            GestureEvent::EdgeSwipeStart { edge, .. } => {
                self.gesture.edge = Some(*edge);
                self.gesture.progress = 0.0;
                self.gesture.completed = false;
            }
            GestureEvent::EdgeSwipeUpdate { progress, velocity, .. } => {
                self.gesture.progress = *progress;
                self.gesture.velocity = *velocity;
            }
            GestureEvent::EdgeSwipeEnd { edge, completed, velocity, .. } => {
                self.gesture.completed = *completed;
                self.gesture.velocity = *velocity;

                if *completed {
                    match edge {
                        Edge::Bottom => {
                            // Swipe up - go home
                            self.view = ShellView::Home;
                        }
                        Edge::Right => {
                            // Swipe left from right edge - app switcher
                            tracing::info!("Gesture completed: switching to Switcher view");
                            self.view = ShellView::Switcher;
                        }
                        Edge::Top => {
                            // Swipe down - close app (handled by compositor)
                        }
                        Edge::Left => {
                            // Swipe right from left edge - quick settings panel
                            tracing::info!("Gesture completed: switching to QuickSettings view");
                            self.view = ShellView::QuickSettings;
                        }
                    }
                }

                // Reset gesture after handling
                self.gesture.edge = None;
                self.gesture.progress = 0.0;
            }
            _ => {}
        }
    }

    /// Called when an app is launched - switch to app view
    pub fn app_launched(&mut self) {
        self.view = ShellView::App;
        self.gesture = GestureState::default();
    }

    /// Called when switching to an app from switcher
    pub fn switch_to_app(&mut self) {
        self.view = ShellView::App;
        self.gesture = GestureState::default();
    }

    /// Close the app switcher (go back to current app)
    pub fn close_switcher(&mut self) {
        self.view = ShellView::App;
        self.gesture = GestureState::default();
    }

    /// Sync Quick Settings panel with current system status
    pub fn sync_quick_settings(&mut self, system: &crate::system::SystemStatus) {
        self.quick_settings.update_from_system(system);
    }

    /// Check if shell UI should be visible
    pub fn is_visible(&self) -> bool {
        match self.view {
            ShellView::App => {
                // Show during gesture animations
                self.gesture.edge.is_some()
            }
            ShellView::Home | ShellView::Switcher | ShellView::QuickSettings => true,
        }
    }

    /// Close quick settings panel (go back to previous view)
    pub fn close_quick_settings(&mut self) {
        // Go back to app if there are apps, otherwise home
        self.view = ShellView::App;
        self.gesture = GestureState::default();
    }

    /// Handle touch on the shell (returns app exec if app was tapped)
    pub fn handle_touch(&mut self, pos: Point<f64, Logical>) -> Option<String> {
        if self.view != ShellView::Home {
            return None;
        }

        // Check if touch is on an app tile
        let app_index = self.hit_test_app(pos);
        if let Some(idx) = app_index {
            return Some(self.apps[idx].exec.clone());
        }

        None
    }

    /// Hit test for app grid - returns app index if hit
    fn hit_test_app(&self, pos: Point<f64, Logical>) -> Option<usize> {
        let grid = app_grid::AppGridLayout::new(self.screen_size);

        for (i, app) in self.apps.iter().enumerate() {
            let rect = grid.app_rect(i);
            // Adjust for scroll offset - tiles scroll up as home_scroll increases
            let adjusted_y = rect.y - self.home_scroll;
            // Debug: log each rect
            tracing::debug!("App {} '{}': rect ({:.0},{:.0} {:.0}x{:.0}), touch ({:.0},{:.0}), scroll={:.0}",
                i, app.exec, rect.x, adjusted_y, rect.width, rect.height, pos.x, pos.y, self.home_scroll);
            if pos.x >= rect.x && pos.x < rect.x + rect.width &&
               pos.y >= adjusted_y && pos.y < adjusted_y + rect.height {
                tracing::info!("Hit app {} '{}'", i, app.exec);
                return Some(i);
            }
        }

        tracing::debug!("No app hit at ({:.0},{:.0})", pos.x, pos.y);
        None
    }

    /// Start tracking a touch on Quick Settings panel
    pub fn start_qs_touch(&mut self, x: f64, y: f64) {
        self.qs_touch_start_y = Some(y);
        self.qs_touch_last_y = Some(y);
        self.is_scrolling = false;

        // Check if touching a toggle button
        self.pending_toggle_index = self.quick_settings.hit_test_toggle(x, y);

        // Check if touching brightness slider
        if let Some(brightness) = self.quick_settings.hit_test_brightness(x, y) {
            self.quick_settings.set_brightness(brightness);
        }
    }

    /// Update Quick Settings scroll based on touch movement
    pub fn update_qs_scroll(&mut self, x: f64, y: f64) -> bool {
        if let Some(start_y) = self.qs_touch_start_y {
            let total_delta = (y - start_y).abs();
            if total_delta > 30.0 {
                self.is_scrolling = true;
                self.pending_toggle_index = None;
            }
        }

        if let Some(last_y) = self.qs_touch_last_y {
            let delta = last_y - y;
            self.quick_settings.scroll(delta);
        }

        // Update brightness if dragging on slider
        if let Some(brightness) = self.quick_settings.hit_test_brightness(x, y) {
            self.quick_settings.set_brightness(brightness);
        }

        self.qs_touch_last_y = Some(y);
        self.is_scrolling
    }

    /// End Quick Settings touch - toggle if it was a tap, returns toggle ID for system action
    pub fn end_qs_touch(&mut self) -> Option<String> {
        let toggle_id = if !self.is_scrolling {
            if let Some(index) = self.pending_toggle_index.take() {
                self.quick_settings.toggle(index)
            } else {
                None
            }
        } else {
            None
        };
        self.qs_touch_start_y = None;
        self.qs_touch_last_y = None;
        self.pending_toggle_index = None;
        self.is_scrolling = false;
        toggle_id
    }

    /// Get current brightness value for system sync
    pub fn get_qs_brightness(&self) -> f32 {
        self.quick_settings.brightness
    }
}
