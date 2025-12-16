//! Test binary for the C API
//!
//! This tests the libgbm/libdrm-compatible C API to ensure
//! applications can use it as a drop-in replacement.

use drm_hwcomposer_shim::c_api::*;
use std::ptr;

fn main() {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::DEBUG)
        .init();

    println!("=== C API Compatibility Test ===\n");

    // Test 1: Initialize the shim
    println!("--- Test 1: Initialize shim ---");
    unsafe {
        let ret = drm_hwcomposer_shim_init();
        if ret != 0 {
            println!("  FAILED: drm_hwcomposer_shim_init returned {}", ret);
            return;
        }
        println!("  OK: Shim initialized");
    }

    // Test 2: GBM device creation
    println!("\n--- Test 2: GBM device creation ---");
    let gbm_dev = unsafe { gbm_create_device(-1) };
    if gbm_dev.is_null() {
        println!("  FAILED: gbm_create_device returned NULL");
        return;
    }
    println!("  OK: GBM device created");

    // Test 3: Check format support
    println!("\n--- Test 3: Format support ---");
    unsafe {
        let supported = gbm_device_is_format_supported(gbm_dev, GBM_FORMAT_ARGB8888, GBM_BO_USE_RENDERING);
        println!("  ARGB8888 + RENDERING: {}", if supported != 0 { "supported" } else { "not supported" });

        let supported = gbm_device_is_format_supported(gbm_dev, GBM_FORMAT_XRGB8888, GBM_BO_USE_SCANOUT);
        println!("  XRGB8888 + SCANOUT: {}", if supported != 0 { "supported" } else { "not supported" });
    }

    // Test 4: Buffer object creation
    println!("\n--- Test 4: Buffer object creation ---");
    let bo = unsafe {
        gbm_bo_create(
            gbm_dev,
            256,
            256,
            GBM_FORMAT_ARGB8888,
            GBM_BO_USE_RENDERING | GBM_BO_USE_SCANOUT,
        )
    };
    if bo.is_null() {
        println!("  FAILED: gbm_bo_create returned NULL");
    } else {
        unsafe {
            println!("  OK: Buffer created");
            println!("    Width: {}", gbm_bo_get_width(bo));
            println!("    Height: {}", gbm_bo_get_height(bo));
            println!("    Stride: {}", gbm_bo_get_stride(bo));
            println!("    Format: 0x{:08x}", gbm_bo_get_format(bo));
            println!("    BPP: {}", gbm_bo_get_bpp(bo));
            println!("    Planes: {}", gbm_bo_get_plane_count(bo));

            // Test map/unmap
            let mut stride: u32 = 0;
            let mut map_data: *mut std::ffi::c_void = ptr::null_mut();
            let ptr = gbm_bo_map(bo, 0, 0, 256, 256, GBM_BO_TRANSFER_WRITE, &mut stride, &mut map_data);
            if ptr.is_null() {
                println!("    Map: FAILED");
            } else {
                println!("    Map: OK (stride={})", stride);
                // Write a test pixel
                let data = ptr as *mut u32;
                *data = 0xFFFF0000; // Red
                gbm_bo_unmap(bo, map_data);
                println!("    Unmap: OK");
            }

            // Test DMA-BUF export
            println!("  Testing DMA-BUF export...");
            let dmabuf_fd = gbm_bo_get_fd(bo);
            if dmabuf_fd >= 0 {
                println!("    DMA-BUF fd: {} (success!)", dmabuf_fd);
                // Close the duplicated fd
                libc::close(dmabuf_fd);
                println!("    Closed fd: OK");
            } else {
                println!("    DMA-BUF fd: not available (this is OK for some drivers)");
            }

            gbm_bo_destroy(bo);
            println!("  Buffer destroyed");
        }
    }

    // Test 5: Surface creation
    println!("\n--- Test 5: Surface creation ---");
    let surface = unsafe {
        gbm_surface_create(
            gbm_dev,
            640,
            480,
            GBM_FORMAT_XRGB8888,
            GBM_BO_USE_RENDERING | GBM_BO_USE_SCANOUT,
        )
    };
    if surface.is_null() {
        println!("  FAILED: gbm_surface_create returned NULL");
    } else {
        unsafe {
            println!("  OK: Surface created");

            let has_free = gbm_surface_has_free_buffers(surface);
            println!("    Has free buffers: {}", if has_free != 0 { "yes" } else { "no" });

            // Lock front buffer
            let front_bo = gbm_surface_lock_front_buffer(surface);
            if !front_bo.is_null() {
                println!("    Locked front buffer: OK");
                gbm_surface_release_buffer(surface, front_bo);
                println!("    Released buffer: OK");
            }

            gbm_surface_destroy(surface);
            println!("  Surface destroyed");
        }
    }

    // Test 6: DRM resources
    println!("\n--- Test 6: DRM resources ---");
    unsafe {
        let resources = drmModeGetResources(-1);
        if resources.is_null() {
            println!("  FAILED: drmModeGetResources returned NULL");
        } else {
            println!("  OK: Got DRM resources");
            println!("    CRTCs: {}", (*resources).count_crtcs);
            println!("    Connectors: {}", (*resources).count_connectors);
            println!("    Encoders: {}", (*resources).count_encoders);
            println!("    Min size: {}x{}", (*resources).min_width, (*resources).min_height);
            println!("    Max size: {}x{}", (*resources).max_width, (*resources).max_height);
            drmModeFreeResources(resources);
            println!("  Resources freed");
        }
    }

    // Test 7: DRM connector
    println!("\n--- Test 7: DRM connector ---");
    unsafe {
        let connector = drmModeGetConnector(-1, 1);
        if connector.is_null() {
            println!("  FAILED: drmModeGetConnector returned NULL");
        } else {
            println!("  OK: Got connector");
            println!("    ID: {}", (*connector).connector_id);
            println!("    Type: {}", (*connector).connector_type);
            println!("    Connection: {}", match (*connector).connection {
                DRM_MODE_CONNECTED => "connected",
                DRM_MODE_DISCONNECTED => "disconnected",
                _ => "unknown",
            });
            println!("    Size: {}x{} mm", (*connector).mmWidth, (*connector).mmHeight);
            println!("    Modes: {}", (*connector).count_modes);

            if (*connector).count_modes > 0 && !(*connector).modes.is_null() {
                let mode = &*(*connector).modes;
                println!("    Mode[0]: {}x{} @ {}Hz",
                    mode.hdisplay, mode.vdisplay, mode.vrefresh);
            }

            drmModeFreeConnector(connector);
            println!("  Connector freed");
        }
    }

    // Test 8: DRM CRTC
    println!("\n--- Test 8: DRM CRTC ---");
    unsafe {
        let crtc = drmModeGetCrtc(-1, 10);
        if crtc.is_null() {
            println!("  FAILED: drmModeGetCrtc returned NULL");
        } else {
            println!("  OK: Got CRTC");
            println!("    ID: {}", (*crtc).crtc_id);
            println!("    Position: ({}, {})", (*crtc).x, (*crtc).y);
            println!("    Size: {}x{}", (*crtc).width, (*crtc).height);
            println!("    Mode valid: {}", (*crtc).mode_valid);
            drmModeFreeCrtc(crtc);
            println!("  CRTC freed");
        }
    }

    // Test 9: DRM planes
    println!("\n--- Test 9: DRM planes ---");
    unsafe {
        let plane_res = drmModeGetPlaneResources(-1);
        if plane_res.is_null() {
            println!("  FAILED: drmModeGetPlaneResources returned NULL");
        } else {
            println!("  OK: Got plane resources");
            println!("    Planes: {}", (*plane_res).count_planes);

            for i in 0..(*plane_res).count_planes {
                let plane_id = *(*plane_res).planes.add(i as usize);
                let plane = drmModeGetPlane(-1, plane_id);
                if !plane.is_null() {
                    println!("    Plane {}: formats={}, possible_crtcs=0x{:x}",
                        (*plane).plane_id, (*plane).count_formats, (*plane).possible_crtcs);
                    drmModeFreePlane(plane);
                }
            }

            drmModeFreePlaneResources(plane_res);
            println!("  Plane resources freed");
        }
    }

    // Test 10: DRM framebuffer
    println!("\n--- Test 10: DRM framebuffer ---");
    unsafe {
        let mut fb_id: u32 = 0;
        let ret = drmModeAddFB(-1, 1080, 1920, 24, 32, 1080 * 4, 0, &mut fb_id);
        if ret != 0 {
            println!("  FAILED: drmModeAddFB returned {}", ret);
        } else {
            println!("  OK: Created framebuffer {}", fb_id);

            let fb = drmModeGetFB(-1, fb_id);
            if !fb.is_null() {
                println!("    Size: {}x{}", (*fb).width, (*fb).height);
                println!("    Pitch: {}", (*fb).pitch);
                println!("    BPP: {}", (*fb).bpp);
                drmModeFreeFB(fb);
            }

            let ret = drmModeRmFB(-1, fb_id);
            println!("  Removed framebuffer: {}", if ret == 0 { "OK" } else { "FAILED" });
        }
    }

    // Test 11: DRM version
    println!("\n--- Test 11: DRM version ---");
    unsafe {
        let version = drmGetVersion(-1);
        if version.is_null() {
            println!("  FAILED: drmGetVersion returned NULL");
        } else {
            println!("  OK: Got version");
            println!("    Version: {}.{}.{}",
                (*version).version_major,
                (*version).version_minor,
                (*version).version_patchlevel);

            if !(*version).name.is_null() {
                let name = std::ffi::CStr::from_ptr((*version).name);
                println!("    Name: {}", name.to_string_lossy());
            }

            drmFreeVersion(version);
            println!("  Version freed");
        }
    }

    // Cleanup
    println!("\n--- Cleanup ---");
    unsafe {
        gbm_device_destroy(gbm_dev);
        println!("  GBM device destroyed");
    }

    println!("\n=== All tests complete! ===");
}
