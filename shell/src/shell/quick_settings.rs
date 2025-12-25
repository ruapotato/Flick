//! Quick Settings / Notifications panel
//!
//! Slides in from the left edge, Android-style.
//! Shows status bar, quick toggles, brightness, and notifications.

use smithay::utils::{Logical, Size};
use super::primitives::{Rect, Color, colors};
use super::text;
use std::sync::{Arc, Mutex};
use std::time::SystemTime;

/// Quick toggle button definition
#[derive(Debug, Clone)]
pub struct QuickToggle {
    pub id: String,
    pub name: String,
    pub icon: &'static str,
    pub enabled: bool,
}

impl QuickToggle {
    pub fn new(id: &str, name: &str, icon: &'static str, enabled: bool) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            icon,
            enabled,
        }
    }

    pub fn background_color(&self) -> Color {
        if self.enabled {
            [0.2, 0.6, 1.0, 1.0]  // Bright blue when on
        } else {
            [0.4, 0.4, 0.5, 1.0]  // Light gray when off
        }
    }

    pub fn icon_color(&self) -> Color {
        [1.0, 1.0, 1.0, 1.0]  // Always white
    }
}

/// Default quick toggles
pub fn default_toggles() -> Vec<QuickToggle> {
    vec![
        QuickToggle::new("wifi", "WiFi", "W", true),
        QuickToggle::new("bluetooth", "BT", "B", false),
        QuickToggle::new("dnd", "DND", "D", false),
        QuickToggle::new("flashlight", "Light", "L", false),
        QuickToggle::new("rotation", "Rotate", "R", true),
        QuickToggle::new("airplane", "Flight", "A", false),
    ]
}

/// Notification priority/urgency
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum NotificationUrgency {
    Low,
    Normal,
    Critical,
}

/// Notification item
#[derive(Debug, Clone)]
pub struct Notification {
    pub id: u32,
    pub app_name: String,
    pub summary: String,
    pub body: String,
    pub urgency: NotificationUrgency,
    pub timestamp: u64,
}

impl Notification {
    pub fn new(id: u32, app_name: &str, summary: &str, body: &str) -> Self {
        let timestamp = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        Self {
            id,
            app_name: app_name.to_string(),
            summary: summary.to_string(),
            body: body.to_string(),
            urgency: NotificationUrgency::Normal,
            timestamp,
        }
    }

    pub fn accent_color(&self) -> Color {
        match self.urgency {
            NotificationUrgency::Low => [0.5, 0.8, 0.5, 1.0],
            NotificationUrgency::Normal => [0.4, 0.6, 1.0, 1.0],
            NotificationUrgency::Critical => [1.0, 0.4, 0.4, 1.0],
        }
    }

    pub fn time_ago(&self) -> String {
        let now = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        let diff = now.saturating_sub(self.timestamp);

        if diff < 60 {
            "now".to_string()
        } else if diff < 3600 {
            format!("{}m", diff / 60)
        } else if diff < 86400 {
            format!("{}h", diff / 3600)
        } else {
            format!("{}d", diff / 86400)
        }
    }
}

/// Global notification store
pub struct NotificationStore {
    notifications: Vec<Notification>,
    next_id: u32,
}

impl NotificationStore {
    pub fn new() -> Self {
        Self {
            notifications: Vec::new(),
            next_id: 1,
        }
    }

    pub fn add(&mut self, app_name: &str, summary: &str, body: &str) -> u32 {
        let id = self.next_id;
        self.next_id += 1;
        self.notifications.push(Notification::new(id, app_name, summary, body));
        id
    }

    pub fn remove(&mut self, id: u32) {
        self.notifications.retain(|n| n.id != id);
    }

    pub fn get_all(&self) -> Vec<Notification> {
        let mut notifs = self.notifications.clone();
        notifs.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
        notifs
    }
}

impl Default for NotificationStore {
    fn default() -> Self {
        Self::new()
    }
}

