import QtQuick 2.15
import QtQuick.Window 2.15

Window {
    id: root
    visible: true
    visibility: Window.FullScreen
    title: "Flick Lock Screen"
    color: "#0a0a0f"

    // Config
    property string correctPin: "1234"  // TODO: Load from config file
    property string stateDir: Qt.application.arguments[1] || (Qt.getenv("HOME") + "/.local/state/flick")

    LockScreen {
        anchors.fill: parent
        correctPin: root.correctPin
        stateDir: root.stateDir

        onUnlocked: {
            console.log("Unlocked! Writing signal file...")
            Qt.quit()
        }
    }
}
