#ifndef FLICK_APPS_H
#define FLICK_APPS_H

#include <stdbool.h>

// Maximum lengths for app info strings
#define FLICK_APP_NAME_MAX 128
#define FLICK_APP_EXEC_MAX 512
#define FLICK_APP_ICON_MAX 256
#define FLICK_APP_COMMENT_MAX 256

// Represents a .desktop application entry
struct flick_app {
    char name[FLICK_APP_NAME_MAX];
    char exec[FLICK_APP_EXEC_MAX];
    char icon[FLICK_APP_ICON_MAX];
    char comment[FLICK_APP_COMMENT_MAX];
    bool terminal;  // Run in terminal
    bool no_display;  // Hidden from menus

    struct flick_app *next;  // Linked list
};

// App list manager
struct flick_app_list {
    struct flick_app *apps;
    int count;
};

// Initialize app list (scans .desktop files)
void flick_app_list_init(struct flick_app_list *list);

// Free app list
void flick_app_list_destroy(struct flick_app_list *list);

// Get app by index
struct flick_app *flick_app_list_get(struct flick_app_list *list, int index);

// Launch an app
bool flick_app_launch(struct flick_app *app);

#endif // FLICK_APPS_H
