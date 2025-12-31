//! Compositor state - the heart of Flick

use std::{
    cell::RefCell,
    collections::HashMap,
    ffi::OsString,
    rc::Rc,
    sync::Arc,
    time::Instant,
};

use smithay::{
    delegate_compositor, delegate_data_device, delegate_dmabuf, delegate_output, delegate_seat,
    delegate_shm, delegate_xdg_shell,
    backend::allocator::{dmabuf::Dmabuf, Buffer},
    desktop::{PopupManager, Space, Window},
    input::{dnd::DndGrabHandler, Seat, SeatHandler, SeatState},
    output::Output,
    reexports::{
        calloop::LoopHandle,
        wayland_protocols::xdg::shell::server::xdg_toplevel,
        wayland_server::{
            backend::{ClientData, ClientId, DisconnectReason},
            protocol::{wl_buffer, wl_seat, wl_surface::WlSurface},
            Display, DisplayHandle, Resource,
        },
    },
    utils::{Clock, Logical, Monotonic, Serial, Size},
    wayland::{
        buffer::BufferHandler,
        compositor::{
            get_parent, is_sync_subsurface, with_states, CompositorClientState, CompositorHandler,
            CompositorState, SurfaceAttributes,
        },
        dmabuf::{DmabufGlobal, DmabufHandler, DmabufState, ImportNotifier},
        output::{OutputHandler, OutputManagerState},
        selection::{
            data_device::{
                set_data_device_focus, DataDeviceHandler, DataDeviceState,
                WaylandDndGrabHandler,
            },
            SelectionHandler,
        },
        shell::xdg::{
            PopupSurface, PositionerState, ToplevelSurface, XdgShellHandler, XdgShellState,
        },
        shm::{with_buffer_contents, ShmHandler, ShmState},
        socket::ListeningSocketSource,
    },
    wayland::xwayland_shell::XWaylandShellState,
    xwayland::{xwm::X11Wm, XWayland},
};

/// Stored buffer data for a surface (for rendering without Smithay's renderer)
#[derive(Debug, Clone)]
pub struct StoredBuffer {
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub format: u32, // wl_shm format
    pub pixels: Vec<u8>,
}

/// EGL-imported texture data
#[derive(Debug)]
pub struct EglTextureBuffer {
    pub texture_id: u32,
    pub width: u32,
    pub height: u32,
    pub egl_image: *mut std::ffi::c_void,
}

// Mark as Send+Sync since the texture ID and EGL image are just handles
unsafe impl Send for EglTextureBuffer {}
unsafe impl Sync for EglTextureBuffer {}

/// User data key for storing buffer data on surfaces
#[derive(Debug, Default)]
pub struct SurfaceBufferData {
    /// SHM buffer pixels (if available)
    pub buffer: Option<StoredBuffer>,
    /// EGL texture (if imported)
    pub egl_texture: Option<EglTextureBuffer>,
    /// Flag indicating this surface needs EGL import (SHM failed)
    pub needs_egl_import: bool,
    /// Raw wl_buffer pointer for EGL import (stored during commit)
    pub wl_buffer_ptr: Option<*mut std::ffi::c_void>,
    /// The actual WlBuffer for releasing after import
    pub pending_buffer: Option<wl_buffer::WlBuffer>,
}

use crate::input::{GestureRecognizer, GestureAction};
use crate::viewport::Viewport;
use crate::shell::Shell;
use crate::system::SystemStatus;
use crate::text_input::{TextInputState, TextInputHandler};
use crate::android_wlegl::{AndroidWleglState, AndroidWleglHandler};

/// Client-specific state
#[derive(Default)]
pub struct ClientState {
    pub compositor_state: CompositorClientState,
}

impl ClientData for ClientState {
    fn initialized(&self, client_id: ClientId) {
        tracing::info!("Client {:?} initialized", client_id);
    }
    fn disconnected(&self, client_id: ClientId, reason: DisconnectReason) {
        tracing::info!("Client {:?} disconnected: {:?}", client_id, reason);
    }
}

/// The main compositor state
pub struct Flick {
    pub start_time: Instant,
    pub socket_name: OsString,
    pub display_handle: DisplayHandle,
    pub display: Rc<RefCell<Display<Self>>>,
    pub clock: Clock<Monotonic>,

    // Wayland state
    pub compositor_state: CompositorState,
    pub xdg_shell_state: XdgShellState,
    pub shm_state: ShmState,
    pub output_manager_state: OutputManagerState,
    pub data_device_state: DataDeviceState,
    pub seat_state: SeatState<Self>,
    pub seat: Seat<Self>,
    pub text_input_state: TextInputState,
    pub android_wlegl_state: AndroidWleglState,
    pub dmabuf_state: DmabufState,
    pub dmabuf_global: Option<DmabufGlobal>,

    // Desktop
    pub space: Space<Window>,
    pub popup_manager: PopupManager,

    // Outputs
    pub outputs: Vec<Output>,

    // Viewports for desktop apps (virtual 1080p spaces)
    pub viewports: HashMap<u32, Viewport>,
    pub next_viewport_id: u32,

    // Screen size (logical - may be swapped when rotated)
    pub screen_size: Size<i32, Logical>,
    // Physical display size (never changes, used for touch coordinate transformation)
    pub physical_display_size: Size<i32, Logical>,

    // XWayland
    pub xwayland: Option<XWayland>,
    pub xwm: Option<X11Wm>,
    pub xwayland_shell_state: Option<XWaylandShellState>,

    // Gesture recognition
    pub gesture_recognizer: GestureRecognizer,

    // Close gesture animation state
    pub close_gesture_window: Option<Window>,
    pub close_gesture_original_y: i32,  // Original Y position
    /// Home gesture state (swipe up from bottom - slides app upward)
    pub home_gesture_window: Option<Window>,
    pub home_gesture_original_y: i32,
    /// Track if home gesture has passed keyboard threshold (for keyboard-first gesture)
    pub home_gesture_past_keyboard: bool,

    /// Switcher transition gesture (swipe from right - app shrinks into card)
    pub switcher_gesture_active: bool,
    pub switcher_gesture_progress: f64,

    /// Quick settings transition gesture (swipe from left - slides in from left)
    pub qs_gesture_active: bool,
    pub qs_gesture_progress: f64,

    /// Return gesture from Switcher to Home (swipe from left edge)
    pub switcher_return_active: bool,
    pub switcher_return_progress: f64,
    pub switcher_return_start_progress: f64,  // Initial progress when gesture started

    /// Return gesture from QuickSettings to Home (swipe from right edge)
    pub qs_return_active: bool,
    pub qs_return_progress: f64,
    pub qs_return_start_progress: f64,  // Initial progress when gesture started

    /// Per-slot keyboard touch tracking for multi-touch support
    /// Maps touch slot ID -> initial touch position
    pub keyboard_touch_initial: HashMap<i32, smithay::utils::Point<f64, smithay::utils::Logical>>,
    /// Maps touch slot ID -> last known touch position
    pub keyboard_touch_last: HashMap<i32, smithay::utils::Point<f64, smithay::utils::Logical>>,
    /// Keyboard dismiss gesture - which slot is dragging (if any)
    pub keyboard_dismiss_slot: Option<i32>,
    /// Start Y position for dismiss gesture
    pub keyboard_dismiss_start_y: f64,
    /// Current offset for dismiss gesture
    pub keyboard_dismiss_offset: f64,
    pub keyboard_pointer_cleared: bool, // Track if we've sent pointer_exit during swipe

    /// Per-window keyboard visibility state (surface ID -> keyboard was visible)
    pub window_keyboard_state: HashMap<smithay::reexports::wayland_server::backend::ObjectId, bool>,

    // Touch visual effects (distortion-based fisheye and ripples)
    pub touch_effects: crate::touch_effects::TouchEffectManager,
    pub touch_effects_enabled: bool,
    pub settings_last_check: std::time::Instant,

    // System status refresh timer (battery, wifi, etc.)
    pub system_last_refresh: std::time::Instant,

    // Auto-lock timer - tracks last user input for idle detection
    pub last_activity: std::time::Instant,

