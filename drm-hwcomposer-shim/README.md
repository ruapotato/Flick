# drm-hwcomposer-shim

A DRM/KMS shim layer over Android's hwcomposer HAL for Linux phones.

## Overview

This library provides a DRM/KMS-compatible interface that internally uses Android's hwcomposer (via libhybris) for display output. This allows **any standard Wayland compositor** to run on Android-based Linux phones (Droidian, postmarketOS with libhybris, etc.).

## Why?

Android phones use proprietary GPU drivers that only work with Android's HAL (Hardware Abstraction Layer). Running Linux on these devices requires either:

1. **Reverse-engineering** the GPU driver (hard, device-specific)
2. **Using libhybris** to run Android userspace alongside Linux

Option 2 is what Droidian and similar projects do. However, libhybris requires applications to use Android's EGL/GLES implementation, which is incompatible with standard Linux DRM/KMS.

This shim bridges the gap by:
- Exposing a DRM-like interface to compositors
- Translating DRM/KMS calls to hwcomposer internally
- Providing GBM buffer allocation via Android's gralloc
- Enabling EGL buffer sharing between Android and Linux

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Wayland Compositor (any)                       │
│         (Flick, Phosh, Plasma Mobile, Sway, etc.)          │
└─────────────────────────────────────────────────────────────┘
                             │
                   Standard DRM/KMS/GBM APIs
                             │
┌─────────────────────────────────────────────────────────────┐
│              drm-hwcomposer-shim                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ DRM Device  │  │ GBM Device  │  │ EGL Integration     │ │
│  │ (KMS ioctl) │  │ (gralloc)   │  │ (buffer sharing)    │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                             │
                       libhybris
                             │
┌─────────────────────────────────────────────────────────────┐
│              Android HAL (hwcomposer, gralloc)              │
└─────────────────────────────────────────────────────────────┘
                             │
┌─────────────────────────────────────────────────────────────┐
│              GPU Driver (Adreno, Mali, PowerVR, etc.)       │
└─────────────────────────────────────────────────────────────┘
```

## Status

✅ **Display Output Working!** ✅

The shim can now render to the display via hwcomposer. Color cycling test shows RED→GREEN→BLUE→YELLOW→MAGENTA→CYAN.

### Completed
- [x] Basic library structure
- [x] hwcomposer HAL interface (hwc2_compat_layer)
- [x] HWCNativeWindow integration
- [x] DRM device with connector/CRTC/plane abstractions
- [x] GBM device with real gralloc buffer allocation
- [x] EGL integration (context, surface, swap buffers)
- [x] Real FFI bindings to libhybris
- [x] gralloc_initialize() / hwc2_initialize() calls
- [x] Display power management (unblank, power on)
- [x] Buffer map/unmap for CPU access
- [x] Framebuffer management
- [x] Plane state tracking

### In Progress
- [ ] C API for libdrm/libgbm drop-in replacement
- [ ] DMA-BUF export/import for buffer sharing

### Planned
- [ ] Testing with Weston/Sway
- [ ] Smithay backend integration
- [ ] Atomic modesetting

## Building

**Must be built on a Droidian/libhybris device** (requires libhybris libraries).

```bash
# On the phone (via SSH)
ssh droidian@<phone-ip>
cd ~/Flick/drm-hwcomposer-shim

# Source cargo environment
source ~/.cargo/env

# Build the library and test binary
cargo build --release

# Run the test
./target/release/test_hwc
```

### Dependencies (on target device)

- Rust 1.70+ (install via rustup)
- libhybris (`libhybris-common`, `libhybris-hwcomposerwindow`)
- hwc2_compat_layer (`libhwc2_compat_layer`)
- EGL libraries from Android HAL

On Droidian, these should be pre-installed. If not:
```bash
sudo apt install libhybris-common libhybris-dev
```

## FFI Bindings

The shim uses the following libhybris APIs:

### hwc2_compat_layer.h
```c
// Device management
hwc2_compat_device_t* hwc2_compat_device_new(bool use_vr);
hwc2_compat_display_t* hwc2_compat_device_get_display_by_id(device, id);
HWC2DisplayConfig* hwc2_compat_display_get_active_config(display);

// Display operations
hwc2_compat_display_set_power_mode(display, mode);
hwc2_compat_display_set_vsync_enabled(display, enabled);
hwc2_compat_display_present(display, &fence);

// Layer management
hwc2_compat_layer_t* hwc2_compat_display_create_layer(display);
hwc2_compat_layer_set_composition_type(layer, type);
hwc2_compat_layer_set_display_frame(layer, l, t, r, b);
```

### HWCNativeWindow (libhybris-hwcomposerwindow)
```c
// Create window for EGL
ANativeWindow* HWCNativeWindowCreate(width, height, format, present_cb, data);
void HWCNativeWindowDestroy(window);

// Buffer fence management
int HWCNativeBufferGetFence(buffer);
void HWCNativeBufferSetFence(buffer, fd);
```

## Usage

### As a Library (for compositors to integrate directly)

```rust
use drm_hwcomposer_shim::HwcDrmDevice;
use std::sync::Arc;

// Create DRM device (initializes hwcomposer)
let drm = HwcDrmDevice::new()?;

// Get display info
let (width, height) = drm.get_dimensions();
let refresh_rate = drm.get_refresh_rate();
println!("Display: {}x{} @ {}Hz", width, height, refresh_rate);

// Initialize EGL for rendering
drm.init_egl()?;

// Render loop
loop {
    // ... render with OpenGL ES ...
    drm.swap_buffers()?;
}
```

### Test Scripts

```bash
# On the phone - use the test script (handles hwcomposer restart)
cd ~/Flick/drm-hwcomposer-shim
./test_shim.sh
```

The test script will:
1. Stop phosh
2. Restart hwcomposer service properly
3. Run the color cycling test

**You should see colors cycling on the display: RED → GREEN → BLUE → YELLOW → MAGENTA → CYAN**

### Test Binaries

```bash
# Color cycling display test
./target/release/test_hwc

# GBM/gralloc buffer allocation test
./target/release/test_gbm
```

Expected output for test_hwc:
```
=== DRM-HWComposer Shim Test ===
Display initialized successfully!
  Resolution: 1080x2220
  Refresh rate: 60 Hz
  DPI: 442.5x444.0

EGL initialized!
OpenGL ES functions loaded

Rendering colored frames...
Frame 0: Showing RED
Frame 30: Showing GREEN
Frame 60: Showing BLUE
...
Test complete!
```

## Troubleshooting

### "Failed to create HWC2 device"
- Ensure libhybris is properly installed
- Check that Android HAL is accessible (`/vendor/lib64/hw/`)
- Verify hybris environment: `EGL_PLATFORM=hwcomposer`

### "Failed to get EGL display"
- Try setting: `export EGL_PLATFORM=hwcomposer`
- Check libEGL is the hybris version

### Linker errors
- Ensure these libraries are available:
  - `libhybris-hwcomposerwindow.so`
  - `libhwc2_compat_layer.so`
  - `libEGL.so` (from hybris)

## Related Projects

- [libhybris](https://github.com/libhybris/libhybris) - Android compatibility layer for Linux
- [Droidian](https://droidian.org/) - Debian-based Linux for Android phones
- [drm_hwcomposer](https://gitlab.freedesktop.org/nicco/drm_hwcomposer) - Android's DRM HAL using Linux DRM (opposite direction)

## License

GPL-3.0
