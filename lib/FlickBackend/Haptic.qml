pragma Singleton
import QtQuick 2.15

QtObject {
    id: haptic

    // State directory for file-based IPC
    readonly property string stateDir: {
        var paths = [
            "/home/furios/.local/state/flick",
            "/home/droidian/.local/state/flick"
        ]
        for (var i = 0; i < paths.length; i++) {
            var xhr = new XMLHttpRequest()
            xhr.open("GET", "file://" + paths[i] + "/display_config.json", false)
            try {
                xhr.send()
                if ((xhr.status === 200 || xhr.status === 0) && xhr.responseText) {
                    return paths[i]
                }
            } catch (e) {}
        }
        return "/home/furios/.local/state/flick"
    }

    // Trigger a light tap haptic (for key presses, selections)
    // Duration: ~15ms
    function tap() {
        sendHaptic("tap")
    }

    // Trigger a medium click haptic (for confirms, toggles)
    // Duration: ~25ms
    function click() {
        sendHaptic("click")
    }

    // Trigger a heavy haptic (for important actions, errors)
    // Duration: ~50ms
    function heavy() {
        sendHaptic("heavy")
    }

    // Custom duration vibration in milliseconds (max 100ms)
    function vibrate(ms) {
        sendHaptic(String(Math.min(ms, 100)))
    }

    // Pattern vibration: array of [on_ms, off_ms, on_ms, ...]
    function pattern(durations) {
        if (durations.length === 0) return
        var patternStr = durations.map(function(d) { return Math.min(d, 100) }).join(",")
        sendHaptic("pattern:" + patternStr)
    }

    // Success feedback - double tap
    function success() {
        sendHaptic("success")
    }

    // Error feedback - long vibration
    function error() {
        sendHaptic("error")
    }

    // Internal function to send haptic command
    // Uses both console.log (for shell script capture) and file-based IPC
    function sendHaptic(cmd) {
        // Log for shell script capture (legacy support)
        console.log("HAPTIC:" + cmd)

        // File-based IPC for direct compositor control
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + stateDir + "/haptic_command")
        xhr.send(cmd + ":" + Date.now())
    }
}
