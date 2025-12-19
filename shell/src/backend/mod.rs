//! Backend implementations for Flick compositor
//!
//! This branch targets hwcomposer/libhybris devices (Droidian).
//!
//! - `winit`: Windowed mode for development
//! - `hwcomposer`: Android hwcomposer via libhybris + our C shim
//!
//! The DRM/udev backend is on the main branch for mainline devices (PinePhone).

pub mod winit;

// FFI bindings to our C shim (libflick_hwc)
pub mod hwc_shim_ffi;

// HWComposer backend implementation
pub mod hwcomposer;

// Keep old FFI for reference (will be removed)
#[allow(dead_code)]
pub mod hwcomposer_ffi;
