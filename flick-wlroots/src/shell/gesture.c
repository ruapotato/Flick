#define _POSIX_C_SOURCE 200809L

#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <wlr/util/log.h>
#include "gesture.h"

// Helper: get time difference in milliseconds
static uint32_t timespec_diff_ms(struct timespec *start, struct timespec *end) {
    return (end->tv_sec - start->tv_sec) * 1000 +
           (end->tv_nsec - start->tv_nsec) / 1000000;
}

// Helper: get time difference in seconds
static double timespec_diff_sec(struct timespec *start, struct timespec *end) {
    return (end->tv_sec - start->tv_sec) +
           (end->tv_nsec - start->tv_nsec) / 1000000000.0;
}

// Helper: find touch point by id
static struct flick_touch_point *find_point(struct flick_gesture_recognizer *gesture,
                                            int32_t id) {
    for (int i = 0; i < FLICK_MAX_TOUCH_POINTS; i++) {
        if (gesture->points[i].active && gesture->points[i].id == id) {
            return &gesture->points[i];
        }
    }
    return NULL;
}

// Helper: find free slot
static struct flick_touch_point *find_free_slot(struct flick_gesture_recognizer *gesture) {
    for (int i = 0; i < FLICK_MAX_TOUCH_POINTS; i++) {
        if (!gesture->points[i].active) {
            return &gesture->points[i];
        }
    }
    return NULL;
}

// Helper: detect edge from position
static enum flick_edge detect_edge(struct flick_gesture_recognizer *gesture,
                                   double x, double y) {
    double threshold = gesture->config.edge_threshold;
    double w = gesture->screen_width;
    double h = gesture->screen_height;

    if (x < threshold) {
        return FLICK_EDGE_LEFT;
    } else if (x > w - threshold) {
        return FLICK_EDGE_RIGHT;
    } else if (y < threshold) {
        return FLICK_EDGE_TOP;
    } else if (y > h - threshold) {
        return FLICK_EDGE_BOTTOM;
    }

    return FLICK_EDGE_NONE;
}

// Helper: calculate distance between start and current position
static double point_distance(struct flick_touch_point *point) {
    double dx = point->current_x - point->start_x;
    double dy = point->current_y - point->start_y;
    return sqrt(dx * dx + dy * dy);
}

// Helper: calculate delta
static void point_delta(struct flick_touch_point *point, double *dx, double *dy) {
    *dx = point->current_x - point->start_x;
    *dy = point->current_y - point->start_y;
}

void flick_gesture_init(struct flick_gesture_recognizer *gesture,
                        int32_t screen_width, int32_t screen_height) {
    memset(gesture, 0, sizeof(*gesture));

    gesture->screen_width = screen_width;
    gesture->screen_height = screen_height;

    // Default configuration (matching Rust version)
    gesture->config.edge_threshold = 80.0;           // 80px edge zone
    gesture->config.swipe_threshold = 300.0;         // 300px for animation progress
    gesture->config.swipe_complete_threshold = 100.0; // 100px to trigger short action
    gesture->config.swipe_long_threshold = 200.0;    // 200px for long swipe (home)
    gesture->config.long_press_ms = 500;             // 500ms for long press
    gesture->config.tap_ms = 200;                    // 200ms max for tap
    gesture->config.tap_distance = 10.0;             // 10px max movement for tap
    gesture->config.flick_velocity = 500.0;          // 500px/s for flick

    wlr_log(WLR_DEBUG, "Gesture recognizer initialized: %dx%d, edge=%0.f",
            screen_width, screen_height, gesture->config.edge_threshold);
}

void flick_gesture_set_screen_size(struct flick_gesture_recognizer *gesture,
                                   int32_t width, int32_t height) {
    gesture->screen_width = width;
    gesture->screen_height = height;
    wlr_log(WLR_DEBUG, "Gesture screen size updated: %dx%d", width, height);
}

