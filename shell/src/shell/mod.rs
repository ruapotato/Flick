//! Integrated shell UI - rendered directly by the compositor
//!
//! Components:
//! - Lock screen (PIN, pattern, password authentication - external QML app)
//! - App grid (home screen)
//! - App switcher (Android-style card stack)
//! - Quick settings panel (notifications/toggles)
//! - Gesture overlays (close indicators)

pub mod primitives;
pub mod app_grid;
pub mod app_switcher;
pub mod quick_settings;
pub mod overlay;
pub mod text;
pub mod apps;
pub mod icons;
pub mod lock_screen;
pub mod slint_ui;
pub mod presage;
pub mod word_prediction;

use smithay::utils::{Logical, Point, Size};
use crate::input::{Edge, GestureEvent};
use std::cell::Cell;
use std::path::PathBuf;

/// Get the Flick project root directory
/// Checks in order: FLICK_ROOT env var, executable's grandparent dir, HOME/Flick
pub fn get_flick_root() -> std::path::PathBuf {
    // 1. Check FLICK_ROOT env var
    if let Ok(root) = std::env::var("FLICK_ROOT") {
        return std::path::PathBuf::from(root);
    }

    // 2. Try to find from executable path (e.g., /path/to/Flick/shell/target/release/flick)
    if let Ok(exe) = std::env::current_exe() {
        // Go up from flick -> release -> target -> shell -> Flick
        if let Some(flick_root) = exe.parent()  // release/
            .and_then(|p| p.parent())           // target/
            .and_then(|p| p.parent())           // shell/
            .and_then(|p| p.parent())           // Flick/
        {
            if flick_root.join("apps").exists() {
                return flick_root.to_path_buf();
            }
        }
    }

    // 3. Fallback to HOME/Flick
    let home = std::env::var("HOME").unwrap_or_else(|_| "/home/droidian".to_string());
    std::path::PathBuf::from(home).join("Flick")
}

/// Lock screen executable path (QML app launched via qmlscene)
pub fn get_lockscreen_exec() -> String {
    get_flick_root()
        .join("apps/lockscreen/main.qml")
        .to_string_lossy()
        .to_string()
}

/// Get the command to launch the lock screen (wrapper script that handles unlock signal)
pub fn get_lockscreen_command() -> (String, Vec<String>) {
    let wrapper_path = get_flick_root()
        .join("apps/lockscreen/run_lockscreen.sh")
        .to_string_lossy()
        .to_string();

    // Use wrapper script that captures output and creates unlock signal file
    (
        wrapper_path,
        vec![]
    )
}

/// Path to unlock signal file (written by lock screen app on successful auth)
pub fn unlock_signal_path() -> PathBuf {
    // Use FLICK_STATE_DIR if set (same as QML lockscreen uses)
    // Otherwise try SUDO_USER's home (when running via sudo), then HOME
    if let Ok(state_dir) = std::env::var("FLICK_STATE_DIR") {
        return PathBuf::from(state_dir).join("unlock_signal");
    }

    // When running via sudo, HOME is /root but we need the real user's home
    let home = if let Ok(sudo_user) = std::env::var("SUDO_USER") {
        format!("/home/{}", sudo_user)
    } else {
        std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string())
    };
    PathBuf::from(home).join(".local/state/flick/unlock_signal")
}

/// App definition for the launcher
#[derive(Debug, Clone)]
pub struct AppInfo {
    pub name: String,
    pub exec: String,
    pub color: [f32; 4], // RGBA
}

impl AppInfo {
    pub fn new(name: &str, exec: &str, color: [f32; 4]) -> Self {
        Self {
            name: name.to_string(),
            exec: exec.to_string(),
            color,
        }
    }
}

/// Default apps for the launcher
pub fn default_apps() -> Vec<AppInfo> {
    vec![
        // X11 apps (via XWayland) - more likely to work
        AppInfo::new("XTerm", "xterm", [0.2, 0.6, 0.3, 1.0]),      // Green
        AppInfo::new("XCalc", "xcalc", [0.3, 0.5, 0.8, 1.0]),      // Blue
        AppInfo::new("XClock", "xclock", [0.8, 0.6, 0.2, 1.0]),    // Orange
        AppInfo::new("XEyes", "xeyes", [0.7, 0.3, 0.5, 1.0]),      // Purple
        AppInfo::new("XEdit", "xedit", [0.5, 0.5, 0.5, 1.0]),      // Gray
        AppInfo::new("XLoad", "xload", [0.6, 0.4, 0.3, 1.0]),      // Brown
    ]
}

/// Current shell view state
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ShellView {
    /// Lock screen - must authenticate to proceed
    LockScreen,
    /// Showing a running app (shell hidden)
    App,
    /// Home screen with app grid
    Home,
    /// App switcher overlay
    Switcher,
    /// Quick settings / notifications panel
    QuickSettings,
    /// Pick default app for a category
    PickDefault,
}

/// Active gesture state for animations
#[derive(Debug, Clone)]
pub struct GestureState {
    /// Which edge the gesture started from (if any)
    pub edge: Option<Edge>,
    /// Progress 0.0 to 1.0+
    pub progress: f64,
    /// Velocity for momentum
    pub velocity: f64,
    /// Whether gesture completed successfully
    pub completed: bool,
}

impl Default for GestureState {
    fn default() -> Self {
        Self {
            edge: None,
            progress: 0.0,
            velocity: 0.0,
            completed: false,
        }
    }
}

/// Menu level for long press menu
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum MenuLevel {
    /// Main menu with Move / Change Default options
    Main,
    /// Submenu showing available apps for the category
    SelectApp,
}

/// Action returned from menu interaction
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum MenuAction {
    /// Enter wiggle mode for rearranging icons
    EnterWiggleMode,
    /// Show the app list submenu
    ShowAppList,
    /// An app was selected as the new default
    AppSelected,
}

/// Long press menu for app categories
#[derive(Debug, Clone)]
pub struct LongPressMenu {
    /// The category ID being configured
    pub category_id: String,
    /// Position of the menu (where long press occurred)
    pub position: Point<f64, Logical>,
    /// Available apps for this category
    pub available_apps: Vec<apps::DesktopEntry>,
    /// Currently highlighted option
    pub highlighted: Option<usize>,
    /// Current menu level
    pub level: MenuLevel,
    /// Scroll offset for app list (when list is long)
    pub scroll_offset: f64,
}

/// Shell state - manages UI views and animations
pub struct Shell {
    /// Current view
    pub view: ShellView,
    /// Screen size
    pub screen_size: Size<i32, Logical>,
    /// Active gesture for animations
    pub gesture: GestureState,
    /// App manager (handles categories and installed apps)
    pub app_manager: apps::AppManager,
    /// Legacy apps for compatibility (will be removed)
    pub apps: Vec<AppInfo>,
    /// Selected app index (for touch feedback)
    pub selected_app: Option<usize>,
    /// Scroll offset for app switcher
    pub switcher_scroll: f64,
    /// Switcher momentum velocity (pixels per second)
    pub switcher_velocity: f64,
    /// Switcher is animating (momentum or snap)
    pub switcher_animating: bool,
    /// Target scroll position for snap animation
    pub switcher_snap_target: Option<f64>,
    /// Last time switcher was updated (for delta time)
    pub switcher_last_update: Option<std::time::Instant>,
    /// Touch times for velocity calculation
    pub switcher_touch_times: Vec<(f64, std::time::Instant)>, // (x position, time)
    /// Switcher enter animation active (shrink from app to card)
    pub switcher_enter_anim: bool,
    /// When switcher enter animation started
    pub switcher_enter_start: Option<std::time::Instant>,
    /// Scroll offset for app grid (home screen)
    pub home_scroll: f64,
    /// Horizontal push offset for edge swipe gestures (-1.0 to 1.0)
    pub home_push_offset: f64,
    /// Home scroll momentum velocity (pixels per second)
    pub home_scroll_velocity: f64,
    /// Home scroll is animating (momentum)
    pub home_scroll_animating: bool,
    /// Last time home scroll was updated (for delta time)
    pub home_scroll_last_update: Option<std::time::Instant>,
    /// Touch times for velocity calculation (y position, time)
    pub home_scroll_touch_times: Vec<(f64, std::time::Instant)>,
    /// Touch tracking for scrolling (home screen - vertical)
    pub scroll_touch_start_y: Option<f64>,
    pub scroll_touch_last_y: Option<f64>,
    /// Touch tracking for app switcher (horizontal)
    pub switcher_touch_start_x: Option<f64>,
    pub switcher_touch_last_x: Option<f64>,
    /// Pending app launch (exec command) - waits for touch up to confirm tap vs scroll
    pub pending_app_launch: Option<String>,
    /// Pending category ID for long press menu
    pub pending_category_id: Option<String>,
    /// Pending switcher window index - waits for touch up to confirm tap vs scroll
    pub pending_switcher_index: Option<usize>,
    /// Whether current touch is scrolling (moved significantly)
    pub is_scrolling: bool,
    /// Long press tracking
    pub long_press_start: Option<std::time::Instant>,
    pub long_press_category_id: Option<String>,
    pub long_press_position: Option<Point<f64, Logical>>,
    /// Quick Settings panel state
    pub quick_settings: quick_settings::QuickSettingsPanel,
    /// Quick settings touch tracking
    pub qs_touch_start_y: Option<f64>,
    pub qs_touch_last_y: Option<f64>,
    /// Pending toggle index for Quick Settings
    pub pending_toggle_index: Option<usize>,
    /// Long press menu state
    pub long_press_menu: Option<LongPressMenu>,
    /// Flag to prevent closing menu on same touch that opened it
    pub menu_just_opened: bool,
    /// Wiggle mode for rearranging icons
    pub wiggle_mode: bool,
    /// When wiggle mode started (for animation)
    pub wiggle_start_time: Option<std::time::Instant>,
    /// Category being dragged (index in grid_order)
    pub dragging_index: Option<usize>,
    /// Initial drag start position (for detecting drag vs tap)
    pub drag_start_position: Option<Point<f64, Logical>>,
    /// Current drag position (updated during drag)
    pub drag_position: Option<Point<f64, Logical>>,
    /// Whether popup menu is showing (for Slint state sync)
    pub popup_showing: bool,
    /// Category ID for popup menu / pick default view
    pub popup_category_id: Option<String>,
    /// Flag to prevent processing touch on same event that opened pick default view
    pub pick_default_just_opened: bool,
    /// Context menu state (copy/paste circular menu)
    pub context_menu_active: bool,
    /// Context menu center position
    pub context_menu_position: Option<Point<f64, Logical>>,
    /// Context menu highlighted option (0=none, 1=copy, 2=paste)
    pub context_menu_highlight: i32,
    /// Touch slot for context menu (to track the finger)
    pub context_menu_slot: Option<i32>,
    /// Context menu timer start (for 500ms long press detection)
    pub context_menu_start: Option<std::time::Instant>,
    /// Current clipboard content (for display in context menu)
    pub clipboard_content: Option<String>,
    /// Last time we checked the clipboard
    pub clipboard_last_check: std::time::Instant,
    /// Show "Copied!" popup notification
    pub show_copied_popup: bool,
    /// Text shown in copied popup
    pub copied_popup_text: String,
    /// When the copied popup was shown (for auto-hide)
    pub copied_popup_start: Option<std::time::Instant>,
    /// Position for copied popup (where finger was)
    pub copied_popup_position: Option<Point<f64, Logical>>,
    /// System menu (power options) is active
    pub system_menu_active: bool,
    /// Icon cache for app icons
    pub icon_cache: icons::IconCache,
    /// Lock screen configuration
    pub lock_config: lock_screen::LockConfig,
    /// Lock screen runtime state (kept for legacy compatibility, not actively used)
    pub lock_state: lock_screen::LockScreenState,
    /// Slint UI shell (optional - may fail to initialize)
    pub slint_ui: Option<slint_ui::SlintShell>,
    /// Whether external lock screen app is active
    pub lock_screen_active: bool,
    /// Time of last unlock (to prevent spurious App view switches)
    pub last_unlock_time: Option<std::time::Instant>,
    /// Time of last activity on lock screen (for auto-dim)
    pub lock_screen_last_activity: std::time::Instant,
    /// Whether lock screen is dimmed (power saving mode)
    pub lock_screen_dimmed: bool,
    /// Whether display is blanked (powered off)
    pub display_blanked: bool,
    /// View before locking (to restore after unlock)
    pub pre_lock_view: ShellView,
    /// Whether an app window was open before locking
    pub pre_lock_had_app: bool,
    /// App to open after unlock (from notification tap)
    pub unlock_open_app: Option<String>,
    /// App was launched after unlock (allows new window to switch to App view)
    pub unlock_app_launched: bool,
    /// Time of last tap on dimmed lock screen (for double-tap detection)
    pub lock_screen_last_tap: Option<std::time::Instant>,
    /// Screen timeout in seconds (0 = never, from display settings)
    pub screen_timeout_secs: u64,
    /// Text scale factor (1.0 = normal, 2.0 = double size, etc.)
    pub text_scale: f32,
    /// Whether UI icons have been loaded and set to Slint (Cell for interior mutability)
    pub ui_icons_loaded: Cell<bool>,
    /// Word predictor for on-screen keyboard
    pub word_predictor: word_prediction::WordPredictor,
}

