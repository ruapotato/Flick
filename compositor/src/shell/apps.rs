//! App category management and desktop file parsing
//!
//! Manages app categories (Web, Email, Files, etc.) that open system default apps.
//! Users can long-press to select which installed app to use for each category.

use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use serde::{Deserialize, Serialize};

/// Predefined app categories that appear on the home screen
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum AppCategory {
    Web,
    Email,
    Messages,
    Phone,
    Camera,
    Photos,
    Music,
    Video,
    Files,
    Terminal,
    Calculator,
    Calendar,
    Notes,
    Settings,
}

impl AppCategory {
    /// Get all categories in display order
    pub fn all() -> Vec<Self> {
        vec![
            Self::Phone,
            Self::Messages,
            Self::Web,
            Self::Email,
            Self::Camera,
            Self::Photos,
            Self::Music,
            Self::Files,
            Self::Calendar,
            Self::Notes,
            Self::Calculator,
            Self::Terminal,
            Self::Settings,
        ]
    }

    /// Get the display name for this category
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Web => "Web",
            Self::Email => "Email",
            Self::Messages => "Messages",
            Self::Phone => "Phone",
            Self::Camera => "Camera",
            Self::Photos => "Photos",
            Self::Music => "Music",
            Self::Video => "Video",
            Self::Files => "Files",
            Self::Terminal => "Terminal",
            Self::Calculator => "Calculator",
            Self::Calendar => "Calendar",
            Self::Notes => "Notes",
            Self::Settings => "Settings",
        }
    }

    /// Get the desktop category strings that match this category
    /// Returns (primary categories, secondary categories) - primary matches are ranked higher
    pub fn desktop_categories(&self) -> (Vec<&'static str>, Vec<&'static str>) {
        match self {
            Self::Web => (vec!["WebBrowser"], vec!["Network"]),
            Self::Email => (vec!["Email"], vec!["ContactManagement"]),
            Self::Messages => (vec!["InstantMessaging", "Chat"], vec!["IRCClient"]),
            Self::Phone => (vec!["Telephony"], vec![]),
            Self::Camera => (vec!["Camera"], vec!["Photography", "Recorder"]),
            Self::Photos => (vec!["Photography", "Viewer"], vec!["Graphics", "2DGraphics"]),
            Self::Music => (vec!["Music", "Audio"], vec!["Player"]),
            Self::Video => (vec!["Video"], vec!["AudioVideo"]),
            Self::Files => (vec!["FileManager"], vec!["FileTools", "Filesystem"]),
            Self::Terminal => (vec!["TerminalEmulator"], vec![]), // Only exact terminal matches
            Self::Calculator => (vec!["Calculator"], vec!["Math"]),
            Self::Calendar => (vec!["Calendar"], vec!["ProjectManagement"]),
            Self::Notes => (vec!["TextEditor"], vec!["WordProcessor"]),
            Self::Settings => (vec!["Settings", "DesktopSettings"], vec![]),
        }
    }

    /// Get a default color for this category (used as fallback if no icon)
    pub fn default_color(&self) -> [f32; 4] {
        match self {
            Self::Web => [0.2, 0.5, 0.9, 1.0],       // Blue
            Self::Email => [0.9, 0.3, 0.3, 1.0],     // Red
            Self::Messages => [0.2, 0.8, 0.4, 1.0],  // Green
            Self::Phone => [0.2, 0.8, 0.2, 1.0],     // Bright Green
            Self::Camera => [0.5, 0.5, 0.5, 1.0],    // Gray
            Self::Photos => [0.8, 0.4, 0.8, 1.0],    // Purple
            Self::Music => [0.9, 0.4, 0.2, 1.0],     // Orange
            Self::Video => [0.8, 0.2, 0.2, 1.0],     // Dark Red
            Self::Files => [0.8, 0.7, 0.3, 1.0],     // Yellow
            Self::Terminal => [0.2, 0.2, 0.2, 1.0],  // Dark Gray
            Self::Calculator => [0.3, 0.3, 0.7, 1.0], // Indigo
            Self::Calendar => [0.2, 0.6, 0.9, 1.0],  // Light Blue
            Self::Notes => [0.9, 0.9, 0.3, 1.0],     // Yellow
            Self::Settings => [0.5, 0.5, 0.6, 1.0],  // Gray-Blue
        }
    }
}

/// A parsed desktop entry (.desktop file)
#[derive(Debug, Clone)]
pub struct DesktopEntry {
    /// Application name
    pub name: String,
    /// Exec command
    pub exec: String,
    /// Icon name (can be resolved to a path)
    pub icon: Option<String>,
    /// Categories from the desktop file
    pub categories: Vec<String>,
    /// Path to the .desktop file
    pub path: PathBuf,
    /// Whether this is a terminal application
    pub terminal: bool,
}

