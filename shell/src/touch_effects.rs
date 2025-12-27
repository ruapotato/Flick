//! Touch visual effects - GPU-based distortion effects
//!
//! Creates stunning touch feedback:
//! - Finger down: Fisheye/lens distortion under the finger
//! - Finger up: Expanding ripple distortion ring (like water)
//! - All effects are displacement-based, not color overlays
//! - All parameters are configurable via effects_config.json

use std::time::Instant;

/// Maximum number of active touch effects (for shader uniforms)
pub const MAX_TOUCH_EFFECTS: usize = 10;

/// Effect style determines the visual appearance
#[derive(Clone, Copy, Debug, PartialEq, Default)]
#[repr(i32)]
pub enum EffectStyle {
    #[default]
    Water = 0,        // Blue water ripple
    Snow = 1,         // White/blue snow/frost effect
    CRT = 2,          // CRT scanlines and effects
    TerminalRipple = 3, // ASCII effect on touched areas with ripple
}

impl From<i32> for EffectStyle {
    fn from(v: i32) -> Self {
        match v {
            1 => EffectStyle::Snow,
            2 => EffectStyle::CRT,
            3 => EffectStyle::TerminalRipple,
            _ => EffectStyle::Water,
        }
    }
}

/// Configurable effect parameters
#[derive(Clone, Debug)]
pub struct EffectConfig {
    pub effect_style: EffectStyle, // Visual style (water/snow/crt/terminal)
    pub fisheye_size: f32,      // Radius as fraction of screen (0.05 - 0.30)
    pub fisheye_strength: f32,  // Distortion strength (0.0 - 0.50)
    pub ripple_size: f32,       // Max radius as fraction of screen (0.10 - 0.50)
    pub ripple_strength: f32,   // Distortion strength (0.0 - 0.50)
    pub ripple_duration: f32,   // Duration in seconds (0.2 - 1.0)
    pub ascii_density: f32,     // ASCII character density (4.0 - 16.0, lower = larger chars)
    pub living_pixels: bool,    // Enable living pixels master toggle
    // Living pixels sub-toggles
    pub lp_stars: bool,         // Twinkling stars in dark areas
    pub lp_shooting_stars: bool, // Occasional shooting stars
    pub lp_fireflies: bool,     // Fireflies in dim areas
    pub lp_dust: bool,          // Floating dust motes in mid-tones
    pub lp_shimmer: bool,       // Shimmer in bright areas
    pub lp_eyes: bool,          // Soot sprites on edges
    pub lp_rain: bool,          // Compiz-style rain ripples
}

impl Default for EffectConfig {
    fn default() -> Self {
        Self {
            effect_style: EffectStyle::Water,
            fisheye_size: 0.16,      // 16% of screen
            fisheye_strength: 0.13,  // 13% distortion
            ripple_size: 0.30,       // 30% of screen
            ripple_strength: 0.07,   // 7% distortion (subtle)
            ripple_duration: 0.5,    // 0.5 seconds
            ascii_density: 8.0,      // Medium density
            living_pixels: false,    // Disabled by default
            lp_stars: true,
            lp_shooting_stars: true,
            lp_fireflies: true,
            lp_dust: true,
            lp_shimmer: true,
            lp_eyes: true,
            lp_rain: false,          // Disabled by default
        }
    }
}

