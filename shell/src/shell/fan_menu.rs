//! Fan Menu - sPlay-inspired gesture menu system
//!
//! Replaces edge-specific gestures with a symmetric fan menu that works
//! for both left and right-handed users. The menu anchors at the bottom
//! corner of the triggering edge and fans out in an arc.
//!
//! ## App Registration
//! Apps can register dynamic menu items via IPC (file-based):
//! - Write to $XDG_RUNTIME_DIR/flick-fan-menu/<app-id>.json
//! - Items appear in the fan menu while the file exists
//! - Useful for media controls, quick actions, etc.

use smithay::utils::{Logical, Point, Size};
use std::collections::HashMap;
use std::f64::consts::PI;
use std::path::PathBuf;

/// Which side the fan menu is anchored to
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FanMenuSide {
    Left,   // Anchored at bottom-left
    Right,  // Anchored at bottom-right (mirrored)
}

/// Fan menu categories (inspired by sPlay research)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum FanCategory {
    Communicate,  // Phone, Messages, Contacts, Email
    Media,        // Music, Photos, Videos, Camera
    Tools,        // Calendar, Notes, Files, Calculator
    Apps,         // Full app launcher
    System,       // Settings, power/lock options
}

impl FanCategory {
    pub fn all() -> &'static [FanCategory] {
        &[
            FanCategory::Communicate,
            FanCategory::Media,
            FanCategory::Tools,
            FanCategory::Apps,
            FanCategory::System,
        ]
    }

    pub fn label(&self) -> &'static str {
        match self {
            FanCategory::Communicate => "Communicate",
            FanCategory::Media => "Media",
            FanCategory::Tools => "Tools",
            FanCategory::Apps => "Apps",
            FanCategory::System => "System",
        }
    }

    pub fn icon(&self) -> &'static str {
        match self {
            FanCategory::Communicate => "📱",
            FanCategory::Media => "🎵",
            FanCategory::Tools => "🔧",
            FanCategory::Apps => "📲",
            FanCategory::System => "⚙",
        }
    }
}

/// Item within a fan category
#[derive(Debug, Clone)]
pub struct FanMenuItem {
    pub name: String,
    pub icon: String,
    pub exec: String,
    pub is_recent: bool,
}

/// Fan menu state
#[derive(Debug, Clone)]
pub struct FanMenuState {
    /// Whether the fan menu is visible
    pub visible: bool,
    /// Which side it's anchored to
    pub side: FanMenuSide,
    /// Currently highlighted category (0-4, or -1 for none)
    pub highlighted_category: i32,
    /// Currently selected category for sub-menu
    pub selected_category: Option<FanCategory>,
    /// Currently highlighted item in sub-menu (-1 for none)
    pub highlighted_item: i32,
    /// Touch position for tracking
    pub touch_pos: Point<f64, Logical>,
    /// Anchor position (bottom corner)
    pub anchor: Point<f64, Logical>,
    /// Animation progress (0.0 = hidden, 1.0 = fully visible)
    pub progress: f64,
    /// Sub-menu animation progress
    pub submenu_progress: f64,
}

impl Default for FanMenuState {
    fn default() -> Self {
        Self {
            visible: false,
            side: FanMenuSide::Right,
            highlighted_category: -1,
            selected_category: None,
            highlighted_item: -1,
            touch_pos: Point::from((0.0, 0.0)),
            anchor: Point::from((0.0, 0.0)),
            progress: 0.0,
            submenu_progress: 0.0,
        }
    }
}

/// Fan menu layout calculator
pub struct FanMenuLayout {
    pub screen_size: Size<i32, Logical>,
    /// Radius of the main fan arc
    pub fan_radius: f64,
    /// Size of category buttons
    pub button_size: f64,
    /// Arc span in radians (how much of a circle the fan covers)
    pub arc_span: f64,
    /// Start angle offset from horizontal
    pub arc_start: f64,
}

