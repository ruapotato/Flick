# Flick

A mobile-first Wayland compositor and shell for Linux phones, designed to replace Phosh and Plasma Mobile as the go-to Linux mobile desktop environment.

**Why Flick?** Phosh (GNOME/GTK) and Plasma Mobile (KDE/Qt) are desktop environments squeezed onto phones. Flick is built from the ground up for mobile - gestures are the primary input, not an afterthought. Rust + Smithay + Slint means it's lean, fast, and doesn't carry decades of desktop baggage.

**Target devices:** PinePhone, PinePhone Pro, Librem 5, FuriPhone FLXS1/FLXS1s, and any Linux phone running postmarketOS, Mobian, or Droidian.

## Device Compatibility

| Device Type | Status | Notes |
|-------------|--------|-------|
| **Native Linux** (PinePhone, Librem 5) | ✅ Works | Standard DRM/KMS, full support |
| **PostmarketOS** (mainline kernel) | ✅ Works | Uses freedreno/panfrost DRM drivers |
| **Mobian** | ✅ Works | Standard Linux graphics stack |
| **Droidian** (Android phones) | 🚧 In Progress | Requires hwcomposer backend (see below) |

### Droidian / libhybris Support

Droidian and similar Android-based Linux distributions use **libhybris** to run Android's hardware abstraction layer (HAL) for graphics. This means:

- **Display**: Controlled by Android's hwcomposer, not standard Linux DRM/KMS
- **GPU**: Accessed through Android's graphics stack, not Mesa DRM
- **Current limitation**: Flick's DRM backend cannot acquire display control on these devices

**What we found testing on Pixel 3a (Droidian):**
```
GL Renderer: "llvmpipe (LLVM 19.1.7, 128 bits)"  # Software rendering only
Mode-setting failed: DRM access error (Invalid argument)
```

The DRM device exists but is meant to be controlled by hwcomposer, not directly by applications. Phosh works on Droidian because wlroots has a hwcomposer backend - we're working on adding one to Flick.

**Workaround (temporary)**: None currently. Native Linux devices work fully.

## Current Status

**Working:**
- Wayland compositor with DRM/KMS rendering (60fps)
- Touch gesture navigation (edge swipes, multi-touch)
- Home screen with categorized app grid
- App switcher with Android-style stacked cards
- Quick Settings panel (WiFi, Bluetooth, brightness, flashlight, airplane mode, rotation lock)
- Lock screen with PIN authentication (Python/Kivy app)
- On-screen keyboard (Slint-based, integrated into shell)
- XWayland support for X11 apps
- Smooth animated transitions throughout

**In Progress:**
- Keyboard input routing to lock screen
- PAM integration for lock screen (system password auth)
- Settings app

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

### Phase 1: Core Shell (Done)
- [x] Wayland compositor (Smithay)
- [x] DRM/KMS + GBM rendering
- [x] Touch gesture recognition
- [x] Home screen with app grid
- [x] App switcher with card stack
- [x] Quick Settings panel
- [x] Lock screen (PIN)
- [x] On-screen keyboard (Slint-based)
- [x] XWayland support
- [x] Animated transitions

### Phase 2: Daily Driver Basics (Current)
- [ ] Hwcomposer backend for Droidian/libhybris devices
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
│   │   │   └── gestures.rs    # Touch gesture recognition
│   │   ├── shell/             # Shell UI components
│   │   │   ├── mod.rs         # Shell state + view transitions
│   │   │   ├── slint_ui.rs    # Slint integration + keyboard
│   │   │   ├── lock_screen.rs # Lock screen detection + IPC
│   │   │   ├── quick_settings.rs
│   │   │   └── apps.rs        # .desktop file parsing
│   │   ├── backend/
│   │   │   └── udev.rs        # DRM/KMS backend + gesture security
│   │   └── system.rs          # Hardware integration
│   └── ui/
│       └── shell.slint        # Slint UI definitions (keyboard, home, etc.)
├── apps/                       # App layer - Python/Kivy apps
│   └── flick_lockscreen/      # Lock screen (Python/Kivy)
│       └── flick_lockscreen.py # Animated PIN entry + PAM auth
└── start.sh                   # Launch script
```

## Contributing

Flick aims to be the best Linux phone DE. Contributions welcome - especially for:
- Keyboard improvements (swipe typing, predictions)
- Phone hardware support (ModemManager, ofono)
- Accessibility features
- Testing on different devices

## License

GPL-3.0 - David Hamner
