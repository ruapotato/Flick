//! Backend implementations for Flick compositor
//!
//! - `udev`: Real hardware (DRM + libinput) - for native Linux devices
//!          On libhybris devices, use LD_PRELOAD with drm-hwcomposer-shim
//! - `winit`: Windowed mode for development
//! - `hwcomposer`: Android hwcomposer via libhybris - for Droidian devices (legacy)

pub mod udev;
pub mod winit;

#[cfg(feature = "hwcomposer")]
pub mod hwcomposer_ffi;

#[cfg(feature = "hwcomposer")]
pub mod hwcomposer;
