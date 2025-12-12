#!/bin/bash
# Flick Installation Script for Mobian (PinePhone/PinePhone Pro)
# This script installs all dependencies and builds Flick from source

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

echo "[1/4] Installing system dependencies..."
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

echo ""
echo "[2/4] Installing Rust toolchain..."
if command -v rustc &> /dev/null; then
    echo "Rust is already installed: $(rustc --version)"
else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

# Ensure cargo is in PATH for this session
export PATH="$HOME/.cargo/bin:$PATH"

echo ""
echo "[3/4] Building Flick shell (this may take 30+ minutes on PinePhone)..."
cd "$FLICK_DIR/shell"
cargo build --release

# Add user to video group if not already
if ! groups | grep -q video; then
    echo ""
    echo "[4/5] Adding user to video group..."
    sudo usermod -aG video "$USER"
    echo "NOTE: You may need to logout/login for group changes to take effect"
fi

echo ""
echo "[5/5] Installation complete!"
echo ""
echo "=== How to run Flick ==="
echo ""
echo "IMPORTANT: Flick must be run from a LOCAL TTY, not over SSH!"
echo ""
echo "Option 1: Run manually from TTY"
echo "  1. Stop display manager: sudo systemctl stop greetd"
echo "  2. Switch to TTY2: sudo chvt 2 (or Ctrl+Alt+F2)"
echo "  3. Login as your user"
echo "  4. Run Flick: $FLICK_DIR/start.sh"
echo ""
echo "Option 2: Install as a session (advanced)"
echo "  Run: $FLICK_DIR/install-session.sh"
echo ""
echo "To switch back to Phosh:"
echo "  sudo systemctl start greetd"
echo "  sudo chvt 7"
echo ""
echo "See MOBIAN.md for detailed instructions and troubleshooting."
echo ""
