#ifndef FLICK_SERVER_H
#define FLICK_SERVER_H

#include <wayland-server-core.h>
#include <wlr/backend.h>
#include <wlr/backend/session.h>
#include <wlr/render/allocator.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_subcompositor.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_data_device.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_xcursor_manager.h>
#include "../shell/gesture.h"
#include "../shell/shell.h"

struct flick_server {
    struct wl_display *wl_display;
    struct wl_event_loop *wl_event_loop;

    struct wlr_backend *backend;
    struct wlr_session *session;
    struct wlr_renderer *renderer;
    struct wlr_allocator *allocator;

    // Session event listeners (for VT switching)
    struct wl_listener session_active;
    struct wl_listener session_destroy;

    // Scene graph for rendering
    struct wlr_scene *scene;
    struct wlr_output_layout *output_layout;
    struct wlr_scene_output_layout *scene_layout;
    struct wlr_scene_rect *background;  // Shell background color

    // Wayland protocols
    struct wlr_compositor *compositor;
    struct wlr_subcompositor *subcompositor;
    struct wlr_xdg_shell *xdg_shell;
    struct wlr_seat *seat;
    struct wlr_data_device_manager *data_device_manager;

    // Cursor
    struct wlr_cursor *cursor;
    struct wlr_xcursor_manager *cursor_mgr;
    struct wl_listener cursor_motion;
    struct wl_listener cursor_motion_absolute;
    struct wl_listener cursor_button;
    struct wl_listener cursor_axis;
    struct wl_listener cursor_frame;

    // Seat request listeners
    struct wl_listener request_cursor;
    struct wl_listener request_set_selection;

    // Pointer gesture tracking (for testing without touchscreen)
    bool pointer_dragging;
    double pointer_drag_start_x;
    double pointer_drag_start_y;

    struct wl_list outputs;  // flick_output.link
    struct wl_list inputs;   // flick_input.link
    struct wl_list views;    // flick_view.link

    struct wl_listener new_output;
    struct wl_listener new_input;
    struct wl_listener new_xdg_toplevel;
    struct wl_listener new_xdg_popup;

    // Display dimensions (for touch coordinate normalization)
    int32_t output_width;
    int32_t output_height;

    // Gesture recognition
    struct flick_gesture_recognizer gesture;

    // Shell state machine
    struct flick_shell shell;
};

// Initialize the server (creates backend, renderer, allocator)
bool flick_server_init(struct flick_server *server);

// Start the backend (begins output/input enumeration)
bool flick_server_start(struct flick_server *server);

// Run the main event loop
void flick_server_run(struct flick_server *server);

// Cleanup
void flick_server_destroy(struct flick_server *server);

#endif // FLICK_SERVER_H
