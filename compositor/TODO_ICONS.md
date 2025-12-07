# Icon Rendering TODO

## Current State
- Icon loading infrastructure complete (`src/shell/icons.rs`)
- IconCache loads PNGs from standard XDG directories (hicolor, Adwaita, etc.)
- Icons are resized to 64x64 and cached as RGBA data
- Shell has `icon_cache` field ready to use

## Challenge
Smithay's render element system uses complex generics. Mixing `SolidColorRenderElement` 
with `TextureRenderElement<GlesTexture>` in a single `Vec` requires either:

1. **Custom enum with RenderElement impl** - Tried but lifetime issues with `Frame<'frame, 'buffer>`
2. **render_elements! macro** - Has generic type constraints that conflict with concrete GlesTexture
3. **Separate render pass** - Render icons after solid colors using renderer directly

## Research Needed
- Look at smithay's `render_elements!` macro more closely
- Check if `render_output` can accept `&[&dyn RenderElement]` (trait objects)
- Look at how anvil example handles mixed element types
- Consider using `MemoryRenderBuffer` instead of `TextureBuffer`

## Files to Modify
- `src/backend/udev.rs` - Add icon texture rendering in `render_frame()`
- `src/shell/app_grid.rs` - Return icon info alongside rects
- `src/shell/apps.rs` - CategoryInfo already has `icon: Option<String>`

## Icon Resolution
Icons are found by searching:
1. ~/.local/share/icons/hicolor/{size}/{category}/{name}.png
2. /usr/share/icons/{Adwaita,gnome,hicolor}/{size}/{category}/{name}.png  
3. /usr/share/pixmaps/{name}.png

Sizes tried: 256x256, 128x128, 96x96, 64x64, 48x48
Categories: apps, applications, mimetypes, places, devices, actions, status