impl Shell {
    pub fn new(screen_size: Size<i32, Logical>) -> Self {
        // Load lock config first to determine initial view
        let lock_config = lock_screen::LockConfig::load();
        let lock_state = lock_screen::LockScreenState::new(&lock_config);

        // Start at lock screen if lock is configured, otherwise home
        let initial_view = if lock_config.method == lock_screen::LockMethod::None {
            ShellView::Home
        } else {
            ShellView::LockScreen
        };

        // Try to initialize Slint UI (may fail on some platforms)
        let slint_ui = match std::panic::catch_unwind(|| {
            slint_ui::SlintShell::new(screen_size)
        }) {
            Ok(ui) => {
                tracing::info!("Slint UI initialized successfully");
                // Lock screen is now QML-based, mode is read from config by QML
                // Initialize text scale from config
                let text_scale = Self::load_text_scale();
                ui.set_text_scale(text_scale);
                tracing::info!("Text scale initialized to: {}", text_scale);
                // Initialize wallpaper from config
                if let Some(wallpaper) = Self::load_wallpaper_image() {
                    ui.set_wallpaper(wallpaper);
                    ui.set_has_wallpaper(true);
                    tracing::info!("Wallpaper loaded and set");
                }
                Some(ui)
            }
            Err(e) => {
                tracing::warn!("Failed to initialize Slint UI: {:?}", e);
                None
            }
        };

        let mut shell = Self {
            view: initial_view,
            screen_size,
            gesture: GestureState::default(),
            app_manager: apps::AppManager::new(),
            apps: default_apps(),
            selected_app: None,
            switcher_scroll: 0.0,
            switcher_velocity: 0.0,
            switcher_animating: false,
            switcher_snap_target: None,
            switcher_last_update: None,
            switcher_touch_times: Vec::new(),
            switcher_enter_anim: false,
            switcher_enter_start: None,
            home_scroll: 0.0,
            home_push_offset: 0.0,
            home_scroll_velocity: 0.0,
            home_scroll_animating: false,
            home_scroll_last_update: None,
            home_scroll_touch_times: Vec::new(),
            scroll_touch_start_y: None,
            scroll_touch_last_y: None,
            switcher_touch_start_x: None,
            switcher_touch_last_x: None,
            pending_app_launch: None,
            pending_category_id: None,
            pending_switcher_index: None,
            is_scrolling: false,
            long_press_start: None,
            long_press_category_id: None,
            long_press_position: None,
            quick_settings: quick_settings::QuickSettingsPanel::new(screen_size),
            qs_touch_start_y: None,
            qs_touch_last_y: None,
            pending_toggle_index: None,
            long_press_menu: None,
            menu_just_opened: false,
            wiggle_mode: false,
            wiggle_start_time: None,
            dragging_index: None,
            drag_start_position: None,
            drag_position: None,
            popup_showing: false,
            popup_category_id: None,
            pick_default_just_opened: false,
            context_menu_active: false,
            context_menu_position: None,
            context_menu_highlight: 0,
            context_menu_slot: None,
            context_menu_start: None,
            clipboard_content: None,
            clipboard_last_check: std::time::Instant::now(),
            show_copied_popup: false,
            copied_popup_text: String::new(),
            copied_popup_start: None,
            copied_popup_position: None,
            system_menu_active: false,
            icon_cache: icons::IconCache::new(128), // 128px icons for larger tiles
            lock_config: lock_config.clone(),
            lock_state,
            slint_ui,
            // Set lock_screen_active based on whether we start with a lock screen
            lock_screen_active: lock_config.method != lock_screen::LockMethod::None,
            last_unlock_time: None,
            lock_screen_last_activity: std::time::Instant::now(),
            lock_screen_dimmed: false,
            display_blanked: false,
            pre_lock_view: ShellView::Home,
            pre_lock_had_app: false,
            unlock_open_app: None,
            unlock_app_launched: false,
            lock_screen_last_tap: None,
            screen_timeout_secs: Self::load_screen_timeout(),
            text_scale: Self::load_text_scale(),
            ui_icons_loaded: Cell::new(false),
            word_predictor: word_prediction::WordPredictor::new(),
        };

        // Preload icons for all categories
        shell.preload_icons();

        // Clear any stale unlock signal from previous session
        let signal_path = unlock_signal_path();
        if signal_path.exists() {
            tracing::info!("Clearing stale unlock signal from previous session");
            let _ = std::fs::remove_file(&signal_path);
        }

        shell
    }

    /// Get display config path (handles both normal and sudo cases)
    fn get_display_config_path() -> std::path::PathBuf {
        // Try SUDO_USER first (for when running as root via sudo)
        if let Ok(sudo_user) = std::env::var("SUDO_USER") {
            return std::path::PathBuf::from(format!("/home/{}/.local/state/flick/display_config.json", sudo_user));
        }
        // Try HOME environment variable
        if let Ok(home) = std::env::var("HOME") {
            return std::path::PathBuf::from(format!("{}/.local/state/flick/display_config.json", home));
        }
        // Fallback to droidian
        std::path::PathBuf::from("/home/droidian/.local/state/flick/display_config.json")
    }

