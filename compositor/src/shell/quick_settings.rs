//! Quick Settings / Notifications panel
//!
//! Slides in from the left edge, Android-style.
//! Shows quick toggles and notifications.

use smithay::utils::{Logical, Size};
use super::primitives::{Rect, Color, colors};
use super::text;

/// Quick toggle button definition
#[derive(Debug, Clone)]
pub struct QuickToggle {
    pub name: String,
    pub icon: char,
    pub enabled: bool,
    pub color_on: Color,
    pub color_off: Color,
}

impl QuickToggle {
    pub fn new(name: &str, icon: char, enabled: bool) -> Self {
        Self {
            name: name.to_string(),
            icon,
            enabled,
            color_on: [0.2, 0.6, 0.9, 1.0],  // Blue when on
            color_off: [0.3, 0.3, 0.3, 1.0], // Gray when off
        }
    }

    pub fn current_color(&self) -> Color {
        if self.enabled {
            self.color_on
        } else {
            self.color_off
        }
    }
}

/// Default quick toggles
pub fn default_toggles() -> Vec<QuickToggle> {
    vec![
        QuickToggle::new("WiFi", 'W', true),
        QuickToggle::new("BT", 'B', false),
        QuickToggle::new("DND", 'D', false),
        QuickToggle::new("Flash", 'F', false),
        QuickToggle::new("Auto", 'A', true),
        QuickToggle::new("Dark", 'N', false),
    ]
}

/// Notification item
#[derive(Debug, Clone)]
pub struct Notification {
    pub app_name: String,
    pub title: String,
    pub body: String,
    pub color: Color,
    pub timestamp: String,
}

impl Notification {
    pub fn new(app_name: &str, title: &str, body: &str, color: Color) -> Self {
        Self {
            app_name: app_name.to_string(),
            title: title.to_string(),
            body: body.to_string(),
            color,
            timestamp: "now".to_string(),
        }
    }
}

/// Sample notifications for demo
pub fn sample_notifications() -> Vec<Notification> {
    vec![
        Notification::new(
            "System",
            "Welcome to Flick",
            "Swipe gestures enabled",
            [0.2, 0.6, 0.3, 1.0], // Green
        ),
        Notification::new(
            "Battery",
            "Battery at 85%",
            "Charging",
            [0.8, 0.6, 0.2, 1.0], // Orange
        ),
    ]
}

/// Quick settings panel layout
pub struct QuickSettingsPanel {
    /// Screen size
    pub screen_size: Size<i32, Logical>,
    /// X offset for slide animation (0 = fully visible, -screen_width = hidden left)
    pub x_offset: f64,
    /// Quick toggles
    pub toggles: Vec<QuickToggle>,
    /// Notifications
    pub notifications: Vec<Notification>,
}

impl QuickSettingsPanel {
    pub fn new(screen_size: Size<i32, Logical>) -> Self {
        Self {
            screen_size,
            x_offset: 0.0,
            toggles: default_toggles(),
            notifications: sample_notifications(),
        }
    }

    /// Update x offset based on gesture progress (for slide-in animation)
    /// progress: 0 = hidden, 1 = fully visible
    pub fn set_progress(&mut self, progress: f64) {
        let screen_width = self.screen_size.w as f64;
        self.x_offset = -screen_width * (1.0 - progress);
    }

