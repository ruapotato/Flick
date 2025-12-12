# Flick on Mobian (PinePhone / PinePhone Pro)

This guide covers installing and running Flick on Mobian Linux for PinePhone and PinePhone Pro.

## Quick Install

```bash
cd ~/Flick
./install-mobian.sh
```

This script will:
1. Install all system dependencies (including seatd)
2. Install Rust if not present
3. Build Flick from source (takes 30-60+ minutes on PinePhone)
4. Add user to video group
5. Install and enable the Flick systemd service
6. Disable greetd/Phosh

After installation, reboot or run:
```bash
sudo systemctl stop greetd
sudo systemctl start flick
```

## Manual Installation

### 1. Install Dependencies

```bash
sudo apt update
sudo apt install -y \
    git \
    libseat-dev \
    libinput-dev \
    libudev-dev \
    libgbm-dev \
    libegl-dev \
    libdrm-dev \
    libxkbcommon-dev \
    pkg-config \
    libpam0g-dev \
    python3-kivy \
    curl \
    build-essential \
    libdisplay-info-dev \
    libpixman-1-dev \
    seatd
```

### 2. Install Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
```

### 3. Build Flick

```bash
cd ~/Flick/shell
cargo build --release
```

### 4. Add User to Video Group

```bash
sudo usermod -aG video $USER
```

### 5. Install Systemd Service

```bash
sudo ./install-service.sh
```

Or manually copy the service file:
```bash
sudo cp flick.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable seatd
sudo systemctl enable flick
sudo systemctl disable greetd
```

## Running Flick

### Via Systemd (Recommended)

Start Flick:
```bash
sudo systemctl stop greetd    # Stop Phosh first
sudo systemctl start flick
```

View logs:
```bash
journalctl -u flick -f
```

### Manual Testing

If you want to test without the service:

1. Stop any running display manager:
   ```bash
   sudo systemctl stop greetd
   sudo systemctl stop flick
   ```

2. Switch to TTY2:
   ```bash
   sudo chvt 2
   ```

3. Run Flick directly:
   ```bash
   cd ~/Flick
   ./start.sh
   ```

## Gestures

| Gesture | Action |
|---------|--------|
| Swipe up from bottom | Go home / show keyboard (in apps) |
| Swipe down from top | Close current app |
| Swipe right from left edge | Quick Settings panel |
| Swipe left from right edge | App switcher |
| Swipe up from Quick Settings | Return to home |
| Swipe up from App Switcher | Return to home |

## Switching Between Flick and Phosh

**Switch to Phosh:**
```bash
sudo systemctl stop flick
sudo systemctl disable flick
sudo systemctl enable greetd
sudo systemctl start greetd
```

**Switch to Flick:**
```bash
sudo systemctl stop greetd
sudo systemctl disable greetd
sudo systemctl enable flick
sudo systemctl start flick
```

## Troubleshooting

### "No usable GPU found" / "Resource temporarily unavailable"

This error occurs when:
1. Another compositor (Phosh/phoc) is still running - stop greetd first
2. seatd service not running - run `sudo systemctl start seatd`
3. User not in video group - run `sudo usermod -aG video $USER` and reboot

### Service fails to start

Check logs:
```bash
journalctl -u flick -n 50
```

Ensure seatd is running:
```bash
sudo systemctl status seatd
```

### Black screen after starting

The PinePhone's display may need a moment to initialize. Wait 5-10 seconds.

### Can't switch back to Phosh

From SSH:
```bash
sudo systemctl stop flick
sudo systemctl start greetd
sudo chvt 7
```

## Known Limitations on PinePhone

- Build takes 30-60+ minutes on the PinePhone's A64 SoC
- Animations may be slow due to GPU limitations
- Some app icons may not load (GNOME symbolic icons need hicolor fallbacks)
- Settings app toggles are not yet functional
- App switcher animations need optimization

## Files

- `/etc/systemd/system/flick.service` - Systemd service file
- `~/Flick/shell/target/release/flick` - Flick binary
- `~/.local/state/flick/` - Logs and state files