    // Touch position tracking for hwcomposer backend
    pub last_touch_pos: HashMap<i32, smithay::utils::Point<f64, smithay::utils::Logical>>,

    // Keyboard swipe-down dismiss tracking
    pub keyboard_swipe_start_y: Option<f64>,
    pub keyboard_swipe_active: bool,

    // Active window for touch input (explicitly tracked for reliability)
    pub active_window: Option<Window>,

    // Integrated shell UI
    pub shell: Shell,

    // System status (hardware integration)
    pub system: SystemStatus,
}

impl Flick {
    pub fn new(
        display: Display<Self>,
        loop_handle: LoopHandle<'static, Self>,
        screen_size: Size<i32, Logical>,
    ) -> Self {
        let start_time = Instant::now();
        let display_handle = display.handle();
        let clock = Clock::new();

        // Wrap display in Rc<RefCell> so we can access it from multiple places
        let display = Rc::new(RefCell::new(display));

        // Initialize Wayland globals
        let compositor_state = CompositorState::new::<Self>(&display_handle);
        let xdg_shell_state = XdgShellState::new::<Self>(&display_handle);
        let shm_state = ShmState::new::<Self>(&display_handle, vec![]);
        let output_manager_state = OutputManagerState::new_with_xdg_output::<Self>(&display_handle);
        let data_device_state = DataDeviceState::new::<Self>(&display_handle);
        let text_input_state = TextInputState::new::<Self>(&display_handle);
        let android_wlegl_state = AndroidWleglState::new::<Self>(&display_handle);
        let dmabuf_state = DmabufState::new();
        // dmabuf_global is created later in the backend when EGL context is ready

        // Set up seat (input devices)
        let mut seat_state = SeatState::new();
        let mut seat = seat_state.new_wl_seat(&display_handle, "seat0");

        // Add keyboard with default keymap
        seat.add_keyboard(Default::default(), 200, 25)
            .expect("Failed to add keyboard to seat");

        // Add pointer
        seat.add_pointer();

        // Add touch
        seat.add_touch();

        // Create the Wayland socket
        let socket = ListeningSocketSource::new_auto().expect("Failed to create socket");
        let socket_name = socket.socket_name().to_os_string();

        // Fix socket permissions so apps running as user can connect
        // This is needed when the compositor runs as root but apps run as a normal user
        if let Ok(runtime_dir) = std::env::var("XDG_RUNTIME_DIR") {
            let socket_path = std::path::Path::new(&runtime_dir).join(&socket_name);
            if let Some(username) = crate::spawn_user::get_target_user() {
                if let Some((uid, gid, _home)) = crate::spawn_user::get_user_info(&username) {
                    // chown the socket to the real user
                    unsafe {
                        let path_cstr = std::ffi::CString::new(socket_path.to_string_lossy().as_bytes())
                            .expect("Invalid socket path");
                        if libc::chown(path_cstr.as_ptr(), uid, gid) == 0 {
                            tracing::info!("Changed socket ownership to {}:{} ({})", uid, gid, username);
                        } else {
                            tracing::warn!("Failed to chown socket: {}", std::io::Error::last_os_error());
                        }
                        // Also chmod to allow group access
                        if libc::chmod(path_cstr.as_ptr(), 0o770) == 0 {
                            tracing::info!("Set socket permissions to 0770");
                        }
                    }
                }
            }
        }

        loop_handle
            .insert_source(socket, move |client, _, state| {
                tracing::info!("New Wayland client connected!");
                if let Err(err) = state
                    .display_handle
                    .insert_client(client, Arc::new(ClientState::default()))
                {
                    tracing::error!("Error inserting client: {}", err);
                } else {
                    tracing::info!("Client successfully added");
                }
            })
            .expect("Failed to insert socket source");

        tracing::info!("Wayland socket: {:?}", socket_name);

        Self {
            start_time,
            socket_name,
            display_handle,
            display,
            clock,
            compositor_state,
            xdg_shell_state,
            shm_state,
            output_manager_state,
            data_device_state,
            text_input_state,
            android_wlegl_state,
            dmabuf_state,
            dmabuf_global: None,
            seat_state,
            seat,
            space: Space::default(),
            popup_manager: PopupManager::default(),
            outputs: Vec::new(),
            viewports: HashMap::new(),
            next_viewport_id: 0,
            screen_size,
            physical_display_size: screen_size, // Initially same as logical size
            xwayland: None,
            xwm: None,
            xwayland_shell_state: None,
            gesture_recognizer: GestureRecognizer::new(screen_size),
            close_gesture_window: None,
            close_gesture_original_y: 0,
            home_gesture_window: None,
            home_gesture_original_y: 0,
            home_gesture_past_keyboard: false,
            switcher_gesture_active: false,
            switcher_gesture_progress: 0.0,
            qs_gesture_active: false,
            qs_gesture_progress: 0.0,
            switcher_return_active: false,
            switcher_return_progress: 0.0,
            switcher_return_start_progress: 0.0,
            qs_return_active: false,
            qs_return_progress: 0.0,
            qs_return_start_progress: 0.0,
            keyboard_touch_initial: HashMap::new(),
            keyboard_touch_last: HashMap::new(),
            keyboard_dismiss_slot: None,
            keyboard_dismiss_start_y: 0.0,
            keyboard_dismiss_offset: 0.0,
            keyboard_pointer_cleared: false,
            window_keyboard_state: HashMap::new(),
            touch_effects: crate::touch_effects::TouchEffectManager::new(),
            touch_effects_enabled: Self::load_compositor_settings(),  // Load from config
            settings_last_check: Instant::now(),
            system_last_refresh: Instant::now(),
            last_activity: Instant::now(),
            last_touch_pos: HashMap::new(),
            keyboard_swipe_start_y: None,
            keyboard_swipe_active: false,
            active_window: None,
            shell: Shell::new(screen_size),
            system: SystemStatus::new(),
        }
    }

    /// Send gesture progress to shell for interactive animations
    /// Format: timestamp|edge|state|progress|velocity
    pub fn send_gesture_progress(&self, edge: &str, state: &str, progress: f64, velocity: f64) {
        use std::io::Write;

        if let Ok(runtime_dir) = std::env::var("XDG_RUNTIME_DIR") {
            let gesture_file = format!("{}/flick-gesture", runtime_dir);
            match std::fs::OpenOptions::new()
                .create(true)
                .write(true)
                .truncate(true)
                .open(&gesture_file)
            {
                Ok(mut file) => {
                    let timestamp = std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .map(|d| d.as_micros())  // Use microseconds for finer granularity
                        .unwrap_or(0);
                    let msg = format!("{}|{}|{}|{:.3}|{:.1}", timestamp, edge, state, progress, velocity);
                    let _ = file.write_all(msg.as_bytes());
                }
                Err(_) => {}
            }
        }
    }

    /// Handle a completed gesture action - manage windows and notify shell
    pub fn handle_gesture_complete(&mut self, action: &GestureAction) {
        // Handle window management based on gesture
        match action {
            GestureAction::AppDrawer | GestureAction::Home => {
                // Bring shell to front for home gestures
                self.bring_shell_to_front();
            }
            GestureAction::AppSwitcher => {
                // Don't bring shell to front - the shell shows its own app switcher overlay
                // which appears on top of everything. Changing focus here causes timing issues.
            }
            GestureAction::CloseApp => {
                // Close gesture is handled by end_close_gesture() in udev.rs
                // Do NOT call close_focused_app() here - it would close a second window
            }
            _ => {}
        }
    }

    /// Bring the shell window (non-X11) to the front
    fn bring_shell_to_front(&mut self) {
        // Find the shell window (Wayland window, not X11)
        let shell_window = self.space.elements()
            .find(|w| w.x11_surface().is_none())
            .cloned();

        if let Some(window) = shell_window {
            // Raise to top by re-mapping with activate=true
            let loc = self.space.element_location(&window).unwrap_or_default();
            self.space.map_element(window.clone(), loc, true);
            tracing::info!("Shell brought to front");

            // Set keyboard focus to shell
            if let Some(surface) = window.toplevel().map(|t| t.wl_surface().clone()) {
                let serial = smithay::utils::SERIAL_COUNTER.next_serial();
                if let Some(keyboard) = self.seat.get_keyboard() {
                    keyboard.set_focus(self, Some(surface), serial);
                }
            }
        }
    }

