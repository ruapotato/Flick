//! Lock screen with PIN, pattern, and password authentication
//!
//! Provides a secure lock screen that blocks access until authenticated.
//! Supports multiple authentication methods with PAM password as fallback.

use std::fs;
use std::path::PathBuf;
use std::time::Instant;
use serde::{Deserialize, Serialize};
use smithay::utils::{Logical, Point, Size};
use super::primitives::{Rect, Color};
use super::text;

/// Lock screen authentication method
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LockMethod {
    /// No lock - unlock immediately (for development/testing)
    None,
    /// 4-6 digit PIN
    Pin,
    /// 3x3 pattern lock (Android-style)
    Pattern,
    /// Full PAM password
    Password,
}

impl Default for LockMethod {
    fn default() -> Self {
        LockMethod::None // Default to no lock for initial setup
    }
}

/// Lock screen configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LockConfig {
    /// Authentication method
    pub method: LockMethod,
    /// Bcrypt hash of PIN (if method is Pin)
    #[serde(default)]
    pub pin_hash: Option<String>,
    /// Bcrypt hash of pattern (if method is Pattern)
    /// Pattern is stored as comma-separated node indices (0-8)
    #[serde(default)]
    pub pattern_hash: Option<String>,
    /// Auto-lock timeout in seconds (0 = immediate, -1 = never)
    #[serde(default = "default_timeout")]
    pub timeout_seconds: i32,
    /// Number of failed attempts before lockout
    #[serde(default = "default_max_attempts")]
    pub max_attempts: u32,
}

fn default_timeout() -> i32 { 300 } // 5 minutes
fn default_max_attempts() -> u32 { 5 }

impl Default for LockConfig {
    fn default() -> Self {
        Self {
            method: LockMethod::None,
            pin_hash: None,
            pattern_hash: None,
            timeout_seconds: default_timeout(),
            max_attempts: default_max_attempts(),
        }
    }
}

impl LockConfig {
    /// Get the config file path
    fn config_path() -> Option<PathBuf> {
        std::env::var("HOME").ok().map(|home| {
            PathBuf::from(home).join(".local/state/flick/lock_config.json")
        })
    }

    /// Load config from file, or return default if not found
    pub fn load() -> Self {
        if let Some(path) = Self::config_path() {
            if let Ok(contents) = fs::read_to_string(&path) {
                if let Ok(config) = serde_json::from_str(&contents) {
                    tracing::info!("Loaded lock config from {:?}", path);
                    return config;
                }
            }
        }
        tracing::info!("No lock config found, using defaults (no lock)");
        Self::default()
    }

    /// Save config to file
    pub fn save(&self) {
        if let Some(path) = Self::config_path() {
            if let Some(parent) = path.parent() {
                let _ = fs::create_dir_all(parent);
            }
            if let Ok(json) = serde_json::to_string_pretty(self) {
                if let Err(e) = fs::write(&path, json) {
                    tracing::warn!("Failed to save lock config: {:?}", e);
                } else {
                    tracing::info!("Saved lock config to {:?}", path);
                }
            }
        }
    }

    /// Verify a PIN against the stored hash
    pub fn verify_pin(&self, pin: &str) -> bool {
        if let Some(ref hash) = self.pin_hash {
            bcrypt::verify(pin, hash).unwrap_or(false)
        } else {
            false
        }
    }

    /// Verify a pattern against the stored hash
    /// Pattern is a sequence of node indices (0-8)
    pub fn verify_pattern(&self, pattern: &[u8]) -> bool {
        if let Some(ref hash) = self.pattern_hash {
            let pattern_str = pattern.iter()
                .map(|n| n.to_string())
                .collect::<Vec<_>>()
                .join(",");
            bcrypt::verify(&pattern_str, hash).unwrap_or(false)
        } else {
            false
        }
    }

    /// Set a new PIN (hashes it before storing)
    pub fn set_pin(&mut self, pin: &str) -> Result<(), bcrypt::BcryptError> {
        let hash = bcrypt::hash(pin, bcrypt::DEFAULT_COST)?;
        self.pin_hash = Some(hash);
        self.method = LockMethod::Pin;
        Ok(())
    }

    /// Set a new pattern (hashes it before storing)
    pub fn set_pattern(&mut self, pattern: &[u8]) -> Result<(), bcrypt::BcryptError> {
        let pattern_str = pattern.iter()
            .map(|n| n.to_string())
            .collect::<Vec<_>>()
            .join(",");
        let hash = bcrypt::hash(&pattern_str, bcrypt::DEFAULT_COST)?;
        self.pattern_hash = Some(hash);
        self.method = LockMethod::Pattern;
        Ok(())
    }
}

