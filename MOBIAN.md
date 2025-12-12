# Flick on Mobian (PinePhone / PinePhone Pro)

This guide covers installing and running Flick on Mobian Linux for PinePhone and PinePhone Pro.

## Quick Install

```bash
cd ~/Flick
./install-mobian.sh
```

This script will:
1. Install all system dependencies
2. Install Rust if not present
3. Build Flick from source (takes 30-60+ minutes on PinePhone)

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
    libpixman-1-dev
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

Then logout and login for the group change to take effect.

## Running Flick

**IMPORTANT**: Flick must be run from a local TTY, NOT over SSH. The compositor needs direct seat access to the GPU.

### Option 1: Manual Testing (Recommended for first test)

1. On your PinePhone, open a terminal or switch to a TTY (hardware keyboard: Ctrl+Alt+F2)

2. Login as your user

3. Stop the display manager:
   ```bash
   sudo systemctl stop greetd
   sudo systemctl stop phosh  # if running
   ```

4. Run Flick:
   ```bash
   cd ~/Flick
   ./start.sh
   ```

5. To return to Phosh:
   ```bash
   # Press Ctrl+Alt+F1 or kill Flick, then:
   sudo systemctl start greetd
   ```

### Option 2: Install as a Session (Advanced)

You can install Flick as a greetd session to select it from the greeter:

```bash
cd ~/Flick
./install-session.sh
```

Then reboot and select "Flick" from the greeter.

## Gestures

| Gesture | Action |
|---------|--------|
| Swipe up from bottom | Go home / show keyboard (in apps) |
| Swipe down from top | Close current app |
| Swipe right from left edge | Quick Settings panel |
| Swipe left from right edge | App switcher |
| Swipe up from Quick Settings | Return to home |
| Swipe up from App Switcher | Return to home |

## Troubleshooting

### "No usable GPU found" / "Resource temporarily unavailable"

This error occurs when:
1. Another compositor (Phosh/phoc) is still running - make sure to stop greetd
2. You're running over SSH - Flick needs local seat access
3. User not in video group - run `sudo usermod -aG video $USER` and re-login

### Black screen after starting

The PinePhone's display may need a moment to initialize. Wait 5-10 seconds.

### Can't switch back to Phosh

From a TTY or SSH:
```bash
sudo systemctl start greetd
sudo chvt 7
```

## Known Limitations on PinePhone

- Build takes 30-60+ minutes on the PinePhone's A64 SoC
- Some app icons may not load (GNOME symbolic icons)
- First run may take a few seconds to render

## Switching Between Flick and Phosh

Flick and Phosh cannot run simultaneously. To switch:

**From Phosh to Flick:**
```bash
sudo systemctl stop greetd
# Switch to TTY2 using hardware keyboard or:
sudo chvt 2
# Login and run:
~/Flick/start.sh
```

**From Flick to Phosh:**
```bash
# Kill Flick (Ctrl+C if running in terminal)
sudo systemctl start greetd
sudo chvt 7
```
