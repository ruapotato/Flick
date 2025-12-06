//! Touch input handling

use smithay::utils::{Logical, Point};

/// Raw touch event from libinput
#[derive(Debug, Clone)]
pub enum TouchEvent {
    Down {
        slot: i32,
        position: Point<f64, Logical>,
    },
    Up {
        slot: i32,
    },
    Motion {
        slot: i32,
        position: Point<f64, Logical>,
    },
    Cancel,
    Frame,
}
