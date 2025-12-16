//! Simple test binary for the hwcomposer shim

use drm_hwcomposer_shim::HwcDrmDevice;
use std::thread;
use std::time::Duration;

fn main() {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::DEBUG)
        .init();

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

            // Render a few frames
            println!("\nRendering frames...");
            for i in 0..60 {
                // In a real app, you'd render something here with OpenGL ES
                // For now, just swap buffers
                if let Err(e) = device.swap_buffers() {
                    println!("Frame {} failed: {}", i, e);
                } else if i % 10 == 0 {
                    println!("Frame {} presented", i);
                }

                // Wait for vsync (approximately)
                thread::sleep(Duration::from_millis(16));
            }

            println!("\nTest complete!");
        }
        Err(e) => {
            println!("Failed to create HwcDrmDevice: {}", e);
        }
    }
}
