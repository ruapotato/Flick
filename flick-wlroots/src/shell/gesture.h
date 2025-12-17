#ifndef FLICK_GESTURE_H
#define FLICK_GESTURE_H

#include <stdbool.h>
#include <stdint.h>
#include <time.h>

// Maximum number of simultaneous touch points
#define FLICK_MAX_TOUCH_POINTS 10

// Screen edge
enum flick_edge {
    FLICK_EDGE_NONE = 0,
    FLICK_EDGE_LEFT,
    FLICK_EDGE_RIGHT,
    FLICK_EDGE_TOP,
    FLICK_EDGE_BOTTOM,
};

// Gesture event types
enum flick_gesture_type {
    FLICK_GESTURE_NONE = 0,
    FLICK_GESTURE_TAP,
    FLICK_GESTURE_LONG_PRESS,
    FLICK_GESTURE_EDGE_SWIPE_START,
    FLICK_GESTURE_EDGE_SWIPE_UPDATE,
    FLICK_GESTURE_EDGE_SWIPE_END,
    FLICK_GESTURE_PINCH,
    FLICK_GESTURE_PAN,
};

// Gesture actions (what to do in response)
enum flick_gesture_action {
    FLICK_ACTION_NONE = 0,
    FLICK_ACTION_GO_HOME,           // Bottom edge swipe up
    FLICK_ACTION_CLOSE_APP,         // Top edge swipe down
    FLICK_ACTION_QUICK_SETTINGS,    // Left edge swipe right
    FLICK_ACTION_APP_SWITCHER,      // Right edge swipe left
    FLICK_ACTION_TAP,
    FLICK_ACTION_LONG_PRESS,
};

// Per-slot gesture state
enum flick_slot_state {
    FLICK_SLOT_NONE = 0,
    FLICK_SLOT_POTENTIAL_TAP,
    FLICK_SLOT_LONG_PRESS,
    FLICK_SLOT_EDGE_SWIPE,
    FLICK_SLOT_SWIPE,
    FLICK_SLOT_MULTI_TOUCH,
};

// Touch point data
struct flick_touch_point {
    int32_t id;
    bool active;

    // Positions
    double start_x, start_y;
    double current_x, current_y;

    // Velocity (pixels per second)
    double velocity_x, velocity_y;

    // Timing
    struct timespec start_time;
    struct timespec last_time;

    // Per-slot state
    enum flick_slot_state state;
    enum flick_edge edge;  // If state is EDGE_SWIPE
};

// Gesture event data
struct flick_gesture_event {
    enum flick_gesture_type type;

    // For tap/long_press
    double x, y;

    // For edge swipes
    enum flick_edge edge;
    double progress;   // 0.0 to 1.0+
    double velocity;
    bool completed;    // For swipe end: did it complete?
    uint32_t fingers;

    // For pinch
    double scale;
    double center_x, center_y;

    // For pan
    double delta_x, delta_y;
};

// Gesture configuration
struct flick_gesture_config {
    // Width of edge detection zone in pixels
    double edge_threshold;

    // Distance for swipe animation progress (larger = smoother)
    double swipe_threshold;

    // Distance required to complete/trigger a swipe action
    double swipe_complete_threshold;

    // Time threshold for long press (milliseconds)
    uint32_t long_press_ms;

    // Maximum time for a tap (milliseconds)
    uint32_t tap_ms;

    // Maximum movement for a tap (pixels)
    double tap_distance;

    // Velocity threshold for flick gestures
    double flick_velocity;
};

// Gesture recognizer
struct flick_gesture_recognizer {
    struct flick_gesture_config config;

    // Screen size
    int32_t screen_width;
    int32_t screen_height;

    // Touch points (indexed by slot, not touch id)
    struct flick_touch_point points[FLICK_MAX_TOUCH_POINTS];
    int active_count;

    // Multi-touch state
    bool multi_touch_active;
    double pinch_initial_distance;
};

// Initialize gesture recognizer
void flick_gesture_init(struct flick_gesture_recognizer *gesture,
                        int32_t screen_width, int32_t screen_height);

// Set screen size (e.g., on output change)
void flick_gesture_set_screen_size(struct flick_gesture_recognizer *gesture,
                                   int32_t width, int32_t height);

// Process touch events - returns true if event generated
bool flick_gesture_touch_down(struct flick_gesture_recognizer *gesture,
                              int32_t id, double x, double y,
                              struct flick_gesture_event *event);

bool flick_gesture_touch_motion(struct flick_gesture_recognizer *gesture,
                                int32_t id, double x, double y,
                                struct flick_gesture_event *event);

bool flick_gesture_touch_up(struct flick_gesture_recognizer *gesture,
                            int32_t id,
                            struct flick_gesture_event *event);

void flick_gesture_touch_cancel(struct flick_gesture_recognizer *gesture);

// Map gesture event to action
enum flick_gesture_action flick_gesture_to_action(
    const struct flick_gesture_event *event);

// Get readable name for action (for logging)
const char *flick_gesture_action_name(enum flick_gesture_action action);

// Get readable name for edge (for logging)
const char *flick_edge_name(enum flick_edge edge);

#endif // FLICK_GESTURE_H
