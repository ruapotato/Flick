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
    property color accentColor: "#4a9eff"
    property color accentPressed: Qt.darker(accentColor, 1.2)
    property int baseFontSize: 8

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

    // Title bar with action buttons
    Rectangle {
        id: titleBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 36 * textScale
        color: "#1a1a2e"
        z: 1

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 8 * textScale
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * textScale

            // Copy button
            Rectangle {
                width: 56 * textScale
                height: 28 * textScale
                radius: 6 * textScale
                color: copyArea.pressed ? "#3a3a5e" : "#2a2a4e"

                Text {
                    anchors.centerIn: parent
                    text: "Copy"
                    color: "#aaccff"
                    font.pixelSize: 11 * textScale
                }

                MouseArea {
                    id: copyArea
                    anchors.fill: parent
                    onClicked: {
                        terminal.copyClipboard()
                        copiedPopup.show()
                    }
                }
            }

            // Paste button
            Rectangle {
                width: 56 * textScale
                height: 28 * textScale
                radius: 6 * textScale
                color: pasteArea.pressed ? "#3a3a5e" : "#2a2a4e"

                Text {
                    anchors.centerIn: parent
                    text: "Paste"
                    color: "#aaccff"
                    font.pixelSize: 11 * textScale
                }

                MouseArea {
                    id: pasteArea
                    anchors.fill: parent
                    onClicked: {
                        terminal.pasteClipboard()
                    }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: "Flick Terminal"
            color: "#aaaacc"
            font.pixelSize: 14 * textScale
            font.weight: Font.Medium
        }

        MouseArea {
            anchors.fill: parent
            anchors.leftMargin: 130 * textScale  // Don't overlap buttons
            onClicked: terminal.forceActiveFocus()
        }
    }

    // Copied popup
    Rectangle {
        id: copiedPopup
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: titleBar.bottom
        anchors.topMargin: 20 * textScale
        width: 100 * textScale
        height: 36 * textScale
        radius: 18 * textScale
        color: "#44aa44"
        opacity: 0
        z: 10

        Text {
            anchors.centerIn: parent
            text: "Copied!"
            color: "white"
            font.pixelSize: 14 * textScale
            font.weight: Font.Medium
        }

        function show() {
            opacity = 1
            hideTimer.restart()
        }

        Timer {
            id: hideTimer
            interval: 1500
            onTriggered: copiedPopup.opacity = 0
        }

        Behavior on opacity {
            NumberAnimation { duration: 200 }
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
