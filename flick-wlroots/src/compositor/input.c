#define _POSIX_C_SOURCE 200809L

#include <stdlib.h>
#include <wlr/util/log.h>
#include <wlr/version.h>
#include <xkbcommon/xkbcommon.h>
#include "input.h"
#include "server.h"
#include "view.h"
#include "../shell/shell.h"

// --- Keyboard handling ---

static void keyboard_modifiers_notify(struct wl_listener *listener, void *data) {
    struct flick_keyboard *keyboard = wl_container_of(listener, keyboard, modifiers);
    struct flick_server *server = keyboard->base.server;

    // Forward modifiers to focused client
    wlr_seat_set_keyboard(server->seat, keyboard->wlr_keyboard);
    wlr_seat_keyboard_notify_modifiers(server->seat,
        &keyboard->wlr_keyboard->modifiers);
}

static void keyboard_key_notify(struct wl_listener *listener, void *data) {
    struct flick_keyboard *keyboard = wl_container_of(listener, keyboard, key);
    struct flick_server *server = keyboard->base.server;
    struct wlr_keyboard_key_event *event = data;

    // Get keysym
    uint32_t keycode = event->keycode + 8;
    const xkb_keysym_t *syms;
    int nsyms = xkb_state_key_get_syms(
        keyboard->wlr_keyboard->xkb_state, keycode, &syms);

    // Check modifiers for debugging VT switching
    uint32_t mods = wlr_keyboard_get_modifiers(keyboard->wlr_keyboard);
    bool ctrl = mods & WLR_MODIFIER_CTRL;
    bool alt = mods & WLR_MODIFIER_ALT;

    bool handled = false;
    if (event->state == WL_KEYBOARD_KEY_STATE_PRESSED) {
        for (int i = 0; i < nsyms; i++) {
            xkb_keysym_t sym = syms[i];

            // Log ALL key presses at INFO level for debugging
            char name[64];
            xkb_keysym_get_name(sym, name, sizeof(name));
            wlr_log(WLR_INFO, "KEY: %s (0x%x) mods=%s%s keycode=%d",
                    name, sym,
                    ctrl ? "Ctrl+" : "",
                    alt ? "Alt+" : "",
                    event->keycode);

            // Handle VT switching (XF86Switch_VT_1 through XF86Switch_VT_12)
            if (sym >= XKB_KEY_XF86Switch_VT_1 && sym <= XKB_KEY_XF86Switch_VT_12) {
                unsigned vt = sym - XKB_KEY_XF86Switch_VT_1 + 1;
                if (server->session) {
                    wlr_log(WLR_INFO, "Switching to VT %d", vt);
                    wlr_session_change_vt(server->session, vt);
                    handled = true;
                } else {
                    wlr_log(WLR_INFO, "VT switch requested but no session available");
                }
            }

            // Alt+Tab: cycle between views/apps
            if (alt && sym == XKB_KEY_Tab) {
                wlr_log(WLR_INFO, "Alt+Tab: cycling apps");
                // Focus the next view in the list
                if (!wl_list_empty(&server->views)) {
                    struct flick_view *current = NULL;
                    struct wlr_surface *focused = server->seat->keyboard_state.focused_surface;
                    if (focused) {
                        struct wlr_xdg_surface *xdg = wlr_xdg_surface_try_from_wlr_surface(focused);
                        if (xdg && xdg->role == WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
                            // Find the view for this surface
                            struct flick_view *v;
                            wl_list_for_each(v, &server->views, link) {
                                if (v->xdg_toplevel->base == xdg) {
                                    current = v;
                                    break;
                                }
                            }
                        }
                    }
                    // Get next view (or first if no current)
                    struct flick_view *next = NULL;
                    if (current && current->link.next != &server->views) {
                        next = wl_container_of(current->link.next, next, link);
                    } else {
                        next = wl_container_of(server->views.next, next, link);
                    }
                    if (next) {
                        flick_focus_view(next, next->xdg_toplevel->base->surface);
                    }
                }
                handled = true;
            }

            // Super/Meta: go home
            if (sym == XKB_KEY_Super_L || sym == XKB_KEY_Super_R) {
                wlr_log(WLR_INFO, "Super key: going home");
                flick_shell_go_to_view(&server->shell, FLICK_VIEW_HOME);
                handled = true;
            }

            // Alt+F4: close focused window
            if (alt && sym == XKB_KEY_F4) {
                struct wlr_surface *focused = server->seat->keyboard_state.focused_surface;
                if (focused) {
                    struct wlr_xdg_surface *xdg = wlr_xdg_surface_try_from_wlr_surface(focused);
                    if (xdg && xdg->role == WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
                        wlr_log(WLR_INFO, "Alt+F4: closing window");
                        wlr_xdg_toplevel_send_close(xdg->toplevel);
                        handled = true;
                    }
                }
            }

            // Escape to quit (for testing)
            if (sym == XKB_KEY_Escape) {
                wlr_log(WLR_INFO, "Escape pressed, terminating");
                wl_display_terminate(server->wl_display);
                handled = true;
            }
        }
    }

    // Forward key event to focused client if not handled by compositor
    if (!handled) {
        wlr_seat_set_keyboard(server->seat, keyboard->wlr_keyboard);
        wlr_seat_keyboard_notify_key(server->seat, event->time_msec,
            event->keycode, event->state);
    }
}