impl EffectConfig {
    /// Load config from file, falling back to defaults
    pub fn load() -> Self {
        // Try multiple paths to find the config
        let possible_homes = [
            // Try SUDO_USER's home first
            std::env::var("SUDO_USER").ok().and_then(|user| {
                std::fs::read_to_string("/etc/passwd").ok().and_then(|passwd| {
                    passwd.lines()
                        .find(|line| line.starts_with(&format!("{}:", user)))
                        .and_then(|line| line.split(':').nth(5))
                        .map(|s| s.to_string())
                })
            }),
            // Try droidian's home directly (common on Droidian)
            Some("/home/droidian".to_string()),
            // Try HOME
            std::env::var("HOME").ok(),
        ];

        let config_path = possible_homes.iter()
            .filter_map(|h| h.as_ref())
            .map(|home| std::path::PathBuf::from(home).join(".local/state/flick/effects_config.json"))
            .find(|p| p.exists())
            .unwrap_or_else(|| std::path::PathBuf::from("/tmp/effects_config.json"));

        tracing::debug!("Loading effects config from: {:?}", config_path);

        if let Ok(contents) = std::fs::read_to_string(&config_path) {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&contents) {
                let style_val = json.get("touch_effect_style").and_then(|v| v.as_i64()).unwrap_or(0);
                let effect_style = EffectStyle::from(style_val as i32);
                tracing::info!("Loaded effect style: {:?} (raw value: {})", effect_style, style_val);
                return Self {
                    effect_style,
                    fisheye_size: json.get("fisheye_size")
                        .and_then(|v| v.as_f64())
                        .map(|v| v as f32)
                        .unwrap_or(0.16),
                    fisheye_strength: json.get("fisheye_strength")
                        .and_then(|v| v.as_f64())
                        .map(|v| v as f32)
                        .unwrap_or(0.13),
                    ripple_size: json.get("ripple_size")
                        .and_then(|v| v.as_f64())
                        .map(|v| v as f32)
                        .unwrap_or(0.30),
                    ripple_strength: json.get("ripple_strength")
                        .and_then(|v| v.as_f64())
                        .map(|v| v as f32)
                        .unwrap_or(0.07),
                    ripple_duration: json.get("ripple_duration")
                        .and_then(|v| v.as_f64())
                        .map(|v| v as f32)
                        .unwrap_or(0.5),
                    ascii_density: json.get("ascii_density")
                        .and_then(|v| v.as_f64())
                        .map(|v| v as f32)
                        .unwrap_or(8.0),
                    living_pixels: json.get("living_pixels")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false),
                    lp_stars: json.get("lp_stars")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(true),
                    lp_shooting_stars: json.get("lp_shooting_stars")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(true),
                    lp_fireflies: json.get("lp_fireflies")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(true),
                    lp_dust: json.get("lp_dust")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(true),
                    lp_shimmer: json.get("lp_shimmer")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(true),
                    lp_eyes: json.get("lp_eyes")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(true),
                    lp_rain: json.get("rain_effect_enabled")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false),
                };
            }
        }
        Self::default()
    }
}

/// Effect type determines the distortion behavior
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum EffectType {
    /// Fisheye lens effect while finger is pressed
    Fisheye,
    /// Expanding ripple ring on finger release
    Ripple,
}

/// A single touch effect
#[derive(Clone, Debug)]
pub struct TouchEffect {
    pub touch_id: u64,
    pub x: f64,
    pub y: f64,
    /// Initial touch position (for effects that should stay in place like snow)
    pub initial_x: f64,
    pub initial_y: f64,
    pub effect_type: EffectType,
    pub start_time: Instant,
    /// For fisheye: tracks if finger is still down
    pub active: bool,
}

impl TouchEffect {
    /// Create a new fisheye effect (finger down)
    pub fn new_fisheye(x: f64, y: f64, touch_id: u64) -> Self {
        Self {
            touch_id,
            x,
            y,
            initial_x: x,
            initial_y: y,
            effect_type: EffectType::Fisheye,
            start_time: Instant::now(),
            active: true,
        }
    }

    /// Convert to ripple effect (finger up)
    pub fn to_ripple(&mut self) {
        self.effect_type = EffectType::Ripple;
        self.start_time = Instant::now();
        self.active = false;
    }

    /// Update position (for fisheye tracking finger movement)
    pub fn update_position(&mut self, x: f64, y: f64) {
        if self.effect_type == EffectType::Fisheye && self.active {
            self.x = x;
            self.y = y;
        }
    }

    /// Get age in seconds
    pub fn age(&self) -> f64 {
        self.start_time.elapsed().as_secs_f64()
    }

    /// Check if effect is expired (uses config for ripple duration)
    pub fn is_expired_with_config(&self, config: &EffectConfig) -> bool {
        match self.effect_type {
            EffectType::Fisheye => !self.active, // Fisheye expires when finger lifts (converted to ripple)
            EffectType::Ripple => self.age() > config.ripple_duration as f64,
        }
    }

