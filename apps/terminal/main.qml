import QtQuick 2.15
import QtQuick.Window 2.15
import QMLTermWidget 1.0

Window {
    id: root
    visible: true
    width: 1080
    height: 2400
    title: "Flick Terminal"
    color: "#0a0a0f"

    // Settings from Flick config
    property real textScale: 2.0
    property int baseFontSize: 24

    Component.onCompleted: {
        loadConfig()
    }

    function loadConfig() {
        // Try to read config from standard location (uses droidian home)
        var configPath = "/home/droidian/.local/state/flick/display_config.json"
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + configPath, false)
        try {
            xhr.send()
            if (xhr.status === 200 || xhr.status === 0) {
                var config = JSON.parse(xhr.responseText)
                if (config.text_scale !== undefined) {
                    textScale = config.text_scale
                    console.log("Loaded text scale: " + textScale)
                    // Update terminal font
                    terminal.font.pixelSize = Math.round(baseFontSize * textScale)
                }
            }
        } catch (e) {
            console.log("Using default text scale: " + textScale)
        }
    }

    // Reload config periodically to pick up settings changes
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: loadConfig()
    }

    // Title bar
    Rectangle {
        id: titleBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 28 * textScale
        color: "#1a1a2e"
        z: 1

        Text {
            anchors.centerIn: parent
            text: "Flick Terminal"
            color: "#aaaacc"
            font.pixelSize: 14 * textScale
            font.weight: Font.Medium
        }

        MouseArea {
            anchors.fill: parent
            onClicked: terminal.forceActiveFocus()
        }
    }

    // Terminal widget
    QMLTermWidget {
        id: terminal
        anchors.top: titleBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 4

        font.family: "Monospace"
        font.pixelSize: Math.round(baseFontSize * textScale)

        colorScheme: "Linux"

        session: QMLTermSession {
            id: termSession
            initialWorkingDirectory: "/home/droidian"
            onFinished: Qt.quit()
        }

        Component.onCompleted: {
            termSession.startShellProgram()
            forceActiveFocus()
        }

        // Scrollbar
        QMLTermScrollbar {
            terminal: terminal
            width: 8 * textScale
            Rectangle {
                anchors.fill: parent
                color: "#444466"
                radius: width / 2
                opacity: 0.8
            }
        }
    }
}
