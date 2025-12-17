#define _POSIX_C_SOURCE 200809L

#include <string.h>
#include <wlr/util/log.h>
#include <wlr/types/wlr_scene.h>
#include "shell.h"
#include "../compositor/server.h"

void flick_shell_init(struct flick_shell *shell, struct flick_server *server) {
    memset(shell, 0, sizeof(*shell));
    shell->server = server;
    shell->current_view = FLICK_VIEW_HOME;  // Start at home screen
    shell->transition_state = FLICK_TRANSITION_NONE;

    wlr_log(WLR_INFO, "Shell initialized at %p, current_view=%d (%s), server=%p",
            (void*)shell, shell->current_view,
            flick_shell_view_name(shell->current_view), (void*)server);
}

// Determine target view based on current view and gesture edge
static enum flick_shell_view get_transition_target(
    enum flick_shell_view current, enum flick_edge edge) {

    switch (current) {
    case FLICK_VIEW_APP:
        switch (edge) {
        case FLICK_EDGE_BOTTOM:
            return FLICK_VIEW_HOME;        // Swipe up from bottom -> Home
        case FLICK_EDGE_TOP:
            return FLICK_VIEW_HOME;        // Swipe down from top -> Close app (go home)
        case FLICK_EDGE_LEFT:
            return FLICK_VIEW_QUICK_SETTINGS;
        case FLICK_EDGE_RIGHT:
            return FLICK_VIEW_APP_SWITCHER;
        default:
            return current;
        }

    case FLICK_VIEW_HOME:
        switch (edge) {
        case FLICK_EDGE_LEFT:
            return FLICK_VIEW_QUICK_SETTINGS;
        case FLICK_EDGE_RIGHT:
            return FLICK_VIEW_APP_SWITCHER;
        default:
            return current;
        }

    case FLICK_VIEW_QUICK_SETTINGS:
        switch (edge) {
        case FLICK_EDGE_RIGHT:
            return FLICK_VIEW_HOME;        // Swipe right to dismiss
        case FLICK_EDGE_BOTTOM:
            return FLICK_VIEW_HOME;
        default:
            return current;
        }

    case FLICK_VIEW_APP_SWITCHER:
        switch (edge) {
        case FLICK_EDGE_LEFT:
            return FLICK_VIEW_HOME;        // Swipe left to dismiss
        case FLICK_EDGE_BOTTOM:
            return FLICK_VIEW_HOME;
        default:
            return current;
        }

    case FLICK_VIEW_LOCK:
        // Can only unlock with specific gesture or auth
        return current;

    default:
        return current;
    }
}

bool flick_shell_handle_gesture(struct flick_shell *shell,
                                const struct flick_gesture_event *event) {
    if (!event) return false;

    wlr_log(WLR_DEBUG, "Shell(%p): handle_gesture type=%d current_view=%d (%s)",
            (void*)shell, event->type, shell->current_view,
            flick_shell_view_name(shell->current_view));

    switch (event->type) {
    case FLICK_GESTURE_EDGE_SWIPE_START: {
        // Determine where we might be going
        enum flick_shell_view target = get_transition_target(
            shell->current_view, event->edge);

        if (target != shell->current_view) {
            shell->transition_state = FLICK_TRANSITION_STARTING;
            shell->transition_from = shell->current_view;
            shell->transition_to = target;
            shell->transition_progress = 0.0;
            shell->active_edge = event->edge;

            wlr_log(WLR_DEBUG, "Shell: Starting transition %s -> %s (edge %s)",
                    flick_shell_view_name(shell->transition_from),
                    flick_shell_view_name(shell->transition_to),
                    flick_edge_name(event->edge));
            return true;
        }
        break;
    }

    case FLICK_GESTURE_EDGE_SWIPE_UPDATE: {
        if (shell->transition_state == FLICK_TRANSITION_STARTING &&
            event->edge == shell->active_edge) {
            // Update progress based on gesture
            shell->transition_progress = event->progress;

            // Clamp to 0-1 range for display purposes
            if (shell->transition_progress > 1.0) {
                shell->transition_progress = 1.0;
            }

            // Update visuals to track finger position
            flick_shell_update_visuals(shell);

            wlr_log(WLR_DEBUG, "Shell: Transition progress %.2f",
                    shell->transition_progress);
            return true;
        }
        break;
    }

    case FLICK_GESTURE_EDGE_SWIPE_END: {
        if (shell->transition_state == FLICK_TRANSITION_STARTING &&
            event->edge == shell->active_edge) {

            if (event->completed) {
                // Complete the transition
                shell->transition_state = FLICK_TRANSITION_ANIMATING;
                wlr_log(WLR_INFO, "Shell: Completing transition to %s (from %s)",
                        flick_shell_view_name(shell->transition_to),
                        flick_shell_view_name(shell->transition_from));

                // For now, instant transition (animation would be added later)
                shell->current_view = shell->transition_to;
                shell->transition_state = FLICK_TRANSITION_NONE;
                shell->transition_progress = 0.0;

                wlr_log(WLR_INFO, "Shell: current_view now set to %d (%s)",
                        shell->current_view,
                        flick_shell_view_name(shell->current_view));
                flick_shell_update_visuals(shell);
            } else {
                // Cancel the transition
                shell->transition_state = FLICK_TRANSITION_CANCELING;
                wlr_log(WLR_DEBUG, "Shell: Canceling transition, returning to %s",
                        flick_shell_view_name(shell->transition_from));

                // For now, instant cancel
                shell->transition_state = FLICK_TRANSITION_NONE;
                shell->transition_progress = 0.0;

                // Reset visuals to original state
                flick_shell_update_visuals(shell);
            }
            return true;
        }
        break;
    }

    case FLICK_GESTURE_TAP: {
        wlr_log(WLR_DEBUG, "Shell: Tap at (%.0f, %.0f) in view %s",
                event->x, event->y, flick_shell_view_name(shell->current_view));
        // Could handle taps on shell UI elements here
        return false;  // Let compositor handle taps on windows
    }

    default:
        break;
    }

    return false;
}

