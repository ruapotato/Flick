//! System integration module - real hardware control
//!
//! Provides access to:
//! - Backlight/brightness control
//! - Battery status
//! - WiFi management (via nmcli)
//! - Process stats (CPU, RAM, IO)

use std::fs;
use std::process::Command;
use std::collections::HashMap;
use std::time::Instant;

/// Backlight controller
pub struct Backlight {
    path: String,
    max_brightness: u32,
}

impl Backlight {
    /// Find and initialize backlight control
    pub fn new() -> Option<Self> {
        let backlight_dir = "/sys/class/backlight";
        if let Ok(entries) = fs::read_dir(backlight_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if let Ok(max) = fs::read_to_string(path.join("max_brightness")) {
                    if let Ok(max_brightness) = max.trim().parse() {
                        return Some(Self {
                            path: path.to_string_lossy().to_string(),
                            max_brightness,
                        });
                    }
                }
            }
        }
        None
    }

    /// Get current brightness as 0.0-1.0
    pub fn get(&self) -> f32 {
        if let Ok(current) = fs::read_to_string(format!("{}/brightness", self.path)) {
            if let Ok(val) = current.trim().parse::<u32>() {
                return val as f32 / self.max_brightness as f32;
            }
        }
        0.5
    }

    /// Set brightness (0.0-1.0)
    pub fn set(&self, value: f32) {
        let clamped = value.clamp(0.05, 1.0); // Minimum 5% to avoid black screen
        let raw_value = (clamped * self.max_brightness as f32) as u32;
        let brightness_path = format!("{}/brightness", self.path);

        // Try writing directly (requires permissions)
        if fs::write(&brightness_path, raw_value.to_string()).is_err() {
            // Fallback: try with brightnessctl or pkexec
            let _ = Command::new("brightnessctl")
                .args(["set", &format!("{}%", (clamped * 100.0) as u32)])
                .output();
        }
    }
}

/// Haptic feedback controller (vibrator motor)
pub struct Vibrator {
    path: String,
}

impl Vibrator {
    /// Find and initialize vibrator control
    pub fn new() -> Option<Self> {
        // Android/Droidian vibrator path
        let vibrator_path = "/sys/class/leds/vibrator";
        if std::path::Path::new(vibrator_path).exists() {
            return Some(Self {
                path: vibrator_path.to_string(),
            });
        }
        None
    }

    /// Trigger a short vibration (duration in milliseconds)
    pub fn vibrate(&self, duration_ms: u32) {
        // Set duration
        let duration_path = format!("{}/duration", self.path);
        if fs::write(&duration_path, duration_ms.to_string()).is_err() {
            tracing::warn!("Failed to set vibrator duration");
            return;
        }

        // Activate
        let activate_path = format!("{}/activate", self.path);
        if fs::write(&activate_path, "1").is_err() {
            tracing::warn!("Failed to activate vibrator");
        }
    }

    /// Short tap feedback (for key presses)
    pub fn tap(&self) {
        self.vibrate(15);
    }

    /// Medium feedback (for actions like closing apps)
    pub fn click(&self) {
        self.vibrate(25);
    }

    /// Strong feedback (for important events)
    pub fn heavy(&self) {
        self.vibrate(50);
    }
}

/// Battery status
#[derive(Debug, Clone)]
pub struct BatteryStatus {
    pub capacity: u8,
    pub charging: bool,
    pub status: String,
}

impl BatteryStatus {
    /// Read current battery status
    pub fn read() -> Option<Self> {
        // Try common battery paths (Android uses "battery", Linux uses "BAT0"/"BAT1")
        let battery_paths = [
            "/sys/class/power_supply/battery",
            "/sys/class/power_supply/Battery",
            "/sys/class/power_supply/BAT0",
            "/sys/class/power_supply/BAT1",
        ];

        for battery_path in &battery_paths {
            let path = std::path::Path::new(battery_path);
            if path.exists() {
                let capacity = fs::read_to_string(path.join("capacity"))
                    .ok()
                    .and_then(|s| s.trim().parse().ok())
                    .unwrap_or(0);
                let status = fs::read_to_string(path.join("status"))
                    .map(|s| s.trim().to_string())
                    .unwrap_or_else(|_| "Unknown".to_string());
                let charging = status == "Charging" || status == "Full";

                return Some(Self { capacity, charging, status });
            }
        }
        None
    }
}