bool flick_gesture_touch_down(struct flick_gesture_recognizer *gesture,
                              int32_t id, double x, double y,
                              struct flick_gesture_event *event) {
    struct flick_touch_point *point = find_free_slot(gesture);
    if (!point) {
        wlr_log(WLR_ERROR, "No free touch slot for id %d", id);
        return false;
    }

    // Initialize touch point
    memset(point, 0, sizeof(*point));
    point->id = id;
    point->active = true;
    point->start_x = x;
    point->start_y = y;
    point->current_x = x;
    point->current_y = y;
    clock_gettime(CLOCK_MONOTONIC, &point->start_time);
    point->last_time = point->start_time;

    gesture->active_count++;

    // Check for edge swipe
    enum flick_edge edge = detect_edge(gesture, x, y);
    if (edge != FLICK_EDGE_NONE) {
        point->state = FLICK_SLOT_EDGE_SWIPE;
        point->edge = edge;

        wlr_log(WLR_DEBUG, "Touch down id=%d at (%.0f,%.0f): edge swipe %s",
                id, x, y, flick_edge_name(edge));

        if (event) {
            event->type = FLICK_GESTURE_EDGE_SWIPE_START;
            event->edge = edge;
            event->fingers = gesture->active_count;
            event->x = x;
            event->y = y;
        }
        return true;
    }

    // Not an edge touch - potential tap
    point->state = FLICK_SLOT_POTENTIAL_TAP;

    wlr_log(WLR_DEBUG, "Touch down id=%d at (%.0f,%.0f): potential tap",
            id, x, y);

    // Check for multi-touch
    if (gesture->active_count == 2) {
        gesture->multi_touch_active = true;
        // Mark all points as multi-touch
        for (int i = 0; i < FLICK_MAX_TOUCH_POINTS; i++) {
            if (gesture->points[i].active) {
                gesture->points[i].state = FLICK_SLOT_MULTI_TOUCH;
            }
        }
        wlr_log(WLR_DEBUG, "Multi-touch mode activated");
    }

    return false;
}

bool flick_gesture_touch_motion(struct flick_gesture_recognizer *gesture,
                                int32_t id, double x, double y,
                                struct flick_gesture_event *event) {
    struct flick_touch_point *point = find_point(gesture, id);
    if (!point) {
        return false;
    }

    // Calculate velocity
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    double dt = timespec_diff_sec(&point->last_time, &now);

    if (dt > 0.001) {
        point->velocity_x = (x - point->current_x) / dt;
        point->velocity_y = (y - point->current_y) / dt;
    }

    point->current_x = x;
    point->current_y = y;
    point->last_time = now;

    // Handle based on slot state
    switch (point->state) {
    case FLICK_SLOT_EDGE_SWIPE: {
        double dx, dy;
        point_delta(point, &dx, &dy);

        // Calculate progress based on edge
        double progress = 0.0;
        double velocity = 0.0;

        switch (point->edge) {
        case FLICK_EDGE_LEFT:
            progress = dx / gesture->config.swipe_threshold;
            velocity = point->velocity_x;
            break;
        case FLICK_EDGE_RIGHT:
            progress = -dx / gesture->config.swipe_threshold;
            velocity = -point->velocity_x;
            break;
        case FLICK_EDGE_TOP:
            progress = dy / gesture->config.swipe_threshold;
            velocity = point->velocity_y;
            break;
        case FLICK_EDGE_BOTTOM:
            progress = -dy / gesture->config.swipe_threshold;
            velocity = -point->velocity_y;
            break;
        default:
            break;
        }

        if (progress < 0.0) progress = 0.0;

        if (event) {
            event->type = FLICK_GESTURE_EDGE_SWIPE_UPDATE;
            event->edge = point->edge;
            event->progress = progress;
            event->velocity = velocity;
            event->fingers = gesture->active_count;
        }
        return true;
    }

    case FLICK_SLOT_POTENTIAL_TAP:
        // Check if moved too far for a tap
        if (point_distance(point) > gesture->config.tap_distance) {
            point->state = FLICK_SLOT_SWIPE;
            wlr_log(WLR_DEBUG, "Touch %d: tap -> swipe (moved %.0f px)",
                    id, point_distance(point));
        }
        break;

    case FLICK_SLOT_MULTI_TOUCH:
        // TODO: Handle pinch/pan
        break;

    default:
        break;
    }

    return false;
}

