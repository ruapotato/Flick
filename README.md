# Flick

A mobile-first Wayland compositor and shell for Linux phones. Flick includes a custom compositor built with Smithay (Rust) and a gesture-driven Flutter shell.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│              Flick Shell (Flutter)                  │
│         Touch-first UI, app launcher, gestures      │
└─────────────────────────────────────────────────────┘
                        │
                   Wayland protocol
                        │
┌─────────────────────────────────────────────────────┐
│            Flick Compositor (Rust/Smithay)          │
│   DRM/KMS rendering, libinput, session management   │
└─────────────────────────────────────────────────────┘
                        │
┌─────────────────────────────────────────────────────┐
│                    Linux Kernel                     │
│              DRM, input devices, TTY                │
└─────────────────────────────────────────────────────┘
```

Flick is a complete compositor - it runs directly on DRM/KMS without X11 or another Wayland compositor.

## Requirements

- Rust (for compositor)
- Flutter 3.x (for shell)
- libseat, libinput, libudev (session/input management)
- Mesa with GBM and EGL support
- gtk-layer-shell (optional, for shell)

### Installing Dependencies (Debian/Ubuntu)

```bash
# Compositor dependencies
sudo apt install libseat-dev libinput-dev libudev-dev libgbm-dev \
                 libegl-dev libdrm-dev libxkbcommon-dev pkg-config

# Shell dependencies
sudo apt install libgtk-layer-shell-dev libgtk-3-dev \
                 cmake ninja-build clang
```

## Building

### Quick Start

```bash
# Build and run everything
./start.sh
```

### Manual Build

```bash
# Build compositor
cd compositor
cargo build --release

# Build shell
cd ../shell
flutter pub get
flutter build linux --release
```

## Usage

### Running Flick

From a TTY (not from within another graphical session):

```bash
./start.sh
```

Options:
- `--timeout, -t SECONDS` - Exit after N seconds (useful for testing)
- `--shell, -s COMMAND` - Use a different shell (default: flick_shell, fallback: foot)

```bash
# Run with foot terminal for testing
./start.sh --shell foot

# Run for 30 seconds then exit
./start.sh --timeout 30
```

### VT Switching

Press `Ctrl+Alt+F1` through `Ctrl+Alt+F12` to switch between virtual terminals.

### Development Mode

Run just the shell in windowed mode (requires another Wayland compositor):

```bash
FLICK_NO_LAYER_SHELL=1 ./shell/build/linux/x64/release/bundle/flick_shell
```

## Directory Structure

```
flick/
├── compositor/                 # Rust Wayland compositor (Smithay)
│   ├── src/
│   │   ├── main.rs            # Entry point, argument parsing
│   │   ├── state.rs           # Compositor state, Wayland protocols
│   │   ├── viewport.rs        # Virtual viewport management
│   │   └── backend/
│   │       └── udev.rs        # DRM/KMS backend, rendering, input
│   └── Cargo.toml
│
├── shell/                      # Flutter shell application
│   ├── lib/
│   │   ├── main.dart          # Entry point
│   │   ├── core/
│   │   │   ├── logger.dart    # Logging and crash recording
│   │   │   └── app_model.dart # App data model
│   │   ├── shell/
│   │   │   └── home/
│   │   │       ├── home_screen.dart
│   │   │       └── app_grid.dart
│   │   └── theme/
│   │       └── flick_theme.dart
│   └── linux/
│       └── runner/
│           └── my_application.cc
│
├── start.sh                    # Main entry point
└── config/                     # Configuration scripts
```

## Input

The compositor handles input directly via libinput:

- **Keyboard**: Full keyboard support with proper keymap handling
- **Pointer/Mouse**: Motion and button events forwarded to focused window
- **Touch**: Touch events supported (touchscreen devices)

Click or tap on a window to focus it.

## Logging

### Shell Logs

Logs are stored in `~/.local/share/flick/logs/`:

| File | Contents |
|------|----------|
| `flick-TIMESTAMP.log` | Session logs |
| `crash.log` | Crash reports with stack traces |
| `swap.log` | Hot-swap script logs |
| `lisgd.log` | Gesture daemon output |
| `shell.log` | Shell stdout/stderr |

### Compositor Logs

Compositor logs are stored in `~/.local/state/flick/`:

| File | Contents |
|------|----------|
| `compositor.log.YYYY-MM-DD` | Daily compositor logs (rotates automatically) |

These logs persist even after a hard freeze/crash - check them to see what happened before the system went down.

### Viewing Logs

```bash
# Follow current shell session
tail -f ~/.local/share/flick/logs/flick-*.log

# Check for shell crashes
cat ~/.local/share/flick/logs/crash.log

# Check compositor logs (after crash/freeze)
cat ~/.local/state/flick/compositor.log.*

# Verbose compositor logging
RUST_LOG=debug ./start.sh
```

## Configuration

### Environment Variables

| Variable | Description |
|----------|-------------|
| `RUST_LOG` | Compositor log level (error, warn, info, debug, trace) |
| `FLICK_NO_LAYER_SHELL` | Disable layer-shell for shell (windowed mode) |

## Development

### Shell Development (Hot Reload)

```bash
cd shell
FLICK_NO_LAYER_SHELL=1 flutter run -d linux
```

### Compositor Development

```bash
cd compositor
RUST_LOG=debug cargo run -- --shell foot
```

### Code Style

- Mobile-first: minimum 48dp touch targets
- Content-first: no splash screens or unnecessary dialogs
- Direct manipulation: prefer gestures over buttons

## Roadmap

- [x] Custom Wayland compositor (Smithay)
- [x] DRM/KMS rendering with GBM
- [x] Keyboard and pointer input
- [x] VT switching support
- [x] Session management (libseat)
- [x] Flutter shell with app grid
- [x] Logging infrastructure
- [ ] Touch gesture support
- [ ] Multi-window management
- [ ] Layer-shell protocol
- [ ] Quick settings panel
- [ ] Notification system
- [ ] Lock screen

## License

MIT
