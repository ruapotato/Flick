#define _POSIX_C_SOURCE 200809L

#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <linux/input-event-codes.h>
#include <wlr/util/log.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_scene.h>
#include "server.h"
#include "output.h"
#include "input.h"
#include "view.h"
#include "../shell/shell.h"
#include "../shell/gesture.h"

// Forward declarations
static struct flick_view *view_at(struct flick_server *server,
    double lx, double ly, struct wlr_surface **surface,
    double *sx, double *sy);

// Session event handlers (for VT switching)
static void session_active_notify(struct wl_listener *listener, void *data) {
    struct flick_server *server = wl_container_of(listener, server, session_active);
    bool active = server->session->active;
    wlr_log(WLR_INFO, "Session %s", active ? "activated" : "deactivated");
}

static void session_destroy_notify(struct wl_listener *listener, void *data) {
    struct flick_server *server = wl_container_of(listener, server, session_destroy);
    wlr_log(WLR_INFO, "Session destroyed");
    wl_display_terminate(server->wl_display);
}

// Find view at given coordinates
static struct flick_view *view_at(struct flick_server *server,
    double lx, double ly, struct wlr_surface **surface,
    double *sx, double *sy) {

    struct wlr_scene_node *node = wlr_scene_node_at(
        &server->scene->tree.node, lx, ly, sx, sy);
    if (!node || node->type != WLR_SCENE_NODE_BUFFER) {
        return NULL;
    }

    struct wlr_scene_buffer *scene_buffer = wlr_scene_buffer_from_node(node);
    struct wlr_scene_surface *scene_surface =
        wlr_scene_surface_try_from_buffer(scene_buffer);
    if (!scene_surface) {
        return NULL;
    }

    *surface = scene_surface->surface;

    // Walk up the tree to find our view's scene_tree
    struct wlr_scene_tree *tree = node->parent;
    while (tree && !tree->node.data) {
        tree = tree->node.parent;
    }
    return tree ? tree->node.data : NULL;
}

// Process cursor motion
static void process_cursor_motion(struct flick_server *server, uint32_t time) {
    // If dragging, feed to gesture recognizer (for testing edge swipes with mouse)
    if (server->pointer_dragging) {
        struct flick_gesture_event gesture_event = {0};
        if (flick_gesture_touch_motion(&server->gesture, 0,
                server->cursor->x, server->cursor->y, &gesture_event)) {
            flick_shell_handle_gesture(&server->shell, &gesture_event);
        }
        return;  // Don't send to clients while gesturing
    }

    double sx, sy;
    struct wlr_surface *surface = NULL;
    struct flick_view *view = view_at(server,
        server->cursor->x, server->cursor->y, &surface, &sx, &sy);

    if (!view) {
        // No view under cursor - set default cursor
        wlr_cursor_set_xcursor(server->cursor, server->cursor_mgr, "default");
    }

    if (surface) {
        // Send pointer enter/motion events to the surface
        wlr_seat_pointer_notify_enter(server->seat, surface, sx, sy);
        wlr_seat_pointer_notify_motion(server->seat, time, sx, sy);
    } else {
        // Clear pointer focus
        wlr_seat_pointer_clear_focus(server->seat);
    }
}

// Cursor motion event (relative)
static void cursor_motion_notify(struct wl_listener *listener, void *data) {
    struct flick_server *server = wl_container_of(listener, server, cursor_motion);
    struct wlr_pointer_motion_event *event = data;

    wlr_cursor_move(server->cursor, &event->pointer->base,
        event->delta_x, event->delta_y);
    process_cursor_motion(server, event->time_msec);
}

// Cursor motion event (absolute - touchpads, tablets)
static void cursor_motion_absolute_notify(struct wl_listener *listener, void *data) {
    struct flick_server *server = wl_container_of(listener, server, cursor_motion_absolute);
    struct wlr_pointer_motion_absolute_event *event = data;

    wlr_cursor_warp_absolute(server->cursor, &event->pointer->base, event->x, event->y);
    process_cursor_motion(server, event->time_msec);
}

