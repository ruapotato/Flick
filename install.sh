#!/bin/bash
# Flick Installation Script
# Supports multiple devices via config system
#
# Usage: ./install.sh [options]
#   --device <name>  Use specific device config (default: auto-detect or flx1s)
#   --no-build       Skip building (use existing binary)
#   --no-enable      Don't enable on boot, just install
#   --list-devices   List available device configurations
#   --help           Show this help

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICES_DIR="$SCRIPT_DIR/config/devices"
CONFIG_INSTALL_DIR="/etc/flick"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[FLICK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Parse arguments
NO_BUILD=false
NO_ENABLE=false
DEVICE_CONFIG=""
for arg in "$@"; do
    case $arg in
        --no-build) NO_BUILD=true ;;
        --no-enable) NO_ENABLE=true ;;
        --device=*) DEVICE_CONFIG="${arg#*=}" ;;
        --list-devices)
            echo "Available device configurations:"
            for f in "$DEVICES_DIR"/*.conf; do
                [ -f "$f" ] || continue
                name=$(basename "$f" .conf)
                desc=$(grep "^DEVICE_NAME=" "$f" | cut -d'"' -f2)
                echo "  $name - $desc"
            done
            exit 0
            ;;
        --help)
            echo "Flick Installation Script"
            echo ""
            echo "Usage: ./install.sh [options]"
            echo ""
            echo "Options:"
            echo "  --device=<name>  Use specific device config (default: flx1s)"
            echo "  --no-build       Skip building (use existing binary)"
            echo "  --no-enable      Don't enable services on boot"
            echo "  --list-devices   List available device configurations"
            echo "  --help           Show this help"
            echo ""
            echo "Examples:"
            echo "  ./install.sh                    # Install with auto-detected or default config"
            echo "  ./install.sh --device=pixel3a   # Install using Pixel 3a config"
            echo "  ./install.sh --no-build         # Install without rebuilding"
            exit 0
            ;;
    esac
done

# Detect platform
detect_platform() {
    if [ -f /etc/droidian-release ] || grep -qi droidian /etc/os-release 2>/dev/null; then
        echo "droidian"
    elif [ -f /etc/furios-release ] || grep -qi furios /etc/os-release 2>/dev/null; then
        echo "droidian"  # FuriOS is Droidian-based
    elif [ -f /etc/mobian-release ] || grep -qi mobian /etc/os-release 2>/dev/null; then
        echo "mobian"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# Auto-detect device config based on current system
auto_detect_device() {
    # Check if there's an existing config
    if [ -f "$CONFIG_INSTALL_DIR/device.conf" ]; then
        grep "^DEVICE_CODENAME=" "$CONFIG_INSTALL_DIR/device.conf" | cut -d'"' -f2
        return
    fi

    # Check for known device indicators
    if [ -f /etc/furios-release ] || [ -d /home/furios ]; then
        echo "flx1s"
    elif [ -d /home/droidian ]; then
        # Could be any Droidian device - check hardware
        if grep -qi "sargo\|Pixel 3a" /proc/device-tree/model 2>/dev/null; then
            echo "pixel3a"
        else
            echo "pixel3a"  # Default to pixel3a for unknown Droidian
        fi
    elif [ -d /home/mobian ]; then
        echo "pinephone"
    else
        echo "flx1s"  # Default
    fi
}

PLATFORM=$(detect_platform)

# Select device config
if [ -z "$DEVICE_CONFIG" ]; then
    DEVICE_CONFIG=$(auto_detect_device)
fi

DEVICE_CONF_FILE="$DEVICES_DIR/$DEVICE_CONFIG.conf"
if [ ! -f "$DEVICE_CONF_FILE" ]; then
    error "Device config not found: $DEVICE_CONF_FILE\nRun --list-devices to see available configs"
fi

# Load device config
source "$DEVICE_CONF_FILE"

echo ""
echo "========================================"
echo "  Flick Installation Script"
echo "========================================"
echo ""
log "Platform: $PLATFORM"
log "Device: $DEVICE_NAME ($DEVICE_CODENAME)"
log "Install directory: $SCRIPT_DIR"
echo ""

# Validate we have the required config values
[ -z "$DEVICE_USER" ] && error "DEVICE_USER not set in config"
[ -z "$DEVICE_UID" ] && error "DEVICE_UID not set in config"
[ -z "$DEVICE_HOME" ] && error "DEVICE_HOME not set in config"

# Set install variables from config
INSTALL_USER="$DEVICE_USER"
INSTALL_UID="$DEVICE_UID"
INSTALL_HOME="$DEVICE_HOME"

# Check if running as correct user
if [ "$DEVICE_PLATFORM" = "droidian" ]; then
    if [ "$EUID" -ne 0 ]; then
        error "On Droidian/hwcomposer systems, please run as root: sudo $0 $*"
    fi
else
    if [ "$EUID" -eq 0 ]; then
        error "Please run as a regular user (not root)\nThe script will use sudo when needed"
    fi
fi

# Check if target user exists
if ! id "$INSTALL_USER" &>/dev/null; then
    warn "User '$INSTALL_USER' does not exist"
    info "Creating user or using current user..."
    if [ "$EUID" -eq 0 ]; then
        INSTALL_USER=$(who | head -1 | awk '{print $1}')
        [ -z "$INSTALL_USER" ] && INSTALL_USER="root"
    else
        INSTALL_USER="$USER"
    fi
    INSTALL_UID=$(id -u "$INSTALL_USER")
    INSTALL_HOME=$(getent passwd "$INSTALL_USER" | cut -d: -f6)
    warn "Using user: $INSTALL_USER (UID: $INSTALL_UID)"
fi

log "User: $INSTALL_USER (UID: $INSTALL_UID)"
log "Home: $INSTALL_HOME"
echo ""

#######################################
# Step 1: Install Dependencies
#######################################
log "[1/6] Installing system dependencies..."

if [ "$DEVICE_PLATFORM" = "droidian" ]; then
    apt update
    apt install -y \
        python3 \
        python3-dbus \
        python3-gi \
        curl \
        build-essential \
        pkg-config \
        libpam0g-dev \
        libxkbcommon-dev \
        libpixman-1-dev \
        libudev-dev \
        libseat-dev \
        libinput-dev \
        libgbm-dev \
        libegl-dev \
        libdrm-dev \
        libdisplay-info-dev \
        qmlscene \
        qml-module-qtquick2 \
        qml-module-qtquick-window2 \
        qml-module-qtquick-controls2
else
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
        python3 \
        python3-dbus \
        curl \
        build-essential \
        libdisplay-info-dev \
        libpixman-1-dev \
        seatd
fi

#######################################
# Step 2: Install Rust/Cargo
#######################################
echo ""
log "[2/6] Checking Rust/Cargo toolchain..."

install_rust() {
    local target_user="$1"
    local target_home="$2"

    log "Installing Rust for $target_user..."
    if [ "$target_user" = "root" ] || [ "$EUID" -eq 0 ] && [ "$target_user" != "$USER" ]; then
        sudo -u "$target_user" bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
    else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi
}

check_rust() {
    local target_user="$1"
    local target_home="$2"

    if [ "$target_user" = "root" ] || ([ "$EUID" -eq 0 ] && [ "$target_user" != "root" ]); then
        sudo -u "$target_user" bash -c "source $target_home/.cargo/env 2>/dev/null; command -v cargo" &>/dev/null
    else
        command -v cargo &>/dev/null || ([ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env" && command -v cargo &>/dev/null)
    fi
}

# Check and install Rust
if [ "$DEVICE_PLATFORM" = "droidian" ]; then
    if check_rust "$INSTALL_USER" "$INSTALL_HOME"; then
        RUST_VER=$(sudo -u "$INSTALL_USER" bash -c "source $INSTALL_HOME/.cargo/env 2>/dev/null; rustc --version")
        log "Rust already installed: $RUST_VER"
    else
        warn "Cargo not found for $INSTALL_USER"
        install_rust "$INSTALL_USER" "$INSTALL_HOME"
        log "Rust installed successfully"
    fi
else
    if check_rust "$USER" "$HOME"; then
        log "Rust already installed: $(rustc --version)"
    else
        warn "Cargo not found"
        install_rust "$USER" "$HOME"
        log "Rust installed successfully"
    fi
fi

#######################################
# Step 3: Build Flick
#######################################
echo ""
log "[3/6] Building Flick shell..."

if [ "$NO_BUILD" = true ]; then
    info "Skipping build (--no-build specified)"
    if [ ! -f "$SCRIPT_DIR/shell/target/release/flick" ]; then
        error "No existing binary found at $SCRIPT_DIR/shell/target/release/flick"
    fi
else
    cd "$SCRIPT_DIR/shell"
    if [ "$DEVICE_PLATFORM" = "droidian" ]; then
        log "Building as $INSTALL_USER (this may take 30+ minutes on ARM)..."
        sudo -u "$INSTALL_USER" bash -c "source $INSTALL_HOME/.cargo/env && cargo build --release"
    else
        export PATH="$HOME/.cargo/bin:$PATH"
        log "Building (this may take 30+ minutes on ARM)..."
        cargo build --release
    fi
fi

cd "$SCRIPT_DIR"

if [ ! -f "$SCRIPT_DIR/shell/target/release/flick" ]; then
    error "Build failed - binary not found"
fi
log "Binary built: $SCRIPT_DIR/shell/target/release/flick"

#######################################
# Step 4: Setup Permissions & State
#######################################
echo ""
log "[4/6] Setting up permissions and state directories..."

# Create state directory
STATE_DIR="$INSTALL_HOME/.local/state/flick"
DATA_DIR="$INSTALL_HOME/.local/share/flick"

if [ "$DEVICE_PLATFORM" = "droidian" ]; then
    mkdir -p "$STATE_DIR" "$DATA_DIR/logs"
    chown -R "$INSTALL_USER:$INSTALL_USER" "$STATE_DIR" 2>/dev/null || true
    chown -R "$INSTALL_USER:$INSTALL_USER" "$DATA_DIR" 2>/dev/null || true
    chown -R "$INSTALL_USER:$INSTALL_USER" "$INSTALL_HOME/.local/state" 2>/dev/null || true
    chown -R "$INSTALL_USER:$INSTALL_USER" "$INSTALL_HOME/.local/share" 2>/dev/null || true
else
    mkdir -p "$STATE_DIR" "$DATA_DIR/logs"
    if ! groups "$INSTALL_USER" | grep -q video; then
        sudo usermod -aG video "$INSTALL_USER"
        log "Added $INSTALL_USER to video group"
    fi
fi

# Install device config to /etc/flick
if [ "$DEVICE_PLATFORM" = "droidian" ]; then
    mkdir -p "$CONFIG_INSTALL_DIR"
    cp "$DEVICE_CONF_FILE" "$CONFIG_INSTALL_DIR/device.conf"
    log "Device config installed to $CONFIG_INSTALL_DIR/device.conf"
else
    sudo mkdir -p "$CONFIG_INSTALL_DIR"
    sudo cp "$DEVICE_CONF_FILE" "$CONFIG_INSTALL_DIR/device.conf"
    log "Device config installed to $CONFIG_INSTALL_DIR/device.conf"
fi

#######################################
# Step 5: Stop Phosh (don't disable)
#######################################
echo ""
log "[5/6] Preparing display environment..."

# Only stop Phosh, don't disable or mask it
# This keeps Phosh available as a fallback
if systemctl is-active --quiet phosh 2>/dev/null; then
    info "Stopping Phosh (keeping it available as fallback)..."
    if [ "$DEVICE_PLATFORM" = "droidian" ]; then
        systemctl stop phosh 2>/dev/null || true
    else
        sudo systemctl stop phosh 2>/dev/null || true
    fi
fi

#######################################
# Step 6: Install Systemd Services
#######################################
echo ""
log "[6/6] Installing systemd services..."

if [ "$DEVICE_PLATFORM" = "droidian" ]; then
    # Droidian: hwcomposer backend, multiple services

    # Create flick.service
    cat > /etc/systemd/system/flick.service << EOF
[Unit]
Description=Flick Mobile Shell
Documentation=https://github.com/ruapotato/Flick
After=phosh.service
After=lxc@android.service
After=dbus.socket
# Conflict but don't disable - allows easy switching back
Conflicts=phosh.service

[Service]
Type=simple
User=root
Group=root

RuntimeDirectory=flick
RuntimeDirectoryMode=0755
Environment=XDG_RUNTIME_DIR=$FLICK_RUNTIME_DIR
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_CURRENT_DESKTOP=Flick
Environment=EGL_PLATFORM=$EGL_PLATFORM
Environment=HOME=$INSTALL_HOME
Environment=FLICK_DEVICE=$DEVICE_CODENAME
Environment=FLICK_USER=$INSTALL_USER

# Wait for Android container if required
ExecStartPre=/bin/sh -c '[ "$ANDROID_CONTAINER" != "true" ] && exit 0; for i in \$(seq 1 $ANDROID_BOOT_WAIT); do if [ "\$(getprop sys.boot_completed)" = "1" ]; then exit 0; fi; sleep 1; done; echo "Android container not ready, continuing anyway"'

# Kill any lingering Wayland clients
ExecStartPre=-/usr/bin/pkill -9 qmlscene
ExecStartPre=-/usr/bin/pkill -9 Xwayland
ExecStartPre=/bin/sleep 1

# Ensure state directory exists
ExecStartPre=/bin/mkdir -p $INSTALL_HOME/.local/state/flick
ExecStartPre=/bin/chown -R $INSTALL_USER:$INSTALL_USER $INSTALL_HOME/.local/state/flick

# Start hwcomposer
ExecStartPre=/bin/sh -c '[ "$ANDROID_CONTAINER" != "true" ] && exit 0; ANDROID_SERVICE="$HWCOMPOSER_SERVICE" /usr/lib/halium-wrappers/android-service.sh hwcomposer start || true'
ExecStartPre=/bin/sleep 2

ExecStart=$SCRIPT_DIR/shell/target/release/flick

StandardOutput=journal
StandardError=journal
SyslogIdentifier=flick

Restart=on-failure
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    # Create flick-phone-helper.service
    cat > /etc/systemd/system/flick-phone-helper.service << EOF
[Unit]
Description=Flick Phone Helper Daemon
Documentation=https://github.com/ruapotato/Flick
After=ofono.service
BindsTo=flick.service
After=flick.service

[Service]
Type=simple
User=root

Environment=FLICK_USER=$INSTALL_USER
Environment=FLICK_HOME=$INSTALL_HOME
Environment=FLICK_DEVICE=$DEVICE_CODENAME

ExecStartPre=/bin/rm -f /tmp/flick_phone_status /tmp/flick_phone_cmd
ExecStartPre=-/bin/sh -c '[ "$MODEM_FORCE_2G_CALLS" = "true" ] && sleep 5 && mmcli -m 0 --set-allowed-modes="2g" || true'
ExecStart=/usr/bin/python3 $SCRIPT_DIR/apps/phone/phone_helper.py daemon

StandardOutput=journal
StandardError=journal
SyslogIdentifier=flick-phone

Restart=on-failure
RestartSec=5

[Install]
WantedBy=flick.service
EOF

    # Create flick-messaging.service
    cat > /etc/systemd/system/flick-messaging.service << EOF
[Unit]
Description=Flick Messaging Daemon
Documentation=https://github.com/ruapotato/Flick
After=dbus.socket
BindsTo=flick.service
After=flick.service

[Service]
Type=simple
User=$INSTALL_USER
Group=$INSTALL_USER

Environment=XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
Environment=FLICK_USER=$INSTALL_USER
Environment=FLICK_HOME=$INSTALL_HOME

ExecStart=/usr/bin/python3 $SCRIPT_DIR/apps/messages/messaging_daemon.py daemon

StandardOutput=journal
StandardError=journal
SyslogIdentifier=flick-messaging

Restart=on-failure
RestartSec=5

[Install]
WantedBy=flick.service
EOF

    # Create flick-audio-keepalive.service (only if needed)
    if [ "$AUDIO_KEEPALIVE" = "true" ]; then
        cat > /etc/systemd/system/flick-audio-keepalive.service << EOF
[Unit]
Description=Flick Audio Keepalive
After=pulseaudio.service user@$INSTALL_UID.service
Wants=user@$INSTALL_UID.service
BindsTo=flick.service
After=flick.service

[Service]
Type=simple
User=$INSTALL_USER
Group=$INSTALL_USER
Environment=XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR

ExecStartPre=/bin/sh -c 'for i in \$(seq 1 60); do [ -S $XDG_RUNTIME_DIR/pulse/native ] && exit 0; sleep 1; done; echo "PulseAudio not ready"; exit 1'
ExecStart=/usr/bin/pacat --playback /dev/zero --rate=44100 --channels=2 --format=s16le --latency-msec=1000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=flick.service
EOF
    fi

    # Disable PulseAudio suspend-on-idle
    mkdir -p /etc/pulse/default.pa.d
    cat > /etc/pulse/default.pa.d/no-suspend.pa << EOF
# Disable suspend-on-idle for Droidian audio stability
.nofail
unload-module module-suspend-on-idle
EOF

    systemctl daemon-reload

    if [ "$NO_ENABLE" = false ]; then
        log "Enabling Flick services..."
        # Don't disable phosh - just enable flick
        systemctl enable flick flick-phone-helper flick-messaging
        [ "$AUDIO_KEEPALIVE" = "true" ] && systemctl enable flick-audio-keepalive
    fi

    echo ""
    echo "========================================"
    echo "  Installation Complete ($DEVICE_NAME)"
    echo "========================================"
    echo ""
    log "Services installed:"
    echo "  - flick.service (main compositor)"
    echo "  - flick-phone-helper.service (phone daemon)"
    echo "  - flick-messaging.service (SMS daemon)"
    [ "$AUDIO_KEEPALIVE" = "true" ] && echo "  - flick-audio-keepalive.service (audio fix)"
    echo ""
    if [ "$NO_ENABLE" = false ]; then
        info "Flick is enabled and will start on next boot."
        echo ""
    fi
    log "To start Flick now:"
    echo "  sudo systemctl stop phosh"
    echo "  sudo systemctl start flick flick-phone-helper flick-messaging"
    echo ""
    log "To switch back to Phosh:"
    echo "  sudo systemctl stop flick flick-phone-helper flick-messaging"
    echo "  sudo systemctl start phosh"

else
    # Mobian/Debian: DRM backend with seatd
    cat > /tmp/flick.service << EOF
[Unit]
Description=Flick Mobile Shell
After=systemd-user-sessions.service seatd.service
Requires=seatd.service
Conflicts=greetd.service phosh.service

[Service]
Type=simple
ExecStartPre=+/usr/bin/chvt 2
ExecStart=$SCRIPT_DIR/shell/target/release/flick
User=$INSTALL_USER
StandardOutput=journal
StandardError=journal

Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_CURRENT_DESKTOP=Flick
Environment=XDG_SEAT=seat0
Environment=XDG_VTNR=2
Environment=HOME=$INSTALL_HOME
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR
Environment=LIBSEAT_BACKEND=seatd
Environment=FLICK_DEVICE=$DEVICE_CODENAME
Environment=FLICK_USER=$INSTALL_USER

Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical.target
Alias=display-manager.service
EOF

    sudo cp /tmp/flick.service /etc/systemd/system/flick.service
    rm /tmp/flick.service
    sudo systemctl daemon-reload

    if [ "$NO_ENABLE" = false ]; then
        log "Enabling Flick and seatd..."
        sudo systemctl enable seatd
        sudo systemctl enable flick
    fi

    echo ""
    echo "========================================"
    echo "  Installation Complete ($DEVICE_NAME)"
    echo "========================================"
    echo ""
    if [ "$NO_ENABLE" = false ]; then
        info "Flick is enabled and will start on next boot."
        echo ""
    fi
    log "To start Flick now:"
    echo "  sudo systemctl stop greetd phosh 2>/dev/null"
    echo "  sudo systemctl start flick"
    echo ""
    log "To switch back to Phosh/greetd:"
    echo "  sudo systemctl stop flick"
    echo "  sudo systemctl start phosh"
fi

echo ""
log "Device config: $CONFIG_INSTALL_DIR/device.conf"
log "View logs: journalctl -u flick -f"
echo ""
