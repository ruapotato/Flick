//! DRM Shim backend - uses drm-hwcomposer-shim for libhybris devices
//!
//! This backend provides display and rendering via hwcomposer, using
//! the drm-hwcomposer-shim crate to abstract Android's hwcomposer.
//! Touch input comes from libinput (same as the udev backend).

use std::{
    cell::RefCell,
    os::unix::io::OwnedFd,
    path::Path,
    rc::Rc,
    sync::Arc,
    time::Duration,
};

use anyhow::Result;
use tracing::{debug, error, info, warn};

use smithay::{
    backend::{
        input::InputEvent,
        libinput::{LibinputInputBackend, LibinputSessionInterface},
        session::{libseat::LibSeatSession, Session, Event as SessionEvent},
    },
    desktop::utils::surface_primary_scanout_output,
    output::{Mode, Output, PhysicalProperties, Subpixel},
    reexports::{
        calloop::{EventLoop, LoopHandle, timer::{Timer, TimeoutAction}, generic::Generic, Interest, PostAction},
        input::Libinput,
        wayland_server::Display,
    },
    utils::Transform,
    wayland::compositor,
};

use drm_hwcomposer_shim::{HwcDrmDevice, HwcGbmDevice};

use khronos_egl as egl;

use crate::state::Flick;
use crate::shell::ShellView;
use crate::input;

/// DRM Shim display state
pub struct ShimDisplay {
    pub drm_device: Arc<HwcDrmDevice>,
    #[allow(dead_code)]
    pub gbm_device: Arc<HwcGbmDevice>,
    pub egl_instance: egl::DynamicInstance<egl::EGL1_4>,
    pub egl_display: egl::Display,
    pub egl_surface: egl::Surface,
    pub egl_context: egl::Context,
    pub width: u32,
    pub height: u32,
}

impl Drop for ShimDisplay {
    fn drop(&mut self) {
        info!("ShimDisplay cleanup");

        // Make EGL context not current
        let _ = self.egl_instance.make_current(
            self.egl_display,
            None,
            None,
            None,
        );

        // Destroy EGL resources
        if let Err(e) = self.egl_instance.destroy_surface(self.egl_display, self.egl_surface) {
            warn!("Failed to destroy EGL surface: {:?}", e);
        }
        if let Err(e) = self.egl_instance.destroy_context(self.egl_display, self.egl_context) {
            warn!("Failed to destroy EGL context: {:?}", e);
        }
        if let Err(e) = self.egl_instance.terminate(self.egl_display) {
            warn!("Failed to terminate EGL display: {:?}", e);
        }

        info!("ShimDisplay cleanup complete");
    }
}

/// Initialize the DRM shim display
fn init_shim_display() -> Result<ShimDisplay> {
    info!("Initializing DRM shim display");

    // Create DRM device (initializes hwcomposer internally)
    let drm_device = Arc::new(HwcDrmDevice::new()?);

    let (width, height) = drm_device.get_dimensions();
    let refresh_rate = drm_device.get_refresh_rate();
    let (dpi_x, dpi_y) = drm_device.get_dpi();

    info!("Display: {}x{} @ {}Hz, DPI: {:.1}x{:.1}",
          width, height, refresh_rate, dpi_x, dpi_y);

    // Create GBM device for buffer allocation
    let gbm_device = Arc::new(HwcGbmDevice::new(drm_device.clone())?);

    // Initialize EGL
    info!("Initializing EGL");
    let egl_instance = unsafe { egl::DynamicInstance::<egl::EGL1_4>::load_required()? };

    // Initialize EGL on the DRM device (this sets up the native window)
    drm_device.init_egl()?;

    // Get the EGL display from the shim
    let egl_display_ptr = drm_device.egl_display()?;
    let egl_display = unsafe {
        egl::Display::from_ptr(egl_display_ptr as *mut _)
    };

    // Get EGL surface from shim
    let egl_surface_ptr = drm_device.egl_surface()?;
    let egl_surface = unsafe {
        egl::Surface::from_ptr(egl_surface_ptr as *mut _)
    };

    // Get EGL context from shim
    let egl_context_ptr = drm_device.egl_context()?;
    let egl_context = unsafe {
        egl::Context::from_ptr(egl_context_ptr as *mut _)
    };

    // Make context current
    egl_instance.make_current(
        egl_display,
        Some(egl_surface),
        Some(egl_surface),
        Some(egl_context),
    )?;

    info!("EGL initialized successfully");

    // Initialize OpenGL ES
    unsafe { gl::init(); }
    info!("OpenGL ES functions loaded");

    Ok(ShimDisplay {
        drm_device,
        gbm_device,
        egl_instance,
        egl_display,
        egl_surface,
        egl_context,
        width,
        height,
    })
}

