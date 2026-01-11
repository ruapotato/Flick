pragma Singleton
import QtQuick 2.15
import FlickBackend 1.0

QtObject {
    id: theme

    // Accent color from config
    property color accentColor: Scaling.accentColor
    property color accentPressed: Qt.darker(accentColor, 1.2)

    // Use Scaling singleton for all scaled values
    readonly property real uiScale: Scaling.scaleFactor
    readonly property real textScale: Scaling.textScale

    // Scaled font sizes
    readonly property int fontTiny: Scaling.fontTiny
    readonly property int fontSmall: Scaling.fontSmall
    readonly property int fontNormal: Scaling.fontNormal
    readonly property int fontMedium: Scaling.fontMedium
    readonly property int fontLarge: Scaling.fontLarge
    readonly property int fontXLarge: Scaling.fontXLarge
    readonly property int fontXXLarge: Scaling.fontXXLarge
    readonly property int fontHuge: Scaling.fontHuge

    // Scaled spacing
    readonly property int spacingTiny: Scaling.spacingTiny
    readonly property int spacingSmall: Scaling.spacingSmall
    readonly property int spacingNormal: Scaling.spacingNormal
    readonly property int spacingLarge: Scaling.spacingLarge
    readonly property int spacingXLarge: Scaling.spacingXLarge

    // Scaled sizes
    readonly property int iconSmall: Scaling.iconSmall
    readonly property int iconNormal: Scaling.iconNormal
    readonly property int iconLarge: Scaling.iconLarge
    readonly property int iconXLarge: Scaling.iconXLarge

    readonly property int buttonHeight: Scaling.buttonHeight
    readonly property int buttonHeightSmall: Scaling.buttonHeightSmall
    readonly property int listItemHeight: Scaling.listItemHeight
    readonly property int headerHeight: Scaling.headerHeight

    // State directory and paths from Scaling
    readonly property string stateDir: Scaling.stateDir
    readonly property string configPath: stateDir + "/display_config.json"
    readonly property string homeDir: Scaling.homeDir

    // Helper functions
    function sp(pixels) { return Scaling.sp(pixels) }
    function tp(pixels) { return Scaling.tp(pixels) }
    function wp(percent) { return Scaling.wp(percent) }
    function hp(percent) { return Scaling.hp(percent) }

    // Initialize with screen size
    function init(width, height) {
        Scaling.init(width, height)
    }
}
