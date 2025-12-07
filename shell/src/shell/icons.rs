//! Icon loading and caching for app grid
//!
//! Loads PNG icons from standard XDG icon directories and caches them.

use std::collections::HashMap;
use std::path::PathBuf;
use std::fs;

/// Icon cache storing loaded RGBA pixel data
pub struct IconCache {
    /// Cached icons: icon_name -> (width, height, rgba_data)
    cache: HashMap<String, Option<IconData>>,
    /// Preferred icon size
    icon_size: u32,
}

/// Loaded icon data
#[derive(Clone)]
pub struct IconData {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u8>, // RGBA bytes
}

impl IconCache {
    pub fn new(icon_size: u32) -> Self {
        Self {
            cache: HashMap::new(),
            icon_size,
        }
    }

    /// Get or load an icon by name (requires mutable access)
    pub fn get(&mut self, icon_name: &str) -> Option<&IconData> {
        if !self.cache.contains_key(icon_name) {
            let icon_data = self.load_icon(icon_name);
            self.cache.insert(icon_name.to_string(), icon_data);
        }
        self.cache.get(icon_name).and_then(|o| o.as_ref())
    }

    /// Get an already-cached icon (non-mutable, for use in render loops)
    /// Returns None if the icon hasn't been loaded yet
    pub fn get_cached(&self, icon_name: &str) -> Option<&IconData> {
        self.cache.get(icon_name).and_then(|o| o.as_ref())
    }

    /// Preload icons for the given names (call this before rendering)
    pub fn preload(&mut self, icon_names: &[&str]) {
        for name in icon_names {
            let _ = self.get(name);
        }
    }

    /// Load an icon from disk
    fn load_icon(&self, icon_name: &str) -> Option<IconData> {
        // If it's already a path, try loading directly
        if icon_name.starts_with('/') {
            return self.load_icon_file(icon_name);
        }

        // Search in standard icon directories
        let icon_path = self.find_icon(icon_name)?;
        self.load_icon_file(&icon_path)
    }

    /// Find icon file path by name
    fn find_icon(&self, icon_name: &str) -> Option<String> {
        // Icon search paths in priority order
        let search_paths = self.get_icon_search_paths();

        // Sizes to try (prefer larger for quality, will be scaled down)
        let sizes = ["256x256", "128x128", "96x96", "64x64", "48x48", "scalable"];

        // Categories to search
        let categories = ["apps", "applications", "mimetypes", "places", "devices", "actions", "status"];

        for base_path in &search_paths {
            for size in &sizes {
                for category in &categories {
                    // Try PNG first
                    let png_path = format!("{}/{}/{}/{}.png", base_path, size, category, icon_name);
                    if fs::metadata(&png_path).is_ok() {
                        return Some(png_path);
                    }
                }
            }

            // Also try direct path (some themes put icons at root)
            let direct_png = format!("{}/{}.png", base_path, icon_name);
            if fs::metadata(&direct_png).is_ok() {
                return Some(direct_png);
            }
        }

        // Try pixmaps directory as fallback
        let pixmap_paths = [
            format!("/usr/share/pixmaps/{}.png", icon_name),
            format!("/usr/share/pixmaps/{}.xpm", icon_name),
        ];
        for path in &pixmap_paths {
            if fs::metadata(path).is_ok() {
                return Some(path.clone());
            }
        }

        tracing::debug!("Icon not found: {}", icon_name);
        None
    }

    /// Get list of icon search paths
    fn get_icon_search_paths(&self) -> Vec<String> {
        let mut paths = Vec::new();

        // User icons
        if let Ok(home) = std::env::var("HOME") {
            paths.push(format!("{}/.local/share/icons/hicolor", home));
            paths.push(format!("{}/.icons/hicolor", home));
        }

        // System icon themes (prefer Adwaita, then hicolor as fallback)
        let themes = ["Adwaita", "gnome", "hicolor", "mate"];
        for theme in &themes {
            paths.push(format!("/usr/share/icons/{}", theme));
        }

        paths
    }

    /// Load icon from a specific file path
    fn load_icon_file(&self, path: &str) -> Option<IconData> {
        // Only support PNG for now
        if !path.ends_with(".png") {
            tracing::debug!("Skipping non-PNG icon: {}", path);
            return None;
        }

        let data = fs::read(path).ok()?;

        let img = image::load_from_memory(&data).ok()?;
        let rgba = img.to_rgba8();

        // Resize to target size if needed
        let (width, height) = (rgba.width(), rgba.height());
        let target = self.icon_size;

        let final_img = if width != target || height != target {
            image::imageops::resize(&rgba, target, target, image::imageops::FilterType::Lanczos3)
        } else {
            rgba
        };

        tracing::info!("Loaded icon: {} ({}x{} -> {}x{})", path, width, height, target, target);

        Some(IconData {
            width: target,
            height: target,
            data: final_img.into_raw(),
        })
    }
}

/// Resolve an icon name from a .desktop file to a loadable path or name
pub fn resolve_icon_name(icon: &str) -> String {
    // If it's already a full path, return as-is
    if icon.starts_with('/') {
        return icon.to_string();
    }

    // Remove any file extension if present (some .desktop files include it)
    let name = icon.strip_suffix(".png")
        .or_else(|| icon.strip_suffix(".svg"))
        .or_else(|| icon.strip_suffix(".xpm"))
        .unwrap_or(icon);

    name.to_string()
}
