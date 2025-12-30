#!/bin/bash
# Initialize Flick shell configuration with native app defaults
# Run this on first install to set up all Flick apps as defaults

set -e

# Determine the user's home directory
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    USER_HOME="/home/$SUDO_USER"
elif [ -n "$FLICK_USER" ] && [ "$FLICK_USER" != "root" ]; then
    USER_HOME="/home/$FLICK_USER"
elif [ -d "/home/droidian" ]; then
    USER_HOME="/home/droidian"
else
    USER_HOME="$HOME"
fi

# Find the Flick shell directory (where this script and config/apps.json live)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_JSON="$SCRIPT_DIR/config/apps.json"

if [ ! -f "$APPS_JSON" ]; then
    echo "Error: Cannot find $APPS_JSON"
    echo "Make sure this script is in the Flick/shell directory"
    exit 1
fi

# Config output location
CONFIG_DIR="$USER_HOME/.local/state/flick"
CONFIG_FILE="$CONFIG_DIR/app_config.json"

echo "Initializing Flick configuration..."
echo "  User home: $USER_HOME"
echo "  Apps config: $APPS_JSON"
echo "  Output: $CONFIG_FILE"

# Create config directory
mkdir -p "$CONFIG_DIR"

# Check if jq is available for JSON processing
if command -v jq &> /dev/null; then
    # Use jq for proper JSON handling
    echo "Using jq for JSON processing..."

    # Extract category IDs and default_exec values
    SELECTIONS=$(jq -c '[.categories[] | {(.id): .default_exec}] | add' "$APPS_JSON")
    GRID_ORDER=$(jq -c '[.categories[].id]' "$APPS_JSON")

    # Create the config file
    jq -n --argjson selections "$SELECTIONS" --argjson grid_order "$GRID_ORDER" \
        '{selections: $selections, grid_order: $grid_order}' > "$CONFIG_FILE"
else
    # Fallback: use Python for JSON processing
    if command -v python3 &> /dev/null; then
        echo "Using Python for JSON processing..."
        python3 << EOF
import json
import os

apps_json = "$APPS_JSON"
config_file = "$CONFIG_FILE"

with open(apps_json, 'r') as f:
    apps = json.load(f)

config = {
    "selections": {},
    "grid_order": []
}

for cat in apps["categories"]:
    cat_id = cat["id"]
    default_exec = cat["default_exec"]
    config["selections"][cat_id] = default_exec
    config["grid_order"].append(cat_id)

with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)

print(f"Created config with {len(config['grid_order'])} categories")
EOF
    else
        # Last resort: manual JSON generation
        echo "Warning: Neither jq nor python3 found, using basic shell parsing..."

        # Extract category IDs from apps.json (basic grep/sed approach)
        CATEGORIES=$(grep -o '"id": "[^"]*"' "$APPS_JSON" | sed 's/"id": "//;s/"//')

        # Start building JSON
        echo '{' > "$CONFIG_FILE"
        echo '  "selections": {' >> "$CONFIG_FILE"

        FIRST=1
        for CAT in $CATEGORIES; do
            # Get the default_exec for this category
            EXEC=$(grep -A5 "\"id\": \"$CAT\"" "$APPS_JSON" | grep "default_exec" | sed 's/.*"default_exec": "//;s/",$//')

            if [ $FIRST -eq 1 ]; then
                FIRST=0
            else
                echo ',' >> "$CONFIG_FILE"
            fi
            printf '    "%s": "%s"' "$CAT" "$EXEC" >> "$CONFIG_FILE"
        done

        echo '' >> "$CONFIG_FILE"
        echo '  },' >> "$CONFIG_FILE"
        echo '  "grid_order": [' >> "$CONFIG_FILE"

        FIRST=1
        for CAT in $CATEGORIES; do
            if [ $FIRST -eq 1 ]; then
                FIRST=0
            else
                echo ',' >> "$CONFIG_FILE"
            fi
            printf '    "%s"' "$CAT" >> "$CONFIG_FILE"
        done

        echo '' >> "$CONFIG_FILE"
        echo '  ]' >> "$CONFIG_FILE"
        echo '}' >> "$CONFIG_FILE"

        echo "Created config with basic shell parsing"
    fi
fi

# Fix ownership if running as root
if [ "$(id -u)" -eq 0 ]; then
    if [ -n "$SUDO_USER" ]; then
        chown -R "$SUDO_USER:$SUDO_USER" "$CONFIG_DIR"
    elif [ -n "$FLICK_USER" ]; then
        chown -R "$FLICK_USER:$FLICK_USER" "$CONFIG_DIR"
    fi
fi

echo ""
echo "Configuration initialized successfully!"
echo ""
echo "Categories configured:"
if command -v jq &> /dev/null; then
    jq -r '.grid_order[]' "$CONFIG_FILE" | while read cat; do
        echo "  - $cat"
    done
else
    grep -o '"[a-z]*"' "$CONFIG_FILE" | head -25 | tr -d '"' | while read cat; do
        echo "  - $cat"
    done
fi
echo ""
echo "To customize which apps are used for each category,"
echo "long-press on any app icon in the home screen."
