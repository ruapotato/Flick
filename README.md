# Flick

A mobile-first Wayland compositor and shell for Linux phones, designed to replace Phosh and Plasma Mobile as the go-to Linux mobile desktop environment.

**Why Flick?** Phosh (GNOME/GTK) and Plasma Mobile (KDE/Qt) are desktop environments squeezed onto phones. Flick is built from the ground up for mobile - gestures are the primary input, not an afterthought. Rust + Smithay + Slint means it's lean, fast, and doesn't carry decades of desktop baggage.

**Target devices:** PinePhone, PinePhone Pro, Librem 5, FuriPhone FLXS1/FLXS1s, and any Linux phone running postmarketOS, Mobian, or Droidian.

## Current Status

**Working:**
- Wayland compositor with DRM/KMS rendering (60fps)
- Touch gesture navigation (edge swipes, multi-touch)
- Home screen with categorized app grid
- App switcher with Android-style stacked cards
- Quick Settings panel (WiFi, Bluetooth, brightness, flashlight, airplane mode, rotation lock)
- Lock screen with PIN/pattern authentication
- XWayland support for X11 apps
- Smooth animated transitions throughout

**In Progress:**
- On-screen keyboard (next priority)
- PAM integration for lock screen
- Settings app enhancements

## Architecture

Flick uses a **layered architecture** that separates the core compositor from UI components. This enables security (shell controls what apps can do), flexibility (swap UI implementations), and rapid development (iterate on apps without touching the compositor).

```
┌─────────────────────────────────────────────────────┐
│           App Layer (Python/Kivy, Flutter, etc.)    │
│  ┌───────────────┐  ┌───────────────────────────┐  │
│  │  Lock Screen  │  │   Settings, Phone, SMS,   │  │
│  │  (Python/Kivy)│  │   Contacts (Flutter)      │  │
│  │  Fullscreen   │  │   Regular windowed apps   │  │
│  │  Wayland app  │  │                           │  │
│  └───────────────┘  └───────────────────────────┘  │
│   Beautiful animated visuals, PAM authentication    │
│   File-based IPC with shell for unlock signals      │
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

**App Layer (Python/Kivy, Flutter)** - Regular Wayland clients:
- **Lock Screen** (Python/Kivy) - Full-screen app with beautiful animations, PIN/pattern entry, PAM authentication. Runs as a special Wayland client that the shell recognizes.
- **Settings** (Flutter) - WiFi, Bluetooth, display, lock screen config, etc.
- **Phone/Messages/Contacts** (Flutter) - Planned system apps

This separation enables:
- **Security**: Shell enforces lock screen - even if the Python app crashed, gestures still blocked
- **Flexibility**: Swap lock screen implementation (Python → Flutter → native) without touching compositor
- **Rapid iteration**: Use Python/Kivy for quick prototyping, Flutter for production apps
- **Beautiful UIs**: Python/Kivy enables stunning visual effects that would be complex in Slint

Apps communicate with the shell via:
- **File-based IPC**: `~/.local/state/flick/unlock_signal` (lock screen writes, shell reads)
- **Config files**: `~/.local/state/flick/lock_config.json` (credentials, settings)
- **D-Bus**: For real-time events (notifications, calls, etc.)

## Gestures

| Gesture | Action |
|---------|--------|
| Swipe up from bottom | Go home / minimize app |
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
                 libpam0g-dev
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

### Phase 1: Core Shell (Done)
- [x] Wayland compositor (Smithay)
- [x] DRM/KMS + GBM rendering
- [x] Touch gesture recognition
- [x] Home screen with app grid
- [x] App switcher with card stack
- [x] Quick Settings panel
- [x] Lock screen (PIN/pattern)
- [x] XWayland support
- [x] Animated transitions

### Phase 2: Daily Driver Basics (Current)
- [ ] **On-screen keyboard** (Wayland virtual keyboard protocol + XWayland)
- [ ] PAM authentication for lock screen (Linux password as fallback)
- [ ] Notifications (freedesktop notification daemon)
- [ ] Settings: WiFi network picker
- [ ] Settings: Bluetooth pairing
- [ ] Settings: Sound controls

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
│   │   │   └── gestures.rs    # Touch gesture recognition
│   │   ├── shell/             # Shell UI components
│   │   │   ├── mod.rs         # Shell state + view transitions
│   │   │   ├── slint_ui.rs    # Slint integration
│   │   │   ├── lock_screen.rs # Lock screen detection + IPC
│   │   │   ├── quick_settings.rs
│   │   │   └── apps.rs        # .desktop file parsing
│   │   ├── backend/
│   │   │   └── udev.rs        # DRM/KMS backend + gesture security
│   │   └── system.rs          # Hardware integration
│   └── ui/
│       └── shell.slint        # Slint UI definitions
├── apps/                       # App layer - Python/Kivy + Flutter apps
│   ├── flick_lockscreen/      # Lock screen (Python/Kivy)
│   │   └── main.py            # Beautiful animated PIN/pattern entry
│   ├── flick_settings/        # Settings app (Flutter)
│   ├── flick_phone/           # Phone/Dialer app (planned)
│   └── flick_messages/        # SMS/MMS app (planned)
└── start.sh                   # Launch script
```

## Contributing

Flick aims to be the best Linux phone DE. Contributions welcome - especially for:
- On-screen keyboard improvements
- Phone hardware support (ModemManager, ofono)
- Accessibility features
- Testing on different devices

## License

GPL-3.0 - David Hamner
