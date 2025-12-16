//! Hwcomposer backend for Droidian/libhybris devices
//!
//! This backend runs on Android-based Linux distributions (Droidian, UBports, etc.)
//! that use libhybris to access Android's hwcomposer HAL for graphics.
//!
//! Environment variables:
//! - EGL_PLATFORM=hwcomposer (set automatically)
//! - FLICK_DISPLAY_WIDTH / FLICK_DISPLAY_HEIGHT (optional, override display size)

use std::{
    cell::RefCell,
    ffi::c_void,
    rc::Rc,
    sync::atomic::{AtomicBool, Ordering},
    time::Duration,
};

use anyhow::Result;
use tracing::{debug, error, info, warn};

use smithay::{
    backend::{
        input::InputEvent,
        libinput::{LibinputInputBackend, LibinputSessionInterface},
        session::{
            libseat::LibSeatSession,
            Event as SessionEvent, Session,
        },
    },
    output::{Mode, Output, PhysicalProperties, Subpixel},
    reexports::{
        calloop::{EventLoop, timer::{Timer, TimeoutAction}},
        input::Libinput,
        wayland_server::{Display, Resource},
    },
    utils::Transform,
    wayland::compositor,
};

// Note: ImportAll/ImportMem will be needed once we integrate proper Smithay rendering

use crate::state::Flick;
use crate::shell::ShellView;

use super::hwcomposer_ffi::{
    self, HwcNativeWindow, ANativeWindow, ANativeWindowBuffer, hal_format,
    Hwc2Device, Hwc2Display, hwc2_initialize, gralloc_initialize,
    HWC2EventListener, hwc2_compat_device_t, hwc2_display_t,
};

// Re-use khronos-egl for raw EGL access
use khronos_egl as egl;

// Note: Render element macros would go here once we integrate proper Smithay rendering
// For now, we use direct OpenGL rendering as a proof-of-concept

/// Keyboard modifier state
#[derive(Default)]
struct ModifierState {
    ctrl: bool,
    alt: bool,
    shift: bool,
    #[allow(dead_code)]
    super_key: bool,
}

/// Hwcomposer display state
struct HwcDisplay {
    #[allow(dead_code)]
    native_window: HwcNativeWindow,
    egl_instance: egl::DynamicInstance<egl::EGL1_4>,
    egl_display: egl::Display,
    egl_surface: egl::Surface,
    #[allow(dead_code)]
    egl_context: egl::Context,
    width: u32,
    height: u32,
    // HWC2 for display presentation
    hwc2_device: Option<Hwc2Device>,
    hwc2_display: Option<Hwc2Display>,
}

/// Present callback data
struct PresentCallbackData {
    frame_ready: Rc<AtomicBool>,
    hwc2_display: *mut hwcomposer_ffi::hwc2_compat_display_t,
    hwc2_layer: *mut hwcomposer_ffi::hwc2_compat_layer_t,
    buffer_slot: std::sync::atomic::AtomicU32,
    present_count: std::sync::atomic::AtomicU32,
    present_errors: std::sync::atomic::AtomicU32,
}

/// Present callback - called when hwcomposer has a buffer ready to display
unsafe extern "C" fn present_callback(
    user_data: *mut c_void,
    _window: *mut ANativeWindow,
    buffer: *mut ANativeWindowBuffer,
) {
    if user_data.is_null() {
        return;
    }

    let data = &*(user_data as *const PresentCallbackData);
    let count = data.present_count.fetch_add(1, Ordering::Relaxed);

    // Get the acquire fence from the buffer
    let acquire_fence = hwcomposer_ffi::get_buffer_fence(buffer);

    // Present via HWC2 if we have a display
    if !data.hwc2_display.is_null() && !buffer.is_null() {
        // Get current slot and increment for next buffer
        let slot = data.buffer_slot.fetch_add(1, Ordering::Relaxed) % 3;

        // Set buffer on the layer (if we have one)
        let layer_err = if !data.hwc2_layer.is_null() {
            hwcomposer_ffi::hwc2_compat_layer_set_buffer(
                data.hwc2_layer,
                slot,
                buffer,
                acquire_fence,
            )
        } else {
            0 // No layer, skip
        };

        // Set client target with the buffer
        let target_err = hwcomposer_ffi::hwc2_compat_display_set_client_target(
            data.hwc2_display,
            slot,
            buffer,
            acquire_fence,
            0, // HAL_DATASPACE_UNKNOWN
        );

        // Validate display
        let mut num_types: u32 = 0;
        let mut num_requests: u32 = 0;
        let validate_err = hwcomposer_ffi::hwc2_compat_display_validate(
            data.hwc2_display,
            &mut num_types,
            &mut num_requests,
        );

        // Accept changes if needed (validate_err == 3 means HAS_CHANGES)
        if validate_err == 0 || validate_err == 3 {
            if num_types > 0 || num_requests > 0 {
                hwcomposer_ffi::hwc2_compat_display_accept_changes(data.hwc2_display);
            }

            // Present the frame
            let mut present_fence: i32 = -1;
            let present_err = hwcomposer_ffi::hwc2_compat_display_present(
                data.hwc2_display,
                &mut present_fence,
            );

            if present_err != 0 {
                data.present_errors.fetch_add(1, Ordering::Relaxed);
            }

            // Set the present fence on the buffer for the next frame
            if present_fence >= 0 {
                hwcomposer_ffi::set_buffer_fence(buffer, present_fence);
            }

            // Log progress every 60 frames
            if count % 60 == 0 {
                eprintln!("HWC2 present #{}: layer={}, target={}, validate={}, present={}, errors={}",
                    count, layer_err, target_err, validate_err, present_err,
                    data.present_errors.load(Ordering::Relaxed));
            }
        } else {
            data.present_errors.fetch_add(1, Ordering::Relaxed);
            if count % 60 == 0 {
                eprintln!("HWC2 validate failed: err={}", validate_err);
            }
        }
    } else {
        // No HWC2, just close the fence
        if acquire_fence >= 0 {
            libc::close(acquire_fence);
        }
    }

    data.frame_ready.store(true, Ordering::Release);
}

// ============================================================================
// HWC2 Event Callbacks
// ============================================================================

/// Global HWC2 device pointer for use in callbacks
static mut HWC2_DEVICE_PTR: *mut hwc2_compat_device_t = std::ptr::null_mut();

/// Vsync callback - called when display vsync occurs
unsafe extern "C" fn hwc2_on_vsync(
    _listener: *mut HWC2EventListener,
    _sequence_id: i32,
    _display: hwc2_display_t,
    _timestamp: i64,
) {
    // We don't use vsync for now, but the callback must exist
}

/// Hotplug callback - called when display is connected/disconnected
unsafe extern "C" fn hwc2_on_hotplug(
    _listener: *mut HWC2EventListener,
    _sequence_id: i32,
    display: hwc2_display_t,
    connected: bool,
    primary_display: bool,
) {
    eprintln!("HWC2 hotplug: display={}, connected={}, primary={}",
              display, connected, primary_display);

    // Notify the HWC2 device about the hotplug event
    if !HWC2_DEVICE_PTR.is_null() {
        hwcomposer_ffi::hwc2_compat_device_on_hotplug(HWC2_DEVICE_PTR, display, connected);
    }
}

/// Refresh callback - called when display needs refresh
unsafe extern "C" fn hwc2_on_refresh(
    _listener: *mut HWC2EventListener,
    _sequence_id: i32,
    _display: hwc2_display_t,
) {
    // We don't use refresh callbacks for now
}