/// WiFi network info
#[derive(Debug, Clone)]
pub struct WifiNetwork {
    pub ssid: String,
    pub signal: u8,
    pub security: String,
    pub connected: bool,
}

/// WiFi manager using nmcli
pub struct WifiManager;

impl WifiManager {
    /// Check if WiFi is enabled
    pub fn is_enabled() -> bool {
        Command::new("nmcli")
            .args(["radio", "wifi"])
            .output()
            .map(|o| String::from_utf8_lossy(&o.stdout).trim() == "enabled")
            .unwrap_or(false)
    }

    /// Enable WiFi
    pub fn enable() -> bool {
        Command::new("nmcli")
            .args(["radio", "wifi", "on"])
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// Disable WiFi
    pub fn disable() -> bool {
        Command::new("nmcli")
            .args(["radio", "wifi", "off"])
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// Toggle WiFi
    pub fn toggle() -> bool {
        if Self::is_enabled() {
            Self::disable()
        } else {
            Self::enable()
        }
    }

    /// Get current connection info
    pub fn current_connection() -> Option<String> {
        Command::new("nmcli")
            .args(["-t", "-f", "NAME,TYPE", "connection", "show", "--active"])
            .output()
            .ok()
            .and_then(|o| {
                String::from_utf8_lossy(&o.stdout)
                    .lines()
                    .find(|l| l.contains("wireless") || l.contains("wifi"))
                    .map(|l| l.split(':').next().unwrap_or("").to_string())
            })
    }

    /// Scan for available networks
    pub fn scan() -> Vec<WifiNetwork> {
        let current = Self::current_connection();

        Command::new("nmcli")
            .args(["-t", "-f", "SSID,SIGNAL,SECURITY", "dev", "wifi", "list"])
            .output()
            .map(|o| {
                String::from_utf8_lossy(&o.stdout)
                    .lines()
                    .filter_map(|line| {
                        let parts: Vec<&str> = line.split(':').collect();
                        if parts.len() >= 2 && !parts[0].is_empty() {
                            let ssid = parts[0].to_string();
                            let signal = parts.get(1)
                                .and_then(|s| s.parse().ok())
                                .unwrap_or(0);
                            let security = parts.get(2)
                                .map(|s| s.to_string())
                                .unwrap_or_default();
                            let connected = current.as_ref().map(|c| c == &ssid).unwrap_or(false);

                            Some(WifiNetwork { ssid, signal, security, connected })
                        } else {
                            None
                        }
                    })
                    .collect()
            })
            .unwrap_or_default()
    }

    /// Connect to a network
    pub fn connect(ssid: &str, password: Option<&str>) -> bool {
        let mut args = vec!["dev", "wifi", "connect", ssid];
        if let Some(pwd) = password {
            args.extend(["password", pwd]);
        }

        Command::new("nmcli")
            .args(&args)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }

    /// Disconnect from current network
    pub fn disconnect() -> bool {
        // Find the active wifi device
        if let Ok(output) = Command::new("nmcli")
            .args(["-t", "-f", "DEVICE,TYPE", "dev"])
            .output()
        {
            for line in String::from_utf8_lossy(&output.stdout).lines() {
                if line.contains("wifi") {
                    let device = line.split(':').next().unwrap_or("");
                    return Command::new("nmcli")
                        .args(["dev", "disconnect", device])
                        .status()
                        .map(|s| s.success())
                        .unwrap_or(false);
                }
            }
        }
        false
    }
}

/// Bluetooth manager
pub struct BluetoothManager;

impl BluetoothManager {
    /// Check if Bluetooth is enabled via rfkill
    pub fn is_enabled() -> bool {
        Command::new("rfkill")
            .args(["list", "bluetooth"])
            .output()
            .map(|o| !String::from_utf8_lossy(&o.stdout).contains("Soft blocked: yes"))
            .unwrap_or(false)
    }

    /// Toggle Bluetooth
    pub fn toggle() -> bool {
        let action = if Self::is_enabled() { "block" } else { "unblock" };
        Command::new("rfkill")
            .args([action, "bluetooth"])
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }
}

/// Airplane mode (all radios)
pub struct AirplaneMode;

impl AirplaneMode {
    /// Check if airplane mode is on
    pub fn is_enabled() -> bool {
        // Check if all radios are blocked
        !WifiManager::is_enabled() && !BluetoothManager::is_enabled()
    }

    /// Toggle airplane mode
    pub fn toggle() -> bool {
        if Self::is_enabled() {
            // Turn off airplane mode - enable radios
            WifiManager::enable();
            let _ = Command::new("rfkill").args(["unblock", "bluetooth"]).status();
            true
        } else {
            // Turn on airplane mode - disable all radios
            WifiManager::disable();
            let _ = Command::new("rfkill").args(["block", "bluetooth"]).status();
            true
        }
    }
}

/// Volume/Audio manager using pactl (PulseAudio/PipeWire)
/// Runs commands as the user who owns the audio session (not root)
pub struct VolumeManager;

impl VolumeManager {
    /// Find the username that owns PulseAudio/PipeWire (from /run/user/*)
    fn get_audio_user() -> Option<(u32, String)> {
        // Find first user runtime directory
        if let Ok(entries) = std::fs::read_dir("/run/user") {
            for entry in entries.flatten() {
                if let Ok(name) = entry.file_name().into_string() {
                    if let Ok(uid) = name.parse::<u32>() {
                        // Check if this user has a pulse/pipewire socket
                        let pulse_path = format!("/run/user/{}/pulse", uid);
                        let pipewire_path = format!("/run/user/{}/pipewire-0", uid);
                        if std::path::Path::new(&pulse_path).exists()
                            || std::path::Path::new(&pipewire_path).exists() {
                            // Look up username from uid via /etc/passwd
                            if let Some(username) = Self::uid_to_username(uid) {
                                tracing::debug!("Found audio user: uid={} username={}", uid, username);
                                return Some((uid, username));
                            }
                        }
                    }
                }
            }
        }
        tracing::warn!("No audio user found in /run/user");
        None
    }

    /// Look up username from uid via /etc/passwd
    fn uid_to_username(uid: u32) -> Option<String> {
        if let Ok(contents) = std::fs::read_to_string("/etc/passwd") {
            for line in contents.lines() {
                let parts: Vec<&str> = line.split(':').collect();
                if parts.len() >= 3 {
                    if let Ok(file_uid) = parts[2].parse::<u32>() {
                        if file_uid == uid {
                            return Some(parts[0].to_string());
                        }
                    }
                }
            }
        }
        None
    }

    /// Run pactl command as the audio user
    fn run_pactl(args: &[&str]) -> Option<std::process::Output> {
        if let Some((uid, _username)) = Self::get_audio_user() {
            // Check if we're already running as the target user
            let current_uid = unsafe { libc::getuid() };

            if current_uid == uid {
                // Already the right user, run directly with env vars
                tracing::info!("Running pactl directly (same user): {:?}", args);
                Command::new("pactl")
                    .env("XDG_RUNTIME_DIR", format!("/run/user/{}", uid))
                    .args(args)
                    .output()
                    .ok()
            } else {
                // Need to switch users - use sudo with sh -c to properly set env
                let quoted_args: Vec<String> = args.iter().map(|a| format!("'{}'", a)).collect();
                let shell_cmd = format!(
                    "XDG_RUNTIME_DIR=/run/user/{} pactl {}",
                    uid, quoted_args.join(" ")
                );
                tracing::info!("Running pactl via sudo as uid {}: {:?}", uid, args);
                Command::new("sudo")
                    .args(["-u", &format!("#{}", uid), "sh", "-c", &shell_cmd])
                    .output()
                    .ok()
            }
        } else {
            // Fallback to direct call (works if not running as root)
            tracing::info!("Running pactl directly (no audio user found): {:?}", args);
            Command::new("pactl")
                .args(args)
                .output()
                .ok()
        }
    }

    /// Run pactl command as the audio user (fire and forget)
    fn run_pactl_async(args: &[&str]) {
        if let Some((uid, _username)) = Self::get_audio_user() {
            let current_uid = unsafe { libc::getuid() };

            if current_uid == uid {
                tracing::info!("Running pactl async directly (same user): {:?}", args);
                let mut cmd = Command::new("pactl");
                cmd.env("XDG_RUNTIME_DIR", format!("/run/user/{}", uid));
                cmd.args(args);
                let _ = cmd.spawn();
            } else {
                // Use sudo with sh -c to properly set env
                let quoted_args: Vec<String> = args.iter().map(|a| format!("'{}'", a)).collect();
                let shell_cmd = format!(
                    "XDG_RUNTIME_DIR=/run/user/{} pactl {}",
                    uid, quoted_args.join(" ")
                );
                tracing::info!("Running pactl async via sudo as uid {}: {:?}", uid, args);
                let _ = Command::new("sudo")
                    .args(["-u", &format!("#{}", uid), "sh", "-c", &shell_cmd])
                    .spawn();
            }
        } else {
            tracing::info!("Running pactl async directly: {:?}", args);
            let _ = Command::new("pactl")
                .args(args)
                .spawn();
        }
    }

    /// Run amixer command as the audio user (blocking)
    fn run_amixer(args: &[&str]) -> Option<std::process::Output> {
        if let Some((uid, _username)) = Self::get_audio_user() {
            let current_uid = unsafe { libc::getuid() };

            if current_uid == uid {
                // Already the right user, run directly
                Command::new("amixer")
                    .args(args)
                    .output()
                    .ok()
            } else {
                // Need to switch users
                let quoted_args: Vec<String> = args.iter().map(|a| format!("'{}'", a)).collect();
                let shell_cmd = format!("amixer {}", quoted_args.join(" "));
                Command::new("sudo")
                    .args(["-u", &format!("#{}", uid), "sh", "-c", &shell_cmd])
                    .output()
                    .ok()
            }
        } else {
            // Fallback to direct call
            Command::new("amixer")
                .args(args)
                .output()
                .ok()
        }
    }

    /// Get current volume (0-100) using amixer (works with droid audio)
    pub fn get_volume() -> u8 {
        Self::run_amixer(&["get", "Master"])
            .and_then(|o| {
                let output = String::from_utf8_lossy(&o.stdout);
                // Parse "Front Left: Playback 32768 [50%] [on]"
                for line in output.lines() {
                    if line.contains("Playback") && line.contains('[') {
                        if let Some(start) = line.find('[') {
                            if let Some(end) = line[start..].find('%') {
                                if let Ok(vol) = line[start+1..start+end].parse::<u8>() {
                                    return Some(vol);
                                }
                            }
                        }
                    }
                }
                None
            })
            .unwrap_or(50)
    }

    /// Set volume (0-100)
    pub fn set_volume(value: u8) {
        let clamped = value.min(100);
        let _ = Self::run_amixer(&["set", "Master", &format!("{}%", clamped)]);
    }

    /// Increase volume by 5%
    pub fn volume_up() {
        let _ = Self::run_amixer(&["set", "Master", "5%+"]);
    }

    /// Decrease volume by 5%
    pub fn volume_down() {
        let _ = Self::run_amixer(&["set", "Master", "5%-"]);
    }

    /// Check if muted (using amixer)
    pub fn is_muted() -> bool {
        Self::run_amixer(&["get", "Master"])
            .map(|o| String::from_utf8_lossy(&o.stdout).contains("[off]"))
            .unwrap_or(false)
    }

    /// Set mute state
    pub fn set_mute(muted: bool) {
        let state = if muted { "mute" } else { "unmute" };
        let _ = Self::run_amixer(&["set", "Master", state]);
    }

    /// Toggle mute
    pub fn toggle_mute() {
        let _ = Self::run_amixer(&["set", "Master", "toggle"]);
    }
}

/// Phone call status (read from phone_helper daemon)
#[derive(Debug, Clone, Default)]
pub struct PhoneStatus {
    pub state: String,       // idle, incoming, dialing, alerting, active
    pub number: String,      // Phone number
    pub duration: u32,       // Call duration in seconds
    pub last_check: Option<std::time::Instant>,
}

impl PhoneStatus {
    const STATUS_FILE: &'static str = "/tmp/flick_phone_status";
    const CMD_FILE: &'static str = "/tmp/flick_phone_cmd";

    /// Read current phone status from the phone helper daemon
    pub fn read() -> Self {
        match fs::read_to_string(Self::STATUS_FILE) {
            Ok(contents) => {
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&contents) {
                    return Self {
                        state: json.get("state")
                            .and_then(|v| v.as_str())
                            .unwrap_or("idle")
                            .to_string(),
                        number: json.get("number")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string(),
                        duration: json.get("duration")
                            .and_then(|v| v.as_u64())
                            .unwrap_or(0) as u32,
                        last_check: Some(std::time::Instant::now()),
                    };
                }
            }
            Err(_) => {}
        }
        Self::default()
    }

    /// Check if there's an incoming call
    pub fn is_incoming(&self) -> bool {
        self.state == "incoming"
    }

    /// Check if there's an active call
    pub fn is_active(&self) -> bool {
        self.state == "active"
    }

    /// Check if we're in a call (any state except idle)
    pub fn in_call(&self) -> bool {
        self.state != "idle" && !self.state.is_empty()
    }

    /// Send answer command to phone helper
    pub fn answer() {
        let cmd = serde_json::json!({"action": "answer"});
        let _ = fs::write(Self::CMD_FILE, cmd.to_string());
        tracing::info!("Phone: sent answer command");
    }

    /// Send hangup command to phone helper
    pub fn hangup() {
        let cmd = serde_json::json!({"action": "hangup"});
        let _ = fs::write(Self::CMD_FILE, cmd.to_string());
        tracing::info!("Phone: sent hangup command");
    }

    /// Toggle speaker mode
    pub fn set_speaker(enabled: bool) {
        let cmd = serde_json::json!({"action": "speaker", "enabled": enabled});
        let _ = fs::write(Self::CMD_FILE, cmd.to_string());
        tracing::info!("Phone: set speaker = {}", enabled);
    }
}

/// Do Not Disturb mode (mutes notifications)
pub struct DoNotDisturb {
    pub enabled: bool,
}

impl DoNotDisturb {
    pub fn new() -> Self {
        Self { enabled: false }
    }

