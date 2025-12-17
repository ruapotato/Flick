#define _POSIX_C_SOURCE 200809L

#include <stdlib.h>
#include <wlr/util/log.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_xdg_shell.h>
#include "view.h"
#include "server.h"

void flick_focus_view(struct flick_view *view, struct wlr_surface *surface) {
    if (view == NULL) {
        return;
    }

    struct flick_server *server = view->server;
    struct wlr_seat *seat = server->seat;
    struct wlr_surface *prev_surface = seat->keyboard_state.focused_surface;

    if (prev_surface == surface) {
        // Already focused
        return;
    }

    if (prev_surface) {
        // Deactivate previous toplevel
        struct wlr_xdg_toplevel *prev_toplevel =
            wlr_xdg_toplevel_try_from_wlr_surface(prev_surface);
        if (prev_toplevel != NULL) {
            wlr_xdg_toplevel_set_activated(prev_toplevel, false);
        }
    }

    // Move view to front
    wlr_scene_node_raise_to_top(&view->scene_tree->node);

    // Move to front of views list
    wl_list_remove(&view->link);
    wl_list_insert(&server->views, &view->link);

    // Activate new toplevel
    wlr_xdg_toplevel_set_activated(view->xdg_toplevel, true);

    // Set keyboard focus
    struct wlr_keyboard *keyboard = wlr_seat_get_keyboard(seat);
    if (keyboard != NULL) {
        wlr_seat_keyboard_notify_enter(seat, view->xdg_toplevel->base->surface,
            keyboard->keycodes, keyboard->num_keycodes, &keyboard->modifiers);
    }

    wlr_log(WLR_DEBUG, "Focused view: %s",
            view->xdg_toplevel->title ? view->xdg_toplevel->title : "(untitled)");
}

struct flick_view *flick_view_at(struct flick_server *server,
        double lx, double ly,
        struct wlr_surface **surface,
        double *sx, double *sy) {

    struct wlr_scene_node *node = wlr_scene_node_at(
        &server->scene->tree.node, lx, ly, sx, sy);

    if (node == NULL || node->type != WLR_SCENE_NODE_BUFFER) {
        return NULL;
    }

    struct wlr_scene_buffer *scene_buffer = wlr_scene_buffer_from_node(node);
    struct wlr_scene_surface *scene_surface =
        wlr_scene_surface_try_from_buffer(scene_buffer);

    if (!scene_surface) {
        return NULL;
    }

    *surface = scene_surface->surface;

    // Find the view that owns this surface
    struct wlr_scene_tree *tree = node->parent;
    while (tree != NULL && tree->node.data == NULL) {
        tree = tree->node.parent;
    }

    return tree ? tree->node.data : NULL;
}

static void xdg_toplevel_map(struct wl_listener *listener, void *data) {
    struct flick_view *view = wl_container_of(listener, view, map);
    struct flick_server *server = view->server;

    wlr_log(WLR_INFO, "Toplevel mapped: %s",
            view->xdg_toplevel->title ? view->xdg_toplevel->title : "(untitled)");

    wl_list_insert(&server->views, &view->link);

    // For mobile: fullscreen all windows
    if (server->output_width > 0 && server->output_height > 0) {
        wlr_xdg_toplevel_set_size(view->xdg_toplevel,
            server->output_width, server->output_height);
        wlr_xdg_toplevel_set_fullscreen(view->xdg_toplevel, true);

        // Position at 0,0
        wlr_scene_node_set_position(&view->scene_tree->node, 0, 0);
    }

    // Focus the new view
    flick_focus_view(view, view->xdg_toplevel->base->surface);
}

static void xdg_toplevel_unmap(struct wl_listener *listener, void *data) {
    struct flick_view *view = wl_container_of(listener, view, unmap);

    wlr_log(WLR_INFO, "Toplevel unmapped: %s",
            view->xdg_toplevel->title ? view->xdg_toplevel->title : "(untitled)");

    // Remove from views list
    wl_list_remove(&view->link);

    // Reset keyboard focus if this was the focused surface
    struct wlr_seat *seat = view->server->seat;
    if (seat->keyboard_state.focused_surface ==
            view->xdg_toplevel->base->surface) {
        wlr_seat_keyboard_clear_focus(seat);

        // Focus next view if available
        if (!wl_list_empty(&view->server->views)) {
            struct flick_view *next_view = wl_container_of(
                view->server->views.next, next_view, link);
            flick_focus_view(next_view, next_view->xdg_toplevel->base->surface);
        }
    }
}