/// Lock screen input mode
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum LockInputMode {
    /// Showing PIN pad
    Pin,
    /// Showing pattern grid
    Pattern,
    /// Showing password field (for PAM auth)
    Password,
}

/// Lock screen runtime state
#[derive(Debug, Clone)]
pub struct LockScreenState {
    /// Current input mode
    pub input_mode: LockInputMode,
    /// Entered PIN digits (hidden as dots)
    pub entered_pin: String,
    /// Pattern nodes touched during current gesture (0-8)
    pub pattern_nodes: Vec<u8>,
    /// Is pattern gesture currently active (finger down)
    pub pattern_active: bool,
    /// Current touch position for pattern drawing
    pub pattern_touch_pos: Option<Point<f64, Logical>>,
    /// Entered password text
    pub entered_password: String,
    /// Number of failed attempts
    pub failed_attempts: u32,
    /// Time of last failed attempt (for rate limiting)
    pub last_failed_attempt: Option<Instant>,
    /// Error message to display
    pub error_message: Option<String>,
    /// Currently pressed button (for visual feedback)
    pub pressed_button: Option<usize>,
}

impl Default for LockScreenState {
    fn default() -> Self {
        Self {
            input_mode: LockInputMode::Pin,
            entered_pin: String::new(),
            pattern_nodes: Vec::new(),
            pattern_active: false,
            pattern_touch_pos: None,
            entered_password: String::new(),
            failed_attempts: 0,
            last_failed_attempt: None,
            error_message: None,
            pressed_button: None,
        }
    }
}

impl LockScreenState {
    /// Create new lock screen state based on config
    pub fn new(config: &LockConfig) -> Self {
        let input_mode = match config.method {
            LockMethod::None => LockInputMode::Pin, // Will auto-unlock anyway
            LockMethod::Pin => LockInputMode::Pin,
            LockMethod::Pattern => LockInputMode::Pattern,
            LockMethod::Password => LockInputMode::Password,
        };

        Self {
            input_mode,
            ..Default::default()
        }
    }

    /// Reset input state (after failed attempt or mode switch)
    pub fn reset_input(&mut self) {
        self.entered_pin.clear();
        self.pattern_nodes.clear();
        self.pattern_active = false;
        self.pattern_touch_pos = None;
        self.entered_password.clear();
        self.pressed_button = None;
    }

    /// Record a failed attempt
    pub fn record_failed_attempt(&mut self) {
        self.failed_attempts += 1;
        self.last_failed_attempt = Some(Instant::now());
        self.error_message = Some(format!(
            "Wrong {}. {} attempts remaining.",
            match self.input_mode {
                LockInputMode::Pin => "PIN",
                LockInputMode::Pattern => "pattern",
                LockInputMode::Password => "password",
            },
            5u32.saturating_sub(self.failed_attempts)
        ));
    }

    /// Check if currently locked out due to too many attempts
    pub fn is_locked_out(&self) -> bool {
        if self.failed_attempts >= 5 {
            if let Some(last) = self.last_failed_attempt {
                // Lock out for 30 seconds after 5 failed attempts
                return last.elapsed().as_secs() < 30;
            }
        }
        false
    }

    /// Get lockout remaining seconds
    pub fn lockout_remaining(&self) -> u64 {
        if let Some(last) = self.last_failed_attempt {
            let elapsed = last.elapsed().as_secs();
            if elapsed < 30 {
                return 30 - elapsed;
            }
        }
        0
    }

    /// Switch to password mode (fallback)
    pub fn switch_to_password(&mut self) {
        self.input_mode = LockInputMode::Password;
        self.reset_input();
        self.error_message = None;
    }
}

/// PIN pad button layout (3x4 grid + backspace/enter)
pub const PIN_BUTTONS: &[&str] = &[
    "1", "2", "3",
    "4", "5", "6",
    "7", "8", "9",
    "<", "0", "OK",
];

/// Get PIN pad button positions
pub fn get_pin_button_rects(screen_size: Size<i32, Logical>) -> Vec<(Rect, &'static str)> {
    let screen_w = screen_size.w as f64;
    let screen_h = screen_size.h as f64;

    let button_size = 80.0;
    let button_gap = 20.0;
    let grid_width = 3.0 * button_size + 2.0 * button_gap;
    let grid_height = 4.0 * button_size + 3.0 * button_gap;

    let start_x = (screen_w - grid_width) / 2.0;
    let start_y = screen_h * 0.4;

    let mut buttons = Vec::new();

    for (i, label) in PIN_BUTTONS.iter().enumerate() {
        let row = i / 3;
        let col = i % 3;
        let x = start_x + col as f64 * (button_size + button_gap);
        let y = start_y + row as f64 * (button_size + button_gap);
        buttons.push((Rect::new(x, y, button_size, button_size), *label));
    }

    buttons
}

