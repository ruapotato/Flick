#!/bin/bash
# Flick - Mobile-first Wayland compositor with integrated shell
#
# Usage:
#   ./start.sh              - Run compositor
#   ./start.sh --timeout 10 - Run for 10 seconds then exit

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSITOR_DIR="$SCRIPT_DIR/compositor"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Defaults
TIMEOUT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout|-t)
            TIMEOUT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --timeout, -t SECONDS  Exit after SECONDS (useful for testing)"
            echo "  --help, -h             Show this help"
            echo ""
            echo "The shell UI is integrated into the compositor."
            echo ""
            echo "Gestures:"
            echo "  Swipe up from bottom    - Go home (app grid)"
            echo "  Swipe down from top     - Close current app"
            echo "  Swipe left from right   - App switcher"
            echo "  Swipe right from left   - Back"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Build compositor if needed
cd "$COMPOSITOR_DIR"
if [ ! -f target/release/flick ] || [ Cargo.toml -nt target/release/flick ] || [ -n "$(find src -newer target/release/flick 2>/dev/null)" ]; then
    echo -e "${YELLOW}Building compositor (release)...${NC}"
    cargo build --release
fi

echo -e "${GREEN}Starting Flick compositor...${NC}"
[ -n "$TIMEOUT" ] && echo -e "  Timeout: ${TIMEOUT}s"
echo -e "  Logs: ~/.local/state/flick/compositor.log.*"
echo ""

# Run compositor
if [ -n "$TIMEOUT" ]; then
    timeout "$TIMEOUT" ./target/release/flick || EXIT_CODE=$?
    if [ "$EXIT_CODE" = "124" ]; then
        echo -e "\n${YELLOW}Timeout reached (${TIMEOUT}s)${NC}"
    fi
else
    ./target/release/flick
fi
