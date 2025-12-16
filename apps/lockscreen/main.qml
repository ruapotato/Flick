import QtQuick 2.15
import QtQuick.Window 2.15

Window {
    id: root
    visible: true
    visibility: Window.FullScreen
    title: "Flick Lock Screen"
    color: "#ff0000"  // TEMP: Bright red for debugging

    // Config
    property string correctPin: "1234"  // TODO: Load from config file
    // State dir - hardcoded to standard location
    // The wrapper script ensures this dir exists
    property string stateDir: "/home/david/.local/state/flick"

    Component.onCompleted: {
        console.log("Lock screen started")
        console.log("stateDir:", stateDir)
    }

    LockScreen {
        anchors.fill: parent
        correctPin: root.correctPin
        stateDir: root.stateDir

        onUnlocked: {
            console.log("Unlocked! Quitting...")
            Qt.quit()
        }
    }
}