/// Get pattern grid dot positions (3x3 grid)
pub fn get_pattern_dot_positions(screen_size: Size<i32, Logical>) -> Vec<Point<f64, Logical>> {
    let screen_w = screen_size.w as f64;
    let screen_h = screen_size.h as f64;

    let dot_spacing = 100.0;
    let grid_size = 2.0 * dot_spacing;
    let start_x = (screen_w - grid_size) / 2.0;
    let start_y = screen_h * 0.4;

    let mut dots = Vec::new();

    for row in 0..3 {
        for col in 0..3 {
            let x = start_x + col as f64 * dot_spacing;
            let y = start_y + row as f64 * dot_spacing;
            dots.push(Point::from((x, y)));
        }
    }

    dots
}

/// Check if a point is near a pattern dot
pub fn hit_test_pattern_dot(pos: Point<f64, Logical>, dots: &[Point<f64, Logical>]) -> Option<u8> {
    let hit_radius = 40.0;

    for (i, dot) in dots.iter().enumerate() {
        let dx = pos.x - dot.x;
        let dy = pos.y - dot.y;
        if dx * dx + dy * dy < hit_radius * hit_radius {
            return Some(i as u8);
        }
    }

    None
}

/// Render lock screen elements
pub fn render_lock_screen(
    state: &LockScreenState,
    config: &LockConfig,
    screen_size: Size<i32, Logical>,
) -> Vec<(Rect, Color)> {
    let mut elements = Vec::new();
    let screen_w = screen_size.w as f64;
    let screen_h = screen_size.h as f64;

    // Background
    elements.push((
        Rect::new(0.0, 0.0, screen_w, screen_h),
        [0.05, 0.05, 0.1, 1.0], // Dark background
    ));

    // Title area
    let title = match state.input_mode {
        LockInputMode::Pin => "Enter PIN",
        LockInputMode::Pattern => "Draw Pattern",
        LockInputMode::Password => "Enter Password",
    };
    let title_y = screen_h * 0.15;
    elements.extend(text::render_text_centered(title, screen_w / 2.0, title_y, 4.0, [1.0, 1.0, 1.0, 1.0]));

    // Show lockout message if applicable
    if state.is_locked_out() {
        let msg = format!("Try again in {}s", state.lockout_remaining());
        elements.extend(text::render_text_centered(&msg, screen_w / 2.0, title_y + 50.0, 2.0, [1.0, 0.3, 0.3, 1.0]));
        return elements;
    }

    // Error message
    if let Some(ref msg) = state.error_message {
        elements.extend(text::render_text_centered(msg, screen_w / 2.0, title_y + 50.0, 2.0, [1.0, 0.5, 0.5, 1.0]));
    }

    // Input indicator (dots for PIN/password)
    match state.input_mode {
        LockInputMode::Pin => {
            // Show dots for entered digits
            let dot_size = 15.0;
            let dot_gap = 25.0;
            let num_dots = state.entered_pin.len();
            let indicator_width = num_dots as f64 * (dot_size + dot_gap) - dot_gap;
            let start_x = (screen_w - indicator_width) / 2.0;
            let dot_y = screen_h * 0.28;

            for i in 0..num_dots {
                let x = start_x + i as f64 * (dot_size + dot_gap);
                elements.push((
                    Rect::new(x, dot_y, dot_size, dot_size),
                    [1.0, 1.0, 1.0, 1.0],
                ));
            }

            // PIN pad buttons
            let buttons = get_pin_button_rects(screen_size);
            for (i, (rect, label)) in buttons.iter().enumerate() {
                // Button background
                let is_pressed = state.pressed_button == Some(i);
                let bg_color = if is_pressed {
                    [0.3, 0.5, 0.8, 1.0]
                } else {
                    [0.2, 0.2, 0.3, 1.0]
                };
                elements.push((*rect, bg_color));

                // Button label
                let label_x = rect.x + rect.width / 2.0;
                let label_y = rect.y + rect.height / 2.0 - 10.0;
                elements.extend(text::render_text_centered(label, label_x, label_y, 3.0, [1.0, 1.0, 1.0, 1.0]));
            }
        }

        LockInputMode::Pattern => {
            // Pattern dots
            let dots = get_pattern_dot_positions(screen_size);
            let dot_radius = 15.0;

            for (i, dot) in dots.iter().enumerate() {
                let is_selected = state.pattern_nodes.contains(&(i as u8));
                let color = if is_selected {
                    [0.3, 0.7, 1.0, 1.0] // Highlighted
                } else {
                    [0.5, 0.5, 0.6, 1.0] // Normal
                };

                elements.push((
                    Rect::new(dot.x - dot_radius, dot.y - dot_radius, dot_radius * 2.0, dot_radius * 2.0),
                    color,
                ));
            }

            // Draw lines between selected nodes
            // (Using thin rectangles as approximation)
            for i in 1..state.pattern_nodes.len() {
                let from_idx = state.pattern_nodes[i - 1] as usize;
                let to_idx = state.pattern_nodes[i] as usize;
                if from_idx < dots.len() && to_idx < dots.len() {
                    let from = dots[from_idx];
                    let to = dots[to_idx];
                    // Draw line segments as small rectangles
                    let line_rects = draw_line(from, to, 4.0, [0.3, 0.7, 1.0, 0.8]);
                    elements.extend(line_rects);
                }
            }

            // Draw line to current touch position if active
            if state.pattern_active {
                if let (Some(&last_node), Some(touch_pos)) = (state.pattern_nodes.last(), state.pattern_touch_pos) {
                    if (last_node as usize) < dots.len() {
                        let from = dots[last_node as usize];
                        let line_rects = draw_line(from, touch_pos, 4.0, [0.3, 0.7, 1.0, 0.5]);
                        elements.extend(line_rects);
                    }
                }
            }
        }

        LockInputMode::Password => {
            // Password dots
            let dot_size = 12.0;
            let dot_gap = 15.0;
            let num_dots = state.entered_password.len().min(20);
            let indicator_width = num_dots as f64 * (dot_size + dot_gap) - dot_gap;
            let start_x = (screen_w - indicator_width) / 2.0;
            let dot_y = screen_h * 0.35;

            for i in 0..num_dots {
                let x = start_x + i as f64 * (dot_size + dot_gap);
                elements.push((
                    Rect::new(x, dot_y, dot_size, dot_size),
                    [1.0, 1.0, 1.0, 1.0],
                ));
            }

            // Instruction text
            elements.extend(text::render_text_centered(
                "Use keyboard to type password",
                screen_w / 2.0,
                screen_h * 0.5,
                2.0,
                [0.7, 0.7, 0.7, 1.0],
            ));
        }
    }

    // "Use Password" fallback link (always visible for PIN/Pattern)
    if state.input_mode != LockInputMode::Password && config.method != LockMethod::Password {
        let link_y = screen_h * 0.9;
        elements.extend(text::render_text_centered(
            "Use Password",
            screen_w / 2.0,
            link_y,
            2.0,
            [0.5, 0.7, 1.0, 1.0],
        ));
    }

    elements
}

