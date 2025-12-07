//! Gesture recognition system
//!
//! Supports:
//! - Edge swipes (left, right, bottom, top)
//! - Multi-finger swipes (2, 3, 4 fingers)
//! - Pinch to zoom
//! - Pan/drag
//! - Long press
//! - Tap

use smithay::utils::{Logical, Point, Size};
use std::time::{Duration, Instant};

/// Edge of the screen
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Edge {
    Left,
    Right,
    Top,
    Bottom,
}

/// Direction of a swipe
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SwipeDirection {
    Up,
    Down,
    Left,
    Right,
}

/// Recognized gesture
#[derive(Debug, Clone)]
pub enum GestureEvent {
    /// Single tap
    Tap {
        position: Point<f64, Logical>,
    },

    /// Long press (finger held down)
    LongPress {
        position: Point<f64, Logical>,
    },

    /// Edge swipe started
    EdgeSwipeStart {
        edge: Edge,
        fingers: u32,
    },

    /// Edge swipe in progress
    EdgeSwipeUpdate {
        edge: Edge,
        fingers: u32,
        progress: f64, // 0.0 to 1.0
        velocity: f64,
    },

    /// Edge swipe completed (finger lifted)
    EdgeSwipeEnd {
        edge: Edge,
        fingers: u32,
        completed: bool, // true if swipe was far enough
        velocity: f64,
    },

    /// Multi-finger swipe (not from edge)
    Swipe {
        direction: SwipeDirection,
        fingers: u32,
        delta: Point<f64, Logical>,
        velocity: Point<f64, Logical>,
    },

    /// Pinch gesture (zoom)
    Pinch {
        center: Point<f64, Logical>,
        scale: f64,      // Current scale factor
        delta: f64,      // Change since last event
        rotation: f64,   // Rotation in radians (if supported)
    },

    /// Pan gesture (two-finger drag)
    Pan {
        center: Point<f64, Logical>,
        delta: Point<f64, Logical>,
        velocity: Point<f64, Logical>,
    },

    /// Combined pinch + pan
    PinchPan {
        center: Point<f64, Logical>,
        pan_delta: Point<f64, Logical>,
        scale: f64,
        scale_delta: f64,
    },
}

/// Configuration for gesture recognition
#[derive(Debug, Clone)]
pub struct GestureConfig {
    /// Width of edge detection zone in pixels
    pub edge_threshold: f64,

    /// Distance for swipe animation progress (larger = smoother following)
    pub swipe_threshold: f64,

    /// Distance required to complete/trigger a swipe action
    pub swipe_complete_threshold: f64,

    /// Time threshold for long press (ms)
    pub long_press_duration: Duration,

    /// Maximum time for a tap (ms)
    pub tap_duration: Duration,

    /// Minimum distance between fingers for pinch detection
    pub pinch_threshold: f64,

    /// Velocity threshold for flick gestures
    pub flick_velocity: f64,
}

impl Default for GestureConfig {
    fn default() -> Self {
        Self {
            edge_threshold: 50.0,  // 50px edge zone for easier touch
            swipe_threshold: 300.0, // 300px for smooth finger-following animation
            swipe_complete_threshold: 100.0, // 100px to trigger/complete the action
            long_press_duration: Duration::from_millis(500),
            tap_duration: Duration::from_millis(200),
            pinch_threshold: 50.0,
            flick_velocity: 500.0,
        }
    }
}

/// Touch point tracking
#[derive(Debug, Clone)]
pub struct TouchPoint {
    pub id: i32,
    pub start_pos: Point<f64, Logical>,
    pub current_pos: Point<f64, Logical>,
    pub start_time: Instant,
    pub last_time: Instant,
    pub velocity: Point<f64, Logical>,
}

impl TouchPoint {
    pub fn new(id: i32, pos: Point<f64, Logical>) -> Self {
        Self {
            id,
            start_pos: pos,
            current_pos: pos,
            start_time: Instant::now(),
            last_time: Instant::now(),
            velocity: Point::from((0.0, 0.0)),
        }
    }

    pub fn update(&mut self, pos: Point<f64, Logical>) {
        let now = Instant::now();
        let dt = now.duration_since(self.last_time).as_secs_f64();

        if dt > 0.001 {
            self.velocity = Point::from((
                (pos.x - self.current_pos.x) / dt,
                (pos.y - self.current_pos.y) / dt,
            ));
        }

        self.current_pos = pos;
        self.last_time = now;
    }

    pub fn delta(&self) -> Point<f64, Logical> {
        Point::from((
            self.current_pos.x - self.start_pos.x,
            self.current_pos.y - self.start_pos.y,
        ))
    }