    pub fn toggle(&mut self) {
        self.enabled = !self.enabled;
        // In a real implementation, this would suppress notification display
    }
}

/// Screen orientation
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Orientation {
    Portrait,
    Landscape90,   // 90 degrees clockwise
    Landscape270,  // 270 degrees clockwise (90 counter-clockwise)
}

/// Rotation lock
pub struct RotationLock {
    pub locked: bool,
    pub current_orientation: Orientation,
}

impl RotationLock {
    pub fn new() -> Self {
        Self {
            locked: false,
            current_orientation: Orientation::Portrait,
        }
    }

    pub fn toggle(&mut self) {
        self.locked = !self.locked;
        // In a real implementation, this would prevent screen rotation
    }

    /// Get current orientation
    pub fn get_orientation(&self) -> Orientation {
        self.current_orientation
    }

    /// Set orientation (cycles between Portrait and Landscape90 for now)
    pub fn set_orientation(&mut self, orientation: Orientation) {
        self.current_orientation = orientation;
    }

    /// Cycle to next orientation (Portrait -> Landscape90 -> Portrait)
    pub fn cycle_orientation(&mut self) {
        self.current_orientation = match self.current_orientation {
            Orientation::Portrait => Orientation::Landscape90,
            Orientation::Landscape90 => Orientation::Portrait,
            Orientation::Landscape270 => Orientation::Portrait,
        };
    }
}

/// Flashlight (if available via camera flash LED)
pub struct Flashlight;

impl Flashlight {
    /// Primary torch LED path (Pixel 3a and similar devices)
    const PRIMARY_TORCH: &'static str = "/sys/class/leds/led:torch_0";

