#!/bin/bash
# Flick Installation Script
# Supports Droidian (hwcomposer) and Mobian/standard Linux (DRM)
#
# Usage: ./install.sh [--no-build] [--no-enable]
#   --no-build   Skip building (use existing binary)
#   --no-enable  Don't enable on boot, just install

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="$SCRIPT_DIR/config/systemd"

# Parse arguments
NO_BUILD=false
NO_ENABLE=false
for arg in "$@"; do
    case $arg in
        --no-build) NO_BUILD=true ;;
        --no-enable) NO_ENABLE=true ;;
    esac
done

# Detect platform
detect_platform() {
    if [ -f /etc/droidian-release ] || grep -qi droidian /etc/os-release 2>/dev/null; then
        echo "droidian"
    elif [ -f /etc/mobian-release ] || grep -qi mobian /etc/os-release 2>/dev/null; then
        echo "mobian"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

PLATFORM=$(detect_platform)

echo "========================================"
echo "  Flick Installation Script"
echo "========================================"
echo ""
echo "Platform detected: $PLATFORM"
echo "Install directory: $SCRIPT_DIR"
echo ""

# Check if running as correct user
if [ "$PLATFORM" = "droidian" ]; then
    if [ "$EUID" -ne 0 ]; then
        echo "On Droidian, please run as root: sudo $0"
        exit 1
    fi
    INSTALL_USER="droidian"
    INSTALL_UID=$(id -u droidian 2>/dev/null || echo "32011")
    INSTALL_HOME=$(getent passwd droidian | cut -d: -f6)
else
    if [ "$EUID" -eq 0 ]; then
        echo "Please run as a regular user (not root)"
        echo "The script will use sudo when needed"
        exit 1
    fi
    INSTALL_USER="$USER"
    INSTALL_UID=$(id -u)
    INSTALL_HOME="$HOME"
fi

echo "User: $INSTALL_USER (UID: $INSTALL_UID)"
echo "Home: $INSTALL_HOME"
echo ""

#######################################
# Step 1: Install Dependencies
#######################################
echo "[1/5] Installing dependencies..."

if [ "$PLATFORM" = "droidian" ]; then
    # Droidian uses hwcomposer, minimal deps needed
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
        libpixman-1-dev
else
    # Mobian/Debian needs DRM/seatd dependencies
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
# Step 2: Install Rust
#######################################
echo ""
echo "[2/5] Checking Rust toolchain..."

# For Droidian, check as the droidian user
if [ "$PLATFORM" = "droidian" ]; then
    if sudo -u droidian bash -c 'source ~/.cargo/env 2>/dev/null; command -v rustc' &>/dev/null; then
        RUST_VER=$(sudo -u droidian bash -c 'source ~/.cargo/env; rustc --version')
        echo "Rust is already installed: $RUST_VER"
    else
        echo "Installing Rust for droidian user..."
        sudo -u droidian bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
    fi
else
    if command -v rustc &>/dev/null; then
        echo "Rust is already installed: $(rustc --version)"
    else
        echo "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi
fi

#######################################
# Step 3: Build Flick
#######################################
echo ""
echo "[3/5] Building Flick shell..."

if [ "$NO_BUILD" = true ]; then
    echo "Skipping build (--no-build specified)"
    if [ ! -f "$SCRIPT_DIR/shell/target/release/flick" ]; then
        echo "ERROR: No existing binary found at $SCRIPT_DIR/shell/target/release/flick"
        exit 1
    fi
else
    cd "$SCRIPT_DIR/shell"
    if [ "$PLATFORM" = "droidian" ]; then
        echo "Building as droidian user (this may take 30+ minutes)..."
        sudo -u droidian bash -c 'source ~/.cargo/env && cargo build --release'
    else
        export PATH="$HOME/.cargo/bin:$PATH"
        echo "Building (this may take 30+ minutes on ARM)..."
        cargo build --release
    fi
fi

cd "$SCRIPT_DIR"

# Verify binary exists
if [ ! -f "$SCRIPT_DIR/shell/target/release/flick" ]; then
    echo "ERROR: Build failed - binary not found"
    exit 1
fi
echo "Binary built: $SCRIPT_DIR/shell/target/release/flick"

#######################################
# Step 4: Setup Permissions & State
#######################################
echo ""
echo "[4/5] Setting up permissions..."

# Create and fix state directory
STATE_DIR="$INSTALL_HOME/.local/state/flick"
if [ "$PLATFORM" = "droidian" ]; then
    mkdir -p "$STATE_DIR"
    chown -R droidian:droidian "$STATE_DIR" 2>/dev/null || true
    chown -R droidian:droidian "$INSTALL_HOME/.local/state" 2>/dev/null || true
else
    mkdir -p "$STATE_DIR"
    # Add user to video group for DRM access
    if ! groups "$INSTALL_USER" | grep -q video; then
        sudo usermod -aG video "$INSTALL_USER"
        echo "Added $INSTALL_USER to video group"
    fi
fi

#######################################
# Step 5: Install Systemd Services
#######################################
echo ""
echo "[5/5] Installing systemd services..."

if [ "$PLATFORM" = "droidian" ]; then
    # Droidian: hwcomposer backend, multiple services
    mkdir -p "$SERVICE_DIR"

    # Create flick.service
    cat > /etc/systemd/system/flick.service << EOF
[Unit]
Description=Flick Mobile Shell
Documentation=https://github.com/anthropics/flick
After=phosh.service
After=lxc@android.service
After=dbus.socket
Wants=user-runtime-dir@$INSTALL_UID.service
After=user-runtime-dir@$INSTALL_UID.service
Conflicts=phosh.service

[Service]
Type=simple
# Run as root - compositor needs root for hwcomposer, drops privileges for spawned apps
User=root
Group=root

Environment=XDG_RUNTIME_DIR=/run/user/$INSTALL_UID
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_CURRENT_DESKTOP=Flick
Environment=EGL_PLATFORM=hwcomposer
Environment=HOME=$INSTALL_HOME

# Wait for Android container to stabilize
ExecStartPre=/bin/sleep 3

# Ensure state directory exists and has correct permissions
ExecStartPre=/bin/mkdir -p $INSTALL_HOME/.local/state/flick
ExecStartPre=/bin/chown -R droidian:droidian $INSTALL_HOME/.local/state/flick

# Restart hwcomposer (required after Phosh releases it)
ExecStartPre=/bin/sh -c 'ANDROID_SERVICE="(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)" /usr/lib/halium-wrappers/android-service.sh hwcomposer stop || true'
ExecStartPre=/bin/sleep 2
ExecStartPre=/bin/sh -c 'ANDROID_SERVICE="(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)" /usr/lib/halium-wrappers/android-service.sh hwcomposer start'
ExecStartPre=/bin/sleep 1

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
Documentation=https://github.com/anthropics/flick
After=ofono.service
BindsTo=flick.service
After=flick.service

[Service]
Type=simple
User=root

ExecStartPre=/bin/rm -f /tmp/flick_phone_status /tmp/flick_phone_cmd
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
Documentation=https://github.com/anthropics/flick
After=dbus.socket
BindsTo=flick.service
After=flick.service

[Service]
Type=simple
User=droidian
Group=droidian

Environment=XDG_RUNTIME_DIR=/run/user/$INSTALL_UID
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$INSTALL_UID/bus

ExecStart=/usr/bin/python3 $SCRIPT_DIR/apps/messages/messaging_daemon.py daemon

StandardOutput=journal
StandardError=journal
SyslogIdentifier=flick-messaging

Restart=on-failure
RestartSec=5

[Install]
WantedBy=flick.service
EOF

    systemctl daemon-reload

    if [ "$NO_ENABLE" = false ]; then
        echo "Enabling Flick services..."
        systemctl disable phosh 2>/dev/null || true
        systemctl enable flick flick-phone-helper flick-messaging
    fi

    echo ""
    echo "========================================"
    echo "  Installation Complete (Droidian)"
    echo "========================================"
    echo ""
    echo "Services installed:"
    echo "  - flick.service (main compositor)"
    echo "  - flick-phone-helper.service (phone daemon)"
    echo "  - flick-messaging.service (SMS daemon)"
    echo ""
    if [ "$NO_ENABLE" = false ]; then
        echo "Flick is enabled and will start on next boot."
        echo ""
    fi
    echo "To start Flick now:"
    echo "  sudo systemctl stop phosh"
    echo "  sudo systemctl start flick flick-phone-helper flick-messaging"
    echo ""
    echo "To switch back to Phosh:"
    echo "  sudo systemctl stop flick flick-phone-helper flick-messaging"
    echo "  sudo systemctl disable flick flick-phone-helper flick-messaging"
    echo "  sudo systemctl enable phosh"
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
Environment=XDG_RUNTIME_DIR=/run/user/$INSTALL_UID
Environment=LIBSEAT_BACKEND=seatd

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
        echo "Enabling Flick and seatd..."
        sudo systemctl disable greetd 2>/dev/null || true
        sudo systemctl enable seatd
        sudo systemctl enable flick
    fi

    echo ""
    echo "========================================"
    echo "  Installation Complete (Mobian/Debian)"
    echo "========================================"
    echo ""
    if [ "$NO_ENABLE" = false ]; then
        echo "Flick is enabled and will start on next boot."
        echo ""
    fi
    echo "To start Flick now:"
    echo "  sudo systemctl stop greetd"
    echo "  sudo systemctl start flick"
    echo ""
    echo "To switch back to Phosh/greetd:"
    echo "  sudo systemctl stop flick"
    echo "  sudo systemctl disable flick"
    echo "  sudo systemctl enable greetd"
    echo "  sudo systemctl start greetd"
fi

echo ""
echo "View logs: journalctl -u flick -f"
echo ""
