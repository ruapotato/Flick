pragma Singleton
import QtQuick 2.15

QtObject {
    id: theme

    // Default accent color (pink/red)
    property color accentColor: "#e94560"
    property color accentPressed: Qt.darker(accentColor, 1.2)

    // UI Scale - adjust based on screen width
    // 720px width = 1.0, 1080px width = 1.5
    readonly property real uiScale: 1.0  // For 720x1600 primary device

    // Text scale loaded from config or default for device
    property real textScale: 1.0  // Reduced from 2.0 for 720px width

    // Common font sizes (already scaled for 720px)
    readonly property int fontTiny: 10
    readonly property int fontSmall: 12
    readonly property int fontNormal: 14
    readonly property int fontMedium: 16
    readonly property int fontLarge: 18
    readonly property int fontXLarge: 22
    readonly property int fontXXLarge: 28
    readonly property int fontHuge: 36

    // Common spacing
    readonly property int spacingTiny: 4
    readonly property int spacingSmall: 8
    readonly property int spacingNormal: 12
    readonly property int spacingLarge: 16
    readonly property int spacingXLarge: 24

    // Common sizes
    readonly property int iconSmall: 20
    readonly property int iconNormal: 24
    readonly property int iconLarge: 32
    readonly property int iconXLarge: 48

    readonly property int buttonHeight: 44
    readonly property int buttonHeightSmall: 36
    readonly property int listItemHeight: 52
    readonly property int headerHeight: 56

    // Dynamic state directory from environment or fallback
    readonly property string stateDir: {
        // Check FLICK_STATE_DIR first (set by compositor)
        var envDir = Qt.application.arguments.indexOf("--state-dir")
        if (envDir >= 0 && envDir + 1 < Qt.application.arguments.length) {
            return Qt.application.arguments[envDir + 1]
        }
        // Try common locations - use GET instead of HEAD (HEAD not supported by QML XMLHttpRequest)
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
        // Default to furios (primary device)
        return "/home/furios/.local/state/flick"
    }

    // Config file path (derived from stateDir)
    readonly property string configPath: stateDir + "/display_config.json"

    // Home directory (derived from stateDir)
    readonly property string homeDir: stateDir.replace("/.local/state/flick", "")

    // Load config (accent color, text scale)
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
                if (config.text_scale && config.text_scale > 0) {
                    textScale = config.text_scale
                }
            }
        } catch (e) {
            console.log("Could not load theme config, using defaults")
        }
    }

    Component.onCompleted: loadConfig()
}
