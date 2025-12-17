#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <unistd.h>
#include <limits.h>
#include <wlr/util/log.h>
#include "apps.h"

// Standard .desktop file locations
static const char *desktop_dirs[] = {
    "/usr/share/applications",
    "/usr/local/share/applications",
    NULL  // Will be filled with ~/.local/share/applications
};

// Parse a single .desktop file
static struct flick_app *parse_desktop_file(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) {
        return NULL;
    }

    struct flick_app *app = calloc(1, sizeof(*app));
    if (!app) {
        fclose(f);
        return NULL;
    }

    char line[1024];
    bool in_desktop_entry = false;

    while (fgets(line, sizeof(line), f)) {
        // Remove trailing newline
        size_t len = strlen(line);
        if (len > 0 && line[len - 1] == '\n') {
            line[len - 1] = '\0';
        }

        // Check for section headers
        if (line[0] == '[') {
            in_desktop_entry = (strcmp(line, "[Desktop Entry]") == 0);
            continue;
        }

        // Only parse Desktop Entry section
        if (!in_desktop_entry) {
            continue;
        }

        // Parse key=value pairs
        char *eq = strchr(line, '=');
        if (!eq) {
            continue;
        }

        *eq = '\0';
        char *key = line;
        char *value = eq + 1;

        if (strcmp(key, "Name") == 0 && app->name[0] == '\0') {
            strncpy(app->name, value, FLICK_APP_NAME_MAX - 1);
        } else if (strcmp(key, "Exec") == 0) {
            // Strip field codes (%f, %F, %u, %U, etc.)
            char *dst = app->exec;
            char *src = value;
            while (*src && dst < app->exec + FLICK_APP_EXEC_MAX - 1) {
                if (*src == '%' && src[1]) {
                    src += 2;  // Skip %X
                } else {
                    *dst++ = *src++;
                }
            }
            *dst = '\0';
            // Trim trailing spaces
            while (dst > app->exec && dst[-1] == ' ') {
                *--dst = '\0';
            }
        } else if (strcmp(key, "Icon") == 0) {
            strncpy(app->icon, value, FLICK_APP_ICON_MAX - 1);
        } else if (strcmp(key, "Comment") == 0 && app->comment[0] == '\0') {
            strncpy(app->comment, value, FLICK_APP_COMMENT_MAX - 1);
        } else if (strcmp(key, "Terminal") == 0) {
            app->terminal = (strcmp(value, "true") == 0);
        } else if (strcmp(key, "NoDisplay") == 0) {
            app->no_display = (strcmp(value, "true") == 0);
        } else if (strcmp(key, "Type") == 0) {
            // Only keep Application types
            if (strcmp(value, "Application") != 0) {
                free(app);
                fclose(f);
                return NULL;
            }
        }
    }

    fclose(f);

    // Must have at least a name and exec
    if (app->name[0] == '\0' || app->exec[0] == '\0') {
        free(app);
        return NULL;
    }

    return app;
}

// Scan a directory for .desktop files
static void scan_desktop_dir(struct flick_app_list *list, const char *dir) {
    DIR *d = opendir(dir);
    if (!d) {
        return;
    }

    wlr_log(WLR_DEBUG, "Scanning %s for .desktop files", dir);

    struct dirent *entry;
    while ((entry = readdir(d))) {
        // Skip hidden files and non-.desktop files
        if (entry->d_name[0] == '.') {
            continue;
        }

        size_t len = strlen(entry->d_name);
        if (len < 8 || strcmp(entry->d_name + len - 8, ".desktop") != 0) {
            continue;
        }

        // Build full path
        char path[PATH_MAX];
        snprintf(path, sizeof(path), "%s/%s", dir, entry->d_name);

        struct flick_app *app = parse_desktop_file(path);
        if (app && !app->no_display) {
            // Add to list
            app->next = list->apps;
            list->apps = app;
            list->count++;
            wlr_log(WLR_DEBUG, "Found app: %s", app->name);
        } else if (app) {
            free(app);
        }
    }

    closedir(d);
}

void flick_app_list_init(struct flick_app_list *list) {
    memset(list, 0, sizeof(*list));

    // Scan standard directories
    for (int i = 0; desktop_dirs[i]; i++) {
        scan_desktop_dir(list, desktop_dirs[i]);
    }

    // Scan user directory
    const char *home = getenv("HOME");
    if (home) {
        char user_dir[PATH_MAX];
        snprintf(user_dir, sizeof(user_dir), "%s/.local/share/applications", home);
        scan_desktop_dir(list, user_dir);
    }

    wlr_log(WLR_INFO, "Found %d applications", list->count);
}

void flick_app_list_destroy(struct flick_app_list *list) {
    struct flick_app *app = list->apps;
    while (app) {
        struct flick_app *next = app->next;
        free(app);
        app = next;
    }
    list->apps = NULL;
    list->count = 0;
}

struct flick_app *flick_app_list_get(struct flick_app_list *list, int index) {
    if (index < 0 || index >= list->count) {
        return NULL;
    }

    struct flick_app *app = list->apps;
    for (int i = 0; i < index && app; i++) {
        app = app->next;
    }
    return app;
}

bool flick_app_launch(struct flick_app *app) {
    if (!app || app->exec[0] == '\0') {
        return false;
    }

    wlr_log(WLR_INFO, "Launching: %s (%s)", app->name, app->exec);

    pid_t pid = fork();
    if (pid == 0) {
        // Child process
        if (app->terminal) {
            // TODO: Wrap in terminal emulator
            execl("/bin/sh", "/bin/sh", "-c", app->exec, NULL);
        } else {
            execl("/bin/sh", "/bin/sh", "-c", app->exec, NULL);
        }
        _exit(EXIT_FAILURE);
    } else if (pid < 0) {
        wlr_log(WLR_ERROR, "Failed to fork for app: %s", app->name);
        return false;
    }

    return true;
}
