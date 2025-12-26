//! Touch visual effects - GPU-based distortion effects
//!
//! Creates stunning touch feedback:
//! - Finger down: Fisheye/lens distortion under the finger
//! - Finger up: Expanding ripple distortion ring (like water)
//! - All effects are displacement-based, not color overlays

use std::time::Instant;

/// Maximum number of active touch effects (for shader uniforms)
pub const MAX_TOUCH_EFFECTS: usize = 10;

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

    /// Check if effect is expired
    pub fn is_expired(&self) -> bool {
        match self.effect_type {
            EffectType::Fisheye => !self.active, // Fisheye expires when finger lifts (converted to ripple)
            EffectType::Ripple => self.age() > 0.6, // Ripple lasts 0.6 seconds
        }
    }

    /// Get effect parameters for shader
    /// Returns (x, y, radius, strength, type_flag)
    /// x, y: normalized 0-1 screen coordinates
    /// radius: effect radius in normalized units
    /// strength: effect intensity 0-1
    /// type_flag: 0 = fisheye, 1 = ripple
    pub fn get_shader_params(&self, screen_width: f64, screen_height: f64) -> (f32, f32, f32, f32, f32) {
        let nx = (self.x / screen_width) as f32;
        let ny = (self.y / screen_height) as f32;

        match self.effect_type {
            EffectType::Fisheye => {
                // Fisheye: constant radius, strength based on age (quick ramp up)
                let age = self.age();
                let ramp = (age * 8.0).min(1.0); // Ramp up over 0.125s
                let radius = 0.15; // 15% of screen
                let strength = 0.3 * ramp; // 30% max distortion
                (nx, ny, radius as f32, strength as f32, 0.0)
            }
            EffectType::Ripple => {
                // Ripple: expanding ring
                let age = self.age();
                let duration = 0.6;
                let progress = (age / duration).min(1.0);

                // Smooth ease-out for expansion
                let eased = 1.0 - (1.0 - progress).powi(3);

                // Ring expands from 0 to 30% of screen
                let radius = 0.30 * eased;

                // Ring thickness decreases as it expands
                // Encoded in the strength: positive = ring inner edge, we use a formula
                // Strength fades out
                let strength = 0.25 * (1.0 - progress).powi(2);

                (nx, ny, radius as f32, strength as f32, 1.0 + progress as f32)
            }
        }
    }
}

/// Manager for all active touch effects
#[derive(Default)]
pub struct TouchEffectManager {
    effects: Vec<TouchEffect>,
}

impl TouchEffectManager {
    pub fn new() -> Self {
        Self { effects: Vec::new() }
    }

    /// Add a new touch (finger down) - creates fisheye effect
    pub fn add_touch(&mut self, x: f64, y: f64, touch_id: u64) {
        // Remove any existing effect for this touch
        self.effects.retain(|e| e.touch_id != touch_id);
        self.effects.push(TouchEffect::new_fisheye(x, y, touch_id));
    }

    /// Update touch position (finger move)
    pub fn update_touch(&mut self, x: f64, y: f64, touch_id: u64) {
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

    /// Clean up expired effects
    pub fn cleanup(&mut self) {
        self.effects.retain(|e| !e.is_expired());
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

    /// Get shader uniform data
    /// Returns arrays suitable for passing to GL uniforms
    pub fn get_shader_data(&self, screen_width: f64, screen_height: f64) -> TouchEffectShaderData {
        let mut data = TouchEffectShaderData::default();

        for (i, effect) in self.effects.iter().take(MAX_TOUCH_EFFECTS).enumerate() {
            let (x, y, radius, strength, type_flag) = effect.get_shader_params(screen_width, screen_height);
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
}

impl Default for TouchEffectShaderData {
    fn default() -> Self {
        Self {
            positions: [0.0; MAX_TOUCH_EFFECTS * 2],
            params: [0.0; MAX_TOUCH_EFFECTS * 4],
            count: 0,
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
