#!/bin/bash
# Run the Flick QML shell

cd "$(dirname "$0")"
exec python3 main.py "$@"
