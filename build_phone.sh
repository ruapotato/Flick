#!/bin/bash
# Build script for Droidian phone

# Source cargo environment
source ~/.cargo/env

# Build with limited parallelism to avoid freezing
cd ~/Flick
CARGO_BUILD_JOBS=1 cargo build --release --features hwcomposer -j1
