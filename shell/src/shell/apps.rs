//! App category management and desktop file parsing
//!
//! Categories are loaded from config/apps.json - no hardcoded apps!
//! Users can add new app categories by editing the config file.

use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use serde::{Deserialize, Serialize};

/// Get the real user's home directory
/// When running as root via sudo, this returns the original user's home
fn get_real_user_home() -> PathBuf {
    // First try FLICK_USER (set by start_hwcomposer.sh)
    if let Ok(user) = std::env::var("FLICK_USER") {
        if !user.is_empty() && user != "root" {
            let home = format!("/home/{}", user);
            if std::path::Path::new(&home).exists() {
                return PathBuf::from(home);
            }
        }
    }

    // Then try SUDO_USER
    if let Ok(user) = std::env::var("SUDO_USER") {
        if !user.is_empty() && user != "root" {
            let home = format!("/home/{}", user);
            if std::path::Path::new(&home).exists() {
                return PathBuf::from(home);
            }
        }
    }

    // Fallback to droidian if it exists
    if std::path::Path::new("/home/droidian").exists() {
        return PathBuf::from("/home/droidian");
    }

    // Last resort: use HOME env var
    std::env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/root"))
}

/// Get the Flick shell directory (where config/apps.json lives)
fn get_flick_shell_dir() -> PathBuf {
    // Try common locations
    let home = get_real_user_home();
    let candidates = [
        home.join("Flick/shell"),
        PathBuf::from("/home/droidian/Flick/shell"),
        PathBuf::from("/home/david/Flick/shell"),
    ];

    for path in &candidates {
        if path.join("config/apps.json").exists() {
            return path.clone();
        }
    }

    // Fallback
    home.join("Flick/shell")
}

/// Category definition loaded from config/apps.json
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CategoryDef {
    /// Unique identifier (e.g., "phone", "messages", "passwordsafe")
    pub id: String,
    /// Display name (e.g., "Phone", "Messages", "Passwords")
    pub name: String,
    /// Icon name (matches icons in shell/icons/)
    pub icon: String,
    /// Default color [r, g, b, a] in 0.0-1.0 range
    pub color: [f32; 4],
    /// Default exec command for Flick's built-in app
    pub default_exec: String,
    /// Desktop categories to match (e.g., ["Telephony"], ["WebBrowser", "Network"])
    pub desktop_categories: Vec<String>,
    /// Whether users can change which app is used (false for Settings)
    #[serde(default = "default_true")]
    pub customizable: bool,
}

fn default_true() -> bool { true }

impl CategoryDef {
    /// Check if a desktop entry matches this category
    pub fn matches_entry(&self, entry: &DesktopEntry) -> u32 {
        let mut score = 0u32;

        for cat in &entry.categories {
            if self.desktop_categories.contains(cat) {
                score += 10;
            }
        }

        // Boost terminal apps
        if self.id == "terminal" && entry.terminal {
            score += 5;
        }

        // Boost Flick native apps
        if entry.is_flick_native_app() {
            score += 50;
        }

        score
    }
}

/// Categories configuration loaded from JSON
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CategoriesConfig {
    pub categories: Vec<CategoryDef>,
}

impl CategoriesConfig {
    /// Load categories from config/apps.json
    pub fn load() -> Self {
        let shell_dir = get_flick_shell_dir();
        let config_path = shell_dir.join("config/apps.json");

        tracing::info!("Loading app categories from {:?}", config_path);

        match fs::read_to_string(&config_path) {
            Ok(contents) => {
                match serde_json::from_str::<Self>(&contents) {
                    Ok(config) => {
                        tracing::info!("Loaded {} categories from config", config.categories.len());
                        return config;
                    }
                    Err(e) => {
                        tracing::error!("Failed to parse apps.json: {:?}", e);
                    }
                }
            }
            Err(e) => {
                tracing::error!("Failed to read apps.json: {:?}", e);
            }
        }

        // Return empty config on error - this is a critical failure
        tracing::error!("Using empty categories - apps.json not found!");
        Self { categories: Vec::new() }
    }

    /// Get a category by ID
    pub fn get(&self, id: &str) -> Option<&CategoryDef> {
        self.categories.iter().find(|c| c.id == id)
    }