    /// Find flashlight LED path - prefer torch_0, fallback to search
    fn find_led() -> Option<String> {
        // First try the primary torch LED
        if std::path::Path::new(Self::PRIMARY_TORCH).exists() {
            return Some(Self::PRIMARY_TORCH.to_string());
        }

        // Fallback: search for any torch LED
        let leds_dir = "/sys/class/leds";
        if let Ok(entries) = fs::read_dir(leds_dir) {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_string();
                // Prefer torch over flash (flash is for camera, torch is flashlight)
                if name.contains("torch") {
                    return Some(entry.path().to_string_lossy().to_string());
                }
            }
        }
        None
    }

    /// Get max brightness for the LED
    fn get_max_brightness(path: &str) -> u32 {
        fs::read_to_string(format!("{}/max_brightness", path))
            .ok()
            .and_then(|s| s.trim().parse().ok())
            .unwrap_or(500) // Default to 500 (common for torch LEDs)
    }

    /// Check if flashlight is on
    pub fn is_on() -> bool {
        Self::find_led()
            .and_then(|path| fs::read_to_string(format!("{}/brightness", path)).ok())
            .map(|s| s.trim().parse::<u32>().unwrap_or(0) > 0)
            .unwrap_or(false)
    }

    /// Toggle flashlight
    pub fn toggle() -> bool {
        if let Some(path) = Self::find_led() {
            let brightness = if Self::is_on() {
                "0".to_string()
            } else {
                Self::get_max_brightness(&path).to_string()
            };
            match fs::write(format!("{}/brightness", path), &brightness) {
                Ok(_) => {
                    tracing::info!("Flashlight set to {} at {}", brightness, path);
                    true
                }
                Err(e) => {
                    tracing::error!("Failed to set flashlight: {} at {}", e, path);
                    false
                }
            }
        } else {
            tracing::warn!("No flashlight LED found");
            false
        }
    }
}

