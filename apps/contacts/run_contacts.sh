#!/bin/bash
SCRIPT_DIR="/home/furios/flick-phosh/Flick/apps/contacts"
LOG_FILE="${HOME}/.local/state/flick/qml_contacts.log"

export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QML_XHR_ALLOW_FILE_READ=1

mkdir -p ~/.local/state/flick
> "$LOG_FILE"

echo "Starting Contacts app" >> "$LOG_FILE"

# Run /usr/lib/qt5/bin/qmlscene and capture output for picker commands
stdbuf -oL -eL /usr/lib/qt5/bin/qmlscene "$SCRIPT_DIR/main.qml" 2>&1 | tee -a "$LOG_FILE" | while IFS= read -r line; do
    # Check for picker clear command
    if [[ "$line" == *"PICKER_CLEAR:"* ]]; then
        RESULT_FILE=$(echo "$line" | sed 's/.*PICKER_CLEAR://')
        echo "Clearing picker result file: $RESULT_FILE" >> "$LOG_FILE"
        rm -f "$RESULT_FILE"
    fi
    # Check for picker launch command - format: PICKER_LAUNCH:filter:startdir:resultfile
    if [[ "$line" == *"PICKER_LAUNCH:"* ]]; then
        PICKER_ARGS=$(echo "$line" | sed 's/.*PICKER_LAUNCH://')
        FILTER=$(echo "$PICKER_ARGS" | cut -d: -f1)
        START_DIR=$(echo "$PICKER_ARGS" | cut -d: -f2)
        RESULT_FILE=$(echo "$PICKER_ARGS" | cut -d: -f3)
        echo "Launching file picker: filter=$FILTER, start=$START_DIR, result=$RESULT_FILE" >> "$LOG_FILE"
        # Launch the file app in picker mode
        "$SCRIPT_DIR/../files/run_files.sh" --pick --filter="$FILTER" --start-dir="$START_DIR" --result-file="$RESULT_FILE" &
    fi
    # Check for app launch commands (for messaging integration)
    if [[ "$line" == *"LAUNCH:"* ]]; then
        APP_CMD=$(echo "$line" | sed 's/.*LAUNCH://')
        echo "Launching app: $APP_CMD" >> "$LOG_FILE"
        "$APP_CMD" &
    fi
done

echo "Contacts app exited" >> "$LOG_FILE"