// Cursor button event
static void cursor_button_notify(struct wl_listener *listener, void *data) {
    struct flick_server *server = wl_container_of(listener, server, cursor_button);
    struct wlr_pointer_button_event *event = data;

    // Left button for gestures (edge swipes with mouse)
    if (event->button == BTN_LEFT) {
        if (event->state == WL_POINTER_BUTTON_STATE_PRESSED) {
            // Start tracking drag for gesture
            server->pointer_dragging = true;
            server->pointer_drag_start_x = server->cursor->x;
            server->pointer_drag_start_y = server->cursor->y;

            // Feed to gesture recognizer
            struct flick_gesture_event gesture_event = {0};
            if (flick_gesture_touch_down(&server->gesture, 0,
                    server->cursor->x, server->cursor->y, &gesture_event)) {
                flick_shell_handle_gesture(&server->shell, &gesture_event);
            }
        } else {
            // End drag
            if (server->pointer_dragging) {
                server->pointer_dragging = false;

                struct flick_gesture_event gesture_event = {0};
                if (flick_gesture_touch_up(&server->gesture, 0, &gesture_event)) {
                    flick_shell_handle_gesture(&server->shell, &gesture_event);

                    // Handle the action from completed gesture
                    enum flick_gesture_action action = flick_gesture_to_action(&gesture_event);
                    if (action != FLICK_ACTION_NONE) {
                        flick_shell_handle_action(&server->shell, action);
                    }
                }
            }
        }
        return;
    }

    wlr_seat_pointer_notify_button(server->seat,
        event->time_msec, event->button, event->state);

    // Focus the view under cursor on click (non-left buttons)
    if (event->state == WL_POINTER_BUTTON_STATE_PRESSED) {
        double sx, sy;
        struct wlr_surface *surface = NULL;
        struct flick_view *view = view_at(server,
            server->cursor->x, server->cursor->y, &surface, &sx, &sy);

        if (view && surface) {
            flick_focus_view(view, surface);
        }
    }
}

// Cursor axis event (scroll wheel)
static void cursor_axis_notify(struct wl_listener *listener, void *data) {
    struct flick_server *server = wl_container_of(listener, server, cursor_axis);
    struct wlr_pointer_axis_event *event = data;

    wlr_seat_pointer_notify_axis(server->seat,
        event->time_msec, event->orientation, event->delta,
        event->delta_discrete, event->source, event->relative_direction);
}

// Cursor frame event (end of a set of events)
static void cursor_frame_notify(struct wl_listener *listener, void *data) {
    struct flick_server *server = wl_container_of(listener, server, cursor_frame);
    wlr_seat_pointer_notify_frame(server->seat);
}

// Client requests to set cursor image
static void seat_request_cursor_notify(struct wl_listener *listener, void *data) {
    struct flick_server *server = wl_container_of(listener, server, request_cursor);
    struct wlr_seat_pointer_request_set_cursor_event *event = data;

    struct wlr_seat_client *focused_client = server->seat->pointer_state.focused_client;
    if (focused_client == event->seat_client) {
        wlr_cursor_set_surface(server->cursor, event->surface,
            event->hotspot_x, event->hotspot_y);
    }
}

// Client requests to set selection (clipboard)
static void seat_request_set_selection_notify(struct wl_listener *listener, void *data) {
    struct flick_server *server = wl_container_of(listener, server, request_set_selection);
    struct wlr_seat_request_set_selection_event *event = data;
    wlr_seat_set_selection(server->seat, event->source, event->serial);
}