impl FanMenuLayout {
    pub fn new(screen_size: Size<i32, Logical>) -> Self {
        Self {
            screen_size,
            fan_radius: 200.0,
            button_size: 80.0,
            arc_span: PI * 0.5,  // 90 degrees
            arc_start: PI * 0.1, // Start slightly above horizontal
        }
    }

    /// Get the anchor point for a given side
    pub fn anchor_point(&self, side: FanMenuSide) -> Point<f64, Logical> {
        let y = self.screen_size.h as f64 - 20.0; // 20px from bottom
        let x = match side {
            FanMenuSide::Left => 20.0,
            FanMenuSide::Right => self.screen_size.w as f64 - 20.0,
        };
        Point::from((x, y))
    }

    /// Get the center position for a category button
    /// index: 0-4 for the 5 categories
    pub fn category_position(&self, index: usize, side: FanMenuSide, anchor: Point<f64, Logical>) -> Point<f64, Logical> {
        let count = FanCategory::all().len() as f64;
        let angle_step = self.arc_span / (count - 1.0);

        // Calculate angle for this button
        let base_angle = match side {
            FanMenuSide::Left => PI - self.arc_start - (index as f64 * angle_step),
            FanMenuSide::Right => self.arc_start + (index as f64 * angle_step),
        };

        let x = anchor.x + self.fan_radius * base_angle.cos();
        let y = anchor.y - self.fan_radius * base_angle.sin(); // Y is inverted

        Point::from((x, y))
    }

    /// Get the rectangle bounds for a category button
    pub fn category_rect(&self, index: usize, side: FanMenuSide, anchor: Point<f64, Logical>) -> (f64, f64, f64, f64) {
        let center = self.category_position(index, side, anchor);
        let half = self.button_size / 2.0;
        (center.x - half, center.y - half, self.button_size, self.button_size)
    }

    /// Determine which category is highlighted based on touch position
    pub fn hit_test_category(&self, touch: Point<f64, Logical>, side: FanMenuSide, anchor: Point<f64, Logical>) -> i32 {
        for (i, _) in FanCategory::all().iter().enumerate() {
            let (x, y, w, h) = self.category_rect(i, side, anchor);
            if touch.x >= x && touch.x <= x + w && touch.y >= y && touch.y <= y + h {
                return i as i32;
            }
        }
        -1
    }

    /// Get positions for sub-menu items (secondary fan from selected category)
    pub fn submenu_positions(&self, category_index: usize, item_count: usize, side: FanMenuSide, anchor: Point<f64, Logical>) -> Vec<Point<f64, Logical>> {
        let category_pos = self.category_position(category_index, side, anchor);

        // Sub-menu fans out from the category button
        let submenu_radius = 120.0;
        let submenu_arc = PI * 0.4; // Smaller arc for sub-menu
        let arc_step = if item_count > 1 {
            submenu_arc / (item_count - 1) as f64
        } else {
            0.0
        };

        (0..item_count).map(|i| {
            let base_angle = match side {
                FanMenuSide::Left => PI * 0.75 - (i as f64 * arc_step),
                FanMenuSide::Right => PI * 0.25 + (i as f64 * arc_step),
            };

            Point::from((
                category_pos.x + submenu_radius * base_angle.cos(),
                category_pos.y - submenu_radius * base_angle.sin(),
            ))
        }).collect()
    }
}

