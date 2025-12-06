#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <gtk-layer-shell/gtk-layer-shell.h>

#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#include <wayland-client.h>
#include "phosh-private-client-protocol.h"
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
#ifdef GDK_WINDOWING_WAYLAND
  struct phosh_private* phosh_private;
#endif
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

/*
 * TODO: Re-enable phosh_private protocol once we fix the EINVAL issue
 * The protocol binding causes "Error 22 (Invalid argument) dispatching to Wayland display"
 * This code binds to phosh_private and signals SHELL_STATE_UP to dismiss phoc's spinner.
 * See: https://gitlab.gnome.org/World/Phosh/phoc/-/blob/main/protocols/phosh-private.xml
 */

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  // Create the window
  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Check if we should use layer-shell (only on Wayland)
  const gchar* session_type = g_getenv("XDG_SESSION_TYPE");
  gboolean use_layer_shell = g_strcmp0(session_type, "wayland") == 0;

  // Check for FLICK_NO_LAYER_SHELL env var for development
  if (g_getenv("FLICK_NO_LAYER_SHELL") != NULL) {
    use_layer_shell = FALSE;
    g_message("Layer shell disabled by FLICK_NO_LAYER_SHELL");
  }

  if (use_layer_shell && gtk_layer_is_supported()) {
    g_message("Initializing Flick shell with layer-shell");

    // Initialize layer shell
    gtk_layer_init_for_window(window);

    // Set the layer - use OVERLAY to cover everything including splash screens
    gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_OVERLAY);

    // Set namespace for the surface
    gtk_layer_set_namespace(window, "flick-shell");

    // Anchor to all edges to fill the screen
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_BOTTOM, TRUE);
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);

    // No margins - fill the screen
    gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_TOP, 0);
    gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_BOTTOM, 0);
    gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_LEFT, 0);
    gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_RIGHT, 0);

    // Request keyboard interactivity
    gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND);

    // Set exclusive zone to -1 to not reserve space
    gtk_layer_set_exclusive_zone(window, -1);

  } else {
    g_message("Running Flick shell in regular window mode (development)");
    // Development mode - regular window
    gtk_window_set_title(window, "Flick Shell");
    gtk_window_set_default_size(window, 360, 720);
    gtk_window_set_decorated(window, TRUE);
  }

  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
#ifdef GDK_WINDOWING_WAYLAND
  if (self->phosh_private != nullptr) {
    phosh_private_destroy(self->phosh_private);
    self->phosh_private = nullptr;
  }
#endif
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
#ifdef GDK_WINDOWING_WAYLAND
  self->phosh_private = nullptr;
#endif
}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
