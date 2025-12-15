# Flick Testing Guide

## Device Setup

**Phone:** Pixel 3a running Droidian
**SSH Access:** `ssh droidian@10.15.19.82`
**Password:** (use your configured password)

## Building

### On the phone (recommended):
```bash
cd ~/Flick/shell
cargo build --release --features hwcomposer
```

### Cross-compile from host:
```bash
cd ~/Flick/shell
cross build --release --target aarch64-unknown-linux-gnu --features hwcomposer
scp target/aarch64-unknown-linux-gnu/release/flick droidian@10.15.19.82:~/Flick/shell/target/release/
```

## Running Flick

### Quick Start (recommended):
```bash
ssh droidian@10.15.19.82
cd ~/Flick
sudo systemctl stop phosh
./start_flick.sh
```

### Manual Start:
```bash
# Stop conflicting compositor (phosh holds the hwcomposer binder)
sudo systemctl stop phosh

# Start hwcomposer service
sudo systemctl start android-service@hwcomposer.service
# Or use the wrapper script:
sudo ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' \
    /usr/lib/halium-wrappers/android-service.sh hwcomposer start

# Wait for hwcomposer to start
sleep 2

# Run Flick
export XDG_RUNTIME_DIR=/run/user/32011
export EGL_PLATFORM=hwcomposer
sudo -E ~/Flick/shell/target/release/flick --hwcomposer
```

### Background mode with logging:
```bash
sudo systemctl stop phosh
./start_flick.sh --bg
tail -f /tmp/flick.log
```

## Testing Wayland Clients

After Flick is running (with `--bg` or in another terminal):

```bash
export WAYLAND_DISPLAY=wayland-1
export XDG_RUNTIME_DIR=/run/user/32011

# Test with foot terminal
foot &

# Test with Python lockscreen
cd ~/Flick/apps/flick_lockscreen
python3 flick_lockscreen.py
```

## Returning to Phosh

```bash
sudo pkill flick
sudo systemctl start phosh
```

## Debug Logging

Enable verbose logs:
```bash
RUST_LOG=debug sudo -E ~/Flick/shell/target/release/flick --hwcomposer
```

Check logs:
```bash
tail -f /tmp/flick.log
cat ~/.local/state/flick/flick_lockscreen.log
```

## Known Issues

- Only one compositor can use hwcomposer at a time (stop phosh first)
- HWC2 may report error 6 (NO_RESOURCES) after extended use
- **Python lockscreen (Kivy/SDL2) doesn't work yet** - requires `android_wlegl` protocol
  - Error: "Fatal: the server doesn't advertise the android_wlegl global!"
  - This libhybris-specific Wayland extension allows GPU buffer sharing
  - Droidian's wlroots has it (`wlr_android_wlegl_create`), Flick needs implementation
- Built-in Slint lock screen works and displays on screen
- Native Wayland clients (foot terminal) can connect but may crash

## TODO: android_wlegl Protocol

For libhybris-based clients to work, Flick needs to implement:
1. Register `android_wlegl` Wayland global
2. Handle `create_handle` - receive gralloc buffer handles
3. Handle `create_buffer` - create wl_buffer from native handles

## Working Commit Reference

Last known working: Current main branch