bool flick_server_init(struct flick_server *server) {
    wlr_log(WLR_INFO, "Initializing Flick server");

    server->wl_display = wl_display_create();
    if (!server->wl_display) {
        wlr_log(WLR_ERROR, "Failed to create Wayland display");
        return false;
    }

    server->wl_event_loop = wl_display_get_event_loop(server->wl_display);

    // Initialize lists
    wl_list_init(&server->outputs);
    wl_list_init(&server->inputs);
    wl_list_init(&server->views);

    // Create backend - automatically selects DRM, hwcomposer, Wayland, or X11
    // Can be overridden with WLR_BACKENDS environment variable
    server->backend = wlr_backend_autocreate(server->wl_event_loop, &server->session);
    if (!server->backend) {
        wlr_log(WLR_ERROR, "Failed to create wlroots backend");
        wl_display_destroy(server->wl_display);
        return false;
    }

    // Log session info (important for VT switching)
    if (server->session) {
        wlr_log(WLR_INFO, "Session created: active=%d", server->session->active);

        // Listen for session events (VT switching)
        server->session_active.notify = session_active_notify;
        wl_signal_add(&server->session->events.active, &server->session_active);

        server->session_destroy.notify = session_destroy_notify;
        wl_signal_add(&server->session->events.destroy, &server->session_destroy);
    } else {
        wlr_log(WLR_INFO, "No session (probably nested in Wayland/X11)");
    }

    // Create renderer
    server->renderer = wlr_renderer_autocreate(server->backend);
    if (!server->renderer) {
        wlr_log(WLR_ERROR, "Failed to create renderer");
        wlr_backend_destroy(server->backend);
        wl_display_destroy(server->wl_display);
        return false;
    }

    // Initialize renderer for shared memory buffers
    wlr_renderer_init_wl_shm(server->renderer, server->wl_display);

    // Create allocator
    server->allocator = wlr_allocator_autocreate(server->backend, server->renderer);
    if (!server->allocator) {
        wlr_log(WLR_ERROR, "Failed to create allocator");
        wlr_backend_destroy(server->backend);
        wl_display_destroy(server->wl_display);
        return false;
    }

    // Create scene graph for rendering
    server->scene = wlr_scene_create();
    if (!server->scene) {
        wlr_log(WLR_ERROR, "Failed to create scene");
        wlr_backend_destroy(server->backend);
        wl_display_destroy(server->wl_display);
        return false;
    }

    // Create output layout for scene
    server->output_layout = wlr_output_layout_create(server->wl_display);
    server->scene_layout = wlr_scene_attach_output_layout(server->scene, server->output_layout);

    // Create background rect for shell
    float bg_color[4] = {0.1f, 0.1f, 0.3f, 1.0f};  // Dark blue (home)
    server->background = wlr_scene_rect_create(
        &server->scene->tree, 4096, 4096, bg_color);
    if (server->background) {
        wlr_log(WLR_INFO, "Created background rect");
    } else {
        wlr_log(WLR_ERROR, "Failed to create background rect");
    }

    // Create compositor (wl_compositor and wl_subcompositor protocols)
    server->compositor = wlr_compositor_create(server->wl_display, 5, server->renderer);
    if (!server->compositor) {
        wlr_log(WLR_ERROR, "Failed to create compositor");
        wlr_backend_destroy(server->backend);
        wl_display_destroy(server->wl_display);
        return false;
    }

    server->subcompositor = wlr_subcompositor_create(server->wl_display);

    // Create xdg-shell for window management
    server->xdg_shell = wlr_xdg_shell_create(server->wl_display, 3);
    if (!server->xdg_shell) {
        wlr_log(WLR_ERROR, "Failed to create xdg-shell");
        wlr_backend_destroy(server->backend);
        wl_display_destroy(server->wl_display);
        return false;
    }

    // Setup xdg-shell listeners
    server->new_xdg_toplevel.notify = flick_new_xdg_toplevel;
    wl_signal_add(&server->xdg_shell->events.new_toplevel, &server->new_xdg_toplevel);

    server->new_xdg_popup.notify = flick_new_xdg_popup;
    wl_signal_add(&server->xdg_shell->events.new_popup, &server->new_xdg_popup);

    // Create seat for input management
    server->seat = wlr_seat_create(server->wl_display, "seat0");
    if (!server->seat) {
        wlr_log(WLR_ERROR, "Failed to create seat");
        wlr_backend_destroy(server->backend);
        wl_display_destroy(server->wl_display);
        return false;
    }

    // Create data device manager for clipboard
    server->data_device_manager = wlr_data_device_manager_create(server->wl_display);

    // Create cursor
    server->cursor = wlr_cursor_create();
    if (!server->cursor) {
        wlr_log(WLR_ERROR, "Failed to create cursor");
        wlr_backend_destroy(server->backend);
        wl_display_destroy(server->wl_display);
        return false;
    }
    wlr_cursor_attach_output_layout(server->cursor, server->output_layout);

    // Create xcursor manager for cursor themes
    server->cursor_mgr = wlr_xcursor_manager_create(NULL, 24);
    if (server->cursor_mgr) {
        wlr_xcursor_manager_load(server->cursor_mgr, 1);
        wlr_log(WLR_INFO, "Cursor manager created");
    }

    // Setup cursor event listeners
    server->cursor_motion.notify = cursor_motion_notify;
    wl_signal_add(&server->cursor->events.motion, &server->cursor_motion);

    server->cursor_motion_absolute.notify = cursor_motion_absolute_notify;
    wl_signal_add(&server->cursor->events.motion_absolute, &server->cursor_motion_absolute);

    server->cursor_button.notify = cursor_button_notify;
    wl_signal_add(&server->cursor->events.button, &server->cursor_button);

    server->cursor_axis.notify = cursor_axis_notify;
    wl_signal_add(&server->cursor->events.axis, &server->cursor_axis);

    server->cursor_frame.notify = cursor_frame_notify;
    wl_signal_add(&server->cursor->events.frame, &server->cursor_frame);

    // Setup seat request listeners
    server->request_cursor.notify = seat_request_cursor_notify;
    wl_signal_add(&server->seat->events.request_set_cursor, &server->request_cursor);

    server->request_set_selection.notify = seat_request_set_selection_notify;
    wl_signal_add(&server->seat->events.request_set_selection, &server->request_set_selection);

    // Setup output listener
    server->new_output.notify = flick_new_output_notify;
    wl_signal_add(&server->backend->events.new_output, &server->new_output);

    // Setup input listener
    server->new_input.notify = flick_new_input_notify;
    wl_signal_add(&server->backend->events.new_input, &server->new_input);

    // Initialize gesture recognizer (will be updated when output is configured)
    flick_gesture_init(&server->gesture, 1280, 720);

    // Initialize shell state machine
    flick_shell_init(&server->shell, server);

    wlr_log(WLR_INFO, "Server initialized successfully");
    return true;
}