    /// Close the focused app (topmost non-shell window)
    fn close_focused_app(&mut self) {
        // Find topmost app window (X11 or Wayland - anything that's not our shell)
        // The shell window is the one without an app_id or with our shell's surface
        // For now, we consider any window with a toplevel to be an app
        let app_window = self.space.elements()
            .filter(|w| w.x11_surface().is_some() || w.toplevel().is_some())
            .last()
            .cloned();

        if let Some(window) = app_window {
            if let Some(x11) = window.x11_surface() {
                tracing::info!("Closing X11 window: {:?}", x11.window_id());
                let _ = x11.close();
            } else if let Some(toplevel) = window.toplevel() {
                tracing::info!("Closing Wayland window");
                toplevel.send_close();
            }
            self.space.unmap_elem(&window);

            // Bring shell to front after closing
            self.bring_shell_to_front();
        }
    }

    /// Start close gesture - find the top-most app window and track it
    pub fn start_close_gesture(&mut self) {
        // Find the top-most app window (X11 or Wayland) to animate
        let app_window = self.space.elements()
            .filter(|w| w.x11_surface().is_some() || w.toplevel().is_some())
            .last()
            .cloned();

        if let Some(window) = app_window {
            // Store original position
            if let Some(loc) = self.space.element_location(&window) {
                tracing::info!("Starting close gesture for window at y={}", loc.y);
                self.close_gesture_original_y = loc.y;
                self.close_gesture_window = Some(window);
            }
        }
    }

    /// Update close gesture - move the window down based on progress
    pub fn update_close_gesture(&mut self, progress: f64) {
        if let Some(ref window) = self.close_gesture_window.clone() {
            // Calculate new Y position based on progress
            // progress = finger_distance / swipe_threshold (300px)
            // So offset = progress * 300 gives 1:1 finger tracking
            let swipe_threshold = 300.0;
            let offset = (progress * swipe_threshold) as i32;
            let new_y = self.close_gesture_original_y + offset;

            // Move the window in the space
            if let Some(loc) = self.space.element_location(window) {
                self.space.map_element(window.clone(), (loc.x, new_y), false);
            }
        }
    }

    /// End close gesture - either close the window or animate it back
    pub fn end_close_gesture(&mut self, completed: bool) {
        if let Some(window) = self.close_gesture_window.take() {
            if completed {
                // Haptic feedback for app close
                self.system.haptic_heavy();

                // Close the window
                if let Some(x11) = window.x11_surface() {
                    tracing::info!("Close gesture completed - closing X11 window");
                    let _ = x11.close();
                } else if let Some(toplevel) = window.toplevel() {
                    tracing::info!("Close gesture completed - closing Wayland window");
                    toplevel.send_close();
                }
                self.space.unmap_elem(&window);

                // If no more windows, go to home screen
                let has_windows = self.space.elements().any(|w| w.x11_surface().is_some() || w.toplevel().is_some());
                if !has_windows {
                    tracing::info!("No more windows, switching to Home view");
                    self.shell.set_view(crate::shell::ShellView::Home);
                    self.shell.switcher_scroll = 0.0; // Reset switcher state
                }
            } else {
                // Cancel - restore original position
                tracing::info!("Close gesture cancelled - restoring position");
                if let Some(loc) = self.space.element_location(&window) {
                    self.space.map_element(window, (loc.x, self.close_gesture_original_y), false);
                }
            }
        }
        self.close_gesture_original_y = 0;
    }

    /// Get keyboard height in pixels
    pub fn get_keyboard_height(&self) -> i32 {
        std::cmp::max(200, (self.screen_size.h as f32 * 0.22) as i32)
    }

    /// Start home gesture - find the top-most app window and track it for upward slide
    /// Also starts showing the keyboard progressively (if not already visible)
    /// On lock screen: just shows keyboard (no window tracking, no going home)
    pub fn start_home_gesture(&mut self) {
        tracing::info!("start_home_gesture called, view={:?}", self.shell.view);

        // Handle lock screen keyboard reveal gesture
        if self.shell.view == crate::shell::ShellView::LockScreen {
            tracing::info!("Lock screen: starting keyboard reveal gesture");
            // Just show the keyboard - no window tracking needed
            if let Some(ref slint_ui) = self.shell.slint_ui {
                let was_visible = slint_ui.is_keyboard_visible();
                tracing::info!("Lock screen keyboard: was_visible={}", was_visible);
                if !was_visible {
                    slint_ui.set_keyboard_visible(true);
                    tracing::info!("Lock screen keyboard: NOW SET TO VISIBLE");
                }
            } else {
                tracing::warn!("Lock screen: slint_ui is None!");
            }
            // Set flag to track lock keyboard gesture is active
            self.home_gesture_past_keyboard = false;
            return;
        }

        // Only start if we're viewing an app
        if self.shell.view != crate::shell::ShellView::App {
            return;
        }

        // Find the top-most app window (X11 or Wayland) to animate
        let app_window = self.space.elements()
            .filter(|w| w.x11_surface().is_some() || w.toplevel().is_some())
            .last()
            .cloned();

        if let Some(window) = app_window {
            // Store original position
            if let Some(loc) = self.space.element_location(&window) {
                tracing::info!("Starting home gesture for window at y={}", loc.y);
                self.home_gesture_original_y = loc.y;
                self.home_gesture_window = Some(window);

                // Check if keyboard is already visible
                let keyboard_already_visible = self.shell.slint_ui.as_ref()
                    .map(|ui| ui.is_keyboard_visible())
                    .unwrap_or(false);

                if keyboard_already_visible {
                    // Keyboard already visible - start past keyboard threshold
                    // (this is a pure home gesture)
                    self.home_gesture_past_keyboard = true;
                    tracing::info!("Home gesture: keyboard already visible, going directly to home mode");
                } else {
                    // Show keyboard but start offscreen (will slide up following finger)
                    self.home_gesture_past_keyboard = false;
                    if let Some(ref slint_ui) = self.shell.slint_ui {
                        let keyboard_height = self.get_keyboard_height();
                        tracing::info!("Home gesture: starting keyboard slide-up, height={}", keyboard_height);
                        // Set offset to keyboard height so it starts fully offscreen
                        slint_ui.set_keyboard_y_offset(keyboard_height as f32);
                        slint_ui.set_keyboard_visible(true);
                    }
                }
            }
        }
    }

    /// Update home gesture - move the window UP based on progress
    /// Keyboard visibility is dynamic based on finger position:
    /// - Within keyboard zone: keyboard visible
    /// - In buffer zone (just past keyboard): keyboard still visible, can snap back
    /// - Past buffer zone: keyboard hidden, committed to going home
    /// - If finger moves back into range, keyboard reappears
    /// On lock screen: keyboard stays visible regardless of swipe distance (no "go home")
    pub fn update_home_gesture(&mut self, progress: f64) {
        // Lock screen: just keep keyboard visible, no window movement
        if self.shell.view == crate::shell::ShellView::LockScreen {
            // Keep keyboard visible - don't allow past_keyboard state on lock screen
            // This prevents the "go home" behavior
            return;
        }

        if let Some(ref window) = self.home_gesture_window.clone() {
            // Calculate new Y position - move UP (negative offset)
            // progress = finger_distance / swipe_threshold (300px)
            // So offset = progress * 300 gives 1:1 finger tracking
            let swipe_threshold = 300.0;
            let offset = (progress * swipe_threshold) as i32;
            let new_y = self.home_gesture_original_y - offset;

            let keyboard_height = self.get_keyboard_height();
            let buffer_zone = 60; // Buffer zone above keyboard where user can still change mind
            let commit_threshold = keyboard_height + buffer_zone;

            // Update keyboard slide-up position based on finger position
            // Keyboard slides up from bottom as finger moves up
            if let Some(ref slint_ui) = self.shell.slint_ui {
                let was_past = self.home_gesture_past_keyboard;

                if offset >= commit_threshold {
                    // Past the buffer zone - committed to going home
                    if !was_past {
                        tracing::info!("Home gesture: committed to home ({}px >= {}px), hiding keyboard",
                            offset, commit_threshold);
                        slint_ui.set_keyboard_visible(false);
                        self.home_gesture_past_keyboard = true;
                    }
                } else {
                    // Within keyboard zone - keyboard follows finger
                    // keyboard_y_offset goes from keyboard_height (offscreen) to 0 (fully visible)
                    let keyboard_offset = (keyboard_height - offset).max(0);
                    slint_ui.set_keyboard_y_offset(keyboard_offset as f32);

                    // This handles the "changed mind" case where user drags up then back down
                    if was_past {
                        tracing::info!("Home gesture: back in range ({}px < {}px), showing keyboard",
                            offset, commit_threshold);
                        slint_ui.set_keyboard_visible(true);
                        slint_ui.set_keyboard_y_offset(keyboard_offset as f32);
                        self.home_gesture_past_keyboard = false;
                    }
                }
            }

            // Move the window in the space
            if let Some(loc) = self.space.element_location(window) {
                self.space.map_element(window.clone(), (loc.x, new_y), false);
            }
        }
    }

