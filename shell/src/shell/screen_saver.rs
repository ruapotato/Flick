//! Screen saver effects for the lock screen
//!
//! These run when the display is blanked and the lock screen is active,
//! waking the display briefly to show fun visual effects.

use std::time::{Duration, Instant};

/// Available screen saver effects
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ScreenSaverType {
    SpyEye,      // Creepy eye that looks around
    Pacman,      // Pacman crossing the screen
    Pipes,       // Classic pipes screen saver
    Starfield,   // Flying through stars
    Matrix,      // Matrix rain effect
    Bouncing,    // Bouncing logo/shape
}

impl ScreenSaverType {
    pub fn all() -> &'static [ScreenSaverType] {
        &[
            ScreenSaverType::SpyEye,
            ScreenSaverType::Pacman,
            ScreenSaverType::Pipes,
            ScreenSaverType::Starfield,
            ScreenSaverType::Matrix,
            ScreenSaverType::Bouncing,
        ]
    }

    pub fn name(&self) -> &'static str {
        match self {
            ScreenSaverType::SpyEye => "Spy Eye",
            ScreenSaverType::Pacman => "Pacman",
            ScreenSaverType::Pipes => "Pipes",
            ScreenSaverType::Starfield => "Starfield",
            ScreenSaverType::Matrix => "Matrix",
            ScreenSaverType::Bouncing => "Bouncing",
        }
    }
}

/// Screen saver configuration
#[derive(Debug, Clone)]
pub struct ScreenSaverConfig {
    /// Whether screen savers are enabled
    pub enabled: bool,
    /// Which screen savers are enabled (pick randomly from enabled ones)
    pub enabled_savers: Vec<ScreenSaverType>,
    /// How long screen savers can run after lock (seconds, max 300 = 5 min)
    pub duration_secs: u64,
    /// Delay before first screen saver appears (seconds)
    pub initial_delay_secs: u64,
    /// Accent color for effects (hex string like "#e94560")
    pub accent_color: [f32; 4], // RGBA
}

impl Default for ScreenSaverConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            enabled_savers: vec![ScreenSaverType::SpyEye],
            duration_secs: 60, // 1 minute default
            initial_delay_secs: 30, // First saver appears 30s after blank
            accent_color: [0.91, 0.27, 0.38, 1.0], // #e94560
        }
    }
}

impl ScreenSaverConfig {
    /// Load config from display_config.json
    pub fn load() -> Self {
        let config_path = Self::config_path();
        let mut config = Self::default();

        if let Ok(contents) = std::fs::read_to_string(&config_path) {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&contents) {
                if let Some(enabled) = json.get("screen_saver_enabled").and_then(|v| v.as_bool()) {
                    config.enabled = enabled;
                }
                if let Some(duration) = json.get("screen_saver_duration").and_then(|v| v.as_u64()) {
                    config.duration_secs = duration.min(300);
                }
                if let Some(delay) = json.get("screen_saver_delay").and_then(|v| v.as_u64()) {
                    config.initial_delay_secs = delay;
                }
                if let Some(color) = json.get("accent_color").and_then(|v| v.as_str()) {
                    config.accent_color = parse_hex_color(color);
                }
                // Parse enabled savers list
                if let Some(savers) = json.get("screen_savers").and_then(|v| v.as_array()) {
                    config.enabled_savers = savers
                        .iter()
                        .filter_map(|v| v.as_str())
                        .filter_map(|s| match s {
                            "spy_eye" => Some(ScreenSaverType::SpyEye),
                            "pacman" => Some(ScreenSaverType::Pacman),
                            "pipes" => Some(ScreenSaverType::Pipes),
                            "starfield" => Some(ScreenSaverType::Starfield),
                            "matrix" => Some(ScreenSaverType::Matrix),
                            "bouncing" => Some(ScreenSaverType::Bouncing),
                            _ => None,
                        })
                        .collect();
                    if config.enabled_savers.is_empty() {
                        config.enabled_savers = vec![ScreenSaverType::SpyEye];
                    }
                }
            }
        }

        config
    }

    fn config_path() -> String {
        let home = if let Ok(sudo_user) = std::env::var("SUDO_USER") {
            format!("/home/{}", sudo_user)
        } else {
            std::env::var("HOME").unwrap_or_else(|_| "/home/droidian".to_string())
        };
        format!("{}/.local/state/flick/display_config.json", home)
    }
}

