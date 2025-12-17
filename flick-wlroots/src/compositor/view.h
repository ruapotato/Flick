#ifndef FLICK_VIEW_H
#define FLICK_VIEW_H

#include <wayland-server-core.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/types/wlr_scene.h>

struct flick_server;

// A view represents a toplevel window
struct flick_view {
    struct flick_server *server;
    struct wlr_xdg_toplevel *xdg_toplevel;
    struct wlr_scene_tree *scene_tree;

    struct wl_list link;  // flick_server.views

    // Position
    int x, y;

    // Listeners
    struct wl_listener map;
    struct wl_listener unmap;
    struct wl_listener destroy;
    struct wl_listener request_move;
    struct wl_listener request_resize;
    struct wl_listener request_maximize;
    struct wl_listener request_fullscreen;
};

// Get view at given coordinates
struct flick_view *flick_view_at(struct flick_server *server,
    double lx, double ly,
    struct wlr_surface **surface,
    double *sx, double *sy);

// Focus a view (bring to front, give keyboard focus)
void flick_focus_view(struct flick_view *view, struct wlr_surface *surface);

// Called when new xdg toplevel is created
void flick_new_xdg_toplevel(struct wl_listener *listener, void *data);

// Called when new xdg popup is created
void flick_new_xdg_popup(struct wl_listener *listener, void *data);

#endif // FLICK_VIEW_H
