#!/bin/bash
# Flick - Start compositor and shell
#
# Usage:
#   ./start.sh              - Run compositor with shell
#   ./start.sh --timeout 10 - Run for 10 seconds then exit
#   ./start.sh --shell foot - Use foot instead of flick_shell

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSITOR_DIR="$SCRIPT_DIR/compositor"
SHELL_QML="$SCRIPT_DIR/shell-qml/run.sh"
SHELL_FLUTTER="$SCRIPT_DIR/shell/build/linux/x64/release/bundle/flick_shell"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Defaults
TIMEOUT=""
SHELL_CMD=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout|-t)
            TIMEOUT="$2"
            shift 2
            ;;
        --shell|-s)
            SHELL_CMD="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --timeout, -t SECONDS  Exit after SECONDS (useful for testing)"
            echo "  --shell, -s COMMAND    Shell command to run (default: flick_shell)"
            echo "  --help, -h             Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                     # Run with flick_shell"
            echo "  $0 --timeout 10        # Run for 10 seconds"
            echo "  $0 --shell foot        # Run with foot terminal"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Determine shell to use
if [ -z "$SHELL_CMD" ]; then
    if [ -x "$SHELL_QML" ]; then
        SHELL_CMD="$SHELL_QML"
        echo -e "${GREEN}Using QML shell${NC}"
    elif [ -f "$SHELL_FLUTTER" ]; then
        SHELL_CMD="$SHELL_FLUTTER"
        echo -e "${YELLOW}Using Flutter shell (fallback)${NC}"
    else
        echo -e "${YELLOW}No shell found, using foot as fallback${NC}"
        SHELL_CMD="foot"
    fi
fi

# Build compositor if needed
cd "$COMPOSITOR_DIR"
if [ ! -f target/release/flick ] || [ Cargo.toml -nt target/release/flick ] || [ -n "$(find src -newer target/release/flick 2>/dev/null)" ]; then
    echo -e "${YELLOW}Building compositor (release)...${NC}"
    cargo build --release
fi

echo -e "${GREEN}Starting Flick compositor...${NC}"
echo -e "  Shell: $SHELL_CMD"
[ -n "$TIMEOUT" ] && echo -e "  Timeout: ${TIMEOUT}s"
echo -e "  Logs: ~/.local/state/flick/compositor.log.*"
echo ""

# Run compositor
if [ -n "$TIMEOUT" ]; then
    timeout "$TIMEOUT" cargo run --release -- --shell "$SHELL_CMD" || EXIT_CODE=$?
    if [ "$EXIT_CODE" = "124" ]; then
        echo -e "\n${YELLOW}Timeout reached (${TIMEOUT}s)${NC}"
    fi
else
    cargo run --release -- --shell "$SHELL_CMD"
fi
