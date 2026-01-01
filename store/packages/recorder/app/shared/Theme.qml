pragma Singleton
import QtQuick 2.15

QtObject {
    id: theme

    // Default accent color (pink/red)
    property color accentColor: "#e94560"
    property color accentPressed: Qt.darker(accentColor, 1.2)

    // Config file path
    property string configPath: "/home/droidian/.local/state/flick/display_config.json"

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