static void keyboard_destroy_notify(struct wl_listener *listener, void *data) {
    struct flick_keyboard *keyboard = wl_container_of(listener, keyboard, base.destroy);

    wlr_log(WLR_INFO, "Keyboard destroyed");

    wl_list_remove(&keyboard->key.link);
    wl_list_remove(&keyboard->modifiers.link);
    wl_list_remove(&keyboard->base.destroy.link);
    wl_list_remove(&keyboard->base.link);

    free(keyboard);
}

static void handle_new_keyboard(struct flick_server *server,
                                 struct wlr_input_device *device) {
    struct flick_keyboard *keyboard = calloc(1, sizeof(*keyboard));
    if (!keyboard) {
        wlr_log(WLR_ERROR, "Failed to allocate keyboard");
        return;
    }

    keyboard->base.server = server;
    keyboard->base.wlr_device = device;
    keyboard->wlr_keyboard = wlr_keyboard_from_input_device(device);

    if (!keyboard->wlr_keyboard) {
        wlr_log(WLR_ERROR, "Failed to get keyboard from device: %s", device->name);
        free(keyboard);
        return;
    }

    wlr_log(WLR_INFO, "Setting up keyboard: %s", device->name);

    // Setup XKB keymap
    struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    if (!context) {
        wlr_log(WLR_ERROR, "Failed to create XKB context");
        free(keyboard);
        return;
    }

    struct xkb_keymap *keymap = xkb_keymap_new_from_names(
        context, NULL, XKB_KEYMAP_COMPILE_NO_FLAGS);
    if (!keymap) {
        wlr_log(WLR_ERROR, "Failed to create XKB keymap");
        xkb_context_unref(context);
        free(keyboard);
        return;
    }

    wlr_keyboard_set_keymap(keyboard->wlr_keyboard, keymap);
    xkb_keymap_unref(keymap);
    xkb_context_unref(context);

    // Set repeat rate
    wlr_keyboard_set_repeat_info(keyboard->wlr_keyboard, 25, 600);

    // Setup listeners
    keyboard->modifiers.notify = keyboard_modifiers_notify;
    wl_signal_add(&keyboard->wlr_keyboard->events.modifiers, &keyboard->modifiers);

    keyboard->key.notify = keyboard_key_notify;
    wl_signal_add(&keyboard->wlr_keyboard->events.key, &keyboard->key);

    keyboard->base.destroy.notify = keyboard_destroy_notify;
    wl_signal_add(&device->events.destroy, &keyboard->base.destroy);

    wl_list_insert(&server->inputs, &keyboard->base.link);

    // Set keyboard on seat and update capabilities
    wlr_seat_set_keyboard(server->seat, keyboard->wlr_keyboard);
    uint32_t caps = WL_SEAT_CAPABILITY_KEYBOARD;
    wlr_seat_set_capabilities(server->seat, caps);

    wlr_log(WLR_INFO, "Keyboard configured");
}

// --- Touch handling ---

