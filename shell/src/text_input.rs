//! Text input protocol handling for embedded on-screen keyboard
//!
//! This module implements zwp_text_input_v3 protocol to detect when apps
//! request text input (e.g., when a text field gets focus) and automatically
//! show/hide our embedded on-screen keyboard.

use std::sync::{Arc, Mutex};

use smithay::reexports::wayland_protocols::wp::text_input::zv3::server::{
    zwp_text_input_manager_v3::{self, ZwpTextInputManagerV3},
    zwp_text_input_v3::{self, ZwpTextInputV3},
};
use smithay::reexports::wayland_server::{
    backend::{ClientId, GlobalId, ObjectId},
    protocol::wl_surface::WlSurface,
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use tracing::{debug, info};

/// Shared state for tracking text input instances
#[derive(Debug, Default)]
struct TextInputTracker {
    /// All active text input instances (client_id -> instance)
    instances: Vec<(ClientId, ZwpTextInputV3)>,
    /// Currently focused surface
    focused_surface: Option<WlSurface>,
}

/// Global shared tracker
lazy_static::lazy_static! {
    static ref TRACKER: Mutex<TextInputTracker> = Mutex::new(TextInputTracker::default());
}

/// State for text input manager
#[derive(Debug)]
pub struct TextInputState {
    global: GlobalId,
}

impl TextInputState {
    /// Initialize the text input manager global
    pub fn new<D>(display: &DisplayHandle) -> Self
    where
        D: GlobalDispatch<ZwpTextInputManagerV3, ()> + 'static,
        D: Dispatch<ZwpTextInputManagerV3, ()> + 'static,
        D: Dispatch<ZwpTextInputV3, TextInputData> + 'static,
    {
        let global = display.create_global::<D, ZwpTextInputManagerV3, _>(1, ());
        info!("Text input manager v3 global created");
        Self { global }
    }

    /// Get the global ID
    pub fn global(&self) -> GlobalId {
        self.global.clone()
    }

    /// Called when keyboard focus changes - sends enter/leave to text input clients
    pub fn focus_changed(new_focus: Option<&WlSurface>) {
        let mut tracker = TRACKER.lock().unwrap();

        info!("TextInputState::focus_changed called - new_focus: {:?}, instances: {}",
            new_focus.map(|s| s.id()), tracker.instances.len());

        // Get old focus
        let old_focus = tracker.focused_surface.take();

        // Send leave to old focus
        if let Some(ref old_surface) = old_focus {
            let old_client_id = old_surface.client().map(|c| c.id());
            for (client_id, text_input) in &tracker.instances {
                if old_client_id.as_ref().map(|id| id == client_id).unwrap_or(false) {
                    info!("Sending text_input LEAVE to client {:?}", client_id);
                    text_input.leave(old_surface);
                }
            }
        }

        // Update focused surface
        tracker.focused_surface = new_focus.cloned();

        // Send enter to new focus
        if let Some(ref new_surface) = tracker.focused_surface {
            let new_client_id = new_surface.client().map(|c| c.id());
            for (client_id, text_input) in &tracker.instances {
                if new_client_id.as_ref().map(|id| id == client_id).unwrap_or(false) {
                    info!("Sending text_input ENTER to client {:?}", client_id);
                    text_input.enter(new_surface);
                }
            }
        }
    }
}

/// Inner state that can be mutated
#[derive(Debug, Default)]
struct TextInputInner {
    /// Whether text input is currently enabled
    enabled: bool,
    /// Pending enable state (set by Enable/Disable, applied on Commit)
    pending_enable: Option<bool>,
    /// The serial number for this text input
    serial: u32,
}

/// Data associated with each text input instance
#[derive(Debug, Clone, Default)]
pub struct TextInputData {
    inner: Arc<Mutex<TextInputInner>>,
}

/// Handler trait for text input events
pub trait TextInputHandler {
    /// Called when a client enables text input (e.g., text field focused)
    fn text_input_enabled(&mut self);

    /// Called when a client disables text input (e.g., text field unfocused)
    fn text_input_disabled(&mut self);
}

// Implement GlobalDispatch for the manager
impl<D> GlobalDispatch<ZwpTextInputManagerV3, (), D> for TextInputState
where
    D: GlobalDispatch<ZwpTextInputManagerV3, ()> + 'static,
    D: Dispatch<ZwpTextInputManagerV3, ()> + 'static,
    D: Dispatch<ZwpTextInputV3, TextInputData> + 'static,
{
    fn bind(
        _state: &mut D,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwpTextInputManagerV3>,
        _global_data: &(),
        data_init: &mut DataInit<'_, D>,
    ) {
        data_init.init(resource, ());
        debug!("Text input manager bound by client");
    }
}

// Implement Dispatch for the manager
impl<D> Dispatch<ZwpTextInputManagerV3, (), D> for TextInputState
where
    D: Dispatch<ZwpTextInputManagerV3, ()> + 'static,
    D: Dispatch<ZwpTextInputV3, TextInputData> + 'static,
{
    fn request(
        _state: &mut D,
        client: &Client,
        _resource: &ZwpTextInputManagerV3,
        request: zwp_text_input_manager_v3::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, D>,
    ) {
        match request {
            zwp_text_input_manager_v3::Request::GetTextInput { id, seat: _ } => {
                let instance = data_init.init(id, TextInputData::default());
                let client_id = client.id();
                info!("Text input INSTANCE CREATED: {:?} for client {:?}", instance.id(), client_id);

                // Register instance in tracker
                let mut tracker = TRACKER.lock().unwrap();
                tracker.instances.push((client_id.clone(), instance.clone()));

                // If there's already a focused surface for this client, send enter
                if let Some(ref focused) = tracker.focused_surface {
                    if focused.client().map(|c| c.id() == client_id).unwrap_or(false) {
                        debug!("Sending immediate enter to new text_input instance");
                        instance.enter(focused);
                    }
                }
            }
            zwp_text_input_manager_v3::Request::Destroy => {
                debug!("Text input manager destroyed");
            }
            _ => unreachable!(),
        }
    }
}

// Implement Dispatch for text input instances
impl<D> Dispatch<ZwpTextInputV3, TextInputData, D> for TextInputState
where
    D: Dispatch<ZwpTextInputV3, TextInputData> + TextInputHandler + 'static,
{
    fn request(
        state: &mut D,
        _client: &Client,
        resource: &ZwpTextInputV3,
        request: zwp_text_input_v3::Request,
        data: &TextInputData,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, D>,
    ) {
        match request {
            zwp_text_input_v3::Request::Enable => {
                info!("Text input ENABLE requested (pending) from client");
                data.inner.lock().unwrap().pending_enable = Some(true);
            }
            zwp_text_input_v3::Request::Disable => {
                info!("Text input DISABLE requested (pending) from client");
                data.inner.lock().unwrap().pending_enable = Some(false);
            }
            zwp_text_input_v3::Request::SetSurroundingText { text, cursor, anchor } => {
                debug!("Set surrounding text: '{}' cursor={} anchor={}", text, cursor, anchor);
            }
            zwp_text_input_v3::Request::SetTextChangeCause { cause: _ } => {
                debug!("Set text change cause");
            }
            zwp_text_input_v3::Request::SetContentType { hint: _, purpose: _ } => {
                debug!("Set content type");
            }
            zwp_text_input_v3::Request::SetCursorRectangle { x, y, width, height } => {
                debug!("Set cursor rectangle: ({}, {}) {}x{}", x, y, width, height);
            }
            zwp_text_input_v3::Request::Commit => {
                let (serial, enable_change, was_enabled) = {
                    let mut inner = data.inner.lock().unwrap();
                    inner.serial += 1;
                    let serial = inner.serial;

                    // Apply pending enable state
                    if let Some(enable) = inner.pending_enable.take() {
                        let was_enabled = inner.enabled;
                        inner.enabled = enable;
                        (serial, Some(enable), was_enabled)
                    } else {
                        (serial, None, inner.enabled)
                    }
                };

                // Send done event to acknowledge
                resource.done(serial);

                // Notify the compositor of state change (after dropping the lock)
                if let Some(enable) = enable_change {
                    debug!("Text input COMMIT - serial {}, enabled: {} -> {}", serial, was_enabled, enable);
                    if enable && !was_enabled {
                        info!("Text input ENABLED - showing keyboard");
                        state.text_input_enabled();
                    } else if !enable && was_enabled {
                        info!("Text input DISABLED - hiding keyboard");
                        state.text_input_disabled();
                    }
                } else {
                    debug!("Text input COMMIT - serial {} (no state change)", serial);
                }
            }
            zwp_text_input_v3::Request::Destroy => {
                debug!("Text input instance destroyed: {:?}", resource.id());
                // If text input was enabled, disable it
                let was_enabled = data.inner.lock().unwrap().enabled;
                if was_enabled {
                    state.text_input_disabled();
                }
                // Remove from tracker
                let resource_id = resource.id();
                let mut tracker = TRACKER.lock().unwrap();
                tracker.instances.retain(|(_, ti)| ti.id() != resource_id);
            }
            _ => unreachable!(),
        }
    }
}

/// Macro to delegate text input handling
#[macro_export]
macro_rules! delegate_text_input {
    ($ty:ty) => {
        smithay::reexports::wayland_server::delegate_global_dispatch!($ty: [
            smithay::reexports::wayland_protocols::wp::text_input::zv3::server::zwp_text_input_manager_v3::ZwpTextInputManagerV3: ()
        ] => $crate::text_input::TextInputState);

        smithay::reexports::wayland_server::delegate_dispatch!($ty: [
            smithay::reexports::wayland_protocols::wp::text_input::zv3::server::zwp_text_input_manager_v3::ZwpTextInputManagerV3: ()
        ] => $crate::text_input::TextInputState);

        smithay::reexports::wayland_server::delegate_dispatch!($ty: [
            smithay::reexports::wayland_protocols::wp::text_input::zv3::server::zwp_text_input_v3::ZwpTextInputV3: $crate::text_input::TextInputData
        ] => $crate::text_input::TextInputState);
    };
}
