//! Fan Menu - sPlay-inspired gesture menu system
//!
//! Replaces edge-specific gestures with a symmetric fan menu that works
//! for both left and right-handed users. The menu anchors at the bottom
//! corner of the triggering edge and fans out in an arc.

use smithay::utils::{Logical, Point, Size};
use std::f64::consts::PI;

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
            FanMenuItem { name: "Music".into(), icon: "🎵".into(), exec: "lollypop".into(), is_recent: false },
            FanMenuItem { name: "Photos".into(), icon: "🖼️".into(), exec: "shotwell".into(), is_recent: false },
            FanMenuItem { name: "Videos".into(), icon: "🎬".into(), exec: "totem".into(), is_recent: false },
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