void flick_shell_handle_action(struct flick_shell *shell,
                               enum flick_gesture_action action) {
    enum flick_shell_view old_view = shell->current_view;

    wlr_log(WLR_DEBUG, "Shell(%p): handle_action(%s) current_view=%d (%s)",
            (void*)shell, flick_gesture_action_name(action), old_view,
            flick_shell_view_name(old_view));

    switch (action) {
    case FLICK_ACTION_GO_HOME:
        if (shell->current_view != FLICK_VIEW_HOME) {
            wlr_log(WLR_INFO, "Shell: Going home");
            shell->current_view = FLICK_VIEW_HOME;
        }
        break;

    case FLICK_ACTION_SHOW_KEYBOARD:
        wlr_log(WLR_INFO, "Shell: Show keyboard requested");
        // TODO: Launch on-screen keyboard (squeekboard, wvkbd, etc.)
        // For now, just log the request
        break;

    case FLICK_ACTION_CLOSE_APP:
        if (shell->current_view == FLICK_VIEW_APP) {
            wlr_log(WLR_INFO, "Shell: Closing app, going home");
            // TODO: Actually close the focused app
            shell->current_view = FLICK_VIEW_HOME;
        }
        break;

    case FLICK_ACTION_QUICK_SETTINGS:
        if (shell->current_view != FLICK_VIEW_QUICK_SETTINGS) {
            wlr_log(WLR_INFO, "Shell: Opening quick settings");
            shell->current_view = FLICK_VIEW_QUICK_SETTINGS;
        }
        break;

    case FLICK_ACTION_APP_SWITCHER:
        if (shell->current_view != FLICK_VIEW_APP_SWITCHER) {
            wlr_log(WLR_INFO, "Shell: Opening app switcher");
            shell->current_view = FLICK_VIEW_APP_SWITCHER;
        }
        break;

    default:
        break;
    }

    // Update visuals if view changed
    if (shell->current_view != old_view) {
        flick_shell_update_visuals(shell);
    }
}

void flick_shell_update(struct flick_shell *shell, uint32_t delta_ms) {
    (void)delta_ms;  // Will be used for animations later

    // Handle animation states
    switch (shell->transition_state) {
    case FLICK_TRANSITION_ANIMATING:
        // Animate towards target
        shell->transition_progress += delta_ms / 200.0;  // 200ms animation
        if (shell->transition_progress >= 1.0) {
            shell->current_view = shell->transition_to;
            shell->transition_state = FLICK_TRANSITION_NONE;
            shell->transition_progress = 0.0;
        }
        break;

    case FLICK_TRANSITION_CANCELING:
        // Animate back to source
        shell->transition_progress -= delta_ms / 200.0;
        if (shell->transition_progress <= 0.0) {
            shell->transition_state = FLICK_TRANSITION_NONE;
            shell->transition_progress = 0.0;
        }
        break;

    default:
        break;
    }
}