/// Parse hex color string to RGBA floats
fn parse_hex_color(hex: &str) -> [f32; 4] {
    let hex = hex.trim_start_matches('#');
    if hex.len() >= 6 {
        let r = u8::from_str_radix(&hex[0..2], 16).unwrap_or(233) as f32 / 255.0;
        let g = u8::from_str_radix(&hex[2..4], 16).unwrap_or(69) as f32 / 255.0;
        let b = u8::from_str_radix(&hex[4..6], 16).unwrap_or(96) as f32 / 255.0;
        [r, g, b, 1.0]
    } else {
        [0.91, 0.27, 0.38, 1.0] // Default accent
    }
}

/// Runtime state for screen saver
#[derive(Debug)]
pub struct ScreenSaverState {
    /// Current config
    pub config: ScreenSaverConfig,
    /// When the display was blanked (for timing screen saver start)
    pub blanked_at: Option<Instant>,
    /// Currently running screen saver
    pub active_saver: Option<ActiveScreenSaver>,
    /// When current screen saver started
    pub saver_started_at: Option<Instant>,
    /// Whether we're in the screen saver window (time since lock < duration)
    pub in_saver_window: bool,
    /// When the lock screen became active
    pub lock_started_at: Option<Instant>,
}

impl ScreenSaverState {
    pub fn new() -> Self {
        Self {
            config: ScreenSaverConfig::load(),
            blanked_at: None,
            active_saver: None,
            saver_started_at: None,
            in_saver_window: false,
            lock_started_at: None,
        }
    }

    /// Called when display is blanked
    pub fn on_display_blanked(&mut self) {
        self.blanked_at = Some(Instant::now());
        tracing::info!("Screen saver: display blanked, will trigger in {}s",
                       self.config.initial_delay_secs);
    }

    /// Called when display is unblanked (user activity)
    pub fn on_display_unblanked(&mut self) {
        self.blanked_at = None;
        self.active_saver = None;
        self.saver_started_at = None;
    }

    /// Called when lock screen becomes active
    pub fn on_lock_screen_active(&mut self) {
        self.lock_started_at = Some(Instant::now());
        self.in_saver_window = true;
        self.config = ScreenSaverConfig::load(); // Reload config
        tracing::info!("Screen saver: lock active, window open for {}s",
                       self.config.duration_secs);
    }

    /// Called when lock screen is dismissed
    pub fn on_unlock(&mut self) {
        self.lock_started_at = None;
        self.in_saver_window = false;
        self.blanked_at = None;
        self.active_saver = None;
        self.saver_started_at = None;
    }

    /// Check if we should start a screen saver
    /// Returns true if display should be woken for screen saver
    pub fn should_start_saver(&mut self) -> bool {
        if !self.config.enabled || self.config.enabled_savers.is_empty() {
            return false;
        }

        // Check if we're still in the screen saver window
        if let Some(lock_start) = self.lock_started_at {
            if lock_start.elapsed() > Duration::from_secs(self.config.duration_secs) {
                self.in_saver_window = false;
                return false;
            }
        } else {
            return false;
        }

        // Check if enough time has passed since blanking
        if let Some(blanked) = self.blanked_at {
            if blanked.elapsed() >= Duration::from_secs(self.config.initial_delay_secs) {
                // Time to start a screen saver!
                if self.active_saver.is_none() {
                    self.start_random_saver();
                    return true;
                }
            }
        }

        false
    }

    /// Start a random screen saver from enabled list
    fn start_random_saver(&mut self) {
        // Simple pseudo-random using time
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let idx = (now as usize) % self.config.enabled_savers.len();
        let saver_type = self.config.enabled_savers[idx];

        tracing::info!("Screen saver: starting {:?}", saver_type);

        self.active_saver = Some(ActiveScreenSaver::new(saver_type, self.config.accent_color));
        self.saver_started_at = Some(Instant::now());
    }

    /// Check if current screen saver is done
    pub fn is_saver_done(&self) -> bool {
        if let Some(ref saver) = self.active_saver {
            saver.is_done()
        } else {
            true
        }
    }

