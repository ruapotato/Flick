#!/bin/bash
# Build script for Flick mobile shell and apps
# Run this on the target device (phone)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Flick Build Script ===${NC}"

# Check for Rust
if ! command -v cargo &> /dev/null; then
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    else
        echo -e "${RED}Error: Rust/Cargo not found. Install with:${NC}"
        echo "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
        exit 1
    fi
fi

# Check for required system dependencies
check_deps() {
    local missing=()

    # Check for SDL2 (for sandbox app)
    if ! pkg-config --exists sdl2 2>/dev/null; then
        missing+=("libsdl2-dev")
    fi

    # Check for other common build deps
    if ! command -v cmake &> /dev/null; then
        missing+=("cmake")
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${YELLOW}Missing dependencies: ${missing[*]}${NC}"
        echo "Install with: sudo apt-get install ${missing[*]}"
        exit 1
    fi
}

# Build a Rust project
build_project() {
    local name=$1
    local path=$2

    if [ -f "$path/Cargo.toml" ]; then
        echo -e "${YELLOW}Building $name...${NC}"
        cd "$path"
        cargo build --release
        echo -e "${GREEN}$name built successfully${NC}"
        cd "$SCRIPT_DIR"
    else
        echo -e "${RED}$name not found at $path${NC}"
    fi
}

# Parse arguments
BUILD_ALL=true
BUILD_SHELL=false
BUILD_APPS=false
BUILD_SERVICES=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --shell)
            BUILD_ALL=false
            BUILD_SHELL=true
            shift
            ;;
        --apps)
            BUILD_ALL=false
            BUILD_APPS=true
            shift
            ;;
        --services)
            BUILD_ALL=false
            BUILD_SERVICES=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --shell     Build only the main shell"
            echo "  --apps      Build only apps (sandbox, etc.)"
            echo "  --services  Build only services"
            echo "  --help      Show this help"
            echo ""
            echo "Without options, builds everything."
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check dependencies
check_deps

# Build components
if [ "$BUILD_ALL" = true ] || [ "$BUILD_SHELL" = true ]; then
    build_project "Flick Shell" "$SCRIPT_DIR/shell"
    build_project "DRM HWComposer Shim" "$SCRIPT_DIR/drm-hwcomposer-shim"
fi

if [ "$BUILD_ALL" = true ] || [ "$BUILD_SERVICES" = true ]; then
    build_project "Flick App Service" "$SCRIPT_DIR/services/flick-app-service"
fi

if [ "$BUILD_ALL" = true ] || [ "$BUILD_APPS" = true ]; then
    # Build all Rust apps
    for app_dir in "$SCRIPT_DIR"/apps/*/; do
        if [ -f "$app_dir/Cargo.toml" ]; then
            app_name=$(basename "$app_dir")
            build_project "App: $app_name" "$app_dir"
        fi
    done
fi

echo ""
echo -e "${GREEN}=== Build Complete ===${NC}"
echo ""
echo "Built binaries:"

if [ "$BUILD_ALL" = true ] || [ "$BUILD_SHELL" = true ]; then
    if [ -f "$SCRIPT_DIR/shell/target/release/flick" ]; then
        echo "  Shell: $SCRIPT_DIR/shell/target/release/flick"
    fi
    if [ -f "$SCRIPT_DIR/drm-hwcomposer-shim/target/release/libdrm_hwcomposer_shim.so" ]; then
        echo "  Shim:  $SCRIPT_DIR/drm-hwcomposer-shim/target/release/libdrm_hwcomposer_shim.so"
    fi
fi

if [ "$BUILD_ALL" = true ] || [ "$BUILD_SERVICES" = true ]; then
    if [ -f "$SCRIPT_DIR/services/flick-app-service/target/release/flick-app-service" ]; then
        echo "  App Service: $SCRIPT_DIR/services/flick-app-service/target/release/flick-app-service"
    fi
fi

if [ "$BUILD_ALL" = true ] || [ "$BUILD_APPS" = true ]; then
    for app_dir in "$SCRIPT_DIR"/apps/*/; do
        if [ -f "$app_dir/Cargo.toml" ]; then
            app_name=$(basename "$app_dir")
            binary="$app_dir/target/release/flick-$app_name"
            if [ -f "$binary" ]; then
                echo "  App $app_name: $binary"
            fi
        fi
    done
fi