/// Try to unblank/power on the display via various methods
fn unblank_display() {
    use std::fs::OpenOptions;
    use std::os::unix::io::AsRawFd;

    // Method 1: Try backlight bl_power sysfs (most reliable on Qualcomm devices)
    // bl_power: 0 = FB_BLANK_UNBLANK (on), 4 = FB_BLANK_POWERDOWN (off)
    if let Ok(()) = std::fs::write("/sys/class/backlight/panel0-backlight/bl_power", "0") {
        info!("Display powered on via backlight bl_power sysfs");
    } else {
        debug!("Could not write to panel0-backlight/bl_power");
    }

    // Method 2: Set brightness to max if it's at 0
    if let Ok(brightness) = std::fs::read_to_string("/sys/class/backlight/panel0-backlight/brightness") {
        if brightness.trim() == "0" {
            if let Ok(()) = std::fs::write("/sys/class/backlight/panel0-backlight/brightness", "255") {
                info!("Backlight brightness set to max");
            }
        }
    }

    // Method 3: Try fbdev ioctl to unblank
    const FBIOBLANK: libc::c_ulong = 0x4611;
    const FB_BLANK_UNBLANK: libc::c_int = 0;

    if let Ok(fb) = OpenOptions::new().write(true).open("/dev/fb0") {
        let fd = fb.as_raw_fd();
        let result = unsafe { libc::ioctl(fd, FBIOBLANK, FB_BLANK_UNBLANK) };
        if result == 0 {
            info!("Display unblanked via fbdev ioctl");
        } else {
            debug!("fbdev unblank ioctl failed: {}", std::io::Error::last_os_error());
        }
    } else {
        debug!("Could not open /dev/fb0 to unblank display");
    }

    // Method 4: Try sysfs graphics blank
    if let Ok(()) = std::fs::write("/sys/class/graphics/fb0/blank", "0") {
        info!("Display unblanked via graphics sysfs");
    }
}

/// Get display dimensions from environment or system
fn get_display_dimensions() -> (u32, u32) {
    // Try environment variables first
    if let (Ok(w), Ok(h)) = (
        std::env::var("FLICK_DISPLAY_WIDTH"),
        std::env::var("FLICK_DISPLAY_HEIGHT"),
    ) {
        if let (Ok(width), Ok(height)) = (w.parse(), h.parse()) {
            info!("Display size from environment: {}x{}", width, height);
            return (width, height);
        }
    }

    // Try /sys/class/graphics/fb0
    if let Ok(contents) = std::fs::read_to_string("/sys/class/graphics/fb0/virtual_size") {
        let parts: Vec<&str> = contents.trim().split(',').collect();
        if parts.len() >= 2 {
            if let (Ok(w), Ok(h)) = (parts[0].parse(), parts[1].parse()) {
                info!("Display size from fb0: {}x{}", w, h);
                return (w, h);
            }
        }
    }

    // Try Android properties
    if let Ok(output) = std::process::Command::new("getprop")
        .arg("ro.sf.lcd_width")
        .output()
    {
        if let Ok(width) = String::from_utf8_lossy(&output.stdout).trim().parse::<u32>() {
            if let Ok(output) = std::process::Command::new("getprop")
                .arg("ro.sf.lcd_height")
                .output()
            {
                if let Ok(height) = String::from_utf8_lossy(&output.stdout).trim().parse::<u32>() {
                    info!("Display size from Android props: {}x{}", width, height);
                    return (width, height);
                }
            }
        }
    }

    // Default
    info!("Using default display size: 1080x2340");
    (1080, 2340)
}

/// Initialize EGL and hwcomposer display
fn init_hwc_display(_output: &Output) -> Result<HwcDisplay> {
    let (width, height) = get_display_dimensions();
    info!("Initializing hwcomposer display: {}x{}", width, height);

    // Try to unblank the display first via sysfs
    unblank_display();

    // Set EGL platform environment variable
    std::env::set_var("EGL_PLATFORM", "hwcomposer");

    // Check if android hwcomposer is running
    // Either the systemd service is active, OR the composer process is running directly
    let systemd_active = std::process::Command::new("systemctl")
        .args(["is-active", "--quiet", "android-service@hwcomposer.service"])
        .status()
        .map(|s| s.success())
        .unwrap_or(false);

    // Also check if the composer process is running directly (in case started via script)
    let composer_process_running = std::process::Command::new("pgrep")
        .args(["-f", "android.hardware.graphics.composer"])
        .status()
        .map(|s| s.success())
        .unwrap_or(false);

    // Log detection results for debugging
    info!("HWC service detection: systemd={}, pgrep={}", systemd_active, composer_process_running);

    // Check if we should skip HWC2 device creation (use simpler EGL-only path)
    // The HWC2 device creation crashes on some devices, so we provide a fallback
    let skip_hwc2 = std::env::var("FLICK_SKIP_HWC2").is_ok();

    let hwc_service_active = if skip_hwc2 {
        info!("FLICK_SKIP_HWC2 set - skipping HWC2 device creation");
        false
    } else {
        true
    };

    if composer_process_running && !systemd_active {
        info!("Composer process running (started directly, not via systemd)");
    } else if !systemd_active && !composer_process_running {
        info!("Detection failed but trying HWC2 anyway (detection unreliable from within compositor)");
    }

    let (hwc2_device, hwc2_display): (Option<Hwc2Device>, Option<Hwc2Display>) = if hwc_service_active {
        info!("Android hwcomposer service is active");

        // Initialize gralloc first (required for buffer allocation)
        info!("Initializing hybris gralloc...");
        gralloc_initialize();
        info!("Gralloc initialized");

        // Initialize HWC2 subsystem BEFORE creating device
        info!("Calling hybris_hwc2_initialize()...");
        hwc2_initialize();
        info!("HWC2 subsystem initialized");

        // Now try to create HWC2 device
        info!("Creating HWC2 device...");
        let hwc2_device = Hwc2Device::new();

        match hwc2_device {
            Some(device) => {
                info!("HWC2 device created successfully");

                // Store device pointer for callbacks
                unsafe {
                    HWC2_DEVICE_PTR = device.as_ptr();
                }

                // Create event listener with our callbacks
                // Note: This must be leaked/static because HWC2 keeps a reference to it
                let event_listener = Box::leak(Box::new(HWC2EventListener {
                    on_vsync_received: Some(hwc2_on_vsync),
                    on_hotplug_received: Some(hwc2_on_hotplug),
                    on_refresh_received: Some(hwc2_on_refresh),
                }));

                // Register callbacks with the device
                info!("Registering HWC2 callbacks...");
                device.register_callback(event_listener as *mut _, 0);
                info!("HWC2 callbacks registered");

                // Trigger hotplug for primary display (ID 0)
                // This tells the hwcomposer that display 0 is connected
                device.on_hotplug(0, true);
                info!("Triggered hotplug for primary display");

                // Small delay to allow hotplug processing
                std::thread::sleep(std::time::Duration::from_millis(100));

                // Get primary display
                match device.get_primary_display() {
                    Some(display) => {
                        info!("Got HWC2 primary display");

                        // Get display config
                        if let Some(config) = display.get_active_config() {
                            info!("HWC2 display config: {}x{} @ {:.1}fps, DPI: {:.1}x{:.1}",
                                config.width, config.height,
                                1_000_000_000.0 / config.vsync_period as f64,
                                config.dpi_x, config.dpi_y);
                        }

                        // Power on display
                        match display.set_power_mode(true) {
                            Ok(()) => info!("HWC2 display powered on"),
                            Err(e) => warn!("Failed to power on HWC2 display: error {}", e),
                        }

                        (Some(device), Some(display))
                    }
                    None => {
                        warn!("Failed to get HWC2 primary display");
                        (Some(device), None)
                    }
                }
            }
            None => {
                warn!("Failed to create HWC2 device");
                (None, None)
            }
        }
    } else {
        error!("Android hwcomposer service is NOT running!");
        error!("Please start it with: sudo systemctl start android-service@hwcomposer.service");
        error!("Display output will not work without the hwcomposer service.");
        warn!("Continuing without HWC2 - rendering will work but display may be black");
        (None, None)
    };

    // Create HWC2 layer if we have a display
    let hwc2_layer = if let Some(ref display) = hwc2_display {
        match display.create_layer() {
            Some(layer) => {
                info!("Created HWC2 layer");
                // Configure the layer for fullscreen client composition
                let w = width as i32;
                let h = height as i32;

                // Set composition type to CLIENT (we render, HWC just displays)
                if let Err(e) = layer.set_composition_type(hwcomposer_ffi::hwc2_composition::HWC2_COMPOSITION_CLIENT) {
                    warn!("Failed to set layer composition type: {}", e);
                }

                // Set blend mode to NONE (opaque)
                if let Err(e) = layer.set_blend_mode(hwcomposer_ffi::hwc2_blend_mode::HWC2_BLEND_MODE_NONE) {
                    warn!("Failed to set layer blend mode: {}", e);
                }

                // Set display frame (where on screen)
                if let Err(e) = layer.set_display_frame(0, 0, w, h) {
                    warn!("Failed to set layer display frame: {}", e);
                }

                // Set source crop (portion of buffer)
                if let Err(e) = layer.set_source_crop(0.0, 0.0, width as f32, height as f32) {
                    warn!("Failed to set layer source crop: {}", e);
                }

                // Set visible region
                if let Err(e) = layer.set_visible_region(0, 0, w, h) {
                    warn!("Failed to set layer visible region: {}", e);
                }

                // Set plane alpha to fully opaque
                if let Err(e) = layer.set_plane_alpha(1.0) {
                    warn!("Failed to set layer plane alpha: {}", e);
                }

                Some(layer)
            }
            None => {
                warn!("Failed to create HWC2 layer");
                None
            }
        }
    } else {
        None
    };

    // Create present callback data with HWC2 display and layer pointers
    let frame_ready = Rc::new(AtomicBool::new(true));
    let hwc2_display_ptr = hwc2_display.as_ref()
        .map(|d| d.as_ptr())
        .unwrap_or(std::ptr::null_mut());
    let hwc2_layer_ptr = hwc2_layer.as_ref()
        .map(|l| l.as_ptr())
        .unwrap_or(std::ptr::null_mut());
    let callback_data = Box::new(PresentCallbackData {
        frame_ready: frame_ready.clone(),
        hwc2_display: hwc2_display_ptr,
        hwc2_layer: hwc2_layer_ptr,
        buffer_slot: std::sync::atomic::AtomicU32::new(0),
        present_count: std::sync::atomic::AtomicU32::new(0),
        present_errors: std::sync::atomic::AtomicU32::new(0),
    });
    let callback_data_ptr = Box::into_raw(callback_data) as *mut c_void;

    // Create HWC native window
    let native_window = unsafe {
        HwcNativeWindow::new(
            width,
            height,
            hal_format::HAL_PIXEL_FORMAT_RGBA_8888,
            Some(present_callback),
            callback_data_ptr,
        )
    }.ok_or_else(|| anyhow::anyhow!("Failed to create HWC native window"))?;

    // Set triple buffering
    if let Err(e) = native_window.set_buffer_count(3) {
        warn!("Failed to set buffer count: {}", e);
    }

    info!("Created HWC native window");

    // Load EGL dynamically
    let egl = unsafe { egl::DynamicInstance::<egl::EGL1_4>::load_required() }
        .map_err(|e| anyhow::anyhow!("Failed to load EGL: {:?}", e))?;

    info!("Loaded EGL library");

    // Get EGL display (will use hwcomposer platform due to EGL_PLATFORM env var)
    let egl_display = unsafe { egl.get_display(egl::DEFAULT_DISPLAY) }
        .ok_or_else(|| anyhow::anyhow!("Failed to get EGL display"))?;

    info!("Got EGL display");

    // Initialize EGL
    let (major, minor) = egl.initialize(egl_display)
        .map_err(|e| anyhow::anyhow!("Failed to initialize EGL: {:?}", e))?;

    info!("EGL initialized: {}.{}", major, minor);

    // Choose EGL config
    let config_attribs = [
        egl::RED_SIZE, 8,
        egl::GREEN_SIZE, 8,
        egl::BLUE_SIZE, 8,
        egl::ALPHA_SIZE, 8,
        egl::DEPTH_SIZE, 0,
        egl::STENCIL_SIZE, 0,
        egl::RENDERABLE_TYPE, egl::OPENGL_ES2_BIT,
        egl::SURFACE_TYPE, egl::WINDOW_BIT,
        egl::NONE,
    ];

    let config = egl.choose_first_config(egl_display, &config_attribs)
        .map_err(|e| anyhow::anyhow!("Failed to choose EGL config: {:?}", e))?
        .ok_or_else(|| anyhow::anyhow!("No suitable EGL config found"))?;

    info!("Chose EGL config");

    // Create EGL context
    let context_attribs = [
        egl::CONTEXT_CLIENT_VERSION, 2,
        egl::NONE,
    ];

    let egl_context = egl.create_context(egl_display, config, None, &context_attribs)
        .map_err(|e| anyhow::anyhow!("Failed to create EGL context: {:?}", e))?;

    info!("Created EGL context");

    // Create EGL surface from native window
    let surface_attribs = [egl::NONE];

    let egl_surface = unsafe {
        egl.create_window_surface(
            egl_display,
            config,
            native_window.as_ptr() as egl::NativeWindowType,
            Some(&surface_attribs),
        )
    }.map_err(|e| anyhow::anyhow!("Failed to create EGL surface: {:?}", e))?;

    info!("Created EGL surface");

    // Make context current
    egl.make_current(egl_display, Some(egl_surface), Some(egl_surface), Some(egl_context))
        .map_err(|e| anyhow::anyhow!("Failed to make EGL context current: {:?}", e))?;

    info!("Made EGL context current");

    // Initialize GL function pointers
    unsafe { gl::init(); }

    // Try to power on display again after EGL init (in case it was turned off)
    unblank_display();

    info!("HWComposer display initialized successfully");

    Ok(HwcDisplay {
        native_window,
        egl_instance: egl,
        egl_display,
        egl_surface,
        egl_context,
        width,
        height,
        hwc2_device,
        hwc2_display,
    })
}

