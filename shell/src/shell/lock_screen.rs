//! Lock screen with PIN, pattern, and password authentication
//!
//! Provides a secure lock screen that blocks access until authenticated.
//! Supports multiple authentication methods with PAM password as fallback.
//!
//! NOTE: Rendering is handled by Slint UI (shell.slint LockScreen component).
//! This module only contains authentication logic and state management.

use std::fs;
use std::path::PathBuf;
use std::time::Instant;
use serde::{Deserialize, Serialize};
use smithay::utils::{Logical, Point};

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
        LockMethod::Password // Default to password auth for security
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
            method: LockMethod::default(),
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
            tracing::info!("Looking for lock config at: {:?}", path);
            match fs::read_to_string(&path) {
                Ok(contents) => {
                    tracing::info!("Read lock config file, contents: {}", contents);
                    match serde_json::from_str(&contents) {
                        Ok(config) => {
                            tracing::info!("Loaded lock config from {:?}", path);
                            return config;
                        }
                        Err(e) => {
                            tracing::warn!("Failed to parse lock config: {:?}", e);
                        }
                    }
                }
                Err(e) => {
                    tracing::info!("Could not read lock config file: {:?}", e);
                }
            }
        } else {
            tracing::warn!("Could not determine lock config path (HOME not set?)");
        }
        tracing::info!("Using default lock config (password auth)");
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
        let pattern_str = pattern.iter()
            .map(|n| n.to_string())
            .collect::<Vec<_>>()
            .join(",");

        if let Some(ref hash) = self.pattern_hash {
            // Check if hash is a valid bcrypt hash (starts with $2)
            if hash.starts_with("$2") {
                return bcrypt::verify(&pattern_str, hash).unwrap_or(false);
            }
        }

        // No valid hash set - generate and log one for first-time setup
        if pattern.len() >= 4 {
            if let Ok(new_hash) = bcrypt::hash(&pattern_str, bcrypt::DEFAULT_COST) {
                tracing::info!("PATTERN SETUP: To save this pattern, set pattern_hash to: {}", new_hash);
            }
            // Accept the pattern for now (first-time setup mode)
            tracing::warn!("No valid pattern hash configured - accepting pattern for first-time setup");
            return true;
        }
        false
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