/// Process statistics
#[derive(Debug, Clone, Default)]
pub struct ProcessStats {
    pub pid: u32,
    pub name: String,
    pub cpu_percent: f32,
    pub memory_mb: f32,
    pub io_read_bytes: u64,
    pub io_write_bytes: u64,
}

/// Process stats collector with history for graphs
pub struct ProcessStatsCollector {
    /// Historical CPU usage for graphing (last N samples)
    cpu_history: HashMap<u32, Vec<f32>>,
    /// Historical memory usage
    mem_history: HashMap<u32, Vec<f32>>,
    /// Historical IO read bytes
    io_history: HashMap<u32, Vec<u64>>,
    /// Previous CPU times for delta calculation
    prev_cpu_times: HashMap<u32, (u64, u64)>, // (utime+stime, total_time)
    /// Last sample time
    last_sample: Instant,
    /// History length
    history_len: usize,
}

impl ProcessStatsCollector {
    pub fn new(history_len: usize) -> Self {
        Self {
            cpu_history: HashMap::new(),
            mem_history: HashMap::new(),
            io_history: HashMap::new(),
            prev_cpu_times: HashMap::new(),
            last_sample: Instant::now(),
            history_len,
        }
    }

    /// Get stats for a process by PID
    pub fn get_stats(&mut self, pid: u32) -> Option<ProcessStats> {
        let proc_path = format!("/proc/{}", pid);

        // Read comm (process name)
        let name = fs::read_to_string(format!("{}/comm", proc_path))
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|_| "unknown".to_string());

