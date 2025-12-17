//! DRM/KMS Shim for Android hwcomposer
//!
//! This library provides a DRM/KMS-compatible interface that internally uses
//! Android's hwcomposer (via libhybris) for display output. This allows any
//! standard Wayland compositor to run on Android-based Linux phones (Droidian,
//! Mobian on Android devices, etc.)
//!
//! # Architecture
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────────┐
//! │              Wayland Compositor (any)                       │
//! │         (Flick, Phosh, Plasma Mobile, etc.)                │
//! └─────────────────────────────────────────────────────────────┘
//!                              │
//!                    Standard DRM/KMS/GBM APIs
//!                              │
//! ┌─────────────────────────────────────────────────────────────┐
//! │              drm-hwcomposer-shim                            │
//! │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
//! │  │ DRM Device  │  │ GBM Device  │  │ EGL Integration     │ │
//! │  │ (KMS ioctl) │  │ (gralloc)   │  │ (buffer sharing)    │ │
//! │  └─────────────┘  └─────────────┘  └─────────────────────┘ │
//! └─────────────────────────────────────────────────────────────┘
//!                              │
//!                       libhybris
//!                              │
//! ┌─────────────────────────────────────────────────────────────┐
//! │              Android HAL (hwcomposer, gralloc)              │
//! └─────────────────────────────────────────────────────────────┘
//!                              │
//! ┌─────────────────────────────────────────────────────────────┐
//! │              GPU Driver (Adreno, Mali, etc.)                │
//! └─────────────────────────────────────────────────────────────┘
//! ```
//!
//! # Usage
//!
//! ```rust,ignore
//! use drm_hwcomposer_shim::HwcDrmDevice;
//!
//! // Create the shim device
//! let device = HwcDrmDevice::new()?;
//!
//! // Use it like a normal DRM device
//! let fd = device.as_raw_fd();
//! // Pass fd to your compositor...
//! ```

pub mod c_api;
pub mod drm_device;
pub mod egl;
pub mod error;
pub mod ffi;
pub mod gbm_device;
pub mod hwcomposer;

pub use drm_device::HwcDrmDevice;
pub use gbm_device::HwcGbmDevice;
pub use error::Error;
pub use c_api::drm_hwcomposer_shim_register_device;

/// Result type for this crate
pub type Result<T> = std::result::Result<T, Error>;
