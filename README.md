# Flick

A gesture-driven mobile Linux shell built with Flutter. Flick runs on existing mobile Linux infrastructure (Phoc compositor, lisgd for gestures) and provides a modern, touch-first experience.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│              Flick Shell (Flutter)                  │
│        layer-shell surface, responds to gestures    │
└─────────────────────────────────────────────────────┘
                        │
            D-Bus signals / XF86 keys
                        │
┌─────────────────────────────────────────────────────┐
│                     lisgd                           │
│   Left edge swipe → XF86Back (back navigation)      │
│   Right edge swipe → XF86Forward                    │
└─────────────────────────────────────────────────────┘
                        │
┌─────────────────────────────────────────────────────┐
│                      Phoc                           │
│    Wayland compositor (unchanged, runs as-is)       │
└─────────────────────────────────────────────────────┘
```

Flick doesn't replace the compositor - it's a layer-shell client that can hot-swap with Phosh.

## Requirements

- Flutter 3.x
- Phoc (Wayland compositor)
- lisgd (gesture daemon)
- wtype (key injection)
- gtk-layer-shell

### Installing Dependencies (Debian/Ubuntu)

```bash
sudo apt install libgtk-layer-shell-dev libgtk-3-dev pkg-config \
                 cmake ninja-build clang lisgd wtype
```

## Building

```bash
cd shell
flutter pub get
flutter build linux --release
```

The binary will be at `shell/build/linux/x64/release/bundle/flick_shell`

## Usage

### Development Mode (Windowed)

Run Flick in a regular window without layer-shell:

```bash
FLICK_NO_LAYER_SHELL=1 ./shell/build/linux/x64/release/bundle/flick_shell
```

### Hot-Swap with Phosh

Switch from Phosh to Flick without restarting the compositor:

```bash
# Switch to Flick
./config/flick-swap.sh

# Switch back to Phosh
./config/flick-swap.sh phosh
```

### Full Session

Start Flick as the shell (replaces Phosh entirely):

```bash
./config/flick-session
```

## Directory Structure

```
flick/
├── shell/                      # Flutter shell application
│   ├── lib/
│   │   ├── main.dart           # Entry point, keyboard handling
│   │   ├── core/
│   │   │   ├── logger.dart     # Logging and crash recording
│   │   │   └── app_model.dart  # App data model
│   │   ├── shell/
│   │   │   └── home/
│   │   │       ├── home_screen.dart
│   │   │       └── app_grid.dart
│   │   └── theme/
│   │       └── flick_theme.dart
│   └── linux/
│       └── runner/
│           └── my_application.cc  # Layer-shell integration
│
├── services/                   # Rust D-Bus services (planned)
│   └── flick-app-service/
│
├── config/
│   ├── lisgd.sh               # Gesture daemon configuration
│   ├── flick-session          # Full session startup
│   └── flick-swap.sh          # Hot-swap between shells
│
└── apps/                       # Native Flick apps (planned)
```

## Gestures

Flick uses lisgd for edge gestures:

| Gesture | Action |
|---------|--------|
| Left edge swipe right | Back (XF86Back) |
| Right edge swipe left | Forward (XF86Forward) |
| Swipe up from bottom | Open app drawer |
| Swipe down on drawer | Close app drawer |

The shell listens for XF86Back/XF86Forward keys sent by lisgd via wtype.

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
RUST_LOG=debug ./compositor/run.sh
```

## Configuration

### Environment Variables

| Variable | Description |
|----------|-------------|
| `FLICK_NO_LAYER_SHELL` | Set to any value to disable layer-shell (windowed mode) |
| `FLICK_ROOT` | Override the Flick installation directory |
| `LISGD_DEVICE` | Override touchscreen device path |

### Customizing Gestures

Edit `config/lisgd.sh` to modify gesture bindings:

```bash
lisgd -d "$LISGD_DEVICE" \
  -g "1,LR,L,*,R,wtype -k XF86Back" \
  -g "1,RL,R,*,R,wtype -k XF86Forward"
```

See `man lisgd` for gesture configuration syntax.

## Development

### Running with Hot Reload

```bash
cd shell
FLICK_NO_LAYER_SHELL=1 flutter run -d linux
```

### Testing Layer-Shell

Test in a nested Wayland session or hot-swap on a real Phosh device:

```bash
# Build release
flutter build linux --release

# Hot-swap
../config/flick-swap.sh
```

### Code Style

- No back buttons in UI - back is always edge swipe
- No hamburger menus - use bottom sheets
- Minimum 48dp touch targets
- Content-first - no welcome screens

## Roadmap

- [x] Layer-shell integration
- [x] Home screen with app grid
- [x] App drawer with search
- [x] XF86Back handling
- [x] Logging and crash recording
- [x] Hot-swap script
- [ ] App discovery via D-Bus service
- [ ] Waydroid app integration
- [ ] Quick settings panel
- [ ] Notification shade
- [ ] Lock screen
- [ ] Native Flick apps (Files, Settings, Terminal)

## License

MIT