        // Read stat for CPU times
        let stat = fs::read_to_string(format!("{}/stat", proc_path)).ok()?;
        let stat_parts: Vec<&str> = stat.split_whitespace().collect();

        // Fields: utime (13), stime (14) - in clock ticks
        let utime: u64 = stat_parts.get(13)?.parse().ok()?;
        let stime: u64 = stat_parts.get(14)?.parse().ok()?;
        let proc_time = utime + stime;

        // Calculate CPU percentage
        let cpu_percent = if let Some((prev_proc, prev_total)) = self.prev_cpu_times.get(&pid) {
            let total_time = self.get_total_cpu_time();
            let proc_delta = proc_time.saturating_sub(*prev_proc);
            let total_delta = total_time.saturating_sub(*prev_total);
            if total_delta > 0 {
                (proc_delta as f32 / total_delta as f32) * 100.0
            } else {
                0.0
            }
        } else {
            0.0
        };

        // Update previous times
        self.prev_cpu_times.insert(pid, (proc_time, self.get_total_cpu_time()));

        // Read statm for memory (in pages, typically 4KB each)
        let statm = fs::read_to_string(format!("{}/statm", proc_path)).ok()?;
        let statm_parts: Vec<&str> = statm.split_whitespace().collect();
        let rss_pages: u64 = statm_parts.get(1)?.parse().ok()?;
        let page_size = 4096u64; // Typically 4KB
        let memory_mb = (rss_pages * page_size) as f32 / (1024.0 * 1024.0);

        // Read io stats
        let (io_read_bytes, io_write_bytes) = fs::read_to_string(format!("{}/io", proc_path))
            .map(|io| {
                let mut read = 0u64;
                let mut write = 0u64;
                for line in io.lines() {
                    if line.starts_with("read_bytes:") {
                        read = line.split_whitespace().nth(1)
                            .and_then(|s| s.parse().ok())
                            .unwrap_or(0);
                    } else if line.starts_with("write_bytes:") {
                        write = line.split_whitespace().nth(1)
                            .and_then(|s| s.parse().ok())
                            .unwrap_or(0);
                    }
                }
                (read, write)
            })
            .unwrap_or((0, 0));

        // Update histories
        self.update_history(pid, cpu_percent, memory_mb, io_read_bytes);

