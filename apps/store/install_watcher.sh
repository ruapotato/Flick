#!/bin/bash
# Flick Store Install Watcher
# Watches for install requests and processes them
# Run this in the background: ./install_watcher.sh &

REQUEST_FILE="/tmp/flick_install_request"
SCRIPT_DIR="$(dirname "$0")"
INSTALL_SCRIPT="$SCRIPT_DIR/install_app.sh"

echo "Flick Store Install Watcher started"
echo "Watching: $REQUEST_FILE"

# Create the request file if it doesn't exist
touch "$REQUEST_FILE"

# Watch for changes
while true; do
    if [ -s "$REQUEST_FILE" ]; then
        REQUEST=$(cat "$REQUEST_FILE")
        if [ -n "$REQUEST" ]; then
            APP_ID=$(echo "$REQUEST" | cut -d: -f1)
            ACTION=$(echo "$REQUEST" | cut -d: -f2)

            echo "Processing: $ACTION $APP_ID"

            # Run the install script
            "$INSTALL_SCRIPT" "$APP_ID" "$ACTION"

            # Clear the request file
            > "$REQUEST_FILE"
        fi
    fi
    sleep 0.5
done
