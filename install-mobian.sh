#!/bin/bash
# Flick Installation Script for Mobian (PinePhone/PinePhone Pro)
# This script installs all dependencies, builds Flick, and sets up the systemd service

set -e

echo "=== Flick Installation Script for Mobian ==="
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "Please run this script as a regular user (not root)"
    echo "The script will use sudo when needed"
    exit 1
fi

FLICK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$FLICK_DIR"

echo "[1/6] Installing system dependencies..."
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
    libpresage-dev \
    libpresage-data \
    seatd

echo ""
echo "[2/6] Installing Rust toolchain..."
if command -v rustc &> /dev/null; then
    echo "Rust is already installed: $(rustc --version)"
else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

# Ensure cargo is in PATH for this session
export PATH="$HOME/.cargo/bin:$PATH"

echo ""
echo "[3/6] Building Flick shell (this may take 30+ minutes on PinePhone)..."
cd "$FLICK_DIR/shell"
cargo build --release

echo ""
echo "[4/6] Adding user to video group..."
if ! groups | grep -q video; then
    sudo usermod -aG video "$USER"
    echo "Added $USER to video group"
else
    echo "User already in video group"
fi

echo ""
echo "[5/6] Installing systemd service..."

# Create service file with correct paths
cat > /tmp/flick.service << EOF
[Unit]
Description=Flick Mobile Shell
After=systemd-user-sessions.service seatd.service
Requires=seatd.service
Conflicts=greetd.service phosh.service

[Service]
Type=simple

# Switch VT as root before starting
ExecStartPre=+/usr/bin/chvt 2

# Run Flick directly - it will connect to the existing seatd
ExecStart=$FLICK_DIR/shell/target/release/flick
User=$USER
StandardOutput=journal
StandardError=journal

# Environment for DRM/Wayland
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_CURRENT_DESKTOP=Flick
Environment=XDG_SEAT=seat0
Environment=XDG_VTNR=2
Environment=HOME=$HOME
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u)
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

echo ""
echo "[6/6] Enabling Flick and disabling Phosh..."
sudo systemctl disable greetd 2>/dev/null || true
sudo systemctl enable seatd
sudo systemctl enable flick

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Flick is now installed and will start on next boot."
echo ""
echo "To start Flick now:"
echo "  sudo systemctl stop greetd"
echo "  sudo systemctl start flick"
echo ""
echo "To switch back to Phosh:"
echo "  sudo systemctl stop flick"
echo "  sudo systemctl disable flick"
echo "  sudo systemctl enable greetd"
echo "  sudo systemctl start greetd"
echo ""
echo "View logs with: journalctl -u flick -f"
echo ""
echo "See MOBIAN.md for gestures and troubleshooting."
echo ""
