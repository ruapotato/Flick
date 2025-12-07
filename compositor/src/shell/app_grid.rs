//! App grid home screen
//!
//! Displays a grid of app launchers with touch support.

use smithay::utils::{Logical, Size};
use super::primitives::{Rect, Color, colors};
use super::text;
use super::AppInfo;
use super::apps::CategoryInfo;

/// Layout configuration for app grid
pub struct AppGridLayout {
    /// Screen size
    pub screen_size: Size<i32, Logical>,
    /// Number of columns
    pub columns: usize,
    /// Cell size (width and height)
    pub cell_size: f64,
    /// Padding between cells
    pub padding: f64,
    /// Top offset (for status bar)
    pub top_offset: f64,
    /// Side margin
    pub side_margin: f64,
}

impl AppGridLayout {
    pub fn new(screen_size: Size<i32, Logical>) -> Self {
        let w = screen_size.w;

        // Responsive column count based on screen width
        // Phone portrait: 3 columns (< 600px)
        // Phone landscape / small tablet: 4 columns (600-900px)
        // Tablet / laptop: 5-6 columns (> 900px)
        let columns = if w < 600 {
            3
        } else if w < 900 {
            4
        } else if w < 1200 {
            5
        } else {
            6
        };

        // Responsive margins based on screen width
        let side_margin = if w < 600 { 16.0 } else { 24.0 };

        let available_width = screen_size.w as f64 - (side_margin * 2.0);
        let cell_size = available_width / columns as f64;

        // Responsive padding - smaller on phones
        let padding = if w < 600 { 8.0 } else { 10.0 };

        // Top offset for status bar
        let top_offset = 72.0;

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

    /// Get list of rectangles to render for the app grid (legacy)
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

    /// Get list of rectangles to render for the category grid (simple version)
    pub fn get_category_rects(&self, categories: &[CategoryInfo]) -> Vec<(Rect, Color)> {
        self.get_category_rects_ex(categories, None, None)
    }

    /// Get list of rectangles to render for the category grid
    /// wiggle_offsets: per-index (x, y) offset for wiggle animation
    /// dragging: (index being dragged, current drag position)
    pub fn get_category_rects_ex(
        &self,
        categories: &[CategoryInfo],
        wiggle_offsets: Option<&[(f64, f64)]>,
        dragging: Option<(usize, (f64, f64))>,
    ) -> Vec<(Rect, Color)> {
        let mut rects = Vec::new();

        // Status bar (fixed at top)
        let status_bar = Rect::new(0.0, self.y_offset, self.layout.screen_size.w as f64, 48.0);
        rects.push((status_bar, colors::STATUS_BAR));

        // Category tiles (scrollable)
        for (i, cat_info) in categories.iter().enumerate() {
            let mut tile_rect = self.layout.app_content_rect(i);
            tile_rect.y += self.y_offset - self.scroll_offset;

            // Apply wiggle offset if in wiggle mode
            if let Some(offsets) = wiggle_offsets {
                if let Some((wx, wy)) = offsets.get(i) {
                    tile_rect.x += wx;
                    tile_rect.y += wy;
                }
            }

            // If this tile is being dragged, render it at drag position instead
            let is_dragging = dragging.map(|(idx, _)| idx == i).unwrap_or(false);
            if is_dragging {
                if let Some((_, (dx, dy))) = dragging {
                    // Center the tile on the drag position
                    tile_rect.x = dx - tile_rect.width / 2.0;
                    tile_rect.y = dy - tile_rect.height / 2.0;
                }
            }

            // Only render if visible on screen
            if tile_rect.y + tile_rect.height > 48.0 && tile_rect.y < self.layout.screen_size.h as f64 {
                // Use the category's color (brighter if dragging)
                let mut color = cat_info.color;
                if is_dragging {
                    // Make dragged tile slightly brighter
                    color[0] = (color[0] * 1.2).min(1.0);
                    color[1] = (color[1] * 1.2).min(1.0);
                    color[2] = (color[2] * 1.2).min(1.0);
                }
                rects.push((tile_rect.clone(), color));

                // If there's no app available, show a dimmed overlay
                if cat_info.available_count == 0 {
                    let dimmed_color: Color = [0.0, 0.0, 0.0, 0.5];
                    rects.push((tile_rect.clone(), dimmed_color));
                }

                // Render first letter of category name on the tile (single char = fewer rects)
                let first_char = cat_info.name.chars().next().unwrap_or('?').to_string();
                let text_scale = 4.0; // Larger scale for single letter
                let char_width = 5.0 * text_scale;
                let char_height = 7.0 * text_scale;
                let text_x = tile_rect.x + (tile_rect.width - char_width) / 2.0;
                let text_y = tile_rect.y + (tile_rect.height - char_height) / 2.0;
                let text_color: Color = [1.0, 1.0, 1.0, 0.9];
                let text_rects = text::render_text(&first_char, text_x, text_y, text_scale, text_color);
                rects.extend(text_rects);
            }
        }

        // In wiggle mode, show a "Done" button
        if wiggle_offsets.is_some() {
            let btn_width = 100.0;
            let btn_height = 40.0;
            let btn_x = (self.layout.screen_size.w as f64 - btn_width) / 2.0;
            let btn_y = self.layout.screen_size.h as f64 - 80.0;
            let btn_rect = Rect::new(btn_x, btn_y, btn_width, btn_height);
            rects.push((btn_rect, [0.2, 0.6, 0.2, 1.0])); // Green button

            // "Done" text
            let text_rects = text::render_text_centered("Done", btn_x + btn_width / 2.0, btn_y + 12.0, 2.5, [1.0, 1.0, 1.0, 1.0]);
            rects.extend(text_rects);
        }

        // Home indicator bar (fixed at bottom)
        let indicator_width = 134.0;
        let indicator_height = 5.0;
        let indicator_x = (self.layout.screen_size.w as f64 - indicator_width) / 2.0;
        let indicator_y = self.layout.screen_size.h as f64 - 21.0 + self.y_offset;
        let indicator = Rect::new(indicator_x, indicator_y, indicator_width, indicator_height);
        rects.push((indicator, colors::HOME_INDICATOR));

        // CRITICAL: Reverse so background renders first (at back)
        // Smithay renders front-to-back, so first element is on top
        rects.reverse();

        rects
    }
}

/// Get the text/label for an app (first character for now)
pub fn app_initial(app: &AppInfo) -> char {
    app.name.chars().next().unwrap_or('?')
}

/// Render a long press menu for selecting alternative apps
pub fn render_long_press_menu(
    menu: &super::LongPressMenu,
    screen_size: Size<i32, Logical>,
) -> Vec<(Rect, Color)> {
    use super::MenuLevel;
    let mut rects = Vec::new();

    // Semi-transparent overlay
    let overlay = Rect::new(0.0, 0.0, screen_size.w as f64, screen_size.h as f64);
    rects.push((overlay, [0.0, 0.0, 0.0, 0.7]));

    // Responsive menu sizing
    let w = screen_size.w as f64;
    let menu_width = if w < 400.0 { w * 0.85 } else if w < 800.0 { 280.0 } else { 320.0 };
    let item_height = if screen_size.h < 600 { 50.0 } else { 60.0 };
    let header_height = if screen_size.h < 600 { 40.0 } else { 50.0 };

    // Calculate number of items based on menu level
    let num_items = match menu.level {
        MenuLevel::Main => 2, // "Move" and "Change Default"
        MenuLevel::SelectApp => menu.available_apps.len().min(4).max(1), // Max 4 visible, scrollable
    };
    let menu_height = header_height + (num_items as f64 * item_height);

    // Center the menu
    let menu_x = (screen_size.w as f64 - menu_width) / 2.0;
    let menu_y = (screen_size.h as f64 - menu_height) / 2.0;

    // Menu background
    let menu_bg = Rect::new(menu_x, menu_y, menu_width, menu_height);
    rects.push((menu_bg, [0.15, 0.15, 0.2, 1.0]));

    // Header with category name
    let header = Rect::new(menu_x, menu_y, menu_width, header_height);
    rects.push((header, [0.2, 0.2, 0.25, 1.0]));

    // Header text depends on level
    let header_text_y = menu_y + 18.0;
    let header_text_x = menu_x + menu_width / 2.0;
    let header_label = match menu.level {
        MenuLevel::Main => menu.category.display_name().to_string(),
        MenuLevel::SelectApp => format!("Select {} App", menu.category.display_name()),
    };
    let header_text = text::render_text_centered(
        &header_label,
        header_text_x,
        header_text_y,
        2.5,
        [1.0, 1.0, 1.0, 1.0],
    );
    rects.extend(header_text);

    match menu.level {
        MenuLevel::Main => {
            // Main menu: "Move" and "Change Default"
            let options = ["Move", "Change Default"];
            for (i, label) in options.iter().enumerate() {
                let item_y = menu_y + header_height + (i as f64 * item_height);
                let is_highlighted = menu.highlighted == Some(i);

                // Item background
                let item_bg = Rect::new(menu_x, item_y, menu_width, item_height);
                let item_color = if is_highlighted {
                    [0.3, 0.3, 0.5, 1.0]
                } else {
                    [0.18, 0.18, 0.22, 1.0]
                };
                rects.push((item_bg, item_color));

                // Divider line
                if i > 0 {
                    let divider = Rect::new(menu_x + 10.0, item_y, menu_width - 20.0, 1.0);
                    rects.push((divider, [0.3, 0.3, 0.35, 1.0]));
                }

                // Option text
                let text_y = item_y + 22.0;
                let option_text = text::render_text_centered(
                    label,
                    menu_x + menu_width / 2.0,
                    text_y,
                    2.5,
                    [1.0, 1.0, 1.0, 1.0],
                );
                rects.extend(option_text);
            }
        }
        MenuLevel::SelectApp => {
            // App selection submenu
            if menu.available_apps.is_empty() {
                let no_apps_y = menu_y + header_height + 20.0;
                let no_apps_text = text::render_text_centered(
                    "No apps found",
                    menu_x + menu_width / 2.0,
                    no_apps_y,
                    2.0,
                    [0.6, 0.6, 0.6, 1.0],
                );
                rects.extend(no_apps_text);
            } else {
                // Calculate visible items with scrolling
                let scroll_index = (menu.scroll_offset / item_height) as usize;
                let max_visible = 4;
                let visible_apps: Vec<_> = menu.available_apps.iter()
                    .skip(scroll_index)
                    .take(max_visible)
                    .enumerate()
                    .collect();

                for (display_i, app) in visible_apps {
                    let actual_index = scroll_index + display_i;
                    let item_y = menu_y + header_height + (display_i as f64 * item_height);
                    let is_highlighted = menu.highlighted == Some(actual_index);

                    // Item background
                    let item_bg = Rect::new(menu_x, item_y, menu_width, item_height);
                    let item_color = if is_highlighted {
                        [0.3, 0.3, 0.5, 1.0]
                    } else {
                        [0.18, 0.18, 0.22, 1.0]
                    };
                    rects.push((item_bg, item_color));

                    // Divider line
                    if display_i > 0 {
                        let divider = Rect::new(menu_x + 10.0, item_y, menu_width - 20.0, 1.0);
                        rects.push((divider, [0.3, 0.3, 0.35, 1.0]));
                    }

                    // App name
                    let text_y = item_y + 22.0;
                    let app_text = text::render_text_centered(
                        &app.name,
                        menu_x + menu_width / 2.0,
                        text_y,
                        2.5,
                        [1.0, 1.0, 1.0, 1.0],
                    );
                    rects.extend(app_text);
                }

                // Scroll indicators if there are more items
                if scroll_index > 0 {
                    // Up arrow indicator
                    let arrow_y = menu_y + header_height + 5.0;
                    let arrow = text::render_text_centered("^", menu_x + menu_width - 20.0, arrow_y, 2.0, [0.7, 0.7, 0.7, 1.0]);
                    rects.extend(arrow);
                }
                if scroll_index + max_visible < menu.available_apps.len() {
                    // Down arrow indicator
                    let arrow_y = menu_y + menu_height - 15.0;
                    let arrow = text::render_text_centered("v", menu_x + menu_width - 20.0, arrow_y, 2.0, [0.7, 0.7, 0.7, 1.0]);
                    rects.extend(arrow);
                }
            }
        }
    }

    // CRITICAL: Reverse so background renders first (at back)
    // Smithay renders front-to-back, so first element is on top
    rects.reverse();

    rects
}

/// Hit test for long press menu items - returns index if hit
pub fn hit_test_menu(
    menu: &super::LongPressMenu,
    screen_size: Size<i32, Logical>,
    pos: (f64, f64),
) -> Option<usize> {
    use super::MenuLevel;

    // Use same responsive values as render function
    let w = screen_size.w as f64;
    let menu_width = if w < 400.0 { w * 0.85 } else if w < 800.0 { 280.0 } else { 320.0 };
    let item_height = if screen_size.h < 600 { 50.0 } else { 60.0 };
    let header_height = if screen_size.h < 600 { 40.0 } else { 50.0 };

    // Calculate number of items based on menu level
    let num_items = match menu.level {
        MenuLevel::Main => 2,
        MenuLevel::SelectApp => menu.available_apps.len().min(4).max(1),
    };
    let menu_height = header_height + (num_items as f64 * item_height);

    let menu_x = (screen_size.w as f64 - menu_width) / 2.0;
    let menu_y = (screen_size.h as f64 - menu_height) / 2.0;

    let (px, py) = pos;

    // Check if within menu bounds
    if px < menu_x || px > menu_x + menu_width {
        return None;
    }

    // Check if within items area (below header)
    let items_start_y = menu_y + header_height;
    if py < items_start_y || py > menu_y + menu_height {
        return None;
    }

    // Calculate which item was hit
    let relative_y = py - items_start_y;
    let display_index = (relative_y / item_height) as usize;

    match menu.level {
        MenuLevel::Main => {
            // Main menu has 2 items
            if display_index < 2 {
                Some(display_index)
            } else {
                None
            }
        }
        MenuLevel::SelectApp => {
            // Convert display index to actual index accounting for scroll
            let max_visible = 4;
            let scroll_index = (menu.scroll_offset / item_height) as usize;
            let actual_index = scroll_index + display_index;
            if display_index < max_visible && actual_index < menu.available_apps.len() {
                Some(actual_index)
            } else {
                None
            }
        }
    }
}
