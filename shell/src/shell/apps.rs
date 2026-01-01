//! Dynamic app discovery - scans ~/Flick/apps/ for apps
//!
//! Each subdirectory in ~/Flick/apps/ is an app.
//! Optional manifest.json for custom name/icon/color.

use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use serde::{Deserialize, Serialize};

/// Get the real user's home directory
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

/// Optional manifest for an app (manifest.json in app directory)
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AppManifest {
    /// Display name (defaults to capitalized directory name)
    #[serde(default)]
    pub name: Option<String>,
    /// Icon name (defaults to directory name)
    #[serde(default)]
    pub icon: Option<String>,
    /// Color [r, g, b, a] in 0.0-1.0 range
    #[serde(default)]
    pub color: Option<[f32; 4]>,
    /// Custom exec command (defaults to run_{id}.sh)
    #[serde(default)]
    pub exec: Option<String>,
    /// Whether to show in app grid (defaults to true)
    #[serde(default = "default_true")]
    pub visible: bool,
}

fn default_true() -> bool { true }

/// A discovered app
#[derive(Debug, Clone)]
pub struct AppDef {
    /// Unique identifier (directory name)
    pub id: String,
    /// Display name
    pub name: String,
    /// Icon name (matches icons in shell/icons/)
    pub icon: String,
    /// Display color [r, g, b, a]
    pub color: [f32; 4],
    /// Exec command
    pub exec: String,
    /// Path to app directory
    pub path: PathBuf,
}

impl AppDef {
    /// Discover an app from a directory
    fn from_dir(path: &PathBuf) -> Option<Self> {
        let id = path.file_name()?.to_str()?.to_string();

        // Skip hidden directories and special cases
        if id.starts_with('.') || id == "lockscreen" || id == "shared" || id == "welcome" {
            return None;
        }

        // Check for run script or main.qml
        let run_script = path.join(format!("run_{}.sh", id));
        let main_qml = path.join("main.qml");
        if !run_script.exists() && !main_qml.exists() {
            return None;
        }

        // Load manifest if exists
        let manifest_path = path.join("manifest.json");
        let manifest: AppManifest = if manifest_path.exists() {
            fs::read_to_string(&manifest_path)
                .ok()
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or_default()
        } else {
            AppManifest::default()
        };

        // Skip if not visible
        if !manifest.visible {
            return None;
        }

        // Derive name from id (capitalize first letter)
        let default_name = {
            let mut chars = id.chars();
            match chars.next() {
                None => id.clone(),
                Some(c) => c.to_uppercase().chain(chars).collect(),
            }
        };

        // Generate default color from id hash
        let default_color = generate_color_from_id(&id);

        // Default exec command
        let home = get_real_user_home();
        let default_exec = if run_script.exists() {
            format!("sh -c \"{}/Flick/apps/{}/run_{}.sh\"", home.display(), id, id)
        } else {
            format!("qmlscene {}/Flick/apps/{}/main.qml", home.display(), id)
        };

        Some(Self {
            id: id.clone(),
            name: manifest.name.unwrap_or(default_name),
            icon: manifest.icon.unwrap_or_else(|| id.clone()),
            color: manifest.color.unwrap_or(default_color),
            exec: manifest.exec.unwrap_or(default_exec),
            path: path.clone(),
        })
    }
}

/// Generate a consistent color from an app id
fn generate_color_from_id(id: &str) -> [f32; 4] {
    // Simple hash to generate hue
    let hash: u32 = id.bytes().fold(0u32, |acc, b| acc.wrapping_mul(31).wrapping_add(b as u32));
    let hue = (hash % 360) as f32;

    // Convert HSV to RGB (saturation=0.6, value=0.7)
    let s = 0.6f32;
    let v = 0.7f32;
    let c = v * s;
    let x = c * (1.0 - ((hue / 60.0) % 2.0 - 1.0).abs());
    let m = v - c;

    let (r, g, b) = match (hue / 60.0) as u32 {
        0 => (c, x, 0.0),
        1 => (x, c, 0.0),
        2 => (0.0, c, x),
        3 => (0.0, x, c),
        4 => (x, 0.0, c),
        _ => (c, 0.0, x),
    };

    [r + m, g + m, b + m, 1.0]
}

/// User's app configuration - stores grid order
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AppConfig {
    /// Grid order (app IDs)
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

    /// Move an app in the grid
    pub fn move_app(&mut self, from: usize, to: usize) {
        if from < self.grid_order.len() && to < self.grid_order.len() {
            let app = self.grid_order.remove(from);
            self.grid_order.insert(to, app);
        }
    }
}

/// Information about an app for rendering
#[derive(Debug, Clone)]
pub struct AppInfo {
    /// App ID
    pub id: String,
    /// Display name
    pub name: String,
    /// Exec command
    pub exec: String,
    /// Icon name
    pub icon: Option<String>,
    /// Display color
    pub color: [f32; 4],
    /// Number of available alternatives (always 1 in simplified model)
    pub available_count: usize,
}

// Keep CategoryInfo as an alias for compatibility
pub type CategoryInfo = AppInfo;

/// Manager for discovering apps
pub struct AppManager {
    /// All discovered apps by ID
    pub apps: HashMap<String, AppDef>,
    /// User configuration
    pub config: AppConfig,
    /// Cached app info for rendering (in grid order)
    cached_app_info: Vec<AppInfo>,
}

