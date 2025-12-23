//! Flick Compositor - A mobile-first Wayland compositor
//!
//! Features:
//! - Virtual 1920x1080 viewport for desktop apps with pinch-to-zoom/pan
//! - Native resolution for mobile-first apps
//! - Touch-first input handling
//! - No phosh baggage

mod state;
mod backend;
mod handlers;
mod shell;
mod input;
mod viewport;
mod xwayland;
mod touch_effects;
pub mod system;
pub mod text_input;
pub mod android_wlegl;

use std::path::PathBuf;

use anyhow::Result;
use clap::Parser;
use tracing::info;
use tracing_subscriber::{EnvFilter, fmt, prelude::*};
use tracing_appender::rolling;

#[derive(Parser, Debug)]
#[command(name = "flick")]
#[command(about = "Flick mobile compositor for Droidian/libhybris devices", long_about = None)]
struct Args {
    /// Run in windowed mode (for development)
    #[arg(short, long)]
    windowed: bool,

    /// Enable verbose debug output
    #[arg(short, long)]
    debug: bool,
}

fn main() -> Result<()> {
    // Set up panic hook to log panics before crashing
    std::panic::set_hook(Box::new(|panic_info| {
        eprintln!("PANIC: {}", panic_info);
        // Also write to log file directly
        if let Ok(home) = std::env::var("HOME") {
            let crash_log = format!("{}/.local/state/flick/crash.log", home);
            if let Ok(mut f) = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(&crash_log)
            {
                use std::io::Write;
                let _ = writeln!(f, "[{}] PANIC: {}", chrono::Local::now(), panic_info);
            }
        }
    }));

    // Set up log directory (~/.local/state/flick or /tmp/flick)
    let log_dir = std::env::var("XDG_STATE_HOME")
        .map(PathBuf::from)
        .or_else(|_| std::env::var("HOME").map(|h| PathBuf::from(h).join(".local/state")))
        .unwrap_or_else(|_| PathBuf::from("/tmp"))
        .join("flick");

    std::fs::create_dir_all(&log_dir).ok();

    // Parse args early to check for debug flag
    let args = Args::parse();

    // File appender - keeps last 3 log files, rotates daily
    let file_appender = rolling::daily(&log_dir, "compositor.log");
    let (non_blocking, _guard) = tracing_appender::non_blocking(file_appender);

    // Initialize logging - quiet by default, verbose with --debug
    let default_filter = if args.debug {
        "debug,flick=debug"
    } else {
        "warn,flick=info"
    };
    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new(default_filter));

    tracing_subscriber::registry()
        .with(env_filter)
        .with(fmt::layer().with_writer(std::io::stderr))
        .with(fmt::layer().with_writer(non_blocking).with_ansi(false))
        .init();

    info!(log_path = %log_dir.display(), "Flick compositor starting");

    if args.windowed {
        info!("Running in windowed mode (winit backend)");
        backend::winit::run()
    } else {
        // On this branch (hwcomposer-backend), hwcomposer is the default
        info!("Running on hardware (hwcomposer backend for Droidian)");
        backend::hwcomposer::run()
    }
}