    /// End home gesture - behavior depends on finger position at release:
    /// - If keyboard still visible (within buffer zone): snap keyboard into place, stay in app
    /// - If keyboard hidden (past buffer zone): go home
    /// On lock screen: just keep keyboard visible (never go home)
    pub fn end_home_gesture(&mut self, completed: bool) {
        // Lock screen: just keep keyboard visible, don't change view
        if self.shell.view == crate::shell::ShellView::LockScreen {
            tracing::info!("Lock screen: keyboard gesture ended, keeping keyboard visible");
            self.home_gesture_past_keyboard = false;
            return;
        }

        let past_keyboard = self.home_gesture_past_keyboard;

        if let Some(window) = self.home_gesture_window.take() {
            // Calculate how far we actually moved
            let current_y = self.space.element_location(&window)
                .map(|loc| loc.y)
                .unwrap_or(self.home_gesture_original_y);
            let actual_offset = self.home_gesture_original_y - current_y;

            if past_keyboard {
                // User went past the buffer zone - keyboard is already hidden, go home
                tracing::info!("Home gesture: past buffer zone (offset={}px) - going home", actual_offset);

                // Cancel any pending touch sequences before leaving app
                // This ensures the app doesn't think a touch is still in progress
                if let Some(touch) = self.seat.get_touch() {
                    touch.cancel(self);
                    tracing::info!("Home gesture: cancelled pending touch sequences");
                }

                // Haptic feedback for returning to home
                self.system.haptic_click();
                self.shell.set_view(crate::shell::ShellView::Home);

                // Restore window to original position (it will be hidden anyway)
                if let Some(loc) = self.space.element_location(&window) {
                    self.space.map_element(window, (loc.x, self.home_gesture_original_y), false);
                }
            } else if actual_offset > 20 {
                // Released within keyboard/buffer zone with some movement - snap keyboard into place
                tracing::info!("Home gesture: within buffer zone (offset={}px) - snapping keyboard into place",
                    actual_offset);

                // Haptic feedback for keyboard opening
                self.system.haptic_tap();

                // Snap keyboard to fully visible (offset = 0)
                if let Some(ref slint_ui) = self.shell.slint_ui {
                    slint_ui.set_keyboard_y_offset(0.0);
                }

                // Restore window position
                if let Some(loc) = self.space.element_location(&window) {
                    self.space.map_element(window.clone(), (loc.x, self.home_gesture_original_y), false);
                }

                // Resize windows for keyboard (this ensures proper layout)
                self.resize_windows_for_keyboard(true);

                // Save keyboard state for this window
                if let Some(toplevel) = window.toplevel() {
                    let surface_id = toplevel.wl_surface().id();
                    self.window_keyboard_state.insert(surface_id, true);
                }
            } else {
                // Barely moved - cancel the gesture
                tracing::info!("Home gesture cancelled (offset={}px) - hiding keyboard", actual_offset);

                // Restore window position
                if let Some(loc) = self.space.element_location(&window) {
                    self.space.map_element(window, (loc.x, self.home_gesture_original_y), false);
                }

                // Hide keyboard since gesture was cancelled
                if let Some(ref slint_ui) = self.shell.slint_ui {
                    slint_ui.set_keyboard_y_offset(0.0);  // Reset offset
                    slint_ui.set_keyboard_visible(false);
                }
                // Resize windows to full screen
                self.resize_windows_for_keyboard(false);
            }
        }

        self.home_gesture_original_y = 0;
        self.home_gesture_past_keyboard = false;
    }

    /// Resize windows for keyboard visibility
    /// When keyboard shows, reduce window height to fit above keyboard
    /// When keyboard hides, restore full screen height
    pub fn resize_windows_for_keyboard(&mut self, keyboard_visible: bool) {
        let keyboard_height = std::cmp::max(200, (self.screen_size.h as f32 * 0.22) as i32);
        let available_height = if keyboard_visible {
            self.screen_size.h - keyboard_height
        } else {
            self.screen_size.h
        };

        tracing::info!("Resizing windows for keyboard: visible={}, available_height={}",
            keyboard_visible, available_height);

        // Resize all app windows
        for window in self.space.elements() {
            // Only resize actual app windows (not override redirects, etc.)
            if let Some(toplevel) = window.toplevel() {
                let new_size: smithay::utils::Size<i32, smithay::utils::Logical> =
                    (self.screen_size.w, available_height).into();
                toplevel.with_pending_state(|state| {
                    state.size = Some(new_size);
                });
                toplevel.send_configure();
                tracing::debug!("Resized Wayland window to {}x{}", self.screen_size.w, available_height);
            }

            // Handle X11 windows
            if let Some(x11_surface) = window.x11_surface() {
                let new_geo = smithay::utils::Rectangle::from_loc_and_size(
                    (0, 0),
                    (self.screen_size.w, available_height),
                );
                let _ = x11_surface.configure(new_geo);
                tracing::debug!("Resized X11 window to {}x{}", self.screen_size.w, available_height);
            }
        }
    }

    /// Save keyboard state for the current topmost window
    pub fn save_keyboard_state_for_current_window(&mut self) {
        let keyboard_visible = self.shell.slint_ui.as_ref()
            .map(|ui| ui.is_keyboard_visible())
            .unwrap_or(false);

        // Get the topmost window's surface ID
        if let Some(window) = self.space.elements().last() {
            if let Some(toplevel) = window.toplevel() {
                let surface_id = toplevel.wl_surface().id();
                tracing::info!("Saving keyboard state for window {:?}: {}", surface_id, keyboard_visible);
                self.window_keyboard_state.insert(surface_id, keyboard_visible);
            } else if let Some(x11) = window.x11_surface() {
                // For X11 windows, use the window ID converted to an ObjectId-like key
                // We'll store it in a separate way - use a synthetic ID
                tracing::info!("Saving keyboard state for X11 window {}: {}", x11.window_id(), keyboard_visible);
                // X11 windows don't have WlSurface IDs in the same way, skip for now
            }
        }
    }

    /// Restore keyboard state for the current topmost window
    pub fn restore_keyboard_state_for_current_window(&mut self) {
        // Get the topmost window's surface ID
        let keyboard_should_show = if let Some(window) = self.space.elements().last() {
            if let Some(toplevel) = window.toplevel() {
                let surface_id = toplevel.wl_surface().id();
                let should_show = self.window_keyboard_state.get(&surface_id).copied().unwrap_or(false);
                tracing::info!("Restoring keyboard state for window {:?}: {}", surface_id, should_show);
                should_show
            } else {
                false
            }
        } else {
            false
        };

        // Apply the keyboard state
        if let Some(ref slint_ui) = self.shell.slint_ui {
            let current_visible = slint_ui.is_keyboard_visible();
            if keyboard_should_show != current_visible {
                slint_ui.set_keyboard_visible(keyboard_should_show);
                self.resize_windows_for_keyboard(keyboard_should_show);
            }
        }
    }

