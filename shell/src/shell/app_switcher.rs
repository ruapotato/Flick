//! App switcher - Android-style vertical card stack
//!
//! Shows open windows as overlapping cards that can be scrolled through.

use smithay::utils::{Logical, Size};
use super::primitives::{Rect, Color};

/// Window info for the app switcher
#[derive(Debug, Clone)]
pub struct WindowCard {
    pub id: u32,
    pub title: String,
    pub app_class: String,
    pub color: Color, // Derived from app class
}

impl WindowCard {
    pub fn new(id: u32, title: String, app_class: String) -> Self {
        // Generate a color based on app class hash
        let color = class_to_color(&app_class);
        Self { id, title, app_class, color }
    }
}

/// Generate a consistent color from app class name
fn class_to_color(class: &str) -> Color {
    // Simple hash to color
    let hash: u32 = class.bytes().fold(0, |acc, b| acc.wrapping_add(b as u32).wrapping_mul(31));

    // Generate hue from hash (0-360)
    let hue = (hash % 360) as f32;

    // Convert HSL to RGB (fixed saturation and lightness for nice colors)
    let s = 0.6_f32;
    let l = 0.4_f32;

    let c = (1.0 - (2.0 * l - 1.0).abs()) * s;
    let x = c * (1.0 - ((hue / 60.0) % 2.0 - 1.0).abs());
    let m = l - c / 2.0;

    let (r, g, b) = match (hue / 60.0) as i32 {
        0 => (c, x, 0.0),
        1 => (x, c, 0.0),
        2 => (0.0, c, x),
        3 => (0.0, x, c),
        4 => (x, 0.0, c),
        _ => (c, 0.0, x),
    };

    [r + m, g + m, b + m, 1.0]
}

/// App switcher layout
pub struct AppSwitcherLayout {
    screen_size: Size<i32, Logical>,
    /// Card height as fraction of screen
    card_height_ratio: f64,
    /// Vertical spacing between cards
    card_spacing: f64,
    /// Side margin
    side_margin: f64,
    /// Top offset
    top_offset: f64,
}

impl AppSwitcherLayout {
    pub fn new(screen_size: Size<i32, Logical>) -> Self {
        Self {
            screen_size,
            card_height_ratio: 0.55, // 55% of screen height
            card_spacing: 180.0,      // Overlap amount
            side_margin: 16.0,
            top_offset: 80.0,         // Below header
        }
    }

    /// Get the card rectangle for a window at the given index
    pub fn card_rect(&self, index: usize, scroll_offset: f64) -> Rect {
        let card_width = self.screen_size.w as f64 - (self.side_margin * 2.0);
        let card_height = self.screen_size.h as f64 * self.card_height_ratio;

        let y = self.top_offset + (index as f64 * self.card_spacing) - scroll_offset;

        Rect::new(self.side_margin, y, card_width, card_height)
    }

    /// Get the header bar area for the card
    pub fn card_header_rect(&self, card: &Rect) -> Rect {
        Rect::new(card.x, card.y, card.width, 60.0)
    }

    /// Get the preview area (main content area of card)
    pub fn card_preview_rect(&self, card: &Rect) -> Rect {
        Rect::new(card.x, card.y, card.width, card.height - 60.0)
    }
}

/// App switcher state
pub struct AppSwitcher {
    pub layout: AppSwitcherLayout,
    /// Scroll offset for panning through cards
    pub scroll_offset: f64,
    /// X offset for slide-in animation (screen_width = hidden, 0 = visible)
    pub x_offset: f64,
}

impl AppSwitcher {
    pub fn new(screen_size: Size<i32, Logical>) -> Self {
        Self {
            layout: AppSwitcherLayout::new(screen_size),
            scroll_offset: 0.0,
            x_offset: screen_size.w as f64, // Start hidden
        }
    }

    /// Update x offset based on gesture progress (for slide-in from right)
    /// progress: 0 = hidden (right), 1 = fully visible
    pub fn set_progress(&mut self, progress: f64, screen_width: f64) {
        self.x_offset = screen_width * (1.0 - progress);
    }

    /// Get rectangles to render for the app switcher
    pub fn get_render_rects(&self, windows: &[WindowCard]) -> Vec<(Rect, Color)> {
        let mut rects = Vec::new();

        // Background - dark but visible
        let bg = Rect::new(
            self.x_offset,
            0.0,
            self.layout.screen_size.w as f64,
            self.layout.screen_size.h as f64,
        );
        rects.push((bg, [0.08, 0.08, 0.12, 1.0]));

        // Header bar
        let header = Rect::new(
            self.x_offset,
            0.0,
            self.layout.screen_size.w as f64,
            60.0,
        );
        rects.push((header, [0.15, 0.15, 0.20, 1.0]));

        // Window cards (render back to front, so last card is on top)
        for (i, window) in windows.iter().enumerate().rev() {
            let mut card = self.layout.card_rect(i, self.scroll_offset);
            card.x += self.x_offset;

            // Skip if card is fully off screen
            if card.y + card.height < 0.0 || card.y > self.layout.screen_size.h as f64 {
                continue;
            }

            // Card border/shadow (slightly larger, darker)
            let shadow = Rect::new(card.x - 2.0, card.y - 2.0, card.width + 4.0, card.height + 4.0);
            rects.push((shadow, [0.0, 0.0, 0.0, 0.5]));

            // Card background - light gray
            rects.push((card, [0.25, 0.25, 0.30, 1.0]));

            // Preview area with app color (brighter)
            let preview = Rect::new(card.x + 8.0, card.y + 8.0, card.width - 16.0, card.height - 76.0);
            // Make the color brighter
            let bright_color = [
                (window.color[0] * 1.5).min(1.0),
                (window.color[1] * 1.5).min(1.0),
                (window.color[2] * 1.5).min(1.0),
                1.0,
            ];
            rects.push((preview, bright_color));

            // Title bar at bottom - darker
            let title_bar = Rect::new(
                card.x,
                card.y + card.height - 60.0,
                card.width,
                60.0,
            );
            rects.push((title_bar, [0.18, 0.18, 0.22, 1.0]));
        }

        rects
    }

    /// Hit test for tapping on a card - returns window ID if hit
    pub fn hit_test(&self, pos: (f64, f64), windows: &[WindowCard]) -> Option<u32> {
        let (px, py) = pos;

        // Check cards from front to back (reverse order)
        for (i, window) in windows.iter().enumerate() {
            let card = self.layout.card_rect(i, self.scroll_offset);
            let adjusted_x = card.x + self.x_offset;

            if px >= adjusted_x && px < adjusted_x + card.width &&
               py >= card.y && py < card.y + card.height {
                return Some(window.id);
            }
        }

        None
    }
}
