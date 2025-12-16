//! Test binary for GBM/gralloc buffer allocation
//!
//! This tests that we can allocate buffers via gralloc and use them.

use drm_hwcomposer_shim::drm_device::HwcDrmDevice;
use drm_hwcomposer_shim::gbm_device::{GbmFormat, HwcGbmDevice, gbm_usage};
use std::sync::Arc;

fn main() {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::DEBUG)
        .init();

    println!("=== GBM/Gralloc Buffer Allocation Test ===\n");

    // Create DRM device (initializes hwcomposer and gralloc)
    println!("Creating DRM device...");
    let drm_device = match HwcDrmDevice::new() {
        Ok(d) => {
            println!("  DRM device created successfully");
            Arc::new(d)
        }
        Err(e) => {
            println!("Failed to create DRM device: {}", e);
            return;
        }
    };

    // Create GBM device
    println!("\nCreating GBM device...");
    let gbm_device = match HwcGbmDevice::new(drm_device.clone()) {
        Ok(d) => {
            println!("  GBM device created successfully");
            Arc::new(d)
        }
        Err(e) => {
            println!("Failed to create GBM device: {}", e);
            return;
        }
    };

    // Test 1: Allocate a simple buffer
    println!("\n--- Test 1: Allocate 256x256 ARGB buffer ---");
    let usage = gbm_usage::GBM_BO_USE_RENDERING | gbm_usage::GBM_BO_USE_SCANOUT;
    match gbm_device.create_bo(256, 256, GbmFormat::Argb8888, usage) {
        Ok(bo) => {
            println!("  Allocated buffer:");
            println!("    Size: {}x{}", bo.width(), bo.height());
            println!("    Stride: {} bytes", bo.stride());
            println!("    Format: {:?}", bo.format());
            println!("    Handle: {:p}", bo.handle());

            // Try to map and write to the buffer
            println!("  Testing map/unmap...");
            match bo.map() {
                Ok(ptr) => {
                    println!("    Mapped at: {:p}", ptr);
                    // Write a test pattern (red pixels)
                    let data = ptr as *mut u32;
                    for i in 0..100 {
                        unsafe { *data.add(i) = 0xFFFF0000; } // ARGB red
                    }
                    println!("    Wrote test pattern");
                    if let Err(e) = bo.unmap() {
                        println!("    Unmap failed: {}", e);
                    } else {
                        println!("    Unmapped successfully");
                    }
                }
                Err(e) => println!("    Map failed: {}", e),
            }
        }
        Err(e) => {
            println!("  Failed to allocate buffer: {}", e);
        }
    }

    // Test 2: Allocate a fullscreen buffer
    let (width, height) = drm_device.get_dimensions();
    println!("\n--- Test 2: Allocate fullscreen {}x{} buffer ---", width, height);
    match gbm_device.create_bo(width, height, GbmFormat::Xrgb8888, usage) {
        Ok(bo) => {
            println!("  Allocated fullscreen buffer:");
            println!("    Size: {}x{}", bo.width(), bo.height());
            println!("    Stride: {} bytes", bo.stride());
            println!("    Expected stride: {} bytes", width * 4);
        }
        Err(e) => {
            println!("  Failed to allocate fullscreen buffer: {}", e);
        }
    }

    // Test 3: Create a GBM surface (triple buffered)
    println!("\n--- Test 3: Create GBM surface with triple buffering ---");
    match gbm_device.create_surface(640, 480, GbmFormat::Argb8888, usage) {
        Ok(mut surface) => {
            println!("  Created surface:");
            let (w, h) = surface.dimensions();
            println!("    Size: {}x{}", w, h);
            println!("    Format: {:?}", surface.format());

            // Lock a few buffers
            for i in 0..5 {
                match surface.lock_front_buffer() {
                    Ok(bo) => {
                        println!("    Buffer {}: {}x{} stride={}",
                            i, bo.width(), bo.height(), bo.stride());
                    }
                    Err(e) => {
                        println!("    Failed to lock buffer {}: {}", i, e);
                    }
                }
            }
        }
        Err(e) => {
            println!("  Failed to create surface: {}", e);
        }
    }

    println!("\n=== Test complete! ===");
}
