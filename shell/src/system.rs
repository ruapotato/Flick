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
        if let Some((uid, username)) = Self::get_audio_user() {
            // Set XDG_RUNTIME_DIR in the command itself since su doesn't pass env
            let pactl_cmd = format!("XDG_RUNTIME_DIR=/run/user/{} pactl {}", uid, args.join(" "));

            Command::new("su")
                .args([&username, "-c", &pactl_cmd])
                .output()
                .ok()
        } else {
            // Fallback to direct call (works if not running as root)
            Command::new("pactl")
                .args(args)
                .output()
                .ok()
        }
    }

    /// Run pactl command as the audio user (fire and forget)
    fn run_pactl_async(args: &[&str]) {
        if let Some((uid, username)) = Self::get_audio_user() {
            // Set XDG_RUNTIME_DIR in the command itself since su doesn't pass env
            let pactl_cmd = format!("XDG_RUNTIME_DIR=/run/user/{} pactl {}", uid, args.join(" "));

            tracing::info!("Running pactl as user {}: {:?}", username, args);
            let _ = Command::new("su")
                .args([&username, "-c", &pactl_cmd])
                .spawn();
        } else {
            tracing::info!("Running pactl directly: {:?}", args);
            let _ = Command::new("pactl")
                .args(args)
                .spawn();
        }
    }

    /// Get current volume (0-100)
    pub fn get_volume() -> u8 {
        Self::run_pactl(&["get-sink-volume", "@DEFAULT_SINK@"])
            .and_then(|o| {
                let output = String::from_utf8_lossy(&o.stdout);
                // Parse "Volume: front-left: 65536 / 100% / 0.00 dB, ..."
                output.split('/').nth(1)
                    .and_then(|s| s.trim().trim_end_matches('%').parse().ok())
            })
            .unwrap_or(50)
    }

    /// Set volume (0-100)
    pub fn set_volume(value: u8) {
        let clamped = value.min(100);
        Self::run_pactl_async(&["set-sink-volume", "@DEFAULT_SINK@", &format!("{}%", clamped)]);
    }

    /// Increase volume by 5%
    pub fn volume_up() {
        Self::run_pactl_async(&["set-sink-volume", "@DEFAULT_SINK@", "+5%"]);
    }

    /// Decrease volume by 5%
    pub fn volume_down() {
        Self::run_pactl_async(&["set-sink-volume", "@DEFAULT_SINK@", "-5%"]);
    }

    /// Check if muted
    pub fn is_muted() -> bool {
        Self::run_pactl(&["get-sink-mute", "@DEFAULT_SINK@"])
            .map(|o| String::from_utf8_lossy(&o.stdout).contains("yes"))
            .unwrap_or(false)
    }

    /// Set mute state
    pub fn set_mute(muted: bool) {
        let state = if muted { "1" } else { "0" };
        Self::run_pactl_async(&["set-sink-mute", "@DEFAULT_SINK@", state]);
    }

    /// Toggle mute
    pub fn toggle_mute() {
        Self::run_pactl_async(&["set-sink-mute", "@DEFAULT_SINK@", "toggle"]);
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

/// Rotation lock
pub struct RotationLock {
    pub locked: bool,
}

impl RotationLock {
    pub fn new() -> Self {
        Self { locked: false }
    }

    pub fn toggle(&mut self) {
        self.locked = !self.locked;
        // In a real implementation, this would prevent screen rotation
    }
}

/// Flashlight (if available via camera flash LED)
pub struct Flashlight;

impl Flashlight {
    /// Find flashlight LED path
    fn find_led() -> Option<String> {
        let leds_dir = "/sys/class/leds";
        if let Ok(entries) = fs::read_dir(leds_dir) {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_string();
                if name.contains("flash") || name.contains("torch") {
                    return Some(entry.path().to_string_lossy().to_string());
                }
            }
        }
        None
    }

    /// Check if flashlight is on
    pub fn is_on() -> bool {
        Self::find_led()
            .and_then(|path| fs::read_to_string(format!("{}/brightness", path)).ok())
            .map(|s| s.trim() != "0")
            .unwrap_or(false)
    }

    /// Toggle flashlight
    pub fn toggle() -> bool {
        if let Some(path) = Self::find_led() {
            let brightness = if Self::is_on() { "0" } else { "1" };
            fs::write(format!("{}/brightness", path), brightness).is_ok()
        } else {
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
}

impl SystemStatus {
    pub fn new() -> Self {
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
}

impl Default for SystemStatus {
    fn default() -> Self {
        Self::new()
    }
}