    /// Write the list of open windows to IPC file for shell to read
    pub fn update_window_list(&self) {
        use std::io::Write;

        if let Ok(runtime_dir) = std::env::var("XDG_RUNTIME_DIR") {
            let window_list_file = format!("{}/flick-windows", runtime_dir);
            match std::fs::OpenOptions::new()
                .create(true)
                .write(true)
                .truncate(true)
                .open(&window_list_file)
            {
                Ok(mut file) => {
                    let timestamp = std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .map(|d| d.as_millis())
                        .unwrap_or(0);

                    let mut content = format!("{}\n", timestamp);
                    let mut window_count = 0;
                    let mut x11_count = 0;

                    for window in self.space.elements() {
                        window_count += 1;
                        // Check for X11 windows first
                        if let Some(x11) = window.x11_surface() {
                            x11_count += 1;
                            let window_id = x11.window_id();
                            let title = x11.title();
                            let title = if title.is_empty() { "Unknown".to_string() } else { title };
                            let class = x11.class();
                            let class = if class.is_empty() { "unknown".to_string() } else { class };
                            // Format: id|title|class
                            content.push_str(&format!("{}|{}|{}\n", window_id, title, class));
                            tracing::debug!("Window list: X11 {} - {} ({})", window_id, title, class);
                        }
                    }

                    // Log periodically if windows exist but none are X11
                    if window_count > 0 && x11_count == 0 {
                        tracing::debug!("Window list: {} windows in space, 0 are X11", window_count);
                    }

                    if let Err(e) = file.write_all(content.as_bytes()) {
                        tracing::warn!("Failed to write window list: {:?}", e);
                    }
                }
                Err(e) => {
                    tracing::warn!("Failed to open window list file: {:?}", e);
                }
            }
        }
    }

    /// Check for focus request from shell and focus the requested window
    pub fn check_focus_request(&mut self) {
        if let Ok(runtime_dir) = std::env::var("XDG_RUNTIME_DIR") {
            let focus_file = format!("{}/flick-focus", runtime_dir);

            if let Ok(content) = std::fs::read_to_string(&focus_file) {
                let content = content.trim();
                if !content.is_empty() {
                    // Clear the file immediately to prevent re-processing
                    let _ = std::fs::write(&focus_file, "");

                    if let Ok(window_id) = content.parse::<u32>() {
                        self.focus_window_by_id(window_id);
                    }
                }
            }
        }
    }

    /// Try to find and focus an existing window matching the exec command
    /// Returns true if a window was found and focused, false if we should launch a new instance
    pub fn try_focus_existing_app(&mut self, exec: &str) -> bool {
        // Extract the binary name from the exec command
        // e.g., "/usr/bin/vlc %u" -> "vlc", "env VAR=val firefox" -> "firefox"
        let binary_name = exec
            .split_whitespace()
            .find(|part| !part.starts_with('%') && !part.contains('=') && *part != "env")
            .map(|s| s.rsplit('/').next().unwrap_or(s))
            .unwrap_or("")
            .to_lowercase();

        if binary_name.is_empty() {
            return false;
        }

        tracing::info!("Looking for existing window matching binary: {}", binary_name);

        // Find a window whose app_id or class matches the binary name
        let matching_window = self.space.elements()
            .find(|window| {
                // Check X11 window class/instance
                if let Some(x11) = window.x11_surface() {
                    let class = x11.class().to_lowercase();
                    let instance = x11.instance().to_lowercase();
                    if class.contains(&binary_name) || instance.contains(&binary_name)
                       || binary_name.contains(&class) || binary_name.contains(&instance) {
                        tracing::info!("Found matching X11 window: class={}, instance={}", class, instance);
                        return true;
                    }
                }
                // For Wayland windows, we can check if wl_surface matches
                // TODO: Add proper app_id checking when we have a way to access it
                false
            })
            .cloned();

        if let Some(window) = matching_window {
            // Raise window to top
            let loc = self.space.element_location(&window).unwrap_or_default();
            self.space.map_element(window.clone(), loc, true);

            // Set keyboard focus
            if let Some(x11) = window.x11_surface() {
                if let Some(wl_surface) = x11.wl_surface() {
                    let serial = smithay::utils::SERIAL_COUNTER.next_serial();
                    if let Some(keyboard) = self.seat.get_keyboard() {
                        keyboard.set_focus(self, Some(wl_surface), serial);
                    }
                }
            } else if let Some(toplevel) = window.toplevel() {
                let wl_surface = toplevel.wl_surface().clone();
                let serial = smithay::utils::SERIAL_COUNTER.next_serial();
                if let Some(keyboard) = self.seat.get_keyboard() {
                    keyboard.set_focus(self, Some(wl_surface), serial);
                }
            }

            // Switch to App view
            self.shell.set_view(crate::shell::ShellView::App);
            tracing::info!("Focused existing window instead of launching new instance");
            return true;
        }

        false
    }

    /// Focus a window by its X11 window ID
    fn focus_window_by_id(&mut self, window_id: u32) {
        let target_window = self.space.elements()
            .find(|w| {
                w.x11_surface()
                    .map(|x11| x11.window_id() == window_id)
                    .unwrap_or(false)
            })
            .cloned();

        if let Some(window) = target_window {
            // Raise to top
            let loc = self.space.element_location(&window).unwrap_or_default();
            self.space.map_element(window.clone(), loc, true);
            tracing::info!("Focused window ID: {}", window_id);

            // Set keyboard focus
            if let Some(x11) = window.x11_surface() {
                if let Some(wl_surface) = x11.wl_surface() {
                    let serial = smithay::utils::SERIAL_COUNTER.next_serial();
                    if let Some(keyboard) = self.seat.get_keyboard() {
                        keyboard.set_focus(self, Some(wl_surface), serial);
                    }
                }
            }
        }
    }

    /// Dispatch Wayland clients - processes incoming client requests
    /// This must be called regularly for the compositor to respond to clients
    pub fn dispatch_clients(&mut self) {
        // SAFETY: We use raw pointers to work around the borrow checker.
        // This is safe because dispatch_clients only accesses protocol state,
        // not the display field itself.
        let display_ptr = self.display.as_ptr();
        let self_ptr = self as *mut Self;
        unsafe {
            tracing::debug!("dispatch_clients: calling Display::dispatch_clients");
            if let Err(e) = (*display_ptr).dispatch_clients(&mut *self_ptr) {
                tracing::warn!("Failed to dispatch clients: {:?}", e);
            }
            tracing::debug!("dispatch_clients: returned from Display::dispatch_clients");
            if let Err(e) = (*display_ptr).flush_clients() {
                tracing::warn!("Failed to flush clients: {:?}", e);
            }
            tracing::debug!("dispatch_clients: complete");
        }
    }

    /// Get the desktop viewport (1920x1080)
    pub fn get_or_create_desktop_viewport(&mut self) -> u32 {
        if !self.viewports.contains_key(&0) {
            self.next_viewport_id = 1.max(self.next_viewport_id);
            let viewport = Viewport::new(0, Size::from((1920, 1080)));
            self.viewports.insert(0, viewport);
            tracing::info!("Created desktop viewport (1920x1080)");
        }
        0
    }

    // ========================================================================
    // Touch Effects (distortion-based fisheye and ripples)
    // ========================================================================

    /// Start a touch effect at the given position (finger down - fisheye)
    pub fn add_touch_effect(&mut self, x: f64, y: f64, touch_id: u64) {
        if !self.touch_effects_enabled {
            return;
        }
        self.touch_effects.add_touch(x, y, touch_id);
    }

    /// Update touch effect position (finger move - update fisheye position)
    pub fn update_touch_effect(&mut self, x: f64, y: f64, touch_id: u64) {
        if !self.touch_effects_enabled {
            return;
        }
        self.touch_effects.update_touch(x, y, touch_id);
    }

    /// End touch effect (finger up - convert fisheye to expanding ripple)
    pub fn end_touch_effect(&mut self, touch_id: u64) {
        if !self.touch_effects_enabled {
            return;
        }
        self.touch_effects.end_touch(touch_id);
    }

    /// Clean up expired touch effects
    pub fn cleanup_touch_effects(&mut self) {
        self.touch_effects.cleanup();
    }

