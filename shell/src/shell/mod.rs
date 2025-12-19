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

use smithay::utils::{Logical, Point, Size};
use crate::input::{Edge, GestureEvent};
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
    /// The category being configured
    pub category: apps::AppCategory,
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
    /// Touch tracking for scrolling (home screen - vertical)
    pub scroll_touch_start_y: Option<f64>,
    pub scroll_touch_last_y: Option<f64>,
    /// Touch tracking for app switcher (horizontal)
    pub switcher_touch_start_x: Option<f64>,
    pub switcher_touch_last_x: Option<f64>,
    /// Pending app launch (exec command) - waits for touch up to confirm tap vs scroll
    pub pending_app_launch: Option<String>,
    /// Pending category for long press menu
    pub pending_category: Option<apps::AppCategory>,
    /// Pending switcher window index - waits for touch up to confirm tap vs scroll
    pub pending_switcher_index: Option<usize>,
    /// Whether current touch is scrolling (moved significantly)
    pub is_scrolling: bool,
    /// Long press tracking
    pub long_press_start: Option<std::time::Instant>,
    pub long_press_category: Option<apps::AppCategory>,
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
    /// Current drag position
    pub drag_position: Option<Point<f64, Logical>>,
    /// Whether popup menu is showing (for Slint state sync)
    pub popup_showing: bool,
    /// Category for popup menu / pick default view
    pub popup_category: Option<apps::AppCategory>,
    /// Flag to prevent processing touch on same event that opened pick default view
    pub pick_default_just_opened: bool,
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
                // Initialize lock screen mode based on config
                let lock_mode = match lock_config.method {
                    lock_screen::LockMethod::None => "none",
                    lock_screen::LockMethod::Pin => "pin",
                    lock_screen::LockMethod::Pattern => "pattern",
                    lock_screen::LockMethod::Password => "password",
                };
                ui.set_lock_mode(lock_mode);
                tracing::info!("Lock screen mode set to: {}", lock_mode);
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
            scroll_touch_start_y: None,
            scroll_touch_last_y: None,
            switcher_touch_start_x: None,
            switcher_touch_last_x: None,
            pending_app_launch: None,
            pending_category: None,
            pending_switcher_index: None,
            is_scrolling: false,
            long_press_start: None,
            long_press_category: None,
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
            drag_position: None,
            popup_showing: false,
            popup_category: None,
            pick_default_just_opened: false,
            icon_cache: icons::IconCache::new(128), // 128px icons for larger tiles
            lock_config: lock_config.clone(),
            lock_state,
            slint_ui,
            // Set lock_screen_active based on whether we start with a lock screen
            lock_screen_active: lock_config.method != lock_screen::LockMethod::None,
            last_unlock_time: None,
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

    /// Attempt to unlock with the current input
    /// Returns true if unlock succeeded
    pub fn try_unlock(&mut self) -> bool {
        match self.lock_state.input_mode {
            lock_screen::LockInputMode::Pin => {
                if self.lock_config.verify_pin(&self.lock_state.entered_pin) {
                    self.unlock();
                    return true;
                }
            }
            lock_screen::LockInputMode::Pattern => {
                if self.lock_config.verify_pattern(&self.lock_state.pattern_nodes) {
                    self.unlock();
                    return true;
                }
            }
            lock_screen::LockInputMode::Password => {
                if let Some(username) = lock_screen::get_current_user() {
                    if lock_screen::authenticate_pam(&username, &self.lock_state.entered_password) {
                        self.unlock();
                        return true;
                    }
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

        // Hide keyboard when leaving App view
        if self.view == ShellView::App && new_view != ShellView::App {
            if let Some(ref slint_ui) = self.slint_ui {
                if slint_ui.is_keyboard_visible() {
                    tracing::info!("Hiding keyboard - leaving App view for {:?}", new_view);
                    slint_ui.set_keyboard_visible(false);
                }
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

    /// Unlock and transition to home screen
    pub fn unlock(&mut self) {
        tracing::info!("Lock screen unlocked");
        self.lock_screen_active = false;
        self.last_unlock_time = Some(std::time::Instant::now());
        self.set_view(ShellView::Home);
        self.lock_state.reset_input();
        self.lock_state.failed_attempts = 0;
        self.lock_state.error_message = None;
        // Clear the unlock signal file if it exists
        let signal_path = unlock_signal_path();
        if signal_path.exists() {
            let _ = std::fs::remove_file(&signal_path);
        }
        // Force Slint UI redraw to show home screen
        if let Some(ref slint_ui) = self.slint_ui {
            slint_ui.request_redraw();
            tracing::info!("Requested Slint UI redraw after unlock");
        }
    }

    /// Lock the screen - sets up state, compositor will launch Python app
    pub fn lock(&mut self) {
        tracing::info!("Locking screen");
        self.lock_config = lock_screen::LockConfig::load(); // Reload latest config
        if self.lock_config.method != lock_screen::LockMethod::None {
            self.lock_screen_active = true;
            self.set_view(ShellView::LockScreen);
            self.lock_state = lock_screen::LockScreenState::new(&self.lock_config);
            // Clear any stale unlock signal
            let signal_path = unlock_signal_path();
            if signal_path.exists() {
                let _ = std::fs::remove_file(&signal_path);
            }
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

    /// Launch the external lock screen app (called by compositor)
    pub fn launch_lock_screen_app(&self, socket_name: &str) -> bool {
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

        match std::process::Command::new("sh")
            .arg("-c")
            .arg(&shell_cmd)
            .env("WAYLAND_DISPLAY", socket_name)
            .env("QT_QPA_PLATFORM", "wayland")
            .env("QT_WAYLAND_CLIENT_BUFFER_INTEGRATION", "shm")
            .env("FLICK_STATE_DIR", &state_dir)
            .env("XDG_RUNTIME_DIR", std::env::var("XDG_RUNTIME_DIR").unwrap_or_default())
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

    /// Start tracking a touch on home screen (potential scroll or tap)
    pub fn start_home_touch(&mut self, y: f64, pending_app: Option<String>) {
        self.scroll_touch_start_y = Some(y);
        self.scroll_touch_last_y = Some(y);
        self.pending_app_launch = pending_app;
        self.is_scrolling = false;
        self.long_press_start = Some(std::time::Instant::now());
    }

    /// Start tracking a touch on a specific category (for long press detection)
    pub fn start_category_touch(&mut self, pos: Point<f64, Logical>, category: apps::AppCategory) {
        self.scroll_touch_start_y = Some(pos.y);
        self.scroll_touch_last_y = Some(pos.y);
        self.pending_category = Some(category);
        self.pending_app_launch = self.app_manager.get_exec(category);
        self.is_scrolling = false;
        self.long_press_start = Some(std::time::Instant::now());
        self.long_press_category = Some(category);
        self.long_press_position = Some(pos);
    }

    /// Check if a long press has occurred (300ms threshold)
    pub fn check_long_press(&mut self) -> Option<apps::AppCategory> {
        if self.is_scrolling {
            return None;
        }
        if let (Some(start), Some(category)) = (self.long_press_start, self.long_press_category) {
            if start.elapsed() >= std::time::Duration::from_millis(300) {
                // Clear the pending app launch since this is a long press
                self.pending_app_launch = None;
                return Some(category);
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
        if let Some(category) = self.check_long_press() {
            // Skip long press menu for non-customizable categories (like Settings)
            if !category.is_customizable() {
                tracing::debug!("Long press on non-customizable category {:?}, ignoring", category);
                self.long_press_start = None;
                self.long_press_category = None;
                return false;
            }
            if let Some(pos) = self.long_press_position {
                tracing::info!("Long press triggered for {:?} at ({:.0}, {:.0})", category, pos.x, pos.y);
                self.show_long_press_menu(category, pos);
                // Clear long press tracking so it doesn't trigger again
                self.long_press_start = None;
                self.long_press_category = None;
                return true;
            }
        }
        false
    }

    /// Show long press menu for a category
    pub fn show_long_press_menu(&mut self, category: apps::AppCategory, position: Point<f64, Logical>) {
        let available_apps = self.app_manager.apps_for_category(category)
            .into_iter()
            .cloned()
            .collect();
        self.long_press_menu = Some(LongPressMenu {
            category,
            position,
            available_apps,
            highlighted: None,
            level: MenuLevel::Main,
            scroll_offset: 0.0,
        });
        self.menu_just_opened = true; // Don't close on this touch release

        // Also set Slint popup state
        self.popup_showing = true;
        self.popup_category = Some(category);
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
                    let category = menu.category;
                    self.app_manager.set_category_app(category, exec);
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
        self.drag_position = None;
        // Ensure all popup/menu state is cleared for clean long press detection
        self.long_press_menu = None;
        self.menu_just_opened = false;
        self.popup_showing = false;
        self.popup_category = None;
    }

    /// Start dragging a category in wiggle mode
    pub fn start_drag(&mut self, index: usize, pos: Point<f64, Logical>) {
        if self.wiggle_mode {
            self.dragging_index = Some(index);
            self.drag_position = Some(pos);
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
                self.pending_category = None;
                self.long_press_start = None;
                self.long_press_category = None;
                self.long_press_position = None;
            }
        }

        if let Some(last_y) = self.scroll_touch_last_y {
            let delta = last_y - y; // Scroll down when finger moves up

            // Calculate max scroll based on content height (must match AppGrid calculation)
            let num_items = self.app_manager.config.grid_order.len();
            let grid = app_grid::AppGridLayout::new(self.screen_size);
            let rows = (num_items + grid.columns - 1) / grid.columns;
            let cell_height = grid.cell_size * 1.2;
            let content_height = rows as f64 * cell_height + 72.0; // top_offset = 72
            let max_scroll = (content_height - self.screen_size.h as f64 + 100.0).max(0.0);

            self.home_scroll = (self.home_scroll + delta).clamp(0.0, max_scroll);
        }
        self.scroll_touch_last_y = Some(y);
        self.is_scrolling
    }

    /// End touch gesture - returns app exec string if this was a tap (not scroll)
    pub fn end_home_touch(&mut self) -> Option<String> {
        let app = if !self.is_scrolling {
            self.pending_app_launch.take()
        } else {
            None
        };
        self.scroll_touch_start_y = None;
        self.scroll_touch_last_y = None;
        self.pending_app_launch = None;
        self.pending_category = None;
        self.is_scrolling = false;
        self.long_press_start = None;
        self.long_press_category = None;
        self.long_press_position = None;
        app
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
                            // Swipe left from right edge - app switcher
                            tracing::info!("Gesture completed: switching to Switcher view");
                            self.set_view(ShellView::Switcher);
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
    pub fn open_switcher(&mut self, num_windows: usize, card_spacing: f64) {
        // Start enter animation if coming from App view
        let was_in_app = self.view == ShellView::App;

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

        // Start shrink animation if there are windows and we came from App view
        if was_in_app && num_windows > 0 {
            self.switcher_enter_anim = true;
            self.switcher_enter_start = Some(std::time::Instant::now());
        } else {
            self.switcher_enter_anim = false;
            self.switcher_enter_start = None;
        }
    }

    /// Get switcher enter animation progress (0.0 to 1.0, None if not animating)
    /// Animation lasts 250ms with ease-out curve
    pub fn get_switcher_enter_progress(&mut self) -> Option<f32> {
        if !self.switcher_enter_anim {
            return None;
        }

        let start = self.switcher_enter_start?;
        let elapsed = start.elapsed().as_millis() as f32;
        let duration = 250.0; // 250ms animation

        if elapsed >= duration {
            // Animation complete
            self.switcher_enter_anim = false;
            self.switcher_enter_start = None;
            return None;
        }

        // Progress 0.0 to 1.0 with ease-out curve
        let linear = elapsed / duration;
        let eased = 1.0 - (1.0 - linear).powi(3); // Cubic ease-out
        Some(eased)
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
    pub fn show_popup(&mut self, category: apps::AppCategory) {
        self.popup_showing = true;
        self.popup_category = Some(category);
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
        self.popup_category = None;
        self.wiggle_mode = true;
        self.wiggle_start_time = Some(std::time::Instant::now());
    }

    /// Enter pick default view for a category
    pub fn enter_pick_default(&mut self, category: apps::AppCategory) {
        // Clear the long press menu state (like enter_wiggle_mode does)
        self.long_press_menu = None;
        self.menu_just_opened = false;
        self.popup_showing = false;
        self.popup_category = Some(category);
        self.set_view(ShellView::PickDefault);
        self.pick_default_just_opened = true;  // Don't process touch on same event
    }

    /// Exit pick default view (go back to home)
    pub fn exit_pick_default(&mut self) {
        self.popup_category = None;
        self.set_view(ShellView::Home);
        self.pick_default_just_opened = false;
    }

    /// Select a new default app for the current pick default category
    pub fn select_default_app(&mut self, exec: &str) {
        if let Some(category) = self.popup_category {
            self.app_manager.set_category_app(category, exec.to_string());
            self.exit_pick_default();
        }
    }

    /// Handle touch on the shell (returns app exec if app was tapped)
    pub fn handle_touch(&mut self, pos: Point<f64, Logical>) -> Option<String> {
        if self.view != ShellView::Home {
            return None;
        }

        // Check if touch is on a category tile
        if let Some(category) = self.hit_test_category(pos) {
            return self.app_manager.get_exec(category);
        }

        None
    }

    /// Hit test for app grid - returns category if hit
    /// Uses Slint's layout constants to match visual display
    pub fn hit_test_category(&self, pos: Point<f64, Logical>) -> Option<apps::AppCategory> {
        let categories = &self.app_manager.config.grid_order;
        let width = self.screen_size.w as f64;

        // Match Slint HomeScreen layout constants exactly
        let status_bar_height = 48.0;
        let padding = 24.0;
        let row_height = 140.0;
        let row_spacing = 16.0;
        let col_spacing = 12.0;
        let columns = 4;

        // Grid starts after status bar + padding
        let grid_start_y = status_bar_height + padding;

        // Check if above the grid
        if pos.y < grid_start_y - self.home_scroll {
            tracing::debug!("Touch above grid at ({:.0},{:.0})", pos.x, pos.y);
            return None;
        }

        // Calculate grid dimensions
        let grid_width = width - 2.0 * padding;
        let col_width = (grid_width - (columns - 1) as f64 * col_spacing) / columns as f64;

        // Adjust touch position for scroll
        let scroll_adjusted_y = pos.y + self.home_scroll;
        let relative_y = scroll_adjusted_y - grid_start_y;

        // Calculate row (accounting for spacing)
        let row_with_spacing = row_height + row_spacing;
        let row = (relative_y / row_with_spacing) as usize;

        // Check if tap is between rows (in the spacing)
        let y_in_row = relative_y - (row as f64 * row_with_spacing);
        if y_in_row > row_height {
            tracing::debug!("Touch in row gap at ({:.0},{:.0})", pos.x, pos.y);
            return None;
        }

        // Calculate column
        let relative_x = pos.x - padding;
        if relative_x < 0.0 || relative_x > grid_width {
            tracing::debug!("Touch outside grid horizontally at ({:.0},{:.0})", pos.x, pos.y);
            return None;
        }

        let col_with_spacing = col_width + col_spacing;
        let col = (relative_x / col_with_spacing) as usize;

        // Check if tap is between columns (in the spacing)
        let x_in_col = relative_x - (col as f64 * col_with_spacing);
        if x_in_col > col_width {
            tracing::debug!("Touch in column gap at ({:.0},{:.0})", pos.x, pos.y);
            return None;
        }

        // Calculate index
        let index = row * columns + col;

        tracing::debug!("Hit test: pos({:.0},{:.0}) scroll={:.0} -> row={}, col={}, index={}",
            pos.x, pos.y, self.home_scroll, row, col, index);

        // Return category if valid index
        if index < categories.len() {
            let category = categories[index];
            tracing::info!("Hit category {} '{}'", index, category.display_name());
            Some(category)
        } else {
            tracing::debug!("Index {} out of range ({})", index, categories.len());
            None
        }
    }

    /// Hit test for app grid - returns grid index if hit (for drag/drop)
    /// Also handles dropping below/after the last item
    /// Uses Slint's layout constants to match visual display
    pub fn hit_test_category_index(&self, pos: Point<f64, Logical>) -> Option<usize> {
        let categories = &self.app_manager.config.grid_order;
        let num_categories = categories.len();
        let width = self.screen_size.w as f64;

        if num_categories == 0 {
            return None;
        }

        // Match Slint HomeScreen layout constants exactly
        let status_bar_height = 48.0;
        let padding = 24.0;
        let row_height = 140.0;
        let row_spacing = 16.0;
        let col_spacing = 12.0;
        let columns = 4;

        // Grid starts after status bar + padding
        let grid_start_y = status_bar_height + padding;

        // Calculate grid dimensions
        let grid_width = width - 2.0 * padding;
        let col_width = (grid_width - (columns - 1) as f64 * col_spacing) / columns as f64;
        let row_with_spacing = row_height + row_spacing;
        let col_with_spacing = col_width + col_spacing;

        // Helper to get rect for an index
        let get_rect = |index: usize| -> (f64, f64, f64, f64) {
            let row = index / columns;
            let col = index % columns;
            let x = padding + col as f64 * col_with_spacing;
            let y = grid_start_y + row as f64 * row_with_spacing - self.home_scroll;
            (x, y, col_width, row_height)
        };

        // First check for exact hit on a tile
        for i in 0..num_categories {
            let (x, y, w, h) = get_rect(i);
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
            if pos.y >= last_row_y && pos.y < last_row_y + row_height {
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
