//! User privilege handling for app launching
//!
//! When the compositor runs as root, apps should be spawned as a normal user.
//! This module provides helpers to drop privileges before exec.

use std::ffi::CString;
use std::fs::{self, OpenOptions};
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};

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

                // Set PulseAudio and D-Bus to user's runtime dir (not our custom one)
                let user_runtime = format!("/run/user/{}", uid);
                command.env("PULSE_SERVER", format!("unix:{}/pulse/native", user_runtime));
                command.env("DBUS_SESSION_BUS_ADDRESS", format!("unix:path={}/bus", user_runtime));

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

/// Get log file path for an app
fn get_log_path(app_id: &str, home: &str) -> std::path::PathBuf {
    std::path::PathBuf::from(format!(
        "{}/.local/share/flick/logs/{}/app.log",
        home, app_id
    ))
}

/// Ensure log directory exists and rotate logs if needed
fn setup_app_logging(app_id: &str, home: &str) -> Option<std::fs::File> {
    let log_dir = format!("{}/.local/share/flick/logs/{}", home, app_id);
    let log_path = get_log_path(app_id, home);

    // Create log directory
    if fs::create_dir_all(&log_dir).is_err() {
        tracing::warn!("Could not create log directory: {}", log_dir);
        return None;
    }

    // Check if we need to rotate (1MB max)
    if log_path.exists() {
        if let Ok(metadata) = fs::metadata(&log_path) {
            if metadata.len() > 1024 * 1024 {
                // Rotate: rename current to timestamped
                let timestamp = chrono::Local::now().format("%Y%m%d_%H%M%S");
                let rotated = format!("{}/app.log.{}", log_dir, timestamp);
                let _ = fs::rename(&log_path, &rotated);

                // Clean up old logs (keep last 5)
                if let Ok(entries) = fs::read_dir(&log_dir) {
                    let mut logs: Vec<_> = entries
                        .filter_map(|e| e.ok())
                        .filter(|e| e.file_name().to_string_lossy().starts_with("app.log."))
                        .collect();
                    logs.sort_by_key(|e| e.metadata().ok().map(|m| m.modified().ok()).flatten());
                    while logs.len() > 4 {
                        if let Some(old) = logs.first() {
                            let _ = fs::remove_file(old.path());
                        }
                        logs.remove(0);
                    }
                }
            }
        }
    }

    // Open log file for appending
    OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_path)
        .ok()
}

/// Spawn an app with logging to ~/.local/share/flick/logs/<app_id>/app.log
pub fn spawn_app_with_logging(
    cmd: &str,
    app_id: &str,
    socket_name: &str,
    text_scale: f64,
) -> Result<(), String> {
    let qt_scale = format!("{}", text_scale);
    let gdk_scale = format!("{}", text_scale.round() as i32);

    let mut command = Command::new("sh");
    command.arg("-c").arg(cmd);

    // Set Wayland environment
    command.env("WAYLAND_DISPLAY", socket_name);
    command.env("QT_QPA_PLATFORM", "wayland");
    command.env("GDK_BACKEND", "wayland");
    command.env("GSK_RENDERER", "cairo");
    command.env("GDK_RENDERING", "image");
    command.env("GSETTINGS_BACKEND", "memory");
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

    // Set app ID for logging context
    command.env("FLICK_APP_ID", app_id);

    // If running as root, set up privilege dropping and logging
    if should_drop_privileges() {
        if let Some(username) = get_target_user() {
            if let Some((uid, gid, home)) = get_user_info(&username) {
                tracing::info!(
                    "Spawning app '{}' as {} with logging",
                    app_id, username
                );

                // Set up logging
                if let Some(log_file) = setup_app_logging(app_id, &home) {
                    let log_file2 = log_file.try_clone().unwrap_or_else(|_| {
                        OpenOptions::new()
                            .create(true)
                            .append(true)
                            .open(get_log_path(app_id, &home))
                            .unwrap()
                    });
                    command.stdout(Stdio::from(log_file));
                    command.stderr(Stdio::from(log_file2));
                }

                // Set user environment
                command.env("HOME", &home);
                command.env("USER", &username);
                command.env("LOGNAME", &username);

                let state_dir = format!("{}/.local/state/flick", home);
                command.env("FLICK_STATE_DIR", &state_dir);

                command.env("XDG_CONFIG_HOME", format!("{}/.config", home));
                command.env("XDG_DATA_HOME", format!("{}/.local/share", home));
                command.env("XDG_CACHE_HOME", format!("{}/.cache", home));
                command.env("XDG_STATE_HOME", format!("{}/.local/state", home));

                let user_runtime = format!("/run/user/{}", uid);
                command.env("PULSE_SERVER", format!("unix:{}/pulse/native", user_runtime));
                command.env("DBUS_SESSION_BUS_ADDRESS", format!("unix:path={}/bus", user_runtime));

                unsafe {
                    command.pre_exec(move || {
                        if libc::setgroups(0, std::ptr::null()) != 0 {
                            eprintln!("Warning: setgroups failed");
                        }
                        if libc::setgid(gid) != 0 {
                            return Err(std::io::Error::last_os_error());
                        }
                        if libc::setuid(uid) != 0 {
                            return Err(std::io::Error::last_os_error());
                        }
                        Ok(())
                    });
                }
            }
        }
    } else {
        // Not root - still set up logging
        if let Ok(home) = std::env::var("HOME") {
            if let Some(log_file) = setup_app_logging(app_id, &home) {
                let log_file2 = log_file.try_clone().unwrap_or_else(|_| {
                    OpenOptions::new()
                        .create(true)
                        .append(true)
                        .open(get_log_path(app_id, &home))
                        .unwrap()
                });
                command.stdout(Stdio::from(log_file));
                command.stderr(Stdio::from(log_file2));
            }
        }
    }

    match command.spawn() {
        Ok(_) => Ok(()),
        Err(e) => Err(format!("Failed to spawn app '{}': {}", app_id, e)),
    }
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

    // Note: GStreamer video sinks have format issues with droidcamsrc
    // DroidMediaQueueBuffer format is only supported by droideglsink/droidvideotexturesink
    // AAL backend bypasses GStreamer and may work better

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

                // Set PulseAudio and D-Bus to user's runtime dir (not our custom one)
                let user_runtime = format!("/run/user/{}", uid);
                command.env("PULSE_SERVER", format!("unix:{}/pulse/native", user_runtime));
                command.env("DBUS_SESSION_BUS_ADDRESS", format!("unix:path={}/bus", user_runtime));

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