lazy_static::lazy_static! {
    pub static ref NOTIFICATIONS: Arc<Mutex<NotificationStore>> = {
        let mut store = NotificationStore::new();
        store.add("Flick", "Welcome to Flick", "Swipe gestures are ready");
        Arc::new(Mutex::new(store))
    };
}

/// Quick settings panel state
pub struct QuickSettingsPanel {
    pub screen_size: Size<i32, Logical>,
    pub toggles: Vec<QuickToggle>,
    pub brightness: f32,
    pub volume: u8,
    pub muted: bool,
    pub scroll_offset: f64,
    // Cached system status for rendering
    pub battery_percent: u8,
    pub battery_charging: bool,
    pub wifi_connected: bool,
    pub wifi_ssid: Option<String>,
}

impl QuickSettingsPanel {
    pub fn new(screen_size: Size<i32, Logical>) -> Self {
        Self {
            screen_size,
            toggles: default_toggles(),
            brightness: 0.7,
            volume: 50,
            muted: false,
            scroll_offset: 0.0,
            battery_percent: 0,
            battery_charging: false,
            wifi_connected: false,
            wifi_ssid: None,
        }
    }

    /// Update system status from the main system module
    pub fn update_from_system(&mut self, system: &crate::system::SystemStatus) {
        // Update battery
        if let Some(ref battery) = system.battery {
            self.battery_percent = battery.capacity;
            self.battery_charging = battery.charging;
        }

        // Update WiFi status
        self.wifi_connected = system.wifi_enabled;
        self.wifi_ssid = system.wifi_ssid.clone();

        // Update toggles to reflect real system state
        for toggle in &mut self.toggles {
            match toggle.id.as_str() {
                "wifi" => toggle.enabled = system.wifi_enabled,
                "bluetooth" => toggle.enabled = system.bluetooth_enabled,
                "dnd" => toggle.enabled = system.dnd.enabled,
                "rotation" => toggle.enabled = system.rotation_lock.locked,
                "airplane" => toggle.enabled = !system.wifi_enabled && !system.bluetooth_enabled,
                _ => {}
            }
        }

        // Sync brightness from system (read current value)
        self.brightness = system.get_brightness();

        // Sync volume from system
        self.volume = system.volume;
        self.muted = system.muted;
    }