/// Main entry point for the DRM shim backend
pub fn run() -> Result<()> {
    info!("Starting Flick with DRM shim backend");

    // Initialize the shim display
    let shim_display = init_shim_display()?;
    let width = shim_display.width;
    let height = shim_display.height;
    let shim_display = Rc::new(RefCell::new(shim_display));

    // Create Wayland display
    let wayland_display: Display<Flick> = Display::new()?;

    // Create event loop
    let mut event_loop: EventLoop<Flick> = EventLoop::try_new()?;
    let loop_handle = event_loop.handle();

    // Create output
    let output = Output::new(
        "SHIM-1".to_string(),
        PhysicalProperties {
            size: (62, 127).into(), // Approximate phone size in mm
            subpixel: Subpixel::Unknown,
            make: "DRM-Shim".to_string(),
            model: "HWComposer".to_string(),
            serial_number: "Unknown".to_string(),
        },
    );

    let mode = Mode {
        size: (width as i32, height as i32).into(),
        refresh: 60_000, // 60 Hz in mHz
    };

    output.change_current_state(
        Some(mode),
        Some(Transform::Normal),
        None,
        Some((0, 0).into()),
    );
    output.set_preferred(mode);

    // Create compositor state (takes ownership of wayland_display)
    let screen_size = smithay::utils::Size::from((width as i32, height as i32));
    let mut state = Flick::new(
        wayland_display,
        loop_handle.clone(),
        screen_size,
    );
    state.space.map_output(&output, (0, 0));

    // Initialize libinput for touch/input
    info!("Initializing libinput for touch input...");
    if let Err(e) = init_libinput(&loop_handle, &mut state, width, height) {
        warn!("Failed to initialize libinput: {:?}. Touch will not work.", e);
    } else {
        info!("libinput initialized successfully");
    }

    // Frame timer for rendering at 60fps
    let frame_timer = Timer::from_duration(Duration::from_millis(16));
    let shim_display_clone = shim_display.clone();
    let output_clone = output.clone();

    loop_handle.insert_source(frame_timer, move |_, _, state| {
        // Render frame
        render_frame(&shim_display_clone, state, &output_clone);

        // Schedule next frame
        TimeoutAction::ToDuration(Duration::from_millis(16))
    }).expect("Failed to insert frame timer");

    info!("DRM shim backend initialized, entering event loop");

    // Run the event loop
    loop {
        // Dispatch Wayland events
        state.dispatch_clients();

        // Run one iteration of the event loop
        if let Err(e) = event_loop.dispatch(Some(Duration::from_millis(1)), &mut state) {
            error!("Event loop error: {:?}", e);
        }
    }
}

/// Initialize libinput for touch/input handling
fn init_libinput(
    loop_handle: &LoopHandle<'static, Flick>,
    state: &mut Flick,
    screen_width: u32,
    screen_height: u32,
) -> Result<()> {
    // Create a minimal session interface for libinput
    // We don't need full session management for hwcomposer devices
    let mut libinput_context = Libinput::new_with_udev(NullSession);
    libinput_context.udev_assign_seat("seat0")
        .map_err(|_| anyhow::anyhow!("Failed to assign seat to libinput"))?;

    let libinput_backend = LibinputInputBackend::new(libinput_context.clone());

    // Store screen size for coordinate transformation
    state.screen_size = smithay::utils::Size::from((screen_width as i32, screen_height as i32));

    // Insert libinput source into event loop
    loop_handle.insert_source(libinput_backend, move |event, _, state| {
        handle_input_event(state, event);
    }).map_err(|e| anyhow::anyhow!("Failed to insert libinput source: {:?}", e))?;

    Ok(())
}

/// Null session for libinput (we manage device access ourselves on hwcomposer devices)
struct NullSession;

impl LibinputSessionInterface for NullSession {
    fn open(&mut self, path: &Path, _flags: i32) -> std::result::Result<OwnedFd, i32> {
        use std::os::unix::fs::OpenOptionsExt;
        use std::os::unix::io::IntoRawFd;

        std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .custom_flags(libc::O_NONBLOCK)
            .open(path)
            .map(|f| unsafe { OwnedFd::from_raw_fd(f.into_raw_fd()) })
            .map_err(|e| e.raw_os_error().unwrap_or(-1))
    }

    fn close(&mut self, _fd: OwnedFd) {
        // fd will be closed when dropped
    }
}

use std::os::unix::io::FromRawFd;

