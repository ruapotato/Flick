//! Icon loading and caching for app grid
//!
//! Loads PNG and SVG icons from standard XDG icon directories and caches them.

use std::collections::HashMap;
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

        // Extensions to try (prefer SVG for quality, PNG as fallback)
        let extensions = ["svg", "png"];

        // Try both original name and lowercase (our Papirus icons are lowercase)
        let names_to_try = [icon_name.to_string(), icon_name.to_lowercase()];

        for name in &names_to_try {
            for base_path in &search_paths {
                for size in &sizes {
                    for category in &categories {
                        for ext in &extensions {
                            let path = format!("{}/{}/{}/{}.{}", base_path, size, category, name, ext);
                            if fs::metadata(&path).is_ok() {
                                return Some(path);
                            }
                        }
                    }
                }

                // Also try direct path (some themes put icons at root)
                for ext in &extensions {
                    let direct_path = format!("{}/{}.{}", base_path, name, ext);
                    if fs::metadata(&direct_path).is_ok() {
                        return Some(direct_path);
                    }
                }
            }

            // Try pixmaps directory as fallback
            let pixmap_paths = [
                format!("/usr/share/pixmaps/{}.png", name),
                format!("/usr/share/pixmaps/{}.svg", name),
                format!("/usr/share/pixmaps/{}.xpm", name),
            ];
            for path in &pixmap_paths {
                if fs::metadata(path).is_ok() {
                    return Some(path.clone());
                }
            }
        }

        tracing::debug!("Icon not found: {}", icon_name);
        None
    }

    /// Get list of icon search paths
    fn get_icon_search_paths(&self) -> Vec<String> {
        let mut paths = Vec::new();

        // Flick's own icons (highest priority)
        if let Ok(home) = std::env::var("HOME") {
            paths.push(format!("{}/Flick/icons/apps", home));
            paths.push(format!("{}/Flick/icons/ui", home));
        }

        // Hardcoded paths for when running as root (compositor runs as root on phone)
        // Check common user home directories
        for user_dir in &["/home/droidian", "/home/user", "/home/phablet"] {
            if fs::metadata(user_dir).is_ok() {
                paths.push(format!("{}/Flick/icons/apps", user_dir));
                paths.push(format!("{}/Flick/icons/ui", user_dir));
            }
        }

        // Also check relative to executable for development
        if let Ok(exe_path) = std::env::current_exe() {
            if let Some(shell_dir) = exe_path.parent().and_then(|p| p.parent()) {
                let icons_path = shell_dir.join("icons").join("apps");
                if icons_path.exists() {
                    paths.push(icons_path.to_string_lossy().to_string());
                }
            }
        }

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
        if path.ends_with(".svg") {
            self.load_svg_file(path)
        } else if path.ends_with(".png") {
            self.load_png_file(path)
        } else {
            tracing::debug!("Skipping unsupported icon format: {}", path);
            None
        }
    }

    /// Load a PNG icon file
    fn load_png_file(&self, path: &str) -> Option<IconData> {
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

        tracing::info!("Loaded PNG icon: {} ({}x{} -> {}x{})", path, width, height, target, target);

        Some(IconData {
            width: target,
            height: target,
            data: final_img.into_raw(),
        })
    }

    /// Load an SVG icon file and render to RGBA pixels
    fn load_svg_file(&self, path: &str) -> Option<IconData> {
        let svg_data = fs::read(path).ok()?;
        let target = self.icon_size;

        // Parse the SVG
        let options = resvg::usvg::Options::default();
        let tree = resvg::usvg::Tree::from_data(&svg_data, &options).ok()?;

        // Calculate scaling to fit target size
        let svg_size = tree.size();
        let scale_x = target as f32 / svg_size.width();
        let scale_y = target as f32 / svg_size.height();
        let scale = scale_x.min(scale_y);

        // Create a pixmap to render into
        let mut pixmap = resvg::tiny_skia::Pixmap::new(target, target)?;

        // Center the icon in the target area
        let scaled_width = svg_size.width() * scale;
        let scaled_height = svg_size.height() * scale;
        let offset_x = (target as f32 - scaled_width) / 2.0;
        let offset_y = (target as f32 - scaled_height) / 2.0;

        // Render SVG to pixmap
        let transform = resvg::tiny_skia::Transform::from_scale(scale, scale)
            .post_translate(offset_x, offset_y);
        resvg::render(&tree, transform, &mut pixmap.as_mut());

        tracing::info!("Loaded SVG icon: {} ({}x{} -> {}x{})",
            path, svg_size.width() as u32, svg_size.height() as u32, target, target);

        Some(IconData {
            width: target,
            height: target,
            data: pixmap.data().to_vec(),
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