    /// Update the active screen saver, returns true if still running
    pub fn update(&mut self) -> bool {
        if let Some(ref mut saver) = self.active_saver {
            saver.update();
            if saver.is_done() {
                tracing::info!("Screen saver: {:?} finished", saver.saver_type);
                self.active_saver = None;
                self.blanked_at = Some(Instant::now()); // Reset timer for next saver
                return false;
            }
            return true;
        }
        false
    }
}

/// Active screen saver instance with animation state
#[derive(Debug)]
pub struct ActiveScreenSaver {
    pub saver_type: ScreenSaverType,
    pub started_at: Instant,
    pub accent_color: [f32; 4],

    // Animation state (varies by type)
    pub phase: f32, // 0.0 to 1.0 for main animation
    pub eye_open: f32, // 0.0 closed, 1.0 open (for SpyEye)
    pub eye_look_x: f32, // -1 to 1 (for SpyEye)
    pub eye_look_y: f32, // -1 to 1 (for SpyEye)
    pub pacman_x: f32, // 0.0 to 1.0 screen position
    pub pacman_dir: i32, // 1 = right, -1 = left
    pub pacman_mouth: f32, // 0.0 to 1.0 for mouth animation
    pub done: bool,
}

impl ActiveScreenSaver {
    pub fn new(saver_type: ScreenSaverType, accent_color: [f32; 4]) -> Self {
        Self {
            saver_type,
            started_at: Instant::now(),
            accent_color,
            phase: 0.0,
            eye_open: 0.0,
            eye_look_x: 0.0,
            eye_look_y: 0.0,
            pacman_x: -0.1, // Start off screen
            pacman_dir: 1,
            pacman_mouth: 0.0,
            done: false,
        }
    }

    pub fn update(&mut self) {
        let elapsed = self.started_at.elapsed().as_secs_f32();

        match self.saver_type {
            ScreenSaverType::SpyEye => self.update_spy_eye(elapsed),
            ScreenSaverType::Pacman => self.update_pacman(elapsed),
            _ => {
                // Other savers run for 5 seconds then done
                if elapsed > 5.0 {
                    self.done = true;
                }
                self.phase = (elapsed / 5.0).min(1.0);
            }
        }
    }

    fn update_spy_eye(&mut self, elapsed: f32) {
        // Timeline: 0-1s open, 1-5s look around, 5-6s close
        const OPEN_TIME: f32 = 1.0;
        const LOOK_TIME: f32 = 4.0;
        const CLOSE_TIME: f32 = 1.0;
        const TOTAL_TIME: f32 = OPEN_TIME + LOOK_TIME + CLOSE_TIME;

        if elapsed < OPEN_TIME {
            // Opening
            self.eye_open = elapsed / OPEN_TIME;
            self.eye_look_x = 0.0;
            self.eye_look_y = 0.0;
        } else if elapsed < OPEN_TIME + LOOK_TIME {
            // Looking around
            self.eye_open = 1.0;
            let look_phase = (elapsed - OPEN_TIME) / LOOK_TIME;
            // Smooth random-ish movement using sin/cos
            self.eye_look_x = (look_phase * 7.0).sin() * 0.7;
            self.eye_look_y = (look_phase * 5.0).cos() * 0.4;
        } else if elapsed < TOTAL_TIME {
            // Closing
            let close_phase = (elapsed - OPEN_TIME - LOOK_TIME) / CLOSE_TIME;
            self.eye_open = 1.0 - close_phase;
            // Return to center while closing
            self.eye_look_x *= 1.0 - close_phase;
            self.eye_look_y *= 1.0 - close_phase;
        } else {
            self.done = true;
        }

        self.phase = (elapsed / TOTAL_TIME).min(1.0);
    }

    fn update_pacman(&mut self, elapsed: f32) {
        // Pacman crosses screen in about 4 seconds
        const CROSS_TIME: f32 = 4.0;

        self.pacman_x = -0.15 + (elapsed / CROSS_TIME) * 1.3; // -0.15 to 1.15
        self.pacman_mouth = (elapsed * 8.0).sin() * 0.5 + 0.5; // Chomping animation

        if self.pacman_x > 1.15 {
            self.done = true;
        }

        self.phase = (elapsed / CROSS_TIME).min(1.0);
    }

    pub fn is_done(&self) -> bool {
        self.done
    }
}
