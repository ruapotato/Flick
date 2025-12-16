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
    // State dir from environment (set by run_lockscreen.sh) or fallback
    property string stateDir: {
        var envDir = Qt.getenv("FLICK_STATE_DIR")
        return envDir ? envDir : (Qt.getenv("HOME") + "/.local/state/flick")
    }

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
