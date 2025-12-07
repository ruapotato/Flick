# Flick

A mobile-first Wayland compositor for Linux phones with an integrated touch shell.

**Target devices:** FuriPhone FLX1s, PinePhone, and other Linux phones running Droidian/postmarketOS/Mobian.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│              Flick Shell (Rust + Slint)             │
│  ┌─────────────────────────────────────────────────┐│
│  │              Slint UI Layer                     ││
│  │   Home screen, lock screen, quick settings     ││
│  │      (GPU accelerated via OpenGL ES 2.0)       ││
│  └─────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────┐│
│  │           Smithay Compositor Core               ││
│  │   DRM/KMS, libinput, XWayland, Wayland protocols││
│  └─────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────┘
                        │
┌─────────────────────────────────────────────────────┐
│                    Linux Kernel                     │
│              DRM, input devices, TTY                │
└─────────────────────────────────────────────────────┘
```

The shell UI is rendered directly by the compositor using Slint - no separate shell process, no IPC. This provides:
- Zero-latency gesture response
- Direct access to window list
- Single process simplicity
- Smooth 60fps animations
- OpenGL ES 2.0 for broad device support

## Features

- **Lock Screen** - PIN, pattern, or PAM password authentication
- **Home Screen** - App grid with category-based organization
- **App Switcher** - Android-style horizontal card stack
- **Quick Settings** - WiFi, Bluetooth, brightness controls
- **Settings App** - Flutter-based system settings

## Requirements

- Rust 1.70+
- libseat, libinput, libudev (session/input management)
- Mesa with GBM and EGL support
- OpenGL ES 2.0+ capable GPU

### Installing Dependencies (Debian/Ubuntu)

```bash
sudo apt install libseat-dev libinput-dev libudev-dev libgbm-dev \
                 libegl-dev libdrm-dev libxkbcommon-dev pkg-config \
                 libpam0g-dev
```

## Building

```bash
./start.sh
```

Or manually:

```bash
cd shell
cargo build --release
```

## Usage

### Running Flick

From a TTY (not from within another graphical session):

```bash
./start.sh
```

### Lock Screen

- **Power button** or **Super+L** to lock
- Set PIN/pattern/password via Settings app

### VT Switching

Press `Ctrl+Alt+F1` through `Ctrl+Alt+F12` to switch between virtual terminals.

## Directory Structure

```
flick/
├── shell/                      # Rust Wayland compositor + Slint shell
│   ├── src/
│   │   ├── main.rs            # Entry point
│   │   ├── state.rs           # Compositor state, Wayland protocols
│   │   ├── input/
│   │   │   └── gestures.rs    # Touch gesture recognition
│   │   ├── shell/             # Shell UI components
│   │   │   ├── mod.rs         # Shell state and coordination
│   │   │   ├── app_grid.rs    # Home screen app launcher
│   │   │   ├── lock_screen.rs # Lock screen (PIN/pattern/password)
│   │   │   ├── quick_settings.rs # Quick settings panel
│   │   │   └── apps.rs        # Desktop file parsing
│   │   └── backend/
│   │       └── udev.rs        # DRM/KMS backend, rendering
│   └── Cargo.toml
│
├── apps/
│   └── flick_settings/        # Flutter Settings app
│
└── start.sh                   # Launch script
```

## Gestures

| Gesture | Action |
|---------|--------|
| Swipe up from bottom | Go home (app grid) |
| Swipe down from top | Close current app |
| Swipe right from left | Quick settings panel |
| Swipe left from right | App switcher |

## Roadmap

- [x] Wayland compositor (Smithay)
- [x] DRM/KMS + GBM rendering
- [x] Touch gesture recognition
- [x] Integrated shell UI (home, switcher, quick settings)
- [x] XWayland support
- [x] Lock screen (PIN/pattern/PAM)
- [x] Settings app (Flutter)
- [ ] **Slint UI migration** (in progress)
- [ ] Notifications (D-Bus integration)
- [ ] On-screen keyboard
- [ ] Phone/SMS integration

## License

GPL-3.0 - David Hamner