const char *flick_shell_view_name(enum flick_shell_view view) {
    switch (view) {
    case FLICK_VIEW_LOCK:           return "lock";
    case FLICK_VIEW_HOME:           return "home";
    case FLICK_VIEW_APP:            return "app";
    case FLICK_VIEW_APP_SWITCHER:   return "app_switcher";
    case FLICK_VIEW_QUICK_SETTINGS: return "quick_settings";
    default:                        return "unknown";
    }
}

bool flick_shell_is_transitioning(struct flick_shell *shell) {
    return shell->transition_state != FLICK_TRANSITION_NONE;
}

void flick_shell_go_to_view(struct flick_shell *shell, enum flick_shell_view view) {
    if (shell->current_view != view) {
        wlr_log(WLR_INFO, "Shell: Programmatic transition %s -> %s",
                flick_shell_view_name(shell->current_view),
                flick_shell_view_name(view));
        shell->current_view = view;
        flick_shell_update_visuals(shell);
    }
}

// Get background color for a shell view - VERY DISTINCT colors for debugging
static void get_view_color(enum flick_shell_view view, float color[4]) {
    switch (view) {
    case FLICK_VIEW_LOCK:
        // RED for lock screen
        color[0] = 0.8f; color[1] = 0.1f; color[2] = 0.1f; color[3] = 1.0f;
        break;
    case FLICK_VIEW_HOME:
        // BLUE for home
        color[0] = 0.1f; color[1] = 0.2f; color[2] = 0.8f; color[3] = 1.0f;
        break;
    case FLICK_VIEW_APP:
        // BLACK (show app)
        color[0] = 0.0f; color[1] = 0.0f; color[2] = 0.0f; color[3] = 1.0f;
        break;
    case FLICK_VIEW_APP_SWITCHER:
        // GREEN for app switcher
        color[0] = 0.1f; color[1] = 0.7f; color[2] = 0.2f; color[3] = 1.0f;
        break;
    case FLICK_VIEW_QUICK_SETTINGS:
        // PURPLE/MAGENTA for quick settings
        color[0] = 0.7f; color[1] = 0.1f; color[2] = 0.7f; color[3] = 1.0f;
        break;
    default:
        // YELLOW fallback (shouldn't happen)
        color[0] = 0.9f; color[1] = 0.9f; color[2] = 0.1f; color[3] = 1.0f;
        break;
    }
}

// Linearly interpolate between two colors based on progress (0.0 - 1.0)
static void lerp_color(float from[4], float to[4], float progress, float out[4]) {
    // Clamp progress to 0-1
    if (progress < 0.0f) progress = 0.0f;
    if (progress > 1.0f) progress = 1.0f;

    for (int i = 0; i < 4; i++) {
        out[i] = from[i] + (to[i] - from[i]) * progress;
    }
}

void flick_shell_update_visuals(struct flick_shell *shell) {
    if (!shell->server || !shell->server->background) {
        return;
    }

    float color[4];

    // If we're in a transition, interpolate between from and to colors
    if (shell->transition_state == FLICK_TRANSITION_STARTING ||
        shell->transition_state == FLICK_TRANSITION_ANIMATING ||
        shell->transition_state == FLICK_TRANSITION_CANCELING) {

        float from_color[4], to_color[4];
        get_view_color(shell->transition_from, from_color);
        get_view_color(shell->transition_to, to_color);

        lerp_color(from_color, to_color, shell->transition_progress, color);
    } else {
        // Not transitioning - use current view color
        get_view_color(shell->current_view, color);
    }

    wlr_log(WLR_DEBUG, "Shell: update_visuals color=(%.2f,%.2f,%.2f) view=%s trans=%d",
            color[0], color[1], color[2],
            flick_shell_view_name(shell->current_view),
            shell->transition_state);

    wlr_scene_rect_set_color(shell->server->background, color);
}

void flick_shell_get_color(struct flick_shell *shell, float *r, float *g, float *b) {
    float color[4];

    // If we're in a transition, interpolate between from and to colors
    if (shell->transition_state == FLICK_TRANSITION_STARTING ||
        shell->transition_state == FLICK_TRANSITION_ANIMATING ||
        shell->transition_state == FLICK_TRANSITION_CANCELING) {

        float from_color[4], to_color[4];
        get_view_color(shell->transition_from, from_color);
        get_view_color(shell->transition_to, to_color);

        lerp_color(from_color, to_color, shell->transition_progress, color);
    } else {
        // Not transitioning - use current view color
        get_view_color(shell->current_view, color);
    }

    *r = color[0];
    *g = color[1];
    *b = color[2];
}