    /// Load screen timeout from display config file
    fn load_screen_timeout() -> u64 {
        let config_path = Self::get_display_config_path();
        if let Ok(content) = std::fs::read_to_string(&config_path) {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(timeout) = json.get("screen_timeout").and_then(|v| v.as_u64()) {
                    tracing::info!("Loaded screen timeout: {}s from {:?}", timeout, config_path);
                    return timeout;
                }
            }
        }
        tracing::info!("Using default screen timeout: 30s (config: {:?})", config_path);
        30 // Default 30 seconds
    }

    /// Load text scale from display config file
    fn load_text_scale() -> f32 {
        let config_path = Self::get_display_config_path();
        if let Ok(content) = std::fs::read_to_string(&config_path) {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(scale) = json.get("text_scale").and_then(|v| v.as_f64()) {
                    tracing::info!("Loaded text scale: {} from {:?}", scale, config_path);
                    return scale as f32;
                }
            }
        }
        tracing::info!("Using default text scale: 2.0 (config: {:?})", config_path);
        2.0 // Default scale for mobile
    }

    /// Reload screen timeout from config (called when settings may have changed)
    pub fn reload_screen_timeout(&mut self) {
        self.screen_timeout_secs = Self::load_screen_timeout();
    }

    /// Reload text scale from config
    pub fn reload_text_scale(&mut self) {
        self.text_scale = Self::load_text_scale();
    }

    /// Load wallpaper path from display config file
    pub fn load_wallpaper_path() -> Option<std::path::PathBuf> {
        let config_path = Self::get_display_config_path();
        tracing::info!("WALLPAPER: Looking for config at {:?}", config_path);
        match std::fs::read_to_string(&config_path) {
            Ok(content) => {
                tracing::info!("WALLPAPER: Config content: {}", content);
                match serde_json::from_str::<serde_json::Value>(&content) {
                    Ok(json) => {
                        if let Some(path_str) = json.get("wallpaper").and_then(|v| v.as_str()) {
                            tracing::info!("WALLPAPER: Found wallpaper key: '{}'", path_str);
                            if !path_str.is_empty() {
                                let path = std::path::PathBuf::from(path_str);
                                if path.exists() {
                                    tracing::info!("WALLPAPER: File exists at {:?}", path);
                                    return Some(path);
                                } else {
                                    tracing::warn!("WALLPAPER: File not found: {:?}", path);
                                }
                            } else {
                                tracing::info!("WALLPAPER: Empty path string");
                            }
                        } else {
                            tracing::info!("WALLPAPER: No wallpaper key in config");
                        }
                    }
                    Err(e) => {
                        tracing::warn!("WALLPAPER: Failed to parse JSON: {}", e);
                    }
                }
            }
            Err(e) => {
                tracing::warn!("WALLPAPER: Failed to read config: {}", e);
            }
        }
        None
    }

    /// Load wallpaper image as slint::Image
    pub fn load_wallpaper_image() -> Option<slint::Image> {
        tracing::info!("WALLPAPER: load_wallpaper_image() called");
        let path = match Self::load_wallpaper_path() {
            Some(p) => {
                tracing::info!("WALLPAPER: Got path: {:?}", p);
                p
            }
            None => {
                tracing::info!("WALLPAPER: No path returned from load_wallpaper_path");
                return None;
            }
        };
        tracing::info!("WALLPAPER: Opening image at {:?}", path);
        match image::open(&path) {
            Ok(img) => {
                let rgba = img.to_rgba8();
                let (width, height) = rgba.dimensions();
                tracing::info!("WALLPAPER: Image loaded, dimensions {}x{}", width, height);
                let pixel_buffer = slint::SharedPixelBuffer::<slint::Rgba8Pixel>::clone_from_slice(
                    rgba.as_raw(),
                    width,
                    height,
                );
                tracing::info!("WALLPAPER: Created pixel buffer, returning Image");
                Some(slint::Image::from_rgba8(pixel_buffer))
            }
            Err(e) => {
                tracing::error!("WALLPAPER: Failed to load image {:?}: {}", path, e);
                None
            }
        }
    }

    /// Reload wallpaper from config (called when settings change)
    pub fn reload_wallpaper(&self) {
        if let Some(ref slint_ui) = self.slint_ui {
            if let Some(wallpaper) = Self::load_wallpaper_image() {
                slint_ui.set_wallpaper(wallpaper);
                slint_ui.set_has_wallpaper(true);
                tracing::info!("Wallpaper reloaded");
            } else {
                slint_ui.set_has_wallpaper(false);
                tracing::info!("Wallpaper cleared");
            }
            // Force redraw to show the new wallpaper
            slint_ui.request_redraw();
        }
    }

    /// Attempt to unlock with the current input
    /// Returns true if unlock succeeded
    pub fn try_unlock(&mut self) -> bool {
        // Check if lock method is "none" - always unlock immediately
        if self.lock_config.method == lock_screen::LockMethod::None {
            tracing::info!("Lock method is None - unlocking immediately");
            self.unlock();
            return true;
        }

        match self.lock_state.input_mode {
            lock_screen::LockInputMode::Pin => {
                // First try the configured PIN
                if self.lock_config.verify_pin(&self.lock_state.entered_pin) {
                    self.unlock();
                    return true;
                }
                // PIN failed - try PAM as fallback (in case user entered PAM password)
                if let Some(username) = lock_screen::get_current_user() {
                    if lock_screen::authenticate_pam(&username, &self.lock_state.entered_pin) {
                        tracing::info!("PAM fallback successful for PIN mode");
                        self.unlock();
                        return true;
                    }
                }
            }
            lock_screen::LockInputMode::Pattern => {
                let pattern_str = self.lock_state.pattern_nodes.iter()
                    .map(|n| n.to_string())
                    .collect::<Vec<_>>()
                    .join(",");
                tracing::info!("Pattern entered: [{}] (nodes: {:?})", pattern_str, self.lock_state.pattern_nodes);
                if self.lock_config.verify_pattern(&self.lock_state.pattern_nodes) {
                    self.unlock();
                    return true;
                }
            }
            lock_screen::LockInputMode::Password => {
                // Password mode always uses PAM authentication
                if let Some(username) = lock_screen::get_current_user() {
                    tracing::info!("Trying PAM auth for user {} with password len={}", username, self.lock_state.entered_password.len());
                    if lock_screen::authenticate_pam(&username, &self.lock_state.entered_password) {
                        self.unlock();
                        return true;
                    }
                } else {
                    tracing::error!("Could not get current username for PAM auth");
                }
            }
        }

        // Failed attempt
        self.lock_state.record_failed_attempt();
        self.lock_state.reset_input();
        false
    }

    /// Set the shell view, hiding keyboard when leaving App view
    pub fn set_view(&mut self, new_view: ShellView) {
        // SECURITY: Block view changes while lock screen is active
        // Only the unlock() function should change the view from LockScreen
        if self.lock_screen_active && self.view == ShellView::LockScreen && new_view != ShellView::LockScreen {
            tracing::warn!("SECURITY: Blocked view change from LockScreen to {:?} while lock_screen_active=true", new_view);
            return;
        }

        tracing::info!("set_view: {:?} -> {:?}", self.view, new_view);

        // Hide keyboard when leaving App view
        if self.view == ShellView::App && new_view != ShellView::App {
            if let Some(ref slint_ui) = self.slint_ui {
                if slint_ui.is_keyboard_visible() {
                    tracing::info!("Hiding keyboard - leaving App view for {:?}", new_view);
                    slint_ui.set_keyboard_visible(false);
                }
            }
            // Reload wallpaper when returning from app (settings might have changed it)
            if new_view == ShellView::Home {
                tracing::info!("Reloading wallpaper on return to Home");
                self.reload_wallpaper();
            }
        }
        self.view = new_view;

        // Update Slint UI view
        if let Some(ref slint_ui) = self.slint_ui {
            let view_str = match new_view {
                ShellView::LockScreen => "lock",
                ShellView::Home => "home",
                ShellView::QuickSettings => "quick-settings",
                ShellView::Switcher => "home",    // App switcher overlays home
                ShellView::App => "home",         // App view still shows home underneath
                ShellView::PickDefault => "pick-default",
            };
            slint_ui.set_view(view_str);
            tracing::info!("Set Slint view to: {}", view_str);
        }
    }

    /// Unlock and transition to appropriate view
    pub fn unlock(&mut self) {
        tracing::info!("Lock screen unlocked");
        self.lock_screen_active = false;
        self.lock_screen_dimmed = false;
        self.display_blanked = false;
        self.last_unlock_time = Some(std::time::Instant::now());

        // Check if we should open a specific app (from notification tap)
        self.check_unlock_open_app();

        // Determine what view to restore
        let restore_view = if self.unlock_open_app.is_some() {
            // App will be launched, go to App view (will be set when window opens)
            tracing::info!("Unlock with pending app launch: {:?}", self.unlock_open_app);
            ShellView::Home // Start at home, app will open on top
        } else if self.pre_lock_had_app {
            // Had an app open before locking, restore to App view
            tracing::info!("Restoring to App view (had app before lock)");
            ShellView::App
        } else {
            // Default to home
            tracing::info!("Restoring to Home view");
            ShellView::Home
        };

        self.set_view(restore_view);
        self.lock_state.reset_input();
        self.lock_state.failed_attempts = 0;
        self.lock_state.error_message = None;

        // Clear the unlock signal file if it exists
        let signal_path = unlock_signal_path();
        if signal_path.exists() {
            let _ = std::fs::remove_file(&signal_path);
        }

        // Force Slint UI redraw
        if let Some(ref slint_ui) = self.slint_ui {
            slint_ui.request_redraw();
            tracing::info!("Requested Slint UI redraw after unlock");
        }
    }

    /// Check for app to open after unlock (from notification tap on lock screen)
    fn check_unlock_open_app(&mut self) {
        // Get state dir - same logic as unlock_signal_path()
        let state_dir = if let Ok(dir) = std::env::var("FLICK_STATE_DIR") {
            std::path::PathBuf::from(dir)
        } else {
            let home = if let Ok(sudo_user) = std::env::var("SUDO_USER") {
                format!("/home/{}", sudo_user)
            } else {
                std::env::var("HOME").unwrap_or_else(|_| "/home/droidian".to_string())
            };
            std::path::PathBuf::from(home).join(".local/state/flick")
        };
        let open_app_path = state_dir.join("unlock_open_app.json");

        if open_app_path.exists() {
            if let Ok(content) = std::fs::read_to_string(&open_app_path) {
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(app) = json.get("app").and_then(|v| v.as_str()) {
                        self.unlock_open_app = Some(app.to_string());
                        tracing::info!("Found unlock open app request: {}", app);
                    }
                }
            }
            // Remove the file after reading
            let _ = std::fs::remove_file(&open_app_path);
        }
    }

    /// Lock the screen - sets up state, compositor will launch Python app
    pub fn lock(&mut self) {
        tracing::info!("Locking screen");
        // Save the current view before locking (so we can restore it after unlock)
        self.pre_lock_view = self.view;
        self.pre_lock_had_app = self.view == ShellView::App;
        tracing::info!("Saving pre-lock view: {:?}, had_app: {}", self.pre_lock_view, self.pre_lock_had_app);

        self.lock_config = lock_screen::LockConfig::load(); // Reload latest config
        if self.lock_config.method != lock_screen::LockMethod::None {
            self.lock_screen_active = true;
            self.set_view(ShellView::LockScreen);
            self.lock_state = lock_screen::LockScreenState::new(&self.lock_config);
            // Reset activity time and dimmed state
            self.lock_screen_last_activity = std::time::Instant::now();
            self.lock_screen_dimmed = false;
            // Lock screen is now QML-based
            // Clear any stale unlock signal and open app request
            let signal_path = unlock_signal_path();
            if signal_path.exists() {
                let _ = std::fs::remove_file(&signal_path);
            }
            self.unlock_open_app = None;
            self.unlock_app_launched = false;
        }
    }

    /// Check if lock screen app has signaled successful unlock
    /// Returns true if unlock signal was found (caller should call unlock())
    pub fn check_unlock_signal(&self) -> bool {
        if !self.lock_screen_active {
            return false;
        }
        let signal_path = unlock_signal_path();
        signal_path.exists()
    }

    /// Check if we recently unlocked (within 2 seconds)
    /// Used to prevent spurious App view switches from dying lock screen app
    pub fn is_recently_unlocked(&self) -> bool {
        if let Some(unlock_time) = self.last_unlock_time {
            unlock_time.elapsed() < std::time::Duration::from_secs(2)
        } else {
            false
        }
    }

    /// Reset lock screen activity timer (called on any touch/power button)
    pub fn reset_lock_screen_activity(&mut self) {
        self.lock_screen_last_activity = std::time::Instant::now();
    }

    /// Wake the lock screen from dimmed/blanked state
    pub fn wake_lock_screen(&mut self) {
        if self.display_blanked || self.lock_screen_dimmed {
            tracing::info!("Waking lock screen from dimmed/blanked state");
            self.lock_screen_dimmed = false;
            self.display_blanked = false;
            self.lock_screen_last_activity = std::time::Instant::now();
        }
    }

    /// Check if lock screen should be dimmed (after timeout)
    /// Returns true if state changed
    pub fn check_lock_screen_dim(&mut self) -> bool {
        const DIM_TIMEOUT_SECS: u64 = 5; // Dim after 5 seconds of inactivity

        if !self.lock_screen_active || self.lock_screen_dimmed {
            return false;
        }

        if self.lock_screen_last_activity.elapsed() > std::time::Duration::from_secs(DIM_TIMEOUT_SECS) {
            tracing::info!("Lock screen dimming after {}s inactivity", DIM_TIMEOUT_SECS);
            self.lock_screen_dimmed = true;
            return true;
        }
        false
    }

    /// Check if display should be blanked (shortly after dimming)
    /// Returns true if display should now be blanked (state changed)
    pub fn check_display_blank(&mut self) -> bool {
        const BLANK_TIMEOUT_SECS: u64 = 8; // Blank 3 seconds after dim (5+3=8 total)

        if !self.lock_screen_active || self.display_blanked {
            return false;
        }

        // Only blank if already dimmed
        if !self.lock_screen_dimmed {
            return false;
        }

        if self.lock_screen_last_activity.elapsed() > std::time::Duration::from_secs(BLANK_TIMEOUT_SECS) {
            tracing::info!("Display blanking after {}s inactivity", BLANK_TIMEOUT_SECS);
            self.display_blanked = true;
            return true;
        }
        false
    }

    /// Launch the external QML lock screen app
    pub fn launch_lock_screen_app(&self, _socket_name: &str) -> bool {
        if !self.lock_screen_active {
            return false;
        }

        let (cmd, args) = get_lockscreen_command();
        tracing::info!("Launching QML lock screen: {} {:?}", cmd, args);

        // Create log file for QML output
        let log_path = std::env::var("HOME")
            .map(|h| format!("{}/.local/state/flick/qml_lockscreen.log", h))
            .unwrap_or_else(|_| "/tmp/qml_lockscreen.log".to_string());

        tracing::info!("QML lock screen output will be logged to: {}", log_path);

        // The run_lockscreen.sh already handles logging - just redirect to /dev/null
        // to prevent Qt output from corrupting the terminal
        let shell_cmd = format!(
            "{} {} > /dev/null 2>&1",
            cmd,
            args.join(" ")
        );

        // Use real user's home when running via sudo
        let state_dir = if let Ok(sudo_user) = std::env::var("SUDO_USER") {
            format!("/home/{}/.local/state/flick", sudo_user)
        } else {
            std::env::var("HOME")
                .map(|h| format!("{}/.local/state/flick", h))
                .unwrap_or_else(|_| "/tmp".to_string())
        };

        let qt_scale = format!("{}", self.text_scale);
        let gdk_scale = format!("{}", self.text_scale.round() as i32);
        match std::process::Command::new("sh")
            .arg("-c")
            .arg(&shell_cmd)
            .env("WAYLAND_DISPLAY", _socket_name)
            .env("QT_QPA_PLATFORM", "wayland")
            .env("QT_WAYLAND_CLIENT_BUFFER_INTEGRATION", "shm")
            .env("FLICK_STATE_DIR", &state_dir)
            .env("XDG_RUNTIME_DIR", std::env::var("XDG_RUNTIME_DIR").unwrap_or_default())
            // Text/UI scaling for lock screen app
            .env("QT_SCALE_FACTOR", &qt_scale)
            .env("QT_FONT_DPI", format!("{}", (96.0 * self.text_scale) as i32))
            .env("GDK_SCALE", &gdk_scale)
            .env("GDK_DPI_SCALE", &qt_scale)
            .spawn()
        {
            Ok(_) => {
                tracing::info!("QML lock screen app launched successfully");
                true
            }
            Err(e) => {
                tracing::error!("Failed to launch QML lock screen app: {}", e);
                false
            }
        }
    }

    /// Check if welcome app should be shown (first launch)
    pub fn should_show_welcome(&self) -> bool {
        let config_path = if let Ok(sudo_user) = std::env::var("SUDO_USER") {
            format!("/home/{}/.local/state/flick/welcome_config.json", sudo_user)
        } else {
            std::env::var("HOME")
                .map(|h| format!("{}/.local/state/flick/welcome_config.json", h))
                .unwrap_or_else(|_| "/tmp/welcome_config.json".to_string())
        };

        // If config doesn't exist, show welcome (first launch)
        if !std::path::Path::new(&config_path).exists() {
            tracing::info!("Welcome config not found, showing welcome screen");
            return true;
        }

        // Read config and check showOnStartup
        match std::fs::read_to_string(&config_path) {
            Ok(content) => {
                // Simple JSON parsing - look for "showOnStartup":true/false
                let show = content.contains("\"showOnStartup\":true") ||
                           content.contains("\"showOnStartup\": true");
                tracing::info!("Welcome config: showOnStartup = {}", show);
                show
            }
            Err(e) => {
                tracing::warn!("Failed to read welcome config: {}, showing welcome", e);
                true
            }
        }
    }

    /// Launch the welcome/tutorial app
    pub fn launch_welcome_app(&self, socket_name: &str) -> bool {
        // Get the welcome app path
        let welcome_script = if let Ok(sudo_user) = std::env::var("SUDO_USER") {
            format!("/home/{}/Flick/apps/welcome/run_welcome.sh", sudo_user)
        } else {
            std::env::var("HOME")
                .map(|h| format!("{}/Flick/apps/welcome/run_welcome.sh", h))
                .unwrap_or_else(|_| "/home/droidian/Flick/apps/welcome/run_welcome.sh".to_string())
        };

        if !std::path::Path::new(&welcome_script).exists() {
            tracing::warn!("Welcome script not found at: {}", welcome_script);
            return false;
        }

        tracing::info!("Launching welcome app: {}", welcome_script);

        let state_dir = if let Ok(sudo_user) = std::env::var("SUDO_USER") {
            format!("/home/{}/.local/state/flick", sudo_user)
        } else {
            std::env::var("HOME")
                .map(|h| format!("{}/.local/state/flick", h))
                .unwrap_or_else(|_| "/tmp".to_string())
        };

        let qt_scale = format!("{}", self.text_scale);
        match std::process::Command::new("sh")
            .arg("-c")
            .arg(&welcome_script)
            .env("WAYLAND_DISPLAY", socket_name)
            .env("QT_QPA_PLATFORM", "wayland")
            .env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
            .env("FLICK_STATE_DIR", &state_dir)
            .env("XDG_RUNTIME_DIR", std::env::var("XDG_RUNTIME_DIR").unwrap_or_default())
            .env("QT_SCALE_FACTOR", &qt_scale)
            .env("QT_FONT_DPI", format!("{}", (96.0 * self.text_scale) as i32))
            .spawn()
        {
            Ok(_) => {
                tracing::info!("Welcome app launched successfully");
                true
            }
            Err(e) => {
                tracing::error!("Failed to launch welcome app: {}", e);
                false
            }
        }
    }

    /// Reload lock config from disk
    pub fn reload_lock_config(&mut self) {
        self.lock_config = lock_screen::LockConfig::load();
        tracing::info!("Reloaded lock config: method = {:?}", self.lock_config.method);
    }

    /// Check for keyboard visibility requests from apps (stub - not yet implemented)
    pub fn check_keyboard_request(&mut self) -> Option<bool> {
        None
    }

    /// Preload icons for all categories into the cache
    pub fn preload_icons(&mut self) {
        let icon_names: Vec<String> = self.app_manager
            .get_category_info()
            .iter()
            .filter_map(|info| info.icon.clone())
            .collect();

        tracing::info!("Preloading {} icons", icon_names.len());
        for name in &icon_names {
            let _ = self.icon_cache.get(name);
        }
    }

    /// Get categories with their icons as Slint images (uses already-cached icons)
    /// Returns Vec of (name, slint::Image, color)
    /// Note: Call preload_icons() first to ensure icons are cached
    pub fn get_categories_with_icons(&self) -> Vec<(String, slint::Image, [f32; 4])> {
        self.app_manager
            .get_category_info()
            .iter()
            .map(|cat| {
                let icon = if let Some(ref icon_name) = cat.icon {
                    // Try to get the icon from cache (must be preloaded)
                    if let Some(icon_data) = self.icon_cache.get_cached(icon_name) {
                        // Convert RGBA bytes to Slint image
                        let pixel_buffer = slint::SharedPixelBuffer::<slint::Rgba8Pixel>::clone_from_slice(
                            &icon_data.data,
                            icon_data.width,
                            icon_data.height,
                        );
                        slint::Image::from_rgba8(pixel_buffer)
                    } else {
                        slint::Image::default()
                    }
                } else {
                    slint::Image::default()
                };
                (cat.name.clone(), icon, cat.color)
            })
            .collect()
    }

    /// Load UI icons for quick settings and other shell elements
    /// These are loaded from the icons/ui folder
    pub fn load_ui_icons(&mut self) -> slint_ui::UiIconImages {
        // Helper to load a single icon and convert to slint::Image
        let mut load_icon = |name: &str| -> slint::Image {
            if let Some(icon_data) = self.icon_cache.get(name) {
                let pixel_buffer = slint::SharedPixelBuffer::<slint::Rgba8Pixel>::clone_from_slice(
                    &icon_data.data,
                    icon_data.width,
                    icon_data.height,
                );
                slint::Image::from_rgba8(pixel_buffer)
            } else {
                tracing::warn!("Failed to load UI icon: {}", name);
                slint::Image::default()
            }
        };

        slint_ui::UiIconImages {
            wifi: load_icon("wifi"),
            wifi_off: load_icon("wifi-off"),
            bluetooth: load_icon("bluetooth"),
            bluetooth_off: load_icon("bluetooth-off"),
            moon: load_icon("moon"),
            flashlight: load_icon("flashlight"),
            flashlight_off: load_icon("flashlight-off"),
            plane: load_icon("plane"),
            rotate: load_icon("rotate-cw"),
            lock: load_icon("lock"),
            sun: load_icon("sun"),
            volume: load_icon("volume-2"),
            volume_off: load_icon("volume-off"),
            wand: load_icon("wand"),
        }
    }

    /// Start tracking a touch on home screen (potential scroll or tap)
    pub fn start_home_touch(&mut self, y: f64, pending_app: Option<String>) {
        self.scroll_touch_start_y = Some(y);
        self.scroll_touch_last_y = Some(y);
        self.pending_app_launch = pending_app;
        self.is_scrolling = false;
        self.long_press_start = Some(std::time::Instant::now());
        // Stop any ongoing momentum animation when user touches
        self.home_scroll_animating = false;
        self.home_scroll_velocity = 0.0;
        self.home_scroll_touch_times.clear();
        self.home_scroll_touch_times.push((y, std::time::Instant::now()));
    }

    /// Start tracking a touch on a specific category (for long press detection)
    pub fn start_category_touch(&mut self, pos: Point<f64, Logical>, category_id: &str) {
        self.scroll_touch_start_y = Some(pos.y);
        self.scroll_touch_last_y = Some(pos.y);
        self.pending_category_id = Some(category_id.to_string());
        self.pending_app_launch = self.app_manager.get_exec(category_id);
        self.is_scrolling = false;
        self.long_press_start = Some(std::time::Instant::now());
        self.long_press_category_id = Some(category_id.to_string());
        self.long_press_position = Some(pos);
        // Stop any ongoing momentum animation when user touches
        self.home_scroll_animating = false;
        self.home_scroll_velocity = 0.0;
        self.home_scroll_touch_times.clear();
        self.home_scroll_touch_times.push((pos.y, std::time::Instant::now()));
    }

    /// Check if a long press has occurred (300ms threshold)
    pub fn check_long_press(&mut self) -> Option<String> {
        if self.is_scrolling {
            return None;
        }
        if let (Some(start), Some(ref category_id)) = (self.long_press_start, &self.long_press_category_id) {
            if start.elapsed() >= std::time::Duration::from_millis(300) {
                // Clear the pending app launch since this is a long press
                self.pending_app_launch = None;
                return Some(category_id.clone());
            }
        }
        None
    }

    /// Check for long press and show menu if triggered (called from render loop)
    /// Returns true if menu was shown
    pub fn check_and_show_long_press(&mut self) -> bool {
        if self.long_press_menu.is_some() {
            return false; // Menu already open
        }
        if let Some(category_id) = self.check_long_press() {
            // Skip long press menu for non-customizable categories (like Settings)
            if !self.app_manager.is_customizable(&category_id) {
                tracing::debug!("Long press on non-customizable category {}, ignoring", category_id);
                self.long_press_start = None;
                self.long_press_category_id = None;
                return false;
            }
            if let Some(pos) = self.long_press_position {
                tracing::info!("Long press triggered for {} at ({:.0}, {:.0})", category_id, pos.x, pos.y);
                self.show_long_press_menu(&category_id, pos);
                // Clear long press tracking so it doesn't trigger again
                self.long_press_start = None;
                self.long_press_category_id = None;
                return true;
            }
        }
        false
    }

    /// Show long press menu for a category
    pub fn show_long_press_menu(&mut self, category_id: &str, position: Point<f64, Logical>) {
        let available_apps = self.app_manager.apps_for_category(category_id)
            .into_iter()
            .cloned()
            .collect();
        self.long_press_menu = Some(LongPressMenu {
            category_id: category_id.to_string(),
            position,
            available_apps,
            highlighted: None,
            level: MenuLevel::Main,
            scroll_offset: 0.0,
        });
        self.menu_just_opened = true; // Don't close on this touch release

        // Also set Slint popup state
        self.popup_showing = true;
        self.popup_category_id = Some(category_id.to_string());
    }

    /// Close long press menu
    pub fn close_long_press_menu(&mut self) {
        self.long_press_menu = None;
        self.menu_just_opened = false;
        // Also close Slint popup
        self.popup_showing = false;
    }

    /// Handle menu item selection - returns true if menu should close
    pub fn handle_menu_tap(&mut self, index: usize) -> Option<MenuAction> {
        let menu = self.long_press_menu.as_mut()?;

        match menu.level {
            MenuLevel::Main => {
                match index {
                    0 => {
                        // "Move" - enter wiggle mode
                        self.wiggle_mode = true;
                        self.wiggle_start_time = Some(std::time::Instant::now());
                        self.long_press_menu = None;
                        self.popup_showing = false;  // Must also reset popup_showing
                        Some(MenuAction::EnterWiggleMode)
                    }
                    1 => {
                        // "Change Default" - switch to app selection
                        menu.level = MenuLevel::SelectApp;
                        menu.scroll_offset = 0.0;
                        Some(MenuAction::ShowAppList)
                    }
                    _ => None,
                }
            }
            MenuLevel::SelectApp => {
                // Select an app from the list
                if let Some(entry) = menu.available_apps.get(index) {
                    let exec = entry.exec.clone();
                    let category_id = menu.category_id.clone();
                    self.app_manager.set_category_app(&category_id, exec);
                    self.preload_icons(); // Reload icons after changing selection
                    self.long_press_menu = None;
                    self.popup_showing = false;  // Must also reset popup_showing
                    Some(MenuAction::AppSelected)
                } else {
                    None
                }
            }
        }
    }

    /// Legacy: Select an app from the long press menu
    pub fn select_app_from_menu(&mut self, index: usize) -> bool {
        self.handle_menu_tap(index).is_some()
    }

    /// Exit wiggle mode (after rearranging is done)
    pub fn exit_wiggle_mode(&mut self) {
        self.wiggle_mode = false;
        self.wiggle_start_time = None;
        self.dragging_index = None;
        self.drag_start_position = None;
        self.drag_position = None;
        // Clear long press state to prevent immediate re-entry
        self.long_press_start = None;
        self.long_press_category_id = None;
        // Ensure all popup/menu state is cleared for clean long press detection
        self.long_press_menu = None;
        self.menu_just_opened = false;
        self.popup_showing = false;
        self.popup_category_id = None;
    }

    /// Start dragging a category in wiggle mode
    pub fn start_drag(&mut self, index: usize, pos: Point<f64, Logical>) {
        if self.wiggle_mode {
            self.dragging_index = Some(index);
            self.drag_start_position = Some(pos);  // Initial position for drag detection
            self.drag_position = Some(pos);         // Current position (updated during drag)
        }
    }

    /// Update drag position
    pub fn update_drag(&mut self, pos: Point<f64, Logical>) {
        if self.dragging_index.is_some() {
            self.drag_position = Some(pos);
        }
    }

    /// End drag and reorder if needed - returns true if reordering happened
    pub fn end_drag(&mut self, drop_index: Option<usize>) -> bool {
        let dragging = self.dragging_index.take();
        self.drag_start_position = None;
        self.drag_position = None;

        if let (Some(from), Some(to)) = (dragging, drop_index) {
            if from != to {
                self.app_manager.move_category(from, to);
                return true;
            }
        }
        false
    }

    /// Get wiggle offset for animation (returns x, y offset in pixels)
    pub fn get_wiggle_offset(&self, index: usize) -> (f64, f64) {
        if !self.wiggle_mode {
            return (0.0, 0.0);
        }
        if let Some(start) = self.wiggle_start_time {
            let elapsed = start.elapsed().as_secs_f64();
            // Each icon wiggles with a slight phase offset
            let phase = (index as f64) * 0.5;
            let angle = (elapsed * 8.0 + phase).sin() * 0.05; // Small rotation effect via offset
            let x_offset = angle * 10.0;
            let y_offset = ((elapsed * 10.0 + phase).cos() * 2.0).abs();
            return (x_offset, y_offset);
        }
        (0.0, 0.0)
    }

    /// Update scroll position based on touch movement
    /// Returns true if scrolling is happening
    pub fn update_home_scroll(&mut self, y: f64) -> bool {
        if let Some(start_y) = self.scroll_touch_start_y {
            let total_delta = (y - start_y).abs();
            // If moved more than 40 pixels, it's a scroll, not a tap
            // (increased from 20px for better tap reliability on touch screens)
            if total_delta > 40.0 {
                self.is_scrolling = true;
                self.pending_app_launch = None; // Cancel pending app launch
                self.pending_category_id = None;
                self.long_press_start = None;
                self.long_press_category_id = None;
                self.long_press_position = None;
            }
        }

        // Track touch position for velocity calculation
        let now = std::time::Instant::now();
        self.home_scroll_touch_times.push((y, now));
        // Only keep touches from last 100ms for velocity calculation
        self.home_scroll_touch_times.retain(|(_, t)| now.duration_since(*t).as_millis() < 100);

        if let Some(last_y) = self.scroll_touch_last_y {
            let delta = last_y - y; // Scroll down when finger moves up
            let max_scroll = self.get_home_max_scroll();
            self.home_scroll = (self.home_scroll + delta).clamp(0.0, max_scroll);
        }
        self.scroll_touch_last_y = Some(y);
        self.is_scrolling
    }

    /// Calculate max scroll for home screen based on content
    pub fn get_home_max_scroll(&self) -> f64 {
        let num_items = self.app_manager.config.grid_order.len();
        let columns = 4; // Slint hardcodes 4 columns
        let rows = (num_items + columns - 1) / columns;

        // Match Slint's tile height calculation with text_scale
        let height = self.screen_size.h as f64;
        let status_bar_height = 54.0 * self.text_scale as f64;
        let home_indicator_height = 34.0;
        let grid_padding = 12.0;
        let grid_spacing = 8.0;
        let grid_height = height - status_bar_height - home_indicator_height - grid_padding * 2.0;

        // num_rows for tile height calculation (matches Slint's formula)
        let num_rows_for_height = if num_items > 20 { 6 } else if num_items > 16 { 5 } else if num_items > 12 { 4 } else if num_items > 8 { 3 } else if num_items > 4 { 2 } else { 1 };
        let tile_height = (grid_height - grid_spacing * (num_rows_for_height as f64 - 1.0)) / num_rows_for_height as f64;

        // Total content height = all rows * (tile_height + spacing)
        let content_height = rows as f64 * (tile_height + grid_spacing);
        (content_height - grid_height).max(0.0)
    }

    /// End touch gesture - returns app exec string if this was a tap (not scroll)
    pub fn end_home_touch(&mut self) -> Option<String> {
        let app = if !self.is_scrolling {
            self.pending_app_launch.take()
        } else {
            None
        };

        // Calculate velocity from touch history and start momentum if scrolling
        if self.is_scrolling && self.home_scroll_touch_times.len() >= 2 {
            let first = self.home_scroll_touch_times.first().unwrap();
            let last = self.home_scroll_touch_times.last().unwrap();
            let dt = last.1.duration_since(first.1).as_secs_f64();
            if dt > 0.001 {
                // Velocity in pixels per second (negative because scroll direction is inverted)
                self.home_scroll_velocity = -(last.0 - first.0) / dt;
                // Clamp velocity to reasonable range
                let max_velocity = 6000.0;
                self.home_scroll_velocity = self.home_scroll_velocity.clamp(-max_velocity, max_velocity);

                // Start momentum animation if velocity is significant
                if self.home_scroll_velocity.abs() > 100.0 {
                    self.home_scroll_animating = true;
                    self.home_scroll_last_update = Some(std::time::Instant::now());
                }
            }
        }

        self.scroll_touch_start_y = None;
        self.scroll_touch_last_y = None;
        self.pending_app_launch = None;
        self.pending_category_id = None;
        self.is_scrolling = false;
        self.long_press_start = None;
        self.long_press_category_id = None;
        self.long_press_position = None;
        self.home_scroll_touch_times.clear();
        app
    }

    // ========== Context Menu (Copy/Paste) Methods ==========

    /// Start tracking for context menu (called on any touch down)
    pub fn start_context_menu_tracking(&mut self, pos: Point<f64, Logical>, slot: i32) {
        // Only start tracking if no context menu is already active
        if !self.context_menu_active {
            self.context_menu_position = Some(pos);
            self.context_menu_slot = Some(slot);
            self.context_menu_start = Some(std::time::Instant::now());
            tracing::info!("Context menu tracking started at ({}, {}), slot {}", pos.x, pos.y, slot);
        }
    }

    /// Check if context menu should be shown (500ms threshold)
    /// Called from main loop
    pub fn check_context_menu(&mut self) -> bool {
        // Only check if we're tracking a touch and menu not already shown
        if self.context_menu_active {
            return false;
        }
        if self.context_menu_position.is_none() {
            return false;
        }

        // Don't show context menu if user is scrolling
        if self.is_scrolling {
            tracing::debug!("Context menu blocked: scrolling");
            return false;
        }

        // Check if long press duration has passed (using context menu's own timer)
        if let Some(start) = self.context_menu_start {
            let elapsed = start.elapsed();
            if elapsed >= std::time::Duration::from_millis(500) {
                tracing::info!("Context menu ready after {}ms", elapsed.as_millis());
                return true;
            }
        }
        false
    }

    /// Show the context menu at the current position
    pub fn show_context_menu(&mut self) {
        if let Some(pos) = self.context_menu_position {
            self.context_menu_active = true;
            self.context_menu_highlight = 0;  // No option highlighted initially

            // Update Slint UI
            if let Some(ref slint_ui) = self.slint_ui {
                slint_ui.set_context_menu_position(pos.x as f32, pos.y as f32);
                slint_ui.set_context_menu_highlight(0);
                slint_ui.set_show_context_menu(true);
            }

            tracing::info!("Context menu shown at ({}, {})", pos.x, pos.y);
        }
    }

    /// Update context menu highlight based on finger position
    /// Returns the current highlight (0=none, 1=clipboard, 2=paste, 3=system)
    pub fn update_context_menu_highlight(&mut self, current_pos: Point<f64, Logical>) -> i32 {
        if !self.context_menu_active {
            return 0;
        }

        if let Some(center) = self.context_menu_position {
            let dx = current_pos.x - center.x;
            let dy = current_pos.y - center.y;
            let distance = (dx * dx + dy * dy).sqrt();

            // Require minimum distance from center to select an option
            let min_distance = 50.0;

            let highlight = if distance < min_distance {
                0  // Too close to center - no selection
            } else if dy > 100.0 && dx.abs() < 150.0 {
                3  // Below center = System menu
            } else if dx < 0.0 {
                1  // Left side = Clipboard
            } else {
                2  // Right side = Paste
            };

            if highlight != self.context_menu_highlight {
                self.context_menu_highlight = highlight;
                if let Some(ref slint_ui) = self.slint_ui {
                    slint_ui.set_context_menu_highlight(highlight);
                }
            }

            highlight
        } else {
            0
        }
    }

    /// Complete context menu interaction (finger released)
    /// Returns the action to perform (0=cancel, 1=clipboard, 2=paste, 3=system)
    pub fn complete_context_menu(&mut self) -> i32 {
        let action = self.context_menu_highlight;

        // Hide the menu
        self.context_menu_active = false;
        self.context_menu_position = None;
        self.context_menu_highlight = 0;
        self.context_menu_slot = None;
        self.context_menu_start = None;

        if let Some(ref slint_ui) = self.slint_ui {
            slint_ui.set_show_context_menu(false);
        }

        tracing::info!("Context menu completed with action: {}", action);
        action
    }

    /// Cancel context menu tracking (without completing)
    pub fn cancel_context_menu(&mut self) {
        if self.context_menu_active {
            if let Some(ref slint_ui) = self.slint_ui {
                slint_ui.set_show_context_menu(false);
            }
        }
        self.context_menu_active = false;
        self.context_menu_position = None;
        self.context_menu_highlight = 0;
        self.context_menu_slot = None;
        self.context_menu_start = None;
    }

    /// Check if context menu is active for a specific touch slot
    pub fn is_context_menu_slot(&self, slot: i32) -> bool {
        self.context_menu_slot == Some(slot)
    }

    // ========== Clipboard Methods ==========

    /// Check clipboard content using wl-paste (called periodically)
    pub fn check_clipboard(&mut self) {
        // Only check every 500ms to avoid spam
        if self.clipboard_last_check.elapsed() < std::time::Duration::from_millis(500) {
            return;
        }
        self.clipboard_last_check = std::time::Instant::now();

        // Use timeout to prevent wl-paste from blocking indefinitely
        // wl-paste blocks when no clipboard content exists
        match std::process::Command::new("timeout")
            .args(["0.1", "wl-paste", "--no-newline"])
            .output()
        {
            Ok(output) => {
                if output.status.success() {
                    let content = String::from_utf8_lossy(&output.stdout).to_string();
                    let new_content = if content.is_empty() { None } else { Some(content) };

                    // Check if clipboard changed
                    if new_content != self.clipboard_content {
                        if let Some(ref text) = new_content {
                            // Clipboard has new content - show popup
                            self.show_copied_notification(text.clone(), None);
                        }
                        self.clipboard_content = new_content;

                        // Update Slint UI with clipboard preview
                        self.update_clipboard_preview();
                    }
                }
            }
            Err(_) => {
                // wl-paste not available, ignore
            }
        }
    }

    /// Show "Copied!" popup notification
    pub fn show_copied_notification(&mut self, text: String, position: Option<Point<f64, Logical>>) {
        // Truncate text for display
        let display_text = if text.len() > 30 {
            format!("{}...", &text[..30])
        } else {
            text
        };

        self.show_copied_popup = true;
        self.copied_popup_text = display_text.clone();
        self.copied_popup_start = Some(std::time::Instant::now());
        self.copied_popup_position = position;

        // Update Slint UI
        if let Some(ref slint_ui) = self.slint_ui {
            slint_ui.set_show_copied_popup(true);
            slint_ui.set_copied_popup_text(&display_text);
            if let Some(pos) = position {
                slint_ui.set_copied_popup_position(pos.x as f32, pos.y as f32);
            }
        }

        tracing::info!("Showing copied popup: {}", display_text);
    }

    /// Update the copied popup (hide after 2 seconds)
    pub fn update_copied_popup(&mut self) {
        if !self.show_copied_popup {
            return;
        }

        if let Some(start) = self.copied_popup_start {
            if start.elapsed() >= std::time::Duration::from_secs(2) {
                self.show_copied_popup = false;
                self.copied_popup_start = None;

                if let Some(ref slint_ui) = self.slint_ui {
                    slint_ui.set_show_copied_popup(false);
                }
            }
        }
    }

    /// Update clipboard preview in Slint UI
    fn update_clipboard_preview(&self) {
        if let Some(ref slint_ui) = self.slint_ui {
            let preview = match &self.clipboard_content {
                Some(text) => {
                    if text.len() > 20 {
                        format!("{}...", &text[..20])
                    } else {
                        text.clone()
                    }
                }
                None => String::new(),
            };
            slint_ui.set_clipboard_preview(&preview);
        }
    }

    /// Get clipboard content for display
    pub fn get_clipboard_preview(&self) -> String {
        match &self.clipboard_content {
            Some(text) => {
                if text.len() > 20 {
                    format!("{}...", &text[..20])
                } else {
                    text.clone()
                }
            }
            None => "Empty".to_string(),
        }
    }

    // ========== System Menu Methods ==========

    /// Show system menu (reboot/shutdown/lock options)
    pub fn show_system_menu(&mut self) {
        self.system_menu_active = true;
        if let Some(ref slint_ui) = self.slint_ui {
            slint_ui.set_show_system_menu(true);
        }
        tracing::info!("System menu opened");
    }

    /// Hide system menu
    pub fn hide_system_menu(&mut self) {
        self.system_menu_active = false;
        if let Some(ref slint_ui) = self.slint_ui {
            slint_ui.set_show_system_menu(false);
        }
    }

    /// Execute system action
    pub fn execute_system_action(&mut self, action: &str) {
        tracing::info!("System action: {}", action);
        match action {
            "lock" => {
                self.lock_screen_active = true;
                self.set_view(ShellView::LockScreen);
                // Launch the QML lock screen app
                self.launch_lock_screen_app("wayland-1");
            }
            "reboot" => {
                // Use systemctl to reboot
                let _ = std::process::Command::new("systemctl")
                    .arg("reboot")
                    .spawn();
            }
            "shutdown" => {
                // Use systemctl to power off
                let _ = std::process::Command::new("systemctl")
                    .arg("poweroff")
                    .spawn();
            }
            _ => {}
        }
        self.hide_system_menu();
    }

    /// Update home scroll physics (momentum) - returns true if still animating
    pub fn update_home_scroll_physics(&mut self) -> bool {
        if !self.home_scroll_animating {
            return false;
        }

        let now = std::time::Instant::now();
        let dt = if let Some(last) = self.home_scroll_last_update {
            let elapsed = now.duration_since(last).as_secs_f64();
            // Clamp dt to avoid instability from frame drops
            elapsed.min(0.05)
        } else {
            0.016 // ~60fps default
        };
        self.home_scroll_last_update = Some(now);

        // Simple exponential decay friction (0.95 per frame at 60fps)
        // This gives smooth deceleration without oscillation
        let decay_per_second = 0.05_f64.powf(1.0 / 0.016); // ~0.95 at 60fps
        let decay = decay_per_second.powf(dt);
        self.home_scroll_velocity *= decay;

        // Apply velocity
        self.home_scroll += self.home_scroll_velocity * dt;

        // Hard clamp to bounds (no bounce - simpler and more stable)
        let max_scroll = self.get_home_max_scroll();
        if self.home_scroll < 0.0 {
            self.home_scroll = 0.0;
            self.home_scroll_velocity = 0.0;
        } else if self.home_scroll > max_scroll {
            self.home_scroll = max_scroll;
            self.home_scroll_velocity = 0.0;
        }

        // Stop animation when velocity is very small
        if self.home_scroll_velocity.abs() < 50.0 {
            self.home_scroll_animating = false;
            self.home_scroll_velocity = 0.0;
        }

        self.home_scroll_animating
    }

    /// Start tracking a touch on app switcher (potential horizontal scroll or tap)
    pub fn start_switcher_touch(&mut self, x: f64, pending_index: Option<usize>) {
        self.switcher_touch_start_x = Some(x);
        self.switcher_touch_last_x = Some(x);
        self.pending_switcher_index = pending_index;
        self.is_scrolling = false;
        // Stop any ongoing animation when user touches
        self.switcher_animating = false;
        self.switcher_snap_target = None;
        self.switcher_velocity = 0.0;
        // Start tracking touch positions for velocity calculation
        self.switcher_touch_times.clear();
        self.switcher_touch_times.push((x, std::time::Instant::now()));
    }

    /// Update horizontal scroll position based on touch movement
    /// Returns true if scrolling is happening
    pub fn update_switcher_scroll(&mut self, x: f64, num_windows: usize, card_spacing: f64) -> bool {
        if let Some(start_x) = self.switcher_touch_start_x {
            let total_delta = (x - start_x).abs();
            // If moved more than 40 pixels, it's a scroll, not a tap
            if total_delta > 40.0 {
                self.is_scrolling = true;
                self.pending_switcher_index = None;
            }
        }

        if let Some(last_x) = self.switcher_touch_last_x {
            let delta = last_x - x; // Scroll right when finger moves left
            let max_scroll = self.get_switcher_max_scroll(num_windows, card_spacing);
            self.switcher_scroll = (self.switcher_scroll + delta).clamp(0.0, max_scroll);
        }
        self.switcher_touch_last_x = Some(x);

        // Track position for velocity (keep last 100ms of samples)
        let now = std::time::Instant::now();
        self.switcher_touch_times.push((x, now));
        self.switcher_touch_times.retain(|(_, t)| now.duration_since(*t).as_millis() < 100);

        self.is_scrolling
    }

    /// Calculate max scroll for switcher
    pub fn get_switcher_max_scroll(&self, num_windows: usize, card_spacing: f64) -> f64 {
        if num_windows > 0 {
            (num_windows - 1) as f64 * card_spacing
        } else {
            0.0
        }
    }

    /// End switcher touch gesture - returns window index if this was a tap (not scroll)
    /// Starts momentum animation based on flick velocity
    pub fn end_switcher_touch(&mut self, num_windows: usize, card_spacing: f64) -> Option<usize> {
        let index = if !self.is_scrolling {
            self.pending_switcher_index.take()
        } else {
            None
        };

        // Calculate velocity from recent touch samples
        if self.is_scrolling && self.switcher_touch_times.len() >= 2 {
            let first = self.switcher_touch_times.first().unwrap();
            let last = self.switcher_touch_times.last().unwrap();
            let dt = last.1.duration_since(first.1).as_secs_f64();
            if dt > 0.001 {
                // Velocity is negative of position delta (scroll direction)
                self.switcher_velocity = -(last.0 - first.0) / dt;

                // Clamp velocity to reasonable range
                let max_velocity = 8000.0; // pixels per second
                self.switcher_velocity = self.switcher_velocity.clamp(-max_velocity, max_velocity);

                // Only animate if velocity is significant
                if self.switcher_velocity.abs() > 100.0 {
                    self.switcher_animating = true;
                    self.switcher_last_update = Some(std::time::Instant::now());
                } else {
                    // Snap to nearest card
                    self.start_snap_animation(num_windows, card_spacing);
                }
            }
        } else if self.is_scrolling {
            // No velocity samples, just snap
            self.start_snap_animation(num_windows, card_spacing);
        }

        self.switcher_touch_start_x = None;
        self.switcher_touch_last_x = None;
        self.switcher_touch_times.clear();
        self.pending_switcher_index = None;
        self.is_scrolling = false;
        index
    }

    /// Start snap animation to nearest card
    fn start_snap_animation(&mut self, num_windows: usize, card_spacing: f64) {
        if num_windows == 0 || card_spacing <= 0.0 {
            return;
        }

        // Find nearest card
        let current_card = (self.switcher_scroll / card_spacing).round();
        let target = (current_card * card_spacing).clamp(0.0, self.get_switcher_max_scroll(num_windows, card_spacing));

        self.switcher_snap_target = Some(target);
        self.switcher_animating = true;
        self.switcher_last_update = Some(std::time::Instant::now());
    }

    /// Update switcher physics (call every frame)
    /// Returns true if still animating (needs redraw)
    pub fn update_switcher_physics(&mut self, num_windows: usize, card_spacing: f64) -> bool {
        if !self.switcher_animating {
            return false;
        }

        let now = std::time::Instant::now();
        let dt = self.switcher_last_update
            .map(|t| now.duration_since(t).as_secs_f64())
            .unwrap_or(0.016); // Default to ~60fps
        self.switcher_last_update = Some(now);

        // Clamp dt to avoid physics explosion on lag
        let dt = dt.min(0.05);

        let max_scroll = self.get_switcher_max_scroll(num_windows, card_spacing);

        if let Some(target) = self.switcher_snap_target {
            // Spring animation to target
            let spring_stiffness = 300.0; // Higher = snappier
            let damping = 25.0; // Higher = less bouncy

            let diff = target - self.switcher_scroll;
            let spring_force = diff * spring_stiffness;
            let damping_force = -self.switcher_velocity * damping;

            self.switcher_velocity += (spring_force + damping_force) * dt;
            self.switcher_scroll += self.switcher_velocity * dt;

            // Stop when close enough and slow
            if diff.abs() < 0.5 && self.switcher_velocity.abs() < 10.0 {
                self.switcher_scroll = target;
                self.switcher_velocity = 0.0;
                self.switcher_animating = false;
                self.switcher_snap_target = None;
                return false;
            }
        } else {
            // Momentum with deceleration
            let friction = 3.0; // Deceleration factor
            let decel = -self.switcher_velocity.signum() * friction * self.switcher_velocity.abs().sqrt() * 100.0;

            self.switcher_velocity += decel * dt;
            self.switcher_scroll += self.switcher_velocity * dt;

            // Clamp to bounds with bounce
            if self.switcher_scroll < 0.0 {
                self.switcher_scroll = 0.0;
                self.switcher_velocity = -self.switcher_velocity * 0.3; // Bounce
                if self.switcher_velocity.abs() < 50.0 {
                    self.start_snap_animation(num_windows, card_spacing);
                }
            } else if self.switcher_scroll > max_scroll {
                self.switcher_scroll = max_scroll;
                self.switcher_velocity = -self.switcher_velocity * 0.3;
                if self.switcher_velocity.abs() < 50.0 {
                    self.start_snap_animation(num_windows, card_spacing);
                }
            }

            // When velocity gets low, snap to nearest card
            if self.switcher_velocity.abs() < 200.0 {
                self.start_snap_animation(num_windows, card_spacing);
            }
        }

        true // Still animating
    }

    /// Get the currently focused card index (for highlighting)
    pub fn get_focused_card_index(&self, card_spacing: f64) -> usize {
        if card_spacing <= 0.0 {
            return 0;
        }
        (self.switcher_scroll / card_spacing).round() as usize
    }

    /// Update gesture state from gesture events
    pub fn handle_gesture(&mut self, event: &GestureEvent) {
        match event {
            GestureEvent::EdgeSwipeStart { edge, .. } => {
                self.gesture.edge = Some(*edge);
                self.gesture.progress = 0.0;
                self.gesture.completed = false;
            }
            GestureEvent::EdgeSwipeUpdate { progress, velocity, .. } => {
                self.gesture.progress = *progress;
                self.gesture.velocity = *velocity;
            }
            GestureEvent::EdgeSwipeEnd { edge, completed, velocity, .. } => {
                self.gesture.completed = *completed;
                self.gesture.velocity = *velocity;

                if *completed {
                    match edge {
                        Edge::Bottom => {
                            // Swipe up from bottom edge
                            // In Switcher/QuickSettings view: always go home (no keyboard logic)
                            // In App view: handled by end_home_gesture() which has keyboard-threshold logic
                            if self.view == ShellView::Switcher || self.view == ShellView::QuickSettings {
                                tracing::info!("Gesture completed in {:?}: switching to Home view", self.view);
                                self.set_view(ShellView::Home);
                            }
                            // App view is handled by end_home_gesture() in state.rs
                        }
                        Edge::Right => {
                            // Swipe left from right edge
                            // In QuickSettings: go to Home (app grid)
                            // Otherwise: go to Switcher
                            if self.view == ShellView::QuickSettings {
                                tracing::info!("Gesture completed in QuickSettings: switching to Home view");
                                self.set_view(ShellView::Home);
                            } else {
                                tracing::info!("Gesture completed: switching to Switcher view");
                                self.set_view(ShellView::Switcher);
                            }
                        }
                        Edge::Top => {
                            // Swipe down - close app (handled by compositor)
                        }
                        Edge::Left => {
                            // Swipe right from left edge - quick settings panel
                            tracing::info!("Gesture completed: switching to QuickSettings view");
                            self.set_view(ShellView::QuickSettings);
                        }
                    }
                }

                // Reset gesture after handling
                self.gesture.edge = None;
                self.gesture.progress = 0.0;
            }
            _ => {}
        }
    }

    /// Called when an app is launched - switch to app view
    pub fn app_launched(&mut self) {
        self.set_view(ShellView::App);
        self.gesture = GestureState::default();
    }

    /// Called when switching to an app from switcher
    pub fn switch_to_app(&mut self) {
        self.set_view(ShellView::App);
        self.gesture = GestureState::default();
    }

    /// Close the app switcher (go back to current app, or home if no apps)
    pub fn close_switcher(&mut self, has_windows: bool) {
        self.set_view(if has_windows { ShellView::App } else { ShellView::Home });
        self.gesture = GestureState::default();
        self.switcher_scroll = 0.0;
        self.switcher_velocity = 0.0;
        self.switcher_animating = false;
        self.switcher_snap_target = None;
        self.switcher_touch_times.clear();
    }

    /// Open the app switcher with the current (topmost) app centered
    /// num_windows: total number of windows
    /// card_spacing: spacing between cards in the switcher
    /// from_gesture: true if opened via edge swipe gesture (animation already done)
    pub fn open_switcher(&mut self, num_windows: usize, card_spacing: f64) {
        self.open_switcher_ex(num_windows, card_spacing, false);
    }

    /// Open the app switcher with optional gesture flag
    pub fn open_switcher_ex(&mut self, num_windows: usize, card_spacing: f64, from_gesture: bool) {
        self.set_view(ShellView::Switcher);
        self.gesture = GestureState::default();
        // Set scroll so the topmost window (last index) is centered
        // In switcher: card_scroll_pos = i * card_spacing - scroll_offset
        // For window at index (num_windows-1) to be at position 0:
        // scroll_offset = (num_windows - 1) * card_spacing
        self.switcher_scroll = if num_windows > 0 {
            (num_windows - 1) as f64 * card_spacing
        } else {
            0.0
        };
        self.switcher_velocity = 0.0;
        self.switcher_animating = false;
        self.switcher_snap_target = None;
        self.switcher_touch_times.clear();

        // Don't start animation if opened via gesture (gesture already drove the animation)
        // Animation is complete when from_gesture is true
        self.switcher_enter_anim = false;
        self.switcher_enter_start = None;
    }

    /// Get switcher enter animation progress (0.0 to 1.0)
    /// Returns 1.0 if not animating (animation complete)
    /// Animation lasts 250ms with ease-out curve
    pub fn get_switcher_enter_progress(&self) -> f32 {
        if !self.switcher_enter_anim {
            return 1.0;
        }

        let start = match self.switcher_enter_start {
            Some(s) => s,
            None => return 1.0,
        };

        let elapsed = start.elapsed().as_millis() as f32;
        let duration = 250.0; // 250ms animation

        if elapsed >= duration {
            return 1.0;
        }

        // Progress 0.0 to 1.0 with ease-out curve
        let linear = elapsed / duration;
        1.0 - (1.0 - linear).powi(3) // Cubic ease-out
    }

    /// Update animation state (call periodically to clean up completed animations)
    pub fn update_switcher_enter_anim(&mut self) {
        if self.switcher_enter_anim {
            if let Some(start) = self.switcher_enter_start {
                if start.elapsed().as_millis() >= 250 {
                    self.switcher_enter_anim = false;
                    self.switcher_enter_start = None;
                }
            }
        }
    }

    /// Sync Quick Settings panel with current system status
    pub fn sync_quick_settings(&mut self, system: &crate::system::SystemStatus) {
        self.quick_settings.update_from_system(system);
    }

    /// Check if shell UI should be visible
    pub fn is_visible(&self) -> bool {
        match self.view {
            ShellView::App => {
                // Show during gesture animations
                self.gesture.edge.is_some()
            }
            ShellView::LockScreen | ShellView::Home | ShellView::Switcher | ShellView::QuickSettings | ShellView::PickDefault => true,
        }
    }

    /// Close quick settings panel (go back to previous view)
    pub fn close_quick_settings(&mut self, has_windows: bool) {
        // Go back to app if there are apps, otherwise home
        self.set_view(if has_windows { ShellView::App } else { ShellView::Home });
        self.gesture = GestureState::default();
    }

    /// Show popup menu for a category (after long press)
    pub fn show_popup(&mut self, category_id: &str) {
        self.popup_showing = true;
        self.popup_category_id = Some(category_id.to_string());
    }

    /// Hide popup menu
    pub fn hide_popup(&mut self) {
        self.popup_showing = false;
    }

    /// Enter wiggle mode for rearranging icons
    pub fn enter_wiggle_mode(&mut self) {
        self.long_press_menu = None;
        self.menu_just_opened = false;
        self.popup_showing = false;
        self.popup_category_id = None;
        self.wiggle_mode = true;
        self.wiggle_start_time = Some(std::time::Instant::now());
    }

    /// Enter pick default view for a category
    pub fn enter_pick_default(&mut self, category_id: &str) {
        // Clear the long press menu state (like enter_wiggle_mode does)
        self.long_press_menu = None;
        self.menu_just_opened = false;
        self.popup_showing = false;
        self.popup_category_id = Some(category_id.to_string());
        self.set_view(ShellView::PickDefault);
        self.pick_default_just_opened = true;  // Don't process touch on same event
    }

    /// Exit pick default view (go back to home)
    pub fn exit_pick_default(&mut self) {
        self.popup_category_id = None;
        self.set_view(ShellView::Home);
        self.pick_default_just_opened = false;
    }

    /// Select a new default app for the current pick default category
    pub fn select_default_app(&mut self, exec: &str) {
        if let Some(ref category_id) = self.popup_category_id.clone() {
            if exec == "flick-default" {
                // Set to the Flick native app path using the category ID
                let flick_exec = format!(
                    r#"sh -c "$HOME/Flick/apps/{}/run_{}.sh""#,
                    category_id, category_id
                );
                self.app_manager.set_category_app(category_id, flick_exec);
            } else {
                self.app_manager.set_category_app(category_id, exec.to_string());
            }
            self.exit_pick_default();
        }
    }

    /// Handle touch on the shell (returns app exec if app was tapped)
    pub fn handle_touch(&mut self, pos: Point<f64, Logical>) -> Option<String> {
        if self.view != ShellView::Home {
            return None;
        }

        // Check if touch is on a category tile
        if let Some(category_id) = self.hit_test_category(pos) {
            return self.app_manager.get_exec(&category_id);
        }

        None
    }

    /// Hit test for app grid - returns category ID if hit
    /// Uses Slint's absolute positioning layout constants to match visual display
    pub fn hit_test_category(&self, pos: Point<f64, Logical>) -> Option<String> {
        let grid_order = &self.app_manager.config.grid_order;
        let num_categories = grid_order.len();
        if num_categories == 0 {
            return None;
        }

        let width = self.screen_size.w as f64;
        let height = self.screen_size.h as f64;

        // Match Slint HomeScreen absolute positioning layout exactly
        // Status bar height scales with text_scale (54px * text_scale)
        let status_bar_height = 54.0 * self.text_scale as f64;
        let home_indicator_height = 34.0;
        let grid_padding = 12.0;
        let grid_spacing = 8.0;
        let columns = 4usize;

        // Calculate number of rows based on category count (same as Slint)
        let num_rows = if num_categories > 20 { 6 } else if num_categories > 16 { 5 } else if num_categories > 12 { 4 } else if num_categories > 8 { 3 } else if num_categories > 4 { 2 } else { 1 };

        // Grid dimensions (matching Slint calculations)
        let grid_top = status_bar_height + grid_padding;
        let grid_height = height - status_bar_height - home_indicator_height - grid_padding * 2.0;
        let grid_width = width - grid_padding * 2.0;

        // Tile dimensions (matching Slint calculations)
        let tile_width = (grid_width - grid_spacing * 3.0) / 4.0;
        let tile_height = (grid_height - grid_spacing * (num_rows as f64 - 1.0)) / num_rows as f64;

        // Check if above the grid
        if pos.y < grid_top {
            tracing::debug!("Touch above grid at ({:.0},{:.0})", pos.x, pos.y);
            return None;
        }

        // Calculate which tile was hit by checking each tile's bounds
        // Account for scroll offset - tiles scroll up as home_scroll increases
        for i in 0..num_categories {
            let row = i / columns;
            let col = i % columns;

            let tile_x = grid_padding + (tile_width + grid_spacing) * col as f64;
            // Apply scroll offset to visual tile position
            let tile_y = grid_top + (tile_height + grid_spacing) * row as f64 - self.home_scroll;

            // Skip tiles that have scrolled completely above or below the visible grid area
            if tile_y + tile_height < grid_top || tile_y > grid_top + grid_height {
                continue;
            }

            if pos.x >= tile_x && pos.x < tile_x + tile_width &&
               pos.y >= tile_y && pos.y < tile_y + tile_height {
                tracing::debug!("Hit test: pos({:.0},{:.0}) -> tile row={}, col={}, index={}, scroll={:.0}",
                    pos.x, pos.y, row, col, i, self.home_scroll);
                let category_id = &grid_order[i];
                tracing::info!("Hit category {} '{}'", i, category_id);
                return Some(category_id.clone());
            }
        }

        tracing::debug!("Hit test: pos({:.0},{:.0}) -> no tile hit, scroll={:.0}", pos.x, pos.y, self.home_scroll);
        None
    }

    /// Hit test for app grid - returns grid index if hit (for drag/drop)
    /// Also handles dropping below/after the last item
    /// Uses Slint's absolute positioning layout constants to match visual display
    pub fn hit_test_category_index(&self, pos: Point<f64, Logical>) -> Option<usize> {
        let categories = &self.app_manager.config.grid_order;
        let num_categories = categories.len();
        if num_categories == 0 {
            return None;
        }

        let width = self.screen_size.w as f64;
        let height = self.screen_size.h as f64;

        // Match Slint HomeScreen absolute positioning layout exactly
        let status_bar_height = 48.0;
        let home_indicator_height = 34.0;
        let grid_padding = 12.0;
        let grid_spacing = 8.0;
        let columns = 4usize;

        // Calculate number of rows based on category count (same as Slint)
        let num_rows = if num_categories > 20 { 6 } else if num_categories > 16 { 5 } else if num_categories > 12 { 4 } else if num_categories > 8 { 3 } else if num_categories > 4 { 2 } else { 1 };

        // Grid dimensions (matching Slint calculations)
        let grid_top = status_bar_height + grid_padding;
        let grid_height = height - status_bar_height - home_indicator_height - grid_padding * 2.0;
        let grid_width = width - grid_padding * 2.0;

        // Tile dimensions (matching Slint calculations)
        let tile_width = (grid_width - grid_spacing * 3.0) / 4.0;
        let tile_height = (grid_height - grid_spacing * (num_rows as f64 - 1.0)) / num_rows as f64;

        // Helper to get rect for an index (with scroll offset applied)
        let home_scroll = self.home_scroll;
        let get_rect = |index: usize| -> (f64, f64, f64, f64) {
            let row = index / columns;
            let col = index % columns;
            let x = grid_padding + (tile_width + grid_spacing) * col as f64;
            // Apply scroll offset - tiles scroll up as home_scroll increases
            let y = grid_top + (tile_height + grid_spacing) * row as f64 - home_scroll;
            (x, y, tile_width, tile_height)
        };

        // First check for exact hit on a tile (accounting for scroll)
        for i in 0..num_categories {
            let (x, y, w, h) = get_rect(i);
            // Skip tiles that have scrolled completely above or below the visible grid area
            if y + h < grid_top || y > grid_top + grid_height {
                continue;
            }
            if pos.x >= x && pos.x < x + w && pos.y >= y && pos.y < y + h {
                return Some(i);
            }
        }

        // If not on a tile, check if below/after the last row
        let (_, last_y, _, last_h) = get_rect(num_categories - 1);

        // If below the last tile, return the last index (for appending)
        if pos.y > last_y + last_h {
            return Some(num_categories - 1);
        }

        // Check if in empty space after the last tile in its row
        let last_col = (num_categories - 1) % columns;
        if last_col < columns - 1 {
            let (last_x, last_row_y, last_w, _) = get_rect(num_categories - 1);
            if pos.y >= last_row_y && pos.y < last_row_y + tile_height {
                // Check if in the empty space after last tile
                if pos.x > last_x + last_w {
                    return Some(num_categories - 1);
                }
            }
        }

        None
    }

    /// Hit test for app grid - returns app index if hit (legacy, for compatibility)
    fn hit_test_app(&self, pos: Point<f64, Logical>) -> Option<usize> {
        let grid = app_grid::AppGridLayout::new(self.screen_size);

        for (i, app) in self.apps.iter().enumerate() {
            let rect = grid.app_rect(i);
            // Adjust for scroll offset - tiles scroll up as home_scroll increases
            let adjusted_y = rect.y - self.home_scroll;
            // Debug: log each rect
            tracing::debug!("App {} '{}': rect ({:.0},{:.0} {:.0}x{:.0}), touch ({:.0},{:.0}), scroll={:.0}",
                i, app.exec, rect.x, adjusted_y, rect.width, rect.height, pos.x, pos.y, self.home_scroll);
            if pos.x >= rect.x && pos.x < rect.x + rect.width &&
               pos.y >= adjusted_y && pos.y < adjusted_y + rect.height {
                tracing::info!("Hit app {} '{}'", i, app.exec);
                return Some(i);
            }
        }

        tracing::debug!("No app hit at ({:.0},{:.0})", pos.x, pos.y);
        None
    }

    /// Start tracking a touch on Quick Settings panel
    pub fn start_qs_touch(&mut self, x: f64, y: f64) {
        self.qs_touch_start_y = Some(y);
        self.qs_touch_last_y = Some(y);
        self.is_scrolling = false;

        // Check if touching a toggle button
        self.pending_toggle_index = self.quick_settings.hit_test_toggle(x, y);

        // Check if touching brightness slider
        if let Some(brightness) = self.quick_settings.hit_test_brightness(x, y) {
            self.quick_settings.set_brightness(brightness);
        }
    }

    /// Update Quick Settings scroll based on touch movement
    pub fn update_qs_scroll(&mut self, x: f64, y: f64) -> bool {
        if let Some(start_y) = self.qs_touch_start_y {
            let total_delta = (y - start_y).abs();
            if total_delta > 30.0 {
                self.is_scrolling = true;
                self.pending_toggle_index = None;
            }
        }

        if let Some(last_y) = self.qs_touch_last_y {
            let delta = last_y - y;
            self.quick_settings.scroll(delta);
        }

        // Update brightness if dragging on slider
        if let Some(brightness) = self.quick_settings.hit_test_brightness(x, y) {
            self.quick_settings.set_brightness(brightness);
        }

        self.qs_touch_last_y = Some(y);
        self.is_scrolling
    }

    /// End Quick Settings touch - toggle if it was a tap, returns toggle ID for system action
    pub fn end_qs_touch(&mut self) -> Option<String> {
        let toggle_id = if !self.is_scrolling {
            if let Some(index) = self.pending_toggle_index.take() {
                self.quick_settings.toggle(index)
            } else {
                None
            }
        } else {
            None
        };
        self.qs_touch_start_y = None;
        self.qs_touch_last_y = None;
        self.pending_toggle_index = None;
        self.is_scrolling = false;
        toggle_id
    }

    /// Get current brightness value for system sync
    pub fn get_qs_brightness(&self) -> f32 {
        self.quick_settings.brightness
    }
}
