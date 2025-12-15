# Flick Compositor - Development Notes

## Smithay Render Element Draw Order

**IMPORTANT**: Smithay renders elements in **FRONT-TO-BACK order**:
- The **first element** in the array is rendered **on top** (last in Z-order)
- The **last element** in the array is rendered **at the back** (first in Z-order)

This means when building a list of rectangles to render:
1. Add background elements first
2. Add foreground/UI elements after
3. **Reverse the array** before returning so background renders first

Example from `quick_settings.rs`:
```rust
// Build rectangles: background first, then UI elements
rects.push((background, bg_color));
rects.push((status_bar, status_color));
rects.push((toggle_button, toggle_color));
// ... more UI elements

// CRITICAL: Reverse so background renders first (at back)
rects.reverse();
```

Without the reverse, the background would render on top and cover all UI elements.

## Shell UI Rendering

Shell UI uses `SolidColorRenderElement` for all rectangles. Each shell component
(app_grid, quick_settings, app_switcher) returns `Vec<(Rect, Color)>` which is
converted to render elements in `udev.rs`.

## Touch Gesture Recognition

- Edge swipes: 50px from screen edge to start
- Tap vs scroll threshold: 40px movement
- Gesture progress: 0.0 to 1.0+ based on finger travel

## Slint Software Renderer Buffer Management

**CRITICAL**: When using `MinimalSoftwareWindow`, the `RepaintBufferType` must match
your buffer allocation strategy:

- `RepaintBufferType::NewBuffer` - Use when creating a **fresh buffer each frame**
- `RepaintBufferType::ReusedBuffer` - Use when **reusing the same buffer** between frames

If you create a new buffer each frame but use `ReusedBuffer`, Slint will only repaint
"damaged" regions, leaving the rest of the buffer uninitialized (black). This causes
the symptom: **first frame renders correctly, subsequent frames are black**.

```rust
// CORRECT: New buffer each frame = NewBuffer type
let window = MinimalSoftwareWindow::new(RepaintBufferType::NewBuffer);

// In render():
let mut buffer = SharedPixelBuffer::new(width, height);  // Fresh each frame
renderer.render(buffer.make_mut_slice(), width as usize);
```

The fix in `slint_ui.rs` was changing from `ReusedBuffer` to `NewBuffer`.

## Hwcomposer Backend - Droidian Testing

### Target Device
- **Device**: Google Pixel 3a (sargo)
- **OS**: Droidian
- **IP**: 10.15.19.82
- **User**: droidian
- **SSH Alias**: `phone` (ssh droidian@10.15.19.82)

### Build & Test Workflow
```bash
# On local machine - commit and push
git add -A && git commit -m "message" && git push

# On phone via SSH
ssh droidian@10.15.19.82 "cd ~/Flick && git pull && ./build_phone.sh"

# Run Flick
ssh droidian@10.15.19.82 "./shell/target/release/flick --hwcomposer"
```

Build takes ~8 minutes on phone.

### Hardware Info
- SoC: Snapdragon 670 (sdm670/sargo)
- HWComposer: hwcomposer.sdm710.so (HWC2)
- Display: 1080x2220 @ 60fps, DPI 442.5x444.0

### Current Status (Dec 2024)
- EGL initialization: WORKING
- OpenGL ES rendering: WORKING (test colors, Slint UI)
- HWC2 device creation: WORKING
- HWC2 display access: WORKING
- HWC2 layer creation: WORKING (after callback registration)
- HWC2 present calls: WORKING (validate->accept->present flow)
- Physical display: WORKING (shows UI)
- Touch input: WORKING (gestures recognized)

### Quick Start
```bash
# Run flick on phone (from local machine)
./start_phone.sh
```

### Key Files
- `shell/src/backend/hwcomposer.rs` - Main backend
- `shell/src/backend/hwcomposer_ffi.rs` - FFI bindings

### Libraries Used
- libhybris-hwcomposerwindow (HWCNativeWindowCreate)
- libhwc2 (hwc2_compat_* functions)
- libgralloc (hybris_gralloc_initialize)

### Services
- android-service@hwcomposer.service OR
- Direct start: `sudo ANDROID_SERVICE='(vendor.hwcomposer-.*|vendor.qti.hardware.display.composer)' /usr/lib/halium-wrappers/android-service.sh hwcomposer start`

### HWC2 Present Flow (Critical!)
The correct order for HWC2 frame presentation:
1. Set layer buffer (hwc2_compat_layer_set_buffer)
2. Set client target (hwc2_compat_display_set_client_target)
3. Validate display (hwc2_compat_display_validate)
4. Accept changes (hwc2_compat_display_accept_changes)
5. Present (hwc2_compat_display_present)

Buffer/fence must be set BEFORE validate, not after!

### Notes
- HWC2 callbacks must be registered before layer creation works
- Duplicate fences when passing to multiple HWC2 calls (HWC2 takes ownership)
- Call glFinish() before eglSwapBuffers for proper GPU sync