    /// Get effect parameters for shader using config values
    /// Returns (x, y, radius, strength, type_flag)
    /// x, y: normalized 0-1 screen coordinates
    /// radius: effect radius in normalized units
    /// strength: effect intensity 0-1
    /// type_flag: 0 = fisheye, 1+ = ripple (encodes progress)
    pub fn get_shader_params(&self, screen_width: f64, screen_height: f64, config: &EffectConfig) -> (f32, f32, f32, f32, f32) {
        // For snow effect, use initial position so crystal stays in place
        let (use_x, use_y) = if config.effect_style == EffectStyle::Snow {
            (self.initial_x, self.initial_y)
        } else {
            (self.x, self.y)
        };
        let nx = (use_x / screen_width) as f32;
        let ny = (use_y / screen_height) as f32;

        match self.effect_type {
            EffectType::Fisheye => {
                // Fisheye: constant radius, strength based on age (quick ramp up)
                let age = self.age();
                let ramp = (age * 8.0).min(1.0); // Ramp up over 0.125s
                let radius = config.fisheye_size;
                let strength = config.fisheye_strength * ramp as f32;
                (nx, ny, radius, strength, 0.0)
            }
            EffectType::Ripple => {
                // Ripple: expanding ring
                let age = self.age();
                let duration = config.ripple_duration as f64;
                let progress = (age / duration).min(1.0);

                // Smooth ease-out for expansion
                let eased = 1.0 - (1.0 - progress).powi(3);

                // Ring expands from 0 to configured max size
                let radius = config.ripple_size * eased as f32;

                // Strength fades out
                let strength = config.ripple_strength * (1.0 - progress as f32).powi(2);

                (nx, ny, radius, strength, 1.0 + progress as f32)
            }
        }
    }
}

/// Manager for all active touch effects
pub struct TouchEffectManager {
    effects: Vec<TouchEffect>,
    config: EffectConfig,
    config_check_counter: u32,
    /// Last touch position for eye tracking (screen coordinates)
    last_touch_x: f64,
    last_touch_y: f64,
    /// When the last touch occurred
    last_touch_time: Instant,
}

impl Default for TouchEffectManager {
    fn default() -> Self {
        Self::new()
    }
}

impl TouchEffectManager {
    pub fn new() -> Self {
        Self {
            effects: Vec::new(),
            config: EffectConfig::load(),
            config_check_counter: 0,
            last_touch_x: 0.0,
            last_touch_y: 0.0,
            last_touch_time: Instant::now(),
        }
    }

    /// Add a new touch (finger down) - creates fisheye effect
    pub fn add_touch(&mut self, x: f64, y: f64, touch_id: u64) {
        // Track last touch for eye behavior
        self.last_touch_x = x;
        self.last_touch_y = y;
        self.last_touch_time = Instant::now();
        // Remove any existing effect for this touch
        self.effects.retain(|e| e.touch_id != touch_id);
        self.effects.push(TouchEffect::new_fisheye(x, y, touch_id));
    }

    /// Update touch position (finger move)
    pub fn update_touch(&mut self, x: f64, y: f64, touch_id: u64) {
        // Track last touch for eye behavior
        self.last_touch_x = x;
        self.last_touch_y = y;
        self.last_touch_time = Instant::now();
        if let Some(effect) = self.effects.iter_mut().find(|e| e.touch_id == touch_id) {
            effect.update_position(x, y);
        }
    }

    /// End touch (finger up) - converts fisheye to ripple
    pub fn end_touch(&mut self, touch_id: u64) {
        if let Some(effect) = self.effects.iter_mut().find(|e| e.touch_id == touch_id) {
            effect.to_ripple();
        }
    }

    /// Clean up expired effects and periodically reload config
    pub fn cleanup(&mut self) {
        // Reload config every ~60 frames to pick up settings changes
        self.config_check_counter += 1;
        if self.config_check_counter >= 60 {
            self.config_check_counter = 0;
            self.config = EffectConfig::load();
        }

        let config = &self.config;
        self.effects.retain(|e| !e.is_expired_with_config(config));
    }

    /// Clear all effects
    pub fn clear(&mut self) {
        self.effects.clear();
    }

    /// Check if there are any active effects
    pub fn has_effects(&self) -> bool {
        !self.effects.is_empty()
    }

    /// Get all effects for rendering
    pub fn effects(&self) -> &[TouchEffect] {
        &self.effects
    }

    /// Get current config
    pub fn config(&self) -> &EffectConfig {
        &self.config
    }

