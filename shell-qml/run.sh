#!/bin/bash
# Run the Flick QML shell

cd "$(dirname "$0")"

# Check for PySide6
if ! python3 -c "import PySide6" 2>/dev/null; then
    echo "PySide6 not found. Installing..."
    pip3 install --user PySide6
fi

exec python3 main.py "$@"
