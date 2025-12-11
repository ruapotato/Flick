//! Demo mode support - phone-sized viewport, touch indicators, and screen recording

use std::collections::HashMap;
use std::time::{Duration, Instant};

/// Touch indicator that shows where the user touched and fades out
#[derive(Clone, Debug)]
pub struct TouchIndicator {
    /// Position in demo viewport coordinates
    pub x: f64,
    pub y: f64,
    /// When this touch started
    pub start_time: Instant,
    /// Whether finger is still down
    pub active: bool,
    /// When finger was released (for fade animation)
    pub release_time: Option<Instant>,
}

impl TouchIndicator {
    pub fn new(x: f64, y: f64) -> Self {
        Self {
            x,
            y,
            start_time: Instant::now(),
            active: true,
            release_time: None,
        }
    }

    /// Get opacity (1.0 when active, fades to 0.0 after release)
    pub fn opacity(&self) -> f32 {
        if self.active {
            1.0
        } else if let Some(release) = self.release_time {
            let elapsed = release.elapsed().as_secs_f32();
            let fade_duration = 0.4; // 400ms fade
            (1.0 - (elapsed / fade_duration)).max(0.0)
        } else {
            0.0
        }
    }

    /// Get radius (grows slightly on press, shrinks on release)
    pub fn radius(&self) -> f32 {
        let base_radius = 30.0;
        if self.active {
            let elapsed = self.start_time.elapsed().as_secs_f32();
            let grow = (elapsed * 10.0).min(1.0) * 5.0; // Grow 5px over 100ms
            base_radius + grow
        } else if let Some(release) = self.release_time {
            let elapsed = release.elapsed().as_secs_f32();
            let shrink = elapsed * 50.0; // Shrink quickly
            (base_radius - shrink).max(10.0)
        } else {
            base_radius
        }
    }

    /// Is this indicator finished (fully faded)?
    pub fn is_finished(&self) -> bool {
        if let Some(release) = self.release_time {
            release.elapsed() > Duration::from_millis(400)
        } else {
            false
        }
    }

    pub fn release(&mut self) {
        self.active = false;
        self.release_time = Some(Instant::now());
    }

    pub fn update_position(&mut self, x: f64, y: f64) {
        self.x = x;
        self.y = y;
    }
}

/// Demo mode state
pub struct DemoState {
    /// Demo viewport dimensions (phone-sized)
    pub viewport_width: u32,
    pub viewport_height: u32,
    /// Offset to center viewport on screen
    pub offset_x: i32,
    pub offset_y: i32,
    /// Active touch indicators by slot
    pub touches: HashMap<i32, TouchIndicator>,
    /// Whether to show touch indicators
    pub show_indicators: bool,
    /// Recording state
    pub recording: Option<RecordingState>,
}

pub struct RecordingState {
    pub output_path: String,
    pub frame_count: u64,
    pub start_time: Instant,
}

impl DemoState {
    pub fn new(viewport: &str, screen_width: u32, screen_height: u32, show_indicators: bool) -> Option<Self> {
        // Parse viewport size (e.g., "1080x2340")
        let parts: Vec<&str> = viewport.split('x').collect();
        if parts.len() != 2 {
            tracing::error!("Invalid demo viewport format: {}. Use WIDTHxHEIGHT (e.g., 1080x2340)", viewport);
            return None;
        }

        let viewport_width: u32 = parts[0].parse().ok()?;
        let viewport_height: u32 = parts[1].parse().ok()?;

        // Calculate offset to center viewport on screen
        let offset_x = (screen_width as i32 - viewport_width as i32) / 2;
        let offset_y = (screen_height as i32 - viewport_height as i32) / 2;

        tracing::info!(
            "Demo mode: {}x{} viewport centered at ({}, {}) on {}x{} screen",
            viewport_width, viewport_height, offset_x, offset_y, screen_width, screen_height
        );

        Some(Self {
            viewport_width,
            viewport_height,
            offset_x,
            offset_y,
            touches: HashMap::new(),
            show_indicators,
            recording: None,
        })
    }

    /// Convert screen coordinates to demo viewport coordinates
    /// Returns None if outside the viewport
    pub fn screen_to_viewport(&self, screen_x: f64, screen_y: f64) -> Option<(f64, f64)> {
        let vx = screen_x - self.offset_x as f64;
        let vy = screen_y - self.offset_y as f64;

        if vx >= 0.0 && vx < self.viewport_width as f64 &&
           vy >= 0.0 && vy < self.viewport_height as f64 {
            Some((vx, vy))
        } else {
            None
        }
    }

    /// Handle touch down event
    pub fn touch_down(&mut self, slot: i32, screen_x: f64, screen_y: f64) {
        if let Some((vx, vy)) = self.screen_to_viewport(screen_x, screen_y) {
            self.touches.insert(slot, TouchIndicator::new(vx, vy));
        }
    }

    /// Handle touch motion event
    pub fn touch_motion(&mut self, slot: i32, screen_x: f64, screen_y: f64) {
        if let Some((vx, vy)) = self.screen_to_viewport(screen_x, screen_y) {
            if let Some(indicator) = self.touches.get_mut(&slot) {
                indicator.update_position(vx, vy);
            }
        }
    }

    /// Handle touch up event
    pub fn touch_up(&mut self, slot: i32) {
        if let Some(indicator) = self.touches.get_mut(&slot) {
            indicator.release();
        }
    }

    /// Get all visible touch indicators (for rendering)
    pub fn visible_indicators(&self) -> Vec<&TouchIndicator> {
        self.touches.values()
            .filter(|t| t.opacity() > 0.0)
            .collect()
    }

    /// Clean up finished indicators
    pub fn cleanup_finished(&mut self) {
        self.touches.retain(|_, t| !t.is_finished());
    }

    /// Start recording
    pub fn start_recording(&mut self, path: String) {
        self.recording = Some(RecordingState {
            output_path: path,
            frame_count: 0,
            start_time: Instant::now(),
        });
    }

    /// Stop recording and return stats
    pub fn stop_recording(&mut self) -> Option<(String, u64, Duration)> {
        self.recording.take().map(|r| {
            (r.output_path, r.frame_count, r.start_time.elapsed())
        })
    }
}
