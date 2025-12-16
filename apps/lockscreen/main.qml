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
    // State dir - read from file created by run_lockscreen.sh wrapper
    // Using fixed path since Qt5 QML can't read env vars directly
    property string stateDir: "/home/droidian/.local/state/flick"

    // Try to read actual state dir from file on startup
    Component.onCompleted: {
        var xhr = new XMLHttpRequest()
        // Try user's home first
        var paths = [
            "/home/droidian/.local/state/flick/state_dir.txt",
            "/home/david/.local/state/flick/state_dir.txt",
            "/tmp/flick_state_dir.txt"
        ]
        for (var i = 0; i < paths.length; i++) {
            xhr.open("GET", "file://" + paths[i], false)
            try {
                xhr.send()
                if (xhr.status === 200 && xhr.responseText.trim()) {
                    stateDir = xhr.responseText.trim()
                    console.log("Read stateDir from file:", stateDir)
                    break
                }
            } catch(e) {}
        }
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