    /// Get all category IDs in order
    pub fn ids(&self) -> Vec<String> {
        self.categories.iter().map(|c| c.id.clone()).collect()
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

    /// Check if this is a Flick native app (lives in ~/Flick/apps/)
    pub fn is_flick_native_app(&self) -> bool {
        self.path.to_string_lossy().contains("Flick/apps/")
    }
}

/// User's app configuration - stores selected apps and grid order
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AppConfig {
    /// Selected app exec command per category ID
    #[serde(default)]
    pub selections: HashMap<String, String>,
    /// Grid order (category IDs)
    #[serde(default)]
    pub grid_order: Vec<String>,
}

impl AppConfig {
    /// Get the config file path
    fn config_path() -> Option<PathBuf> {
        let home = get_real_user_home();
        Some(home.join(".local/state/flick/app_config.json"))
    }

    /// Load config from file
    pub fn load() -> Self {
        if let Some(path) = Self::config_path() {
            if let Ok(contents) = fs::read_to_string(&path) {
                if let Ok(config) = serde_json::from_str::<Self>(&contents) {
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
            if let Some(parent) = path.parent() {
                let _ = fs::create_dir_all(parent);
            }
            if let Ok(json) = serde_json::to_string_pretty(self) {
                if let Err(e) = fs::write(&path, json) {
                    tracing::warn!("Failed to save app config: {:?}", e);
                }
            }
        }
    }

    /// Get selected exec for a category
    pub fn get_selected(&self, category_id: &str) -> Option<&str> {
        self.selections.get(category_id).map(|s| s.as_str())
    }

    /// Set selected app for a category
    pub fn set_selected(&mut self, category_id: &str, exec: String) {
        self.selections.insert(category_id.to_string(), exec);
    }

    /// Move a category in the grid
    pub fn move_category(&mut self, from: usize, to: usize) {
        if from < self.grid_order.len() && to < self.grid_order.len() {
            let cat = self.grid_order.remove(from);
            self.grid_order.insert(to, cat);
        }
    }
}

/// Information about a category for rendering
#[derive(Debug, Clone)]
pub struct CategoryInfo {
    /// Category ID
    pub id: String,
    /// Display name
    pub name: String,
    /// Selected exec command
    pub selected_exec: Option<String>,
    /// Number of available apps
    pub available_count: usize,
    /// Icon name
    pub icon: Option<String>,
    /// Display color
    pub color: [f32; 4],
}

/// Manager for discovering and categorizing installed apps
pub struct AppManager {
    /// Category definitions from config
    pub categories: CategoriesConfig,
    /// All discovered desktop entries
    pub entries: Vec<DesktopEntry>,
    /// User configuration
    pub config: AppConfig,
    /// Cached category info for fast rendering
    cached_category_info: Vec<CategoryInfo>,
}

impl AppManager {
    /// Create a new app manager
    pub fn new() -> Self {
        let categories = CategoriesConfig::load();
        let mut config = AppConfig::load();

        // Ensure grid_order has all categories
        let all_ids = categories.ids();
        for id in &all_ids {
            if !config.grid_order.contains(id) {
                config.grid_order.push(id.clone());
            }
        }
        // Remove any categories that no longer exist
        config.grid_order.retain(|id| all_ids.contains(id));

        let mut manager = Self {
            categories,
            entries: Vec::new(),
            config,
            cached_category_info: Vec::new(),
        };

        manager.scan_apps();
        manager.set_defaults();
        manager.config.save();
        manager.rebuild_cache();
        manager
    }

    /// Rebuild the cached category info
    fn rebuild_cache(&mut self) {
        self.cached_category_info = self.config.grid_order.iter().filter_map(|id| {
            let cat_def = self.categories.get(id)?;
            let selected_exec = self.config.get_selected(id).map(|s| s.to_string());
            let available_apps = self.apps_for_category(id);

            Some(CategoryInfo {
                id: id.clone(),
                name: cat_def.name.clone(),
                selected_exec,
                available_count: available_apps.len(),
                icon: Some(cat_def.icon.clone()),
                color: cat_def.color,
            })
        }).collect();
    }

    /// Scan for .desktop files
    pub fn scan_apps(&mut self) {
        use std::collections::HashSet;

        let mut paths = Vec::new();

        // System applications
        paths.push(PathBuf::from("/usr/share/applications"));
        paths.push(PathBuf::from("/usr/local/share/applications"));

        // User applications
        let home = get_real_user_home();
        paths.push(home.join(".local/share/applications"));

        // Flick's native apps
        let flick_apps = home.join("Flick/apps");
        if flick_apps.exists() {
            if let Ok(entries) = fs::read_dir(&flick_apps) {
                for entry in entries.filter_map(|e| e.ok()) {
                    let path = entry.path();
                    if path.is_dir() {
                        paths.push(path);
                    }
                }
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
                            if !desktop.exec.is_empty() {
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

        tracing::info!("Scanned {} desktop entries", self.entries.len());
    }

    /// Get apps matching a category ID
    pub fn apps_for_category(&self, category_id: &str) -> Vec<&DesktopEntry> {
        let cat_def = match self.categories.get(category_id) {
            Some(c) => c,
            None => return Vec::new(),
        };

        let mut matches: Vec<_> = self.entries
            .iter()
            .filter_map(|e| {
                let score = cat_def.matches_entry(e);
                if score > 0 { Some((e, score)) } else { None }
            })
            .collect();

        matches.sort_by(|a, b| {
            b.1.cmp(&a.1).then_with(|| a.0.name.cmp(&b.0.name))
        });

        matches.into_iter().map(|(e, _)| e).collect()
    }

    /// Set default apps for each category
    fn set_defaults(&mut self) {
        for cat_def in &self.categories.categories {
            // Skip if user already has a selection
            if self.config.get_selected(&cat_def.id).is_some() {
                continue;
            }

            // Use the default_exec from config
            if !cat_def.default_exec.is_empty() {
                // Expand $HOME in the exec string
                let home = get_real_user_home();
                let exec = cat_def.default_exec.replace("$HOME", &home.to_string_lossy());
                self.config.set_selected(&cat_def.id, exec);
            }
        }
    }

    /// Get exec command for a category
    pub fn get_exec(&self, category_id: &str) -> Option<String> {
        // First try user selection
        if let Some(exec) = self.config.get_selected(category_id) {
            return Some(exec.to_string());
        }

        // Fall back to default from config
        if let Some(cat_def) = self.categories.get(category_id) {
            if !cat_def.default_exec.is_empty() {
                let home = get_real_user_home();
                return Some(cat_def.default_exec.replace("$HOME", &home.to_string_lossy()));
            }
        }

        None
    }

    /// Get category info (cached)
    pub fn get_category_info(&self) -> &[CategoryInfo] {
        &self.cached_category_info
    }

    /// Get a category definition by ID
    pub fn get_category_def(&self, id: &str) -> Option<&CategoryDef> {
        self.categories.get(id)
    }

    /// Get category ID by index in grid
    pub fn get_category_id(&self, index: usize) -> Option<&str> {
        self.config.grid_order.get(index).map(|s| s.as_str())
    }

    /// Get category info by ID
    pub fn get_category_info_by_id(&self, id: &str) -> Option<&CategoryInfo> {
        self.cached_category_info.iter().find(|c| c.id == id)
    }

    /// Update selected app for a category
    pub fn set_category_app(&mut self, category_id: &str, exec: String) {
        self.config.set_selected(category_id, exec);
        self.rebuild_cache();
        self.config.save();
    }

    /// Clear selected app (reverts to default)
    pub fn clear_category_app(&mut self, category_id: &str) {
        self.config.selections.remove(category_id);
        self.rebuild_cache();
        self.config.save();
    }

    /// Move a category in the grid
    pub fn move_category(&mut self, from: usize, to: usize) {
        self.config.move_category(from, to);
        self.rebuild_cache();
        self.config.save();
    }

    /// Check if a category is customizable
    pub fn is_customizable(&self, category_id: &str) -> bool {
        self.categories.get(category_id)
            .map(|c| c.customizable)
            .unwrap_or(true)
    }
}
