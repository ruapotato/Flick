# Lock Screen & Settings App Implementation Plan

## Overview

Add a lock screen with multiple authentication methods (PAM password, PIN, pattern) and a built-in Settings view to configure lock preferences.

## Architecture

### 1. Lock Screen (Compositor Shell)

**New file:** `src/shell/lock_screen.rs`

**ShellView addition:**
```rust
pub enum ShellView {
    LockScreen,  // NEW - shown on startup and after lock
    App,
    Home,
    Switcher,
    QuickSettings,
    Settings,    // NEW - for settings panel
}
```

**Lock Methods:**
```rust
pub enum LockMethod {
    None,        // No lock (unlock immediately)
    Pin,         // 4-6 digit PIN
    Pattern,     // 3x3 pattern lock
    Password,    // Full PAM password
}
```

**Config file:** `~/.local/state/flick/lock_config.json`
```json
{
    "method": "pin",
    "pin_hash": "bcrypt_hash_here",
    "pattern_hash": "bcrypt_hash_here",
    "timeout_seconds": 300
}
```

### 2. Lock Screen UI Components

**PIN Pad:**
- 3x4 grid: digits 0-9, backspace, enter
- Show dots for entered digits (not actual numbers)
- Visual feedback on button press

**Pattern Lock:**
- 3x3 grid of dots
- Track finger path through dots
- Draw lines connecting selected dots
- Minimum 4 dots required

**Password Entry:**
- Virtual keyboard (or rely on physical keyboard)
- Password field showing dots
- "Enter Password" button/fallback link always visible

**Emergency Fallback:**
- "Use Password" link always visible even with PIN/pattern
- Allows PAM authentication if PIN/pattern forgotten

### 3. Settings Panel (Built into Shell)

**Access:** Tap "Settings" category on home screen (or add gear icon)

**Settings UI Structure:**
```
Settings
├── Lock Screen
│   ├── Lock Method: [None | PIN | Pattern | Password]
│   ├── Set PIN (if PIN selected)
│   ├── Set Pattern (if Pattern selected)
│   └── Lock Timeout: [Immediate | 1min | 5min | 15min | Never]
├── Display
│   └── (future: brightness, etc.)
└── About
    └── Version info
```

### 4. Dependencies

Add to `Cargo.toml`:
```toml
pam = "0.7"      # PAM authentication
bcrypt = "0.15"  # Password/PIN hashing
```

## Implementation Steps

### Phase 1: Lock Screen Infrastructure
1. Create `src/shell/lock_screen.rs` module
2. Add `LockScreen` to `ShellView` enum
3. Add lock screen state to `Shell` struct (entered_pin, pattern_points, etc.)
4. Create `LockConfig` struct with load/save
5. Start compositor in `LockScreen` view instead of `Home`

### Phase 2: PIN Lock UI
1. Render PIN pad (3x4 grid of buttons)
2. Handle touch input on PIN buttons
3. Display entered digits as dots
4. Implement PIN verification (compare bcrypt hash)
5. Transition to Home on successful unlock

### Phase 3: Pattern Lock UI
1. Render 3x3 dot grid
2. Track touch path through dots
3. Draw connection lines during input
4. Implement pattern verification
5. Visual feedback for correct/incorrect

### Phase 4: PAM Password Authentication
1. Add `pam` crate dependency
2. Implement password authentication function
3. Create virtual keyboard or text input field
4. Handle authentication flow with PAM

### Phase 5: Settings Panel
1. Add `Settings` to `ShellView`
2. Create settings UI rendering
3. Implement setting toggles and navigation
4. Add PIN setup flow (enter new PIN twice)
5. Add pattern setup flow
6. Connect to home screen (Settings category or gear icon)

### Phase 6: Integration
1. Lock after timeout
2. Lock on power button press (needs input handling)
3. Lock on suspend/resume
4. Handle authentication failures (delay, attempts limit)

## File Changes Summary

**New files:**
- `src/shell/lock_screen.rs` - Lock screen logic and rendering
- `src/shell/settings.rs` - Settings panel logic and rendering

**Modified files:**
- `Cargo.toml` - Add pam, bcrypt dependencies
- `src/shell/mod.rs` - Add LockScreen/Settings to ShellView, add lock state to Shell
- `src/backend/udev.rs` - Render lock screen, handle lock screen input
- `src/state.rs` - Add lock/unlock methods

## Security Considerations

- Store PIN/pattern as bcrypt hash (not plaintext)
- PAM password never stored, always authenticate live
- Rate limit failed attempts (progressive delay)
- Clear sensitive data from memory after use
- Lock screen blocks all app interactions

## Rendering Approach

Use existing primitives:
- `SolidColorRenderElement` for buttons and backgrounds
- `text::render_text()` for labels
- Custom drawing for pattern lines (use thin rectangles or need line primitive)

## Testing Notes

- Test with no lock configured (immediate unlock)
- Test PIN entry/verification
- Test pattern entry/verification
- Test PAM password fallback
- Test wrong PIN/pattern (error feedback)
- Test settings panel navigation