/// Handle input events from libinput
fn handle_input_event(
    state: &mut Flick,
    event: InputEvent<LibinputInputBackend>,
    _session: &Rc<RefCell<LibSeatSession>>,
    modifiers: &Rc<RefCell<ModifierState>>,
) {
    use smithay::backend::input::{
        Event, KeyboardKeyEvent, PointerMotionEvent, PointerButtonEvent,
    };
    use smithay::input::keyboard::FilterResult;

    match event {
        InputEvent::Keyboard { event } => {
            use smithay::backend::input::KeyState;

            let keycode = event.key_code();
            let raw_keycode: u32 = keycode.raw();
            let key_state = event.state();
            let pressed = key_state == KeyState::Pressed;

            // Smithay Keycode.raw() returns XKB keycodes (evdev + 8)
            // Subtract 8 to get the raw evdev keycode
            let evdev_keycode = raw_keycode.saturating_sub(8);
            debug!("Keyboard event: evdev_keycode={}, pressed={}", evdev_keycode, pressed);

            // Track modifier state
            // Evdev keycodes: 29=LCtrl, 97=RCtrl, 56=LAlt, 100=RAlt, 42=LShift, 54=RShift, 125=LSuper, 126=RSuper
            {
                let mut mods = modifiers.borrow_mut();
                match evdev_keycode {
                    29 | 97 => mods.ctrl = pressed,
                    56 | 100 => mods.alt = pressed,
                    42 | 54 => mods.shift = pressed,
                    125 | 126 => mods.super_key = pressed,
                    _ => {}
                }
            }

            let serial = smithay::utils::SERIAL_COUNTER.next_serial();
            let time = event.time_msec();

            if let Some(keyboard) = state.seat.get_keyboard() {
                keyboard.input::<(), _>(
                    state,
                    keycode,
                    key_state,
                    serial,
                    time,
                    |_, _, _| FilterResult::Forward,
                );
            }
        }

        InputEvent::PointerMotion { event } => {
            use smithay::backend::input::PointerMotionEvent;

            let delta = event.delta();
            debug!("Pointer motion: delta=({}, {})", delta.x, delta.y);

            // Get pointer and notify of relative motion
            if let Some(pointer) = state.seat.get_pointer() {
                let serial = smithay::utils::SERIAL_COUNTER.next_serial();
                let mut pointer_pos = pointer.current_location();
                pointer_pos.x += delta.x;
                pointer_pos.y += delta.y;

                // Clamp to screen bounds
                let screen = state.screen_size;
                pointer_pos.x = pointer_pos.x.max(0.0).min(screen.w as f64);
                pointer_pos.y = pointer_pos.y.max(0.0).min(screen.h as f64);

                // No focus tracking for now - mobile is touch-focused
                let focus = None;

                pointer.motion(
                    state,
                    focus,
                    &smithay::input::pointer::MotionEvent {
                        location: pointer_pos,
                        serial,
                        time: event.time_msec(),
                    },
                );
            }
        }

        InputEvent::PointerButton { event } => {
            let serial = smithay::utils::SERIAL_COUNTER.next_serial();
            let button = event.button_code();
            let button_state = event.state();

            let pointer = state.seat.get_pointer().unwrap();
            pointer.button(
                state,
                &smithay::input::pointer::ButtonEvent {
                    button,
                    state: button_state.into(),
                    serial,
                    time: event.time_msec(),
                },
            );
        }

        InputEvent::TouchDown { event } => {
            use smithay::backend::input::{TouchEvent, AbsolutePositionEvent};
            use smithay::utils::Point;

            let slot_id: i32 = event.slot().into();
            let position = event.position_transformed(state.screen_size);
            let touch_pos = Point::from((position.x, position.y));

            // Track touch position
            state.last_touch_pos.insert(slot_id, touch_pos);

            // Forward to gesture recognizer
            if let Some(gesture_event) = state.gesture_recognizer.touch_down(slot_id, touch_pos) {
                debug!("Gesture touch_down: {:?}", gesture_event);
            }

            // Forward to Slint UI based on current view
            let shell_view = state.shell.view;
            match shell_view {
                crate::shell::ShellView::Home => {
                    // Start tracking home touch with y coordinate
                    state.shell.start_home_touch(touch_pos.y, None);
                    // Forward to Slint for visual feedback
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_pressed(touch_pos.x as f32, touch_pos.y as f32);
                    }
                }
                crate::shell::ShellView::LockScreen => {
                    // Forward to Slint for lock screen interaction
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_pressed(touch_pos.x as f32, touch_pos.y as f32);
                    }
                }
                crate::shell::ShellView::QuickSettings => {
                    // Forward to Slint for quick settings
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_pressed(touch_pos.x as f32, touch_pos.y as f32);
                    }
                }
                _ => {}
            }
        }

        InputEvent::TouchMotion { event } => {
            use smithay::backend::input::{TouchEvent, AbsolutePositionEvent};
            use smithay::utils::Point;

            let slot_id: i32 = event.slot().into();
            let position = event.position_transformed(state.screen_size);
            let touch_pos = Point::from((position.x, position.y));

            // Update tracked touch position
            state.last_touch_pos.insert(slot_id, touch_pos);

            // Forward to gesture recognizer
            if let Some(gesture_event) = state.gesture_recognizer.touch_motion(slot_id, touch_pos) {
                debug!("Gesture touch_motion: {:?}", gesture_event);
            }

            // Forward to Slint UI based on current view
            let shell_view = state.shell.view;
            match shell_view {
                crate::shell::ShellView::Home => {
                    // Forward to Slint for scroll/drag feedback
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_moved(touch_pos.x as f32, touch_pos.y as f32);
                    }
                }
                crate::shell::ShellView::LockScreen => {
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_moved(touch_pos.x as f32, touch_pos.y as f32);
                    }
                }
                crate::shell::ShellView::QuickSettings => {
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.dispatch_pointer_moved(touch_pos.x as f32, touch_pos.y as f32);
                    }
                }
                _ => {}
            }
        }

        InputEvent::TouchUp { event } => {
            use smithay::backend::input::TouchEvent;

            let slot_id: i32 = event.slot().into();

            // Get last touch position
            let last_pos = state.last_touch_pos.remove(&slot_id);

            // Forward to gesture recognizer
            if let Some(gesture_event) = state.gesture_recognizer.touch_up(slot_id) {
                debug!("Gesture touch_up: {:?}", gesture_event);
            }

            // Forward to Slint UI and handle app launching
            let shell_view = state.shell.view;
            match shell_view {
                crate::shell::ShellView::Home => {
                    // Forward to Slint
                    if let Some(pos) = last_pos {
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.dispatch_pointer_released(pos.x as f32, pos.y as f32);
                        }
                    }

                    // End home touch tracking - returns pending app if it was a tap (not scroll)
                    if let Some(exec) = state.shell.end_home_touch() {
                        info!("Launching app from home touch: {}", exec);
                        std::process::Command::new("sh")
                            .arg("-c")
                            .arg(&exec)
                            .spawn()
                            .ok();
                    }
                }
                crate::shell::ShellView::LockScreen => {
                    use crate::shell::slint_ui::LockScreenAction;

                    // Dispatch to Slint
                    if let Some(pos) = last_pos {
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.dispatch_pointer_released(pos.x as f32, pos.y as f32);
                        }
                    }

                    // Poll lock actions from Slint
                    let actions: Vec<LockScreenAction> = if let Some(ref slint_ui) = state.shell.slint_ui {
                        slint_ui.poll_lock_actions()
                    } else {
                        Vec::new()
                    };

                    // Process actions
                    for action in actions {
                        match action {
                            LockScreenAction::PinDigit(digit) => {
                                state.shell.lock_state.entered_pin.push_str(&digit);
                            }
                            LockScreenAction::PinBackspace => {
                                state.shell.lock_state.entered_pin.pop();
                            }
                            _ => {}
                        }
                    }

                    // Try to unlock if PIN is long enough
                    if state.shell.lock_state.entered_pin.len() >= 4 {
                        if state.shell.try_unlock() {
                            info!("Lock screen unlocked!");
                        } else {
                            // Failed attempt - reset PIN
                            state.shell.lock_state.entered_pin.clear();
                        }
                    }
                }
                crate::shell::ShellView::QuickSettings => {
                    if let Some(pos) = last_pos {
                        if let Some(ref slint_ui) = state.shell.slint_ui {
                            slint_ui.dispatch_pointer_released(pos.x as f32, pos.y as f32);
                        }
                    }
                }
                _ => {}
            }
        }

        _ => {}
    }
}

