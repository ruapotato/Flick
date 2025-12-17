#define _POSIX_C_SOURCE 200809L

#include <stdlib.h>
#include <wlr/util/log.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_scene.h>
#include "server.h"
#include "output.h"
#include "input.h"
#include "view.h"

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

    // Create a dark blue background so we know rendering works
    // (visible when there are no clients)
    float bg_color[4] = {0.1f, 0.1f, 0.3f, 1.0f};  // Dark blue
    struct wlr_scene_rect *bg = wlr_scene_rect_create(
        &server->scene->tree, 4096, 4096, bg_color);
    if (bg) {
        wlr_log(WLR_INFO, "Created background rect (dark blue)");
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
