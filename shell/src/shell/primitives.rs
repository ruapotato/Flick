//! Basic rendering primitives for shell UI
//!
//! Provides data structures for shell UI rendering. The actual rendering
//! is done in the backend using Smithay's GLES renderer.

use smithay::utils::{Physical, Point, Rectangle, Size};

/// A simple rectangle for rendering
#[derive(Debug, Clone, Copy)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

impl Rect {
    pub fn new(x: f64, y: f64, width: f64, height: f64) -> Self {
        Self { x, y, width, height }
    }

    pub fn to_physical(&self, scale: f64) -> Rectangle<i32, Physical> {
        Rectangle::new(
            Point::from(((self.x * scale) as i32, (self.y * scale) as i32)),
            Size::from(((self.width * scale) as i32, (self.height * scale) as i32)),
        )
    }

    /// Check if a point is inside this rectangle
    pub fn contains(&self, x: f64, y: f64) -> bool {
        x >= self.x && x < self.x + self.width &&
        y >= self.y && y < self.y + self.height
    }
}

/// Color in RGBA format (0.0 - 1.0)
pub type Color = [f32; 4];

/// Colors for the shell UI
pub mod colors {
    use super::Color;

    pub const BACKGROUND: Color = [0.10, 0.10, 0.18, 1.0];  // Dark blue-gray
    pub const CARD: Color = [0.10, 0.10, 0.18, 1.0];        // Card background
    pub const CARD_HEADER: Color = [0.12, 0.23, 0.37, 1.0]; // Card header gradient top
    pub const TEXT: Color = [1.0, 1.0, 1.0, 1.0];           // White text
    pub const ACCENT: Color = [0.91, 0.27, 0.38, 1.0];      // Red accent
    pub const OVERLAY: Color = [0.0, 0.0, 0.0, 0.7];        // Semi-transparent black
    pub const STATUS_BAR: Color = [0.09, 0.13, 0.24, 1.0];  // Dark blue
    pub const HOME_INDICATOR: Color = [0.29, 0.29, 0.42, 1.0]; // Subtle gray
}

/// Simple animated value for smooth transitions
#[derive(Debug, Clone)]
pub struct AnimatedValue {
    current: f64,
    target: f64,
    velocity: f64,
}

impl AnimatedValue {
    pub fn new(value: f64) -> Self {
        Self {
            current: value,
            target: value,
            velocity: 0.0,
        }
    }

    pub fn set_target(&mut self, target: f64) {
        self.target = target;
    }

    pub fn set_immediate(&mut self, value: f64) {
        self.current = value;
        self.target = value;
        self.velocity = 0.0;
    }

    pub fn update(&mut self, dt: f64) {
        // Simple spring animation
        let spring = 300.0;
        let damping = 20.0;

        let delta = self.target - self.current;
        let accel = spring * delta - damping * self.velocity;

        self.velocity += accel * dt;
        self.current += self.velocity * dt;

        // Snap if close enough
        if (self.current - self.target).abs() < 0.001 && self.velocity.abs() < 0.001 {
            self.current = self.target;
            self.velocity = 0.0;
        }
    }

    pub fn get(&self) -> f64 {
        self.current
    }

    pub fn is_animating(&self) -> bool {
        (self.current - self.target).abs() > 0.001 || self.velocity.abs() > 0.001
    }
}

/// Easing functions for animations
pub mod easing {
    /// Ease out cubic - starts fast, slows down
    pub fn ease_out_cubic(t: f64) -> f64 {
        1.0 - (1.0 - t).powi(3)
    }

    /// Ease in out cubic - smooth start and end
    pub fn ease_in_out_cubic(t: f64) -> f64 {
        if t < 0.5 {
            4.0 * t * t * t
        } else {
            1.0 - (-2.0 * t + 2.0).powi(3) / 2.0
        }
    }

    /// Ease out back - slight overshoot
    pub fn ease_out_back(t: f64) -> f64 {
        let c1 = 1.70158;
        let c3 = c1 + 1.0;
        1.0 + c3 * (t - 1.0).powi(3) + c1 * (t - 1.0).powi(2)
    }
}

/// Linear interpolation
pub fn lerp(a: f64, b: f64, t: f64) -> f64 {
    a + (b - a) * t
}

/// Clamp a value between min and max
pub fn clamp(value: f64, min: f64, max: f64) -> f64 {
    value.max(min).min(max)
}
