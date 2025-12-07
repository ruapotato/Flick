//! App grid home screen
//!
//! Displays a grid of app launchers with touch support.

use smithay::utils::{Logical, Size};
use super::primitives::{Rect, Color, colors};
use super::text;
use super::AppInfo;

/// Layout configuration for app grid
pub struct AppGridLayout {
    /// Screen size
    screen_size: Size<i32, Logical>,
    /// Number of columns
    columns: usize,
    /// Cell size (width and height)
    cell_size: f64,
    /// Padding between cells
    padding: f64,
    /// Top offset (for status bar)
    top_offset: f64,
    /// Side margin
    side_margin: f64,
}

impl AppGridLayout {
    pub fn new(screen_size: Size<i32, Logical>) -> Self {
        let columns = 3;
        let side_margin = 16.0;
        let available_width = screen_size.w as f64 - (side_margin * 2.0);
        let cell_size = available_width / columns as f64;
        let padding = 8.0;
        let top_offset = 72.0; // Status bar + some padding

        Self {
            screen_size,
            columns,
            cell_size,
            padding,
            top_offset,
            side_margin,
        }
    }

    /// Get the rectangle for an app tile at the given index
    pub fn app_rect(&self, index: usize) -> Rect {
        let col = index % self.columns;
        let row = index / self.columns;

        let x = self.side_margin + (col as f64 * self.cell_size) + self.padding;
        let y = self.top_offset + (row as f64 * self.cell_size * 1.2) + self.padding;
        let size = self.cell_size - (self.padding * 2.0);

        Rect::new(x, y, size, size)
    }

    /// Get the rectangle for the app tile content (smaller, for visual padding)
    pub fn app_content_rect(&self, index: usize) -> Rect {
        let outer = self.app_rect(index);
        let inset = 8.0;
        Rect::new(
            outer.x + inset,
            outer.y + inset,
            outer.width - inset * 2.0,
            outer.height - inset * 2.0,
        )
    }
}

/// App grid state
pub struct AppGrid {
    /// Layout calculator
    pub layout: AppGridLayout,
    /// Y offset for slide animation (0 = fully visible, screen_height = hidden below)
    pub y_offset: f64,
    /// Scroll offset for scrolling through apps (0 = top, positive = scrolled down)
    pub scroll_offset: f64,
}

impl AppGrid {
    pub fn new(screen_size: Size<i32, Logical>) -> Self {
        Self {
            layout: AppGridLayout::new(screen_size),
            y_offset: 0.0,
            scroll_offset: 0.0,
        }
    }

    /// Update y offset based on gesture progress (for slide-up animation)
    /// progress: 0 = hidden, 1 = fully visible
    pub fn set_progress(&mut self, progress: f64, screen_height: f64) {
        self.y_offset = screen_height * (1.0 - progress);
    }

    /// Set scroll offset (for scrolling through apps)
    pub fn set_scroll(&mut self, offset: f64, num_apps: usize) {
        // Calculate max scroll based on number of apps
        let rows = (num_apps + self.layout.columns - 1) / self.layout.columns;
        let content_height = rows as f64 * self.layout.cell_size * 1.2 + self.layout.top_offset;
        let screen_height = self.layout.screen_size.h as f64;
        let max_scroll = (content_height - screen_height + 100.0).max(0.0);

        // Clamp scroll offset
        self.scroll_offset = offset.clamp(0.0, max_scroll);
    }

    /// Get list of rectangles to render for the app grid
    pub fn get_render_rects(&self, apps: &[AppInfo]) -> Vec<(Rect, Color)> {
        let mut rects = Vec::new();

        // Status bar (fixed at top)
        let status_bar = Rect::new(0.0, self.y_offset, self.layout.screen_size.w as f64, 48.0);
        rects.push((status_bar, colors::STATUS_BAR));

        // App tiles (scrollable)
        for (i, app) in apps.iter().enumerate() {
            let mut tile_rect = self.layout.app_content_rect(i);
            tile_rect.y += self.y_offset - self.scroll_offset;

            // Only render if visible on screen
            if tile_rect.y + tile_rect.height > 48.0 && tile_rect.y < self.layout.screen_size.h as f64 {
                rects.push((tile_rect.clone(), app.color));

                // Render app name below the tile
                let text_scale = 2.5; // Each "pixel" is 2.5 actual pixels
                let text_y = tile_rect.y + tile_rect.height + 8.0;
                let text_center_x = tile_rect.x + tile_rect.width / 2.0;

                // Use white text for visibility
                let text_color: Color = [1.0, 1.0, 1.0, 1.0];
                let text_rects = text::render_text_centered(&app.name, text_center_x, text_y, text_scale, text_color);
                rects.extend(text_rects);
            }
        }

        // Home indicator bar (fixed at bottom)
        let indicator_width = 134.0;
        let indicator_height = 5.0;
        let indicator_x = (self.layout.screen_size.w as f64 - indicator_width) / 2.0;
        let indicator_y = self.layout.screen_size.h as f64 - 21.0 + self.y_offset;
        let indicator = Rect::new(indicator_x, indicator_y, indicator_width, indicator_height);
        rects.push((indicator, colors::HOME_INDICATOR));

        rects
    }
}

/// Get the text/label for an app (first character for now)
pub fn app_initial(app: &AppInfo) -> char {
    app.name.chars().next().unwrap_or('?')
}