    pub fn distance(&self) -> f64 {
        let d = self.delta();
        (d.x * d.x + d.y * d.y).sqrt()
    }
}

/// Gesture recognizer state machine
pub struct GestureRecognizer {
    pub config: GestureConfig,
    pub screen_size: Size<i32, Logical>,
    pub points: Vec<TouchPoint>,
    pub active_gesture: Option<ActiveGesture>,
}

#[derive(Debug, Clone)]
pub enum ActiveGesture {
    PotentialTap,
    LongPress,
    EdgeSwipe { edge: Edge },
    Swipe,
    Pinch { initial_distance: f64 },
    Pan,
}

impl GestureRecognizer {
    pub fn new(screen_size: Size<i32, Logical>) -> Self {
        Self {
            config: GestureConfig::default(),
            screen_size,
            points: Vec::new(),
            active_gesture: None,
        }
    }

    /// Check if a point is in an edge zone
    pub fn detect_edge(&self, pos: Point<f64, Logical>) -> Option<Edge> {
        let threshold = self.config.edge_threshold;
        let w = self.screen_size.w as f64;
        let h = self.screen_size.h as f64;

        if pos.x < threshold {
            Some(Edge::Left)
        } else if pos.x > w - threshold {
            Some(Edge::Right)
        } else if pos.y < threshold {
            Some(Edge::Top)
        } else if pos.y > h - threshold {
            Some(Edge::Bottom)
        } else {
            None
        }
    }

    /// Calculate center point of all touches
    pub fn center(&self) -> Point<f64, Logical> {
        if self.points.is_empty() {
            return Point::from((0.0, 0.0));
        }

        let sum: (f64, f64) = self.points.iter().fold((0.0, 0.0), |acc, p| {
            (acc.0 + p.current_pos.x, acc.1 + p.current_pos.y)
        });

        Point::from((sum.0 / self.points.len() as f64, sum.1 / self.points.len() as f64))
    }

    /// Calculate distance between two touch points
    pub fn pinch_distance(&self) -> Option<f64> {
        if self.points.len() >= 2 {
            let p1 = &self.points[0].current_pos;
            let p2 = &self.points[1].current_pos;
            let dx = p2.x - p1.x;
            let dy = p2.y - p1.y;
            Some((dx * dx + dy * dy).sqrt())
        } else {
            None
        }
    }

    /// Handle touch down event
    pub fn touch_down(&mut self, id: i32, pos: Point<f64, Logical>) -> Option<GestureEvent> {
        self.points.push(TouchPoint::new(id, pos));

        // First touch - check for edge swipe
        if self.points.len() == 1 {
            if let Some(edge) = self.detect_edge(pos) {
                self.active_gesture = Some(ActiveGesture::EdgeSwipe { edge });
                return Some(GestureEvent::EdgeSwipeStart {
                    edge,
                    fingers: 1,
                });
            } else {
                self.active_gesture = Some(ActiveGesture::PotentialTap);
            }
        }

        // Two touches - potential pinch/pan
        if self.points.len() == 2 {
            if let Some(dist) = self.pinch_distance() {
                self.active_gesture = Some(ActiveGesture::Pinch {
                    initial_distance: dist,
                });
            }
        }

        None
    }

    /// Handle touch motion event
    pub fn touch_motion(&mut self, id: i32, pos: Point<f64, Logical>) -> Option<GestureEvent> {
        // Update the touch point
        if let Some(point) = self.points.iter_mut().find(|p| p.id == id) {
            point.update(pos);
        }

        match &self.active_gesture {
            Some(ActiveGesture::EdgeSwipe { edge }) => {
                let point = self.points.first()?;
                let progress = match edge {
                    Edge::Left => point.delta().x / self.config.swipe_threshold,
                    Edge::Right => -point.delta().x / self.config.swipe_threshold,
                    Edge::Top => point.delta().y / self.config.swipe_threshold,
                    Edge::Bottom => -point.delta().y / self.config.swipe_threshold,
                };

                Some(GestureEvent::EdgeSwipeUpdate {
                    edge: *edge,
                    fingers: self.points.len() as u32,
                    progress: progress.clamp(0.0, 1.0),
                    velocity: match edge {
                        Edge::Left | Edge::Right => point.velocity.x,
                        Edge::Top | Edge::Bottom => point.velocity.y,
                    },
                })
            }

            Some(ActiveGesture::Pinch { initial_distance }) => {
                let current_dist = self.pinch_distance()?;
                let scale = current_dist / initial_distance;
                let center = self.center();

                Some(GestureEvent::Pinch {
                    center,
                    scale,
                    delta: scale - 1.0,
                    rotation: 0.0, // TODO: implement rotation
                })
            }

            Some(ActiveGesture::Pan) => {
                let center = self.center();
                // Calculate average delta
                let delta = if self.points.len() >= 2 {
                    let avg_delta: (f64, f64) = self.points.iter().fold((0.0, 0.0), |acc, p| {
                        let d = p.delta();
                        (acc.0 + d.x, acc.1 + d.y)
                    });
                    Point::from((
                        avg_delta.0 / self.points.len() as f64,
                        avg_delta.1 / self.points.len() as f64,
                    ))
                } else {
                    Point::from((0.0, 0.0))
                };

                let velocity = if !self.points.is_empty() {
                    let avg_vel: (f64, f64) = self.points.iter().fold((0.0, 0.0), |acc, p| {
                        (acc.0 + p.velocity.x, acc.1 + p.velocity.y)
                    });
                    Point::from((
                        avg_vel.0 / self.points.len() as f64,
                        avg_vel.1 / self.points.len() as f64,
                    ))
                } else {
                    Point::from((0.0, 0.0))
                };

                Some(GestureEvent::Pan {
                    center,
                    delta,
                    velocity,
                })
            }

            _ => None,
        }
    }

