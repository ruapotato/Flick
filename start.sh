#!/bin/bash
# Start script for Flick compositor testing

set -e

SCRIPT_DIR="$(dirname "$0")"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/flick-$(date +%Y%m%d-%H%M%S).log"
TIMEOUT=0
VERBOSE=""

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --timeout N    Kill compositor after N seconds"
    echo "  -v, --verbose  Enable verbose logging"
    echo "  -h, --help     Show this help"
    echo ""
    echo "Logs are saved to: $LOG_DIR/"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE="-v"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

cd "$SCRIPT_DIR/flick-wlroots"

# Build if needed
if [ ! -f build/flick ] || [ Makefile -nt build/flick ]; then
    echo "Building flick..."
    make
fi

# Create log directory
mkdir -p "$LOG_DIR"

echo "Starting Flick compositor..."
echo "Log file: $LOG_FILE"
if [ "$TIMEOUT" -gt 0 ] 2>/dev/null; then
    echo "Timeout: ${TIMEOUT}s"
fi

# Run the compositor with logging
if [ "$TIMEOUT" -gt 0 ] 2>/dev/null; then
    # Run with timeout
    timeout --signal=TERM "$TIMEOUT" ./build/flick $VERBOSE 2>&1 | tee "$LOG_FILE"
    EXIT_CODE=${PIPESTATUS[0]}
    if [ $EXIT_CODE -eq 124 ]; then
        echo ""
        echo "=== Compositor terminated after ${TIMEOUT}s timeout ==="
    fi
else
    # Run without timeout
    ./build/flick $VERBOSE 2>&1 | tee "$LOG_FILE"
fi

echo ""
echo "Log saved to: $LOG_FILE"
