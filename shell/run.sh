#!/bin/bash
# Flick Compositor Development Runner
#
# Usage:
#   ./run.sh                    - Run on real hardware (DRM/libinput)
#   ./run.sh --windowed         - Run in a window (requires X11/Wayland)
#   ./run.sh --windowed --shell "foot"  - Run windowed with a shell

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Build if needed
if [ ! -f target/debug/flick ] || [ Cargo.toml -nt target/debug/flick ] || [ -n "$(find src -newer target/debug/flick 2>/dev/null)" ]; then
    echo -e "${YELLOW}Building compositor...${NC}"
    cargo build
fi

echo -e "${GREEN}Starting Flick compositor...${NC}"

# Pass all arguments to the compositor
exec cargo run -- "$@"