/// Handle input events from libinput
fn handle_input_event(state: &mut Flick, event: InputEvent<LibinputInputBackend>) {
    match event {
        InputEvent::DeviceAdded { device } => {
            info!("Input device added: {}", device.name());
        }
        InputEvent::DeviceRemoved { device } => {
            info!("Input device removed: {}", device.name());
        }
        InputEvent::TouchDown { event, .. } => {
            let slot = event.slot().map(|s| s.into()).unwrap_or(0);
            let pos = event.position_transformed(state.screen_size);
            debug!("Touch down: slot={}, pos=({:.1}, {:.1})", slot, pos.x, pos.y);
            input::handle_touch_down(state, slot, pos.x, pos.y);
        }
        InputEvent::TouchUp { event, .. } => {
            let slot = event.slot().map(|s| s.into()).unwrap_or(0);
            debug!("Touch up: slot={}", slot);
            input::handle_touch_up(state, slot);
        }
        InputEvent::TouchMotion { event, .. } => {
            let slot = event.slot().map(|s| s.into()).unwrap_or(0);
            let pos = event.position_transformed(state.screen_size);
            input::handle_touch_motion(state, slot, pos.x, pos.y);
        }
        InputEvent::TouchCancel { .. } => {
            debug!("Touch cancel");
            // Cancel all active touches
            state.gesture_recognizer.reset();
        }
        InputEvent::TouchFrame { .. } => {
            // Frame marker, usually no action needed
        }
        _ => {
            // Handle other events (keyboard, etc.) if needed
        }
    }
}

/// Frame counter for render_frame logging
static mut FRAME_COUNT: u64 = 0;

/// Render a frame
fn render_frame(
    display: &Rc<RefCell<ShimDisplay>>,
    state: &Flick,
    output: &Output,
) {
    let display = display.borrow();

    unsafe {
        FRAME_COUNT += 1;
    }
    let frame_num = unsafe { FRAME_COUNT };
    let log_frame = frame_num % 60 == 0; // Log every 60 frames

    // Set viewport
    unsafe {
        if let Some(f) = gl::FN_VIEWPORT {
            f(0, 0, display.width as i32, display.height as i32);
        }
    }

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
        info!("RENDER frame {}: view={:?}, lock_active={}, elements={}, qml_connected={}",
            frame_num, shell_view, state.shell.lock_screen_active, element_count, qml_lockscreen_connected);
    }

    // Render Slint UI for shell views (but not when QML lockscreen is connected)
    if !qml_lockscreen_connected {
        match shell_view {
            ShellView::Home | ShellView::QuickSettings | ShellView::Switcher | ShellView::PickDefault | ShellView::LockScreen => {
                // Update Slint timers and animations
                slint::platform::update_timers_and_animations();

                // Set up Slint UI state based on current view
                if let Some(ref slint_ui) = state.shell.slint_ui {
                    match shell_view {
                        ShellView::LockScreen => {
                            slint_ui.set_view("lock");
                            slint_ui.set_lock_time(&chrono::Local::now().format("%H:%M").to_string());
                            slint_ui.set_lock_date(&chrono::Local::now().format("%A, %B %e").to_string());
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
                            let windows: Vec<_> = state.space.elements()
                                .enumerate()
                                .map(|(i, window)| {
                                    let title = window.x11_surface()
                                        .map(|x11| {
                                            let t = x11.title();
                                            if !t.is_empty() { t } else { x11.class() }
                                        })
                                        .unwrap_or_else(|| format!("Window {}", i + 1));
                                    let app_class = window.x11_surface()
                                        .map(|x11| x11.class())
                                        .unwrap_or_else(|| "app".to_string());
                                    (i as i32, title, app_class)
                                })
                                .collect();
                            slint_ui.set_switcher_windows(windows);
                        }
                        ShellView::PickDefault => {
                            slint_ui.set_view("pick-default");
                        }
                        _ => {}
                    }
                }

                // Get Slint rendered pixels
                if let Some(ref slint_ui) = state.shell.slint_ui {
                    if let Some((tex_width, tex_height, pixels)) = slint_ui.render() {
                        if log_frame {
                            info!("SLINT RENDER frame {}: {}x{}", frame_num, tex_width, tex_height);
                        }
                        unsafe {
                            gl::render_texture(tex_width, tex_height, &pixels, display.width, display.height);
                        }
                    }
                }
            }
            _ => {}
        }
    }

    // Render Wayland windows for App view OR QML lockscreen
    if shell_view == ShellView::App || qml_lockscreen_connected {
        let windows: Vec<_> = state.space.elements().cloned().collect();
        debug!("Rendering {} Wayland windows", windows.len());

        for (i, window) in windows.iter().enumerate() {
            if let Some(toplevel) = window.toplevel() {
                let wl_surface = toplevel.wl_surface();

                // Get stored buffer from surface user data
                let buffer_info: Option<(u32, u32, Vec<u8>)> = compositor::with_states(wl_surface, |data| {
                    use std::cell::RefCell;
                    use crate::state::SurfaceBufferData;

                    if let Some(buffer_data) = data.data_map.get::<RefCell<SurfaceBufferData>>() {
                        let data = buffer_data.borrow();
                        if let Some(ref stored) = data.buffer {
                            Some((stored.width, stored.height, stored.pixels.clone()))
                        } else {
                            None
                        }
                    } else {
                        None
                    }
                });

                if let Some((tex_width, tex_height, pixels)) = buffer_info {
                    if log_frame {
                        info!("Window {} RENDER: {}x{}", i, tex_width, tex_height);
                    }
                    unsafe {
                        gl::render_texture(tex_width, tex_height, &pixels, display.width, display.height);
                    }
                }
            }
        }
    }

    // Swap buffers
    if let Err(e) = display.drm_device.swap_buffers() {
        error!("Failed to swap buffers: {}", e);
    }
}