// Launch a command in the background
static void launch_command(const char *cmd) {
    pid_t pid = fork();
    if (pid == 0) {
        // Child process
        execl("/bin/sh", "/bin/sh", "-c", cmd, NULL);
        _exit(EXIT_FAILURE);
    } else if (pid < 0) {
        wlr_log(WLR_ERROR, "Failed to fork for command: %s", cmd);
    } else {
        wlr_log(WLR_INFO, "Launched: %s (pid %d)", cmd, pid);
    }
}

bool flick_server_start(struct flick_server *server) {
    wlr_log(WLR_INFO, "Starting Flick backend");

    // Add Wayland socket for clients to connect
    const char *socket = wl_display_add_socket_auto(server->wl_display);
    if (!socket) {
        wlr_log(WLR_ERROR, "Failed to create Wayland socket");
        return false;
    }

    // Set WAYLAND_DISPLAY for child processes
    setenv("WAYLAND_DISPLAY", socket, true);
    wlr_log(WLR_INFO, "Wayland socket: %s", socket);

    if (!wlr_backend_start(server->backend)) {
        wlr_log(WLR_ERROR, "Failed to start backend");
        return false;
    }

    wlr_log(WLR_INFO, "Backend started successfully");

    // Auto-launch a terminal for testing (try foot, then alacritty, then xterm)
    const char *terminal = getenv("FLICK_TERMINAL");
    if (terminal) {
        launch_command(terminal);
    } else {
        // Try common terminals in order of preference
        if (access("/usr/bin/foot", X_OK) == 0) {
            launch_command("foot");
        } else if (access("/usr/bin/alacritty", X_OK) == 0) {
            launch_command("alacritty");
        } else if (access("/usr/bin/weston-terminal", X_OK) == 0) {
            launch_command("weston-terminal");
        } else {
            wlr_log(WLR_INFO, "No terminal found to auto-launch");
        }
    }

    return true;
}

void flick_server_run(struct flick_server *server) {
    wlr_log(WLR_INFO, "Running Flick event loop");
    wl_display_run(server->wl_display);
}

void flick_server_destroy(struct flick_server *server) {
    wlr_log(WLR_INFO, "Destroying Flick server");

    // Outputs and inputs will be cleaned up by backend destroy
    wlr_backend_destroy(server->backend);
    wl_display_destroy(server->wl_display);
}
