#!/bin/bash
# Flick - Start with Phone Shape (Letterbox) Mode
#
# Starts the compositor with black bars on the sides to simulate
# a 9:16 phone aspect ratio in the center of the screen.
# Great for recording demos on a widescreen monitor.
#
# Usage:
#   ./start_letterbox.sh              - Run with letterbox mode
#   ./start_letterbox.sh --timeout 30 - Run for 30 seconds

export FLICK_LETTERBOX=1
exec "$(dirname "$0")/start.sh" "$@"
