# Flick

A mobile-first Wayland compositor for Linux phones with an integrated touch shell.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│            Flick Compositor + Shell (Rust)          │
│  ┌─────────────────────────────────────────────┐   │
│  │           Integrated Shell UI                │   │
│  │   App grid, app switcher, gesture overlays   │   │
│  │         (rendered via GLES directly)         │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│   DRM/KMS rendering, libinput, session management   │
│   XWayland for X11 app compatibility                │
└─────────────────────────────────────────────────────┘
                        │
┌─────────────────────────────────────────────────────┐
│                    Linux Kernel                     │
│              DRM, input devices, TTY                │
└─────────────────────────────────────────────────────┘
```

The shell UI is rendered directly by the compositor - no separate shell process, no IPC. This provides:
- Zero-latency gesture response
- Direct access to window list
- Single process simplicity
- Smooth animations

## Requirements

- Rust 1.70+ (for compositor)
- libseat, libinput, libudev (session/input management)
- Mesa with GBM and EGL support

### Installing Dependencies (Debian/Ubuntu)

```bash
sudo apt install libseat-dev libinput-dev libudev-dev libgbm-dev \
                 libegl-dev libdrm-dev libxkbcommon-dev pkg-config
```

## Building

```bash
cd compositor
cargo build --release
```

## Usage

### Running Flick

From a TTY (not from within another graphical session):

```bash
cd compositor
cargo run --release
```

Or use the start script:

```bash
./start.sh
```

### VT Switching

Press `Ctrl+Alt+F1` through `Ctrl+Alt+F12` to switch between virtual terminals.

## Directory Structure

```
flick/
├── compositor/                 # Rust Wayland compositor + integrated shell
│   ├── src/
│   │   ├── main.rs            # Entry point, argument parsing
│   │   ├── state.rs           # Compositor state, Wayland protocols
│   │   ├── input/
│   │   │   └── gestures.rs    # Touch gesture recognition
│   │   ├── shell/             # Integrated shell UI
│   │   │   ├── mod.rs         # Shell state and coordination
│   │   │   ├── app_grid.rs    # Home screen app launcher grid
│   │   │   ├── app_switcher.rs# Recent apps view (Android-style)
│   │   │   ├── quick_settings.rs # Quick settings/notifications panel
│   │   │   └── overlay.rs     # Gesture overlay animations
│   │   └── backend/
│   │       └── udev.rs        # DRM/KMS backend, rendering, input
│   └── Cargo.toml
│
├── apps/                       # App launcher definitions
├── config/                     # Configuration
└── start.sh                    # Launch script
```

## Gestures

Edge swipe gestures (inspired by N9/webOS/iOS/Android):

| Gesture | Action |
|---------|--------|
| Swipe up from bottom edge | Go home (show app grid) |
| Swipe down from top edge | Close current app (with drag animation) |
| Swipe right from left edge | Quick settings panel (notifications/toggles) |
| Swipe left from right edge | App switcher (Android-style card stack) |

## Shell UI Components

### App Grid (Home Screen)
- Grid of app launchers
- Tap to launch apps via XWayland
- Slides up from bottom on swipe-up gesture

### App Switcher
- Android-style horizontal card stack
- Shows all open windows at 65% size
- Swipe/scroll through cards horizontally
- Tap card to switch to app
- Only appears when apps are open

### Quick Settings Panel
- Android-style notification/settings panel
- Quick toggles for WiFi, Bluetooth, DND, etc.
- Notifications list below toggles
- Swipe right from left edge to open

### Gesture Overlays
- Close indicator (top edge) - follows finger with danger zone
- Visual feedback during all gestures

## Logging

```bash
# Verbose logging
RUST_LOG=debug cargo run --release

# Info level (default)
RUST_LOG=info cargo run --release
```

Logs are written to `~/.local/state/flick/compositor.log.*`

## Roadmap

- [x] Custom Wayland compositor (Smithay)
- [x] DRM/KMS rendering with GBM
- [x] Keyboard, pointer, and touch input
- [x] VT switching support
- [x] Session management (libseat)
- [x] XWayland support (X11 apps)
- [x] Touch gesture recognition
- [x] Integrated shell UI
  - [x] Gesture overlays
  - [x] App grid home screen
  - [x] App switcher
  - [x] Quick settings panel
- [ ] Notification system (IPC integration)
- [ ] Lock screen

## License

MIT
