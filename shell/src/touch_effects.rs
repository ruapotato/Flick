//! Touch visual effects - simple fading circles that merge on swipe
//!
//! Creates elegant touch feedback:
//! - Tap: Circle that fades outward
//! - Swipe: Trail of merging circles creating fluid motion

use std::time::Instant;

/// A single touch circle
#[derive(Clone, Debug)]
pub struct TouchCircle {
    pub x: f64,
    pub y: f64,
    pub start_time: Instant,
}

impl TouchCircle {
    pub fn new(x: f64, y: f64) -> Self {
        Self {
            x,
            y,
            start_time: Instant::now(),
        }
    }

    /// Get age in seconds
    pub fn age(&self) -> f64 {
        self.start_time.elapsed().as_secs_f64()
    }

    /// Check if expired (fully faded)
    pub fn is_expired(&self) -> bool {
        self.age() > 0.6 // Circles last 0.6 seconds
    }
}

/// Touch effect state tracking active touches
#[derive(Clone, Debug)]
pub struct TouchEffect {
    pub touch_id: u64,
    pub circles: Vec<TouchCircle>,
    pub last_pos: (f64, f64),
}

impl TouchEffect {
    pub fn new(x: f64, y: f64, touch_id: u64) -> Self {
        Self {
            touch_id,
            circles: vec![TouchCircle::new(x, y)],
            last_pos: (x, y),
        }
    }

    /// Update position - add new circle if moved enough
    pub fn update_position(&mut self, x: f64, y: f64) {
        let dx = x - self.last_pos.0;
        let dy = y - self.last_pos.1;
        let dist = (dx * dx + dy * dy).sqrt();

        // Add new circle every 15 pixels of movement
        if dist > 15.0 {
            self.circles.push(TouchCircle::new(x, y));
            self.last_pos = (x, y);
        }
    }

    /// Clean up expired circles
    pub fn cleanup(&mut self) {
        self.circles.retain(|c| !c.is_expired());
    }

    /// Check if all circles are expired
    pub fn is_expired(&self) -> bool {
        self.circles.is_empty()
    }
}

/// Render touch effects to an RGBA pixel buffer
pub struct TouchEffectRenderer {
    width: u32,
    height: u32,
}

impl TouchEffectRenderer {
    pub fn new(width: u32, height: u32) -> Self {
        Self { width, height }
    }

    /// Render all effects to an RGBA buffer
    /// Returns None if there are no visible effects
    pub fn render(&self, effects: &[TouchEffect]) -> Option<Vec<u8>> {
        // Collect all circles from all effects
        let all_circles: Vec<&TouchCircle> = effects
            .iter()
            .flat_map(|e| e.circles.iter())
            .collect();

        if all_circles.is_empty() {
            return None;
        }

        let size = (self.width * self.height * 4) as usize;
        let mut pixels = vec![0u8; size];

        // Render each circle
        for circle in &all_circles {
            self.render_circle(&mut pixels, circle);
        }

        // Check if we actually drew anything
        let has_content = pixels.iter().skip(3).step_by(4).any(|&a| a > 0);
        if has_content {
            Some(pixels)
        } else {
            None
        }
    }

    /// Render a single filled fading circle
    fn render_circle(&self, pixels: &mut [u8], circle: &TouchCircle) {
        let age = circle.age();
        if age > 0.6 {
            return;
        }

        let cx = circle.x;
        let cy = circle.y;

        // Circle expands over time
        let max_radius = 50.0;
        let radius = max_radius * (age / 0.6);

        // Fade out as it expands
        let fade = 1.0 - (age / 0.6);

        // Calculate bounding box
        let x_min = ((cx - radius) as i32).max(0) as u32;
        let x_max = ((cx + radius) as i32).min(self.width as i32 - 1) as u32;
        let y_min = ((cy - radius) as i32).max(0) as u32;
        let y_max = ((cy + radius) as i32).min(self.height as i32 - 1) as u32;

        for y in y_min..=y_max {
            for x in x_min..=x_max {
                let dx = x as f64 - cx;
                let dy = y as f64 - cy;
                let dist = (dx * dx + dy * dy).sqrt();

                if dist < radius {
                    // Soft edge at the boundary
                    let edge = 1.0 - (dist / radius);
                    let alpha = (edge * fade * 180.0) as u8;

                    if alpha > 0 {
                        let idx = ((y * self.width + x) * 4) as usize;

                        // Soft cyan/white color
                        let r = 200u8;
                        let g = 230u8;
                        let b = 255u8;

                        // Additive blend for nice merging effect
                        pixels[idx] = pixels[idx].saturating_add((r as u16 * alpha as u16 / 255) as u8);
                        pixels[idx + 1] = pixels[idx + 1].saturating_add((g as u16 * alpha as u16 / 255) as u8);
                        pixels[idx + 2] = pixels[idx + 2].saturating_add((b as u16 * alpha as u16 / 255) as u8);
                        pixels[idx + 3] = pixels[idx + 3].saturating_add(alpha);
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_circle_creation() {
        let circle = TouchCircle::new(100.0, 200.0);
        assert!(circle.age() < 0.1);
    }

    #[test]
    fn test_effect_update() {
        let mut effect = TouchEffect::new(100.0, 100.0, 1);
        effect.update_position(120.0, 100.0); // Move 20px - should add circle
        assert_eq!(effect.circles.len(), 2);
    }

    #[test]
    fn test_renderer() {
        let renderer = TouchEffectRenderer::new(100, 100);
        let effect = TouchEffect::new(50.0, 50.0, 1);
        let pixels = renderer.render(&[effect]);
        assert!(pixels.is_some());
    }
}