    /// Get shader uniform data
    /// Returns arrays suitable for passing to GL uniforms
    pub fn get_shader_data(&self, screen_width: f64, screen_height: f64, time: f32) -> TouchEffectShaderData {
        let mut data = TouchEffectShaderData::default();
        data.effect_style = self.config.effect_style as i32;
        data.ascii_density = self.config.ascii_density;
        data.living_pixels = if self.config.living_pixels { 1 } else { 0 };
        data.time = time;

        // Pack sub-toggles into flags: bit0=stars, bit1=shooting, bit2=fireflies, bit3=dust, bit4=shimmer, bit5=eyes, bit6=rain
        data.lp_flags = 0;
        if self.config.lp_stars { data.lp_flags |= 1; }
        if self.config.lp_shooting_stars { data.lp_flags |= 2; }
        if self.config.lp_fireflies { data.lp_flags |= 4; }
        if self.config.lp_dust { data.lp_flags |= 8; }
        if self.config.lp_shimmer { data.lp_flags |= 16; }
        if self.config.lp_eyes { data.lp_flags |= 32; }
        if self.config.lp_rain { data.lp_flags |= 64; }

        // Last touch position for eye tracking
        data.last_touch_x = (self.last_touch_x / screen_width) as f32;
        data.last_touch_y = (self.last_touch_y / screen_height) as f32;
        data.time_since_touch = self.last_touch_time.elapsed().as_secs_f32();

        for (i, effect) in self.effects.iter().take(MAX_TOUCH_EFFECTS).enumerate() {
            let (x, y, radius, strength, type_flag) = effect.get_shader_params(screen_width, screen_height, &self.config);
            data.positions[i * 2] = x;
            data.positions[i * 2 + 1] = y;
            data.params[i * 4] = radius;
            data.params[i * 4 + 1] = strength;
            data.params[i * 4 + 2] = type_flag;
            data.params[i * 4 + 3] = 0.0; // Reserved
            data.count += 1;
        }

        data
    }
}

/// Shader uniform data for touch effects
#[derive(Clone, Debug)]
pub struct TouchEffectShaderData {
    /// Touch positions: [x0, y0, x1, y1, ...] normalized 0-1
    pub positions: [f32; MAX_TOUCH_EFFECTS * 2],
    /// Touch params: [radius0, strength0, type0, reserved0, radius1, ...]
    pub params: [f32; MAX_TOUCH_EFFECTS * 4],
    /// Number of active effects
    pub count: i32,
    /// Effect style: 0=water, 1=snow, 2=crt, 3=terminal_ripple
    pub effect_style: i32,
    /// ASCII character density (for terminal mode)
    pub ascii_density: f32,
    /// Living pixels enabled (stars in black, eyes in white)
    pub living_pixels: i32,
    /// Time in seconds for animations
    pub time: f32,
    /// Living pixels sub-toggles packed: bit0=stars, bit1=shooting, bit2=fireflies, bit3=dust, bit4=shimmer, bit5=eyes, bit6=rain
    pub lp_flags: i32,
    /// Last touch position (normalized 0-1), for eyes to look at
    pub last_touch_x: f32,
    pub last_touch_y: f32,
    /// Time since last touch (seconds), for eye sleepiness
    pub time_since_touch: f32,
}

impl Default for TouchEffectShaderData {
    fn default() -> Self {
        Self {
            positions: [0.0; MAX_TOUCH_EFFECTS * 2],
            params: [0.0; MAX_TOUCH_EFFECTS * 4],
            count: 0,
            effect_style: 0,
            ascii_density: 8.0,
            living_pixels: 0,
            time: 0.0,
            lp_flags: 0x3F, // All enabled by default
            last_touch_x: 0.5,
            last_touch_y: 0.5,
            time_since_touch: 999.0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fisheye_creation() {
        let effect = TouchEffect::new_fisheye(100.0, 200.0, 1);
        assert_eq!(effect.effect_type, EffectType::Fisheye);
        assert!(effect.active);
    }

    #[test]
    fn test_ripple_conversion() {
        let mut effect = TouchEffect::new_fisheye(100.0, 200.0, 1);
        effect.to_ripple();
        assert_eq!(effect.effect_type, EffectType::Ripple);
        assert!(!effect.active);
    }

    #[test]
    fn test_manager() {
        let mut manager = TouchEffectManager::new();
        manager.add_touch(100.0, 100.0, 1);
        assert!(manager.has_effects());
        assert_eq!(manager.effects().len(), 1);

        manager.end_touch(1);
        assert_eq!(manager.effects()[0].effect_type, EffectType::Ripple);
    }
}
