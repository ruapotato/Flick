#!/bin/bash
# Flick Terminal - First-party terminal for Flick shell
# Reads text_scale from Flick settings

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${HOME}/.local/state/flick"
LOG_FILE="${STATE_DIR}/terminal.log"

mkdir -p "$STATE_DIR"

echo "=== Flick Terminal started at $(date) ===" >> "$LOG_FILE"

# Run the terminal
exec qmlscene "$SCRIPT_DIR/main.qml" 2>> "$LOG_FILE"
