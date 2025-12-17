# Flick

A mobile-first Wayland compositor for Linux phones.

## Status: Under Refactoring

**This project is currently being rewritten and is not functional.**

The main branch is transitioning from Rust/Smithay to **C/wlroots** to better support hwcomposer backends for Droidian and Android-based Linux phones.

### What Works (on main branch)
- Basic wlroots compositor skeleton
- DRM/KMS output on standard Linux (tested on Intel)
- Touch gesture recognition framework
- Shell state machine (home, app switcher, quick settings views)

### What Doesn't Work Yet
- hwcomposer backend integration
- App launching
- On-screen keyboard
- Lock screen
- Most phone functionality

## Target Devices

| Device Type | Backend | Status |
|-------------|---------|--------|
| Standard Linux (PinePhone, Librem 5) | DRM/KMS | Basic rendering works |
| Droidian (Android phones) | hwcomposer | In progress |

## Building

### Dependencies (Debian/Ubuntu)

```bash
sudo apt install libwlroots-dev libwayland-dev libxkbcommon-dev \
                 libpixman-1-dev pkg-config build-essential
```

### Build & Run

```bash
# Build and run with 10 second timeout (for testing)
./start.sh --timeout 10

# With verbose logging
./start.sh --timeout 10 -v

# Check logs
ls flick-wlroots/logs/
```

Run from a TTY (Ctrl+Alt+F2), not from within another graphical session.

## Architecture

```
flick-wlroots/
├── src/
│   ├── main.c                 # Entry point, argument parsing
│   ├── compositor/
│   │   ├── server.c/h         # wlroots server setup
│   │   ├── output.c/h         # Display/output handling
│   │   ├── input.c/h          # Keyboard/touch input
│   │   └── view.c/h           # Window management (xdg-shell)
│   └── shell/
│       ├── gesture.c/h        # Touch gesture recognition
│       └── shell.c/h          # Shell state machine
├── Makefile
└── build/                     # Build output
```

## Gesture Design

| Gesture | Action |
|---------|--------|
| Swipe up from bottom | Go home |
| Swipe down from top | Close app |
| Swipe from left edge | Quick Settings |
| Swipe from right edge | App switcher |

## Previous Implementation

The previous Rust/Smithay implementation had more features but hwcomposer support proved difficult. That code is preserved in git history if needed.

## License

GPL-3.0 - David Hamner
