#ifndef FLICK_INPUT_H
#define FLICK_INPUT_H

#include <wayland-server-core.h>
#include <wlr/types/wlr_input_device.h>
#include <wlr/types/wlr_keyboard.h>
#include <wlr/types/wlr_touch.h>

struct flick_server;

// Generic input device wrapper
struct flick_input {
    struct flick_server *server;
    struct wlr_input_device *wlr_device;
    struct wl_list link;  // flick_server.inputs

    struct wl_listener destroy;
};

// Keyboard-specific wrapper
struct flick_keyboard {
    struct flick_input base;
    struct wlr_keyboard *wlr_keyboard;

    struct wl_listener key;
    struct wl_listener modifiers;
};

// Touch-specific wrapper
struct flick_touch {
    struct flick_input base;
    struct wlr_touch *wlr_touch;

    struct wl_listener down;
    struct wl_listener up;
    struct wl_listener motion;
    struct wl_listener cancel;
};

// Called when a new input device is added
void flick_new_input_notify(struct wl_listener *listener, void *data);

#endif // FLICK_INPUT_H