    /// Get list of rectangles to render
    pub fn get_render_rects(&self) -> Vec<(Rect, Color)> {
        let mut rects = Vec::new();
        let screen_w = self.screen_size.w as f64;
        let screen_h = self.screen_size.h as f64;
        let padding = 20.0;
        let scroll = self.scroll_offset;

        // ============ BACKGROUND ============
        let bg = Rect::new(0.0, 0.0, screen_w, screen_h);
        rects.push((bg, [0.1, 0.1, 0.15, 1.0]));  // Dark background

        // ============ STATUS BAR (fixed at top) ============
        let status_bar_height = 56.0;
        let status_bar = Rect::new(0.0, 0.0, screen_w, status_bar_height);
        rects.push((status_bar, [0.2, 0.3, 0.5, 1.0]));  // Bright blue status bar

        // Time (centered, large)
        let time = Self::get_time_string();
        let time_rects = text::render_text_centered(
            &time,
            screen_w / 2.0,
            18.0,
            4.0,
            [1.0, 1.0, 1.0, 1.0],
        );
        rects.extend(time_rects);

        // WiFi status (left side)
        let wifi_text = if self.wifi_connected {
            if let Some(ref ssid) = self.wifi_ssid {
                ssid.chars().take(12).collect::<String>()  // Truncate long SSIDs
            } else {
                "WiFi".to_string()
            }
        } else {
            "No WiFi".to_string()
        };
        let wifi_color = if self.wifi_connected {
            [0.4, 0.8, 1.0, 1.0]  // Blue when connected
        } else {
            [0.5, 0.5, 0.6, 1.0]  // Gray when off
        };
        let wifi_rects = text::render_text(
            &wifi_text,
            16.0,
            20.0,
            2.5,
            wifi_color,
        );
        rects.extend(wifi_rects);

        // Battery (right side) - use real value
        let battery_str = format!("{}", self.battery_percent);
        let battery_color = if self.battery_charging {
            [0.4, 1.0, 0.4, 1.0]  // Green when charging
        } else if self.battery_percent <= 20 {
            [1.0, 0.4, 0.4, 1.0]  // Red when low
        } else {
            [0.6, 1.0, 0.6, 1.0]  // Normal green
        };
        let battery_rects = text::render_text(
            &battery_str,
            screen_w - 70.0,
            20.0,
            3.0,
            battery_color,
        );
        rects.extend(battery_rects);

        // Battery icon
        let bat_icon = Rect::new(screen_w - 36.0, 20.0, 20.0, 12.0);
        rects.push((bat_icon, battery_color));
        let bat_tip = Rect::new(screen_w - 16.0, 23.0, 4.0, 6.0);
        rects.push((bat_tip, battery_color));

        // Charging indicator (lightning bolt placeholder)
        if self.battery_charging {
            let charge_indicator = Rect::new(screen_w - 32.0, 22.0, 8.0, 8.0);
            rects.push((charge_indicator, [1.0, 1.0, 0.0, 1.0]));  // Yellow
        }

        // ============ SCROLLABLE CONTENT ============
        let content_y = status_bar_height - scroll;

        // ============ QUICK TOGGLES ============
        let toggle_size = 72.0;  // Fixed small size
        let toggle_spacing = 16.0;
        let toggles_per_row = 4;
        let grid_width = toggles_per_row as f64 * toggle_size + (toggles_per_row - 1) as f64 * toggle_spacing;
        let grid_start_x = (screen_w - grid_width) / 2.0;

        // Section header
        let toggles_start_y = content_y + padding;
        let header_rects = text::render_text(
            "QUICK SETTINGS",
            padding,
            toggles_start_y,
            2.5,
            [0.7, 0.7, 0.8, 1.0],
        );
        rects.extend(header_rects);

        let toggles_grid_y = toggles_start_y + 32.0;

        for (i, toggle) in self.toggles.iter().enumerate() {
            let col = i % toggles_per_row;
            let row = i / toggles_per_row;
            let x = grid_start_x + col as f64 * (toggle_size + toggle_spacing);
            let y = toggles_grid_y + row as f64 * (toggle_size + 28.0);

            // Skip if off-screen
            if y + toggle_size < 0.0 || y > screen_h {
                continue;
            }

            // Toggle background
            let toggle_rect = Rect::new(x, y, toggle_size, toggle_size);
            rects.push((toggle_rect, toggle.background_color()));

            // Toggle icon (centered)
            let icon_rects = text::render_text_centered(
                toggle.icon,
                x + toggle_size / 2.0,
                y + toggle_size / 2.0 - 12.0,
                4.0,
                toggle.icon_color(),
            );
            rects.extend(icon_rects);

            // Toggle name below
            let name_rects = text::render_text_centered(
                &toggle.name,
                x + toggle_size / 2.0,
                y + toggle_size + 4.0,
                1.8,
                if toggle.enabled { [1.0, 1.0, 1.0, 1.0] } else { [0.6, 0.6, 0.7, 1.0] },
            );
            rects.extend(name_rects);
        }

        // ============ BRIGHTNESS SLIDER ============
        let rows = (self.toggles.len() + toggles_per_row - 1) / toggles_per_row;
        let brightness_y = toggles_grid_y + rows as f64 * (toggle_size + 28.0) + 24.0;

        if brightness_y < screen_h && brightness_y + 60.0 > 0.0 {
            let bright_label = text::render_text(
                "BRIGHTNESS",
                padding,
                brightness_y,
                2.5,
                [0.7, 0.7, 0.8, 1.0],
            );
            rects.extend(bright_label);

            let slider_y = brightness_y + 32.0;
            let slider_width = screen_w - padding * 2.0;
            let slider_height = 40.0;

            // Slider track
            let track = Rect::new(padding, slider_y, slider_width, slider_height);
            rects.push((track, [0.3, 0.3, 0.35, 1.0]));

            // Slider fill
            let fill_width = slider_width * self.brightness as f64;
            let fill = Rect::new(padding, slider_y, fill_width, slider_height);
            rects.push((fill, [1.0, 0.8, 0.3, 1.0]));  // Bright yellow

            // Sun icon
            let sun_rects = text::render_text(
                "O",
                padding + 14.0,
                slider_y + 10.0,
                3.0,
                [1.0, 1.0, 1.0, 1.0],
            );
            rects.extend(sun_rects);
        }

        // ============ VOLUME SLIDER ============
        let volume_y = brightness_y + 90.0;

        if volume_y < screen_h && volume_y + 60.0 > 0.0 {
            let vol_label = text::render_text(
                "VOLUME",
                padding,
                volume_y,
                2.5,
                [0.7, 0.7, 0.8, 1.0],
            );
            rects.extend(vol_label);

            let vol_slider_y = volume_y + 32.0;
            let slider_width = screen_w - padding * 2.0;
            let slider_height = 40.0;

            // Slider track
            let track = Rect::new(padding, vol_slider_y, slider_width, slider_height);
            rects.push((track, [0.3, 0.3, 0.35, 1.0]));

            // Slider fill (use volume as 0-100)
            let vol_fill_width = if self.muted { 0.0 } else { slider_width * (self.volume as f64 / 100.0) };
            let vol_color = if self.muted {
                [0.5, 0.5, 0.6, 1.0]  // Gray when muted
            } else {
                [0.4, 0.7, 1.0, 1.0]  // Blue for volume
            };
            let vol_fill = Rect::new(padding, vol_slider_y, vol_fill_width, slider_height);
            rects.push((vol_fill, vol_color));

            // Speaker icon (or muted icon)
            let vol_icon = if self.muted { "X" } else { "V" };
            let vol_icon_rects = text::render_text(
                vol_icon,
                padding + 14.0,
                vol_slider_y + 10.0,
                3.0,
                [1.0, 1.0, 1.0, 1.0],
            );
            rects.extend(vol_icon_rects);

            // Volume percentage on right side
            let vol_pct = format!("{}%", self.volume);
            let vol_pct_rects = text::render_text(
                &vol_pct,
                padding + slider_width - 50.0,
                vol_slider_y + 10.0,
                2.5,
                [1.0, 1.0, 1.0, 1.0],
            );
            rects.extend(vol_pct_rects);
        }

        // ============ NOTIFICATIONS ============
        let notif_start_y = volume_y + 90.0;

        if notif_start_y < screen_h {
            let notif_header = text::render_text(
                "NOTIFICATIONS",
                padding,
                notif_start_y,
                2.5,
                [0.7, 0.7, 0.8, 1.0],
            );
            rects.extend(notif_header);
        }

        let notifications = if let Ok(store) = NOTIFICATIONS.lock() {
            store.get_all()
        } else {
            Vec::new()
        };

        let notif_list_y = notif_start_y + 32.0;
        let card_height = 80.0;
        let card_spacing = 12.0;
        let card_width = screen_w - padding * 2.0;

        if notifications.is_empty() && notif_list_y < screen_h {
            let empty_rects = text::render_text_centered(
                "No notifications",
                screen_w / 2.0,
                notif_list_y + 40.0,
                3.0,
                [0.5, 0.5, 0.6, 1.0],
            );
            rects.extend(empty_rects);
        } else {
            for (i, notif) in notifications.iter().take(10).enumerate() {
                let y = notif_list_y + i as f64 * (card_height + card_spacing);

                // Skip if off-screen
                if y + card_height < 0.0 || y > screen_h {
                    continue;
                }

                // Card background
                let card = Rect::new(padding, y, card_width, card_height);
                rects.push((card, [0.25, 0.25, 0.32, 1.0]));

                // Accent bar
                let accent = Rect::new(padding, y, 5.0, card_height);
                rects.push((accent, notif.accent_color()));

                // App name
                let app_rects = text::render_text(
                    &notif.app_name.to_uppercase(),
                    padding + 16.0,
                    y + 10.0,
                    2.0,
                    [0.6, 0.6, 0.7, 1.0],
                );
                rects.extend(app_rects);

                // Time ago
                let time_str = notif.time_ago();
                let time_width = text::text_width(&time_str) * 2.0;
                let time_rects = text::render_text(
                    &time_str,
                    padding + card_width - time_width - 16.0,
                    y + 10.0,
                    2.0,
                    [0.5, 0.5, 0.6, 1.0],
                );
                rects.extend(time_rects);

                // Summary
                let summary_rects = text::render_text(
                    &notif.summary,
                    padding + 16.0,
                    y + 30.0,
                    2.8,
                    [1.0, 1.0, 1.0, 1.0],
                );
                rects.extend(summary_rects);

                // Body
                let body_rects = text::render_text(
                    &notif.body,
                    padding + 16.0,
                    y + 55.0,
                    2.2,
                    [0.8, 0.8, 0.9, 1.0],
                );
                rects.extend(body_rects);
            }
        }

        // ============ HOME INDICATOR (fixed at bottom) ============
        let indicator_width = 134.0;
        let indicator_height = 5.0;
        let indicator_x = (screen_w - indicator_width) / 2.0;
        let indicator_y = screen_h - 21.0;
        let indicator = Rect::new(indicator_x, indicator_y, indicator_width, indicator_height);
        rects.push((indicator, colors::HOME_INDICATOR));

        // IMPORTANT: Smithay renders elements in FRONT-TO-BACK order
        // (first element = on top, last element = background)
        // So we need to reverse the order so background renders first
        rects.reverse();
        rects
    }

