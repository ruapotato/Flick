//! User privilege handling for app launching
//!
//! When the compositor runs as root, apps should be spawned as a normal user.
//! This module provides helpers to drop privileges before exec.

use std::ffi::CString;
use std::os::unix::process::CommandExt;
use std::process::Command;

/// Get the target user for running apps
/// Priority: FLICK_USER > SUDO_USER > "droidian" fallback
pub fn get_target_user() -> Option<String> {
    // First try FLICK_USER (set by start_hwcomposer.sh to preserve user across nested sudo)
    if let Ok(user) = std::env::var("FLICK_USER") {
        if !user.is_empty() && user != "root" {
            tracing::info!("Using FLICK_USER={}", user);
            return Some(user);
        }
    }

    // Then try SUDO_USER (set when running via sudo)
    if let Ok(user) = std::env::var("SUDO_USER") {
        if !user.is_empty() && user != "root" {
            tracing::info!("Using SUDO_USER={}", user);
            return Some(user);
        }
    }

    // Fallback to droidian (common on Droidian devices)
    if std::path::Path::new("/home/droidian").exists() {
        tracing::info!("Using fallback user: droidian");
        return Some("droidian".to_string());
    }

    None
}

/// Check if we're running as root and should drop privileges
pub fn should_drop_privileges() -> bool {
    unsafe { libc::getuid() == 0 }
}

/// Get user info (uid, gid, home) for a username
pub fn get_user_info(username: &str) -> Option<(u32, u32, String)> {
    let c_username = CString::new(username).ok()?;

    unsafe {
        let pwd = libc::getpwnam(c_username.as_ptr());
        if pwd.is_null() {
            return None;
        }

        let uid = (*pwd).pw_uid;
        let gid = (*pwd).pw_gid;
        let home = if (*pwd).pw_dir.is_null() {
            format!("/home/{}", username)
        } else {
            std::ffi::CStr::from_ptr((*pwd).pw_dir)
                .to_string_lossy()
                .into_owned()
        };

        Some((uid, gid, home))
    }
}

/// Spawn a command as a non-root user (if we're running as root)
///
/// If running as root, this will:
/// 1. Look up the target user (SUDO_USER or "droidian")
/// 2. Set up the child process to drop privileges before exec
/// 3. Set appropriate environment variables (HOME, USER, etc.)
///
/// If not running as root, spawns normally.
pub fn spawn_as_user(cmd: &str, socket_name: &str, text_scale: f64) -> Result<(), String> {
    let qt_scale = format!("{}", text_scale);
    let gdk_scale = format!("{}", text_scale.round() as i32);

    let mut command = Command::new("sh");
    command.arg("-c").arg(cmd);

    // Set Wayland environment
    command.env("WAYLAND_DISPLAY", socket_name);
    command.env("QT_QPA_PLATFORM", "wayland");

    // EGL platform for clients
    command.env("EGL_PLATFORM", "wayland");
    command.env("QSG_RENDER_LOOP", "basic");

    // Set scaling
    command.env("QT_SCALE_FACTOR", &qt_scale);
    command.env("QT_FONT_DPI", format!("{}", (96.0 * text_scale) as i32));
    command.env("GDK_SCALE", &gdk_scale);
    command.env("GDK_DPI_SCALE", &qt_scale);

    // Preserve XDG_RUNTIME_DIR
    if let Ok(xdg_runtime) = std::env::var("XDG_RUNTIME_DIR") {
        command.env("XDG_RUNTIME_DIR", xdg_runtime);
    }

    // If running as root, set up privilege dropping
    if should_drop_privileges() {
        if let Some(username) = get_target_user() {
            if let Some((uid, gid, home)) = get_user_info(&username) {
                tracing::info!(
                    "Dropping privileges: running as {} (uid={}, gid={})",
                    username, uid, gid
                );

                // Set user environment
                command.env("HOME", &home);
                command.env("USER", &username);
                command.env("LOGNAME", &username);

                // Set state dir for Flick apps
                let state_dir = format!("{}/.local/state/flick", home);
                command.env("FLICK_STATE_DIR", &state_dir);

                // Set XDG directories
                command.env("XDG_CONFIG_HOME", format!("{}/.config", home));
                command.env("XDG_DATA_HOME", format!("{}/.local/share", home));
                command.env("XDG_CACHE_HOME", format!("{}/.cache", home));
                command.env("XDG_STATE_HOME", format!("{}/.local/state", home));

                // Use pre_exec to drop privileges in the child before exec
                // This is unsafe because we're modifying process state
                unsafe {
                    command.pre_exec(move || {
                        // Drop supplementary groups
                        if libc::setgroups(0, std::ptr::null()) != 0 {
                            // Non-fatal, just log
                            eprintln!("Warning: setgroups failed");
                        }

                        // Set GID first (must be done before setuid)
                        if libc::setgid(gid) != 0 {
                            return Err(std::io::Error::last_os_error());
                        }

                        // Set UID
                        if libc::setuid(uid) != 0 {
                            return Err(std::io::Error::last_os_error());
                        }

                        Ok(())
                    });
                }
            } else {
                tracing::warn!("Could not get user info for '{}', spawning as root", username);
            }
        } else {
            tracing::warn!("Running as root but no target user found, spawning as root");
        }
    }

    match command.spawn() {
        Ok(_) => Ok(()),
        Err(e) => Err(format!("Failed to spawn: {}", e)),
    }
}

