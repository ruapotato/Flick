//! Shell management - window placement, workspaces, etc.

use smithay::{
    desktop::Window,
    utils::{Logical, Point, Size},
};

/// Window placement mode
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WindowMode {
    /// Fullscreen, native resolution (mobile apps)
    Fullscreen,
    /// In the desktop viewport (1080p, pan/zoom)
    Desktop,
    /// Floating window
    Floating,
}

/// Flick shell configuration
#[derive(Debug, Clone)]
pub struct ShellConfig {
    /// Default mode for new windows
    pub default_mode: WindowMode,
    /// Desktop viewport size
    pub desktop_size: Size<i32, Logical>,
    /// Enable virtual desktop for non-mobile apps
    pub enable_desktop_viewport: bool,
}

impl Default for ShellConfig {
    fn default() -> Self {
        Self {
            default_mode: WindowMode::Fullscreen,
            desktop_size: Size::from((1920, 1080)),
            enable_desktop_viewport: true,
        }
    }
}

/// Determine if an app should use the desktop viewport
pub fn should_use_desktop_viewport(app_id: Option<&str>, title: Option<&str>) -> bool {
    // Heuristics to detect desktop apps:
    // 1. Known desktop apps
    // 2. Apps without mobile adaptations
    // 3. Apps requesting specific window sizes

    let desktop_apps = [
        "firefox",
        "chromium",
        "chrome",
        "libreoffice",
        "gimp",
        "inkscape",
        "blender",
        "code",
        "vscode",
    ];

    if let Some(id) = app_id {
        let id_lower = id.to_lowercase();
        for app in &desktop_apps {
            if id_lower.contains(app) {
                return true;
            }
        }
    }

    false
}
