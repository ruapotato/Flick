# Flick

An alternative mobile interface for Linux phones, designed as a gesture-first alternative to Phosh and Plasma Mobile for Debian/Droidian devices.

**Why Flick?** Phosh (GNOME/GTK) and Plasma Mobile (KDE/Qt) are desktop environments squeezed onto phones. Flick is built from the ground up for mobile - gestures are the primary input, not an afterthought. Rust + Smithay + Slint means it's lean, fast, and doesn't carry decades of desktop baggage.

**Target devices:** Debian/Droidian devices including FuriOS (FuriPhone FLXS1/FLXS1s), PinePhone, PinePhone Pro, Librem 5, and devices running postmarketOS or Mobian.

**Goal:** Provide an alternative interface that can co-exist alongside Phosh on mobile Linux distributions, giving users a choice of shell experiences.

## Current Status: ~80% Complete

The core compositor and shell UI work well when running directly on hardware (TTY mode). The project is usable for basic tasks but still has rough edges.

**Working (TTY/Hardware mode):**
- Wayland compositor with DRM/KMS rendering (60fps)
- Touch gesture navigation (edge swipes, multi-touch)
- Home screen with categorized app grid
- App switcher with Android-style stacked cards
- Quick Settings panel (WiFi, Bluetooth, brightness, flashlight, airplane mode, rotation lock)
- Lock screen with PIN authentication (Python/Kivy app)
- On-screen keyboard (Slint-based, integrated into shell)
- XWayland support for X11 apps

**Known Issues / Missing:**
- Gesture animation alignment issues (visual polish needed)
- Nested/embedded mode (running as window) has many bugs - for development only
- Keyboard input routing incomplete
- PAM integration for lock screen not implemented
- No notification support yet
- No settings app yet

## Architecture

Flick uses a **layered architecture** that separates the core compositor from UI components. This enables security (shell controls what apps can do), flexibility (swap UI implementations), and rapid development (iterate on apps without touching the compositor).

```
┌─────────────────────────────────────────────────────┐
│              App Layer (Python/Kivy)                │
│  ┌───────────────┐  ┌───────────────────────────┐  │
│  │  Lock Screen  │  │   Settings, Phone, SMS,   │  │
│  │  (Python/Kivy)│  │   Contacts (planned)      │  │
│  │  Fullscreen   │  │   Regular windowed apps   │  │
│  │  Wayland app  │  │                           │  │
│  └───────────────┘  └───────────────────────────┘  │
│   Beautiful animated visuals, PAM authentication    │
└─────────────────────────────────────────────────────┘
                        │ Wayland protocol
┌─────────────────────────────────────────────────────┐
│              Shell Layer (Rust + Slint)             │
│  ┌─────────────────────────────────────────────────┐│
│  │              Slint UI Layer                     ││
│  │   Home screen, quick settings, app switcher,   ││
│  │   on-screen keyboard, status bar               ││
│  │      (GPU accelerated via OpenGL ES 2.0)       ││
│  └─────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────┐│
│  │           Smithay Compositor Core               ││
│  │   DRM/KMS, libinput, XWayland, Wayland protocols││
│  │   Security: blocks gestures on lock screen,     ││
│  │   manages view transitions, enforces policy     ││
│  └─────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────┘
                        │
┌─────────────────────────────────────────────────────┐
│                    Linux Kernel                     │
│              DRM, input devices, TTY                │
└─────────────────────────────────────────────────────┘
```

### Design Philosophy

**Shell Layer (Rust + Slint)** - The compositor handles:
- Window management & compositing
- Touch gesture recognition with security enforcement
- Core UI: home screen, quick settings toggles, app switcher, on-screen keyboard
- Zero-latency gesture response via direct rendering
- **Security policy**: blocks all navigation gestures while lock screen is active

**App Layer (Python/Kivy)** - Regular Wayland clients:
- **Lock Screen** (Python/Kivy) - Full-screen app with beautiful animations, PIN entry, PAM authentication. Runs as a special Wayland client that the shell recognizes.
- **Settings** (planned) - WiFi, Bluetooth, display, lock screen config, etc.
- **Phone/Messages/Contacts** (planned) - System apps

This separation enables:
- **Security**: Shell enforces lock screen - even if the Python app crashed, gestures still blocked
- **Flexibility**: Swap lock screen implementation without touching compositor
- **Rapid iteration**: Use Python/Kivy for quick prototyping with rich visuals
- **Beautiful UIs**: Python/Kivy enables stunning visual effects that would be complex in Slint

Apps communicate with the shell via:
- **File-based IPC**: `~/.local/state/flick/unlock_signal` (lock screen writes, shell reads)
- **Config files**: `~/.local/state/flick/lock_config.json` (credentials, settings)
- **Wayland protocols**: Standard keyboard/input via Wayland

## Gestures