pub fn run() -> Result<()> {
    info!("Starting hwcomposer backend");

    // Set EGL platform
    std::env::set_var("EGL_PLATFORM", "hwcomposer");

    // Create event loop
    let mut event_loop: EventLoop<Flick> = EventLoop::try_new()?;
    let loop_handle = event_loop.handle();

    // Initialize libseat session
    let (session, notifier) = LibSeatSession::new()
        .map_err(|e| anyhow::anyhow!("Failed to create session: {:?}", e))?;

    let session = Rc::new(RefCell::new(session));
    info!("Session created, seat: {}", session.borrow().seat());

    // Initialize libinput
    let libinput_session = LibinputSessionInterface::from(session.borrow().clone());
    let mut libinput_context = Libinput::new_with_udev(libinput_session);
    libinput_context.udev_assign_seat(&session.borrow().seat()).unwrap();

    let libinput_backend = LibinputInputBackend::new(libinput_context.clone());

    // Create Wayland display
    let display: Display<Flick> = Display::new()?;

    // Get display dimensions
    let (width, height) = get_display_dimensions();
    let screen_size = (width as i32, height as i32).into();

    let mut state = Flick::new(display, loop_handle.clone(), screen_size);

    info!("Wayland socket: {:?}", state.socket_name);
    std::env::set_var("WAYLAND_DISPLAY", &state.socket_name);

    // Create Wayland output
    let output = Output::new(
        "hwcomposer-0".to_string(),
        PhysicalProperties {
            size: (0, 0).into(),
            subpixel: Subpixel::Unknown,
            make: "Flick".to_string(),
            model: "HWComposer".to_string(),
            serial_number: "Unknown".to_string(),
        },
    );

    let mode = Mode {
        size: (width as i32, height as i32).into(),
        refresh: 60_000,
    };

    output.change_current_state(
        Some(mode),
        Some(Transform::Normal),
        None,
        Some((0, 0).into()),
    );
    output.set_preferred(mode);

    output.create_global::<Flick>(&state.display_handle);
    state.space.map_output(&output, (0, 0));
    state.outputs.push(output.clone());

    info!("Output registered: {}x{}", width, height);

    // Initialize hwcomposer display
    let mut hwc_display = init_hwc_display(&output)?;

    // Bind EGL to Wayland display for libhybris clients
    // This is required for EGL_WL_bind_wayland_display extension to work
    {
        // Get the raw wl_display pointer using wayland-backend's server_system feature
        let mut display_ref = state.display.borrow_mut();
        let backend = display_ref.backend();

        // With server_system feature, backend provides display_ptr()
        #[cfg(feature = "hwcomposer")]
        unsafe {
            use wayland_backend::server::Backend as WaylandBackend;

            // The backend's handle has display_ptr() method with server_system feature
            let wl_display_ptr = backend.handle().display_ptr();

            // Load eglBindWaylandDisplayWL function
            type EglBindWaylandDisplayWL = unsafe extern "C" fn(
                *mut std::ffi::c_void, // EGLDisplay
                *mut std::ffi::c_void, // wl_display*
            ) -> u32; // EGLBoolean

            let bind_fn_ptr = hwc_display.egl_instance.get_proc_address("eglBindWaylandDisplayWL");
            if let Some(fn_ptr) = bind_fn_ptr {
                let bind_wayland_display: EglBindWaylandDisplayWL = std::mem::transmute(fn_ptr);
                let result = bind_wayland_display(
                    hwc_display.egl_display.as_ptr() as *mut std::ffi::c_void,
                    wl_display_ptr as *mut std::ffi::c_void,
                );
                if result == egl::TRUE as u32 {
                    info!("Successfully bound EGL to Wayland display");
                } else {
                    warn!("Failed to bind EGL to Wayland display (result={})", result);
                }
            } else {
                info!("eglBindWaylandDisplayWL not available (may be OK for non-libhybris)");
            }
        }
    }

    // Update state with actual screen size
    state.screen_size = (width as i32, height as i32).into();
    state.gesture_recognizer.screen_size = state.screen_size;
    state.shell.screen_size = state.screen_size;
    state.shell.quick_settings.screen_size = state.screen_size;

    if let Some(ref mut slint_ui) = state.shell.slint_ui {
        slint_ui.set_size(state.screen_size);
    }

    // Launch QML lock screen app if configured
    if state.shell.lock_screen_active {
        info!("Lock screen active - launching QML lock screen app");
        if let Some(socket) = state.socket_name.to_str() {
            state.shell.launch_lock_screen_app(socket);
        }
    }

    // Track session state
    let session_active = Rc::new(RefCell::new(true));
    let session_active_for_notifier = session_active.clone();

    let modifiers = Rc::new(RefCell::new(ModifierState::default()));
    let modifiers_for_notifier = modifiers.clone();

    // Add session notifier
    loop_handle
        .insert_source(notifier, move |event, _, _state| match event {
            SessionEvent::PauseSession => {
                info!("Session paused");
                *session_active_for_notifier.borrow_mut() = false;
            }
            SessionEvent::ActivateSession => {
                info!("Session activated");
                *session_active_for_notifier.borrow_mut() = true;
                *modifiers_for_notifier.borrow_mut() = ModifierState::default();
            }
        })
        .map_err(|e| anyhow::anyhow!("Failed to insert session source: {:?}", e))?;

    // Add libinput to event loop
    let session_for_input = session.clone();
    let modifiers_for_input = modifiers.clone();

    loop_handle
        .insert_source(libinput_backend, move |event, _, state| {
            handle_input_event(state, event, &session_for_input, &modifiers_for_input);
        })
        .map_err(|e| anyhow::anyhow!("Failed to insert input source: {:?}", e))?;

    // Add render timer (60fps target)
    let render_timer = Timer::immediate();
    loop_handle
        .insert_source(render_timer, move |_, _, _| {
            TimeoutAction::ToDuration(Duration::from_millis(16))
        })
        .map_err(|e| anyhow::anyhow!("Failed to insert render timer: {:?}", e))?;

    info!("Entering event loop");

    // Main event loop
    let mut loop_count: u64 = 0;
    loop {
        loop_count += 1;
        let log_loop = loop_count % 1000 == 0;

        if log_loop {
            debug!("Event loop iteration {}", loop_count);
        }

        // Dispatch incoming Wayland client requests - this is critical!
        // Without this, clients connect but their protocol messages are never processed.
        // Use the safe dispatch_clients method that handles the borrow properly.
        state.dispatch_clients();

        // Log every loop iteration for debugging
        debug!("Loop {}: after dispatch_clients", loop_count);

        // Dispatch calloop events
        event_loop
            .dispatch(Some(Duration::from_millis(1)), &mut state)
            .map_err(|e| anyhow::anyhow!("Event loop error: {:?}", e))?;

        debug!("Loop {}: after calloop dispatch", loop_count);

        // Skip rendering if session not active
        if !*session_active.borrow() {
            debug!("Loop {}: session not active, skipping render", loop_count);
            continue;
        }

        debug!("Loop {}: calling render_frame", loop_count);
        // Render frame
        if let Err(e) = render_frame(&mut hwc_display, &state, &output) {
            error!("Render error: {:?}", e);
        }
        debug!("Loop {}: after render_frame", loop_count);

        // Send frame callbacks to Wayland clients
        state.space.elements().for_each(|window| {
            window.send_frame(
                &output,
                state.start_time.elapsed(),
                Some(Duration::ZERO),
                |_, _| Some(output.clone()),
            );
        });
    }
}

