//! Backend implementations for Flick compositor
//!
//! - `udev`: Real hardware (DRM + libinput) - for native Linux devices
//! - `winit`: Windowed mode for development
//! - `hwcomposer`: Android hwcomposer via libhybris - for Droidian devices (legacy)
//! - `drm_shim`: DRM/GBM shim over hwcomposer - unified path for libhybris devices

pub mod udev;
pub mod winit;

#[cfg(feature = "hwcomposer")]
pub mod hwcomposer_ffi;

#[cfg(feature = "hwcomposer")]
pub mod hwcomposer;

#[cfg(feature = "drm-shim")]
pub mod drm_shim;