    /// Check if there are any active touch effects
    pub fn has_touch_effects(&self) -> bool {
        self.touch_effects_enabled && self.touch_effects.has_effects()
    }

    /// Toggle touch effects on/off
    pub fn set_touch_effects_enabled(&mut self, enabled: bool) {
        self.touch_effects_enabled = enabled;
        if !enabled {
            self.touch_effects.clear();
        }
        tracing::info!("Touch effects {}", if enabled { "enabled" } else { "disabled" });
        // Save to config file
        Self::save_compositor_settings(enabled);
    }

    /// Load compositor settings from config file
    pub fn load_compositor_settings() -> bool {
        let config_path = Self::compositor_settings_path();
        if let Ok(contents) = std::fs::read_to_string(&config_path) {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&contents) {
                return json.get("touch_effects_enabled")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(true);
            }
        }
        true // Default to enabled
    }

    /// Save compositor settings to config file
    pub fn save_compositor_settings(touch_effects_enabled: bool) {
        let config_path = Self::compositor_settings_path();
        if let Some(parent) = config_path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let json = serde_json::json!({
            "touch_effects_enabled": touch_effects_enabled
        });
        if let Ok(contents) = serde_json::to_string_pretty(&json) {
            let _ = std::fs::write(&config_path, contents);
        }
    }

    /// Get path to effects config file (shared with Settings app)
    fn compositor_settings_path() -> std::path::PathBuf {
        // Try multiple paths to find the config (same logic as touch_effects.rs)
        let possible_homes = [
            std::env::var("SUDO_USER").ok().and_then(|user| {
                std::fs::read_to_string("/etc/passwd").ok().and_then(|passwd| {
                    passwd.lines()
                        .find(|line| line.starts_with(&format!("{}:", user)))
                        .and_then(|line| line.split(':').nth(5))
                        .map(|s| s.to_string())
                })
            }),
            Some("/home/droidian".to_string()),
            std::env::var("HOME").ok(),
        ];

        possible_homes.iter()
            .filter_map(|h| h.as_ref())
            .map(|home| std::path::PathBuf::from(home).join(".local/state/flick/effects_config.json"))
            .find(|p| p.exists())
            .unwrap_or_else(|| {
                std::env::var("HOME")
                    .map(std::path::PathBuf::from)
                    .unwrap_or_else(|_| std::path::PathBuf::from("/tmp"))
                    .join(".local/state/flick/effects_config.json")
            })
    }

    /// Set living pixels enabled/disabled and save to config
    pub fn set_living_pixels_enabled(&mut self, enabled: bool) {
        let config_path = Self::compositor_settings_path();

        // Read existing config
        let mut config = if let Ok(contents) = std::fs::read_to_string(&config_path) {
            serde_json::from_str::<serde_json::Value>(&contents)
                .unwrap_or_else(|_| serde_json::json!({}))
        } else {
            serde_json::json!({})
        };

        // Update living_pixels field
        if let Some(obj) = config.as_object_mut() {
            obj.insert("living_pixels".to_string(), serde_json::Value::Bool(enabled));
        }

        // Write back
        if let Some(parent) = config_path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if let Ok(contents) = serde_json::to_string_pretty(&config) {
            let _ = std::fs::write(&config_path, contents);
        }

        tracing::info!("Living pixels {}", if enabled { "enabled" } else { "disabled" });
    }

    /// Send Ctrl+C to the focused application for copy
    pub fn do_clipboard_copy(&mut self) {
        use smithay::backend::input::KeyState;
        use smithay::input::keyboard::{FilterResult, Keycode};

        tracing::info!("Clipboard: sending Ctrl+C");

        if let Some(keyboard) = self.seat.get_keyboard() {
            let serial = smithay::utils::SERIAL_COUNTER.next_serial();
            let time = self.clock.now().as_millis() as u32;

            // Linux keycodes + 8 for XKB
            let ctrl_keycode = Keycode::new(29 + 8);  // Left Ctrl
            let c_keycode = Keycode::new(46 + 8);     // C

            // Press Ctrl
            keyboard.input::<(), _>(self, ctrl_keycode, KeyState::Pressed, serial, time, |_, _, _| {
                FilterResult::Forward::<()>
            });
            // Press C
            keyboard.input::<(), _>(self, c_keycode, KeyState::Pressed, serial, time, |_, _, _| {
                FilterResult::Forward::<()>
            });
            // Release C
            keyboard.input::<(), _>(self, c_keycode, KeyState::Released, serial, time, |_, _, _| {
                FilterResult::Forward::<()>
            });
            // Release Ctrl
            keyboard.input::<(), _>(self, ctrl_keycode, KeyState::Released, serial, time, |_, _, _| {
                FilterResult::Forward::<()>
            });

            // Haptic feedback
            self.system.haptic_tap();
        }
    }

    /// Send Ctrl+V to the focused application for paste
    pub fn do_clipboard_paste(&mut self) {
        use smithay::backend::input::KeyState;
        use smithay::input::keyboard::{FilterResult, Keycode};

        tracing::info!("Clipboard: sending Ctrl+V");

        if let Some(keyboard) = self.seat.get_keyboard() {
            let serial = smithay::utils::SERIAL_COUNTER.next_serial();
            let time = self.clock.now().as_millis() as u32;

            // Linux keycodes + 8 for XKB
            let ctrl_keycode = Keycode::new(29 + 8);  // Left Ctrl
            let v_keycode = Keycode::new(47 + 8);     // V

            // Press Ctrl
            keyboard.input::<(), _>(self, ctrl_keycode, KeyState::Pressed, serial, time, |_, _, _| {
                FilterResult::Forward::<()>
            });
            // Press V
            keyboard.input::<(), _>(self, v_keycode, KeyState::Pressed, serial, time, |_, _, _| {
                FilterResult::Forward::<()>
            });
            // Release V
            keyboard.input::<(), _>(self, v_keycode, KeyState::Released, serial, time, |_, _, _| {
                FilterResult::Forward::<()>
            });
            // Release Ctrl
            keyboard.input::<(), _>(self, ctrl_keycode, KeyState::Released, serial, time, |_, _, _| {
                FilterResult::Forward::<()>
            });

            // Haptic feedback
            self.system.haptic_tap();
        }
    }

    /// Reload settings from config file if enough time has passed
    /// This allows the Settings app to change settings without restart
    pub fn reload_settings_if_needed(&mut self) {
        // Check every 100ms for responsive toggle
        if self.settings_last_check.elapsed().as_millis() < 100 {
            return;
        }
        self.settings_last_check = Instant::now();

        // Reload touch effects setting
        let new_enabled = Self::load_compositor_settings();
        if new_enabled != self.touch_effects_enabled {
            tracing::info!("Settings changed: touch_effects_enabled {} -> {}",
                self.touch_effects_enabled, new_enabled);
            self.touch_effects_enabled = new_enabled;
            if !new_enabled {
                self.touch_effects.clear();
            }
        }
    }

    /// Apply rotation to the compositor
    /// This will be called by the backend when rotation changes
    pub fn apply_rotation(&mut self, orientation: crate::system::Orientation) {
        use crate::system::Orientation;

        tracing::info!("Applying rotation: {:?}", orientation);

        // Calculate new logical screen dimensions based on orientation
        // (physical_display_size stays unchanged - only logical size rotates)
        let (new_width, new_height) = match orientation {
            Orientation::Portrait => {
                // Portrait: use physical dimensions as-is
                (self.physical_display_size.w, self.physical_display_size.h)
            }
            Orientation::Landscape90 | Orientation::Landscape270 => {
                // Landscape: swap width and height
                (self.physical_display_size.h, self.physical_display_size.w)
            }
        };

        tracing::info!("Screen dimensions changing from {}x{} to {}x{}",
            self.screen_size.w, self.screen_size.h, new_width, new_height);

        // Update logical screen size (apps see this size)
        self.screen_size = Size::from((new_width, new_height));

        // Update gesture recognizer with new screen size
        self.gesture_recognizer = crate::input::GestureRecognizer::new(self.screen_size);

        // Resize all app windows to fit new screen dimensions
        for window in self.space.elements() {
            if let Some(toplevel) = window.toplevel() {
                let new_size: smithay::utils::Size<i32, smithay::utils::Logical> =
                    (new_width, new_height).into();
                toplevel.with_pending_state(|state| {
                    state.size = Some(new_size);
                });
                toplevel.send_configure();
                tracing::debug!("Resized Wayland window to {}x{}", new_width, new_height);
            }

            // Handle X11 windows
            if let Some(x11_surface) = window.x11_surface() {
                let new_geo = smithay::utils::Rectangle::from_loc_and_size(
                    (0, 0),
                    (new_width, new_height),
                );
                let _ = x11_surface.configure(new_geo);
                tracing::debug!("Resized X11 window to {}x{}", new_width, new_height);
            }
        }

        // Update Slint UI if available
        if let Some(ref mut slint_ui) = self.shell.slint_ui {
            slint_ui.set_size(Size::from((new_width, new_height)));
            tracing::info!("Updated Slint UI size to {}x{}", new_width, new_height);
        }

        // Update output transform for hwcomposer
        if let Some(output) = self.outputs.first() {
            use smithay::utils::Transform;

            let transform = match orientation {
                Orientation::Portrait => Transform::Normal,
                Orientation::Landscape90 => Transform::_90,
                Orientation::Landscape270 => Transform::_270,
            };

            // Update output transform (keeps mode unchanged)
            output.change_current_state(
                None, // Don't change mode
                Some(transform),
                None, // Don't change scale
                None, // Don't change location
            );
            tracing::info!("Updated output transform to {:?}", transform);
        }

        tracing::info!("Rotation applied successfully");
    }
}

