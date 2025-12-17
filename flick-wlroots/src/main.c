#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include <wlr/util/log.h>
#include "compositor/server.h"

static void print_usage(const char *name) {
    printf("Usage: %s [options]\n", name);
    printf("\n");
    printf("Flick - Mobile-first Wayland compositor\n");
    printf("\n");
    printf("Options:\n");
    printf("  -h, --help       Show this help message\n");
    printf("  -v, --verbose    Enable verbose logging\n");
    printf("  -V, --version    Show version information\n");
    printf("\n");
    printf("Environment variables:\n");
    printf("  WLR_BACKENDS     Comma-separated list of backends to use\n");
    printf("                   (drm, hwcomposer, wayland, x11, headless)\n");
    printf("  WLR_RENDERER     Renderer to use (gles2, vulkan, pixman)\n");
    printf("\n");
    printf("Examples:\n");
    printf("  %s                           # Auto-detect backend\n", name);
    printf("  WLR_BACKENDS=wayland %s      # Run nested in Wayland\n", name);
    printf("  WLR_BACKENDS=drm,libinput %s # Native on Linux phone\n", name);
    printf("  WLR_BACKENDS=hwcomposer,libinput %s # Droidian\n", name);
}

static void print_version(void) {
    printf("Flick 0.1.0\n");
    printf("wlroots-based mobile compositor\n");
}

int main(int argc, char *argv[]) {
    enum wlr_log_importance log_level = WLR_INFO;

    static struct option long_options[] = {
        {"help",    no_argument, NULL, 'h'},
        {"verbose", no_argument, NULL, 'v'},
        {"version", no_argument, NULL, 'V'},
        {NULL, 0, NULL, 0}
    };

    int opt;
    while ((opt = getopt_long(argc, argv, "hvV", long_options, NULL)) != -1) {
        switch (opt) {
        case 'h':
            print_usage(argv[0]);
            return EXIT_SUCCESS;
        case 'v':
            log_level = WLR_DEBUG;
            break;
        case 'V':
            print_version();
            return EXIT_SUCCESS;
        default:
            print_usage(argv[0]);
            return EXIT_FAILURE;
        }
    }

    // Initialize logging
    wlr_log_init(log_level, NULL);

    wlr_log(WLR_INFO, "Starting Flick compositor");

    // Check backend environment
    const char *backends = getenv("WLR_BACKENDS");
    if (backends) {
        wlr_log(WLR_INFO, "Using backends: %s", backends);
    } else {
        wlr_log(WLR_INFO, "Auto-detecting backend");
    }

    // Create and initialize server
    struct flick_server server = {0};

    if (!flick_server_init(&server)) {
        wlr_log(WLR_ERROR, "Failed to initialize server");
        return EXIT_FAILURE;
    }

    // Start backend (begins output/input enumeration)
    if (!flick_server_start(&server)) {
        wlr_log(WLR_ERROR, "Failed to start backend");
        flick_server_destroy(&server);
        return EXIT_FAILURE;
    }

    wlr_log(WLR_INFO, "Flick compositor running");
    wlr_log(WLR_INFO, "Press Escape to exit");

    // Run main event loop
    flick_server_run(&server);

    // Cleanup
    wlr_log(WLR_INFO, "Flick compositor shutting down");
    flick_server_destroy(&server);

    return EXIT_SUCCESS;
}
