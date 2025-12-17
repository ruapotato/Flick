#define _POSIX_C_SOURCE 200809L

#include <stdlib.h>
#include <time.h>
#include <wlr/util/log.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_scene.h>
#include "output.h"
#include "server.h"

static void output_frame_notify(struct wl_listener *listener, void *data) {
    struct flick_output *output = wl_container_of(listener, output, frame);
    struct wlr_scene_output *scene_output = output->scene_output;

    // Skip first few frames to let hwcomposer fully initialize
    // (native window may not be ready immediately)
    if (output->frame_count < 3) {
        output->frame_count++;
        wlr_log(WLR_DEBUG, "Skipping early frame %d for hwcomposer init",
                output->frame_count);
        // Must schedule next frame or we won't get another frame event
        wlr_output_schedule_frame(output->wlr_output);
        return;
    }

    // Let the scene graph render everything
    wlr_scene_output_commit(scene_output, NULL);

    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    wlr_scene_output_send_frame_done(scene_output, &now);
}

static void output_destroy_notify(struct wl_listener *listener, void *data) {
    struct flick_output *output = wl_container_of(listener, output, destroy);

    wlr_log(WLR_INFO, "Output '%s' destroyed", output->wlr_output->name);

    wl_list_remove(&output->frame.link);
    wl_list_remove(&output->destroy.link);
    wl_list_remove(&output->link);

    free(output);
}

void flick_new_output_notify(struct wl_listener *listener, void *data) {
    struct flick_server *server = wl_container_of(listener, server, new_output);
    struct wlr_output *wlr_output = data;

    wlr_log(WLR_INFO, "New output: %s (%s %s)",
            wlr_output->name,
            wlr_output->make ? wlr_output->make : "unknown",
            wlr_output->model ? wlr_output->model : "unknown");

    // Initialize renderer for this output
    wlr_output_init_render(wlr_output, server->allocator, server->renderer);

    // Create our output wrapper
    struct flick_output *output = calloc(1, sizeof(*output));
    if (!output) {
        wlr_log(WLR_ERROR, "Failed to allocate flick_output");
        return;
    }

    output->server = server;
    output->wlr_output = wlr_output;

    // Setup listeners
    output->frame.notify = output_frame_notify;
    wl_signal_add(&wlr_output->events.frame, &output->frame);

    output->destroy.notify = output_destroy_notify;
    wl_signal_add(&wlr_output->events.destroy, &output->destroy);

    // Add to server's output list
    wl_list_insert(&server->outputs, &output->link);

    // Configure output state
    struct wlr_output_state state;
    wlr_output_state_init(&state);
    wlr_output_state_set_enabled(&state, true);

    // Use preferred mode if available
    struct wlr_output_mode *mode = wlr_output_preferred_mode(wlr_output);
    if (mode) {
        wlr_log(WLR_INFO, "Using mode: %dx%d@%dmHz",
                mode->width, mode->height, mode->refresh);
        wlr_output_state_set_mode(&state, mode);

        // Store dimensions for touch coordinate mapping
        server->output_width = mode->width;
        server->output_height = mode->height;
    } else {
        wlr_log(WLR_INFO, "No preferred mode, using current: %dx%d",
                wlr_output->width, wlr_output->height);
        server->output_width = wlr_output->width;
        server->output_height = wlr_output->height;
    }

    // Commit the state
    wlr_output_commit_state(wlr_output, &state);
    wlr_output_state_finish(&state);

    // Create scene output and add to layout
    struct wlr_output_layout_output *lo = wlr_output_layout_add_auto(
        server->output_layout, wlr_output);

    output->scene_output = wlr_scene_output_create(server->scene, wlr_output);
    wlr_scene_output_layout_add_output(server->scene_layout, lo, output->scene_output);

    // Update gesture recognizer with screen size
    flick_gesture_set_screen_size(&server->gesture,
        server->output_width, server->output_height);

    // Update background size
    if (server->background) {
        wlr_scene_rect_set_size(server->background,
            server->output_width, server->output_height);
    }

    wlr_log(WLR_INFO, "Output configured: %dx%d",
            server->output_width, server->output_height);
}