// ============================================================================
// Wayland Protocol Implementations
// ============================================================================

impl CompositorHandler for Flick {
    fn compositor_state(&mut self) -> &mut CompositorState {
        &mut self.compositor_state
    }

    fn client_compositor_state<'a>(
        &self,
        client: &'a smithay::reexports::wayland_server::Client,
    ) -> &'a CompositorClientState {
        // XWayland client may not have ClientState, use a static default in that case
        static XWAYLAND_CLIENT_STATE: std::sync::OnceLock<ClientState> = std::sync::OnceLock::new();

        if let Some(state) = client.get_data::<ClientState>() {
            &state.compositor_state
        } else {
            // XWayland or other internal client without ClientState
            &XWAYLAND_CLIENT_STATE.get_or_init(ClientState::default).compositor_state
        }
    }

    fn commit(&mut self, surface: &WlSurface) {
        tracing::debug!("Surface commit: {:?}", surface.id());

        // Capture buffer data for hwcomposer backend before on_commit_buffer_handler clears it
        // This stores the SHM buffer pixels so we can render without Smithay's renderer
        with_states(surface, |data| {
            let mut binding = data.cached_state
                .get::<SurfaceAttributes>();
            let attrs = binding.current();

            if let Some(ref buffer_assignment) = attrs.buffer {
                use smithay::wayland::compositor::BufferAssignment;
                if let BufferAssignment::NewBuffer(buffer) = buffer_assignment {
                    // Log buffer info for debugging
                    tracing::debug!("Surface commit with new buffer: {:?}", buffer.id());

                    // Try to capture SHM buffer contents
                    let buffer_data = with_buffer_contents(buffer, |ptr, _pool_len, buf_data| {
                        let width = buf_data.width as u32;
                        let height = buf_data.height as u32;
                        let stride = buf_data.stride as u32;
                        let format = buf_data.format as u32;
                        let row_bytes = (width * 4) as usize; // 4 bytes per pixel

                        // wl_shm formats (little-endian byte order in memory):
                        // Argb8888 = 0 -> bytes are B, G, R, A
                        // Xrgb8888 = 1 -> bytes are B, G, R, X
                        // We need RGBA for OpenGL
                        let is_xrgb = format == 1; // Xrgb8888

                        // Copy row by row, converting BGRA/BGRX to RGBA
                        // buf_data.offset is where this buffer starts within the SHM pool
                        let buffer_offset = buf_data.offset as usize;
                        let mut pixels = Vec::with_capacity(row_bytes * height as usize);
                        for y in 0..height {
                            let row_start = buffer_offset + (y * stride) as usize;
                            for x in 0..width as usize {
                                let pixel_offset = row_start + x * 4;
                                let b = unsafe { *ptr.add(pixel_offset) };
                                let g = unsafe { *ptr.add(pixel_offset + 1) };
                                let r = unsafe { *ptr.add(pixel_offset + 2) };
                                let a = if is_xrgb { 255 } else { unsafe { *ptr.add(pixel_offset + 3) } };
                                // Output as RGBA
                                pixels.push(r);
                                pixels.push(g);
                                pixels.push(b);
                                pixels.push(a);
                            }
                        }

                        StoredBuffer { width, height, stride, format, pixels }
                    });

                    match buffer_data {
                        Ok(stored) => {
                            // Store in surface user data
                            data.data_map.insert_if_missing(|| RefCell::new(SurfaceBufferData::default()));
                            if let Some(buffer_data) = data.data_map.get::<RefCell<SurfaceBufferData>>() {
                                let mut bd = buffer_data.borrow_mut();
                                bd.buffer = Some(stored);
                                bd.needs_egl_import = false;
                            }
                            tracing::info!("Surface {:?} committed SHM buffer", surface.id());
                        }
                        Err(_e) => {
                            // Non-SHM buffer (dmabuf, EGL, android gralloc)
                            // Store buffer pointer and mark for EGL import during rendering
                            use smithay::reexports::wayland_server::Resource;
                            let buffer_ptr = buffer.id().as_ptr() as *mut std::ffi::c_void;

                            data.data_map.insert_if_missing(|| RefCell::new(SurfaceBufferData::default()));
                            if let Some(buffer_data) = data.data_map.get::<RefCell<SurfaceBufferData>>() {
                                let mut bd = buffer_data.borrow_mut();
                                bd.buffer = None; // Clear SHM buffer
                                bd.needs_egl_import = true;
                                bd.wl_buffer_ptr = Some(buffer_ptr);
                                // Store the buffer for releasing after import
                                // Release any previously pending buffer first
                                if let Some(old_buffer) = bd.pending_buffer.take() {
                                    old_buffer.release();
                                }
                                bd.pending_buffer = Some(buffer.clone());
                            }
                            tracing::trace!("Surface {:?} needs EGL import (buffer ptr: {:?})", surface.id(), buffer_ptr);
                        }
                    }
                }
            }
        });

        smithay::backend::renderer::utils::on_commit_buffer_handler::<Self>(surface);

        // Update popup manager state
        self.popup_manager.commit(surface);

        if !is_sync_subsurface(surface) {
            let mut root = surface.clone();
            while let Some(parent) = get_parent(&root) {
                root = parent;
            }

            if let Some(window) = self
                .space
                .elements()
                .find(|w| w.toplevel().map(|t| t.wl_surface() == &root).unwrap_or(false))
            {
                tracing::debug!("Window commit for mapped window");
                window.on_commit();
            }
        }
    }
}

impl BufferHandler for Flick {
    fn buffer_destroyed(&mut self, _buffer: &wl_buffer::WlBuffer) {}
}

impl ShmHandler for Flick {
    fn shm_state(&self) -> &ShmState {
        &self.shm_state
    }
}

impl SeatHandler for Flick {
    type KeyboardFocus = WlSurface;
    type PointerFocus = WlSurface;
    type TouchFocus = WlSurface;

    fn seat_state(&mut self) -> &mut SeatState<Self> {
        &mut self.seat_state
    }

    fn focus_changed(&mut self, seat: &Seat<Self>, focused: Option<&Self::KeyboardFocus>) {
        let dh = &self.display_handle;
        let client = focused.and_then(|s| dh.get_client(s.id()).ok());
        set_data_device_focus(dh, seat, client);

        // Notify text input protocol of focus change (sends enter/leave events)
        TextInputState::focus_changed(focused);
    }

    fn cursor_image(
        &mut self,
        _seat: &Seat<Self>,
        _image: smithay::input::pointer::CursorImageStatus,
    ) {
    }

    fn led_state_changed(
        &mut self,
        _seat: &Seat<Self>,
        _led_state: smithay::input::keyboard::LedState,
    ) {
    }
}