/// Default items for each category
pub fn default_category_items(category: FanCategory) -> Vec<FanMenuItem> {
    match category {
        FanCategory::Communicate => vec![
            FanMenuItem { name: "Phone".into(), icon: "📞".into(), exec: "gnome-calls".into(), is_recent: false },
            FanMenuItem { name: "Messages".into(), icon: "💬".into(), exec: "chatty".into(), is_recent: false },
            FanMenuItem { name: "Contacts".into(), icon: "👤".into(), exec: "gnome-contacts".into(), is_recent: false },
            FanMenuItem { name: "Email".into(), icon: "✉️".into(), exec: "geary".into(), is_recent: false },
        ],
        FanCategory::Media => vec![
            FanMenuItem { name: "Music".into(), icon: "🎵".into(), exec: "__flick_music__".into(), is_recent: false },
            FanMenuItem { name: "Audiobooks".into(), icon: "📚".into(), exec: "__flick_audiobooks__".into(), is_recent: false },
            FanMenuItem { name: "Photos".into(), icon: "🖼️".into(), exec: "shotwell".into(), is_recent: false },
            FanMenuItem { name: "Camera".into(), icon: "📷".into(), exec: "megapixels".into(), is_recent: false },
        ],
        FanCategory::Tools => vec![
            FanMenuItem { name: "Calendar".into(), icon: "📅".into(), exec: "gnome-calendar".into(), is_recent: false },
            FanMenuItem { name: "Notes".into(), icon: "📝".into(), exec: "gnome-notes".into(), is_recent: false },
            FanMenuItem { name: "Files".into(), icon: "📁".into(), exec: "nautilus".into(), is_recent: false },
            FanMenuItem { name: "Calculator".into(), icon: "🔢".into(), exec: "gnome-calculator".into(), is_recent: false },
        ],
        FanCategory::Apps => vec![
            FanMenuItem { name: "All Apps".into(), icon: "📲".into(), exec: "__app_grid__".into(), is_recent: false },
        ],
        FanCategory::System => vec![
            FanMenuItem { name: "Settings".into(), icon: "⚙️".into(), exec: "gnome-control-center".into(), is_recent: false },
            FanMenuItem { name: "Lock".into(), icon: "🔒".into(), exec: "__lock__".into(), is_recent: false },
            FanMenuItem { name: "Power Off".into(), icon: "⏻".into(), exec: "__power_menu__".into(), is_recent: false },
        ],
    }
}

// ============================================================================
// App Registration System
// ============================================================================
// Apps can register dynamic menu items by writing JSON to:
//   $XDG_RUNTIME_DIR/flick-fan-menu/<app-id>.json
//
// Example JSON for a music player:
// {
//   "app_id": "flick-music",
//   "app_name": "Music",
//   "items": [
//     {"name": "Play/Pause", "icon": "⏯️", "action": "dbus:org.mpris.MediaPlayer2.Player.PlayPause"},
//     {"name": "Next", "icon": "⏭️", "action": "dbus:org.mpris.MediaPlayer2.Player.Next"},
//     {"name": "Previous", "icon": "⏮️", "action": "dbus:org.mpris.MediaPlayer2.Player.Previous"}
//   ],
//   "priority": 100,
//   "show_when": "playing"
// }

/// Registered app menu items (loaded from IPC files)
#[derive(Debug, Clone, Default)]
pub struct AppRegistration {
    pub app_id: String,
    pub app_name: String,
    pub items: Vec<RegisteredItem>,
    pub priority: i32,  // Higher = shown first
    pub show_when: ShowCondition,
}

/// When to show registered items
#[derive(Debug, Clone, Default, PartialEq)]
pub enum ShowCondition {
    #[default]
    Always,           // Always show in fan menu
    Playing,          // Only when media is playing
    HasContent,       // Only when app has content (e.g., downloads)
    Foreground,       // Only when app is in foreground
}

/// A single registered menu item
#[derive(Debug, Clone)]
pub struct RegisteredItem {
    pub name: String,
    pub icon: String,
    pub action: String,  // Can be: exec:<cmd>, dbus:<method>, signal:<name>
}

/// Registry of all app-registered menu items
#[derive(Debug, Default)]
pub struct FanMenuRegistry {
    /// Registered apps, keyed by app_id
    pub apps: HashMap<String, AppRegistration>,
    /// Path to the registration directory
    pub registry_dir: PathBuf,
    /// Last scan time
    pub last_scan: std::time::Instant,
}

impl FanMenuRegistry {
    pub fn new() -> Self {
        let runtime_dir = std::env::var("XDG_RUNTIME_DIR")
            .unwrap_or_else(|_| "/run/user/1000".to_string());
        let registry_dir = PathBuf::from(runtime_dir).join("flick-fan-menu");

        // Create directory if it doesn't exist
        let _ = std::fs::create_dir_all(&registry_dir);

        Self {
            apps: HashMap::new(),
            registry_dir,
            last_scan: std::time::Instant::now(),
        }
    }

