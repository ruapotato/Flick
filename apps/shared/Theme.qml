pragma Singleton
import QtQuick 2.15

QtObject {
    id: theme

    // Default accent color (pink/red)
    property color accentColor: "#e94560"
    property color accentPressed: Qt.darker(accentColor, 1.2)

    // Dynamic state directory from environment or fallback
    readonly property string stateDir: {
        // Check FLICK_STATE_DIR first (set by compositor)
        var envDir = Qt.application.arguments.indexOf("--state-dir")
        if (envDir >= 0 && envDir + 1 < Qt.application.arguments.length) {
            return Qt.application.arguments[envDir + 1]
        }
        // Try common locations
        var paths = [
            "/home/furios/.local/state/flick",
            "/home/droidian/.local/state/flick"
        ]
        for (var i = 0; i < paths.length; i++) {
            var xhr = new XMLHttpRequest()
            xhr.open("HEAD", "file://" + paths[i] + "/display_config.json", false)
            try {
                xhr.send()
                if (xhr.status === 200 || xhr.status === 0) {
                    return paths[i]
                }
            } catch (e) {}
        }
        // Default to furios (primary device)
        return "/home/furios/.local/state/flick"
    }

    // Config file path (derived from stateDir)
    readonly property string configPath: stateDir + "/display_config.json"

    // Home directory (derived from stateDir)
    readonly property string homeDir: stateDir.replace("/.local/state/flick", "")

    // Load accent color from config
    function loadConfig() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + configPath, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                if (config.accent_color && config.accent_color !== "") {
                    accentColor = config.accent_color
                }
            }
        } catch (e) {
            console.log("Could not load theme config, using defaults")
        }
    }

    Component.onCompleted: loadConfig()
}