static void touch_down_notify(struct wl_listener *listener, void *data) {
    struct flick_touch *touch = wl_container_of(listener, touch, down);
    struct flick_server *server = touch->base.server;
    struct wlr_touch_down_event *event = data;

    // Convert normalized coordinates to screen pixels
    double x = event->x * server->output_width;
    double y = event->y * server->output_height;

    wlr_log(WLR_INFO, "Touch DOWN: id=%d pos=(%.0f, %.0f) shell.view=%d",
            event->touch_id, x, y, server->shell.current_view);

    // Process through gesture recognizer
    struct flick_gesture_event gesture_event = {0};
    if (flick_gesture_touch_down(&server->gesture, event->touch_id, x, y,
                                  &gesture_event)) {
        // Route to shell for handling
        flick_shell_handle_gesture(&server->shell, &gesture_event);
    }
}

static void touch_up_notify(struct wl_listener *listener, void *data) {
    struct flick_touch *touch = wl_container_of(listener, touch, up);
    struct flick_server *server = touch->base.server;
    struct wlr_touch_up_event *event = data;

    wlr_log(WLR_INFO, "Touch UP: id=%d", event->touch_id);

    // Process through gesture recognizer
    struct flick_gesture_event gesture_event = {0};
    if (flick_gesture_touch_up(&server->gesture, event->touch_id, &gesture_event)) {
        // Route to shell for handling
        flick_shell_handle_gesture(&server->shell, &gesture_event);

        // Also handle the resulting action
        enum flick_gesture_action action = flick_gesture_to_action(&gesture_event);
        if (action != FLICK_ACTION_NONE) {
            flick_shell_handle_action(&server->shell, action);
        }
    }
}

static void touch_motion_notify(struct wl_listener *listener, void *data) {
    struct flick_touch *touch = wl_container_of(listener, touch, motion);
    struct flick_server *server = touch->base.server;
    struct wlr_touch_motion_event *event = data;

    double x = event->x * server->output_width;
    double y = event->y * server->output_height;

    // Process through gesture recognizer
    struct flick_gesture_event gesture_event = {0};
    if (flick_gesture_touch_motion(&server->gesture, event->touch_id, x, y,
                                    &gesture_event)) {
        // Route to shell for handling (tracks transition progress)
        flick_shell_handle_gesture(&server->shell, &gesture_event);
    }
}

static void touch_cancel_notify(struct wl_listener *listener, void *data) {
    struct flick_touch *touch = wl_container_of(listener, touch, cancel);
    struct flick_server *server = touch->base.server;
    struct wlr_touch_cancel_event *event = data;

    wlr_log(WLR_DEBUG, "Touch cancel: id=%d", event->touch_id);

    // Clear gesture state
    flick_gesture_touch_cancel(&server->gesture);
}

static void touch_destroy_notify(struct wl_listener *listener, void *data) {
    struct flick_touch *touch = wl_container_of(listener, touch, base.destroy);

    wlr_log(WLR_INFO, "Touch device destroyed");

    wl_list_remove(&touch->down.link);
    wl_list_remove(&touch->up.link);
    wl_list_remove(&touch->motion.link);
    wl_list_remove(&touch->cancel.link);
    wl_list_remove(&touch->base.destroy.link);
    wl_list_remove(&touch->base.link);

    free(touch);
}

static void handle_new_touch(struct flick_server *server,
                              struct wlr_input_device *device) {
    struct flick_touch *touch = calloc(1, sizeof(*touch));
    if (!touch) {
        wlr_log(WLR_ERROR, "Failed to allocate touch");
        return;
    }

    touch->base.server = server;
    touch->base.wlr_device = device;
    touch->wlr_touch = wlr_touch_from_input_device(device);

    wlr_log(WLR_INFO, "Touch: server=%p shell=%p shell.current_view=%d",
            (void*)server, (void*)&server->shell, server->shell.current_view);

    if (!touch->wlr_touch) {
        wlr_log(WLR_ERROR, "Failed to get touch from device: %s", device->name);
        free(touch);
        return;
    }

    // Setup listeners
    touch->down.notify = touch_down_notify;
    wl_signal_add(&touch->wlr_touch->events.down, &touch->down);

    touch->up.notify = touch_up_notify;
    wl_signal_add(&touch->wlr_touch->events.up, &touch->up);

    touch->motion.notify = touch_motion_notify;
    wl_signal_add(&touch->wlr_touch->events.motion, &touch->motion);

    touch->cancel.notify = touch_cancel_notify;
    wl_signal_add(&touch->wlr_touch->events.cancel, &touch->cancel);

    touch->base.destroy.notify = touch_destroy_notify;
    wl_signal_add(&device->events.destroy, &touch->base.destroy);

    wl_list_insert(&server->inputs, &touch->base.link);

    // Update seat capabilities to include touch
    uint32_t caps = WL_SEAT_CAPABILITY_TOUCH;
    struct flick_input *input;
    wl_list_for_each(input, &server->inputs, link) {
        if (input->wlr_device->type == WLR_INPUT_DEVICE_KEYBOARD) {
            caps |= WL_SEAT_CAPABILITY_KEYBOARD;
        }
        if (input->wlr_device->type == WLR_INPUT_DEVICE_POINTER) {
            caps |= WL_SEAT_CAPABILITY_POINTER;
        }
    }
    wlr_seat_set_capabilities(server->seat, caps);

    wlr_log(WLR_INFO, "Touch device configured (caps=0x%x)", caps);
}

