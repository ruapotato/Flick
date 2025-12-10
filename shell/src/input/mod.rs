//! Input handling - touch, gestures, keyboard
//!
//! This module provides:
//! - Gesture recognition (edge swipes, taps, pinch, etc.)
//! - Shared input handlers for both TTY and embedded backends
//! - Keycode conversion utilities

mod gestures;
mod handler;
mod touch;

pub use gestures::*;
pub use handler::*;