| Gesture | Action |
|---------|--------|
| Swipe up from bottom | Go home / show keyboard (in apps) |
| Swipe down from top | Close current app |
| Swipe right from left edge | Quick Settings panel |
| Swipe left from right edge | App switcher |
| Swipe up from Quick Settings | Return to home |
| Swipe up from App Switcher | Return to home |

All gestures track 1:1 with your finger for responsive, natural feel.

## Building

### Dependencies (Debian/Ubuntu/Mobian)

```bash
sudo apt install libseat-dev libinput-dev libudev-dev libgbm-dev \
                 libegl-dev libdrm-dev libxkbcommon-dev pkg-config \
                 libpam0g-dev python3-kivy
```

### Build & Run

```bash
# Quick start
./start.sh

# Or manually
cd shell
cargo build --release
```

Run from a TTY (Ctrl+Alt+F2), not from within another graphical session.

### VT Switching

Press `Ctrl+Alt+F1` through `Ctrl+Alt+F12` to switch between virtual terminals.

## Roadmap

### Phase 1: Core Shell (~80% Done)
- [x] Wayland compositor (Smithay)
- [x] DRM/KMS + GBM rendering
- [x] Touch gesture recognition
- [x] Home screen with app grid
- [x] App switcher with card stack
- [x] Quick Settings panel
- [x] Lock screen (PIN)
- [x] On-screen keyboard (Slint-based)
- [x] XWayland support
- [ ] Animated transitions (partially working, alignment issues)
- [ ] Nested/embedded mode polish (many bugs)

### Phase 2: Daily Driver Basics
- [ ] Keyboard input routing to all apps
- [ ] PAM authentication for lock screen (Linux password)
- [ ] Notifications (freedesktop notification daemon)
- [ ] Settings app: WiFi network picker
- [ ] Settings app: Bluetooth pairing
- [ ] Settings app: Sound controls

### Phase 3: Phone Features
- [ ] Telephony (ModemManager integration)
- [ ] SMS/MMS
- [ ] Contacts app
- [ ] Cellular signal indicators
- [ ] Power management (suspend/resume)

### Phase 4: Polish
- [ ] Swipe typing
- [ ] App search
- [ ] Notification history/shade
- [ ] Haptic feedback
- [ ] Accessibility features

## Directory Structure

```
flick/
├── shell/                      # Rust Wayland compositor + Slint shell
│   ├── src/
│   │   ├── main.rs            # Entry point
│   │   ├── state.rs           # Compositor state + security policy
│   │   ├── input/
│   │   │   ├── gestures.rs    # Touch gesture recognition
│   │   │   └── handler.rs     # Shared input handling (keycode conversion,
│   │   │                      # lock screen actions, keyboard injection)
│   │   ├── shell/             # Shell UI components
│   │   │   ├── mod.rs         # Shell state + view transitions
│   │   │   ├── slint_ui.rs    # Slint integration + keyboard
│   │   │   ├── lock_screen.rs # Lock screen detection + IPC
│   │   │   ├── quick_settings.rs
│   │   │   └── apps.rs        # .desktop file parsing
│   │   ├── backend/
│   │   │   ├── udev.rs        # TTY backend: DRM/KMS + libinput
│   │   │   └── winit.rs       # Embedded backend: runs in a window
│   │   └── system.rs          # Hardware integration
│   └── ui/
│       └── shell.slint        # Slint UI definitions (keyboard, home, etc.)
├── apps/                       # App layer - Python/Kivy apps
│   └── flick_lockscreen/      # Lock screen (Python/Kivy)
│       └── flick_lockscreen.py # Animated PIN entry + PAM auth
└── start.sh                   # Launch script
```

### Backend Architecture

Flick supports two backends that share common input handling logic:

```
┌─────────────────────────────────────────────┐
│        Shared Input Processing              │
│  (handler.rs: keycode conversion, lock      │
│   screen actions, keyboard injection)       │
└─────────────────────────────────────────────┘
           ↑                        ↑
    ┌──────┴──────┐          ┌──────┴──────┐
    │  TTY Mode   │          │  Embedded   │
    │  (udev.rs)  │          │ (winit.rs)  │
    │  libinput   │          │ winit events│
    │  DRM/KMS    │          │ window      │
    └─────────────┘          └─────────────┘
```

**TTY Mode** (`--windowed` not set): Runs directly on hardware using DRM/KMS for display and libinput for touch/keyboard. This is the production mode for Linux phones.

**Embedded Mode** (`--windowed`): Runs in a window on X11 or Wayland for development and testing. Touch is simulated from mouse events.

## Contributing

Flick aims to be the best Linux phone DE. Contributions welcome - especially for:
- Keyboard improvements (swipe typing, predictions)
- Phone hardware support (ModemManager, ofono)
- Accessibility features
- Testing on different devices

## License

GPL-3.0 - David Hamner