    /// Scan for registered apps (call periodically, e.g., every 500ms)
    pub fn scan(&mut self) {
        // Don't scan too frequently
        if self.last_scan.elapsed().as_millis() < 500 {
            return;
        }
        self.last_scan = std::time::Instant::now();

        let Ok(entries) = std::fs::read_dir(&self.registry_dir) else {
            return;
        };

        // Track which apps we've seen this scan
        let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();

        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().map(|e| e == "json").unwrap_or(false) {
                if let Some(reg) = self.load_registration(&path) {
                    seen.insert(reg.app_id.clone());
                    self.apps.insert(reg.app_id.clone(), reg);
                }
            }
        }

        // Remove apps that no longer have registration files
        self.apps.retain(|id, _| seen.contains(id));
    }

    fn load_registration(&self, path: &PathBuf) -> Option<AppRegistration> {
        let content = std::fs::read_to_string(path).ok()?;
        let json: serde_json::Value = serde_json::from_str(&content).ok()?;

        let app_id = json.get("app_id")?.as_str()?.to_string();
        let app_name = json.get("app_name")?.as_str()?.to_string();
        let priority = json.get("priority").and_then(|v| v.as_i64()).unwrap_or(0) as i32;

        let show_when = match json.get("show_when").and_then(|v| v.as_str()) {
            Some("playing") => ShowCondition::Playing,
            Some("has_content") => ShowCondition::HasContent,
            Some("foreground") => ShowCondition::Foreground,
            _ => ShowCondition::Always,
        };

        let items = json.get("items")?
            .as_array()?
            .iter()
            .filter_map(|item| {
                Some(RegisteredItem {
                    name: item.get("name")?.as_str()?.to_string(),
                    icon: item.get("icon")?.as_str()?.to_string(),
                    action: item.get("action")?.as_str()?.to_string(),
                })
            })
            .collect();

        Some(AppRegistration {
            app_id,
            app_name,
            items,
            priority,
            show_when,
        })
    }

    /// Get all currently active registered items (sorted by priority)
    pub fn get_active_items(&self) -> Vec<&RegisteredItem> {
        let mut apps: Vec<_> = self.apps.values()
            .filter(|app| app.show_when == ShowCondition::Always) // TODO: check other conditions
            .collect();

        // Sort by priority (highest first)
        apps.sort_by(|a, b| b.priority.cmp(&a.priority));

        // Flatten items
        apps.iter().flat_map(|app| app.items.iter()).collect()
    }

    /// Get items for a specific app
    pub fn get_app_items(&self, app_id: &str) -> Option<&Vec<RegisteredItem>> {
        self.apps.get(app_id).map(|app| &app.items)
    }
}

/// Helper to execute a registered action
pub fn execute_action(action: &str) {
    if let Some(cmd) = action.strip_prefix("exec:") {
        // Execute a shell command
        let _ = std::process::Command::new("sh")
            .arg("-c")
            .arg(cmd)
            .spawn();
    } else if let Some(method) = action.strip_prefix("dbus:") {
        // Call a D-Bus method (format: interface.Method)
        // For now, use dbus-send
        let parts: Vec<&str> = method.rsplitn(2, '.').collect();
        if parts.len() == 2 {
            let method_name = parts[0];
            let interface = parts[1];
            let _ = std::process::Command::new("dbus-send")
                .args([
                    "--type=method_call",
                    "--dest=org.mpris.MediaPlayer2.flick-music",
                    "/org/mpris/MediaPlayer2",
                    &format!("{}.{}", interface, method_name),
                ])
                .spawn();
        }
    } else if let Some(signal) = action.strip_prefix("signal:") {
        // Send a signal via file (simple IPC)
        if let Ok(runtime_dir) = std::env::var("XDG_RUNTIME_DIR") {
            let signal_file = format!("{}/flick-signal-{}", runtime_dir, signal);
            let _ = std::fs::write(&signal_file, "1");
        }
    }
}
