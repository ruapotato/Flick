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