// --- Pointer handling ---

static void pointer_destroy_notify(struct wl_listener *listener, void *data) {
    struct flick_pointer *pointer = wl_container_of(listener, pointer, base.destroy);

    wlr_log(WLR_INFO, "Pointer destroyed");

    wl_list_remove(&pointer->base.destroy.link);
    wl_list_remove(&pointer->base.link);

    free(pointer);
}

static void handle_new_pointer(struct flick_server *server,
                                struct wlr_input_device *device) {
    struct flick_pointer *pointer = calloc(1, sizeof(*pointer));
    if (!pointer) {
        wlr_log(WLR_ERROR, "Failed to allocate pointer");
        return;
    }

    pointer->base.server = server;
    pointer->base.wlr_device = device;
    pointer->wlr_pointer = wlr_pointer_from_input_device(device);

    if (!pointer->wlr_pointer) {
        wlr_log(WLR_ERROR, "Failed to get pointer from device: %s", device->name);
        free(pointer);
        return;
    }

    wlr_log(WLR_INFO, "Setting up pointer: %s", device->name);

    // Attach pointer to cursor
    wlr_cursor_attach_input_device(server->cursor, device);

    pointer->base.destroy.notify = pointer_destroy_notify;
    wl_signal_add(&device->events.destroy, &pointer->base.destroy);

    wl_list_insert(&server->inputs, &pointer->base.link);

    // Update seat capabilities
    uint32_t caps = WL_SEAT_CAPABILITY_POINTER;
    if (!wl_list_empty(&server->inputs)) {
        // Check if we have keyboards too
        struct flick_input *input;
        wl_list_for_each(input, &server->inputs, link) {
            if (input->wlr_device->type == WLR_INPUT_DEVICE_KEYBOARD) {
                caps |= WL_SEAT_CAPABILITY_KEYBOARD;
                break;
            }
        }
    }
    wlr_seat_set_capabilities(server->seat, caps);

    wlr_log(WLR_INFO, "Pointer configured");
}

// --- Input device enumeration ---

void flick_new_input_notify(struct wl_listener *listener, void *data) {
    struct flick_server *server = wl_container_of(listener, server, new_input);
    struct wlr_input_device *device = data;

    wlr_log(WLR_INFO, "New input device: %s (type=%d)",
            device->name, device->type);

    switch (device->type) {
    case WLR_INPUT_DEVICE_KEYBOARD:
        handle_new_keyboard(server, device);
        break;
    case WLR_INPUT_DEVICE_TOUCH:
        handle_new_touch(server, device);
        break;
    case WLR_INPUT_DEVICE_POINTER:
        handle_new_pointer(server, device);
        break;
    // Handle tablet - wlroots 0.18 renamed TABLET_TOOL to TABLET
#if WLR_VERSION_MINOR >= 18
    case WLR_INPUT_DEVICE_TABLET:  // wlroots 0.18+
#else
    case WLR_INPUT_DEVICE_TABLET_TOOL:  // wlroots 0.17
#endif
    case WLR_INPUT_DEVICE_TABLET_PAD:
        wlr_log(WLR_INFO, "Tablet device (not yet handled)");
        break;
    case WLR_INPUT_DEVICE_SWITCH:
        wlr_log(WLR_INFO, "Switch device (not yet handled)");
        break;
    }
}