    fn get_time_string() -> String {
        use std::process::Command;
        if let Ok(output) = Command::new("date").arg("+%H:%M").output() {
            if let Ok(time) = String::from_utf8(output.stdout) {
                return time.trim().to_string();
            }
        }
        "12:00".to_string()
    }

    /// Get toggle button layout info for hit testing
    fn get_toggle_layout(&self) -> (f64, f64, f64, f64, usize) {
        let toggle_size = 72.0;
        let toggle_spacing = 16.0;
        let toggles_per_row = 4;
        let screen_w = self.screen_size.w as f64;
        let grid_width = toggles_per_row as f64 * toggle_size + (toggles_per_row - 1) as f64 * toggle_spacing;
        let grid_start_x = (screen_w - grid_width) / 2.0;
        let toggles_grid_y = 56.0 + 20.0 + 32.0 - self.scroll_offset;  // status_bar + padding + header
        (grid_start_x, toggles_grid_y, toggle_size, toggle_spacing, toggles_per_row)
    }

    /// Hit test for toggle buttons
    pub fn hit_test_toggle(&self, x: f64, y: f64) -> Option<usize> {
        let (grid_start_x, toggles_grid_y, toggle_size, toggle_spacing, toggles_per_row) = self.get_toggle_layout();

        for (i, _) in self.toggles.iter().enumerate() {
            let col = i % toggles_per_row;
            let row = i / toggles_per_row;
            let tx = grid_start_x + col as f64 * (toggle_size + toggle_spacing);
            let ty = toggles_grid_y + row as f64 * (toggle_size + 28.0);

            if x >= tx && x < tx + toggle_size && y >= ty && y < ty + toggle_size {
                return Some(i);
            }
        }
        None
    }

