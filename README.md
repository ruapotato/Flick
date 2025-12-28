# Flick

A mobile-first Wayland compositor and shell for Linux phones, designed to replace Phosh and Plasma Mobile as the go-to Linux mobile desktop environment.

**Why Flick?** Phosh (GNOME/GTK) and Plasma Mobile (KDE/Qt) are desktop environments squeezed onto phones. Flick is built from the ground up for mobile - gestures are the primary input, not an afterthought. Rust + Smithay + Qt/QML means it's lean, fast, and doesn't carry decades of desktop baggage.

**Target devices:** Android phones running Droidian (Pixel 3a, OnePlus, etc.). Native Linux support (PinePhone, Librem 5) is deprecated but the DRM/KMS backend could work with some effort.

## Device Compatibility

| Device Type | Status | Notes |
|-------------|--------|-------|
| **Droidian** (Android phones) | ⚠️ Early Prototype | Primary target, HWComposer working, actively developed |
| **Native Linux** (PinePhone, Librem 5) | ❌ Deprecated | DRM/KMS backend exists but unmaintained, could work with effort |
| **PostmarketOS** (mainline kernel) | ❌ Deprecated | Could work with DRM backend fixes |
| **Mobian** | ❌ Deprecated | Could work with DRM backend fixes |

### Droidian / HWComposer Support

Droidian and similar Android-based Linux distributions require **HWComposer** integration to access the GPU.

**Current status (Dec 2025):** Early prototype. HWComposer backend works, core shell functional, but missing telephony/SMS integration.

✅ **Working:**
- Display output via hwcomposer (tested on Pixel 3a)
- EGL/GLES rendering through libhybris HWCNativeWindow
- **Hardware acceleration for ALL apps** (including lock screen)
- Wayland compositor with full client support
- Lock screen, shell UI, and native Wayland apps (terminals, Settings, etc.)
- Edge gesture detection (swipe from edges)
- App switcher with fan-out card stack and gesture-driven animations
- **App switcher previews** - captures EGL textures with GL state save/restore
- Smooth shrink animation when entering app switcher (follows finger)
- On-screen keyboard overlay with touch input to apps
- Keyboard input injection to focused Wayland clients
- Proper privilege dropping for app launching
- Keyboard state save/restore when switching apps
- SHM buffer rendering for external Wayland clients
- EGL buffer import for hardware-accelerated apps (camera preview, etc.)
- Camera with live video preview (via droidian-camera + AAL backend)

⚠️ **Known Issues:**
- X11/XWayland apps do not work (Firefox, etc.) - native Wayland apps only
- App windows may show incorrectly sized on first open (resize after switching away and back)

The hwcomposer backend uses a C shim library (`hwc-shim/`) that wraps Android's HWC2 API via libhybris, with Rust FFI bindings calling into it.

## Current Status

**Working:**
- Wayland compositor with DRM/KMS rendering (60fps)
- Touch gesture navigation (edge swipes, multi-touch)
- Home screen with categorized app grid
- App switcher with Android-style stacked cards
- Quick Settings panel (WiFi, Bluetooth, brightness, flashlight, airplane mode, rotation lock)
- Hardware volume buttons with on-screen overlay
- On-screen keyboard (Slint-based, integrated into shell)
- XWayland support for X11 apps
- Smooth animated transitions throughout
- Droidian/libhybris GPU acceleration
- **Lock screen with PIN unlock** - QML lock screen with swipe-to-unlock and PIN entry, successfully transitions to app grid

**In Progress:**
- PAM integration for lock screen (currently uses static PIN)

**Security:**
- **Privilege dropping** - The compositor runs as root for DRM/GPU access, but apps are spawned as the normal user (e.g., `droidian`). Uses `setuid`/`setgid` to drop privileges before exec, with proper `HOME`, `USER`, and `XDG_*` environment variables.

## Included Apps

Flick comes with a set of QML apps. Status of each:

| App | Status | Notes |
|-----|--------|-------|
| **Settings** | ✅ Working | WiFi, Bluetooth, Display, Sound, Battery, Storage, Date/Time, Timezone, About |
| **Calculator** | ✅ Working | Basic calculator with standard operations |
| **Calendar** | ✅ Working | Basic calendar view |
| **Music** | ✅ Working | Music player with playback controls |
| **Audiobooks** | ✅ Working | Audiobook player with chapter support |
| **Podcast** | ✅ Working | Podcast player with RSS feed support |
| **Video** | ✅ Working | Video player for local files |
| **Ebooks** | ✅ Working | EPUB reader with bookmarks |
| **Camera** | ✅ Working | Camera with live preview (uses droidian-camera on Droidian) |
| **Notes** | ✅ Working | Simple note-taking app with audio recording |
| **Recorder** | ✅ Working | Audio recorder with playback |
| **Files** | ✅ Working | File browser with context menu |
| **Photos** | ✅ Working | Photo gallery viewer |
| **Terminal** | ✅ Working | Terminal emulator |
| **Clock** | ✅ Working | Clock with alarms and timer |
| **Contacts** | ✅ Working | Contact management |
| **Lock Screen** | ✅ Working | Pattern/PIN entry, swipe to unlock, hardware accelerated |
| **Distract** | ✅ Working | Toddler distraction app with interactive animations |
| **Phone** | ⚠️ Partial | Dialer UI works, audio controls work, modem integration in progress |
| **Messages** | ⚠️ Partial | SMS interface UI (requires modem integration) |
| **Email** | 🚧 TODO | Email client (UI only, needs backend) |
| **Web** | 🚧 TODO | Web browser (UI only, needs browser engine) |

