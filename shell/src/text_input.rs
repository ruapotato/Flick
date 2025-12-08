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
    backend::GlobalId, Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use tracing::{debug, info};

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
        _client: &Client,
        _resource: &ZwpTextInputManagerV3,
        request: zwp_text_input_manager_v3::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, D>,
    ) {
        match request {
            zwp_text_input_manager_v3::Request::GetTextInput { id, seat: _ } => {
                let instance = data_init.init(id, TextInputData::default());
                debug!("Text input instance created: {:?}", instance.id());
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
                debug!("Text input ENABLE requested (pending)");
                data.inner.lock().unwrap().pending_enable = Some(true);
            }
            zwp_text_input_v3::Request::Disable => {
                debug!("Text input DISABLE requested (pending)");
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
                debug!("Text input instance destroyed");
                // If text input was enabled, disable it
                let was_enabled = data.inner.lock().unwrap().enabled;
                if was_enabled {
                    state.text_input_disabled();
                }
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
