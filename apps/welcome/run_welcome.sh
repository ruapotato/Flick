#!/bin/bash
# Run the Welcome tutorial app

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.local/state/flick"
CONFIG_FILE="$CONFIG_DIR/welcome_config.json"

# Create config directory if needed
mkdir -p "$CONFIG_DIR"

# Check if we should show the welcome screen
if [ -f "$CONFIG_FILE" ]; then
    SHOW_ON_STARTUP=$(cat "$CONFIG_FILE" | grep -o '"showOnStartup":[^,}]*' | cut -d: -f2 | tr -d ' ')
    if [ "$SHOW_ON_STARTUP" = "false" ]; then
        echo "Welcome screen disabled, exiting"
        exit 0
    fi
fi

# Run the welcome app and capture output for config changes
cd "$SCRIPT_DIR"
OUTPUT=$(QT_QPA_PLATFORM=wayland QT_WAYLAND_DISABLE_WINDOWDECORATION=1 /usr/lib/qt5/bin/qmlscene main.qml 2>&1)

# Check if we need to save config
if echo "$OUTPUT" | grep -q "WELCOME_CONFIG:"; then
    CONFIG_JSON=$(echo "$OUTPUT" | grep "WELCOME_CONFIG:" | sed 's/.*WELCOME_CONFIG://')
    echo "$CONFIG_JSON" > "$CONFIG_FILE"
    echo "Saved welcome config: $CONFIG_JSON"
fi