/// Spawn a command as a non-root user (simple version without scaling)
pub fn spawn_as_user_simple(cmd: &str, socket_name: &str) -> Result<(), String> {
    spawn_as_user(cmd, socket_name, 1.0)
}

/// Spawn a command as a non-root user with hwcomposer-specific settings
///
/// This variant sets environment variables needed for software rendering
/// on hwcomposer/Droidian devices where apps can't use GPU directly.
pub fn spawn_as_user_hwcomposer(cmd: &str, socket_name: &str, text_scale: f64) -> Result<(), String> {
    let qt_scale = format!("{}", text_scale);
    let gdk_scale = format!("{}", text_scale.round() as i32);

    let mut command = Command::new("sh");
    command.arg("-c").arg(cmd);

    // Set Wayland environment
    command.env("WAYLAND_DISPLAY", socket_name);
    command.env("QT_QPA_PLATFORM", "wayland");

    // GDK/GTK settings
    command.env("GDK_BACKEND", "wayland");

    // GTK4 specific - force Cairo rendering instead of GPU
    command.env("GSK_RENDERER", "cairo");
    command.env("GDK_RENDERING", "image");

    // Suppress dconf warnings (no D-Bus session in our environment)
    command.env("GSETTINGS_BACKEND", "memory");

    // EGL platform for clients
    command.env("EGL_PLATFORM", "wayland");

    // Try allowing Qt to use EGL (camera needs this for video)
    // Note: QT_QUICK_BACKEND=software was blocking EGL video path
    command.env("QSG_RENDER_LOOP", "basic");

    // Set scaling
    command.env("QT_SCALE_FACTOR", &qt_scale);
    command.env("QT_FONT_DPI", format!("{}", (96.0 * text_scale) as i32));
    command.env("GDK_SCALE", &gdk_scale);
    command.env("GDK_DPI_SCALE", &qt_scale);

    // Preserve XDG_RUNTIME_DIR
    if let Ok(xdg_runtime) = std::env::var("XDG_RUNTIME_DIR") {
        command.env("XDG_RUNTIME_DIR", xdg_runtime);
    }

    // If running as root, set up privilege dropping
    if should_drop_privileges() {
        if let Some(username) = get_target_user() {
            if let Some((uid, gid, home)) = get_user_info(&username) {
                tracing::info!(
                    "Dropping privileges (hwc): running as {} (uid={}, gid={})",
                    username, uid, gid
                );

                // Set user environment
                command.env("HOME", &home);
                command.env("USER", &username);
                command.env("LOGNAME", &username);

                // Set state dir for Flick apps
                let state_dir = format!("{}/.local/state/flick", home);
                command.env("FLICK_STATE_DIR", &state_dir);

                // Set XDG directories
                command.env("XDG_CONFIG_HOME", format!("{}/.config", home));
                command.env("XDG_DATA_HOME", format!("{}/.local/share", home));
                command.env("XDG_CACHE_HOME", format!("{}/.cache", home));
                command.env("XDG_STATE_HOME", format!("{}/.local/state", home));

                // Use pre_exec to drop privileges in the child before exec
                unsafe {
                    command.pre_exec(move || {
                        // Drop supplementary groups
                        if libc::setgroups(0, std::ptr::null()) != 0 {
                            eprintln!("Warning: setgroups failed");
                        }

                        // Set GID first (must be done before setuid)
                        if libc::setgid(gid) != 0 {
                            return Err(std::io::Error::last_os_error());
                        }

                        // Set UID
                        if libc::setuid(uid) != 0 {
                            return Err(std::io::Error::last_os_error());
                        }

                        Ok(())
                    });
                }
            } else {
                tracing::warn!("Could not get user info for '{}', spawning as root", username);
            }
        } else {
            tracing::warn!("Running as root but no target user found, spawning as root");
        }
    }

    match command.spawn() {
        Ok(_) => Ok(()),
        Err(e) => Err(format!("Failed to spawn: {}", e)),
    }
}
