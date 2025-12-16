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

🚧 **Work in Progress** 🚧

- [x] Basic library structure
- [x] hwcomposer HAL interface
- [x] DRM device abstraction
- [x] GBM device abstraction
- [x] EGL integration framework
- [ ] Full DRM ioctl implementation
- [ ] gralloc buffer allocation
- [ ] DMA-BUF sharing
- [ ] vsync handling
- [ ] Atomic modesetting support
- [ ] Testing with real compositors

## Building

```bash
cd drm-hwcomposer-shim
cargo build --release
```

### Dependencies

- Rust 1.70+
- libhybris (on target device)
- Android HAL libraries (hwcomposer, gralloc)

## Usage

### As a Library (for compositors to integrate directly)

```rust
use drm_hwcomposer_shim::{HwcDrmDevice, HwcGbmDevice};
use std::sync::Arc;

// Create DRM device
let drm = Arc::new(HwcDrmDevice::new()?);

// Create GBM device from DRM
let gbm = Arc::new(HwcGbmDevice::new(drm.clone())?);

// Use gbm for buffer allocation, drm for modesetting
// Pass to your compositor's backend...
```

### As a System Service (planned)

In the future, this could run as a daemon that creates a virtual DRM device at `/dev/dri/card0`, allowing unmodified compositors to use it.

## Related Projects

- [libhybris](https://github.com/libhybris/libhybris) - Android compatibility layer for Linux
- [Droidian](https://droidian.org/) - Debian-based Linux for Android phones
- [drm_hwcomposer](https://gitlab.freedesktop.org/nicco/drm_hwcomposer) - Android's DRM HAL using Linux DRM (opposite direction)

## License

GPL-3.0
