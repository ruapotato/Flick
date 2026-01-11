pragma Singleton
import QtQuick 2.15

QtObject {
    id: scaling

    // Reference resolution (720x1600 - the primary device)
    readonly property real referenceWidth: 720
    readonly property real referenceHeight: 1600

    // Actual screen dimensions - set by app on startup
    property real screenWidth: 720
    property real screenHeight: 1600

    // Scale factor relative to reference resolution
    // This allows UI to look proportionally similar across different screens
    readonly property real scaleFactor: Math.min(screenWidth / referenceWidth, screenHeight / referenceHeight)

    // Horizontal and vertical scale factors (for non-uniform scaling if needed)
    readonly property real scaleX: screenWidth / referenceWidth
    readonly property real scaleY: screenHeight / referenceHeight

    // Text scale loaded from config
    property real textScale: 1.0

    // Dynamic state directory from environment or fallback
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

    // Home directory derived from stateDir
    readonly property string homeDir: stateDir.replace("/.local/state/flick", "")

    // Accent color from config
    property color accentColor: "#e94560"
    property color accentPressed: Qt.darker(accentColor, 1.2)

    // ============ SCALED FONT SIZES ============
    // Base sizes for 720px width reference, auto-scaled
    readonly property int fontTiny: Math.round(10 * scaleFactor * textScale)
    readonly property int fontSmall: Math.round(12 * scaleFactor * textScale)
    readonly property int fontNormal: Math.round(14 * scaleFactor * textScale)
    readonly property int fontMedium: Math.round(16 * scaleFactor * textScale)
    readonly property int fontLarge: Math.round(18 * scaleFactor * textScale)
    readonly property int fontXLarge: Math.round(22 * scaleFactor * textScale)
    readonly property int fontXXLarge: Math.round(28 * scaleFactor * textScale)
    readonly property int fontHuge: Math.round(36 * scaleFactor * textScale)

    // ============ SCALED SPACING ============
    readonly property int spacingTiny: Math.round(4 * scaleFactor)
    readonly property int spacingSmall: Math.round(8 * scaleFactor)
    readonly property int spacingNormal: Math.round(12 * scaleFactor)
    readonly property int spacingLarge: Math.round(16 * scaleFactor)
    readonly property int spacingXLarge: Math.round(24 * scaleFactor)

    // ============ SCALED ICON SIZES ============
    readonly property int iconSmall: Math.round(20 * scaleFactor)
    readonly property int iconNormal: Math.round(24 * scaleFactor)
    readonly property int iconLarge: Math.round(32 * scaleFactor)
    readonly property int iconXLarge: Math.round(48 * scaleFactor)

    // ============ SCALED COMPONENT SIZES ============
    readonly property int buttonHeight: Math.round(44 * scaleFactor)
    readonly property int buttonHeightSmall: Math.round(36 * scaleFactor)
    readonly property int listItemHeight: Math.round(52 * scaleFactor)
    readonly property int headerHeight: Math.round(56 * scaleFactor)
    readonly property int statusBarHeight: Math.round(32 * scaleFactor)

    // ============ SCALED RADII ============
    readonly property int radiusSmall: Math.round(8 * scaleFactor)
    readonly property int radiusNormal: Math.round(12 * scaleFactor)
    readonly property int radiusLarge: Math.round(16 * scaleFactor)
    readonly property int radiusXLarge: Math.round(24 * scaleFactor)

    // ============ HELPER FUNCTIONS ============

    // Scale a pixel value proportionally
    function sp(pixels) {
        return Math.round(pixels * scaleFactor)
    }

    // Scale a pixel value with text scale factor
    function tp(pixels) {
        return Math.round(pixels * scaleFactor * textScale)
    }

    // Scale width proportionally to screen width
    function wp(percent) {
        return Math.round(screenWidth * percent / 100)
    }

    // Scale height proportionally to screen height
    function hp(percent) {
        return Math.round(screenHeight * percent / 100)
    }

    // Initialize with screen dimensions
    function init(width, height) {
        screenWidth = width
        screenHeight = height
        loadConfig()
        console.log("Scaling initialized: " + width + "x" + height + " -> scaleFactor=" + scaleFactor.toFixed(2))
    }

    // Load config (accent color, text scale)
    function loadConfig() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + stateDir + "/display_config.json", false)
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
            console.log("Could not load display config, using defaults")
        }
    }

    Component.onCompleted: loadConfig()
}