        Some(ProcessStats {
            pid,
            name,
            cpu_percent,
            memory_mb,
            io_read_bytes,
            io_write_bytes,
        })
    }

    /// Get total CPU time from /proc/stat
    fn get_total_cpu_time(&self) -> u64 {
        fs::read_to_string("/proc/stat")
            .ok()
            .and_then(|s| {
                s.lines()
                    .next()
                    .map(|line| {
                        line.split_whitespace()
                            .skip(1)
                            .filter_map(|s| s.parse::<u64>().ok())
                            .sum()
                    })
            })
            .unwrap_or(0)
    }

    fn update_history(&mut self, pid: u32, cpu: f32, mem: f32, io: u64) {
        let cpu_hist = self.cpu_history.entry(pid).or_insert_with(Vec::new);
        cpu_hist.push(cpu);
        if cpu_hist.len() > self.history_len {
            cpu_hist.remove(0);
        }

        let mem_hist = self.mem_history.entry(pid).or_insert_with(Vec::new);
        mem_hist.push(mem);
        if mem_hist.len() > self.history_len {
            mem_hist.remove(0);
        }

        let io_hist = self.io_history.entry(pid).or_insert_with(Vec::new);
        io_hist.push(io);
        if io_hist.len() > self.history_len {
            io_hist.remove(0);
        }
    }

    /// Get CPU history for graphing (0.0-100.0 values)
    pub fn get_cpu_history(&self, pid: u32) -> &[f32] {
        self.cpu_history.get(&pid).map(|v| v.as_slice()).unwrap_or(&[])
    }

    /// Get memory history for graphing (MB values)
    pub fn get_mem_history(&self, pid: u32) -> &[f32] {
        self.mem_history.get(&pid).map(|v| v.as_slice()).unwrap_or(&[])
    }

    /// Get IO history for graphing
    pub fn get_io_history(&self, pid: u32) -> &[u64] {
        self.io_history.get(&pid).map(|v| v.as_slice()).unwrap_or(&[])
    }

    /// Clean up old PIDs that no longer exist
    pub fn cleanup(&mut self, active_pids: &[u32]) {
        self.cpu_history.retain(|pid, _| active_pids.contains(pid));
        self.mem_history.retain(|pid, _| active_pids.contains(pid));
        self.io_history.retain(|pid, _| active_pids.contains(pid));
        self.prev_cpu_times.retain(|pid, _| active_pids.contains(pid));
    }
}

/// System status aggregator
pub struct SystemStatus {
    pub backlight: Option<Backlight>,
    pub battery: Option<BatteryStatus>,
    pub wifi_enabled: bool,
    pub wifi_ssid: Option<String>,
    pub bluetooth_enabled: bool,
    pub dnd: DoNotDisturb,
    pub rotation_lock: RotationLock,
    pub process_stats: ProcessStatsCollector,
    pub volume: u8,
    pub muted: bool,
    /// When to hide the volume overlay (set when volume buttons pressed)
    pub volume_overlay_until: Option<std::time::Instant>,
    /// Haptic feedback controller
    pub vibrator: Option<Vibrator>,
    /// Phone call status
    pub phone: PhoneStatus,
    /// Last time we checked phone status
    phone_last_check: std::time::Instant,
}

impl SystemStatus {
    pub fn new() -> Self {
        let vibrator = Vibrator::new();
        if vibrator.is_some() {
            tracing::info!("Vibrator found and initialized");
        }
        Self {
            backlight: Backlight::new(),
            battery: BatteryStatus::read(),
            wifi_enabled: WifiManager::is_enabled(),
            wifi_ssid: WifiManager::current_connection(),
            bluetooth_enabled: BluetoothManager::is_enabled(),
            dnd: DoNotDisturb::new(),
            rotation_lock: RotationLock::new(),
            process_stats: ProcessStatsCollector::new(30), // 30 samples history
            volume: VolumeManager::get_volume(),
            muted: VolumeManager::is_muted(),
            volume_overlay_until: None,
            vibrator,
            phone: PhoneStatus::default(),
            phone_last_check: std::time::Instant::now(),
        }
    }

    /// Trigger haptic feedback (short tap)
    pub fn haptic_tap(&self) {
        if let Some(ref vib) = self.vibrator {
            vib.tap();
        }
    }

    /// Trigger haptic feedback (medium click)
    pub fn haptic_click(&self) {
        if let Some(ref vib) = self.vibrator {
            vib.click();
        }
    }

    /// Trigger haptic feedback (heavy)
    pub fn haptic_heavy(&self) {
        if let Some(ref vib) = self.vibrator {
            vib.heavy();
        }
    }