    /// Hit test for brightness slider
    pub fn hit_test_brightness(&self, x: f64, y: f64) -> Option<f32> {
        let padding = 20.0;
        let screen_w = self.screen_size.w as f64;
        let toggle_size = 72.0;
        let toggles_per_row = 4;
        let rows = (self.toggles.len() + toggles_per_row - 1) / toggles_per_row;
        let toggles_grid_y = 56.0 + 20.0 + 32.0 - self.scroll_offset;
        let brightness_y = toggles_grid_y + rows as f64 * (toggle_size + 28.0) + 24.0;
        let slider_y = brightness_y + 32.0;
        let slider_height = 40.0;
        let slider_width = screen_w - padding * 2.0;

        if y >= slider_y && y < slider_y + slider_height && x >= padding && x < padding + slider_width {
            let brightness = ((x - padding) / slider_width).clamp(0.0, 1.0) as f32;
            return Some(brightness);
        }
        None
    }

    /// Hit test for volume slider - returns volume 0-100
    pub fn hit_test_volume(&self, x: f64, y: f64) -> Option<u8> {
        let padding = 20.0;
        let screen_w = self.screen_size.w as f64;
        let toggle_size = 72.0;
        let toggles_per_row = 4;
        let rows = (self.toggles.len() + toggles_per_row - 1) / toggles_per_row;
        let toggles_grid_y = 56.0 + 20.0 + 32.0 - self.scroll_offset;
        let brightness_y = toggles_grid_y + rows as f64 * (toggle_size + 28.0) + 24.0;
        let volume_y = brightness_y + 90.0;
        let slider_y = volume_y + 32.0;
        let slider_height = 40.0;
        let slider_width = screen_w - padding * 2.0;

        if y >= slider_y && y < slider_y + slider_height && x >= padding && x < padding + slider_width {
            let volume = (((x - padding) / slider_width) * 100.0).clamp(0.0, 100.0) as u8;
            return Some(volume);
        }
        None
    }

