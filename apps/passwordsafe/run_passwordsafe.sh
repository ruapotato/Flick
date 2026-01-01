#!/bin/bash
# Flick Password Safe - QML + keepassxc-cli
# Uses file-based IPC since stdout capture doesn't work for launched apps

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.local/state/flick/passwordsafe"
LOG_FILE="${STATE_DIR}/passwordsafe.log"
QML_LOG="${STATE_DIR}/qml_output.log"
CMD_DIR="/tmp/flick_vault_cmds"
HELPER="$SCRIPT_DIR/vault_helper.sh"

mkdir -p "$STATE_DIR"
mkdir -p "$CMD_DIR"
chmod 700 "$CMD_DIR"

# Clear old files
> "$LOG_FILE"
> "$QML_LOG"
rm -f "$CMD_DIR"/* 2>/dev/null

echo "=== Password Safe started at $(date) ===" >> "$LOG_FILE"
echo "STATE_DIR=$STATE_DIR" >> "$LOG_FILE"
echo "CMD_DIR=$CMD_DIR" >> "$LOG_FILE"

# Write paths to files that QML can read
echo "$STATE_DIR" > "$STATE_DIR/state_dir.txt"
echo "$CMD_DIR" > "$STATE_DIR/cmd_dir.txt"
echo "$STATE_DIR" > /tmp/flick_vault_state_dir

# Cleanup on exit
cleanup() {
    [ -n "$TAIL_PID" ] && kill $TAIL_PID 2>/dev/null
    [ -n "$CLEANER_PID" ] && kill $CLEANER_PID 2>/dev/null
    rm -rf "$CMD_DIR"
    rm -f /tmp/flick_vault_state_dir
    echo "Password Safe exited at $(date)" >> "$LOG_FILE"
}
trap cleanup EXIT

# Background cleaner - removes result files older than 5 seconds
result_cleaner() {
    while true; do
        sleep 5
        find "$CMD_DIR" -name "result_*" -mmin +0.1 -delete 2>/dev/null
    done
}
result_cleaner &
CLEANER_PID=$!

# Process a vault command
process_vault_cmd() {
    local cmd_id="$1"
    local cmd_content="$2"

    echo "Processing command $cmd_id: $cmd_content" >> "$LOG_FILE"

    # Parse command content (format: ACTION|ARG1|ARG2|...)
    IFS='|' read -ra parts <<< "$cmd_content"
    local action="${parts[0]}"
    local args=("${parts[@]:1}")

    # Result file path
    local result_file="$CMD_DIR/result_$cmd_id"

    echo "  Action: $action, Args count: ${#args[@]}" >> "$LOG_FILE"

    # Execute helper
    "$HELPER" "$action" "$result_file" "${args[@]}" 2>> "$LOG_FILE"

    echo "  Result written to: $result_file" >> "$LOG_FILE"
    echo "  Result exists: $(test -f "$result_file" && echo YES || echo NO)" >> "$LOG_FILE"
    echo "  Result content: $(cat "$result_file" 2>/dev/null)" >> "$LOG_FILE"
}

# Background log watcher - processes VAULTCMD lines from QML output
log_watcher() {
    tail -f "$QML_LOG" 2>/dev/null | while IFS= read -r line; do
        echo "$line" >> "$LOG_FILE"

        if [[ "$line" == *"VAULTCMD:"* ]]; then
            # Extract command data: VAULTCMD:cmdId:cmdContent
            cmd_data="${line#*VAULTCMD:}"
            cmd_id="${cmd_data%%:*}"
            cmd_content="${cmd_data#*:}"

            # Process command in background
            process_vault_cmd "$cmd_id" "$cmd_content" &
        fi
    done
}
log_watcher &
TAIL_PID=$!

# Set up QML environment
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QT_IM_MODULE=textinputv3
export XDG_RUNTIME_DIR=/run/flick
export WAYLAND_DISPLAY=wayland-1
export FLICK_STATE_DIR="$STATE_DIR"
export FLICK_CMD_DIR="$CMD_DIR"
export QML_XHR_ALLOW_FILE_READ=1

# Run qmlscene with output going to log file
qmlscene "$SCRIPT_DIR/main.qml" >> "$QML_LOG" 2>&1