## Architecture

Flick uses a **layered architecture** that separates the core compositor from UI components. This enables security (shell controls what apps can do), flexibility (swap UI implementations), and rapid development.

```
┌─────────────────────────────────────────────────────┐
│                App Layer (Qt/QML)                   │
│  ┌───────────────┐  ┌───────────────────────────┐  │
│  │  Lock Screen  │  │   Settings, Phone, SMS,   │  │
│  │    (QML)      │  │   Contacts (planned)      │  │
│  │  Fullscreen   │  │   Regular windowed apps   │  │
│  │  Wayland app  │  │                           │  │
│  └───────────────┘  └───────────────────────────┘  │
│   SailfishOS-style fluid UI, hardware accelerated   │
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

### Technology Stack

| Component | Technology | Why |
|-----------|------------|-----|
| **Compositor** | Rust + Smithay | Memory safe, fast, modern Wayland |
| **Shell UI** | Slint | GPU-accelerated, embedded-friendly |
| **Apps** | Qt5/QML + JavaScript | Hardware accelerated on libhybris, SailfishOS-style fluid UIs |
| **IPC** | File-based + Wayland | Simple, secure, reliable |

### Why QML for Apps?

We chose **Qt/QML** over Python/Kivy because:

1. **Hardware acceleration on libhybris** - Qt5 GLES works natively with Android GPU drivers
2. **SailfishOS proven** - Same stack powers Jolla phones for 10+ years
3. **Declarative UI** - QML is like HTML/CSS for native apps
4. **Efficient** - JavaScript only runs on events, rendering is native C++
5. **No dependency conflicts** - Uses system Qt libraries directly

### Design Philosophy

**Shell Layer (Rust + Slint)** - The compositor handles:
- Window management & compositing
- Touch gesture recognition with security enforcement
- Core UI: home screen, quick settings toggles, app switcher, on-screen keyboard
- Zero-latency gesture response via direct rendering
- **Security policy**: blocks all navigation gestures while lock screen is active

**App Layer (Qt/QML)** - Regular Wayland clients:
- **Lock Screen** - Full-screen app with fluid animations, PIN entry, PAM authentication
- **Settings** - WiFi, Bluetooth, display, sound, about device
- **Phone/Messages/Contacts** (planned) - System apps

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

### Dependencies (Debian/Ubuntu/Mobian/Droidian)

```bash
# Compositor dependencies
sudo apt install libseat-dev libinput-dev libudev-dev libgbm-dev \
                 libegl-dev libdrm-dev libxkbcommon-dev pkg-config \
                 libpam0g-dev

# QML app dependencies
sudo apt install qmlscene qml-module-qtquick2 qml-module-qtquick-window2 \
                 qml-module-qtquick-controls2 qml-module-qtquick-layouts \
                 qml-module-qtgraphicaleffects
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
- [x] On-screen keyboard (Slint-based)
- [x] XWayland support
- [x] Animated transitions
- [x] Droidian/libhybris GPU support

### Phase 2: Daily Driver Basics (Current)
- [x] Lock screen (QML app with PIN entry and unlock flow)
- [ ] Lock screen PAM integration (use system password)
- [ ] App launching from home screen
- [ ] Settings app (QML)
- [ ] Notifications (freedesktop notification daemon)
- [ ] WiFi network picker
- [ ] Bluetooth pairing
- [x] Sound controls (hardware volume buttons)

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
│   │   ├── android_wlegl.rs   # libhybris buffer sharing protocol
│   │   └── system.rs          # Hardware integration
│   └── ui/
│       └── shell.slint        # Slint UI definitions (keyboard, home, etc.)
├── apps/                       # App layer - Qt/QML apps
│   ├── lockscreen/            # Lock screen (QML)
│   │   ├── main.qml           # Entry point
│   │   ├── LockScreen.qml     # Main lock screen UI
│   │   └── PinEntry.qml       # PIN input component
│   └── settings/              # Settings app (QML)
│       ├── main.qml           # Entry point
│       └── pages/             # Settings pages
└── start.sh                   # Launch script
```

## Contributing

Flick aims to be the best Linux phone DE. Contributions welcome - especially for:
- QML app development (lock screen, settings)
- Keyboard improvements (swipe typing, predictions)
- Phone hardware support (ModemManager, ofono)
- Accessibility features
- Testing on different devices

## Credits

### Icons

Flick uses icons from the following open source projects:

- **[Papirus Icon Theme](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme)** (GPL-3.0) - App icons for Phone, Messages, Camera, Calculator, Calendar, Music, Files, Settings, and more
- **[Lucide Icons](https://github.com/lucide-icons/lucide)** (ISC License) - UI icons for status bar and quick settings (WiFi, Bluetooth, battery, volume, etc.)

## License

GPL-3.0 - David Hamner
