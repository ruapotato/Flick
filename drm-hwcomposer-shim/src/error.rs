//! Error types for the DRM hwcomposer shim

use thiserror::Error;

#[derive(Error, Debug)]
pub enum Error {
    #[error("hwcomposer initialization failed: {0}")]
    HwcInit(String),

    #[error("hwcomposer display not found")]
    NoDisplay,

    #[error("EGL error: {0}")]
    Egl(String),

    #[error("gralloc error: {0}")]
    Gralloc(String),

    #[error("buffer allocation failed: {0}")]
    BufferAlloc(String),

    #[error("mode setting failed: {0}")]
    ModeSetting(String),

    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    #[error("DRM error: {0}")]
    Drm(String),
}
