#!/bin/bash
# Flick Store App Installer
# Usage: install_app.sh <app_id> <action>
# action: install | uninstall

APP_ID="$1"
ACTION="${2:-install}"

# Get the real user's home
if [ -n "$FLICK_USER" ] && [ "$FLICK_USER" != "root" ]; then
    USER_HOME="/home/$FLICK_USER"
elif [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    USER_HOME="/home/$SUDO_USER"
elif [ -d "/home/droidian" ]; then
    USER_HOME="/home/droidian"
else
    USER_HOME="$HOME"
fi

FLICK_DIR="$USER_HOME/Flick"
APPS_DIR="$FLICK_DIR/apps"
STORE_PACKAGES="$FLICK_DIR/store/packages"
STATUS_FILE="/tmp/flick_install_status"

# Write status
write_status() {
    echo "$1" > "$STATUS_FILE"
}

if [ -z "$APP_ID" ]; then
    write_status "error:No app ID provided"
    exit 1
fi

if [ "$ACTION" = "install" ]; then
    # Check if package exists
    if [ ! -d "$STORE_PACKAGES/$APP_ID" ]; then
        write_status "error:Package not found: $APP_ID"
        exit 1
    fi

    # Check if already installed
    if [ -d "$APPS_DIR/$APP_ID" ]; then
        write_status "error:App already installed: $APP_ID"
        exit 1
    fi

    # Copy package to apps directory
    cp -r "$STORE_PACKAGES/$APP_ID" "$APPS_DIR/$APP_ID"

    if [ $? -eq 0 ]; then
        write_status "success:$APP_ID installed"
        exit 0
    else
        write_status "error:Failed to copy files"
        exit 1
    fi

elif [ "$ACTION" = "uninstall" ]; then
    # Check if installed
    if [ ! -d "$APPS_DIR/$APP_ID" ]; then
        write_status "error:App not installed: $APP_ID"
        exit 1
    fi

    # Remove app directory
    rm -rf "$APPS_DIR/$APP_ID"

    if [ $? -eq 0 ]; then
        write_status "success:$APP_ID uninstalled"
        exit 0
    else
        write_status "error:Failed to remove files"
        exit 1
    fi
else
    write_status "error:Unknown action: $ACTION"
    exit 1
fi