// Frame counter for render_frame logging
static mut RENDER_FRAME_COUNT: u64 = 0;

/// Render a frame to the hwcomposer display
fn render_frame(
    display: &mut HwcDisplay,
    state: &Flick,
    _output: &Output,
) -> Result<()> {
    let frame_num = unsafe {
        RENDER_FRAME_COUNT += 1;
        RENDER_FRAME_COUNT
    };
    let log_frame = frame_num % 60 == 0;

    // Make our EGL context current
    display.egl_instance.make_current(
        display.egl_display,
        Some(display.egl_surface),
        Some(display.egl_surface),
        Some(display.egl_context),
    ).map_err(|e| anyhow::anyhow!("Failed to make context current: {:?}", e))?;

    // Set viewport to full screen
    unsafe {
        if let Some(f) = gl::FN_VIEWPORT {
            f(0, 0, display.width as i32, display.height as i32);
        }
    }

    // For first 120 frames, render alternating bright colors to test basic rendering
    // Also flash colors for 10 frames every 120 frames after to verify display is still updating
    let test_mode = frame_num <= 120 || (frame_num % 120 < 10);

    if test_mode {
        // Cycle through bright colors: red, green, blue every 40 frames
        let color = match (frame_num / 40) % 3 {
            0 => [1.0f32, 0.0, 0.0, 1.0], // Red
            1 => [0.0, 1.0, 0.0, 1.0],    // Green
            _ => [0.0, 0.0, 1.0, 1.0],    // Blue
        };

        unsafe {
            gl::ClearColor(color[0], color[1], color[2], color[3]);
            gl::Clear(gl::COLOR_BUFFER_BIT);
            gl::Flush();
        }

        if log_frame || frame_num == 1 || frame_num == 40 || frame_num == 80 || frame_num == 120 {
            let (sw, sh) = (display.width, display.height);
            info!("Test mode frame {}: color=({:.1},{:.1},{:.1}) screen={}x{}",
                frame_num, color[0], color[1], color[2], sw, sh);
        }
    } else {
        // Normal rendering mode
        // Determine background color based on shell view
        let shell_view = state.shell.view;
        if log_frame {
            info!("Shell view: {:?}, lock_screen_active: {}", shell_view, state.shell.lock_screen_active);
        }
        let bg_color = match shell_view {
            ShellView::Home | ShellView::QuickSettings | ShellView::PickDefault | ShellView::LockScreen => [0.1, 0.1, 0.15, 1.0],
            ShellView::Switcher => [0.05, 0.05, 0.08, 1.0],
            ShellView::App => [0.0, 0.0, 0.0, 1.0],
        };

        // Clear screen with background color
        unsafe {
            gl::ClearColor(bg_color[0], bg_color[1], bg_color[2], bg_color[3]);
            gl::Clear(gl::COLOR_BUFFER_BIT);
        }

        // Check if QML lockscreen app is connected
        let element_count = state.space.elements().count();
        let qml_lockscreen_connected = shell_view == ShellView::LockScreen
            && state.shell.lock_screen_active
            && element_count > 0;

        if log_frame {
            info!("RENDER: view={:?}, lock_active={}, elements={}, qml_connected={}",
                shell_view, state.shell.lock_screen_active, element_count, qml_lockscreen_connected);
        }

        // Render Slint UI for shell views (but not when QML lockscreen is connected)
        if !qml_lockscreen_connected {
            match shell_view {
                ShellView::Home | ShellView::QuickSettings | ShellView::Switcher | ShellView::PickDefault | ShellView::LockScreen => {
                    // Update Slint timers and animations (needed for clock updates, etc.)
                    slint::platform::update_timers_and_animations();

                    // Set up Slint UI state based on current view
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        match shell_view {
                            ShellView::LockScreen => {
                                // QML lockscreen not connected yet - show debug info
                                slint_ui.set_view("lock");
                                slint_ui.set_lock_time("DEBUG");
                                slint_ui.set_lock_date("Waiting for QML lockscreen...");
                                slint_ui.set_lock_error("If stuck here: check ~/.local/state/flick/qml_lockscreen.log");
                                if log_frame {
                                    warn!("LockScreen view but no QML app connected - showing debug fallback");
                                }
                                slint_ui.set_pin_length(state.shell.lock_state.entered_pin.len() as i32);
                            }
                            ShellView::Home => {
                                slint_ui.set_view("home");
                                let slint_categories = state.shell.get_categories_with_icons();
                                slint_ui.set_categories(slint_categories);
                                slint_ui.set_show_popup(state.shell.popup_showing);
                                slint_ui.set_wiggle_mode(state.shell.wiggle_mode);
                            }
                            ShellView::QuickSettings => {
                                slint_ui.set_view("quick-settings");
                                slint_ui.set_brightness(state.shell.quick_settings.brightness);
                                slint_ui.set_wifi_enabled(state.system.wifi_enabled);
                                slint_ui.set_bluetooth_enabled(state.system.bluetooth_enabled);
                            }
                            ShellView::Switcher => {
                                slint_ui.set_view("switcher");
                                slint_ui.set_switcher_scroll(state.shell.switcher_scroll as f32);
                            }
                            ShellView::PickDefault => {
                                slint_ui.set_view("pick-default");
                            }
                            _ => {}
                        }
                    }

                    // Get Slint rendered pixels
                    if let Some(ref slint_ui) = state.shell.slint_ui {
                        if let Some((width, height, pixels)) = slint_ui.render() {
                            if log_frame {
                                info!("SLINT RENDERING: {}x{} (qml_connected={}, elements={})",
                                    width, height, qml_lockscreen_connected, element_count);
                            }
                            unsafe {
                                gl::render_texture(width, height, &pixels, display.width, display.height);
                            }
                            if log_frame {
                                debug!("Rendered Slint UI {}x{}", width, height);
                            }
                        }
                    }
                }
                _ => {}
            }
        }

        // Render Wayland windows for App view OR QML lockscreen
        if shell_view == ShellView::App || qml_lockscreen_connected {
            if qml_lockscreen_connected && log_frame {
                info!("Rendering QML lockscreen window");
            }
            // Render Wayland client surfaces (windows)
            let windows: Vec<_> = state.space.elements().cloned().collect();
            debug!("Rendering {} Wayland windows", windows.len());

            for (i, window) in windows.iter().enumerate() {
                debug!("Processing window {}", i);
                // Get the surface from the window
                if let Some(toplevel) = window.toplevel() {
                    debug!("Window {} has toplevel", i);
                    let wl_surface = toplevel.wl_surface();
                    debug!("Window {} surface: {:?}", i, wl_surface.id());

                    // Render using stored buffer data from commit handler
                    debug!("Window {} trying to render stored buffer", i);

                    // Get stored buffer from surface user data
                    let buffer_info: Option<(u32, u32, Vec<u8>)> = compositor::with_states(wl_surface, |data| {
                        debug!("  stored: inside with_states");
                        use std::cell::RefCell;
                        use crate::state::SurfaceBufferData;

                        if let Some(buffer_data) = data.data_map.get::<RefCell<SurfaceBufferData>>() {
                            let data = buffer_data.borrow();
                            if let Some(ref stored) = data.buffer {
                                debug!("  stored: found buffer {}x{}", stored.width, stored.height);
                                Some((stored.width, stored.height, stored.pixels.clone()))
                            } else {
                                debug!("  stored: no buffer in data_map");
                                None
                            }
                        } else {
                            debug!("  stored: no SurfaceBufferData in data_map");
                            None
                        }
                    });
                    debug!("Window {} after with_states", i);

                    // Render outside of with_states to avoid holding locks
                    if let Some((width, height, pixels)) = buffer_info {
                        debug!("Window {} rendering {}x{} buffer ({} bytes)", i, width, height, pixels.len());
                        unsafe {
                            gl::render_texture(width, height, &pixels, display.width, display.height);
                        }
                        debug!("Window {} render complete", i);
                    } else {
                        debug!("Window {} no stored buffer to render", i);
                    }
                }
            }
            debug!("Finished rendering windows");
        }
    }

    debug!("render_frame: before swap_buffers");
    // Swap EGL buffers - this triggers the present callback which handles display
    display.egl_instance.swap_buffers(display.egl_display, display.egl_surface)
        .map_err(|e| anyhow::anyhow!("Failed to swap buffers: {:?}", e))?;

    Ok(())
}