    /// Get list of rectangles to render
    pub fn get_render_rects(&self) -> Vec<(Rect, Color)> {
        let mut rects = Vec::new();
        let screen_w = self.screen_size.w as f64;
        let screen_h = self.screen_size.h as f64;

        // Semi-transparent background overlay
        let bg = Rect::new(self.x_offset, 0.0, screen_w, screen_h);
        rects.push((bg, [0.1, 0.1, 0.15, 0.95]));

        // Header bar
        let header = Rect::new(self.x_offset, 0.0, screen_w, 60.0);
        rects.push((header, [0.15, 0.15, 0.2, 1.0]));

        // Title "Quick Settings"
        let title_rects = text::render_text("QUICK SETTINGS", self.x_offset + 20.0, 20.0, 3.0, [1.0, 1.0, 1.0, 1.0]);
        rects.extend(title_rects);

        // Quick toggles grid (2 rows x 3 columns)
        let toggle_size = 100.0;
        let toggle_spacing = 20.0;
        let toggles_start_x = self.x_offset + 30.0;
        let toggles_start_y = 80.0;

        for (i, toggle) in self.toggles.iter().enumerate() {
            let col = i % 3;
            let row = i / 3;
            let x = toggles_start_x + col as f64 * (toggle_size + toggle_spacing);
            let y = toggles_start_y + row as f64 * (toggle_size + toggle_spacing + 20.0);

            // Toggle background
            let toggle_rect = Rect::new(x, y, toggle_size, toggle_size);
            rects.push((toggle_rect, toggle.current_color()));

            // Toggle icon (single character centered)
            let icon_str = toggle.icon.to_string();
            let icon_rects = text::render_text_centered(
                &icon_str,
                x + toggle_size / 2.0,
                y + 25.0,
                5.0,
                [1.0, 1.0, 1.0, 1.0],
            );
            rects.extend(icon_rects);

            // Toggle name below
            let name_rects = text::render_text_centered(
                &toggle.name,
                x + toggle_size / 2.0,
                y + toggle_size + 5.0,
                2.0,
                [0.8, 0.8, 0.8, 1.0],
            );
            rects.extend(name_rects);
        }

        // Notifications section
        let notif_start_y = toggles_start_y + 2.0 * (toggle_size + toggle_spacing + 20.0) + 40.0;

        // "Notifications" header
        let notif_header_rects = text::render_text(
            "NOTIFICATIONS",
            self.x_offset + 20.0,
            notif_start_y,
            2.5,
            [0.7, 0.7, 0.7, 1.0],
        );
        rects.extend(notif_header_rects);

        // Notification cards
        let card_height = 80.0;
        let card_spacing = 10.0;
        let card_width = screen_w - 40.0;

        for (i, notif) in self.notifications.iter().enumerate() {
            let y = notif_start_y + 30.0 + i as f64 * (card_height + card_spacing);

            // Card background
            let card = Rect::new(self.x_offset + 20.0, y, card_width, card_height);
            rects.push((card, [0.2, 0.2, 0.25, 1.0]));

            // App indicator line on left
            let indicator = Rect::new(self.x_offset + 20.0, y, 4.0, card_height);
            rects.push((indicator, notif.color));

            // App name
            let app_rects = text::render_text(
                &notif.app_name.to_uppercase(),
                self.x_offset + 35.0,
                y + 10.0,
                2.0,
                [0.6, 0.6, 0.6, 1.0],
            );
            rects.extend(app_rects);

            // Title
            let title_rects = text::render_text(
                &notif.title,
                self.x_offset + 35.0,
                y + 30.0,
                2.5,
                [1.0, 1.0, 1.0, 1.0],
            );
            rects.extend(title_rects);

            // Body
            let body_rects = text::render_text(
                &notif.body,
                self.x_offset + 35.0,
                y + 55.0,
                2.0,
                [0.7, 0.7, 0.7, 1.0],
            );
            rects.extend(body_rects);
        }

        // "No more notifications" if empty
        if self.notifications.is_empty() {
            let empty_rects = text::render_text_centered(
                "No notifications",
                self.x_offset + screen_w / 2.0,
                notif_start_y + 60.0,
                2.5,
                [0.5, 0.5, 0.5, 1.0],
            );
            rects.extend(empty_rects);
        }

        // Home indicator bar (fixed at bottom)
        let indicator_width = 134.0;
        let indicator_height = 5.0;
        let indicator_x = self.x_offset + (screen_w - indicator_width) / 2.0;
        let indicator_y = screen_h - 21.0;
        let indicator = Rect::new(indicator_x, indicator_y, indicator_width, indicator_height);
        rects.push((indicator, colors::HOME_INDICATOR));

        rects
    }

    /// Hit test for toggle buttons - returns toggle index if hit
    pub fn hit_test_toggle(&self, x: f64, y: f64) -> Option<usize> {
        let toggle_size = 100.0;
        let toggle_spacing = 20.0;
        let toggles_start_x = self.x_offset + 30.0;
        let toggles_start_y = 80.0;

        for (i, _toggle) in self.toggles.iter().enumerate() {
            let col = i % 3;
            let row = i / 3;
            let tx = toggles_start_x + col as f64 * (toggle_size + toggle_spacing);
            let ty = toggles_start_y + row as f64 * (toggle_size + toggle_spacing + 20.0);

            if x >= tx && x < tx + toggle_size && y >= ty && y < ty + toggle_size {
                return Some(i);
            }
        }
        None
    }

    /// Toggle a quick setting
    pub fn toggle(&mut self, index: usize) {
        if let Some(toggle) = self.toggles.get_mut(index) {
            toggle.enabled = !toggle.enabled;
            tracing::info!("Toggle '{}' is now {}", toggle.name, if toggle.enabled { "ON" } else { "OFF" });
        }
    }
}
