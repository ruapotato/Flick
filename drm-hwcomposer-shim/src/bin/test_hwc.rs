//! Simple test binary for the hwcomposer shim
//! Renders alternating colors to prove the display is working

use drm_hwcomposer_shim::HwcDrmDevice;
use std::ffi::c_void;
use std::thread;
use std::time::Duration;

// OpenGL ES constants
const GL_COLOR_BUFFER_BIT: u32 = 0x00004000;

// Function pointer types
type GlClearColorFn = unsafe extern "C" fn(f32, f32, f32, f32);
type GlClearFn = unsafe extern "C" fn(u32);
type GlViewportFn = unsafe extern "C" fn(i32, i32, i32, i32);

// Dynamically loaded GL functions
static mut FN_CLEAR_COLOR: Option<GlClearColorFn> = None;
static mut FN_CLEAR: Option<GlClearFn> = None;
static mut FN_VIEWPORT: Option<GlViewportFn> = None;

unsafe fn load_gl_functions() -> bool {
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
        println!("Failed to load libGLESv2");
        return false;
    }

    // Load GL functions
    let clear_color = libc::dlsym(lib, b"glClearColor\0".as_ptr() as *const _);
    let clear = libc::dlsym(lib, b"glClear\0".as_ptr() as *const _);
    let viewport = libc::dlsym(lib, b"glViewport\0".as_ptr() as *const _);

    if clear_color.is_null() || clear.is_null() {
        println!("Failed to load GL functions");
        return false;
    }

    FN_CLEAR_COLOR = Some(std::mem::transmute(clear_color));
    FN_CLEAR = Some(std::mem::transmute(clear));
    if !viewport.is_null() {
        FN_VIEWPORT = Some(std::mem::transmute(viewport));
    }

    println!("OpenGL ES functions loaded");
    true
}

unsafe fn gl_clear_color(r: f32, g: f32, b: f32, a: f32) {
    if let Some(f) = FN_CLEAR_COLOR {
        f(r, g, b, a);
    }
}

unsafe fn gl_clear(mask: u32) {
    if let Some(f) = FN_CLEAR {
        f(mask);
    }
}

unsafe fn gl_viewport(x: i32, y: i32, w: i32, h: i32) {
    if let Some(f) = FN_VIEWPORT {
        f(x, y, w, h);
    }
}

fn main() {
    // Initialize tracing (use try_init in case LD_PRELOAD already set it up)
    let _ = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::DEBUG)
        .try_init();

    println!("=== DRM-HWComposer Shim Test ===");
    println!("Creating HwcDrmDevice...");

    match HwcDrmDevice::new() {
        Ok(device) => {
            let (width, height) = device.get_dimensions();
            let refresh = device.get_refresh_rate();
            let (dpi_x, dpi_y) = device.get_dpi();

            println!("Display initialized successfully!");
            println!("  Resolution: {}x{}", width, height);
            println!("  Refresh rate: {} Hz", refresh);
            println!("  DPI: {:.1}x{:.1}", dpi_x, dpi_y);

            let mode = device.get_mode_info();
            println!("  Mode: {}", mode.name);

            let connector = device.get_connector();
            println!(
                "  Physical size: {}mm x {}mm",
                connector.width_mm, connector.height_mm
            );

            // Initialize EGL
            println!("\nInitializing EGL...");
            if let Err(e) = device.init_egl() {
                println!("Failed to initialize EGL: {}", e);
                return;
            }
            println!("EGL initialized!");

            // Load OpenGL ES functions
            println!("\nLoading OpenGL ES functions...");
            unsafe {
                if !load_gl_functions() {
                    println!("Failed to load GL functions");
                    return;
                }
            }

            // Set viewport
            unsafe {
                gl_viewport(0, 0, width as i32, height as i32);
            }

            // Render frames with alternating colors
            println!("\nRendering colored frames...");
            println!("You should see RED -> GREEN -> BLUE cycling");

            let colors = [
                (1.0, 0.0, 0.0, 1.0), // Red
                (0.0, 1.0, 0.0, 1.0), // Green
                (0.0, 0.0, 1.0, 1.0), // Blue
                (1.0, 1.0, 0.0, 1.0), // Yellow
                (1.0, 0.0, 1.0, 1.0), // Magenta
                (0.0, 1.0, 1.0, 1.0), // Cyan
            ];

            for i in 0..180 {
                // Pick color based on frame (change every 30 frames = 0.5 sec)
                let color_idx = (i / 30) % colors.len();
                let (r, g, b, a) = colors[color_idx];

                // Clear to the selected color
                unsafe {
                    gl_clear_color(r, g, b, a);
                    gl_clear(GL_COLOR_BUFFER_BIT);
                }

                // Swap buffers
                if let Err(e) = device.swap_buffers() {
                    println!("Frame {} failed: {}", i, e);
                    break;
                }

                if i % 30 == 0 {
                    let color_names = ["RED", "GREEN", "BLUE", "YELLOW", "MAGENTA", "CYAN"];
                    println!("Frame {}: Showing {}", i, color_names[color_idx]);
                }

                // Wait roughly for vsync (16ms = 60fps)
                thread::sleep(Duration::from_millis(16));
            }

            println!("\nTest complete! Did you see colors cycling on the display?");

            // Give time to see the result before cleanup
            thread::sleep(Duration::from_secs(1));
        }
        Err(e) => {
            println!("Failed to create HwcDrmDevice: {}", e);
        }
    }
}