impl SelectionHandler for Flick {
    type SelectionUserData = ();
}

impl DataDeviceHandler for Flick {
    fn data_device_state(&mut self) -> &mut DataDeviceState {
        &mut self.data_device_state
    }
}

impl WaylandDndGrabHandler for Flick {}

impl DndGrabHandler for Flick {}

impl XdgShellHandler for Flick {
    fn xdg_shell_state(&mut self) -> &mut XdgShellState {
        tracing::debug!("xdg_shell_state accessed");
        &mut self.xdg_shell_state
    }

    fn new_toplevel(&mut self, surface: ToplevelSurface) {
        let window = Window::new_wayland_window(surface.clone());

        tracing::info!("NEW TOPLEVEL WINDOW CREATED!");
        tracing::info!("  Surface: {:?}", surface.wl_surface().id());
        tracing::info!("  Number of outputs: {}", self.outputs.len());

        // Cancel any ongoing touch sequences on existing windows
        // This is critical - without this, the old app might still receive touch events
        if let Some(touch) = self.seat.get_touch() {
            touch.cancel(self);
            tracing::info!("Cancelled touch sequences for existing windows");
        }

        // DEACTIVATE all existing windows first
        for existing_window in self.space.elements() {
            if let Some(toplevel) = existing_window.toplevel() {
                toplevel.with_pending_state(|state| {
                    state.states.unset(xdg_toplevel::State::Activated);
                });
                toplevel.send_configure();
                tracing::info!("Deactivated existing window: {:?}", toplevel.wl_surface().id());
            }
        }

        // Configure for fullscreen on our output
        if let Some(output) = self.outputs.first() {
            let output_size = output
                .current_mode()
                .map(|m| m.size)
                .unwrap_or((720, 1440).into());

            surface.with_pending_state(|state| {
                state.size = Some(output_size.to_logical(1));
                // Set fullscreen and activated states - this tells the client
                // not to draw decorations (title bar, borders)
                state.states.set(xdg_toplevel::State::Fullscreen);
                state.states.set(xdg_toplevel::State::Activated);
            });
        }

        surface.send_configure();

        // Add to space at origin and raise to top (activate=true)
        self.space.map_element(window.clone(), (0, 0), true);

        // Track this as the active window for touch input
        let surface_id = surface.wl_surface().id();
        self.active_window = Some(window);
        tracing::info!("Active window set to new toplevel: {:?}", surface_id);

        // Switch to App view now that we have a real window
        // UNLESS we're on the lock screen OR we recently unlocked (dying lock screen app)
        let current_view = self.shell.view;
        if current_view == crate::shell::ShellView::LockScreen {
            tracing::info!("New window on lock screen - staying in LockScreen view");
        } else if self.shell.unlock_app_launched {
            // App was launched from notification tap - switch to App view
            tracing::info!("New window from notification app launch - switching to App view");
            self.shell.unlock_app_launched = false; // Reset flag
            self.shell.set_view(crate::shell::ShellView::App);
        } else if self.shell.is_recently_unlocked() {
            tracing::info!("New window right after unlock - ignoring (likely dying lock app)");
        } else {
            self.shell.set_view(crate::shell::ShellView::App);
            tracing::info!("Switched to App view for new window");
        }

        // Set keyboard focus to this window
        let wl_surface = surface.wl_surface().clone();
        let client_info = wl_surface.client().map(|c| format!("{:?}", c.id())).unwrap_or_else(|| "no-client".to_string());
        tracing::info!("new_toplevel: Setting keyboard focus to {:?} (client: {})", wl_surface.id(), client_info);
        let serial = smithay::utils::SERIAL_COUNTER.next_serial();
        if let Some(keyboard) = self.seat.get_keyboard() {
            keyboard.set_focus(self, Some(wl_surface), serial);
            tracing::info!("Keyboard focus set to new toplevel");
        }
    }

    fn new_popup(&mut self, surface: PopupSurface, _positioner: PositionerState) {
        tracing::info!("New popup created");

        // Track the popup in our PopupManager
        if let Err(e) = self.popup_manager.track_popup(smithay::desktop::PopupKind::Xdg(surface.clone())) {
            tracing::warn!("Failed to track popup: {:?}", e);
        }

        // Configure the popup - it will use the positioner to determine its position
        if let Err(e) = surface.send_configure() {
            tracing::warn!("Failed to configure popup: {:?}", e);
        }
    }

    fn grab(&mut self, _surface: PopupSurface, _seat: wl_seat::WlSeat, _serial: Serial) {
        // Popup grabs are used for menus that should close on outside click
        // For now, we just acknowledge the grab request
        tracing::debug!("Popup grab requested (not fully implemented)");
    }

    fn reposition_request(
        &mut self,
        surface: PopupSurface,
        _positioner: PositionerState,
        token: u32,
    ) {
        tracing::debug!("Popup reposition request");
        surface.send_repositioned(token);
        if let Err(e) = surface.send_configure() {
            tracing::warn!("Failed to reconfigure popup: {:?}", e);
        }
    }

    fn toplevel_destroyed(&mut self, surface: ToplevelSurface) {
        tracing::info!("Toplevel destroyed");

        let window = self
            .space
            .elements()
            .find(|w| w.toplevel().map(|t| t == &surface).unwrap_or(false))
            .cloned();

        if let Some(window) = window {
            self.space.unmap_elem(&window);
        }

        // Clear active window if it was this one
        if self.active_window.as_ref().and_then(|w| w.toplevel()).map(|t| t == &surface).unwrap_or(false) {
            self.active_window = None;
        }

        // If no more windows, return to Home view
        if self.space.elements().count() == 0 {
            tracing::info!("No more windows - returning to Home view");
            self.shell.set_view(crate::shell::ShellView::Home);
        }
    }
}

impl OutputHandler for Flick {}

impl TextInputHandler for Flick {
    fn text_input_enabled(&mut self) {
        // Only show keyboard when in App view (not Home, Switcher, QuickSettings, etc.)
        if self.shell.view != crate::shell::ShellView::App {
            tracing::info!("Text input enabled but not in App view - ignoring");
            return;
        }
        tracing::info!("Text input enabled - showing on-screen keyboard");
        // Show keyboard and resize windows
        if let Some(ref slint_ui) = self.shell.slint_ui {
            slint_ui.set_keyboard_visible(true);
        }
        self.resize_windows_for_keyboard(true);
    }

    fn text_input_disabled(&mut self) {
        tracing::info!("Text input disabled - hiding on-screen keyboard");
        // Hide keyboard and resize windows
        if let Some(ref slint_ui) = self.shell.slint_ui {
            slint_ui.set_keyboard_visible(false);
        }
        self.resize_windows_for_keyboard(false);
    }
}

impl AndroidWleglHandler for Flick {
    fn android_buffer_created(&mut self, buffer: &smithay::reexports::wayland_server::protocol::wl_buffer::WlBuffer) {
        // Log the buffer creation for now
        // Full buffer import implementation will come next
        tracing::info!("Android buffer created: {:?}", buffer.id());
    }
}

impl DmabufHandler for Flick {
    fn dmabuf_state(&mut self) -> &mut DmabufState {
        &mut self.dmabuf_state
    }

    fn dmabuf_imported(&mut self, _global: &DmabufGlobal, dmabuf: Dmabuf, notifier: ImportNotifier) {
        // Log the import for debugging
        tracing::info!(
            "Dmabuf import requested: {}x{}, {} planes, format {:?}",
            dmabuf.width(),
            dmabuf.height(),
            dmabuf.num_planes(),
            dmabuf.format()
        );

        // For now, accept all dmabuf imports - actual GPU import happens during rendering
        // The dmabuf data is stored in the wl_buffer and accessed when the surface is committed
        notifier.successful::<Flick>();
    }
}

// Delegate macros
delegate_compositor!(Flick);
delegate_shm!(Flick);
delegate_seat!(Flick);
delegate_data_device!(Flick);
delegate_output!(Flick);
delegate_xdg_shell!(Flick);
delegate_dmabuf!(Flick);
crate::delegate_text_input!(Flick);
crate::delegate_android_wlegl!(Flick);
