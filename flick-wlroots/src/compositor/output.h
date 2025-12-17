#ifndef FLICK_OUTPUT_H
#define FLICK_OUTPUT_H

#include <wayland-server-core.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_scene.h>

struct flick_server;

struct flick_output {
    struct flick_server *server;
    struct wlr_output *wlr_output;
    struct wlr_scene_output *scene_output;
    struct wl_list link;  // flick_server.outputs

    int frame_count;  // For hwcomposer init delay

    struct wl_listener frame;
    struct wl_listener destroy;
};

// Called when a new output is added
void flick_new_output_notify(struct wl_listener *listener, void *data);

#endif // FLICK_OUTPUT_H