/// Draw a line between two points using small rectangles
fn draw_line(from: Point<f64, Logical>, to: Point<f64, Logical>, thickness: f64, color: Color) -> Vec<(Rect, Color)> {
    let mut rects = Vec::new();

    let dx = to.x - from.x;
    let dy = to.y - from.y;
    let length = (dx * dx + dy * dy).sqrt();

    if length < 1.0 {
        return rects;
    }

    let step = thickness;
    let steps = (length / step) as usize;

    for i in 0..=steps {
        let t = i as f64 / steps as f64;
        let x = from.x + dx * t;
        let y = from.y + dy * t;
        rects.push((
            Rect::new(x - thickness / 2.0, y - thickness / 2.0, thickness, thickness),
            color,
        ));
    }

    rects
}

/// Authenticate with PAM
pub fn authenticate_pam(username: &str, password: &str) -> bool {
    use pam::Authenticator;

    match Authenticator::with_password("flick") {
        Ok(mut auth) => {
            auth.get_handler().set_credentials(username, password);
            match auth.authenticate() {
                Ok(()) => {
                    tracing::info!("PAM authentication successful for user {}", username);
                    true
                }
                Err(e) => {
                    tracing::warn!("PAM authentication failed: {:?}", e);
                    false
                }
            }
        }
        Err(e) => {
            tracing::error!("Failed to create PAM authenticator: {:?}", e);
            false
        }
    }
}

/// Get current username
pub fn get_current_user() -> Option<String> {
    std::env::var("USER").ok()
}
