//! Gesture overlay animations
//!
//! Visual feedback for edge swipe gestures:
//! - Back indicator (left edge)
//! - Close indicator (top edge)
//! - App switcher preview (right edge)
//! - Home indicator (bottom edge)

use smithay::utils::{Logical, Size};
use super::primitives::{Rect, Color, colors, lerp, clamp};
use crate::input::Edge;

/// Overlay renderer for gesture feedback
pub struct GestureOverlay {
    screen_size: Size<i32, Logical>,
}

impl GestureOverlay {
    pub fn new(screen_size: Size<i32, Logical>) -> Self {
        Self { screen_size }
    }

    /// Get render rectangles for the current gesture state
    pub fn get_render_rects(&self, edge: Edge, progress: f64) -> Vec<(Rect, Color)> {
        match edge {
            Edge::Left => self.back_indicator(progress),
            Edge::Right => self.switcher_indicator(progress),
            Edge::Top => self.close_indicator(progress),
            Edge::Bottom => self.home_indicator(progress),
        }
    }

    /// Back gesture indicator (left edge swipe right)
    fn back_indicator(&self, progress: f64) -> Vec<(Rect, Color)> {
        let mut rects = Vec::new();
        let p = clamp(progress, 0.0, 1.0);

        // Gradient bar from left edge
        let bar_width = lerp(0.0, 100.0, p);
        let bar = Rect::new(0.0, 0.0, bar_width, self.screen_size.h as f64);
        let alpha = 0.15 * p as f32;
        rects.push((bar, [1.0, 1.0, 1.0, alpha]));

        // Circle indicator that follows gesture
        let circle_size = lerp(44.0, 60.0, p);
        let circle_x = lerp(-30.0, 30.0, p);
        let circle_y = (self.screen_size.h as f64 / 2.0) - (circle_size / 2.0);
        let circle = Rect::new(circle_x, circle_y, circle_size, circle_size);

        let circle_alpha = if progress > 0.6 { 0.25 } else { 0.15 };
        rects.push((circle, [1.0, 1.0, 1.0, circle_alpha as f32]));

        rects
    }

    /// App switcher indicator (right edge swipe left)
    fn switcher_indicator(&self, progress: f64) -> Vec<(Rect, Color)> {
        let mut rects = Vec::new();
        let p = clamp(progress, 0.0, 1.0);

        // Gradient bar from right edge
        let bar_width = lerp(0.0, 100.0, p);
        let bar_x = self.screen_size.w as f64 - bar_width;
        let bar = Rect::new(bar_x, 0.0, bar_width, self.screen_size.h as f64);
        let alpha = 0.2 * p as f32;
        rects.push((bar, [0.0, 0.0, 0.0, alpha]));

        rects
    }

    /// Close gesture indicator (top edge swipe down)
    fn close_indicator(&self, progress: f64) -> Vec<(Rect, Color)> {
        let mut rects = Vec::new();
        let p = clamp(progress, 0.0, 1.0);

        // Dark vignette from top
        let vignette_height = lerp(0.0, self.screen_size.h as f64 * 0.6, p);
        let vignette = Rect::new(0.0, 0.0, self.screen_size.w as f64, vignette_height);
        let alpha = 0.7 * p as f32;
        rects.push((vignette, [0.0, 0.0, 0.0, alpha]));

        // Red danger zone when past threshold
        if progress > 0.4 {
            let danger_alpha = ((progress - 0.4) * 2.0).min(1.0) * 0.4;
            let danger_height = self.screen_size.h as f64 * 0.15;
            let danger = Rect::new(0.0, 0.0, self.screen_size.w as f64, danger_height);
            rects.push((danger, [0.91, 0.27, 0.38, danger_alpha as f32]));
        }

        // Close circle indicator
        let circle_size = lerp(72.0, 120.0, p);
        let circle_x = (self.screen_size.w as f64 - circle_size) / 2.0;
        let circle_y = lerp(-120.0, self.screen_size.h as f64 * 0.3, p);
        let circle = Rect::new(circle_x, circle_y, circle_size, circle_size);

        let circle_color = if progress > 0.5 {
            colors::ACCENT
        } else {
            [0.18, 0.18, 0.18, 1.0]
        };
        rects.push((circle, circle_color));

        // Progress bar at top
        let bar_width = self.screen_size.w as f64 * (p * 2.0).min(1.0);
        let bar = Rect::new(0.0, 0.0, bar_width, 4.0);
        let bar_color = if progress > 0.5 { colors::ACCENT } else { colors::HOME_INDICATOR };
        rects.push((bar, bar_color));

        rects
    }

    /// Home gesture indicator (bottom edge swipe up)
    fn home_indicator(&self, progress: f64) -> Vec<(Rect, Color)> {
        let mut rects = Vec::new();
        let p = clamp(progress, 0.0, 1.0);

        // Subtle gradient from bottom
        let gradient_height = lerp(0.0, 200.0, p);
        let gradient_y = self.screen_size.h as f64 - gradient_height;
        let gradient = Rect::new(0.0, gradient_y, self.screen_size.w as f64, gradient_height);
        let alpha = 0.3 * p as f32;
        rects.push((gradient, [0.0, 0.0, 0.0, alpha]));

        // Home bar that grows
        let bar_width = lerp(134.0, 200.0, p);
        let bar_height = lerp(5.0, 8.0, p);
        let bar_x = (self.screen_size.w as f64 - bar_width) / 2.0;
        let bar_y = self.screen_size.h as f64 - 21.0 - lerp(0.0, 50.0, p);
        let bar = Rect::new(bar_x, bar_y, bar_width, bar_height);
        rects.push((bar, [1.0, 1.0, 1.0, 0.5 + 0.5 * p as f32]));

        rects
    }
}
