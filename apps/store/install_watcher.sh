#!/bin/bash
# Flick Store Install Watcher
# Watches for install requests and processes them using flick-pkg
# Run this in the background: ./install_watcher.sh &

REQUEST_FILE="/tmp/flick_install_request"

# Find flick-pkg - could be in ~/Flick or /home/*/Flick
find_flick_pkg() {
    if [ -n "$FLICK_USER" ] && [ -f "/home/$FLICK_USER/Flick/flick-pkg" ]; then
        echo "/home/$FLICK_USER/Flick/flick-pkg"
    elif [ -n "$SUDO_USER" ] && [ -f "/home/$SUDO_USER/Flick/flick-pkg" ]; then
        echo "/home/$SUDO_USER/Flick/flick-pkg"
    elif [ -f "/home/droidian/Flick/flick-pkg" ]; then
        echo "/home/droidian/Flick/flick-pkg"
    elif [ -f "$HOME/Flick/flick-pkg" ]; then
        echo "$HOME/Flick/flick-pkg"
    else
        echo ""
    fi
}

FLICK_PKG=$(find_flick_pkg)

if [ -z "$FLICK_PKG" ]; then
    echo "Error: flick-pkg not found"
    exit 1
fi

echo "Flick Store Install Watcher started"
echo "Using: $FLICK_PKG"
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

            # Use flick-pkg for the action
            if [ "$ACTION" = "install" ]; then
                "$FLICK_PKG" install "$APP_ID"
            elif [ "$ACTION" = "uninstall" ]; then
                "$FLICK_PKG" uninstall "$APP_ID"
            else
                echo "Unknown action: $ACTION"
            fi

            # Clear the request file
            > "$REQUEST_FILE"
        fi
    fi
    sleep 0.5
done
