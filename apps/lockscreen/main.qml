import QtQuick 2.15
import QtQuick.Window 2.15

Window {
    id: root
    visible: true
    visibility: Window.FullScreen
    title: "Flick Lock Screen"
    color: wallpaperPath !== "" ? "transparent" : "#0a0a0f"

    // Config - loaded from JSON
    property string lockMethod: "pin"  // "pin", "pattern", "password", "none"
    property string correctPin: "1234"
    property var correctPattern: [0, 1, 2, 5, 8]  // Default pattern
    // State dir - use droidian home on phone, wrapper script sets this path
    property string stateDir: "/home/droidian/.local/state/flick"
    property string wallpaperPath: ""

    Component.onCompleted: {
        console.log("Lock screen started")
        console.log("stateDir:", stateDir)
        loadConfig()
        loadDisplayConfig()
    }

    function loadDisplayConfig() {
        var xhr = new XMLHttpRequest()
        var url = "file://" + stateDir + "/display_config.json"
        xhr.open("GET", url, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                if (config.wallpaper) {
                    wallpaperPath = config.wallpaper
                    console.log("Loaded wallpaper:", wallpaperPath)
                }
            }
        } catch (e) {
            console.log("Could not load display config")
        }
    }

    function loadConfig() {
        var xhr = new XMLHttpRequest()
        var url = "file://" + stateDir + "/lock_config.json"
        console.log("Loading lock config from:", url)
        xhr.open("GET", url)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        var config = JSON.parse(xhr.responseText)
                        console.log("Loaded lock config:", JSON.stringify(config))
                        lockMethod = config.method || "pin"
                        // For now, we use hardcoded credentials
                        // TODO: Implement proper IPC verification with compositor
                        console.log("Lock method:", lockMethod)
                    } catch (e) {
                        console.log("Failed to parse lock config:", e)
                    }
                } else {
                    console.log("Failed to load lock config, using defaults")
                }
            }
        }
        xhr.send()
    }

    // Wallpaper background
    Image {
        anchors.fill: parent
        source: wallpaperPath !== "" ? "file://" + wallpaperPath : ""
        fillMode: Image.PreserveAspectCrop
        visible: wallpaperPath !== ""
    }

    // Dark overlay for readability when wallpaper is set
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: wallpaperPath !== "" ? 0.4 : 0
    }

    LockScreen {
        anchors.fill: parent
        lockMethod: root.lockMethod
        correctPin: root.correctPin
        correctPattern: root.correctPattern
        stateDir: root.stateDir
        hasWallpaper: wallpaperPath !== ""

        onUnlocked: {
            console.log("Unlocked! Quitting...")
            Qt.quit()
        }
    }
}
