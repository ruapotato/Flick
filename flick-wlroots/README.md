# Flick - Mobile Linux Compositor

A wlroots-based Wayland compositor designed for mobile Linux devices, specifically targeting Droidian/Mobian on Android phones.

## Platform Support

### Desktop Linux (x86_64)
- Uses standard wlroots 0.18
- DRM/KMS backend for native display
- Wayland backend for nested testing

### Droidian/Mobile (aarch64)
- **REQUIRES Droidian's wlroots fork** with hwcomposer backend
- Uses Android hwcomposer HAL for display (not DRM)
- Package: `libwlroots-dev` from Droidian repos

## Building

### Desktop (standard wlroots 0.18)
```bash
cd flick-wlroots
make
```

### Droidian Phone (wlroots 0.17 + hwcomposer)
```bash
# On the phone:
cd ~/Flick/flick-wlroots
make
```

The Makefile auto-detects:
- `wlroots-0.18` package (desktop)
- `wlroots` package (Droidian, includes hwcomposer)

### Dependencies

**Desktop:**
- wlroots 0.18
- wayland-server, wayland-protocols
- xkbcommon
- pixman

**Droidian:**
- libwlroots-dev (Droidian's patched version with hwcomposer)
- libwayland-dev
- libxkbcommon-dev
- libpixman-1-dev

## Running

### Desktop Testing
```bash
./start.sh                    # Run with auto-detected backend
./start.sh --timeout 30       # Auto-exit after 30 seconds
./start.sh -v                 # Verbose logging
WLR_BACKENDS=wayland ./start.sh  # Force nested Wayland
```

### Phone (Droidian)
```bash
# From repo root:
./start_hwcomposer.sh --timeout 30

# This script:
# 1. Stops phosh
# 2. Resets hwcomposer
# 3. Runs flick with WLR_BACKENDS=hwcomposer
# 4. Restarts phosh on exit
```

**IMPORTANT:** On Droidian, you MUST use `WLR_BACKENDS=hwcomposer`:
```bash
export WLR_BACKENDS=hwcomposer
export EGL_PLATFORM=hwcomposer
sudo -E ./build/flick -v
```

Without this, wlroots will try DRM which fails on Android devices.

## wlroots Version Compatibility

The code handles API differences between versions:

| Feature | wlroots 0.17 (Droidian) | wlroots 0.18 (Desktop) |
|---------|------------------------|------------------------|
| Package name | `wlroots` | `wlroots-0.18` |
| Backend create | `wlr_backend_autocreate(wl_display, ...)` | `wlr_backend_autocreate(wl_event_loop, ...)` |
| Tablet enum | `WLR_INPUT_DEVICE_TABLET_TOOL` | `WLR_INPUT_DEVICE_TABLET` |
| Axis notify | 6 args | 7 args (+ relative_direction) |

Version checks use `WLR_VERSION_MINOR` from `<wlr/version.h>`.

## Gesture Navigation

All apps run fullscreen. Navigation is via edge swipes.

| Gesture | Action |
|---------|--------|
| Swipe up from bottom (short) | Open on-screen keyboard |
| Swipe up from bottom (long) | Go to home grid |
| Swipe down from top | Close current app |
| Swipe from left edge | Open quick settings |
| Swipe from right edge | Open app switcher |

### Gesture Thresholds
- **Edge zone:** 80px from screen edge
- **Short swipe:** < 100px (keyboard)
- **Long swipe:** > 100px (home/action)
- **Flick velocity:** > 500px/s triggers action

## Keyboard Shortcuts (Desktop Testing)

| Shortcut | Action |
|----------|--------|
| Super | Go to home |
| Alt+Tab | Cycle apps |
| Alt+F4 | Close window |
| Ctrl+Alt+F1-F12 | Switch VT |
| Escape | Quit |

## Mouse Gesture Testing

Left-click and drag from screen edges to simulate touch gestures.
Background color interpolates during drag to show transition progress.

## Shell Views & Colors

| View | Color | RGB |
|------|-------|-----|
| Home | Blue | (0.1, 0.2, 0.8) |
| App | Black | (0.0, 0.0, 0.0) |
| Quick Settings | Purple | (0.7, 0.1, 0.7) |
| App Switcher | Green | (0.1, 0.7, 0.2) |
| Lock | Red | (0.8, 0.1, 0.1) |

## Architecture

```
flick-wlroots/
  src/
    main.c              - Entry point, backend selection
    compositor/
      server.c/h        - Core compositor, cursor, backend init
      output.c/h        - Display output management
      input.c/h         - Keyboard, touch, pointer input
      view.c/h          - XDG toplevel window management
    shell/
      shell.c/h         - Shell state machine, view transitions
      gesture.c/h       - Touch gesture recognition
      apps.c/h          - Desktop file parsing (future)
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `WLR_BACKENDS` | Force backend: `hwcomposer`, `drm`, `wayland`, `x11` |
| `EGL_PLATFORM` | EGL platform: `hwcomposer` for Droidian |
| `FLICK_TERMINAL` | Terminal to auto-launch (default: foot) |
| `XDG_RUNTIME_DIR` | Wayland socket directory |

## Troubleshooting

### "Failed to create DRM backend" on phone
You're not using hwcomposer. Set `WLR_BACKENDS=hwcomposer`.

### "DRM_CRTC_IN_VBLANK_EVENT unsupported"
Android devices don't support standard DRM. Use hwcomposer backend.

### SSH disconnects when running
Normal when stopping phosh. Use `start_hwcomposer.sh` which runs in background.

### Build fails with "wlroots-0.18 not found"
On Droidian, the package is just `wlroots`. The Makefile should auto-detect.
