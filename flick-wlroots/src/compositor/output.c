#define _POSIX_C_SOURCE 200809L

#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <pixman.h>
#include <wlr/util/log.h>
#include <wlr/version.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/render/pass.h>
#include <wlr/render/swapchain.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_scene.h>
#include "output.h"
#include "server.h"
#include "../shell/shell.h"

// Check if this is a hwcomposer output (needs manual rendering)
// Only used on droidian wlroots 0.17
#if WLR_VERSION_MINOR < 18
static bool is_hwcomposer_output(struct wlr_output *output) {
    return output->name && strncmp(output->name, "HWCOMPOSER", 10) == 0;
}
#endif

// Manual rendering for hwcomposer backend (bypasses wlr_scene)
// Only available on droidian wlroots 0.17 which has the android renderer extension
#if WLR_VERSION_MINOR < 18

static void render_hwcomposer_frame(struct flick_output *output) {
    struct wlr_output *wlr_output = output->wlr_output;
    struct flick_server *server = output->server;
    static int frame_num = 0;
    frame_num++;

    // Get current background color from shell
    float r, g, b;
    flick_shell_get_color(&server->shell, &r, &g, &b);

    if (frame_num <= 5 || frame_num % 60 == 0) {
        wlr_log(WLR_INFO, "render_hwcomposer_frame %d: color=(%.2f,%.2f,%.2f)",
                frame_num, r, g, b);
    }

    // Configure and acquire swapchain buffer
    struct wlr_output_state pending;
    wlr_output_state_init(&pending);
    wlr_output_state_set_enabled(&pending, true);

    if (!wlr_output_configure_primary_swapchain(wlr_output, &pending, &wlr_output->swapchain)) {
        wlr_log(WLR_ERROR, "Failed to configure swapchain");
        wlr_output_state_finish(&pending);
        return;
    }

    struct wlr_buffer *buffer = wlr_swapchain_acquire(wlr_output->swapchain, NULL);
    if (!buffer) {
        wlr_log(WLR_ERROR, "Failed to acquire swapchain buffer");
        wlr_output_state_finish(&pending);
        return;
    }

    // Begin render pass with output (droidian extension for android renderer)
    struct wlr_render_pass *pass = wlr_renderer_begin_buffer_pass_for_output(
        wlr_output->renderer, buffer, NULL, wlr_output);
    if (!pass) {
        wlr_log(WLR_ERROR, "Failed to begin render pass");
        wlr_buffer_unlock(buffer);
        wlr_output_state_finish(&pending);
        return;
    }

    // Full screen damage region
    pixman_region32_t damage;
    pixman_region32_init_rect(&damage, 0, 0, wlr_output->width, wlr_output->height);

    // Inform output about damage (required by phoc)
    wlr_output_handle_damage(wlr_output, &damage);

    // Clear to background color
    wlr_render_pass_add_rect(pass, &(struct wlr_render_rect_options){
        .box = { .width = wlr_output->width, .height = wlr_output->height },
        .color = { .r = r, .g = g, .b = b, .a = 1.0f },
        .clip = &damage,  // Use damage as clip region
    });

    // TODO: Render views/surfaces here when not at home screen
    // For now just show background color

    // Submit render pass
    if (!wlr_render_pass_submit(pass)) {
        wlr_log(WLR_ERROR, "Failed to submit render pass");
        wlr_buffer_unlock(buffer);
        pixman_region32_fini(&damage);
        wlr_output_state_finish(&pending);
        return;
    }

    // Attach buffer and set damage
    wlr_output_state_set_buffer(&pending, buffer);
    wlr_buffer_unlock(buffer);
    wlr_output_state_set_damage(&pending, &damage);
    pixman_region32_fini(&damage);

    if (!wlr_output_commit_state(wlr_output, &pending)) {
        wlr_log(WLR_ERROR, "Failed to commit output state");
    } else if (frame_num <= 5) {
        wlr_log(WLR_INFO, "render_hwcomposer_frame %d: committed successfully", frame_num);
    }

    wlr_output_state_finish(&pending);
}
#endif // WLR_VERSION_MINOR < 18

static void output_frame_notify(struct wl_listener *listener, void *data) {
    (void)data;  // unused
    struct flick_output *output = wl_container_of(listener, output, frame);

    // Skip first few frames to let hwcomposer fully initialize
    if (output->frame_count < 3) {
        output->frame_count++;
        wlr_log(WLR_DEBUG, "Skipping early frame %d for hwcomposer init",
                output->frame_count);
        wlr_output_schedule_frame(output->wlr_output);
        return;
    }

    // Use different rendering paths based on backend
#if WLR_VERSION_MINOR < 18
    if (is_hwcomposer_output(output->wlr_output)) {
        // Manual rendering for hwcomposer (android renderer needs output context)
        render_hwcomposer_frame(output);
    } else
#endif
    {
        // Standard wlr_scene rendering for other backends
        struct wlr_scene_output *scene_output = output->scene_output;
        wlr_scene_output_commit(scene_output, NULL);
    }

    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);

    // Send frame done to surfaces
    if (output->scene_output) {
        wlr_scene_output_send_frame_done(output->scene_output, &now);
    }
}

static void output_destroy_notify(struct wl_listener *listener, void *data) {
    (void)data;  // unused
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

    // Create scene output and add to layout (still useful for surface management)
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