// OpenGL ES bindings
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
    type GetErrorFn = unsafe extern "C" fn() -> u32;
    type FlushFn = unsafe extern "C" fn();

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
    static mut FN_GET_ERROR: Option<GetErrorFn> = None;
    static mut FN_FLUSH: Option<FlushFn> = None;

    static mut INITIALIZED: bool = false;
    static mut SHADER_PROGRAM: u32 = 0;
    static mut ATTR_POSITION: i32 = -1;
    static mut ATTR_TEXCOORD: i32 = -1;
    static mut UNIFORM_TEXTURE: i32 = -1;

    const VERTEX_SHADER_SRC: &str = r#"
        attribute vec2 a_position;
        attribute vec2 a_texcoord;
        varying vec2 v_texcoord;
        void main() {
            gl_Position = vec4(a_position, 0.0, 1.0);
            v_texcoord = a_texcoord;
        }
    "#;

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
        FN_GET_ERROR = load_fn(lib, b"glGetError\0");
        FN_FLUSH = load_fn(lib, b"glFlush\0");

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

    pub unsafe fn render_texture(tex_width: u32, tex_height: u32, pixels: &[u8], screen_width: u32, screen_height: u32) {
        if SHADER_PROGRAM == 0 || ATTR_POSITION < 0 || ATTR_TEXCOORD < 0 {
            return;
        }

        while GetError() != 0 {}

        if let Some(f) = FN_VIEWPORT {
            f(0, 0, screen_width as i32, screen_height as i32);
        }

        let mut texture: u32 = 0;
        if let Some(f) = FN_GEN_TEXTURES { f(1, &mut texture); }
        if let Some(f) = FN_BIND_TEXTURE { f(TEXTURE_2D, texture); }

        if let Some(f) = FN_TEX_PARAMETERI {
            f(TEXTURE_2D, TEXTURE_MIN_FILTER, LINEAR);
            f(TEXTURE_2D, TEXTURE_MAG_FILTER, LINEAR);
        }

        let expected_size = (tex_width * tex_height * 4) as usize;
        if pixels.len() != expected_size {
            return;
        }

        if let Some(f) = FN_TEX_IMAGE_2D {
            f(TEXTURE_2D, 0, RGBA as i32, tex_width as i32, tex_height as i32,
              0, RGBA, UNSIGNED_BYTE, pixels.as_ptr() as *const c_void);
        }

        if let Some(f) = FN_USE_PROGRAM { f(SHADER_PROGRAM); }
        if let Some(f) = FN_ACTIVE_TEXTURE { f(0x84C0); }
        if let Some(f) = FN_BIND_TEXTURE { f(TEXTURE_2D, texture); }
        if let Some(f) = FN_UNIFORM1I { f(UNIFORM_TEXTURE, 0); }

        #[rustfmt::skip]
        let vertices: [f32; 16] = [
            -1.0, -1.0,  0.0, 1.0,
             1.0, -1.0,  1.0, 1.0,
            -1.0,  1.0,  0.0, 0.0,
             1.0,  1.0,  1.0, 0.0,
        ];

        if let Some(f) = FN_ENABLE_VERTEX_ATTRIB_ARRAY {
            f(ATTR_POSITION as u32);
            f(ATTR_TEXCOORD as u32);
        }

        if let Some(f) = FN_VERTEX_ATTRIB_POINTER {
            let stride = 4 * std::mem::size_of::<f32>() as i32;
            f(ATTR_POSITION as u32, 2, FLOAT, FALSE, stride, vertices.as_ptr() as *const c_void);
            f(ATTR_TEXCOORD as u32, 2, FLOAT, FALSE, stride,
              (vertices.as_ptr() as *const f32).add(2) as *const c_void);
        }

        if let Some(f) = FN_ENABLE { f(BLEND); }
        if let Some(f) = FN_BLEND_FUNC { f(SRC_ALPHA, ONE_MINUS_SRC_ALPHA); }

        if let Some(f) = FN_DRAW_ARRAYS {
            f(TRIANGLE_STRIP, 0, 4);
        }

        Flush();

        if let Some(f) = FN_DISABLE { f(BLEND); }
        if let Some(f) = FN_DELETE_TEXTURES { f(1, &texture); }
    }
}