static void xdg_toplevel_destroy(struct wl_listener *listener, void *data) {
    struct flick_view *view = wl_container_of(listener, view, destroy);

    wlr_log(WLR_INFO, "Toplevel destroyed");

    wl_list_remove(&view->map.link);
    wl_list_remove(&view->unmap.link);
    wl_list_remove(&view->destroy.link);
    wl_list_remove(&view->request_move.link);
    wl_list_remove(&view->request_resize.link);
    wl_list_remove(&view->request_maximize.link);
    wl_list_remove(&view->request_fullscreen.link);

    free(view);
}

static void xdg_toplevel_request_move(struct wl_listener *listener, void *data) {
    // On mobile, we don't allow window movement
    wlr_log(WLR_DEBUG, "Move request ignored (mobile mode)");
}

static void xdg_toplevel_request_resize(struct wl_listener *listener, void *data) {
    // On mobile, we don't allow window resizing
    wlr_log(WLR_DEBUG, "Resize request ignored (mobile mode)");
}

static void xdg_toplevel_request_maximize(struct wl_listener *listener, void *data) {
    struct flick_view *view = wl_container_of(listener, view, request_maximize);
    struct flick_server *server = view->server;

    wlr_log(WLR_DEBUG, "Maximize request");

    if (view->xdg_toplevel->base->initialized) {
        wlr_xdg_toplevel_set_size(view->xdg_toplevel,
            server->output_width, server->output_height);
        wlr_xdg_toplevel_set_maximized(view->xdg_toplevel, true);
    }
}

static void xdg_toplevel_request_fullscreen(struct wl_listener *listener, void *data) {
    struct flick_view *view = wl_container_of(listener, view, request_fullscreen);
    struct flick_server *server = view->server;

    wlr_log(WLR_DEBUG, "Fullscreen request");

    if (view->xdg_toplevel->base->initialized) {
        wlr_xdg_toplevel_set_size(view->xdg_toplevel,
            server->output_width, server->output_height);
        wlr_xdg_toplevel_set_fullscreen(view->xdg_toplevel, true);
    }
}

void flick_new_xdg_toplevel(struct wl_listener *listener, void *data) {
    struct flick_server *server = wl_container_of(listener, server, new_xdg_toplevel);
    struct wlr_xdg_toplevel *xdg_toplevel = data;

    wlr_log(WLR_INFO, "New XDG toplevel: %s",
            xdg_toplevel->title ? xdg_toplevel->title : "(untitled)");

    // Create view
    struct flick_view *view = calloc(1, sizeof(*view));
    if (!view) {
        wlr_log(WLR_ERROR, "Failed to allocate view");
        return;
    }

    view->server = server;
    view->xdg_toplevel = xdg_toplevel;

    // Create scene tree for this view
    view->scene_tree = wlr_scene_xdg_surface_create(
        &server->scene->tree, xdg_toplevel->base);
    view->scene_tree->node.data = view;

    // Position at origin (fullscreen on mobile)
    view->x = 0;
    view->y = 0;

    // Setup listeners
    view->map.notify = xdg_toplevel_map;
    wl_signal_add(&xdg_toplevel->base->surface->events.map, &view->map);

    view->unmap.notify = xdg_toplevel_unmap;
    wl_signal_add(&xdg_toplevel->base->surface->events.unmap, &view->unmap);

    view->destroy.notify = xdg_toplevel_destroy;
    wl_signal_add(&xdg_toplevel->events.destroy, &view->destroy);

    view->request_move.notify = xdg_toplevel_request_move;
    wl_signal_add(&xdg_toplevel->events.request_move, &view->request_move);

    view->request_resize.notify = xdg_toplevel_request_resize;
    wl_signal_add(&xdg_toplevel->events.request_resize, &view->request_resize);

    view->request_maximize.notify = xdg_toplevel_request_maximize;
    wl_signal_add(&xdg_toplevel->events.request_maximize, &view->request_maximize);

    view->request_fullscreen.notify = xdg_toplevel_request_fullscreen;
    wl_signal_add(&xdg_toplevel->events.request_fullscreen, &view->request_fullscreen);
}

void flick_new_xdg_popup(struct wl_listener *listener, void *data) {
    struct wlr_xdg_popup *xdg_popup = data;

    wlr_log(WLR_DEBUG, "New XDG popup");

    // Get parent surface
    struct wlr_xdg_surface *parent =
        wlr_xdg_surface_try_from_wlr_surface(xdg_popup->parent);
    if (parent == NULL) {
        wlr_log(WLR_ERROR, "Popup has no parent");
        return;
    }

    // Find parent scene tree
    struct wlr_scene_tree *parent_tree = parent->data;
    if (parent_tree == NULL) {
        wlr_log(WLR_ERROR, "Parent has no scene tree");
        return;
    }

    // Create scene tree for popup
    xdg_popup->base->data = wlr_scene_xdg_surface_create(
        parent_tree, xdg_popup->base);
}
