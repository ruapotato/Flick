//! Touch visual effects - Material Design style ripples
//!
//! Creates elegant touch feedback:
//! - Tap: Ripple that expands outward from touch point
//! - Swipe: Trail of ripples creating fluid motion
//! - Uses accent color (#e94560) for brand consistency

use std::time::Instant;

/// Accent color for ripples (RGB)
const RIPPLE_R: u8 = 233;  // #e9
const RIPPLE_G: u8 = 69;   // #45
const RIPPLE_B: u8 = 96;   // #60

/// A single ripple circle
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
        self.age() > 0.45 // Ripples last 0.45 seconds (faster than before)
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

    /// Update position - add ripples along the path for consistent density
    pub fn update_position(&mut self, x: f64, y: f64) {
        let dx = x - self.last_pos.0;
        let dy = y - self.last_pos.1;
        let dist = (dx * dx + dy * dy).sqrt();

        // Spacing between ripples (pixels) - larger for cleaner trails
        let circle_spacing = 20.0;

        if dist >= circle_spacing {
            // Calculate how many circles to add along the path
            let num_circles = (dist / circle_spacing) as i32;

            // Interpolate circles along the path
            for i in 1..=num_circles {
                let t = (i as f64 * circle_spacing) / dist;
                let cx = self.last_pos.0 + dx * t;
                let cy = self.last_pos.1 + dy * t;
                self.circles.push(TouchCircle::new(cx, cy));
            }

            // Update last_pos to the last circle position
            let t = (num_circles as f64 * circle_spacing) / dist;
            self.last_pos = (
                self.last_pos.0 + dx * t,
                self.last_pos.1 + dy * t,
            );
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

    /// Render a single ripple effect (Material Design style)
    fn render_circle(&self, pixels: &mut [u8], circle: &TouchCircle) {
        let age = circle.age();
        let duration = 0.45;
        if age > duration {
            return;
        }

        let cx = circle.x;
        let cy = circle.y;

        // Ripple expands with easing (fast start, slow end)
        let progress = age / duration;
        let eased = 1.0 - (1.0 - progress).powi(3); // Ease out cubic

        let max_radius = 80.0;  // Larger ripple
        let radius = max_radius * eased;

        // Ring thickness - starts thick, gets thinner
        let ring_thickness = 20.0 * (1.0 - progress * 0.5);

        // Fade out smoothly
        let fade = (1.0 - progress).powi(2);

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

                // Create ring effect - solid near edge, fading toward center
                let inner_radius = (radius - ring_thickness).max(0.0);

                if dist < radius {
                    let alpha_value;

                    if dist > inner_radius {
                        // Ring portion - full opacity with soft edge
                        let ring_pos = (dist - inner_radius) / ring_thickness;
                        // Soft edges on both inside and outside
                        let edge_softness = if ring_pos < 0.3 {
                            ring_pos / 0.3
                        } else if ring_pos > 0.7 {
                            (1.0 - ring_pos) / 0.3
                        } else {
                            1.0
                        };
                        alpha_value = edge_softness * fade * 0.6;
                    } else {
                        // Fill portion - subtle glow
                        let fill_fade = dist / inner_radius.max(1.0);
                        alpha_value = fill_fade * fade * 0.15;
                    }

                    let alpha = (alpha_value * 255.0).min(255.0) as u8;

                    if alpha > 0 {
                        let idx = ((y * self.width + x) * 4) as usize;

                        // Use accent color
                        let r = RIPPLE_R;
                        let g = RIPPLE_G;
                        let b = RIPPLE_B;

                        // Alpha blend (over)
                        let src_a = alpha as f32 / 255.0;
                        let dst_a = pixels[idx + 3] as f32 / 255.0;
                        let out_a = src_a + dst_a * (1.0 - src_a);

                        if out_a > 0.0 {
                            pixels[idx] = ((r as f32 * src_a + pixels[idx] as f32 * dst_a * (1.0 - src_a)) / out_a) as u8;
                            pixels[idx + 1] = ((g as f32 * src_a + pixels[idx + 1] as f32 * dst_a * (1.0 - src_a)) / out_a) as u8;
                            pixels[idx + 2] = ((b as f32 * src_a + pixels[idx + 2] as f32 * dst_a * (1.0 - src_a)) / out_a) as u8;
                            pixels[idx + 3] = (out_a * 255.0) as u8;
                        }
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
        effect.update_position(140.0, 100.0); // Move 40px - should add 2 circles (spacing is 20px)
        assert_eq!(effect.circles.len(), 3);
    }

    #[test]
    fn test_renderer() {
        let renderer = TouchEffectRenderer::new(100, 100);
        let effect = TouchEffect::new(50.0, 50.0, 1);
        let pixels = renderer.render(&[effect]);
        assert!(pixels.is_some());
    }
}