    /// Handle touch up event
    pub fn touch_up(&mut self, id: i32) -> Option<GestureEvent> {
        let point_idx = self.points.iter().position(|p| p.id == id)?;
        let point = self.points.remove(point_idx);

        let event = match &self.active_gesture {
            Some(ActiveGesture::EdgeSwipe { edge }) => {
                let completed = point.distance() > self.config.swipe_complete_threshold;
                let velocity = match edge {
                    Edge::Left | Edge::Right => point.velocity.x,
                    Edge::Top | Edge::Bottom => point.velocity.y,
                };

                Some(GestureEvent::EdgeSwipeEnd {
                    edge: *edge,
                    fingers: 1,
                    completed,
                    velocity,
                })
            }

            Some(ActiveGesture::PotentialTap) => {
                let duration = point.start_time.elapsed();
                if duration < self.config.tap_duration && point.distance() < 10.0 {
                    Some(GestureEvent::Tap {
                        position: point.start_pos,
                    })
                } else if duration >= self.config.long_press_duration {
                    Some(GestureEvent::LongPress {
                        position: point.start_pos,
                    })
                } else {
                    None
                }
            }

            _ => None,
        };

        // Reset gesture if all fingers lifted
        if self.points.is_empty() {
            self.active_gesture = None;
        }

        event
    }

    /// Handle touch cancel
    pub fn touch_cancel(&mut self) {
        self.points.clear();
        self.active_gesture = None;
    }
}

/// Actions that can be triggered by gestures
#[derive(Debug, Clone)]
pub enum GestureAction {
    /// Go back in app (swipe from left edge to right)
    Back,
    /// Open app switcher (swipe from right edge to left)
    AppSwitcher,
    /// Close current app (swipe from top edge down)
    CloseApp,
    /// Open app drawer/grid (swipe from bottom edge up)
    AppDrawer,
    /// Open quick settings (reserved for future)
    QuickSettings,
    /// Go home
    Home,
    /// Zoom viewport
    ZoomViewport { scale: f64, center: Point<f64, Logical> },
    /// Pan viewport
    PanViewport { delta: Point<f64, Logical> },
    /// No action
    None,
}

/// Map gestures to actions based on Flick UX:
/// - Swipe up from bottom -> App drawer/grid
/// - Swipe down from top -> Close current app
/// - Swipe right from left edge -> Back in app
/// - Swipe left from right edge -> App switcher
pub fn gesture_to_action(event: &GestureEvent) -> GestureAction {
    match event {
        // Left edge swipe right = Back
        GestureEvent::EdgeSwipeEnd { edge: Edge::Left, completed: true, .. } => {
            GestureAction::Back
        }
        // Right edge swipe left = App Switcher
        GestureEvent::EdgeSwipeEnd { edge: Edge::Right, completed: true, .. } => {
            GestureAction::AppSwitcher
        }
        // Bottom edge swipe up = App Drawer
        GestureEvent::EdgeSwipeEnd { edge: Edge::Bottom, completed: true, .. } => {
            GestureAction::AppDrawer
        }
        // Top edge swipe down = Close App
        GestureEvent::EdgeSwipeEnd { edge: Edge::Top, completed: true, .. } => {
            GestureAction::CloseApp
        }
        GestureEvent::Pinch { scale, center, .. } => {
            GestureAction::ZoomViewport { scale: *scale, center: *center }
        }
        GestureEvent::Pan { delta, .. } => {
            GestureAction::PanViewport { delta: *delta }
        }
        _ => GestureAction::None,
    }
}
