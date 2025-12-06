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
    input::{Seat, SeatHandler, SeatState},
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
};

use crate::viewport::Viewport;

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
            seat_state,
            seat,
            space: Space::default(),
            popup_manager: PopupManager::default(),
            outputs: Vec::new(),
            viewports: HashMap::new(),
            next_viewport_id: 0,
            screen_size,
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
        &client.get_data::<ClientState>().unwrap().compositor_state
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

// Delegate macros
delegate_compositor!(Flick);
delegate_shm!(Flick);
delegate_seat!(Flick);
delegate_data_device!(Flick);
delegate_output!(Flick);
delegate_xdg_shell!(Flick);