bool flick_gesture_touch_up(struct flick_gesture_recognizer *gesture,
                            int32_t id,
                            struct flick_gesture_event *event) {
    struct flick_touch_point *point = find_point(gesture, id);
    if (!point) {
        return false;
    }

    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    uint32_t duration_ms = timespec_diff_ms(&point->start_time, &now);
    double distance = point_distance(point);

    bool has_event = false;

    switch (point->state) {
    case FLICK_SLOT_EDGE_SWIPE: {
        bool completed = distance > gesture->config.swipe_complete_threshold;
        bool is_long = distance > gesture->config.swipe_long_threshold;

        double velocity = 0.0;
        switch (point->edge) {
        case FLICK_EDGE_LEFT:
        case FLICK_EDGE_RIGHT:
            velocity = fabs(point->velocity_x);
            break;
        case FLICK_EDGE_TOP:
        case FLICK_EDGE_BOTTOM:
            velocity = fabs(point->velocity_y);
            break;
        default:
            break;
        }

        // Also complete if flick velocity is high enough
        if (velocity > gesture->config.flick_velocity) {
            completed = true;
            // Fast flick counts as long swipe
            is_long = true;
        }

        wlr_log(WLR_INFO, "Edge swipe %s end: distance=%.0f, velocity=%.0f, completed=%s, long=%s",
                flick_edge_name(point->edge), distance, velocity,
                completed ? "yes" : "no", is_long ? "yes" : "no");

        if (event) {
            event->type = FLICK_GESTURE_EDGE_SWIPE_END;
            event->edge = point->edge;
            event->completed = completed;
            event->is_long = is_long;
            event->distance = distance;
            event->velocity = velocity;
            event->fingers = gesture->active_count;
        }
        has_event = true;
        break;
    }

    case FLICK_SLOT_POTENTIAL_TAP:
        if (duration_ms < gesture->config.tap_ms &&
            distance < gesture->config.tap_distance) {
            wlr_log(WLR_INFO, "Tap at (%.0f, %.0f)", point->start_x, point->start_y);

            if (event) {
                event->type = FLICK_GESTURE_TAP;
                event->x = point->start_x;
                event->y = point->start_y;
            }
            has_event = true;
        } else if (duration_ms >= gesture->config.long_press_ms &&
                   distance < gesture->config.tap_distance) {
            wlr_log(WLR_INFO, "Long press at (%.0f, %.0f)",
                    point->start_x, point->start_y);

            if (event) {
                event->type = FLICK_GESTURE_LONG_PRESS;
                event->x = point->start_x;
                event->y = point->start_y;
            }
            has_event = true;
        }
        break;

    default:
        break;
    }

    // Clear the slot
    point->active = false;
    gesture->active_count--;

    // Reset multi-touch if all fingers lifted
    if (gesture->active_count == 0) {
        gesture->multi_touch_active = false;
        gesture->pinch_initial_distance = 0.0;
    }

    return has_event;
}

void flick_gesture_touch_cancel(struct flick_gesture_recognizer *gesture) {
    wlr_log(WLR_DEBUG, "Touch cancelled, clearing all state");

    for (int i = 0; i < FLICK_MAX_TOUCH_POINTS; i++) {
        gesture->points[i].active = false;
    }
    gesture->active_count = 0;
    gesture->multi_touch_active = false;
    gesture->pinch_initial_distance = 0.0;
}

enum flick_gesture_action flick_gesture_to_action(
    const struct flick_gesture_event *event) {

    if (!event) {
        return FLICK_ACTION_NONE;
    }

    switch (event->type) {
    case FLICK_GESTURE_EDGE_SWIPE_END:
        if (!event->completed) {
            return FLICK_ACTION_NONE;
        }

        switch (event->edge) {
        case FLICK_EDGE_BOTTOM:
            // Short swipe = keyboard, long swipe = go home
            if (event->is_long) {
                return FLICK_ACTION_GO_HOME;
            } else {
                return FLICK_ACTION_SHOW_KEYBOARD;
            }
        case FLICK_EDGE_TOP:
            return FLICK_ACTION_CLOSE_APP;
        case FLICK_EDGE_LEFT:
            return FLICK_ACTION_QUICK_SETTINGS;
        case FLICK_EDGE_RIGHT:
            return FLICK_ACTION_APP_SWITCHER;
        default:
            return FLICK_ACTION_NONE;
        }

    case FLICK_GESTURE_TAP:
        return FLICK_ACTION_TAP;

    case FLICK_GESTURE_LONG_PRESS:
        return FLICK_ACTION_LONG_PRESS;

    default:
        return FLICK_ACTION_NONE;
    }
}

const char *flick_gesture_action_name(enum flick_gesture_action action) {
    switch (action) {
    case FLICK_ACTION_NONE:           return "none";
    case FLICK_ACTION_GO_HOME:        return "go_home";
    case FLICK_ACTION_SHOW_KEYBOARD:  return "show_keyboard";
    case FLICK_ACTION_CLOSE_APP:      return "close_app";
    case FLICK_ACTION_QUICK_SETTINGS: return "quick_settings";
    case FLICK_ACTION_APP_SWITCHER:   return "app_switcher";
    case FLICK_ACTION_TAP:            return "tap";
    case FLICK_ACTION_LONG_PRESS:     return "long_press";
    default:                          return "unknown";
    }
}

const char *flick_edge_name(enum flick_edge edge) {
    switch (edge) {
    case FLICK_EDGE_NONE:   return "none";
    case FLICK_EDGE_LEFT:   return "left";
    case FLICK_EDGE_RIGHT:  return "right";
    case FLICK_EDGE_TOP:    return "top";
    case FLICK_EDGE_BOTTOM: return "bottom";
    default:                return "unknown";
    }
}