// OpenGL ES 2.0 bindings for texture rendering
mod gl {
    use std::os::raw::{c_char, c_int, c_uint, c_void};
    use std::ffi::CString;

    // GL constants
    pub const COLOR_BUFFER_BIT: u32 = 0x00004000;
    pub const TEXTURE_2D: u32 = 0x0DE1;
    pub const RGBA: u32 = 0x1908;
    pub const UNSIGNED_BYTE: u32 = 0x1401;
    pub const TEXTURE_MIN_FILTER: u32 = 0x2801;
    pub const TEXTURE_MAG_FILTER: u32 = 0x2800;
    pub const LINEAR: i32 = 0x2601;
    pub const FLOAT: u32 = 0x1406;
    pub const TRIANGLE_STRIP: u32 = 0x0005;
    pub const VERTEX_SHADER: u32 = 0x8B31;
    pub const FRAGMENT_SHADER: u32 = 0x8B30;
    pub const COMPILE_STATUS: u32 = 0x8B81;
    pub const LINK_STATUS: u32 = 0x8B82;
    pub const BLEND: u32 = 0x0BE2;
    pub const SRC_ALPHA: u32 = 0x0302;
    pub const ONE_MINUS_SRC_ALPHA: u32 = 0x0303;
    pub const FALSE: u8 = 0;

    // Function pointer types
    type ClearColorFn = unsafe extern "C" fn(f32, f32, f32, f32);
    type ClearFn = unsafe extern "C" fn(u32);
    type ViewportFn = unsafe extern "C" fn(i32, i32, i32, i32);
    type GenTexturesFn = unsafe extern "C" fn(i32, *mut u32);
    type BindTextureFn = unsafe extern "C" fn(u32, u32);
    type TexImage2DFn = unsafe extern "C" fn(u32, i32, i32, i32, i32, i32, u32, u32, *const c_void);
    type TexParameteriFn = unsafe extern "C" fn(u32, u32, i32);
    type CreateShaderFn = unsafe extern "C" fn(u32) -> u32;
    type ShaderSourceFn = unsafe extern "C" fn(u32, i32, *const *const c_char, *const i32);
    type CompileShaderFn = unsafe extern "C" fn(u32);
    type GetShaderivFn = unsafe extern "C" fn(u32, u32, *mut i32);
    type CreateProgramFn = unsafe extern "C" fn() -> u32;
    type AttachShaderFn = unsafe extern "C" fn(u32, u32);
    type LinkProgramFn = unsafe extern "C" fn(u32);
    type GetProgramivFn = unsafe extern "C" fn(u32, u32, *mut i32);
    type UseProgramFn = unsafe extern "C" fn(u32);
    type GetAttribLocationFn = unsafe extern "C" fn(u32, *const c_char) -> i32;
    type GetUniformLocationFn = unsafe extern "C" fn(u32, *const c_char) -> i32;
    type EnableVertexAttribArrayFn = unsafe extern "C" fn(u32);
    type VertexAttribPointerFn = unsafe extern "C" fn(u32, i32, u32, u8, i32, *const c_void);
    type DrawArraysFn = unsafe extern "C" fn(u32, i32, i32);
    type Uniform1iFn = unsafe extern "C" fn(i32, i32);
    type ActiveTextureFn = unsafe extern "C" fn(u32);
    type EnableFn = unsafe extern "C" fn(u32);
    type DisableFn = unsafe extern "C" fn(u32);
    type BlendFuncFn = unsafe extern "C" fn(u32, u32);
    type DeleteTexturesFn = unsafe extern "C" fn(i32, *const u32);
    type DeleteShaderFn = unsafe extern "C" fn(u32);
    type DeleteProgramFn = unsafe extern "C" fn(u32);
    type GetErrorFn = unsafe extern "C" fn() -> u32;
    type FlushFn = unsafe extern "C" fn();
    type FinishFn = unsafe extern "C" fn();