impl AppManager {
    /// Create a new app manager
    pub fn new() -> Self {
        let mut manager = Self {
            apps: HashMap::new(),
            config: AppConfig::load(),
            cached_app_info: Vec::new(),
        };

        manager.scan_apps();
        manager.rebuild_cache();
        manager.config.save();
        manager
    }

    /// Scan for apps in ~/Flick/apps/ and other locations
    pub fn scan_apps(&mut self) {
        self.apps.clear();
        let home = get_real_user_home();
        eprintln!("DEBUG: Home directory is {:?}", home);

        // Scan ~/Flick/apps/
        let flick_apps = home.join("Flick/apps");
        eprintln!("DEBUG: Looking for apps in {:?}, exists={}", flick_apps, flick_apps.exists());
        if flick_apps.exists() {
            match fs::read_dir(&flick_apps) {
                Ok(entries) => {
                    for entry in entries.filter_map(|e| e.ok()) {
                        let path = entry.path();
                        eprintln!("DEBUG: Found entry {:?}, is_dir={}", path, path.is_dir());
                        if path.is_dir() {
                            match AppDef::from_dir(&path) {
                                Some(app) => {
                                    eprintln!("DEBUG: Discovered app: {}", app.id);
                                    tracing::info!("Discovered app: {} at {:?}", app.id, path);
                                    self.apps.insert(app.id.clone(), app);
                                }
                                None => {
                                    eprintln!("DEBUG: Skipped {:?} (no run script or filtered)", path);
                                }
                            }
                        }
                    }
                }
                Err(e) => {
                    eprintln!("DEBUG: Failed to read {:?}: {}", flick_apps, e);
                }
            }
        } else {
            eprintln!("DEBUG: Apps directory does not exist: {:?}", flick_apps);
        }

        // Also scan ~/flick-store/ for the store app
        let store_path = home.join("flick-store");
        if store_path.exists() && store_path.join("run_store.sh").exists() {
            let store_app = AppDef {
                id: "store".to_string(),
                name: "Store".to_string(),
                icon: "store".to_string(),
                color: [0.2, 0.6, 0.9, 1.0],
                exec: format!("sh -c \"{}/flick-store/run_store.sh\"", home.display()),
                path: store_path,
            };
            self.apps.insert("store".to_string(), store_app);
        }

        // Ensure grid_order contains all discovered apps
        let all_ids: Vec<String> = self.apps.keys().cloned().collect();
        for id in &all_ids {
            if !self.config.grid_order.contains(id) {
                self.config.grid_order.push(id.clone());
            }
        }
        // Remove apps that no longer exist
        self.config.grid_order.retain(|id| all_ids.contains(id));

        tracing::info!("Discovered {} apps", self.apps.len());
    }

    /// Rebuild the cached app info
    fn rebuild_cache(&mut self) {
        self.cached_app_info = self.config.grid_order.iter().filter_map(|id| {
            let app = self.apps.get(id)?;
            Some(AppInfo {
                id: app.id.clone(),
                name: app.name.clone(),
                exec: app.exec.clone(),
                icon: Some(app.icon.clone()),
                color: app.color,
                available_count: 1, // Always 1 in simplified model
            })
        }).collect();
    }

    /// Get exec command for an app
    pub fn get_exec(&self, app_id: &str) -> Option<String> {
        self.apps.get(app_id).map(|a| a.exec.clone())
    }

    /// Get app info (cached, in grid order)
    pub fn get_category_info(&self) -> &[AppInfo] {
        &self.cached_app_info
    }

    /// Get app ID by index in grid
    pub fn get_category_id(&self, index: usize) -> Option<&str> {
        self.config.grid_order.get(index).map(|s| s.as_str())
    }

    /// Get app info by ID
    pub fn get_category_info_by_id(&self, id: &str) -> Option<&AppInfo> {
        self.cached_app_info.iter().find(|a| a.id == id)
    }

    /// Get app definition by ID
    pub fn get_category_def(&self, id: &str) -> Option<&AppDef> {
        self.apps.get(id)
    }

    /// Move an app in the grid
    pub fn move_category(&mut self, from: usize, to: usize) {
        self.config.move_app(from, to);
        self.rebuild_cache();
        self.config.save();
    }

    /// Check if an app is customizable (always true for now)
    pub fn is_customizable(&self, _app_id: &str) -> bool {
        true
    }

    // Legacy compatibility methods
    pub fn apps_for_category(&self, _category_id: &str) -> Vec<&AppDef> {
        Vec::new() // No alternatives in simplified model
    }

    pub fn set_category_app(&mut self, _category_id: &str, _exec: String) {
        // No-op in simplified model
    }

    pub fn clear_category_app(&mut self, _category_id: &str) {
        // No-op in simplified model
    }
}

// Keep DesktopEntry for compatibility but it's not used
#[derive(Debug, Clone)]
pub struct DesktopEntry {
    pub name: String,
    pub exec: String,
    pub icon: Option<String>,
    pub categories: Vec<String>,
    pub path: PathBuf,
    pub terminal: bool,
}

impl DesktopEntry {
    pub fn is_flick_native_app(&self) -> bool {
        self.path.to_string_lossy().contains("Flick/apps/")
    }
}

// CategoryDef alias for compatibility
pub type CategoryDef = AppDef;
