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
    delegate_compositor, delegate_data_device, delegate_output, delegate_seat, delegate_shm,
    delegate_xdg_shell,
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
            get_parent, is_sync_subsurface, CompositorClientState, CompositorHandler,
            CompositorState,
        },
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
        shm::{ShmHandler, ShmState},
        socket::ListeningSocketSource,
    },
    wayland::xwayland_shell::XWaylandShellState,
    xwayland::{xwm::X11Wm, XWayland},
};

use crate::input::{GestureRecognizer, GestureAction};
use crate::viewport::Viewport;
use crate::shell::Shell;
use crate::system::SystemStatus;
use crate::text_input::{TextInputState, TextInputHandler};

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

    // Desktop
    pub space: Space<Window>,
    pub popup_manager: PopupManager,

    // Outputs
    pub outputs: Vec<Output>,

    // Viewports for desktop apps (virtual 1080p spaces)
    pub viewports: HashMap<u32, Viewport>,
    pub next_viewport_id: u32,

    // Screen size
    pub screen_size: Size<i32, Logical>,

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

    /// Switcher transition gesture (swipe from right - app shrinks into card)
    pub switcher_gesture_active: bool,
    pub switcher_gesture_progress: f64,

    /// Quick settings transition gesture (swipe from left - slides in from left)
    pub qs_gesture_active: bool,
    pub qs_gesture_progress: f64,

    /// Keyboard dismiss gesture (swipe down on keyboard)
    pub keyboard_dismiss_active: bool,
    pub keyboard_dismiss_start_y: f64,
    pub keyboard_dismiss_offset: f64,
    pub keyboard_initial_touch_pos: Option<smithay::utils::Point<f64, smithay::utils::Logical>>,
    pub keyboard_last_touch_pos: Option<smithay::utils::Point<f64, smithay::utils::Logical>>,

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
            seat_state,
            seat,
            space: Space::default(),
            popup_manager: PopupManager::default(),
            outputs: Vec::new(),
            viewports: HashMap::new(),
            next_viewport_id: 0,
            screen_size,
            xwayland: None,
            xwm: None,
            xwayland_shell_state: None,
            gesture_recognizer: GestureRecognizer::new(screen_size),
            close_gesture_window: None,
            close_gesture_original_y: 0,
            home_gesture_window: None,
            home_gesture_original_y: 0,
            switcher_gesture_active: false,
            switcher_gesture_progress: 0.0,
            qs_gesture_active: false,
            qs_gesture_progress: 0.0,
            keyboard_dismiss_active: false,
            keyboard_dismiss_start_y: 0.0,
            keyboard_dismiss_offset: 0.0,
            keyboard_initial_touch_pos: None,
            keyboard_last_touch_pos: None,
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
                    self.shell.view = crate::shell::ShellView::Home;
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

    /// Start home gesture - find the top-most app window and track it for upward slide
    pub fn start_home_gesture(&mut self) {
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
            }
        }
    }

    /// Update home gesture - move the window UP based on progress (opposite of close gesture)
    pub fn update_home_gesture(&mut self, progress: f64) {
        if let Some(ref window) = self.home_gesture_window.clone() {
            // Calculate new Y position - move UP (negative offset)
            // progress = finger_distance / swipe_threshold (300px)
            // So offset = progress * 300 gives 1:1 finger tracking
            let swipe_threshold = 300.0;
            let offset = (progress * swipe_threshold) as i32;
            let new_y = self.home_gesture_original_y - offset;

            // Move the window in the space
            if let Some(loc) = self.space.element_location(window) {
                self.space.map_element(window.clone(), (loc.x, new_y), false);
            }
        }
    }

    /// End home gesture - either go to home or animate the window back
    pub fn end_home_gesture(&mut self, completed: bool) {
        if let Some(window) = self.home_gesture_window.take() {
            if completed {
                // Switch to home view
                tracing::info!("Home gesture completed - switching to home");
                self.shell.view = crate::shell::ShellView::Home;

                // Restore window to original position (it will be hidden anyway)
                if let Some(loc) = self.space.element_location(&window) {
                    self.space.map_element(window, (loc.x, self.home_gesture_original_y), false);
                }
            } else {
                // Cancel - restore original position
                tracing::info!("Home gesture cancelled - restoring position");
                if let Some(loc) = self.space.element_location(&window) {
                    self.space.map_element(window, (loc.x, self.home_gesture_original_y), false);
                }
            }
        }
        self.home_gesture_original_y = 0;
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
            if let Err(e) = (*display_ptr).dispatch_clients(&mut *self_ptr) {
                tracing::warn!("Failed to dispatch clients: {:?}", e);
            }
            if let Err(e) = (*display_ptr).flush_clients() {
                tracing::warn!("Failed to flush clients: {:?}", e);
            }
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

        // Add to space at origin
        self.space.map_element(window, (0, 0), false);

        // Set keyboard focus to this window
        let wl_surface = surface.wl_surface().clone();
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
    }
}

impl OutputHandler for Flick {}

impl TextInputHandler for Flick {
    fn text_input_enabled(&mut self) {
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

// Delegate macros
delegate_compositor!(Flick);
delegate_shm!(Flick);
delegate_seat!(Flick);
delegate_data_device!(Flick);
delegate_output!(Flick);
delegate_xdg_shell!(Flick);
crate::delegate_text_input!(Flick);
