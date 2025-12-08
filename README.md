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
- Direct access to window management
- Single process simplicity
- Smooth 60fps animations
- OpenGL ES 2.0 for broad device support

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
│   │   ├── state.rs           # Compositor state
│   │   ├── input/
│   │   │   └── gestures.rs    # Touch gesture recognition
│   │   ├── shell/             # Shell UI components
│   │   │   ├── mod.rs         # Shell state
│   │   │   ├── slint_ui.rs    # Slint integration
│   │   │   ├── lock_screen.rs # Lock screen
│   │   │   ├── quick_settings.rs
│   │   │   └── apps.rs        # .desktop file parsing
│   │   ├── backend/
│   │   │   └── udev.rs        # DRM/KMS backend
│   │   └── system.rs          # Hardware integration
│   └── ui/
│       └── shell.slint        # Slint UI definitions
├── apps/
│   └── flick_settings/        # Settings app
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
