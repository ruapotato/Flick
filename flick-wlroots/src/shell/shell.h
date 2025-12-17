#ifndef FLICK_SHELL_H
#define FLICK_SHELL_H

#include <stdbool.h>
#include <stdint.h>
#include "gesture.h"

// Forward declaration
struct flick_server;

// Shell views (what's currently displayed)
enum flick_shell_view {
    FLICK_VIEW_LOCK,           // Lock screen
    FLICK_VIEW_HOME,           // Home screen / app grid
    FLICK_VIEW_APP,            // Focused application
    FLICK_VIEW_APP_SWITCHER,   // App switcher (recent apps)
    FLICK_VIEW_QUICK_SETTINGS, // Quick settings panel
};

// Transition state (for animations)
enum flick_transition_state {
    FLICK_TRANSITION_NONE,      // No transition in progress
    FLICK_TRANSITION_STARTING,  // Gesture started, tracking progress
    FLICK_TRANSITION_ANIMATING, // Gesture ended, animating to target
    FLICK_TRANSITION_CANCELING, // Gesture cancelled, returning to source
};

// Shell state
struct flick_shell {
    // Current view
    enum flick_shell_view current_view;

    // Transition state
    enum flick_transition_state transition_state;
    enum flick_shell_view transition_from;
    enum flick_shell_view transition_to;
    double transition_progress;  // 0.0 to 1.0

    // Gesture tracking during transition
    enum flick_edge active_edge;

    // Reference to server (for accessing views, etc.)
    struct flick_server *server;
};

// Initialize shell
void flick_shell_init(struct flick_shell *shell, struct flick_server *server);

// Handle gesture events - returns true if shell handled it
bool flick_shell_handle_gesture(struct flick_shell *shell,
                                const struct flick_gesture_event *event);

// Handle gesture action (from completed gesture)
void flick_shell_handle_action(struct flick_shell *shell,
                               enum flick_gesture_action action);

// Update shell state (call each frame for animations)
void flick_shell_update(struct flick_shell *shell, uint32_t delta_ms);

// Get current view name (for logging)
const char *flick_shell_view_name(enum flick_shell_view view);

// Check if shell is in a transition
bool flick_shell_is_transitioning(struct flick_shell *shell);

// Force transition to a specific view (for programmatic control)
void flick_shell_go_to_view(struct flick_shell *shell, enum flick_shell_view view);

#endif // FLICK_SHELL_H