    /// Toggle a quick setting - returns the toggle ID for system action
    pub fn toggle(&mut self, index: usize) -> Option<String> {
        if let Some(toggle) = self.toggles.get_mut(index) {
            toggle.enabled = !toggle.enabled;
            tracing::info!("Toggle '{}' is now {}", toggle.name, if toggle.enabled { "ON" } else { "OFF" });
            Some(toggle.id.clone())
        } else {
            None
        }
    }

    /// Set brightness
    pub fn set_brightness(&mut self, value: f32) {
        self.brightness = value.clamp(0.0, 1.0);
        tracing::info!("Brightness set to {:.0}%", self.brightness * 100.0);
    }

    /// Set volume (0-100)
    pub fn set_volume(&mut self, value: u8) {
        self.volume = value.min(100);
        self.muted = false;  // Unmute when adjusting volume
        tracing::info!("Volume set to {}%", self.volume);
    }

    /// Get content height for scrolling
    pub fn content_height(&self) -> f64 {
        let toggle_size = 72.0;
        let toggles_per_row = 4;
        let rows = (self.toggles.len() + toggles_per_row - 1) / toggles_per_row;

        let notifications = if let Ok(store) = NOTIFICATIONS.lock() {
            store.get_all().len()
        } else {
            0
        };

        let card_height = 80.0;
        let card_spacing = 12.0;

        // Calculate total content height
        56.0  // status bar
            + 20.0  // padding
            + 32.0  // header
            + rows as f64 * (toggle_size + 28.0)  // toggles
            + 24.0 + 32.0 + 40.0  // brightness section
            + 90.0  // volume section
            + 32.0  // notifications header
            + notifications.max(1) as f64 * (card_height + card_spacing)
            + 100.0  // bottom padding
    }

    /// Update scroll offset
    pub fn scroll(&mut self, delta: f64) {
        let max_scroll = (self.content_height() - self.screen_size.h as f64).max(0.0);
        self.scroll_offset = (self.scroll_offset + delta).clamp(0.0, max_scroll);
    }
}

/// Helper to add a notification
pub fn add_notification(app_name: &str, summary: &str, body: &str) -> Option<u32> {
    if let Ok(mut store) = NOTIFICATIONS.lock() {
        Some(store.add(app_name, summary, body))
    } else {
        None
    }
}