    /// Refresh all status values
    pub fn refresh(&mut self) {
        self.battery = BatteryStatus::read();
        self.wifi_enabled = WifiManager::is_enabled();
        self.wifi_ssid = WifiManager::current_connection();
        self.bluetooth_enabled = BluetoothManager::is_enabled();
        self.volume = VolumeManager::get_volume();
        self.muted = VolumeManager::is_muted();
    }

    /// Get brightness (0.0-1.0)
    pub fn get_brightness(&self) -> f32 {
        self.backlight.as_ref().map(|b| b.get()).unwrap_or(0.5)
    }

    /// Set brightness (0.0-1.0)
    pub fn set_brightness(&self, value: f32) {
        if let Some(ref backlight) = self.backlight {
            backlight.set(value);
        }
    }

    /// Get volume (0-100)
    pub fn get_volume(&self) -> u8 {
        self.volume
    }

    /// Set volume (0-100)
    pub fn set_volume(&mut self, value: u8) {
        VolumeManager::set_volume(value);
        self.volume = value.min(100);
    }

    /// Volume up by 5%
    pub fn volume_up(&mut self) {
        VolumeManager::volume_up();
        self.volume = VolumeManager::get_volume();
        self.show_volume_overlay();
    }

    /// Volume down by 5%
    pub fn volume_down(&mut self) {
        VolumeManager::volume_down();
        self.volume = VolumeManager::get_volume();
        self.show_volume_overlay();
    }

    /// Toggle mute
    pub fn toggle_mute(&mut self) {
        VolumeManager::toggle_mute();
        self.muted = !self.muted;
        self.show_volume_overlay();
    }

    /// Check if muted
    pub fn is_muted(&self) -> bool {
        self.muted
    }

    /// Show the volume overlay for 2 seconds
    pub fn show_volume_overlay(&mut self) {
        self.volume_overlay_until = Some(std::time::Instant::now() + std::time::Duration::from_secs(2));
    }

    /// Check if volume overlay should be visible
    pub fn should_show_volume_overlay(&self) -> bool {
        self.volume_overlay_until.map(|t| std::time::Instant::now() < t).unwrap_or(false)
    }

    /// Check phone status (rate limited to every 500ms)
    /// Returns true if there's a NEW incoming call (state just changed to incoming)
    pub fn check_phone(&mut self) -> bool {
        // Rate limit checks to every 500ms
        if self.phone_last_check.elapsed().as_millis() < 500 {
            return false;
        }
        self.phone_last_check = std::time::Instant::now();

        let old_state = self.phone.state.clone();
        self.phone = PhoneStatus::read();

        // Return true if we just got an incoming call
        old_state != "incoming" && self.phone.state == "incoming"
    }

    /// Check if there's currently an incoming call
    pub fn has_incoming_call(&self) -> bool {
        self.phone.is_incoming()
    }

    /// Check if there's an active call
    pub fn has_active_call(&self) -> bool {
        self.phone.is_active()
    }

    /// Get incoming call number
    pub fn incoming_call_number(&self) -> &str {
        &self.phone.number
    }

    /// Answer incoming call
    pub fn answer_call(&mut self) {
        PhoneStatus::answer();
        // Haptic feedback
        self.haptic_click();
    }

    /// Reject/hangup call
    pub fn reject_call(&mut self) {
        PhoneStatus::hangup();
        // Haptic feedback
        self.haptic_heavy();
    }

    /// Check for haptic feedback requests from apps (via /tmp/flick_haptic)
    /// Apps can write "tap", "click", or "heavy" to request haptic feedback
    pub fn check_app_haptic(&mut self) {
        const HAPTIC_FILE: &str = "/tmp/flick_haptic";
        if let Ok(content) = fs::read_to_string(HAPTIC_FILE) {
            let cmd = content.trim();
            if !cmd.is_empty() {
                match cmd {
                    "tap" => self.haptic_tap(),
                    "click" => self.haptic_click(),
                    "heavy" => self.haptic_heavy(),
                    _ => {
                        // Try to parse as duration in ms
                        if let Ok(ms) = cmd.parse::<u32>() {
                            if let Some(ref vib) = self.vibrator {
                                vib.vibrate(ms.min(100)); // Cap at 100ms for safety
                            }
                        }
                    }
                }
                // Clear the file after processing
                let _ = fs::write(HAPTIC_FILE, "");
            }
        }
    }
}

impl Default for SystemStatus {
    fn default() -> Self {
        Self::new()
    }
}
