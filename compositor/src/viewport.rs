//! Virtual viewport system for desktop apps
//!
//! This allows desktop apps (designed for 1920x1080) to run on mobile screens
//! with pinch-to-zoom and pan gestures.

use smithay::utils::{Logical, Point, Rectangle, Size};

/// A virtual viewport that can be zoomed and panned
#[derive(Debug, Clone)]
pub struct Viewport {
    pub id: u32,
    /// The virtual size (e.g., 1920x1080 for desktop apps)
    pub virtual_size: Size<i32, Logical>,
    /// Current zoom level (1.0 = fit to screen, >1 = zoomed in)
    pub zoom: f64,
    /// Pan offset in virtual coordinates
    pub pan: Point<f64, Logical>,
    /// Minimum zoom (fit entire viewport on screen)
    pub min_zoom: f64,
    /// Maximum zoom (1:1 pixel mapping or higher)
    pub max_zoom: f64,
}

impl Viewport {
    pub fn new(id: u32, virtual_size: Size<i32, Logical>) -> Self {
        Self {
            id,
            virtual_size,
            zoom: 1.0,
            pan: Point::from((0.0, 0.0)),
            min_zoom: 0.3,  // Can zoom out to 30%
            max_zoom: 3.0,  // Can zoom in to 300%
        }
    }

    /// Calculate the zoom level needed to fit the viewport on screen
    pub fn fit_zoom(&self, screen_size: Size<i32, Logical>) -> f64 {
        let scale_x = screen_size.w as f64 / self.virtual_size.w as f64;
        let scale_y = screen_size.h as f64 / self.virtual_size.h as f64;
        scale_x.min(scale_y)
    }

    /// Reset to fit-to-screen view
    pub fn reset(&mut self, screen_size: Size<i32, Logical>) {
        self.zoom = self.fit_zoom(screen_size);
        self.pan = Point::from((0.0, 0.0));
    }

    /// Apply a zoom delta centered on a point
    pub fn zoom_at(&mut self, delta: f64, center: Point<f64, Logical>, screen_size: Size<i32, Logical>) {
        let old_zoom = self.zoom;
        self.zoom = (self.zoom * delta).clamp(self.min_zoom, self.max_zoom);

        if (self.zoom - old_zoom).abs() > 0.001 {
            // Adjust pan to keep the center point stable
            let zoom_ratio = self.zoom / old_zoom;

            // Convert screen center to virtual coordinates before zoom
            let virtual_center = self.screen_to_virtual(center, screen_size);

            // After zoom, adjust pan so the same virtual point is under the finger
            self.pan.x = virtual_center.x - (center.x / self.zoom);
            self.pan.y = virtual_center.y - (center.y / self.zoom);
        }

        self.clamp_pan(screen_size);
    }

    /// Pan by a delta in screen coordinates
    pub fn pan_by(&mut self, delta: Point<f64, Logical>, screen_size: Size<i32, Logical>) {
        // Convert screen delta to virtual delta
        self.pan.x -= delta.x / self.zoom;
        self.pan.y -= delta.y / self.zoom;
        self.clamp_pan(screen_size);
    }

    /// Clamp pan to keep viewport in bounds
    fn clamp_pan(&mut self, screen_size: Size<i32, Logical>) {
        let visible_w = screen_size.w as f64 / self.zoom;
        let visible_h = screen_size.h as f64 / self.zoom;

        // Allow panning but keep at least some content visible
        let max_pan_x = (self.virtual_size.w as f64 - visible_w * 0.1).max(0.0);
        let max_pan_y = (self.virtual_size.h as f64 - visible_h * 0.1).max(0.0);
        let min_pan_x = -(visible_w * 0.9).min(0.0);
        let min_pan_y = -(visible_h * 0.9).min(0.0);

        self.pan.x = self.pan.x.clamp(min_pan_x, max_pan_x);
        self.pan.y = self.pan.y.clamp(min_pan_y, max_pan_y);
    }

    /// Convert screen coordinates to virtual coordinates
    pub fn screen_to_virtual(&self, screen_pos: Point<f64, Logical>, _screen_size: Size<i32, Logical>) -> Point<f64, Logical> {
        Point::from((
            screen_pos.x / self.zoom + self.pan.x,
            screen_pos.y / self.zoom + self.pan.y,
        ))
    }

    /// Convert virtual coordinates to screen coordinates
    pub fn virtual_to_screen(&self, virtual_pos: Point<f64, Logical>, _screen_size: Size<i32, Logical>) -> Point<f64, Logical> {
        Point::from((
            (virtual_pos.x - self.pan.x) * self.zoom,
            (virtual_pos.y - self.pan.y) * self.zoom,
        ))
    }

    /// Get the transformation matrix for rendering
    pub fn get_transform(&self) -> ViewportTransform {
        ViewportTransform {
            scale: self.zoom,
            offset_x: -self.pan.x * self.zoom,
            offset_y: -self.pan.y * self.zoom,
        }
    }

    /// Get the visible rectangle in virtual coordinates
    pub fn visible_rect(&self, screen_size: Size<i32, Logical>) -> Rectangle<f64, Logical> {
        Rectangle::new(
            self.pan,
            Size::from((
                screen_size.w as f64 / self.zoom,
                screen_size.h as f64 / self.zoom,
            )),
        )
    }
}

/// Transform to apply when rendering viewport contents
#[derive(Debug, Clone, Copy)]
pub struct ViewportTransform {
    pub scale: f64,
    pub offset_x: f64,
    pub offset_y: f64,
}

impl ViewportTransform {
    /// Apply transform to a point
    pub fn apply(&self, p: Point<f64, Logical>) -> Point<f64, Logical> {
        Point::from((
            p.x * self.scale + self.offset_x,
            p.y * self.scale + self.offset_y,
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_viewport_fit() {
        let viewport = Viewport::new(0, Size::from((1920, 1080)));
        let screen = Size::from((360, 720));

        let fit = viewport.fit_zoom(screen);
        // 360/1920 = 0.1875, 720/1080 = 0.667 -> min = 0.1875
        assert!((fit - 0.1875).abs() < 0.001);
    }

    #[test]
    fn test_coordinate_conversion() {
        let mut viewport = Viewport::new(0, Size::from((1920, 1080)));
        viewport.zoom = 0.5;
        viewport.pan = Point::from((100.0, 50.0));

        let screen = Size::from((360, 720));
        let screen_point = Point::from((180.0, 360.0));

        let virtual_point = viewport.screen_to_virtual(screen_point, screen);
        let back = viewport.virtual_to_screen(virtual_point, screen);

        assert!((back.x - screen_point.x).abs() < 0.001);
        assert!((back.y - screen_point.y).abs() < 0.001);
    }
}
