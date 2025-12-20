#!/bin/bash
# Build Flick for Droidian phone (requires hwcomposer feature)
# Run this on the phone, not the development machine

set -e

cd "$(dirname "$0")/shell"

echo "Building Flick with hwcomposer support..."
cargo build --release

echo ""
echo "Build complete: target/release/flick"
echo "Run with: ./start_flick.sh"