impl DesktopEntry {
    /// Parse a .desktop file
    pub fn parse(path: &PathBuf) -> Option<Self> {
        let content = fs::read_to_string(path).ok()?;
        let mut name = None;
        let mut exec = None;
        let mut icon = None;
        let mut categories = Vec::new();
        let mut terminal = false;
        let mut in_desktop_entry = false;

        for line in content.lines() {
            let line = line.trim();

            if line.starts_with('[') {
                in_desktop_entry = line == "[Desktop Entry]";
                continue;
            }

            if !in_desktop_entry {
                continue;
            }

            if let Some((key, value)) = line.split_once('=') {
                match key {
                    "Name" => name = Some(value.to_string()),
                    "Exec" => {
                        // Remove field codes like %u, %f, %U, %F
                        let clean_exec = value
                            .replace("%u", "")
                            .replace("%U", "")
                            .replace("%f", "")
                            .replace("%F", "")
                            .replace("%%", "%")
                            .trim()
                            .to_string();
                        exec = Some(clean_exec);
                    }
                    "Icon" => icon = Some(value.to_string()),
                    "Categories" => {
                        categories = value
                            .split(';')
                            .filter(|s| !s.is_empty())
                            .map(|s| s.to_string())
                            .collect();
                    }
                    "Terminal" => terminal = value.eq_ignore_ascii_case("true"),
                    _ => {}
                }
            }
        }

        Some(Self {
            name: name?,
            exec: exec?,
            icon,
            categories,
            path: path.clone(),
            terminal,
        })
    }

    /// Check if this entry matches a category, returning a score (0 = no match, higher = better)
    pub fn match_score(&self, category: AppCategory) -> u32 {
        let (primary, secondary) = category.desktop_categories();
        let mut score = 0u32;

        for cat in &self.categories {
            if primary.contains(&cat.as_str()) {
                score += 10; // Primary category match
            } else if secondary.contains(&cat.as_str()) {
                score += 1; // Secondary category match
            }
        }

        // Boost terminal apps that have Terminal=true in their .desktop file
        if category == AppCategory::Terminal && self.terminal {
            score += 5;
        }

        score
    }

    /// Check if this entry matches a category
    pub fn matches_category(&self, category: AppCategory) -> bool {
        self.match_score(category) > 0
    }
}

/// App configuration - stores user preferences for which apps to use
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    /// Selected app exec command per category
    pub selections: HashMap<AppCategory, String>,
    /// Grid positions for categories (index -> category)
    pub grid_order: Vec<AppCategory>,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            selections: HashMap::new(),
            grid_order: AppCategory::all(),
        }
    }
}

impl AppConfig {
    /// Get the config file path
    fn config_path() -> Option<PathBuf> {
        std::env::var("HOME").ok().map(|home| {
            PathBuf::from(home).join(".local/state/flick/app_config.json")
        })
    }

    /// Load config from file, or return default if not found
    pub fn load() -> Self {
        if let Some(path) = Self::config_path() {
            if let Ok(contents) = fs::read_to_string(&path) {
                if let Ok(config) = serde_json::from_str(&contents) {
                    tracing::info!("Loaded app config from {:?}", path);
                    return config;
                }
            }
        }
        Self::default()
    }

    /// Save config to file
    pub fn save(&self) {
        if let Some(path) = Self::config_path() {
            // Ensure parent directory exists
            if let Some(parent) = path.parent() {
                let _ = fs::create_dir_all(parent);
            }
            if let Ok(json) = serde_json::to_string_pretty(self) {
                if let Err(e) = fs::write(&path, json) {
                    tracing::warn!("Failed to save app config: {:?}", e);
                } else {
                    tracing::info!("Saved app config to {:?}", path);
                }
            }
        }
    }

    /// Get the selected exec command for a category, or None if not set
    pub fn get_selected(&self, category: AppCategory) -> Option<&str> {
        self.selections.get(&category).map(|s| s.as_str())
    }

    /// Set the selected app for a category
    pub fn set_selected(&mut self, category: AppCategory, exec: String) {
        self.selections.insert(category, exec);
    }

    /// Move a category to a new position in the grid
    pub fn move_category(&mut self, from: usize, to: usize) {
        if from < self.grid_order.len() && to < self.grid_order.len() {
            let cat = self.grid_order.remove(from);
            self.grid_order.insert(to, cat);
        }
    }
}

/// Manager for discovering and categorizing installed apps
pub struct AppManager {
    /// All discovered desktop entries
    pub entries: Vec<DesktopEntry>,
    /// User configuration
    pub config: AppConfig,
    /// Cached category info for fast rendering
    cached_category_info: Vec<CategoryInfo>,
}

impl AppManager {
    /// Create a new app manager and scan for installed apps
    pub fn new() -> Self {
        let mut manager = Self {
            entries: Vec::new(),
            config: AppConfig::load(), // Load saved config or use default
            cached_category_info: Vec::new(),
        };
        manager.scan_apps();
        manager.set_defaults();
        manager.rebuild_cache();
        manager
    }

