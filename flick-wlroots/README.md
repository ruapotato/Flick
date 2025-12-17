# Flick - Mobile Linux Compositor

A wlroots-based Wayland compositor designed for mobile Linux devices.

**Status:** In development - undergoing refactoring to support hwcomposer backends.

## Building

```bash
make
```

Requirements:
- wlroots 0.18
- wayland-server
- xkbcommon
- pixman

## Running

```bash
./start.sh                    # Run normally
./start.sh --timeout 30       # Auto-exit after 30 seconds (safe testing)
./start.sh -v                 # Verbose logging
```

## Gesture Navigation

Flick uses edge swipes for all navigation. All apps run fullscreen.

### Edge Swipes

| Gesture | Action |
|---------|--------|
| Swipe up from bottom (short) | Open on-screen keyboard |
| Swipe up from bottom (long) | Go to home grid |
| Swipe down from top | Close current app |
| Swipe from left edge | Open quick settings |
| Swipe from right edge | Open app switcher |

### Gesture Thresholds

- **Edge zone:** 80px from screen edge
- **Short swipe:** Less than 100px (keyboard)
- **Long swipe:** More than 100px (home/action)
- **Animation progress:** Gestures track finger position with color transitions

## Keyboard Shortcuts (Desktop Testing)

| Shortcut | Action |
|----------|--------|
| Super (Windows key) | Go to home |
| Alt+Tab | Cycle between apps |
| Alt+F4 | Close focused window |
| Ctrl+Alt+F1-F12 | Switch VT |
| Escape | Quit compositor |

## Mouse/Pointer Testing

Left-click and drag from screen edges to simulate touch gestures.
The background color interpolates as you drag to show transition progress.

## Environment Variables

- `FLICK_TERMINAL` - Override default terminal to launch (default: foot, alacritty, weston-terminal)
- `WLR_BACKENDS` - Override wlroots backend selection (drm, wayland, x11)

## Architecture

```
src/
  main.c              - Entry point
  compositor/
    server.c/h        - Core compositor, backend init, cursor handling
    output.c/h        - Display output management
    input.c/h         - Keyboard, touch, pointer input
    view.c/h          - XDG toplevel window management
  shell/
    shell.c/h         - Shell state machine (home, app, settings views)
    gesture.c/h       - Touch/pointer gesture recognition
    apps.c/h          - Desktop file parsing
```

## Shell Views

- **Home** - App grid (dark blue background)
- **App** - Running application (fullscreen, transparent)
- **Quick Settings** - System settings panel (purple background)
- **App Switcher** - Recent apps (teal background)
- **Lock** - Lock screen (dark gray background)