    // Cached function pointers
    static mut FN_CLEAR_COLOR: Option<ClearColorFn> = None;
    static mut FN_CLEAR: Option<ClearFn> = None;
    pub static mut FN_VIEWPORT: Option<ViewportFn> = None;
    static mut FN_GEN_TEXTURES: Option<GenTexturesFn> = None;
    static mut FN_BIND_TEXTURE: Option<BindTextureFn> = None;
    static mut FN_TEX_IMAGE_2D: Option<TexImage2DFn> = None;
    static mut FN_TEX_PARAMETERI: Option<TexParameteriFn> = None;
    static mut FN_CREATE_SHADER: Option<CreateShaderFn> = None;
    static mut FN_SHADER_SOURCE: Option<ShaderSourceFn> = None;
    static mut FN_COMPILE_SHADER: Option<CompileShaderFn> = None;
    static mut FN_GET_SHADERIV: Option<GetShaderivFn> = None;
    static mut FN_CREATE_PROGRAM: Option<CreateProgramFn> = None;
    static mut FN_ATTACH_SHADER: Option<AttachShaderFn> = None;
    static mut FN_LINK_PROGRAM: Option<LinkProgramFn> = None;
    static mut FN_GET_PROGRAMIV: Option<GetProgramivFn> = None;
    static mut FN_USE_PROGRAM: Option<UseProgramFn> = None;
    static mut FN_GET_ATTRIB_LOCATION: Option<GetAttribLocationFn> = None;
    static mut FN_GET_UNIFORM_LOCATION: Option<GetUniformLocationFn> = None;
    static mut FN_ENABLE_VERTEX_ATTRIB_ARRAY: Option<EnableVertexAttribArrayFn> = None;
    static mut FN_VERTEX_ATTRIB_POINTER: Option<VertexAttribPointerFn> = None;
    static mut FN_DRAW_ARRAYS: Option<DrawArraysFn> = None;
    static mut FN_UNIFORM1I: Option<Uniform1iFn> = None;
    static mut FN_ACTIVE_TEXTURE: Option<ActiveTextureFn> = None;
    static mut FN_ENABLE: Option<EnableFn> = None;
    static mut FN_DISABLE: Option<DisableFn> = None;
    static mut FN_BLEND_FUNC: Option<BlendFuncFn> = None;
    static mut FN_DELETE_TEXTURES: Option<DeleteTexturesFn> = None;
    static mut FN_DELETE_SHADER: Option<DeleteShaderFn> = None;
    static mut FN_DELETE_PROGRAM: Option<DeleteProgramFn> = None;
    static mut FN_GET_ERROR: Option<GetErrorFn> = None;
    static mut FN_FLUSH: Option<FlushFn> = None;
    static mut FN_FINISH: Option<FinishFn> = None;

    static mut INITIALIZED: bool = false;
    static mut SHADER_PROGRAM: u32 = 0;
    static mut ATTR_POSITION: i32 = -1;
    static mut ATTR_TEXCOORD: i32 = -1;
    static mut UNIFORM_TEXTURE: i32 = -1;

    // Vertex shader - simple pass-through
    const VERTEX_SHADER_SRC: &str = r#"
        attribute vec2 a_position;
        attribute vec2 a_texcoord;
        varying vec2 v_texcoord;
        void main() {
            gl_Position = vec4(a_position, 0.0, 1.0);
            v_texcoord = a_texcoord;
        }
    "#;

    // Fragment shader - texture sampling
    const FRAGMENT_SHADER_SRC: &str = r#"
        precision mediump float;
        varying vec2 v_texcoord;
        uniform sampler2D u_texture;
        void main() {
            gl_FragColor = texture2D(u_texture, v_texcoord);
        }
    "#;

    unsafe fn load_fn<T>(lib: *mut c_void, name: &[u8]) -> Option<T> {
        let ptr = libc::dlsym(lib, name.as_ptr() as *const _);
        if ptr.is_null() {
            None
        } else {
            Some(std::mem::transmute_copy(&ptr))
        }
    }

    pub unsafe fn init() {
        if INITIALIZED {
            return;
        }

        // Load libGLESv2
        let lib = libc::dlopen(
            b"libGLESv2.so.2\0".as_ptr() as *const _,
            libc::RTLD_NOW | libc::RTLD_GLOBAL,
        );
        let lib = if lib.is_null() {
            libc::dlopen(
                b"libGLESv2.so\0".as_ptr() as *const _,
                libc::RTLD_NOW | libc::RTLD_GLOBAL,
            )
        } else {
            lib
        };

        if lib.is_null() {
            tracing::error!("Failed to load libGLESv2");
            return;
        }

        // Load all GL functions
        FN_CLEAR_COLOR = load_fn(lib, b"glClearColor\0");
        FN_CLEAR = load_fn(lib, b"glClear\0");
        FN_VIEWPORT = load_fn(lib, b"glViewport\0");
        FN_GEN_TEXTURES = load_fn(lib, b"glGenTextures\0");
        FN_BIND_TEXTURE = load_fn(lib, b"glBindTexture\0");
        FN_TEX_IMAGE_2D = load_fn(lib, b"glTexImage2D\0");
        FN_TEX_PARAMETERI = load_fn(lib, b"glTexParameteri\0");
        FN_CREATE_SHADER = load_fn(lib, b"glCreateShader\0");
        FN_SHADER_SOURCE = load_fn(lib, b"glShaderSource\0");
        FN_COMPILE_SHADER = load_fn(lib, b"glCompileShader\0");
        FN_GET_SHADERIV = load_fn(lib, b"glGetShaderiv\0");
        FN_CREATE_PROGRAM = load_fn(lib, b"glCreateProgram\0");
        FN_ATTACH_SHADER = load_fn(lib, b"glAttachShader\0");
        FN_LINK_PROGRAM = load_fn(lib, b"glLinkProgram\0");
        FN_GET_PROGRAMIV = load_fn(lib, b"glGetProgramiv\0");
        FN_USE_PROGRAM = load_fn(lib, b"glUseProgram\0");
        FN_GET_ATTRIB_LOCATION = load_fn(lib, b"glGetAttribLocation\0");
        FN_GET_UNIFORM_LOCATION = load_fn(lib, b"glGetUniformLocation\0");
        FN_ENABLE_VERTEX_ATTRIB_ARRAY = load_fn(lib, b"glEnableVertexAttribArray\0");
        FN_VERTEX_ATTRIB_POINTER = load_fn(lib, b"glVertexAttribPointer\0");
        FN_DRAW_ARRAYS = load_fn(lib, b"glDrawArrays\0");
        FN_UNIFORM1I = load_fn(lib, b"glUniform1i\0");
        FN_ACTIVE_TEXTURE = load_fn(lib, b"glActiveTexture\0");
        FN_ENABLE = load_fn(lib, b"glEnable\0");
        FN_DISABLE = load_fn(lib, b"glDisable\0");
        FN_BLEND_FUNC = load_fn(lib, b"glBlendFunc\0");
        FN_DELETE_TEXTURES = load_fn(lib, b"glDeleteTextures\0");
        FN_DELETE_SHADER = load_fn(lib, b"glDeleteShader\0");
        FN_DELETE_PROGRAM = load_fn(lib, b"glDeleteProgram\0");
        FN_GET_ERROR = load_fn(lib, b"glGetError\0");
        FN_FLUSH = load_fn(lib, b"glFlush\0");
        FN_FINISH = load_fn(lib, b"glFinish\0");

        // Create shader program
        if let Some(program) = create_shader_program() {
            SHADER_PROGRAM = program;

            let pos_name = CString::new("a_position").unwrap();
            let tex_name = CString::new("a_texcoord").unwrap();
            let uni_name = CString::new("u_texture").unwrap();

            if let Some(f) = FN_GET_ATTRIB_LOCATION {
                ATTR_POSITION = f(program, pos_name.as_ptr());
                ATTR_TEXCOORD = f(program, tex_name.as_ptr());
            }
            if let Some(f) = FN_GET_UNIFORM_LOCATION {
                UNIFORM_TEXTURE = f(program, uni_name.as_ptr());
            }

            tracing::info!("GL shader program created: program={}, pos={}, tex={}, uni={}",
                SHADER_PROGRAM, ATTR_POSITION, ATTR_TEXCOORD, UNIFORM_TEXTURE);
        }

        INITIALIZED = true;
        tracing::info!("OpenGL ES 2.0 functions loaded");
    }