    /// Rebuild the cached category info (call after any changes)
    fn rebuild_cache(&mut self) {
        self.cached_category_info = self.config.grid_order.iter().map(|&cat| {
            let selected_exec = self.config.get_selected(cat).map(|s| s.to_string());
            let available_apps = self.apps_for_category(cat);
            let icon = selected_exec.as_ref().and_then(|exec| {
                self.entries.iter()
                    .find(|e| &e.exec == exec)
                    .and_then(|e| e.icon.clone())
            });

            CategoryInfo {
                category: cat,
                name: cat.display_name().to_string(),
                selected_exec,
                available_count: available_apps.len(),
                icon,
                color: cat.default_color(),
            }
        }).collect();
    }

    /// Scan standard locations for .desktop files
    pub fn scan_apps(&mut self) {
        use std::collections::HashSet;

        let mut paths = Vec::new();

        // System applications
        paths.push(PathBuf::from("/usr/share/applications"));
        paths.push(PathBuf::from("/usr/local/share/applications"));

        // User applications
        if let Some(home) = std::env::var_os("HOME") {
            let home = PathBuf::from(home);
            paths.push(home.join(".local/share/applications"));
        }

        // XDG data dirs
        if let Ok(xdg_dirs) = std::env::var("XDG_DATA_DIRS") {
            for dir in xdg_dirs.split(':') {
                paths.push(PathBuf::from(dir).join("applications"));
            }
        }

        self.entries.clear();
        let mut seen_names: HashSet<String> = HashSet::new();
        let mut seen_execs: HashSet<String> = HashSet::new();

        for dir in paths {
            if let Ok(entries) = fs::read_dir(&dir) {
                for entry in entries.filter_map(|e| e.ok()) {
                    let path = entry.path();
                    if path.extension().map(|e| e == "desktop").unwrap_or(false) {
                        if let Some(desktop) = DesktopEntry::parse(&path) {
                            // Skip entries with no exec or hidden entries
                            if !desktop.exec.is_empty() {
                                // Deduplicate by name and exec command
                                let name_key = desktop.name.to_lowercase();
                                let exec_key = desktop.exec.split_whitespace().next()
                                    .unwrap_or(&desktop.exec).to_string();

                                if !seen_names.contains(&name_key) && !seen_execs.contains(&exec_key) {
                                    seen_names.insert(name_key);
                                    seen_execs.insert(exec_key);
                                    self.entries.push(desktop);
                                }
                            }
                        }
                    }
                }
            }
        }

        tracing::info!("Scanned {} desktop entries (deduplicated)", self.entries.len());
    }

    /// Get all apps that match a category, sorted by match quality (best first)
    pub fn apps_for_category(&self, category: AppCategory) -> Vec<&DesktopEntry> {
        let mut matches: Vec<_> = self.entries
            .iter()
            .filter_map(|e| {
                let score = e.match_score(category);
                if score > 0 { Some((e, score)) } else { None }
            })
            .collect();

        // Sort by score descending, then by name alphabetically
        matches.sort_by(|a, b| {
            b.1.cmp(&a.1).then_with(|| a.0.name.cmp(&b.0.name))
        });

        matches.into_iter().map(|(e, _)| e).collect()
    }

    /// Set default apps for each category (first matching app)
    fn set_defaults(&mut self) {
        for category in AppCategory::all() {
            if self.config.get_selected(category).is_none() {
                if let Some(entry) = self.apps_for_category(category).first() {
                    self.config.set_selected(category, entry.exec.clone());
                }
            }
        }
    }

    /// Get the exec command for a category (selected or default)
    pub fn get_exec(&self, category: AppCategory) -> Option<String> {
        // First try user selection
        if let Some(exec) = self.config.get_selected(category) {
            return Some(exec.to_string());
        }
        // Fall back to first matching app
        self.apps_for_category(category)
            .first()
            .map(|e| e.exec.clone())
    }

    /// Get the icon name for a category's selected app
    pub fn get_icon(&self, category: AppCategory) -> Option<String> {
        let exec = self.config.get_selected(category)?;
        self.entries
            .iter()
            .find(|e| &e.exec == exec)
            .and_then(|e| e.icon.clone())
    }

    /// Get all categories with their current selection info (cached for performance)
    pub fn get_category_info(&self) -> &[CategoryInfo] {
        &self.cached_category_info
    }

    /// Update the selected app for a category and rebuild cache
    pub fn set_category_app(&mut self, category: AppCategory, exec: String) {
        self.config.set_selected(category, exec);
        self.rebuild_cache();
        self.config.save(); // Persist changes
    }

    /// Move a category and rebuild cache
    pub fn move_category(&mut self, from: usize, to: usize) {
        self.config.move_category(from, to);
        self.rebuild_cache();
        self.config.save(); // Persist changes
    }
}

/// Information about a category for rendering
#[derive(Debug, Clone)]
pub struct CategoryInfo {
    pub category: AppCategory,
    pub name: String,
    pub selected_exec: Option<String>,
    pub available_count: usize,
    pub icon: Option<String>,
    pub color: [f32; 4],
}
