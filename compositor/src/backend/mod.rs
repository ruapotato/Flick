//! Backend implementations for Flick compositor
//!
//! - `udev`: Real hardware (DRM + libinput)
//! - `winit`: Windowed mode for development

pub mod udev;
pub mod winit;