    unsafe fn create_shader_program() -> Option<u32> {
        let create_shader = FN_CREATE_SHADER?;
        let shader_source = FN_SHADER_SOURCE?;
        let compile_shader = FN_COMPILE_SHADER?;
        let get_shaderiv = FN_GET_SHADERIV?;
        let create_program = FN_CREATE_PROGRAM?;
        let attach_shader = FN_ATTACH_SHADER?;
        let link_program = FN_LINK_PROGRAM?;
        let get_programiv = FN_GET_PROGRAMIV?;

        // Create vertex shader
        let vs = create_shader(VERTEX_SHADER);
        let vs_src = CString::new(VERTEX_SHADER_SRC).unwrap();
        let vs_ptr = vs_src.as_ptr();
        shader_source(vs, 1, &vs_ptr, std::ptr::null());
        compile_shader(vs);

        let mut status: i32 = 0;
        get_shaderiv(vs, COMPILE_STATUS, &mut status);
        if status == 0 {
            tracing::error!("Vertex shader compilation failed");
            return None;
        }

        // Create fragment shader
        let fs = create_shader(FRAGMENT_SHADER);
        let fs_src = CString::new(FRAGMENT_SHADER_SRC).unwrap();
        let fs_ptr = fs_src.as_ptr();
        shader_source(fs, 1, &fs_ptr, std::ptr::null());
        compile_shader(fs);

        get_shaderiv(fs, COMPILE_STATUS, &mut status);
        if status == 0 {
            tracing::error!("Fragment shader compilation failed");
            return None;
        }

        // Create program
        let program = create_program();
        attach_shader(program, vs);
        attach_shader(program, fs);
        link_program(program);

        get_programiv(program, LINK_STATUS, &mut status);
        if status == 0 {
            tracing::error!("Shader program linking failed");
            return None;
        }

        Some(program)
    }

    #[allow(non_snake_case)]
    pub unsafe fn ClearColor(r: f32, g: f32, b: f32, a: f32) {
        if let Some(f) = FN_CLEAR_COLOR { f(r, g, b, a); }
    }

    #[allow(non_snake_case)]
    pub unsafe fn Clear(mask: u32) {
        if let Some(f) = FN_CLEAR { f(mask); }
    }

    #[allow(non_snake_case)]
    pub unsafe fn GetError() -> u32 {
        if let Some(f) = FN_GET_ERROR { f() } else { 0 }
    }

    #[allow(non_snake_case)]
    pub unsafe fn Flush() {
        if let Some(f) = FN_FLUSH { f(); }
    }

    #[allow(non_snake_case)]
    pub unsafe fn Finish() {
        if let Some(f) = FN_FINISH { f(); }
    }

    fn check_error(location: &str) {
        unsafe {
            let err = GetError();
            if err != 0 {
                tracing::error!("GL error at {}: 0x{:04X}", location, err);
            }
        }
    }

    // Frame counter for throttled logging
    static mut FRAME_COUNT: u64 = 0;

    /// Render a texture (RGBA pixel buffer) to fill the screen
    pub unsafe fn render_texture(tex_width: u32, tex_height: u32, pixels: &[u8], screen_width: u32, screen_height: u32) {
        FRAME_COUNT += 1;
        let log_frame = FRAME_COUNT % 60 == 0; // Log every 60 frames

        if SHADER_PROGRAM == 0 || ATTR_POSITION < 0 || ATTR_TEXCOORD < 0 {
            tracing::warn!("Shader not initialized");
            return;
        }

        // Clear any pending errors
        while GetError() != 0 {}

        // Set viewport
        if let Some(f) = FN_VIEWPORT {
            f(0, 0, screen_width as i32, screen_height as i32);
        }
        check_error("viewport");

        // Create and bind texture
        let mut texture: u32 = 0;
        if let Some(f) = FN_GEN_TEXTURES { f(1, &mut texture); }
        check_error("genTextures");

        if let Some(f) = FN_BIND_TEXTURE { f(TEXTURE_2D, texture); }
        check_error("bindTexture");

        // Set texture parameters
        if let Some(f) = FN_TEX_PARAMETERI {
            f(TEXTURE_2D, TEXTURE_MIN_FILTER, LINEAR);
            f(TEXTURE_2D, TEXTURE_MAG_FILTER, LINEAR);
        }
        check_error("texParameteri");

        // Upload texture data
        let expected_size = (tex_width * tex_height * 4) as usize;
        if pixels.len() != expected_size {
            tracing::error!("Pixel buffer size mismatch: got {}, expected {}", pixels.len(), expected_size);
            return;
        }

        if let Some(f) = FN_TEX_IMAGE_2D {
            f(TEXTURE_2D, 0, RGBA as i32, tex_width as i32, tex_height as i32,
              0, RGBA, UNSIGNED_BYTE, pixels.as_ptr() as *const c_void);
        }
        check_error("texImage2D");

        // Use shader program
        if let Some(f) = FN_USE_PROGRAM { f(SHADER_PROGRAM); }
        check_error("useProgram");

        // Set texture uniform
        if let Some(f) = FN_ACTIVE_TEXTURE { f(0x84C0); } // GL_TEXTURE0
        check_error("activeTexture");

        if let Some(f) = FN_BIND_TEXTURE { f(TEXTURE_2D, texture); }
        check_error("bindTexture2");

        if let Some(f) = FN_UNIFORM1I { f(UNIFORM_TEXTURE, 0); }
        check_error("uniform1i");

        // Full-screen quad vertices (position + texcoord interleaved)
        // Note: Y is flipped for texcoord because Slint renders top-down
        #[rustfmt::skip]
        let vertices: [f32; 16] = [
            // Position (x, y)  // TexCoord (u, v)
            -1.0, -1.0,         0.0, 1.0,  // Bottom-left
             1.0, -1.0,         1.0, 1.0,  // Bottom-right
            -1.0,  1.0,         0.0, 0.0,  // Top-left
             1.0,  1.0,         1.0, 0.0,  // Top-right
        ];

        // Set vertex attributes
        if let Some(f) = FN_ENABLE_VERTEX_ATTRIB_ARRAY {
            f(ATTR_POSITION as u32);
            f(ATTR_TEXCOORD as u32);
        }
        check_error("enableVertexAttribArray");

        if let Some(f) = FN_VERTEX_ATTRIB_POINTER {
            let stride = 4 * std::mem::size_of::<f32>() as i32;
            f(ATTR_POSITION as u32, 2, FLOAT, FALSE, stride, vertices.as_ptr() as *const c_void);
            f(ATTR_TEXCOORD as u32, 2, FLOAT, FALSE, stride,
              (vertices.as_ptr() as *const f32).add(2) as *const c_void);
        }
        check_error("vertexAttribPointer");

        // Enable blending for transparency
        if let Some(f) = FN_ENABLE { f(BLEND); }
        if let Some(f) = FN_BLEND_FUNC { f(SRC_ALPHA, ONE_MINUS_SRC_ALPHA); }
        check_error("blend setup");

        // Draw
        if let Some(f) = FN_DRAW_ARRAYS {
            f(TRIANGLE_STRIP, 0, 4);
        }
        check_error("drawArrays");

        // Flush to ensure commands are sent to GPU
        Flush();

        // Cleanup
        if let Some(f) = FN_DISABLE { f(BLEND); }
        if let Some(f) = FN_DELETE_TEXTURES { f(1, &texture); }

        if log_frame {
            // Log first few pixels to verify content
            let r = pixels.get(0).copied().unwrap_or(0);
            let g = pixels.get(1).copied().unwrap_or(0);
            let b = pixels.get(2).copied().unwrap_or(0);
            let a = pixels.get(3).copied().unwrap_or(0);
            tracing::info!("Frame {}: texture={}x{} -> screen={}x{}, tex_id={}, first_pixel=RGBA({},{},{},{})",
                FRAME_COUNT, tex_width, tex_height, screen_width, screen_height, texture, r, g, b, a);
        }
    }
}
