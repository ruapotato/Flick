//! Integrated shell UI - rendered directly by the compositor
//!
//! Components:
//! - App grid (home screen)
//! - App switcher (Android-style card stack)
//! - Gesture overlays (back, close indicators)

pub mod primitives;
pub mod app_grid;
pub mod app_switcher;
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
    /// Touch tracking for scrolling
    pub scroll_touch_start_y: Option<f64>,
    pub scroll_touch_last_y: Option<f64>,
    /// Pending app launch (exec command) - waits for touch up to confirm tap vs scroll
    pub pending_app_launch: Option<String>,
    /// Whether current touch is scrolling (moved significantly)
    pub is_scrolling: bool,
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
            pending_app_launch: None,
            is_scrolling: false,
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
            // If moved more than 20 pixels, it's a scroll, not a tap
            if total_delta > 20.0 {
                self.is_scrolling = true;
                self.pending_app_launch = None; // Cancel pending app launch
            }
        }

        if let Some(last_y) = self.scroll_touch_last_y {
            let delta = last_y - y; // Scroll down when finger moves up
            self.home_scroll = (self.home_scroll + delta).max(0.0);
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
                            // Swipe right - back (sent to app)
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

    /// Check if shell UI should be visible
    pub fn is_visible(&self) -> bool {
        match self.view {
            ShellView::App => {
                // Show during gesture animations
                self.gesture.edge.is_some()
            }
            ShellView::Home | ShellView::Switcher => true,
        }
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
            // Debug: log each rect
            tracing::debug!("App {} '{}': rect ({:.0},{:.0} {:.0}x{:.0}), touch ({:.0},{:.0})",
                i, app.exec, rect.x, rect.y, rect.width, rect.height, pos.x, pos.y);
            if pos.x >= rect.x && pos.x < rect.x + rect.width &&
               pos.y >= rect.y && pos.y < rect.y + rect.height {
                tracing::info!("Hit app {} '{}'", i, app.exec);
                return Some(i);
            }
        }

        tracing::debug!("No app hit at ({:.0},{:.0})", pos.x, pos.y);
        None
    }
}
